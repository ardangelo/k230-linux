# K230 Debian packaging

This directory contains only human-authored package definitions and orchestration.
Sharp DRM source remains canonical at
`buildroot-overlay/package/sharp-drm/module/`; Buildroot and Debian compile that
same checkout independently.

`manifest.json` is the authoritative local package list.
`vendor-manifest.json` is the allowlist for prebuilt package inputs. A vendor
entry with `install: false` is quarantined and is neither indexed nor installed.
Vendor checksums identify immutable inputs; changing a vendor package requires a
reviewed manifest update.

Generated state is configuration-specific and disposable:

- `output/<CONF>/debian/build/`: clean package staging trees;
- `output/<CONF>/debian/packages/`: locally built `.deb` files;
- `output/<CONF>/debian/repository/`: local APT repository and manifest;
- `output/<CONF>/debian/logs/`: package build logs;
- `output/<CONF>/debian/build-manifest.json`: source, ABI, toolchain, command,
  build-key, and artifact hashes;
- `output/<CONF>/vendor-debs/`: checksum-verified vendor package cache.

Prebuilt inputs never enter the local package output directory.
Repository assembly copies only declared, validated inputs into a newly created
repository. The repository is unsigned and is trusted only by the temporary
`file:` source used during local image assembly; it must not be distributed as a
network APT repository.

Binary builds stage canonical source and overlay `packages/<name>/debian/`.
Generated products, VCS metadata, and editor/agent state are excluded. Set
`RELEASE=1` to reject dirty canonical source; development builds record and
version dirty source explicitly.

The source format is `3.0 (quilt)`. The current pipeline builds binaries only.
A future source-package path must create an upstream archive from the same
canonical checkout, then combine it with the metadata; checked-in source copies
are not permitted.

## Core Cyberdeck package set

The Cyberdeck configuration builds `k230-sharp-drm` and its matching
`k230-kernel-abi` marker from canonical Sharp DRM source. It installs two
additional prebuilt packages:

- `k230-status-ready`: signals userspace readiness to the Cyberdeck kernel driver.
- `cyberdeck-service`: provides the UART bridge daemon and its JVM library.

The vendor manifest excludes face detection, HelloWorld, FFmpeg, MVX Player,
VG Lite, and VVCAM. Their presence in an old cache does not include them in the
new repository. This selection does not change the Buildroot configuration or
remove its SDK demo build targets. Standard Debian runtime dependencies remain
selected by `distribution-packages.json` and package dependency metadata.

## Providing prebuilt inputs

Both retained prebuilt entries have empty URL lists. Before repository assembly,
provide these exact files under `output/<CONF>/vendor-debs/`:

- `k230-status-ready.deb`
- `cyberdeck-service_0.1_riscv64.deb`

Their SHA-256 pins, package names, versions, and architectures are defined in
`vendor-manifest.json` and checked before indexing. A checksum-matching file in
`output/<CONF>/images/deb/` can also seed the vendor cache. A newly rebuilt
package with the same version is not a substitute for the pinned bytes; changing
an input requires a reviewed manifest update.

GitHub Actions checkout removes ignored build output, including this cache.
Files copied into a retained checkout unblock a manual build but do not provision
a fresh Actions run. The current workflow does not restore these prebuilt
inputs; clean runner builds must supply them after checkout.
