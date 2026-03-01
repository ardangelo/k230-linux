# K230 Debian image assembly environment
#
# Extends the buildroot image with tools needed by distribution.sh:
# parted, mkfs.ext4, dpkg, wget — all operating on regular files,
# no --privileged or block device access required.
#
# Build (requires k230-buildroot image to exist):
#   docker build -f tools/docker/debian/Dockerfile -t k230-debian tools/docker/debian
#
# Run:
#   docker run --rm -v $(pwd):/src k230-debian \
#       make CONF=k230_canmv_01studio_defconfig debian

FROM k230-buildroot:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        # distribution.sh: downloads debian13.tar.gz, extracts .deb packages
        dpkg-dev wget curl rsync gzip \
        # distribution.sh: creates ext4 from directory, manipulates GPT image
        e2fsprogs parted \
        # distribution.sh: apt-get install spi-tools (baked in so it doesn't
        # pollute the host)
        spi-tools \
    && rm -rf /var/lib/apt/lists/*
