#!/usr/bin/env python3
"""Create a deterministic local APT repository from declared package inputs."""

from __future__ import annotations

import gzip
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
LOCAL_MANIFEST = ROOT / "packaging/debian/manifest.json"
VENDOR_MANIFEST = ROOT / "packaging/debian/vendor-manifest.json"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"create-repository: {message}")


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as error:
        fail(f"cannot read {path.relative_to(ROOT)}: {error}")
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        fail(f"unsupported manifest in {path.relative_to(ROOT)}")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def field(path: Path, name: str) -> str:
    result = subprocess.run(
        ["dpkg-deb", "--show", f"--showformat=${{{name}}}", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail(f"cannot read {name} from {path.name}: {result.stderr.strip()}")
    return result.stdout.strip()


def fetch_vendor(entry: dict[str, Any], cache: Path, legacy_cache: Path) -> Path:
    destination = cache / entry["file"]
    if destination.is_file() and sha256_file(destination) == entry["sha256"]:
        return destination
    destination.unlink(missing_ok=True)
    legacy = legacy_cache / entry["file"]
    if legacy.is_file() and sha256_file(legacy) == entry["sha256"]:
        shutil.copy2(legacy, destination)
        return destination
    errors: list[str] = []
    for url in entry["urls"]:
        temporary = destination.with_suffix(".deb.part")
        temporary.unlink(missing_ok=True)
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
        except (OSError, urllib.error.URLError) as error:
            errors.append(f"{url}: {error}")
            temporary.unlink(missing_ok=True)
            continue
        if sha256_file(temporary) != entry["sha256"]:
            errors.append(f"{url}: SHA-256 mismatch")
            temporary.unlink()
            continue
        temporary.replace(destination)
        return destination
    fail(f"could not fetch checksum-verified {entry['file']}:\n  " + "\n  ".join(errors))


def validate_vendor_manifest(value: dict[str, Any]) -> list[dict[str, Any]]:
    packages = value.get("packages")
    if not isinstance(packages, list):
        fail("vendor packages must be an array")
    required = {
        "file",
        "package",
        "version",
        "architecture",
        "sha256",
        "configs",
        "urls",
        "install",
    }
    files: set[str] = set()
    tuples: set[tuple[str, str, str]] = set()
    for entry in packages:
        if not isinstance(entry, dict) or not required.issubset(entry):
            fail(f"invalid vendor entry: {entry!r}")
        if entry["file"] in files:
            fail(f"duplicate vendor filename {entry['file']}")
        files.add(entry["file"])
        key = (entry["package"], entry["version"], entry["architecture"])
        if key in tuples:
            fail(f"duplicate vendor package tuple {key}")
        tuples.add(key)
        if not entry["install"] and not entry.get("quarantine_reason"):
            fail(f"quarantined vendor package {entry['file']} lacks a reason")
        if not isinstance(entry["urls"], list) or not entry["urls"]:
            fail(f"vendor package {entry['file']} has no explicit URL")
        if len(entry["sha256"]) != 64:
            fail(f"vendor package {entry['file']} has an invalid SHA-256")
    return packages


def validate_local_inputs(
    conf: str, local_definition: dict[str, Any], build_manifest: dict[str, Any], packages_dir: Path
) -> tuple[list[dict[str, str]], list[str]]:
    selected = [entry for entry in local_definition.get("packages", []) if conf in entry.get("configs", [])]
    if len(selected) != 1:
        fail(f"expected one local source package for {conf}")
    entry = selected[0]
    if build_manifest.get("conf") != conf or build_manifest.get("source_name") != entry["source_name"]:
        fail("build manifest does not match selected configuration and source package")
    declared = {binary["name"]: binary["architecture"] for binary in entry["binary_packages"]}
    artifacts = build_manifest.get("artifacts", [])
    actual_files = {path.name for path in packages_dir.glob("*.deb")}
    manifest_files = {artifact.get("file") for artifact in artifacts}
    if actual_files != manifest_files:
        fail("local package directory contains stale or undeclared .deb files")
    found: set[str] = set()
    validated: list[dict[str, str]] = []
    for artifact in artifacts:
        path = packages_dir / artifact["file"]
        if not path.is_file() or sha256_file(path) != artifact["sha256"]:
            fail(f"local artifact hash mismatch: {artifact['file']}")
        package = field(path, "Package")
        version = field(path, "Version")
        architecture = field(path, "Architecture")
        if package not in declared or architecture != declared[package]:
            fail(f"undeclared local package metadata in {artifact['file']}")
        if version != build_manifest["version"] or package in found:
            fail(f"duplicate or wrong-version local package {artifact['file']}")
        found.add(package)
        validated.append(
            {
                "package": package,
                "version": version,
                "architecture": architecture,
                "file": path.name,
                "sha256": artifact["sha256"],
                "provenance": "local",
                "source_revision": build_manifest["source_revision"],
            }
        )
    if found != set(declared):
        fail(f"missing declared local packages: {sorted(set(declared) - found)}")
    return validated, list(entry["install_packages"])


def main() -> None:
    conf = os.environ.get("CONF", "")
    if not conf:
        fail("CONF is required")
    output = ROOT / "output" / conf
    local_output = output / "debian"
    packages_dir = local_output / "packages"
    build_manifest_path = local_output / "build-manifest.json"
    if not build_manifest_path.is_file():
        fail("local build manifest is missing; run debian-packages first")
    local_definition = load_json(LOCAL_MANIFEST)
    vendor_definition = load_json(VENDOR_MANIFEST)
    vendors = validate_vendor_manifest(vendor_definition)
    build_manifest = load_json(build_manifest_path)
    local_packages, install_packages = validate_local_inputs(
        conf, local_definition, build_manifest, packages_dir
    )

    vendor_cache = output / "vendor-debs"
    vendor_cache.mkdir(parents=True, exist_ok=True)
    legacy_cache = output / "images/deb"
    repository = local_output / "repository"
    repository.parent.mkdir(parents=True, exist_ok=True)
    validated_vendors: list[dict[str, str]] = []
    quarantined: list[dict[str, str]] = []
    selected_vendors = [entry for entry in vendors if conf in entry["configs"]]
    for entry in selected_vendors:
        path = fetch_vendor(entry, vendor_cache, legacy_cache)
        if sha256_file(path) != entry["sha256"]:
            fail(f"vendor artifact hash mismatch: {entry['file']}")
        metadata = {
            "package": field(path, "Package"),
            "version": field(path, "Version"),
            "architecture": field(path, "Architecture"),
        }
        for name in metadata:
            if metadata[name] != entry[name]:
                fail(f"vendor {entry['file']} {name} is {metadata[name]!r}, expected {entry[name]!r}")
        dependency = field(path, "Depends")
        record = {
            **metadata,
            "file": entry["file"],
            "sha256": entry["sha256"],
            "depends": dependency,
            "provenance": "vendor",
            "url": entry["urls"][0],
        }
        if entry["install"]:
            validated_vendors.append(record)
            install_packages.append(entry["package"])
        else:
            quarantined.append(
                {
                    **record,
                    "reason": entry["quarantine_reason"],
                }
            )

    tuples: set[tuple[str, str, str]] = set()
    for package in local_packages + validated_vendors:
        key = (package["package"], package["version"], package["architecture"])
        if key in tuples:
            fail(f"duplicate repository package tuple {key}")
        tuples.add(key)

    with tempfile.TemporaryDirectory(prefix="repository.", dir=local_output) as temporary_name:
        temporary = Path(temporary_name)
        for package in local_packages:
            shutil.copy2(packages_dir / package["file"], temporary / package["file"])
        for package in validated_vendors:
            shutil.copy2(vendor_cache / package["file"], temporary / package["file"])
        packages_index = temporary / "Packages"
        with packages_index.open("w") as output_stream:
            result = subprocess.run(
                ["dpkg-scanpackages", ".", "/dev/null"],
                cwd=temporary,
                text=True,
                stdout=output_stream,
                stderr=subprocess.PIPE,
                check=False,
            )
        if result.returncode != 0:
            fail(f"dpkg-scanpackages failed: {result.stderr.strip()}")
        with packages_index.open("rb") as source, gzip.GzipFile(
            filename="", mode="wb", fileobj=(temporary / "Packages.gz").open("wb"), mtime=0
        ) as compressed:
            shutil.copyfileobj(source, compressed)
        repository_manifest = {
            "schema_version": 1,
            "conf": conf,
            "kernel_release": build_manifest["kernel_release"],
            "build_key": build_manifest["build_key"],
            "install_packages": install_packages,
            "packages": local_packages + validated_vendors,
            "quarantined_packages": quarantined,
            "trusted_local_only": True,
        }
        (temporary / "repository-manifest.json").write_text(
            json.dumps(repository_manifest, indent=2, sort_keys=True) + "\n"
        )
        shutil.rmtree(repository, ignore_errors=True)
        temporary.replace(repository)
    print(f"repository: {repository.relative_to(ROOT)} ({len(local_packages) + len(validated_vendors)} packages)")


if __name__ == "__main__":
    main()
