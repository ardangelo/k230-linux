# K230 Debian image assembly environment; requires --privileged at runtime.
# Build: docker build -f tools/docker/debian/Dockerfile -t k230-debian tools/docker/debian
FROM k230-buildroot:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-user-static binfmt-support kmod \
    && rm -rf /var/lib/apt/lists/*
