#!/bin/bash
# Script to generate distribution images for K230 SDK
# Usage: distribution.sh <distribution_type> <BRW_BUILD_DIR>

distribution_type="$1"
BRW_BUILD_DIR=$(realpath "$2")
CONF=$(basename "$BRW_BUILD_DIR")
BINARIES_DIR="${BRW_BUILD_DIR}/images"
K230_SDK_ROOT=$(cd "$(dirname "$(dirname "${BRW_BUILD_DIR}")")" && pwd)

# Don't use set -e because it hides errors in pipe commands
# set -e
set -e  # Disable exit on error to see all errors

# Color definitions
COLOR_NONE="\033[0m"
RED="\033[1;31;40m"
BLUE="\033[1;34;40m"
GREEN="\033[1;32;40m"
YELLOW="\033[1;33;40m"

# Print colored messages
print_red() {
    echo -e "${RED}$*${COLOR_NONE}"
}

print_blue() {
    echo -e "${BLUE}$*${COLOR_NONE}"
}

print_green() {
    echo -e "${GREEN}$*${COLOR_NONE}"
}

print_yellow() {
    echo -e "${YELLOW}$*${COLOR_NONE}"
}

# Generate rootfs helper function
# $1: distribution name (debian/ubuntu)
generate_rootfs_help() {
    local dist="$1"
    local script_name="rootfs_${dist}_gen.sh"
    local script_path="${K230_SDK_ROOT}/buildroot-overlay/board/canaan/k230-soc/distribution/${script_name}"

    print_red "You need to manually execute the follow commands from ${script_name}:"
    echo -e "${BLUE}"
    cat "${script_path}"
    echo -e "${COLOR_NONE}"
    print_red "Execute the above commands one by one on Linux (not in Docker)"
    print_red "Reference doc: https://developer.canaan-creative.com/k230/zh/dev/03_other/K230_debian_ubuntu%E8%AF%B4%E6%98%8E.html"
}

debian_gen_rootfs() {
    generate_rootfs_help "debian"
}

ubuntu_gen_rootfs() {
    generate_rootfs_help "ubuntu"
}

# Generate output image filename with version info
# $1: distribution name
get_image_last_name() {
    local distname="$1"
    local CONF=$(basename "${BRW_BUILD_DIR}")

    local sdk_ver="v0.0.0"
    local nncase_ver="v2.11.0"  # Default nncase version
    local commit_id="xx"

    local sdk_ver_file="${K230_SDK_ROOT}/buildroot-overlay/board/canaan/k230-soc/rootfs_overlay/etc/version/release_version"
    local nncase_ver_file="${K230_SDK_ROOT}/output/${CONF}/build/libnncase/nncase/include/nncase/version.h"

    # Determine board name based on config
    local canaan_site_name
    case "${CONF}" in
        k230_canmv_defconfig)
            canaan_site_name="CanMV-K230_V1P0_P1"
            ;;
        k230_evb_defconfig)
            canaan_site_name="EVB-K230"
            ;;
        k230_canmv_01studio_defconfig)
            canaan_site_name="CanMV-K230_01studio"
            ;;
        k230_canmv_lckfb_defconfig)
            canaan_site_name="CanMV-K230_LCKFB"
            ;;
        k230_canmv_v3_defconfig)
            canaan_site_name="CanMV-K230_V3P0"
            ;;
        k230d_canmv_defconfig)
            canaan_site_name="CanMV-K230D"
            ;;
        k230d_canmv_junroc_ai_cam_defconfig)
            canaan_site_name="CanMV_K230D_JUNROC_AI_CAM"
            ;;
        *)
            canaan_site_name="${CONF%%_defconfig}"
            ;;
    esac

    # Extract SDK version
    if [ -f "${sdk_ver_file}" ]; then
        sdk_ver=$(awk -F- '/^sdk:/ { print $1 }' "${sdk_ver_file}" | cut -d: -f2)
        commit_id=$(awk -F- '/^sdk:/ { print $6}' ${sdk_ver_file})
    fi

    # Extract nncase version from version.h if available
    if [ -f "${nncase_ver_file}" ]; then
        local nncase_version_raw
        nncase_version_raw=$(grep -w "NNCASE_VERSION" "${nncase_ver_file}" | cut -d'"' -f2)
        if [ -n "${nncase_version_raw}" ]; then
            nncase_ver="${nncase_version_raw}"
        fi
    fi

    echo "${canaan_site_name}_${distname}_${sdk_ver}_nncase_v${nncase_ver}_${commit_id}.img.gz"
}



