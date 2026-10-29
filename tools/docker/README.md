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

## GitHub Actions (cyberdeck)

`.github/workflows/build-cyberdeck.yml` builds the Buildroot and Debian images on
pushes to `cyberdeck`. It uses the existing `k230-buildroot` and `k230-debian`
images on a self-hosted runner; CI does not build or pull them.

To connect the build host to GitHub:

1. Open the repository's **Settings → Actions → Runners → New self-hosted runner**.
   Select Linux x64 and follow GitHub's download and configuration commands on
   the host containing both Docker images.
2. Add the custom label `k230`. The workflow requires the labels `self-hosted`,
   `linux`, `x64`, and `k230`.
3. Ensure the runner account can use Docker without `sudo` and accesses the
   Docker daemon containing those images. The Debian container runs with
   `--privileged` for mounts and RISC-V binfmt/QEMU.
4. Keep the runner online, preferably as a service using the runner's `svc.sh`.
5. Commit and push the workflow to `cyberdeck`, then open the repository's
   **Actions → Build Cyberdeck** page.

Successful builds publish a `cyberdeck-images-<commit SHA>` artifact containing
`sysimage-sdcard.img.gz` and `debian.img.gz`, retained for seven days. Each run
uses the runner's Actions checkout, not an existing development checkout.

Each job starts from a clean checkout without restoring previous `output/` or
`dl/` directories. It runs normal source prefetch (`make CONF="$CONF" dl`),
then the full Buildroot build in `k230-buildroot`, followed by privileged Debian
assembly in `k230-debian`. No prebuilt Buildroot host tools or completion stamps
are seeded.

The 01studio configuration excludes AI demos, NNCase, model downloads and
OpenCV, while retaining its other selected hardware and media packages.
Retained proprietary wireless sources must still be available, and Debian
assembly fetches the checksum-checked frozen `debian13.tar.gz` when absent.
No source or base-archive restore step bypasses those downloads.

The ABI identity hashes the entire selected board defconfig. Even a non-kernel
package-selection change needs matching publisher packages for the resulting
identity before Debian assembly. The frozen Debian base and dependency
selectors remain unchanged; Cyberdeck packages come from live signed APT.

The workflow also supports manual dispatch. GitHub requires the workflow on
the default branch for the **Run workflow** button; select `cyberdeck` when
dispatching.

Only run trusted code on this host. Docker access and privileged containers
expose the runner host; the workflow deliberately has no pull-request trigger.

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

### 5. Kernel Debian Package

For updating an existing Debian install without writing a full SD-card image,
build a local kernel package from the generated `Image`, selected DTB, boot
symlink, optional `fw_jump_add_uboot_head.bin`, and kernel modules:

```bash
# Incremental kernel rebuild, then package .deb
tools/build-kernel-deb.sh

# Force Linux re-extract/re-patch/rebuild first; use after editing Linux patches
tools/build-kernel-deb.sh --clean
```

Output: `output/$CONF/images/k230-*-kernel_*_riscv64.deb`.

Install on the target with `/boot` mounted:

```bash
sudo dpkg -i k230-*-kernel_*_riscv64.deb
sudo reboot
```

This package updates Linux boot files and `/lib/modules`; it does not update
raw U-Boot partitions.

### 6. Debian image packages

The Debian image installs `cyberdeck-service`, `k230-status-ready`,
`k230-sharp-drm` and `k230-kernel-abi` through the signed Cyberdeck APT archive
for its locally computed kernel ABI. The [Debian package guide](../../packaging/debian/README.md)
describes the trust configuration, frozen Debian dependencies and transaction
failure boundaries.

Package builds and archive signing belong to the separate
[cyberdeck-packages publisher](https://github.com/ardangelo/cyberdeck-packages).
There is no local unsigned repository or separate package/repository make
target for Debian assembly. Buildroot SDK `.deb` hook outputs are not image
APT inputs.

Run the ordinary image command after building Buildroot:

```bash
CONF=k230_canmv_01studio_defconfig
docker run --rm --privileged -v "$PWD:/src" k230-debian make CONF="$CONF" debian
```

A later build of the same commit may install newer matching-ABI Cyberdeck
packages. It does not automatically advance the frozen Debian base or
dependency snapshot.

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
