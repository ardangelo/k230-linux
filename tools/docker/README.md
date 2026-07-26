# K230 Linux Docker Build

Containerized build for K230 Linux (buildroot) and Debian image assembly.
No VM required — all image assembly operates on regular files.

## Requirements

- Docker (or Podman)
- Xuantie RISC-V toolchain tarball placed in `tools/docker/buildroot/`
  (already included: `Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2-20250410.tar.gz`)
- ~2GB disk for Docker images, ~10GB for a full build output

## Building the Docker Images

```bash
# 1. Buildroot image (must be built first — includes toolchain, ~1.5GB)
docker build -f tools/docker/buildroot/Dockerfile -t k230-buildroot tools/docker/buildroot

# 2. Debian image (extends buildroot)
docker build -f tools/docker/debian/Dockerfile -t k230-debian tools/docker/debian
```

## Shell Aliases (Optional)

Add to your shell profile to simplify commands below:

```bash
alias k230-br='docker run --rm -v $(pwd):/src k230-buildroot'
alias k230-deb='docker run --rm --privileged -v $(pwd):/src k230-debian'
alias k230-sh='docker run --rm -it -v $(pwd):/src k230-buildroot bash'
```

---

## Workflows

The source tree is always bind-mounted (`-v $(pwd):/src`), so buildroot's
output directory lives on the host and persists across container runs,
enabling incremental rebuilds.

All commands below are run from the k230-linux repo root.

### 1. Initial Full Build (First Time)

Builds buildroot (kernel, u-boot, opensbi, rootfs) then assembles the Debian SD card image.

```bash
CONF=k230_canmv_01studio_defconfig

# Step 1: Buildroot — cross-compile everything (~30 min first time)
docker run --rm -v $(pwd):/src k230-buildroot \
    make CONF=$CONF

# Step 2: Debian — overlay Debian rootfs onto buildroot image (~5 min)
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=$CONF debian
```

Output: `output/$CONF/images/debian.img.gz`

### 2. Kernel Edit & Rebuild

After modifying kernel source, config fragments, or device tree.

```bash
CONF=k230_canmv_01studio_defconfig

# Rebuild only the kernel + regenerate images (~5 min)
docker run --rm -v $(pwd):/src k230-buildroot \
    bash -c "make CONF=$CONF linux-rebuild && make CONF=$CONF"

# Reassemble Debian image with new kernel modules
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=$CONF debian
```

**Tip**: For kernel config changes, use the interactive shell:

```bash
docker run --rm -it -v $(pwd):/src k230-buildroot bash

# Inside container:
make CONF=k230_canmv_01studio_defconfig linux-menuconfig
make CONF=k230_canmv_01studio_defconfig linux-savedefconfig
```

### 3. Buildroot Base Environment Edit & Rebuild

After changing the buildroot defconfig, adding/removing packages, or modifying
buildroot overlay files (rootfs_overlay, post-build.sh, etc).

```bash
CONF=k230_canmv_01studio_defconfig

# Reconfigure and rebuild (buildroot is incremental — only changed packages rebuild)
docker run --rm -v $(pwd):/src k230-buildroot \
    make CONF=$CONF

# Force a full reconfigure from the defconfig:
docker run --rm -v $(pwd):/src k230-buildroot \
    bash -c "rm -f output/$CONF/.config && make CONF=$CONF"

# Then rebuild Debian if needed
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=$CONF debian
```

**Interactive defconfig editing:**

```bash
docker run --rm -it -v $(pwd):/src k230-buildroot bash

# Inside container:
make CONF=k230_canmv_01studio_defconfig menuconfig
make CONF=k230_canmv_01studio_defconfig savedefconfig
```

### 4. Debian Edit & Rebuild

For changes that only affect the Debian rootfs overlay (custom files,
additional packages, config tweaks) — **no buildroot rebuild needed**.

```bash
CONF=k230_canmv_01studio_defconfig

# Reassemble Debian image only (~2-3 min, reuses cached debian13.tar.gz)
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=$CONF debian
```

The Debian base rootfs (`debian13.tar.gz`) is cached in `output/$CONF/images/`.
Delete it to force a fresh download:

```bash
rm output/$CONF/images/debian13.tar.gz
```

### 5. First-class Debian Packages

