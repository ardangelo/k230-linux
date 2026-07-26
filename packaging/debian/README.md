# K230 Debian packaging

This directory contains only human-authored package definitions and orchestration.
Sharp DRM source remains canonical at
`buildroot-overlay/package/sharp-drm/module/`; Buildroot and Debian compile that
same checkout independently.

`manifest.json` is the authoritative local package list.
`vendor-manifest.json` is the allowlist for downloaded vendor packages. A vendor
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

Downloaded vendor packages never enter the local package output directory.
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