# Generate distribution rootfs and finalize image
# $1: dist name (debian/ubuntu)
# $2: dist_rootfs tarball name (debian13/ubuntu24)
# $3: dist_rootfs tarball URL
# $4: dist_rootfs tarball MD5 checksum
distribution_rootfs_replace() (
    local distname="$1"
    local distr_rootfs="$2"
    local distr_rootfs_url="$3"
    local md5_v="$4"
    local dist_img_name="${distname}.img"

    # Check root privileges
    if [ "$(id -u)" -ne 0 ]; then
        print_red "Permission denied: you need root privileges. Example: sudo make ${distname}"
        exit 1
    fi

    # Check buildroot output exists
    if [ ! -f "${BINARIES_DIR}/sysimage-sdcard.img" ]; then
        print_red "Error: you need to build buildroot first: make buildroot"
        exit 1
    fi

    print_blue "Processing ${distname} distribution..."

    cd "${BINARIES_DIR}"

    # Ubuntu retains the upstream image assembly order. Debian copies the SD
    # image only after package installation and ext4 creation succeed.
    if [ "$distname" = ubuntu ]; then
        cp sysimage-sdcard.img "${dist_img_name}"
    fi

    # Download and verify rootfs tarball
    if [ ! -f "${distr_rootfs}.tar.gz" ]; then
        print_blue "Downloading ${distr_rootfs}.tar.gz..."
        wget --progress=bar:force "${distr_rootfs_url}" -O "${distr_rootfs}.tar.gz"
    fi

    local actual_md5
    actual_md5=$(md5sum "${distr_rootfs}.tar.gz" | cut -d' ' -f1)
    if [ "${md5_v}" != "${actual_md5}" ]; then
        print_red "Error: ${distr_rootfs}.tar.gz MD5 mismatch!"
        print_red "Expected: ${md5_v}, Got: ${actual_md5}"
        exit 1
    fi
    print_green "MD5 verified successfully"

    # Extract rootfs
    print_blue "Extracting rootfs (this may take a while)..."
    local ROOTFS_STAGE ROOTFS_DIR
    if [ "$distname" = debian ]; then
        ROOTFS_STAGE=$(mktemp -d "$(realpath "${TMPDIR:-/tmp}")/k230-debian.XXXXXXXX")
        ROOTFS_DIR="$ROOTFS_STAGE/$distr_rootfs"
        cleanup_debian_stage() {
            local status=$? mounts
            trap - EXIT
            if ! mounts=$(findmnt -rn --raw -o TARGET); then
                print_red "Cannot check mounts; preserving Debian stage: $ROOTFS_STAGE"
                exit 1
            fi
            if printf '%s\n' "$mounts" | awk -v stage="$ROOTFS_STAGE" \
                '$0 == stage || index($0, stage "/") == 1 { found = 1 } END { exit !found }'; then
                print_red "Installer mounts survive; preserving Debian stage: $ROOTFS_STAGE"
                exit 1
            fi
            rm -rf -- "$ROOTFS_STAGE"
            exit "$status"
        }
        trap cleanup_debian_stage EXIT
        tar --same-owner -xf "${distr_rootfs}.tar.gz" -C "$ROOTFS_STAGE"
    else
        ROOTFS_DIR="${BINARIES_DIR}/${distr_rootfs}"
        rm -rf "${distr_rootfs}"
        tar -xf "${distr_rootfs}.tar.gz"
    fi

    # Copy buildroot artifacts to rootfs
    local target_dir="${BINARIES_DIR}/../target"
    cp "${target_dir}/lib/modules" "$ROOTFS_DIR/lib" -r
    cp "${K230_SDK_ROOT}/buildroot-overlay/package/nonai2d/modprobe.d/nonai2d.conf" "$ROOTFS_DIR/lib/modprobe.d/" -r
    cp "${target_dir}/bin/sta.sh" "$ROOTFS_DIR/bin/"
    cp "${target_dir}/bin/k230_iomux.py" "$ROOTFS_DIR/bin/"
    cat "${target_dir}/etc/version/release_version" >> "$ROOTFS_DIR/etc/issue"

    echo '[ -f /etc/fw_env.config ] || echo "${bootddev}   0x1e0000 0x10000" >/etc/fw_env.config' >> "$ROOTFS_DIR/opt/mount_boot.sh"
    cp "${target_dir}/usr/bin/fw_setenv" "$ROOTFS_DIR/usr/bin/"
    cp "${target_dir}/usr/bin/fw_printenv" "$ROOTFS_DIR/usr/bin/"
    cp "${target_dir}"/usr/lib/libubootenv.so* "$ROOTFS_DIR/usr/lib/"

    if [ "$distname" = debian ]; then
        if [ -d "$target_dir/lib/firmware" ]; then
            mkdir -p "$ROOTFS_DIR/lib/firmware"
            cp -a "$target_dir/lib/firmware/." "$ROOTFS_DIR/lib/firmware/"
            if [ -d "$target_dir/lib/firmware/aic8800D80" ]; then
                mkdir -p "$ROOTFS_DIR/etc/modprobe.d"
                printf '%s\n' 'options aic8800_bsp aic_fw_path=/lib/firmware/aic8800D80' > "$ROOTFS_DIR/etc/modprobe.d/aic8800.conf"
            fi
        fi
    else
        # Preserve upstream Ubuntu extraction and service configuration.
        print_blue "Installing DEB packages..."
        for deb_file in "${BINARIES_DIR}/deb/"*.deb; do
            [ -f "${deb_file}" ] && dpkg -x "${deb_file}" "$ROOTFS_DIR/"
        done
        mkdir -p "$ROOTFS_DIR/etc/systemd/system/basic.target.wants/"
        ln -sf /etc/systemd/system/vvcam.service "$ROOTFS_DIR/etc/systemd/system/basic.target.wants/vvcam.service"
    fi

    if grep -qx 'BR2_PACKAGE_PYTHON_K230=y' "$BRW_BUILD_DIR/.config"; then
        # The k230 wheel is ABI-specific: Debian has cp313, Ubuntu has cp312.
        local dist_packages
        dist_packages="$(ls -d "$ROOTFS_DIR"/usr/local/lib/python3.*/dist-packages 2>/dev/null | head -1)"
        if [ -z "$dist_packages" ]; then
            print_red "Error: no /usr/local/lib/python3.*/dist-packages in $ROOTFS_DIR"
            exit 1
        fi

        local py_ver py_tag pkg_build_dir k230_wheel
        py_ver="$(basename "$(dirname "$dist_packages")")"
        py_tag="cp$(echo "$py_ver" | sed 's/^python//; s/\.//')"
        pkg_build_dir="${BINARIES_DIR}/../build/python-k230-1.0.0"
        k230_wheel="${pkg_build_dir}/dist/k230_python-1.0.0-${py_tag}-${py_tag}-linux_riscv64.whl"
        print_blue "${distname} uses ${py_ver}, installing ${py_tag} wheel"

        if [ ! -f "$k230_wheel" ] && [ "$py_tag" = cp312 ]; then
            print_blue "cp312 wheel missing, cross-building it..."
            "${K230_SDK_ROOT}/buildroot-overlay/board/canaan/k230-soc/distribution/cp312-support/build_k230_wheel_py312.sh" "$BRW_BUILD_DIR"
            chown -R --reference="${pkg_build_dir}/setup.py" \
                "${pkg_build_dir}/dist" "${pkg_build_dir}/build-py312"
        fi
        if [ ! -f "$k230_wheel" ]; then
            print_red "Error: ${k230_wheel} not found"
            exit 1
        fi
        unzip -o "$k230_wheel" -d "$dist_packages"
    fi

    # Copy additional libraries and binaries
    cp -fL "${target_dir}/usr/lib/libjpeg.so.9" "$ROOTFS_DIR/usr/lib/riscv64-linux-gnu/"
    cp -rfL "${target_dir}/usr/lib/libcrypt.so.2" "$ROOTFS_DIR/usr/lib/riscv64-linux-gnu/"

    mkdir -p "$ROOTFS_DIR/etc/vvcam"
    cp -rf "${target_dir}/etc/init.d/S41adb_mtp" "$ROOTFS_DIR/etc/vvcam/"
    cp -rf "${target_dir}/etc/umtprd" "$ROOTFS_DIR/etc/"
    cp -rf "${target_dir}/usr/sbin/umtprd" "$ROOTFS_DIR/usr/sbin/"
    cp -rf "${target_dir}/usr/bin/adbd" "$ROOTFS_DIR/usr/bin/"

    # Create /app symlink pointing to /root/app
    rm -rf "$ROOTFS_DIR/app"
    ln -s root/app "$ROOTFS_DIR/app"

    if [ "$distname" = debian ]; then
        local kernel_context="$ROOTFS_STAGE/kernel-context.json"
        if ! python3 "$K230_SDK_ROOT/packaging/debian/scripts/kernel-context.py" \
            --sdk-root "$K230_SDK_ROOT" --conf "$CONF" > "$kernel_context"; then
            print_red "Cannot generate kernel context; preserving the previous SD image"
            exit 1
        fi
        "$K230_SDK_ROOT/packaging/debian/scripts/install-rootfs-packages.sh" \
            "$ROOTFS_DIR" "$kernel_context" \
            "$K230_SDK_ROOT/packaging/debian/keys/cyberdeck-archive.asc"
    fi

    # Generate ext4 image for rootfs
    print_blue "Generating ext4 image..."
    local rootfs_size
    rootfs_size=$(( $(sudo du -sm "$ROOTFS_DIR" | cut -f1) + 300 ))
    mkfs.ext4 -F -d "$ROOTFS_DIR" -r 1 -N 0 -m 1 -L "rootfs" "${distr_rootfs}.ext4" "${rootfs_size}m"

    if [ "$distname" = debian ]; then
        cp sysimage-sdcard.img "$dist_img_name"
    fi

    # Resize the main image and embed the ext4 rootfs
    print_blue "Embedding rootfs into image..."
    local ext4_size=$(( $(wc -c < "${distr_rootfs}.ext4") ))
    local img_size=$(( $(wc -c < "${dist_img_name}") ))
    local total_size=$(( (ext4_size + img_size) / 1024 / 1024 + 2 ))

    truncate "${dist_img_name}" -s $((total_size + 1))M

    # Check and fix partition table
    echo -e "Fix\n" | parted  ---pretend-input-tty "${dist_img_name}" print

    # Find rootfs partition (last MBR partition) and resize it
    local rootfs_part_id
    rootfs_part_id="$(parted -s "${dist_img_name}" print | awk '/^[[:space:]]*[0-9]+/ { last = $1 } END { print last }')"
    parted -s "${dist_img_name}" resizepart "${rootfs_part_id}" "${total_size}MiB"



    # Embed ext4 image into the partition
    {  #add dist ext4 to image
        local rootfs_off_sect
        rootfs_off_sect="$(parted -s "${dist_img_name}" unit s print | awk '/^[[:space:]]*[0-9]+/ { last = $2 } END { print last }' | sed 's/s$//')"
        dd if=${distr_rootfs}.ext4  of=${dist_img_name} seek=${rootfs_off_sect} conv=notrunc
    }

    # Compress and create symlink
    cp "${dist_img_name}" "${dist_img_name}.bak"
    echo "Fix\n" | parted ---pretend-input-tty  "${dist_img_name}" print
    print_blue "Compressing image (this may take a while)..."
    gzip -f "${dist_img_name}"

    local final_name
    final_name=$(get_image_last_name "${distname}")
    rm -f "${final_name}"
    ln -s "${dist_img_name}.gz" "${final_name}"

    print_blue "Build successful: ${BINARIES_DIR}/${final_name}"
    chmod a+w "${distr_rootfs}.tar.gz" "${dist_img_name}.gz" "${final_name}"

    # Cleanup
    if [ "$distname" = ubuntu ]; then
        rm -rf "${distr_rootfs}"
    fi
    rm -f "${distr_rootfs}.ext4"
)
# Main execution
if [ "$(id -u)" -ne 0 ]; then
    print_red "Permission denied: you need root privileges. Example: sudo make debian"
    exit 1
