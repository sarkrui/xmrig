# Local Cross-Platform Builds

This repository now includes local scripts to produce these release-style targets from macOS:

* `linux-amd64`
* `linux-aarch64`
* `macos-amd64`
* `macos-arm64`

## What the scripts do

* `scripts/build-target.sh <target>` builds one target and writes:
  * build output to `build/<target>/`
  * dependency artifacts to `scripts/deps/<target>/`
  * packaged archives and checksums to `dist/<target>/`
* `scripts/cross-build.sh [targets...]` is the macOS entry point:
  * macOS targets are built directly with Xcode/clang.
  * Linux targets are built inside the matching OrbStack VMs over SSH.

## Requirements

For macOS targets:

* Xcode command line tools
* `cmake`
* `autoconf`
* `automake`
* `glibtoolize`
* `pkg-config`
* `curl` or `wget`
* `perl`

For Linux targets from macOS:

* OrbStack running locally
* Existing Ubuntu VMs named `build-arm64` and `build-amd64`
* The VMs must already have the build toolchain installed:
  * `cmake`
  * `ninja`
  * `gcc`
  * `g++`
  * `curl`
  * `perl`
  * `pkg-config`
  * `autoconf`
  * `automake`
  * `libtoolize`

## Usage

Build all four targets:

```bash
./scripts/cross-build.sh
```

Build only the macOS archives:

```bash
./scripts/cross-build.sh macos-amd64 macos-arm64
```

Build a single target directly:

```bash
./scripts/build-target.sh macos-arm64
```

## Outputs

Each target produces:

* `dist/<target>/xmrig-<version>-<target>.tar.gz`
* `dist/<target>/xmrig-<version>-<target>.tar.gz.sha256`

The tarball contains:

* `xmrig`
* `LICENSE`
* `README.md`
* `version`
