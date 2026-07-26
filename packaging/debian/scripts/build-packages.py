#!/usr/bin/env python3
"""Build declared K230 Debian packages from clean canonical-source staging trees."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = ROOT / "packaging/debian/manifest.json"
EXCLUDED_NAMES = {
    ".git",
    ".claude",
    ".cache",
    "debian",
}
EXCLUDED_SUFFIXES = {
    ".o",
    ".ko",
    ".mod",
    ".mod.c",
    ".cmd",
    ".a",
}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"build-packages: {message}")


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture: bool = True,
) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            check=True,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except FileNotFoundError:
        fail(f"required command is unavailable: {command[0]}")
    except subprocess.CalledProcessError as error:
        output = "\n".join(part for part in (error.stdout, error.stderr) if part)
        fail(f"command failed ({' '.join(command)}):\n{output.rstrip()}")
    return result.stdout.strip() if capture else ""


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        fail(f"missing {path.relative_to(ROOT)}")
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {path.relative_to(ROOT)}: {error}")
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_tree(path: Path) -> str:
    digest = hashlib.sha256()
    for item in sorted(path.rglob("*")):
        relative = item.relative_to(path)
        if any(part in EXCLUDED_NAMES for part in relative.parts):
            continue
        if item.is_dir() or should_exclude(item.name):
            continue
        digest.update(str(relative).encode())
        digest.update(b"\0")
        if item.is_symlink():
            digest.update(os.readlink(item).encode())
        else:
            digest.update(item.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def should_exclude(name: str) -> bool:
    if name in EXCLUDED_NAMES or name.startswith(".tmp_versions"):
        return True
    if name in {"Module.symvers", "modules.order"}:
        return True
    return any(name.endswith(suffix) for suffix in EXCLUDED_SUFFIXES)


def copy_source(source: Path, destination: Path) -> None:
    def ignore(_directory: str, names: list[str]) -> set[str]:
        return {name for name in names if should_exclude(name)}

    shutil.copytree(source, destination, symlinks=True, ignore=ignore)


def validate_manifest(value: dict[str, Any]) -> list[dict[str, Any]]:
    if value.get("schema_version") != 1:
        fail("manifest schema_version must be 1")
    packages = value.get("packages")
    if not isinstance(packages, list) or not packages:
        fail("manifest packages must be a non-empty array")
    required = {
        "source_name",
        "upstream_version",
        "canonical_source",
        "packaging",
        "configs",
        "requires_kernel",
        "build_order",
        "binary_packages",
        "install_packages",
    }
    names: set[str] = set()
    for entry in packages:
        if not isinstance(entry, dict) or not required.issubset(entry):
            fail(f"manifest package entry lacks required keys: {entry!r}")
        if entry["source_name"] in names:
            fail(f"duplicate source package {entry['source_name']}")
        names.add(entry["source_name"])
        binaries = entry["binary_packages"]
        if not isinstance(binaries, list) or not binaries:
            fail(f"{entry['source_name']} has no declared binary packages")
        binary_names = {binary.get("name") for binary in binaries if isinstance(binary, dict)}
        if len(binary_names) != len(binaries) or None in binary_names:
            fail(f"{entry['source_name']} has invalid or duplicate binary packages")
        if not set(entry["install_packages"]).issubset(binary_names):
            fail(f"{entry['source_name']} installs an undeclared binary package")
    return sorted(packages, key=lambda entry: entry["build_order"])


def read_buildroot_value(config: Path, key: str) -> str:
    pattern = re.compile(rf"^{re.escape(key)}=(?:\"(.*)\"|(.*))$")
    for line in config.read_text().splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1) if match.group(1) is not None else match.group(2)
    fail(f"{key} is not set in {config.relative_to(ROOT)}")


def resolve_context(conf: str) -> dict[str, Any]:
    defconfig = ROOT / "buildroot-overlay/configs" / conf
    output = ROOT / "output" / conf
    config = output / ".config"
    if not re.fullmatch(r"[A-Za-z0-9_.+-]+_defconfig", conf):
        fail(f"invalid CONF value: {conf!r}")
    if not defconfig.is_file():
        fail(f"selected defconfig does not exist: {defconfig.relative_to(ROOT)}")
    if not config.is_file():
        fail(f"prepared configuration is missing: {config.relative_to(ROOT)}")
    selected = Path(read_buildroot_value(config, "BR2_DEFCONFIG")).name
    if selected != conf:
        fail(f"prepared configuration selects {selected}, not requested {conf}")

    printvars = run(
        ["make", "-s", "-C", str(output), "printvars", "VARS=LINUX_DIR"],
        cwd=ROOT,
    )
    matches = re.findall(r"^LINUX_DIR=(.+)$", printvars, re.MULTILINE)
    if len(matches) != 1:
        fail("could not resolve one LINUX_DIR from the selected Buildroot output")
    kernel_dir = Path(matches[0]).resolve()
    required_kernel = [
        kernel_dir / ".config",
        kernel_dir / "include/config/auto.conf",
        kernel_dir / "include/generated/utsrelease.h",
        kernel_dir / "scripts/mod/modpost",
        kernel_dir / "Module.symvers",
    ]
    missing = [str(path) for path in required_kernel if not path.is_file()]
    if missing:
        fail("prepared kernel tree is incomplete; run linux-rebuild first:\n  " + "\n  ".join(missing))

    toolchain_path = Path(read_buildroot_value(config, "BR2_TOOLCHAIN_EXTERNAL_PATH"))
    toolchain_prefix = read_buildroot_value(config, "BR2_TOOLCHAIN_EXTERNAL_PREFIX")
    cross_compile = str(toolchain_path / "bin" / f"{toolchain_prefix}-")
    compiler = Path(f"{cross_compile}gcc")
    if not compiler.is_file():
        fail(f"configured cross-compiler is unavailable: {compiler}")
    kernel_release = run(
        [
            "make",
            "-s",
            "-C",
            str(kernel_dir),
            "ARCH=riscv",
            f"CROSS_COMPILE={cross_compile}",
            "kernelrelease",
        ]
    )
    if not re.fullmatch(r"[A-Za-z0-9._+-]+", kernel_release):
        fail(f"invalid kernel release reported by Kbuild: {kernel_release!r}")
    compiler_identity = run([str(compiler), "--version"]).splitlines()[0]
    return {
        "conf": conf,
        "defconfig": str(defconfig.relative_to(ROOT)),
        "output": output,
        "config": config,
        "kernel_dir": kernel_dir,
        "kernel_release": kernel_release,
        "kernel_config_sha256": sha256_file(kernel_dir / ".config"),
        "module_symvers_sha256": sha256_file(kernel_dir / "Module.symvers"),
        "cross_compile": cross_compile,
        "compiler_identity": compiler_identity,
    }


def source_state(source: Path) -> dict[str, Any]:
    revision = run(["git", "-C", str(source), "rev-parse", "HEAD"])
    status = run(
        ["git", "-C", str(source), "status", "--porcelain", "--untracked-files=all"]
    )
    dirty = bool(status)
    if dirty and os.environ.get("RELEASE") == "1":
        fail(f"release build rejects dirty canonical source {source.relative_to(ROOT)}:\n{status}")
    try:
        epoch = int(run(["git", "-C", str(source), "show", "-s", "--format=%ct", "HEAD"]))
    except ValueError:
        fail(f"invalid commit timestamp for {source.relative_to(ROOT)}")
    return {
        "revision": revision,
        "dirty": dirty,
        "status": status.splitlines(),
        "content_sha256": sha256_tree(source),
        "source_date_epoch": epoch,
    }


def debian_version(upstream: str, state: dict[str, Any], kernel_release: str) -> str:
    release = re.sub(r"[^A-Za-z0-9.+~]", ".", kernel_release)
    version = f"{upstream}+git{state['revision'][:12]}"
    if state["dirty"]:
        version += f"+dirty.{state['content_sha256'][:12]}"
    return f"{version}-1+k230.{release}"


def replace_generated_metadata(source: Path, version: str, kernel_release: str) -> None:
    changelog = source / "debian/changelog"
    text = changelog.read_text()
    text, count = re.subn(r"^(sharp-drm \()[^)]+(\))", rf"\g<1>{version}\2", text, count=1)
    if count != 1:
        fail("could not set generated version in staged debian/changelog")
    changelog.write_text(text)
    for name in ("k230-sharp-drm.postinst", "k230-sharp-drm.postrm"):
        script = source / "debian" / name
        updated = script.read_text().replace("@KERNEL_RELEASE@", kernel_release)
        if "@KERNEL_RELEASE@" in updated:
            fail(f"failed to substitute kernel release in {name}")
        script.write_text(updated)


def build_key(
    entry: dict[str, Any],
    state: dict[str, Any],
    metadata_sha256: str,
    context: dict[str, Any],
    version: str,
) -> str:
    inputs = {
        "schema_version": 1,
        "source_name": entry["source_name"],
        "source_revision": state["revision"],
        "source_dirty": state["dirty"],
        "source_content_sha256": state["content_sha256"],
        "packaging_sha256": metadata_sha256,
        "version": version,
        "conf": context["conf"],
        "kernel_release": context["kernel_release"],
        "kernel_config_sha256": context["kernel_config_sha256"],
        "module_symvers_sha256": context["module_symvers_sha256"],
        "cross_compile": context["cross_compile"],
        "compiler_identity": context["compiler_identity"],
    }
    encoded = json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def existing_build_is_current(
    manifest_path: Path, expected_key: str, packages_dir: Path
) -> bool:
    if not manifest_path.is_file():
        return False
    try:
        manifest = json.loads(manifest_path.read_text())
    except json.JSONDecodeError:
        return False
    if manifest.get("build_key") != expected_key:
        return False
    artifacts = manifest.get("artifacts", [])
    if not artifacts:
        return False
    declared = {artifact.get("file") for artifact in artifacts}
    actual = {path.name for path in packages_dir.glob("*.deb")}
    if declared != actual:
        return False
    return all(
        (packages_dir / artifact["file"]).is_file()
        and sha256_file(packages_dir / artifact["file"]) == artifact.get("sha256")
        for artifact in artifacts
    )


def build_package(
    entry: dict[str, Any], context: dict[str, Any], output_root: Path
) -> dict[str, Any]:
    source = ROOT / entry["canonical_source"]
    metadata = ROOT / entry["packaging"]
    if not source.is_dir() or not metadata.is_dir():
        fail(f"missing source or metadata for {entry['source_name']}")
    if context["conf"] not in entry["configs"]:
        fail(f"{entry['source_name']} is not enabled for {context['conf']}")
    if not entry["requires_kernel"]:
        fail(f"{entry['source_name']} unexpectedly lacks a kernel requirement")

    state = source_state(source)
    metadata_sha256 = sha256_tree(metadata)
    version = debian_version(entry["upstream_version"], state, context["kernel_release"])
    key = build_key(entry, state, metadata_sha256, context, version)
    packages_dir = output_root / "packages"
    build_manifest_path = output_root / "build-manifest.json"
    if existing_build_is_current(build_manifest_path, key, packages_dir):
        print(f"{entry['source_name']}: build inputs unchanged ({key[:12]}); reusing declared artifacts")
        return load_json(build_manifest_path)

    shutil.rmtree(output_root / "build", ignore_errors=True)
    shutil.rmtree(packages_dir, ignore_errors=True)
    work = output_root / "build" / f"{entry['source_name']}-{version}"
    staged = work / f"{entry['source_name']}-{entry['upstream_version']}"
    packages_dir.mkdir(parents=True, exist_ok=True)
    (output_root / "logs").mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True)
    copy_source(source, staged)
    shutil.copytree(metadata, staged / "debian")
    replace_generated_metadata(staged, version, context["kernel_release"])

    command = ["dpkg-buildpackage", "--build=binary", "--unsigned-source", "--unsigned-changes", "--host-arch=riscv64"]
    environment = os.environ.copy()
    environment.update(
        {
            "K230_KERNEL_DIR": str(context["kernel_dir"]),
            "K230_KERNEL_RELEASE": context["kernel_release"],
            "K230_CROSS_COMPILE": context["cross_compile"],
            "SOURCE_DATE_EPOCH": str(state["source_date_epoch"]),
            "DEB_BUILD_OPTIONS": "nocheck",
        }
    )
    log_path = output_root / "logs" / f"{entry['source_name']}.log"
    with log_path.open("w") as log:
        try:
            subprocess.run(
                command,
                cwd=staged,
                env=environment,
                check=True,
                text=True,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        except FileNotFoundError:
            fail("dpkg-buildpackage is unavailable; rebuild the k230-debian image")
        except subprocess.CalledProcessError:
            fail(f"package build failed; inspect {log_path.relative_to(ROOT)}")

    produced = sorted(work.glob("*.deb"))
    expected = {binary["name"]: binary["architecture"] for binary in entry["binary_packages"]}
    artifacts: list[dict[str, str]] = []
    seen: set[str] = set()
    for package_path in produced:
        fields = run(
            ["dpkg-deb", "-f", str(package_path), "Package", "Version", "Architecture"]
        ).splitlines()
        if len(fields) != 3:
            fail(f"could not inspect declared output {package_path.name}")
        package_name, package_version, architecture = fields
        if package_name not in expected:
            fail(f"undeclared binary package output: {package_path.name} ({package_name})")
        if package_name in seen:
            fail(f"duplicate binary output for {package_name}")
        if architecture != expected[package_name] or package_version != version:
            fail(f"unexpected metadata in {package_path.name}: {fields}")
        seen.add(package_name)
        destination = packages_dir / package_path.name
        shutil.copy2(package_path, destination)
        artifacts.append(
            {
                "package": package_name,
                "version": package_version,
                "architecture": architecture,
                "file": destination.name,
                "sha256": sha256_file(destination),
            }
        )
    if seen != set(expected):
        fail(f"declared outputs missing: {sorted(set(expected) - seen)}")
    undeclared = [path.name for path in work.glob("*.deb") if path.name not in {item.name for item in produced}]
    if undeclared:
        fail(f"undeclared .deb outputs appeared: {undeclared}")

    manifest = {
        "schema_version": 1,
        "source_name": entry["source_name"],
        "source_path": entry["canonical_source"],
        "source_revision": state["revision"],
        "source_dirty": state["dirty"],
        "source_status": state["status"],
        "source_content_sha256": state["content_sha256"],
        "packaging_path": entry["packaging"],
        "packaging_sha256": metadata_sha256,
        "version": version,
        "conf": context["conf"],
        "defconfig": context["defconfig"],
        "kernel_release": context["kernel_release"],
        "kernel_dir": str(context["kernel_dir"]),
        "kernel_config_sha256": context["kernel_config_sha256"],
        "module_symvers_sha256": context["module_symvers_sha256"],
        "cross_compile": context["cross_compile"],
        "compiler_identity": context["compiler_identity"],
        "build_command": command,
        "build_key": key,
        "artifacts": artifacts,
    }
    build_manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    conf = os.environ.get("CONF", "")
    if not conf:
        fail("CONF is required")
    packages = validate_manifest(load_json(MANIFEST_PATH))
    enabled = [entry for entry in packages if conf in entry["configs"]]
    if not enabled:
        fail(f"manifest selects no local packages for {conf}")
    if len(enabled) != 1:
        fail("the current builder requires one source package per configuration")
    context = resolve_context(conf)
    output_root = ROOT / "output" / conf / "debian"
    output_root.mkdir(parents=True, exist_ok=True)
    build_package(enabled[0], context, output_root)


if __name__ == "__main__":
    main()
