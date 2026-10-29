#!/usr/bin/env bash
set -euo pipefail

conf=k230_canmv_01studio_defconfig
if [[ "${CONF-}" != "$conf" ]]; then
    echo "Set CONF=$conf to initialize this SDK image" >&2
    exit 2
fi
if [[ ! -d /src || ! -w /src ]]; then
    echo '/src must be a writable workspace bind mount' >&2
    exit 1
fi
# Check *both* destinations, including broken symlinks, before any mutation.
if [[ -e /src/output || -L /src/output || -e /src/dl || -L /src/dl ]]; then
    echo 'Refusing to replace an existing /src/output or /src/dl' >&2
    exit 1
fi

seed=/opt/k230-sdk
[[ -d "$seed/output/$conf/host" && -d "$seed/output/buildroot-2025.02.1" && -d "$seed/dl" && -f "$seed/debian13.tar.gz" ]] || {
    echo 'Incomplete host SDK image seed' >&2
    exit 1
}
# Preserve symlinks (including Buildroot's absolute /src staging link), modes
# and timestamps. CI restores workspace ownership after the container steps.
cp -a --no-preserve=ownership -- "$seed/output" /src/output
cp -a --no-preserve=ownership -- "$seed/dl" /src/dl
cp -p --no-preserve=ownership -- "$seed/debian13.tar.gz" \
    "/src/output/$conf/images/debian13.tar.gz"
