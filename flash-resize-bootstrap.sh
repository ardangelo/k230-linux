#!/bin/bash

# Toolchain direct download:
# https://occ-oss-prod.oss-cn-hangzhou.aliyuncs.com/resource//1721095219235/Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V2.10.1-20240712.tar.gz
# mkdir -p /opt/toolchain
# tar -zxvf Xuantie-*.tar.gz -C /opt/toolchain
# make CONF=k230_canmv_defconfig

set -e

DEV=sdd
PART=2

if [ "$EUID" -ne 0 ]; then
	echo "Run as root"
	exit
fi

dd if=output/k230_canmv_defconfig/images/sysimage-sdcard.img of=/dev/$DEV bs=1M; sync
expect <<EOF
spawn parted /dev/sdd
expect "(parted)"
send "resizepart\n"
expect "Fix/Ignore?"
send "fix\n"
expect "Partition number?"
send "$PART\n"
expect "End?"
send "16GB\n"
expect "(parted)"
send "quit\n"
EOF

e2fsck -f /dev/$DEV$PART
resize2fs /dev/$DEV$PART

docker build -f debootstrap.Dockerfile -t debootstrap
docker run -it --rm --device=/dev/$DEV$PART --name debootstrap --privileged\
	debootstrap:latest /bin/bash -c " \
mkdir -p /mnt/root /mnt/debroot; \
debootstrap --arch=riscv64 \
	--include="openntpd,network-manager,build-essential,dkms,python3-spidev,wget,zip,device-tree-compiler,ssh,u-boot-tools,nano,less,dbus,systemd-timesync,ca-certificates,rsync,build-essential" \
	unstable /mnt/debroot; \
mount /dev/$DEV$PART /mnt/root; \
rm -rf /mnt/root/sbin /mnt/root/bin; \
mv /mnt/root/etc/init.d /mnt/root/root/init.d; \
rsync -av --exclude="/mnt/debroot/bin" --exclude="/mnt/debroot/lib" /mnt/debroot/ /mnt/root/; \
rsync -av /mnt/debroot/bin/ /mnt/root/bin/; \
rsync -av /mnt/debroot/lib/ /mnt/root/lib/; \
mount -o bind /dev /mnt/root/dev; \
mount -o bind /proc /mnt/root/proc; \
mount -o bind /sys /mnt/root/sys; \
chroot /mnt/root /bin/bash -c ' \
	systemctl enable systemd-timesyncd; timedatectl set-ntp true; \
	echo \"ca-certificates ca-certificates/activate_on_install boolean true\" | debconf-set-selections; \
	dpkg-reconfigure -f noninteractive ca-certificates; \
	update-ca-certificates; \
	echo "j" | passwd "$1" --stdin'; \
ln -sf /dev/null /mnt/root/etc/systemd/system/serial-getty@hvc0.service; \
umount /mnt/root; \
"
