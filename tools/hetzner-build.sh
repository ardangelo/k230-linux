#!/bin/bash
# Build the Cyberdeck SD card images (sysimage-sdcard.img.gz and debian.img.gz) on a rented
# Hetzner Cloud server, copy them back, and always delete the server afterwards, also on failure
# or Ctrl-C.
#
# Usage: tools/hetzner-build.sh [server-type] [location]      e.g. tools/hetzner-build.sh ccx63 hel1
#
# Needs the hcloud CLI with an active context, and an SSH key registered in that Hetzner project:
#   HCLOUD_SSH_KEY  name or ID of the key in the project (required)
#   SSH_IDENTITY    matching private key file (default ~/.ssh/id_ed25519)
#   REPO, BRANCH    source to build (default this repository's cyberdeck branch on GitHub)
#   OUT             where the images go (default ./k230-images)
# The build runs the same Docker commands as the "Cyberdeck Docker build" section of README.md.
# ccx63 (48 dedicated vCPUs) costs about EUR 1.4/h and builds both images in about 2 h; the
# project's dedicated-core limit must allow the type (ask Hetzner support to raise it).
set -euo pipefail

TYPE=${1:-ccx63}
LOC=${2:-hel1}
: "${HCLOUD_SSH_KEY:?set HCLOUD_SSH_KEY to the name or ID of your SSH key in the Hetzner project}"
SSH_IDENTITY=${SSH_IDENTITY:-$HOME/.ssh/id_ed25519}
REPO=${REPO:-https://github.com/ardangelo/k230-linux.git}
BRANCH=${BRANCH:-cyberdeck}
OUT=${OUT:-$PWD/k230-images}
CONF=k230_canmv_01studio_defconfig
TC=Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2-20250410.tar.gz
NAME=k230-build-$(date +%Y%m%d-%H%M%S)
SSHO=(-i "$SSH_IDENTITY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null
      -o LogLevel=ERROR)

mkdir -p "$OUT"
exec > >(tee -a "$OUT/build.log") 2>&1

cleanup() {
  echo "== $(date) deleting $NAME"
  hcloud server delete "$NAME" || echo "!! DELETE FAILED: delete $NAME in the Hetzner console"
  if hcloud server list -o noheader -o columns=name | grep -qx "$NAME"; then
    echo "!! $NAME STILL EXISTS: delete it in the Hetzner console"
  else
    echo "== $NAME deleted"
  fi
}

echo "== $(date) creating $NAME ($TYPE, $LOC) to build $REPO $BRANCH"
trap cleanup EXIT INT TERM
hcloud server create --name "$NAME" --type "$TYPE" --location "$LOC" --image ubuntu-24.04 \
  --ssh-key "$HCLOUD_SSH_KEY" --label purpose=k230-image-build --label temporary=true

IP=$(hcloud server ip "$NAME")
until ssh "${SSHO[@]}" root@"$IP" true 2>/dev/null; do sleep 5; done
echo "== $(date) $IP up"

ssh "${SSHO[@]}" root@"$IP" bash -s -- "$REPO" "$BRANCH" "$CONF" "$TC" <<'REMOTE'
set -euo pipefail
REPO=$1 BRANCH=$2 CONF=$3 TC=$4
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq docker.io git curl >/dev/null
git clone --branch "$BRANCH" --recurse-submodules --shallow-submodules "$REPO" /src
cd /src && git log --oneline -1
curl -fsSL -o "tools/docker/buildroot/$TC" "https://download.kendryte.com/k230/downloads/dl/gcc/$TC"
docker build -q -f tools/docker/buildroot/Dockerfile -t k230-buildroot tools/docker/buildroot
docker build -q -f tools/docker/debian/Dockerfile -t k230-debian tools/docker/debian
echo "== $(date) dl";     docker run --rm -v /src:/src k230-buildroot make CONF="$CONF" dl
echo "== $(date) build";  docker run --rm -v /src:/src k230-buildroot make CONF="$CONF"
echo "== $(date) debian"; docker run --rm --privileged -v /src:/src k230-debian make CONF="$CONF" debian
ls -la "/src/output/$CONF/images/"
REMOTE

scp "${SSHO[@]}" root@"$IP":/src/output/$CONF/images/{sysimage-sdcard.img.gz,debian.img.gz} "$OUT"/
ls -la "$OUT"
echo "== $(date) done; the server is deleted on exit"
