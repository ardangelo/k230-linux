#!/bin/bash
set -Eeuo pipefail

fail()
{
    echo "install-rootfs-packages: $*" >&2
    exit 1
}

[ "$#" -eq 3 ] || fail "usage: $0 ROOTFS KERNEL_CONTEXT PUBLIC_KEY"
[ "$(id -u)" -eq 0 ] || fail "root privileges are required"
ROOTFS=$(realpath "$1")
KERNEL_CONTEXT=$(realpath "$2")
PUBLIC_KEY=$(realpath "$3")
[ -d "$ROOTFS" ] || fail "rootfs does not exist: $ROOTFS"
[ -x "$ROOTFS/bin/true" ] || fail "rootfs lacks executable /bin/true"
[ -f "$KERNEL_CONTEXT" ] || fail "kernel context is missing"
[ -f "$PUBLIC_KEY" ] || fail "public key is missing"

ABI=$(python3 - "$KERNEL_CONTEXT" <<'PY'
import json
import sys
from pathlib import Path

print(json.loads(Path(sys.argv[1]).read_text())["abi_sha256"])
PY
) || fail "cannot read kernel context"
SUITE=trixie-k230-$ABI
POLICY_RC=/usr/sbin/policy-rc.d
MOUNTS=()
QEMU_STAGED=
POLICY_BACKUP=
POLICY_OWNED=
RESOLV_BACKUP=
RESOLV_OWNED=
STATE=
cleanup()
{
    local status=$? index
    trap - EXIT INT TERM
    for ((index=${#MOUNTS[@]}-1; index>=0; index--)); do
        if ! umount -R "${MOUNTS[$index]}"; then
            echo "install-rootfs-packages: cannot unmount ${MOUNTS[$index]}; leaving staging intact" >&2
            exit 1
        fi
    done
    if [ -n "$POLICY_OWNED" ]; then
        rm -f "$ROOTFS$POLICY_RC"
    fi
    if [ -n "$POLICY_BACKUP" ]; then
        mv "$POLICY_BACKUP" "$ROOTFS$POLICY_RC"
    fi
    if [ -n "$QEMU_STAGED" ]; then
        rm -f "$ROOTFS$QEMU_STAGED"
    fi
    if [ -n "$RESOLV_OWNED" ]; then
        rm -f "$ROOTFS/etc/resolv.conf"
    fi
    if [ -n "$RESOLV_BACKUP" ]; then
        mv "$RESOLV_BACKUP" "$ROOTFS/etc/resolv.conf"
    fi
    if [ -n "$STATE" ]; then
        rm -rf "$STATE"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null ||
        fail "cannot mount binfmt_misc; run the Debian container with --privileged"
fi
if [ ! -r /proc/sys/fs/binfmt_misc/qemu-riscv64 ]; then
    command -v update-binfmts >/dev/null 2>&1 || fail "update-binfmts is unavailable"
    update-binfmts --enable qemu-riscv64 || fail "cannot register qemu-riscv64"
fi
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-riscv64 || fail "qemu-riscv64 binfmt is disabled"
if ! chroot "$ROOTFS" /bin/true; then
    INTERPRETER=$(sed -n 's/^interpreter //p' /proc/sys/fs/binfmt_misc/qemu-riscv64)
    FLAGS=$(sed -n 's/^flags: //p' /proc/sys/fs/binfmt_misc/qemu-riscv64)
    [[ "$INTERPRETER" = /* ]] || fail "registered qemu-riscv64 handler has no absolute interpreter"
    [[ "$FLAGS" != *F* ]] || fail "registered fixed qemu-riscv64 interpreter cannot execute the staged rootfs"
    [ ! -e "$ROOTFS$INTERPRETER" ] && [ ! -L "$ROOTFS$INTERPRETER" ] ||
        fail "refusing to overwrite existing QEMU interpreter"
    QEMU=$(command -v qemu-riscv64-static || true)
    [ -n "$QEMU" ] || fail "qemu-riscv64-static is required for non-fixed binfmt registration"
    "$QEMU" -L "$ROOTFS" "$ROOTFS/bin/true" || fail "explicit qemu-riscv64 rootfs smoke test failed"
    QEMU_STAGED=$INTERPRETER
    install -D -m 0755 "$QEMU" "$ROOTFS$INTERPRETER"
    chroot "$ROOTFS" /bin/true || fail "RISC-V chroot remains unusable after staging QEMU"
fi

mount_chroot()
{
    local source=$1 destination=$2 type=${3:-}
    ! mountpoint -q "$ROOTFS$destination" || fail "refusing existing rootfs mount: $destination"
    mkdir -p "$ROOTFS$destination"
    if [ -n "$type" ]; then
        mount -t "$type" "$source" "$ROOTFS$destination"
    else
        mount --rbind "$source" "$ROOTFS$destination"
    fi
    MOUNTS+=("$ROOTFS$destination")
    [ -n "$type" ] || mount --make-rslave "$ROOTFS$destination"
}
mount_chroot proc /proc proc
mount_chroot /sys /sys
mount_chroot /dev /dev

mkdir -p "$ROOTFS/var/tmp"
STATE=$(mktemp -d "$ROOTFS/var/tmp/k230-install.XXXXXXXX")
# The archived resolver expects a running systemd-resolved, absent in a chroot.
if [ -e "$ROOTFS/etc/resolv.conf" ] || [ -L "$ROOTFS/etc/resolv.conf" ]; then
    mv "$ROOTFS/etc/resolv.conf" "$STATE/resolv.conf"
    RESOLV_BACKUP="$STATE/resolv.conf"
fi
RESOLV_OWNED=1
install -m 0644 /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
if [ -e "$ROOTFS$POLICY_RC" ] || [ -L "$ROOTFS$POLICY_RC" ]; then
    mv "$ROOTFS$POLICY_RC" "$STATE/policy-rc.d"
    POLICY_BACKUP="$STATE/policy-rc.d"
fi
POLICY_OWNED=1
install -D -m 0755 /dev/stdin "$ROOTFS$POLICY_RC" <<'POLICY'
#!/bin/sh
exit 101
POLICY

install -D -m 0644 "$KERNEL_CONTEXT" "$ROOTFS/usr/share/k230/kernel-context.json"
install -D -m 0644 /dev/stdin "$ROOTFS/usr/share/k230/kernel-abi" <<<"$ABI"
install -D -m 0644 "$PUBLIC_KEY" "$ROOTFS/etc/apt/keyrings/cyberdeck-archive.asc"
mkdir -p "$ROOTFS/etc/apt/sources.list.d" "$ROOTFS/etc/apt/preferences.d"
rm -f "$ROOTFS/etc/apt/sources.list" \
    "$ROOTFS/etc/apt/sources.list.d/"*.list \
    "$ROOTFS/etc/apt/sources.list.d/"*.sources
cat > "$ROOTFS/etc/apt/sources.list.d/debian.sources" <<'APT_DEBIAN'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main
Architectures: riscv64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main
Architectures: riscv64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
APT_DEBIAN
cat > "$ROOTFS/etc/apt/sources.list.d/cyberdeck.sources" <<APT_CYBERDECK
Types: deb
URIs: https://ardangelo.github.io/cyberdeck-packages/
Suites: $SUITE
Components: main
Architectures: riscv64
Signed-By: /etc/apt/keyrings/cyberdeck-archive.asc C0713A2A6C3A2279E125646BFD377548A4F82392
APT_CYBERDECK
cat > "$ROOTFS/etc/apt/preferences.d/cyberdeck" <<APT_PREFERENCES
Package: cyberdeck-service k230-status-ready k230-sharp-drm k230-kernel-abi
Pin: release o=Cyberdeck,n=$SUITE
Pin-Priority: 500

Package: *
Pin: release o=Cyberdeck
Pin-Priority: -1
APT_PREFERENCES

chroot "$ROOTFS" apt-get -o APT::Update::Error-Mode=any -o Acquire::Check-Valid-Until=true update
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get -y --no-install-recommends install \
    cyberdeck-service k230-status-ready k230-sharp-drm k230-kernel-abi \
    network-manager kbd default-jre-headless
chroot "$ROOTFS" systemctl disable \
    systemd-networkd.service systemd-networkd-wait-online.service systemd-networkd.socket \
    wpa_supplicant.service
chroot "$ROOTFS" systemctl enable \
    NetworkManager.service cyberdeck-service.service k230-status-ready.service
chroot "$ROOTFS" dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' \
    cyberdeck-service k230-status-ready k230-sharp-drm k230-kernel-abi \
    network-manager kbd default-jre-headless
