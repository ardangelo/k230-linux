#!/bin/bash
set -Eeuo pipefail

fail()
{
    echo "install-rootfs-packages: $*" >&2
    exit 1
}

[ "$#" -eq 5 ] || fail "usage: $0 ROOTFS KERNEL_CONTEXT PUBLIC_KEY DISTRIBUTION_MANIFEST CONF"
[ "$(id -u)" -eq 0 ] || fail "root privileges are required"
ROOTFS=$(realpath "$1")
KERNEL_CONTEXT=$(realpath "$2")
PUBLIC_KEY=$(realpath "$3")
DISTRIBUTION_MANIFEST=$(realpath "$4")
CONF=$5
[ "$CONF" = k230_canmv_01studio_defconfig ] || fail "unsupported Buildroot configuration: $CONF"
[ -d "$ROOTFS" ] || fail "rootfs does not exist: $ROOTFS"
[ -x "$ROOTFS/bin/true" ] || fail "rootfs lacks executable /bin/true"
[ -f "$KERNEL_CONTEXT" ] || fail "kernel context is missing"
[ -f "$PUBLIC_KEY" ] || fail "public key is missing"
[ -f "$DISTRIBUTION_MANIFEST" ] || fail "distribution package manifest is missing"

# Capture producer status before parsing; reject invalid inputs before owned cleanup.
if ! CONTEXT_OUTPUT=$(python3 - "$KERNEL_CONTEXT" "$CONF" <<'PY'
import json
import re
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text())
if value.get("schema_version") != 1 or value.get("conf") != sys.argv[2]:
    raise SystemExit("kernel context does not match selected configuration")
release = value.get("kernel_release", "")
abi = value.get("abi_sha256", "")
if not re.fullmatch(r"[A-Za-z0-9._+-]+", release):
    raise SystemExit("invalid kernel release in kernel context")
if not re.fullmatch(r"[0-9a-f]{64}", abi):
    raise SystemExit("invalid ABI in kernel context")
print(release)
print(abi)
PY
); then
    fail "cannot read kernel context"
fi
mapfile -t CONTEXT_VALUES <<< "$CONTEXT_OUTPUT"
KERNEL_RELEASE=${CONTEXT_VALUES[0]}
ABI=${CONTEXT_VALUES[1]}
SUITE=trixie-k230-$ABI
INSTALL_PACKAGES=(cyberdeck-service k230-status-ready k230-sharp-drm k230-kernel-abi)
if ! DISTRIBUTION_OUTPUT=$(python3 - "$DISTRIBUTION_MANIFEST" "$CONF" <<'PY'
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
); then
    fail "cannot read distribution packages"
fi
mapfile -t DISTRIBUTION_VALUES <<< "$DISTRIBUTION_OUTPUT"
DISTRIBUTION_SNAPSHOT=${DISTRIBUTION_VALUES[0]}
DISTRIBUTION_SUITE=${DISTRIBUTION_VALUES[1]}
DISTRIBUTION_PACKAGES=("${DISTRIBUTION_VALUES[@]:2}")
BASELINE_MODULE="$ROOTFS/lib/modules/$KERNEL_RELEASE/updates/sharp-drm.ko"
[ -f "$BASELINE_MODULE" ] || fail "baseline Sharp DRM module is missing at $BASELINE_MODULE"

