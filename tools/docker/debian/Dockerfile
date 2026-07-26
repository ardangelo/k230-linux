# K230 Debian package and image assembly environment.
#
# Extends k230-buildroot with native Debian packaging, repository, QEMU/binfmt,
# chroot, and image manipulation tools. Image assembly requires --privileged.
#
# Build (requires k230-buildroot image to exist):
#   docker build -f tools/docker/debian/Dockerfile -t k230-debian tools/docker/debian
#
# Run package/image assembly with binfmt and mount privileges:
#   docker run --rm --privileged -v $(pwd):/src k230-debian \
#       make CONF=k230_canmv_01studio_defconfig debian

FROM k230-buildroot:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates python3 \
        debhelper fakeroot dpkg-dev lintian \
        qemu-user-static binfmt-support kmod \
        wget curl rsync gzip \
        e2fsprogs parted util-linux \
        spi-tools \
    && rm -rf /var/lib/apt/lists/*