fi

print_blue "Updating package lists..."
apt-get update
apt-get install -y  parted curl

# Determine download mirror

if [ -z "${BR2_PRIMARY_SITE}" ]; then
    BR2_PRIMARY_SITE="$(${K230_SDK_ROOT}/tools/download/get_fast_url.sh | cut -d',' -f1)"
fi
DISTR_DOWN_URI="${BR2_PRIMARY_SITE}/distribution"

print_blue "download mirror...DISTR_DOWN_URI=${DISTR_DOWN_URI},BR2_PRIMARY_SITE=${BR2_PRIMARY_SITE}"


# Process distribution type
case "${distribution_type}" in
    debian)
        if [ "$CONF" != k230_canmv_01studio_defconfig ]; then
            print_red "Signed Debian assembly supports only k230_canmv_01studio_defconfig"
            exit 1
        fi
        distribution_rootfs_replace "debian" "debian13" "${DISTR_DOWN_URI}/debian13.tar.gz" "c958b36f56d5e2a88446b03bb7dc6557"
        ;;
    ubuntu)
        distribution_rootfs_replace "ubuntu" "ubuntu24" "${DISTR_DOWN_URI}/ubuntu24.tar.gz" "899cbac7fca3aaab6b6e7adad11152bf"
        ;;
    debian_rootfs)
        debian_gen_rootfs
        ;;
    ubuntu_rootfs)
        ubuntu_gen_rootfs
        ;;
    *)
        print_red "Unknown distribution type: ${distribution_type}"
        print_yellow "Usage: $0 <debian|ubuntu|debian_rootfs|ubuntu_rootfs> <BRW_BUILD_DIR>"
        exit 1
        ;;
esac
