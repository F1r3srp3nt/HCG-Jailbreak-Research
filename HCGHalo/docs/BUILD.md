# Building HCG Halo

The toolchain matches HCG Vortex (`HCGVortex/docs/BUILD.md` on the Vortex branch). The pinned versions are the same,
so the two products build and package the same way.

## Dependencies

| Dependency | Purpose | Notes |
|---|---|---|
| [Theos](https://github.com/theos/theos) `8167f59` | build system, Logos, packaging | pinned in CI |
| Xcode (macOS) **or** a Theos Linux toolchain | compiler / linker | macOS needed for the native new-ABI arm64e build |
| Patched `iPhoneOS16.5.sdk` (theos/sdks `0222fd5`) | headers + private `Preferences` stub | `scripts/install-sdk.sh`, on every platform |
| `ldid`, `dpkg-deb`, GNU make ≥ 4, `python3` | signing, packaging, scripts | `brew install ldid dpkg xz make` |
| [allemande](https://github.com/p0358/allemande) | **Linux only**: arm64e ABI conversion | `g++ -std=c++20 -o allemande main.cpp` |
| Pillow | only to regenerate the icon (`scripts/make_icon.py`) | not needed to build |

## macOS (canonical)

```sh
cd HCGHalo
THEOS=~/theos scripts/install-sdk.sh       # once
THEOS=~/theos scripts/macos-build.sh       # build + validate with a full log in build-logs/
```

## Linux (test builds only)

```sh
export THEOS=~/theos   # with the L1ghtmann iOS toolchain in $THEOS/toolchain
scripts/install-sdk.sh
ALLEMANDE=~/allemande/allemande scripts/build.sh
```

Linux builds are converted with allemande. `validate.sh` warns about it, and they are **never** distributed.

## What `scripts/build.sh` does

1. Checks Theos and the SDK, and that the generated files are current.
2. Runs `make clean`, then `make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless`.
3. Runs `scripts/validate.sh` on the result, with `--require-new-abi` on macOS.

## Validation (`scripts/validate.sh`)

| § | Checks |
|---|---|
| 1 | host tests (C core, ASan/UBSan), generated files current, packaging-format tests |
| 2 | every `Root.plist` key exists in code; list values equal the code's identifier tables; slider ranges equal `HaloConfig.h` / `HaloProfiles.h`; master switch defaults off; `automatic` never accepted; every action or getter is implemented; `Info.plist` version and PreferenceLoader entry agree |
| 3 | control fields equal `./control`; id `com.hakmicapitalgroup.halo`; `iphoneos-arm64`; canonical file name; dependencies |
| 3a | `ar` members exactly `debian-binary`, `control.tar.gz`, `data.tar.gz`; each gzip fully decompressed with CRC and length checked; `dpkg-deb --fsys-tarfile` exit status and byte count |
| 4 | every file under `/var/jb`; the exact expected file list; packaged `Root.plist` is the generated one; modes 0755/0644, no setuid or world-writable files; ownership; plists parse and agree; control members exactly `control` and `postrm`; `postrm` deletes only Halo's own preference files and only on purge |
| 4a | `HCGHALO-VERSION:<version>` and a single `HCGHALO-BUILD:<commit>` in **both** binaries. A `-dirty` build ID fails with `--require-new-abi` |
| 5 | fat `arm64` + `arm64e`, compiled code, a code signature in every slice, minimum iOS 15.0, arm64e ABI (native required with `--require-new-abi`) |
| 6 | injection filter is SpringBoard only; expected interfaces and notification names are compiled in; the Settings bundle references no SpringBoard classes |
| 7 | no networking, process spawning, privilege, keychain, LocalAuthentication or tracking APIs, and no URLs |
| 8 | `dpkg -i` then `dpkg -r` into a scratch root: everything installed is removed |
| 9 | size, SHA-256, SHA-512 |

## Versioning

- The only version source is `Version:` in `control`, now `0.1.0~beta1`. The binaries and `CFBundleVersion` show
  it as `0.1.0-beta1`.
- `~` sorts before the release: `0.1.0~beta1 < 0.1.0~beta2 < 0.1.0~rc1 < 0.1.0`.
- **Every changed release gets a new version.** A version that has been handed off is never rebuilt with different
  bytes; a packaging-only fix becomes `~beta2`. The build ID (source commit) is compiled in, so two builds of
  different commits always differ.

## Build ID

`HALO_BUILD_ID` is the 12-character source commit, with `-dirty` added if `HCGHalo/` has uncommitted changes. It
appears in Settings (About › Build, and in the header) and in SpringBoard's status. CI builds from a clean checkout.

## CI

| Workflow | Runner | Does |
|---|---|---|
| `.github/workflows/hcg-halo.yml` | `macos-15` | host tests, generated files, format tests, **iOS Simulator runtime tests**, build + `validate.sh --require-new-abi`, uploads `hcg-halo-rootless-deb` (90 days) |
| `.github/workflows/hcg-halo-linux-check.yml` | `ubuntu-latest` | host tests with GCC and Clang, generated files, format tests, script syntax |
| `.github/workflows/hcg-halo-handoff.yml` | `ubuntu-latest` | assembles the HCG Repo handoff from a pinned build run (see `distribution/README.md`) |

Doc-only and `distribution/` changes do not trigger builds, so a pinned artifact remains the newest build of its
commit. None of these workflows publishes, signs or deploys anything.
