# Building HCG Vortex

## Dependencies

| Dependency | Purpose | Notes |
|---|---|---|
| [Theos](https://github.com/theos/theos) | build system, Logos, packaging | any current `master` |
| Xcode (macOS) **or** Theos Linux toolchain | compiler / linker | macOS needed for native new-ABI arm64e |
| Patched iPhoneOS16.5.sdk | headers + private-framework stubs (`Preferences`) | `scripts/install-sdk.sh` (theos/sdks, pinned commit), **on every platform** — Xcode's public SDK can't link the Settings bundle |
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

Verified in CI (GitHub `macos-15`, Xcode 16.4). One-time setup on your own Mac:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # full Xcode, not Command Line Tools
sudo xcodebuild -license accept
xcrun --sdk iphoneos --show-sdk-version                           # must print a version
brew install ldid dpkg xz make
git clone --recursive https://github.com/theos/theos.git ~/theos
```

Then, from `HCGVortex/` (after cloning below): `THEOS=~/theos scripts/install-sdk.sh`.

Build, package and validate with a complete log:

```sh
git clone https://github.com/F1r3srp3nt/HCG-Jailbreak-Research.git
cd HCG-Jailbreak-Research && git checkout claude/optimistic-sagan-xsa3b2
cd HCGVortex
THEOS=~/theos scripts/install-sdk.sh       # once
THEOS=~/theos scripts/macos-build.sh
```

`scripts/macos-build.sh` checks the toolchain first, records it (macOS,
Xcode, SDK, clang, make, ldid, dpkg, Theos and project commits) at the top of
`build-logs/macos-build-<UTC timestamp>.log`, then runs `scripts/build.sh
messages=yes` (every compiler and linker command) and appends all output to
the same log. It exits with the build's status and prints the package path and
SHA-256, normally
`packages/com.hakmicapitalgroup.vortex_0.1.0~alpha_iphoneos-arm64.deb`.
`build.sh` runs `validate.sh --require-new-abi` on macOS, so success means the
arm64e slices carry Xcode's native iOS 14+ ABI.

## Linux (test builds)

```sh
export THEOS=~/theos
# toolchain: Theos' installer, or
#   curl -L https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz \
#     | tar -xJ -C "$THEOS/toolchain"
scripts/install-sdk.sh   # patched iPhoneOS16.5.sdk into $THEOS/sdks
ALLEMANDE=~/allemande/allemande scripts/build.sh
```

Why allemande: open-source clang/ld64 emit the pre-iOS 14 arm64e ABI, which
Theos documents as unusable for rootless on A12+. allemande re-signs the
affected pointers after linking; the Makefile runs it on the *staged* binaries
(`before-package::`) and re-signs with ldid. It is a heuristic converter —
use the macOS build for anything distributed.

## CI

* `.github/workflows/hcg-vortex.yml` builds on a GitHub-hosted macOS runner
  with Xcode and uploads the `.deb` as an artifact.
  - The first four jobs used `macos-14` and were cancelled before a runner
    was assigned; GitHub's annotation on each was `The configuration
    'macos-14-arm64-us-default' is not supported`. Moved to `macos-15`.
  - On `macos-15` (Xcode 16.4) the tweak compiled and linked for arm64 and
    arm64e, but the Settings bundle failed with `ld: framework 'Preferences'
    not found` because Theos picked Xcode's iOS 18.5 SDK. Fixed by pinning
    the patched iPhoneOS16.5.sdk (`scripts/install-sdk.sh`).
  - Two validator checks then failed on macOS only (binary-plist filter;
    Apple's `strings` missing import names). Fixed; run 43921760517 passed
    `validate.sh --require-new-abi` with 0 failures and 0 warnings and
    uploaded the `.deb` as artifact `hcg-vortex-rootless-deb`.
* `.github/workflows/hcg-vortex-linux-check.yml` runs the math unit tests on
  Ubuntu and passes.

Neither workflow publishes or deploys.

## Make variables

| Variable | Default | Meaning |
|---|---|---|
| `THEOS_PACKAGE_SCHEME` | `rootless` | install prefix `/var/jb`, `iphoneos-arm64` |
| `ARCHS` | `arm64 arm64e` | fat binary |
| `TARGET` | `iphone:clang:16.5:15.0` | pinned patched SDK, iOS 15 deployment |
| `FINALPACKAGE` | unset | set to `1` for release version string `0.1.0~alpha` |
| `VORTEX_ABI_CONVERT` | unset | `1` = run allemande on staged binaries |
| `ALLEMANDE` | `allemande` | path to the converter |

## Versioning

Debian version `0.1.0~alpha` (the `~` sorts *before* `0.1.0`, so the final
0.1.0 upgrades cleanly). User-facing version string: `0.1.0-alpha`.
