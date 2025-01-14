#!/bin/bash

default_env_file="$(dirname $(readlink -f "$0"))/../buildroot-overlay/board/canaan/k230-soc/default.env"
uboot_spl_file="$(dirname $(readlink -f "$0"))/../buildroot-overlay/boot/uboot/u-boot-2022.10-overlay/board/canaan/common/k230_spl.c"
rootfs_overlay="$(dirname $(readlink -f "$0"))/../buildroot-overlay/board/canaan/k230-soc/rootfs_overlay"
ddr_size="$1"
source "$(dirname $(readlink -f "$0"))/../.last_conf"


help()
{
    cat <<EOF
Usage: $0 <ddr_size:128/512/1024/2048>
Please provide the DDR size as an argument.
EOF
    exit 1
}

# 根据 DDR 大小设置 VPU 文件名
case "$ddr_size" in
    128)
        vpu_elf="vpu_h264enc_4k_loop_128M.elf"
        cpu_elf="ddr_dma_cpu_read_write_128m.elf"
        ;;
    512)
        vpu_elf="vpu_jpegenc_8k_loop_512MB.elf"
        cpu_elf="ddr_dma_cpu_read_write_20000000.elf"
        ;;
    1024)
        vpu_elf="vpu_jpegenc_8k_loop_512MB.elf"
        cpu_elf="ddr_dma_cpu_read_write_40000000.elf"
        ;;
    2048)
        vpu_elf="vpu_miniplayer_8k_loop_0x40000000.elf"
        cpu_elf="ddr_dma_cpu_read_write_80000000.elf"
        ;;
    *)
        echo "Unsupported DDR size: $ddr_size"
        help
        exit 1
        ;;
esac

# 其他逻辑可以在这里添加


# local default_env_file=${env_dir}/default.env;
blinux_org="$(cat ${default_env_file} | grep blinux= |  sed 's/^blinux=//' )"
echo  "${blinux_org}"

wget "https://ai.b-bug.org/~/wangjianxin/k230/bak/vpu/${vpu_elf}" -O "${vpu_elf}"
vpu="${vpu_elf%.elf}.bin"
/opt/toolchain/Xuantie-900-gcc-elf-newlib-x86_64-V2.6.1/bin/riscv64-unknown-elf-objcopy  -O binary -S  ${vpu_elf}   ${rootfs_overlay}/${vpu}
wget "https://ai.b-bug.org/~/wangjianxin/k230/bak/ddr_test_bin/${cpu_elf}" -O "${cpu_elf}"
cpu="${cpu_elf%.elf}.bin"
/opt/toolchain/Xuantie-900-gcc-elf-newlib-x86_64-V2.6.1/bin/riscv64-unknown-elf-objcopy  -O binary -S  ${cpu_elf}   ${rootfs_overlay}/${cpu}



#替换bootlinux 及 打开电源
blinux="ext4load mmc \${mmc_boot_dev_num}:2 0 /${vpu};boot_baremetal 1 0 0x8000000;"
bcputest="ext4load mmc \${mmc_boot_dev_num}:2 0x200000 /${cpu};cp.b 0x200000 0x80200000 0x100000;boot_baremetal 1 0x80200000 0x100000;"
sed -i  "/blinux=/s#blinux=.*#blinux=${blinux}#" "${default_env_file}"
echo "blinux_org=${blinux_org}" >>  "${default_env_file}"
echo "bcputest=${bcputest}" >>  "${default_env_file}"

#BR2_TARGET_ROOTFS_EXT2_SIZE="256M"
sed -i "/BR2_TARGET_ROOTFS_EXT2_SIZE=/s/BR2_TARGET_ROOTFS_EXT2_SIZE=.*/BR2_TARGET_ROOTFS_EXT2_SIZE=\"1024M\"/"  $(dirname $(readlink -f "$0"))/../output/${CONF}/.config
device_disable="device_disable()"
sed -i  "/${device_disable}/s#${device_disable}#//${device_disable}#" "${uboot_spl_file}"




cd "$(dirname $(dirname $(readlink -f "$0")))"
make uboot;
make
cd -

echo "DDR size is: $ddr_size"
echo "CONF is ${CONF}"
echo "blinux_org=${blinux_org}"
echo "bvputest=${blinux}"
echo "bcputest=${bcputest}"

#恢复以前代码
sed -i  "/${device_disable}/s#//${device_disable}#${device_disable}#" "${uboot_spl_file}"
sed -i  "/blinux_org=.*$/d" "${default_env_file}"
sed -i  "/bcputest=.*\$/d" "${default_env_file}"
linux_line="$(cat ${default_env_file}  | grep blinux= -n | cut -d: -f1)"
sed -i  "/^blinux=.*$/d" "${default_env_file}"
sed -i "${linux_line}i\blinux=${blinux_org}"  "${default_env_file}"

rm -rf ${rootfs_overlay}/${vpu}   ${rootfs_overlay}/${cpu}  ${vpu_elf}   ${cpu_elf}
