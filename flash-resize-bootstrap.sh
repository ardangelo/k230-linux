#!/usr/bin/env bash
# Sync the built K230 Debian image from the build host, fix CA certificates in
# the rootfs, flash it to an SD card, and grow the rootfs partition.

set -Eeuo pipefail

CONF="${CONF:-k230_canmv_01studio_defconfig}"
BUILD_HOST="${BUILD_HOST:-deb}"
REMOTE_REPO="${REMOTE_REPO:-~/k230-linux}"
IMAGE_GLOB="${IMAGE_GLOB:-output/${CONF}/images/*_debian_*.img.gz}"
WORKDIR="${WORKDIR:-.flash-work}"
DEV="${DEV:-/dev/sde}"
ROOT_PART="${ROOT_PART:-2}"
BOOT_PART="${BOOT_PART:-1}"
CA_BUNDLE="${CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"

if [ "${EUID}" -eq 0 ]; then
	SUDO=""
else
	SUDO="sudo"
fi

log()
{
	printf '[flash] %s\n' "$*"
}

fail()
{
	printf '[flash] ERROR: %s\n' "$*" >&2
	exit 1
}

require_cmd()
{
	command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

part_path()
{
	case "$1" in
		*[0-9]) printf '%sp%s\n' "$1" "$2" ;;
		*) printf '%s%s\n' "$1" "$2" ;;
	esac
}

wait_for_block()
{
	local path="$1"
	local i

	for i in $(seq 1 50); do
		[ -b "$path" ] && return 0
		sleep 0.1
	done

	return 1
}

mounted_at=""
loopdev=""
cleanup()
{
	if [ -n "$mounted_at" ] && mountpoint -q "$mounted_at"; then
		$SUDO umount "$mounted_at" || true
	fi
	if [ -n "$loopdev" ]; then
		$SUDO losetup -d "$loopdev" || true
	fi
}
trap cleanup EXIT

sync_image_from_build_host()
{
	mkdir -p "$WORKDIR"

	log "locating Debian image on ${BUILD_HOST}:${REMOTE_REPO}/${IMAGE_GLOB}"
	local remote_image
	remote_image="$(ssh -n "$BUILD_HOST" "cd ${REMOTE_REPO} && set -- ${IMAGE_GLOB}; [ -e \$1 ] && printf '%s\n' \$1")"
	[ -n "$remote_image" ] || fail "no remote image matched ${IMAGE_GLOB}"

	local local_gz="${WORKDIR}/$(basename "$remote_image")"
	log "syncing ${BUILD_HOST}:${REMOTE_REPO}/${remote_image} -> ${local_gz}"
	rsync -av --copy-links "${BUILD_HOST}:${REMOTE_REPO}/${remote_image}" "$local_gz"

	IMG="${local_gz%.gz}"
	log "decompressing ${local_gz} -> ${IMG}"
	gzip -dc "$local_gz" > "${IMG}.tmp"
	mv "${IMG}.tmp" "$IMG"
}

fix_ca_certificates()
{
	local image="$1"
	local root_mount="${WORKDIR}/rootfs"
	local root_part_dev

	[ -f "$CA_BUNDLE" ] || fail "host CA bundle not found: ${CA_BUNDLE}"

	mkdir -p "$root_mount"
	log "attaching ${image} for rootfs fixup"
	loopdev="$($SUDO losetup --find --show --partscan "$image")"
	root_part_dev="$(part_path "$loopdev" "$ROOT_PART")"
	wait_for_block "$root_part_dev" || fail "loop root partition did not appear: ${root_part_dev}"

	log "mounting ${root_part_dev}"
	$SUDO mount "$root_part_dev" "$root_mount"
	mounted_at="$root_mount"

	log "installing host CA bundle into rootfs"
	$SUDO install -d -m 0755 "$root_mount/etc/ssl/certs"
	$SUDO install -m 0644 "$CA_BUNDLE" "$root_mount/etc/ssl/certs/ca-certificates.crt"

	if [ -d /usr/share/ca-certificates ]; then
		log "syncing certificate source directory into rootfs"
		$SUDO install -d -m 0755 "$root_mount/usr/share/ca-certificates"
		$SUDO rsync -a --delete /usr/share/ca-certificates/ "$root_mount/usr/share/ca-certificates/"
	fi

	if command -v openssl >/dev/null 2>&1; then
		log "refreshing OpenSSL certificate hashes"
		$SUDO openssl rehash "$root_mount/etc/ssl/certs" >/dev/null 2>&1 || true
	fi

	$SUDO sync
	$SUDO umount "$root_mount"
	mounted_at=""
	$SUDO losetup -d "$loopdev"
	loopdev=""
}

flash_image()
{
	local image="$1"
	local root_dev

	[ -b "$DEV" ] || fail "target block device does not exist: ${DEV}"
	[ "$DEV" != "/dev/sda" ] || fail "refusing to flash /dev/sda"

	log "target device: ${DEV}"
	$SUDO lsblk "$DEV"
	printf 'About to overwrite %s with %s. Type YES to continue: ' "$DEV" "$image"
	read -r answer
	[ "$answer" = "YES" ] || fail "aborted"

	log "unmounting any mounted target partitions"
	$SUDO umount "${DEV}"* >/dev/null 2>&1 || true

	log "flashing image to ${DEV}"
	$SUDO dd if="$image" of="$DEV" bs=16M status=progress conv=fsync
	$SUDO sync
	$SUDO blockdev --flushbufs "$DEV" || true
	log "verifying the first 4 MiB were written"
	$SUDO cmp -n 4194304 "$image" "$DEV" || fail "target did not retain the flashed image; check SD lock/card reader/device path"
	$SUDO partprobe "$DEV" || true
	sleep 2

	log "growing partition ${ROOT_PART} to fill ${DEV}"
	$SUDO parted -s -f "$DEV" print >/dev/null || true
	$SUDO parted -s "$DEV" resizepart "$ROOT_PART" 100%
	$SUDO partprobe "$DEV" || true
	sleep 2

	root_dev="$(part_path "$DEV" "$ROOT_PART")"
	wait_for_block "$root_dev" || fail "root partition did not appear: ${root_dev}"

	log "checking and resizing filesystem on ${root_dev}"
	$SUDO e2fsck -f -y "$root_dev"
	$SUDO resize2fs "$root_dev"
	$SUDO sync
}

main()
{
	require_cmd ssh
	require_cmd rsync
	require_cmd gzip
	require_cmd losetup
	require_cmd mount
	require_cmd umount
	require_cmd dd
	require_cmd blockdev
	require_cmd cmp
	require_cmd parted
	require_cmd partprobe
	require_cmd e2fsck
	require_cmd resize2fs
	require_cmd lsblk

	local IMG
	sync_image_from_build_host
	fix_ca_certificates "$IMG"
	flash_image "$IMG"
	log "done"
}

main "$@"
