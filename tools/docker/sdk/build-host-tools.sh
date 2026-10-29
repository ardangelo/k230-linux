#!/usr/bin/env bash
set -euo pipefail

conf=k230_canmv_01studio_defconfig
[[ "${CONF-}" == "$conf" ]] || {
    echo "Only CONF=$conf is supported" >&2
    exit 2
}
cd /src

# Configure from this checkout, not from any pre-existing output tree. This
# invokes the ordinary Buildroot source download and overlay sync machinery.
[[ ! -e output && ! -L output ]] || {
    echo 'The SDK build context must not contain output/' >&2
    exit 1
}
make "CONF=$conf" "$conf"
make "CONF=$conf" dl

output="/src/output/$conf"
info=$(mktemp)
packages=$(mktemp)
trap 'rm -f -- "$info" "$packages"' EXIT
make -s --no-print-directory -C "$output" show-info > "$info"

# show-info is Buildroot's complete selected package/rootfs dependency graph.
# Virtual host packages must be built as well as ordinary host packages.
python3 - "$info" "$packages" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    graph = json.load(f)
hosts = sorted(name for name, meta in graph.items() if meta.get('type') == 'host')
if not hosts:
    raise SystemExit('Buildroot returned no host packages')
for name in hosts:
    if not re.fullmatch(r'host-[a-zA-Z0-9_.+-]+', name):
        raise SystemExit(f'Unexpected host package name: {name!r}')
    for dependency in graph[name]['dependencies']:
        if dependency not in graph or graph[dependency].get('type') != 'host':
            raise SystemExit(f'Host package {name} depends on a non-host package: {dependency}')
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('\n'.join(hosts) + '\n')
print(f'Building {len(hosts)} Buildroot host packages (including virtual packages)')
PY
mapfile -t host_packages < "$packages"
make -C "$output" "${host_packages[@]}"

# Do not conceal accidental target compilation by merely deleting its build
# tree: reject any configured/built/installed non-host package first. A normal
# source prefetch may leave source-only non-host directories here.
python3 - "$output" "$info" <<'PY'
import json
from pathlib import Path
import sys

output = Path(sys.argv[1])
with open(sys.argv[2], encoding='utf-8') as f:
    graph = json.load(f)
build = output / 'build'
for directory in build.iterdir():
    if not directory.is_dir() or directory.name.startswith('host-') or directory.name == 'buildroot-config':
        continue
    for stamp in directory.rglob('.stamp_*'):
        if stamp.name in {'.stamp_configured', '.stamp_built', '.stamp_installed'} or stamp.name.endswith('_installed'):
            raise SystemExit(f'Unexpected target compilation/install stamp: {stamp}')
for name, meta in graph.items():
    if meta.get('type') != 'host':
        continue
    stamp_dir = meta.get('stamp_dir', '')
    if not stamp_dir.startswith('build/host-') or '..' in Path(stamp_dir).parts:
        raise SystemExit(f'Unexpected host stamp directory for {name}: {stamp_dir!r}')
    if not (output / stamp_dir / '.stamp_host_installed').is_file():
        raise SystemExit(f'Missing host installation stamp: {name}')
for dirname in ('target', 'images'):
    path = output / dirname
    if path.is_dir() and any(path.iterdir()):
        raise SystemExit(f'Unexpected target/image files in {path}')
host = output / 'host'
if not host.is_dir():
    raise SystemExit('Missing installed host tools')
for sysroot in host.glob('*/sysroot'):
    if sysroot.is_dir() and any(p.is_file() or p.is_symlink() for p in sysroot.rglob('*')):
        raise SystemExit(f'Unexpected target staging files in {sysroot}')
PY

# Preserve the configured Buildroot source, host build/stamp trees, installed
# host tools and dl/. Nothing from a target build or image is seeded.
find "$output/build" -mindepth 1 -maxdepth 1 ! -name 'host-*' \
    ! -name 'buildroot-config' -exec rm -rf -- {} +
rm -rf -- "$output/target" "$output/images"
mkdir -p -- "$output/images"