POLICY_RC=/usr/sbin/policy-rc.d
MOUNTS=()
QEMU_STAGED=
POLICY_BACKUP=
POLICY_OWNED=
TRANSACTION=
cleanup()
{
    local status=$?
    trap - EXIT INT TERM
    if [ -n "$POLICY_OWNED" ]; then
        rm -f "$ROOTFS$POLICY_RC"
    fi
    if [ -n "$POLICY_BACKUP" ]; then
        mv "$POLICY_BACKUP" "$ROOTFS$POLICY_RC"
    fi
    if [ -n "$QEMU_STAGED" ]; then
        rm -f "$ROOTFS$QEMU_STAGED"
    fi
    local index
    for ((index=${#MOUNTS[@]}-1; index>=0; index--)); do
        umount -R "${MOUNTS[$index]}" || exit 1
    done
    if [ -n "$TRANSACTION" ]; then
        rm -rf "$TRANSACTION"
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
    [ -n "$INTERPRETER" ] || fail "registered qemu-riscv64 handler has no interpreter"
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
    mountpoint -q "$ROOTFS$destination" && return
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
TRANSACTION=$(mktemp -d "$ROOTFS/var/tmp/k230-install.XXXXXXXX")
TEMP_DIR=${TRANSACTION#"$ROOTFS"}
chmod 0755 "$TRANSACTION"
if [ -e "$ROOTFS$POLICY_RC" ] || [ -L "$ROOTFS$POLICY_RC" ]; then
    mv "$ROOTFS$POLICY_RC" "$TRANSACTION/policy-rc.d"
    POLICY_BACKUP="$TRANSACTION/policy-rc.d"
fi
POLICY_OWNED=1
install -D -m 0755 /dev/stdin "$ROOTFS$POLICY_RC" <<'POLICY'
#!/bin/sh
exit 101
POLICY

install -D -m 0644 "$KERNEL_CONTEXT" "$ROOTFS/usr/share/k230/kernel-context.json"
printf '%s\n' "$ABI" > "$ROOTFS/usr/share/k230/kernel-abi"
install -D -m 0644 "$PUBLIC_KEY" "$ROOTFS/etc/apt/keyrings/cyberdeck-archive.asc"
cat > "$TRANSACTION/cyberdeck.sources" <<APT_SOURCE
Types: deb
URIs: https://ardangelo.github.io/cyberdeck-packages/
Suites: $SUITE
Components: main
Architectures: riscv64
Signed-By: /etc/apt/keyrings/cyberdeck-archive.asc C0713A2A6C3A2279E125646BFD377548A4F82392
APT_SOURCE
cp "$TRANSACTION/cyberdeck.sources" "$TRANSACTION/k230-install.sources"
cat >> "$TRANSACTION/k230-install.sources" <<APT_SOURCE

Types: deb
URIs: ${DISTRIBUTION_SNAPSHOT%/}/
Suites: $DISTRIBUTION_SUITE
Components: main
Architectures: riscv64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
Check-Valid-Until: no
APT_SOURCE
install -D -m 0644 /dev/stdin "$ROOTFS/etc/apt/preferences.d/cyberdeck" <<APT_PREFERENCES
Package: cyberdeck-service k230-status-ready k230-sharp-drm k230-kernel-abi
Pin: release o=Cyberdeck,n=$SUITE
Pin-Priority: 500

Package: *
Pin: release o=Cyberdeck
Pin-Priority: -1
APT_PREFERENCES
mkdir -p "$TRANSACTION/lists/partial" "$TRANSACTION/cache/archives/partial"
APT_OPTIONS=(
    -o "Dir::Etc::sourcelist=$TEMP_DIR/k230-install.sources"
    -o "Dir::Etc::sourceparts=-"
    -o "Dir::State::lists=$TEMP_DIR/lists"
    -o "Dir::Cache=$TEMP_DIR/cache"
    -o "Acquire::Check-Valid-Until=true"
    -o "Acquire::AllowInsecureRepositories=false"
    -o "APT::Get::AllowUnauthenticated=false"
    -o "APT::Update::Error-Mode=any"
    -o "Acquire::Languages=none"
    -o "Acquire::Retries=0"
)
chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" update
# Record candidates using the very same authenticated transaction lists.
chroot "$ROOTFS" apt-cache "${APT_OPTIONS[@]}" policy "${INSTALL_PACKAGES[@]}"
chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" --simulate --no-install-recommends install \
    "${INSTALL_PACKAGES[@]}" "${DISTRIBUTION_PACKAGES[@]}"
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" \
    -y --download-only --reinstall --no-install-recommends install \
    "${INSTALL_PACKAGES[@]}" "${DISTRIBUTION_PACKAGES[@]}"
# Baseline bytes survive all authentication, resolution and download failures.
rm -f "$BASELINE_MODULE"
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get "${APT_OPTIONS[@]}" \
    -y --no-download --reinstall --no-install-recommends install \
    "${INSTALL_PACKAGES[@]}" "${DISTRIBUTION_PACKAGES[@]}"
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

VERMAGIC=$(chroot "$ROOTFS" modinfo -F vermagic "/lib/modules/$KERNEL_RELEASE/updates/sharp-drm.ko")
[ "${VERMAGIC%% *}" = "$KERNEL_RELEASE" ] || fail "Sharp DRM vermagic does not match kernel release"
python3 - "$ROOTFS/usr/share/k230-kernel-abi/kernel-context.json" "$ABI" <<'PY'
import json
import sys
from pathlib import Path
if json.loads(Path(sys.argv[1]).read_text()).get("abi_sha256") != sys.argv[2]:
    raise SystemExit("installed marker does not match image ABI")
PY
[ -x "$ROOTFS/usr/bin/k230-status-ready" ] || fail "readiness helper is missing"
chroot "$ROOTFS" systemctl is-enabled --quiet k230-status-ready.service || fail "readiness service is not enabled"
install -D -m 0644 "$TRANSACTION/cyberdeck.sources" "$ROOTFS/etc/apt/sources.list.d/cyberdeck.sources"
chroot "$ROOTFS" dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' \
    "${INSTALL_PACKAGES[@]}" "${DISTRIBUTION_PACKAGES[@]%%=*}"
echo "Installed ${INSTALL_PACKAGES[*]} into $ROOTFS"
