# K230 Debian image packages

Debian images for `k230_canmv_01studio_defconfig` install packages from the signed
[Cyberdeck APT archive](https://ardangelo.github.io/cyberdeck-packages/).
The [cyberdeck-packages publisher](https://github.com/ardangelo/cyberdeck-packages)
owns Debian package builds, releases and archive signing. Image assembly does
not build a local repository or require a sibling publisher checkout.

## Build an image

Build the SDK image before replacing its root filesystem with Debian:

```bash
CONF=k230_canmv_01studio_defconfig
docker run --rm -v "$PWD:/src" k230-buildroot make CONF="$CONF"
docker run --rm --privileged -v "$PWD:/src" k230-debian make CONF="$CONF" debian
```

The containers need their existing toolchain and RISC-V binfmt support. Keep the
checkout mounted at `/src`, the path used by generated Buildroot Makefiles.
The Debian command requires root privileges and outbound HTTPS. Its extracted
rootfs uses an owned temporary directory under `TMPDIR` (default `/tmp`); use a
native POSIX filesystem there, not VMHGFS. Tarballs and ext4/SD image byte streams
remain in `output/<CONF>/images/`.

The output is `output/<CONF>/images/debian.img.gz`, with the uncompressed disk
retained as `debian.img.bak`. Ubuntu uses its separate baseline assembly path;
it does not run the Debian installer or require its context, key or package list.

## Matching the prepared kernel

Before extraction, `scripts/kernel-context.py` derives the prepared kernel's
full ABI identity from the selected SDK configuration, kernel inputs, generated
configuration, symbol versions and compiler. It is an unchanged copy of the
publisher's independent ABI tool. Successful generation atomically replaces
`output/<CONF>/debian/kernel-context.json`; failure stops assembly instead of
using an older context.

For ABI `H`, the installer selects suite `trixie-k230-H` at:

```text
https://ardangelo.github.io/cyberdeck-packages/
```

The image owns `/usr/share/k230/kernel-context.json` and
`/usr/share/k230/kernel-abi`. They are installed before package preinsts run.
The module and ABI marker guards reject a missing or different image ABI; their
exact dependency couples module and marker versions. A changed kernel ABI needs
matching published packages, not an edited identity file or another suite.

## Package selection and trust

APT selects the latest matching-ABI candidates without Cyberdeck version pins:

- `cyberdeck-service`: UART bridge daemon and JVM library.
- `k230-status-ready`: userspace-ready helper and enabled service.
- `k230-sharp-drm`: packaged module, depmod metadata and display configuration.
- `k230-kernel-abi`: the module's matching ABI marker.

Rebuilding the same SDK commit can therefore install newer Cyberdeck packages.
Service and readiness versions are independent; this is not a four-package
release-cohort lock. Assembly logs APT candidates and actual installed versions
with `dpkg-query`.

`keys/cyberdeck-archive.asc` is installed mode 0644 at
`/etc/apt/keyrings/cyberdeck-archive.asc`. The deb822 source's `Signed-By` selects
that certificate and primary fingerprint
`C0713A2A6C3A2279E125646BFD377548A4F82392`, including its signing subkey.
APT performs ordinary TLS, signature, freshness and package-hash checks; no
image-side release manifest or unsigned fallback is used.

The persistent `/etc/apt/sources.list.d/cyberdeck.sources` subscribes only to the
locally derived suite. `/etc/apt/preferences.d/cyberdeck` gives the four packages
priority 500 for that suite and all other Cyberdeck-origin packages priority -1.
This integration does not enable unattended upgrades or rewrite unrelated
persistent Debian sources.

## Frozen Debian assembly dependencies

The existing Debian base tarball and `distribution-packages.json` remain the
assembly inputs. The latter selects
`https://snapshot.debian.org/archive/debian/20250809T000000Z/`, trixie/main/riscv64,
with these package selectors:

- `network-manager=1.52.1-1`
- `kbd=2.7.1-2`
- `default-jre-headless=2:1.21-76`

Assembly resolves the complete Cyberdeck and distribution package transaction
against that snapshot and the live matching-ABI source, using fresh isolated APT
lists and cache. Only the historical Debian stanza disables `Check-Valid-Until`;
Cyberdeck retains normal expiry checks. A latest Cyberdeck package needing newer
Debian dependencies fails resolution rather than advancing the snapshot.

After update and simulation, APT downloads the authenticated transaction before
the installer removes the unowned baseline Sharp module. Installation then uses
`--no-download --reinstall` with the same package arguments and local lists, with
no intervening update. Authentication, expiry, dependency and download failures
leave the baseline module intact. A later dpkg failure does not promise module
rollback. The existing SD image is not replaced until rootfs installation and
ext4 creation succeed.

The installer restores its owned policy/mount changes and removes temporary
sources, lists and archives. It retains package ownership, ABI/module,
modules-load, `mono_cutoff=64`, Java/kbd, service and NetworkManager checks.

## Buildroot outputs are separate

Buildroot's Sharp source and recipe remain under
`buildroot-overlay/package/sharp-drm/`. SDK hooks may still generate `.deb` files
under `output/<CONF>/images/deb/`; those files are not Debian image APT inputs.
There are no `debian-packages` or `debian-repository` targets, vendor cache
provisioning steps, or local unsigned repository inputs. SDK demo packages such
as `k230-ffmpeg` and `k230-vvcam` are not selected by the Debian installer; ordinary
Debian packages already present in the frozen base remain unchanged.
