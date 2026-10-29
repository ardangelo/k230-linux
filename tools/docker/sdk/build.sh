#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s IMAGE_TAG DL_DIR DEBIAN_BASE\n' "$0" >&2
    exit 2
}

[[ $# -eq 3 ]] || usage
image_tag=$1
[[ "$image_tag" == *:2025.02.1-canmv-01studio-hosts-1 ]] || {
    echo 'IMAGE_TAG must end in :2025.02.1-canmv-01studio-hosts-1' >&2
    exit 2
}
[[ -d "$2" && -f "$3" ]] || usage
sdk_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
dl_dir=$(realpath -e -- "$2")
debian_base=$(realpath -e -- "$3")
[[ -f "$sdk_root/Makefile" && -d "$sdk_root/buildroot-overlay/package/sharp-drm/module/src" ]] || {
    echo 'SDK Makefile or initialized sharp-drm submodule is missing' >&2
    exit 1
}
printf '%s  %s\n' c958b36f56d5e2a88446b03bb7dc6557 "$debian_base" | md5sum -c -

# Only this disposable directory is ever removed. Never read the checkout's
# output/ or use it as a Docker build input.
context=$(mktemp -d "${TMPDIR:-/tmp}/k230-sdk-build.XXXXXXXX")
trap 'rm -rf -- "$context"' EXIT
mkdir -p -- "$context/sdk-source"
tar -C "$sdk_root" --exclude='.git' --exclude='*/.git' \
    --exclude='tools/docker/buildroot/*.tar.gz' \
    -cf - Makefile tools buildroot-overlay | tar -C "$context/sdk-source" -xf -
cp -a --reflink=auto -- "$dl_dir" "$context/dl"
cp -p --reflink=auto -- "$debian_base" "$context/debian13.tar.gz"

docker build --build-arg "BASE_IMAGE=${BASE_IMAGE:-k230-buildroot:latest}" \
    -f "$context/sdk-source/tools/docker/sdk/Dockerfile" \
    -t "$image_tag" "$context"
