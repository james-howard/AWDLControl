# Vendored Sparkle distribution

`Sparkle/` contains the unmodified upstream Sparkle **2.10.0** binary
distribution, including its framework, command-line tools, sample app, debug
symbols, license and changelog. The framework is embedded and re-signed by the
existing Xcode build configuration.

- Release: <https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0>
- Archive: <https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz>
- Archive SHA-256: `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`
- Framework version/build: `2.10.0` / `2064`
- Minimum macOS version: `12.0`, below AWDLControl's `13.0` minimum.

The archive SHA-256 was checked against the digest published in the upstream
GitHub release asset metadata. The extracted framework passed
`codesign --verify --deep --strict`; upstream distributes it with an ad-hoc
signature, which is replaced by AWDLControl's signing identity during embedding.

## Updating

1. Download the official release archive and verify its published SHA-256.
2. Extract the full archive into a temporary directory, preserving symlinks and
   executable permissions.
3. Replace `Sparkle/` with the extracted distribution, including removal of files
   absent from the new release. Update the version and provenance above.
4. Verify the framework signature, architectures, and minimum system version.
5. Build AWDLControl with Xcode and test the updater and helper registration in
   a signed build before publishing an app release.

Do not edit `docs/appcast.xml` as part of a dependency-only update: it is signed
and describes already-published application releases. Generating a new appcast
requires the maintainer's signing key after creating the new application release.
