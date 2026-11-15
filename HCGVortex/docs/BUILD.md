# Building HCG Vortex

## Dependencies

| Dependency | Purpose | Notes |
|---|---|---|
| [Theos](https://github.com/theos/theos) | build system, Logos, packaging | any current `master` |
| Xcode (macOS) **or** Theos Linux toolchain | compiler / linker | macOS needed for native new-ABI arm64e |
| iPhoneOS SDK | headers/stubs | Xcode's SDK on macOS; `theos/sdks` (16.5 used here) elsewhere |
| `ldid` | code signing | `brew install ldid` / Procursus build |
| `dpkg-deb`, `xz` | packaging | `brew install dpkg xz` |
| GNU make ≥ 4 | Theos | macOS: `brew install make` (`gmake`, or put `gnubin` on PATH) |
| `rsync`, `fakeroot`, `perl` | Theos internals | Linux |
| `python3` | validation, plist generator | |
| [allemande](https://github.com/p0358/allemande) | **Linux only**: arm64e ABI conversion | `g++ -std=c++20 -o allemande main.cpp` |
| C compiler (host) | unit tests | |

Runtime dependencies on device: ElleKit (provides `mobilesubstrate`),
PreferenceLoader. No other libraries (no Cephei, no Swift runtime).

## macOS (canonical)

```sh
export THEOS=~/theos                      # https://theos.dev/docs/installation-macos
cd HCGVortex
MAKE=gmake scripts/build.sh               # builds, packages, validates --require-new-abi
```

## Linux (test builds)

```sh
export THEOS=~/theos
# toolchain: Theos' installer, or
#   curl -L https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz \
#     | tar -xJ -C "$THEOS/toolchain"
# SDK: copy iPhoneOS16.5.sdk from https://github.com/theos/sdks into $THEOS/sdks
ALLEMANDE=~/allemande/allemande scripts/build.sh
```

Why allemande: open-source clang/ld64 emit the pre-iOS 14 arm64e ABI, which
Theos documents as unusable for rootless on A12+. allemande re-signs the
affected pointers after linking; the Makefile runs it on the *staged* binaries
(`before-package::`) and re-signs with ldid. It is a heuristic converter —
use the macOS build for anything distributed.

## CI

`.github/workflows/hcg-vortex.yml` builds on `macos-14` with Xcode, runs
`scripts/build.sh` (which requires the native new ABI) and uploads the `.deb`
as a workflow artifact. It never publishes or deploys.

## Make variables

| Variable | Default | Meaning |
|---|---|---|
| `THEOS_PACKAGE_SCHEME` | `rootless` | install prefix `/var/jb`, `iphoneos-arm64` |
| `ARCHS` | `arm64 arm64e` | fat binary |
| `TARGET` | `iphone:clang:latest:15.0` | latest SDK, iOS 15 deployment |
| `FINALPACKAGE` | unset | set to `1` for release version string `0.1.0~alpha` |
| `VORTEX_ABI_CONVERT` | unset | `1` = run allemande on staged binaries |
| `ALLEMANDE` | `allemande` | path to the converter |

## Versioning

Debian version `0.1.0~alpha` (the `~` sorts *before* `0.1.0`, so the final
0.1.0 upgrades cleanly). User-facing version string: `0.1.0-alpha`.
