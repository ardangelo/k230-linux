# K230 buildroot cross-compilation environment
#
# Build:
#   docker build -f tools/docker/buildroot/Dockerfile -t k230-buildroot tools/docker/buildroot
#
# Run (source tree bind-mounted for incremental rebuilds):
#   docker run --rm -v $(pwd):/src k230-buildroot make CONF=k230_canmv_01studio_defconfig
#
# Interactive:
#   docker run --rm -it -v $(pwd):/src k230-buildroot bash

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        # Core build tools
        git sed make binutils build-essential diffutils gcc g++ bash patch \
        gzip bzip2 perl tar cpio unzip rsync file bc findutils wget curl \
        # Buildroot requirements
        libncurses-dev python3 python3-pip libssl-dev gawk cmake bison flex \
        bash-completion xz-utils \
        # Image assembly (post-image.sh: genimage, mkfs.ext4, fakeroot)
        fakeroot e2fsprogs parted \
        # Misc
        sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --break-system-packages pcpp 2>/dev/null \
    || python3 -m pip install pcpp

# Install Xuantie RISC-V toolchain
# https://kendryte-download.canaan-creative.com/k230/downloads/dl/gcc/Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2-20250410.tar.gz
COPY Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2-20250410.tar.gz /tmp/toolchain.tar.gz
RUN mkdir -p /opt/toolchain \
    && tar -xf /tmp/toolchain.tar.gz -C /opt/toolchain \
    && rm /tmp/toolchain.tar.gz

# Buildroot insists on not running as root for some configure scripts;
# this env var overrides that check.
ENV FORCE_UNSAFE_CONFIGURE=1
ENV BR2_TAR_OPTIONS="--no-same-owner"

WORKDIR /src
