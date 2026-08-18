#!/bin/bash
set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 ROOTFS REPOSITORY DISTRIBUTION_MANIFEST CONF" >&2
    exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "install-rootfs-packages: root privileges are required" >&2
    exit 1
fi

ROOTFS=$(realpath "$1")
REPOSITORY=$(realpath "$2")
DISTRIBUTION_MANIFEST=$(realpath "$3")
CONF=$4
REPOSITORY_MANIFEST="$REPOSITORY/repository-manifest.json"
TEMP_REPOSITORY=/var/tmp/k230-local-repository
TEMP_SOURCE=/etc/apt/sources.list.d/k230-local.list
TEMP_DISTRIBUTION_SOURCE=/etc/apt/sources.list.d/k230-distribution.list
POLICY_RC=/usr/sbin/policy-rc.d
MOUNTS=()
QEMU_STAGED=
POLICY_BACKUP=
SOURCE_BACKUP=

fail()
{
    echo "install-rootfs-packages: $*" >&2
    exit 1
}

cleanup()
{
    local status=$?
    rm -rf "$ROOTFS$TEMP_REPOSITORY"
    rm -f "$ROOTFS$TEMP_SOURCE"
    rm -f "$ROOTFS$TEMP_DISTRIBUTION_SOURCE"
    if [ -n "$SOURCE_BACKUP" ] && [ -e "$SOURCE_BACKUP" ]; then
        mv "$SOURCE_BACKUP" "$ROOTFS$TEMP_SOURCE"
    fi
    rm -f "$ROOTFS$POLICY_RC"
    if [ -n "$POLICY_BACKUP" ] && [ -e "$POLICY_BACKUP" ]; then
        mv "$POLICY_BACKUP" "$ROOTFS$POLICY_RC"
    fi
    if [ -n "$QEMU_STAGED" ]; then
        rm -f "$ROOTFS$QEMU_STAGED"
    fi
    local index
    for ((index=${#MOUNTS[@]}-1; index>=0; index--)); do
        if mountpoint -q "${MOUNTS[$index]}"; then
            umount -l "${MOUNTS[$index]}"
        fi
    done
    exit "$status"
}
trap cleanup EXIT INT TERM

[ -d "$ROOTFS" ] || fail "rootfs does not exist: $ROOTFS"
[ -x "$ROOTFS/bin/true" ] || fail "rootfs lacks executable /bin/true"
[ -f "$REPOSITORY/Packages" ] || fail "repository lacks Packages index"
[ -f "$REPOSITORY_MANIFEST" ] || fail "repository manifest is missing"
[ -f "$DISTRIBUTION_MANIFEST" ] || fail "distribution package manifest is missing"
[[ "$CONF" =~ ^[A-Za-z0-9._+-]+$ ]] || fail "invalid Buildroot configuration name"
if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null ||
        fail "cannot mount binfmt_misc; run the Debian container with --privileged"
fi
if [ ! -r /proc/sys/fs/binfmt_misc/qemu-riscv64 ]; then
    command -v update-binfmts >/dev/null 2>&1 ||
        fail "update-binfmts is unavailable; rebuild the k230-debian image"
    update-binfmts --enable qemu-riscv64 ||
        fail "cannot register qemu-riscv64; run the Debian container with --privileged"
fi
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-riscv64 ||
    fail "qemu-riscv64 binfmt is disabled"

mapfile -t REPOSITORY_VALUES < <(
    python3 - "$REPOSITORY_MANIFEST" <<'PY'
import json
import re
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text())
release = value.get("kernel_release", "")
packages = value.get("install_packages", [])
if not re.fullmatch(r"[A-Za-z0-9._+-]+", release):
    raise SystemExit("invalid kernel release in repository manifest")
if not packages or any(not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", item) for item in packages):
    raise SystemExit("invalid install package allowlist in repository manifest")
print(release)
print(*packages, sep="\n")
PY
)
[ "${#REPOSITORY_VALUES[@]}" -gt 1 ] || fail "repository manifest has no package allowlist"
KERNEL_RELEASE=${REPOSITORY_VALUES[0]}
INSTALL_PACKAGES=("${REPOSITORY_VALUES[@]:1}")

mapfile -t DISTRIBUTION_VALUES < <(
    python3 - "$DISTRIBUTION_MANIFEST" "$CONF" <<'PY'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

value = json.loads(Path(sys.argv[1]).read_text())
conf = sys.argv[2]
if value.get("schema_version") != 1:
    raise SystemExit("unsupported distribution package manifest schema")
snapshot = value.get("snapshot", "")
parsed = urlparse(snapshot)
if parsed.scheme != "https" or parsed.netloc != "snapshot.debian.org":
    raise SystemExit("distribution snapshot must use snapshot.debian.org over HTTPS")
suite = value.get("suite", "")
if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]*", suite):
    raise SystemExit("invalid distribution suite")
packages = []
for entry in value.get("packages", []):
    if conf not in entry.get("configs", []):
        continue
    package = entry.get("package", "")
    version = entry.get("version", "")
    if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", package):
        raise SystemExit(f"invalid distribution package name: {package!r}")
    if not version or any(character.isspace() for character in version):
        raise SystemExit(f"invalid distribution package version: {version!r}")
    packages.append(f"{package}={version}")
if not packages:
    raise SystemExit(f"no distribution packages selected for {conf}")
print(snapshot)
print(suite)
print(*packages, sep="\n")
PY
)
[ "${#DISTRIBUTION_VALUES[@]}" -gt 2 ] || fail "distribution package manifest has no package allowlist"
DISTRIBUTION_SNAPSHOT=${DISTRIBUTION_VALUES[0]}
DISTRIBUTION_SUITE=${DISTRIBUTION_VALUES[1]}
DISTRIBUTION_PACKAGES=("${DISTRIBUTION_VALUES[@]:2}")
# A successful foreign-architecture command is required before rootfs mutation.
if ! chroot "$ROOTFS" /bin/true; then
    INTERPRETER=$(sed -n 's/^interpreter //p' /proc/sys/fs/binfmt_misc/qemu-riscv64)
    FLAGS=$(sed -n 's/^flags: //p' /proc/sys/fs/binfmt_misc/qemu-riscv64)
    [ -n "$INTERPRETER" ] || fail "registered qemu-riscv64 handler has no interpreter"
    if [[ "$FLAGS" == *F* ]]; then
        fail "registered fixed qemu-riscv64 interpreter cannot execute the staged rootfs"
    fi
    QEMU=$(command -v qemu-riscv64-static || true)
    [ -n "$QEMU" ] || fail "qemu-riscv64-static is required for non-fixed binfmt registration"
    "$QEMU" -L "$ROOTFS" "$ROOTFS/bin/true" || fail "explicit qemu-riscv64 rootfs smoke test failed"
    install -D -m 0755 "$QEMU" "$ROOTFS$INTERPRETER"
    QEMU_STAGED=$INTERPRETER
    chroot "$ROOTFS" /bin/true || fail "RISC-V chroot remains unusable after staging QEMU"
fi

mount_chroot()
{
    local source=$1
    local destination=$2
    local type=${3:-}
    mkdir -p "$ROOTFS$destination"
    if [ -n "$type" ]; then
        mount -t "$type" "$source" "$ROOTFS$destination"
    else
        mount --rbind "$source" "$ROOTFS$destination"
        mount --make-rslave "$ROOTFS$destination"
    fi
    MOUNTS+=("$ROOTFS$destination")
}

mount_chroot proc /proc proc
mount_chroot /sys /sys
mount_chroot /dev /dev

if [ -e "$ROOTFS$POLICY_RC" ]; then
    POLICY_BACKUP="$ROOTFS$POLICY_RC.k230-package-backup"
    [ ! -e "$POLICY_BACKUP" ] || fail "stale policy-rc.d backup exists"
    mv "$ROOTFS$POLICY_RC" "$POLICY_BACKUP"
fi
install -D -m 0755 /dev/stdin "$ROOTFS$POLICY_RC" <<'POLICY'
#!/bin/sh
exit 101
POLICY

install -D -m 0644 /dev/stdin "$ROOTFS$TEMP_DISTRIBUTION_SOURCE" <<APT_SOURCE
deb [check-valid-until=no] $DISTRIBUTION_SNAPSHOT $DISTRIBUTION_SUITE main
APT_SOURCE
DISTRIBUTION_APT_OPTIONS=(
    -o "Dir::Etc::sourcelist=$TEMP_DISTRIBUTION_SOURCE"
    -o "Dir::Etc::sourceparts=-"
    -o "Acquire::Check-Valid-Until=false"
    -o "Acquire::Languages=none"
    -o "Acquire::Retries=3"
)
chroot "$ROOTFS" apt-get "${DISTRIBUTION_APT_OPTIONS[@]}" update
chroot "$ROOTFS" apt-get "${DISTRIBUTION_APT_OPTIONS[@]}" --simulate --no-install-recommends install \
    "${DISTRIBUTION_PACKAGES[@]}"
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get "${DISTRIBUTION_APT_OPTIONS[@]}" \
    -y --no-install-recommends install "${DISTRIBUTION_PACKAGES[@]}"
if [ -e "$ROOTFS$TEMP_SOURCE" ]; then
    SOURCE_BACKUP="$ROOTFS$TEMP_SOURCE.k230-package-backup"
    [ ! -e "$SOURCE_BACKUP" ] || fail "stale local APT source backup exists"
    mv "$ROOTFS$TEMP_SOURCE" "$SOURCE_BACKUP"
fi
cp -a "$REPOSITORY" "$ROOTFS$TEMP_REPOSITORY"
install -D -m 0644 /dev/stdin "$ROOTFS$TEMP_SOURCE" <<APT_SOURCE
deb [trusted=yes] file:$TEMP_REPOSITORY ./
APT_SOURCE

APT_OPTIONS=(
    -o "Dir::Etc::sourcelist=$TEMP_SOURCE"
    -o "Dir::Etc::sourceparts=-"
    -o "Acquire::Languages=none"
    -o "Acquire::Retries=0"
)
chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" update
# Resolve the complete transaction before removing the unowned baseline module.
chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" --simulate --no-install-recommends install "${INSTALL_PACKAGES[@]}"

BASELINE_MODULE="$ROOTFS/lib/modules/$KERNEL_RELEASE/updates/sharp-drm.ko"
[ -f "$BASELINE_MODULE" ] || fail "baseline Sharp DRM module is missing at $BASELINE_MODULE"
rm -f "$BASELINE_MODULE"

DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" -y --no-install-recommends install "${INSTALL_PACKAGES[@]}"
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" dpkg --configure -a
AUDIT=$(chroot "$ROOTFS" dpkg --audit)
[ -z "$AUDIT" ] || fail "dpkg audit failed: $AUDIT"
chroot "$ROOTFS" dpkg-query -W k230-sharp-drm >/dev/null
OWNER=$(chroot "$ROOTFS" dpkg-query -S "/lib/modules/$KERNEL_RELEASE/updates/sharp-drm.ko")
[[ "$OWNER" == k230-sharp-drm:* ]] || fail "Sharp DRM module ownership is incorrect: $OWNER"
[ -f "$BASELINE_MODULE" ] || fail "package did not restore Sharp DRM module"
grep -qxF sharp-drm "$ROOTFS/etc/modules-load.d/k230-sharp-drm.conf" || fail "modules-load configuration is incorrect"
grep -qxF 'options sharp-drm mono_cutoff=64' "$ROOTFS/etc/modprobe.d/k230-sharp-drm.conf" || fail "modprobe configuration is incorrect"
grep -qF 'updates/sharp-drm.ko:' "$ROOTFS/lib/modules/$KERNEL_RELEASE/modules.dep" || fail "depmod metadata does not contain Sharp DRM"
ABI_VERSION=$(chroot "$ROOTFS" dpkg-query -W -f='${Version}' k230-kernel-abi)
MODULE_VERSION=$(chroot "$ROOTFS" dpkg-query -W -f='${Version}' k230-sharp-drm)
[ "$ABI_VERSION" = "$MODULE_VERSION" ] || fail "kernel ABI and module package versions differ"
chroot "$ROOTFS" dpkg-query -W cyberdeck-service >/dev/null
[ -x "$ROOTFS/usr/bin/cyberdeck_daemon" ] || fail "cyberdeck-service daemon is missing"
[ -f "$ROOTFS/usr/lib/cyberdeck-service/libpebble3-jvm-fat.jar" ] ||
    fail "cyberdeck-service JVM library is missing"
[ -x "$ROOTFS/usr/bin/kbd_mode" ] || fail "kbd dependency did not install kbd_mode"
chroot "$ROOTFS" test -x /usr/bin/java || fail "Java runtime dependency is missing"
chroot "$ROOTFS" systemctl is-enabled --quiet cyberdeck-service.service ||
    fail "cyberdeck-service is not enabled"
chroot "$ROOTFS" systemctl disable \
    systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service \
    wpa_supplicant.service
chroot "$ROOTFS" systemctl enable NetworkManager.service
[ -x "$ROOTFS/usr/bin/nmtui" ] || fail "network-manager package did not install nmtui"
if chroot "$ROOTFS" systemctl is-enabled --quiet systemd-networkd.service; then
    fail "systemd-networkd remains enabled"
fi
if chroot "$ROOTFS" systemctl is-enabled --quiet wpa_supplicant.service; then
    fail "standalone wpa_supplicant remains enabled"
fi
chroot "$ROOTFS" systemctl is-enabled --quiet NetworkManager.service ||
    fail "NetworkManager is not enabled"
chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS/var/lib/apt/lists/"*

echo "Installed ${INSTALL_PACKAGES[*]} into $ROOTFS"