The Debian package path independently recompiles Sharp DRM from
`buildroot-overlay/package/sharp-drm/module/`; it never copies the Buildroot
module into a `.deb`. A prepared matching kernel tree is required.

```bash
CONF=k230_canmv_01studio_defconfig

# Build or reuse the ABI-specific local packages.
docker run --rm -v $(pwd):/src k230-debian \
    make CONF=$CONF debian-packages

# Recreate the checksum-verified local APT repository.
docker run --rm -v $(pwd):/src k230-debian \
    make CONF=$CONF debian-repository

# Assemble the image and install packages through apt/dpkg in the RISC-V chroot.
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=$CONF debian
```

The package and repository targets do not need `--privileged`; image assembly
does. The installer mounts `binfmt_misc`, enables the packaged `qemu-riscv64`
handler, and verifies a RISC-V command before touching the staged rootfs. It
fails without the required container privilege and never falls back to payload
extraction. Rebuild the Debian container after changing its Dockerfile.

Sharp DRM-only iteration requires no Linux clean or rebuild while the kernel ABI
is unchanged:

```bash
# Edit buildroot-overlay/package/sharp-drm/module/, then:
docker run --rm --privileged -v $(pwd):/src k230-debian \
    make CONF=k230_canmv_01studio_defconfig debian
```

The content-derived build key includes module source and metadata, kernel
release/configuration and `Module.symvers`, and toolchain identity. Kernel ABI
changes therefore invalidate the module package. `sharp-drm-rebuild` remains
the separate Buildroot-image package path.

Generated files are under `output/$CONF/debian/`:

- packages: `packages/*.deb`;
- build provenance: `build-manifest.json`;
- repository and package provenance: `repository/`;
- logs: `logs/`;
- verified vendor cache: `output/$CONF/vendor-debs/`.

Inspect the repository and package:

```bash
dpkg-deb --info output/$CONF/debian/packages/k230-sharp-drm_*.deb
dpkg-deb --contents output/$CONF/debian/packages/k230-sharp-drm_*.deb
cat output/$CONF/debian/repository/repository-manifest.json
```

To update a running target, copy both matching local packages and install them
together so the exact ABI dependency remains satisfied:

```bash
sudo apt install ./k230-kernel-abi_*_riscv64.deb ./k230-sharp-drm_*_riscv64.deb
sudo depmod -a
```

Failures are intentional and actionable:

- missing generated kernel headers or `Module.symvers`: run `linux-rebuild`;
- kernel release/config hash mismatch: rebuild the Debian packages;
- RISC-V execution failure: register binfmt and rerun the image with
  `--privileged`;
- dependency failure: inspect `repository-manifest.json`; network APT sources
  are disabled for the local transaction;
- quarantined vendor package: fix its metadata/scripts and update the reviewed
  checksum instead of extracting its payload.

---

## Advanced: Regenerating the Debian Base Rootfs

The `debian13.tar.gz` is normally downloaded from Canaan's CDN. To regenerate
it from scratch (e.g., to add packages to the base), you need `debootstrap`
with RISC-V QEMU user-mode emulation:

```bash
# One-time host setup: register binfmt handlers for RISC-V
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Run rootfs generation (requires --privileged for chroot + mount)
docker run --rm --privileged -v $(pwd):/src k230-debian \
    bash -c "apt-get update && apt-get install -y qemu-user-static debootstrap debian-ports-archive-keyring && \
             bash buildroot-overlay/board/canaan/k230-soc/distribution/rootfs_debian_gen.sh"
```

Output: `debian13/` directory. Tar it up and place in `output/$CONF/images/`:

```bash
sudo tar -czf output/$CONF/images/debian13.tar.gz debian13
```

---

## Notes

- The Xuantie RISC-V toolchain is **baked into** the buildroot image
  (installed to `/opt/toolchain/`)
- The source tree is bind-mounted at `/src`, so `output/` lives on the host —
  incremental rebuilds work across container runs
- The container runs as root internally — this is required by buildroot's
  `FORCE_UNSAFE_CONFIGURE` and by `distribution.sh`'s root check
- Build output in `output/` is owned by root; use
  `sudo chown -R $(id -u):$(id -g) output/` if needed
- The old `tools/docker/Dockerfile` and `entrypoint.sh` are superseded by
  these images
