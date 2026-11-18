# Build

Same toolchain as HCG Halo and HCG Vortex (their `docs/BUILD.md`):

| Component | Version / source |
|---|---|
| Theos | pinned `8167f59de02fd32cf45b16bfcb1330dfa5c9974c` |
| SDK | patched `iPhoneOS16.5.sdk` from theos/sdks @ `0222fd5` (`scripts/install-sdk.sh`; private `Preferences.framework` stub) |
| `TARGET` | `iphone:clang:16.5:15.0` |
| `ARCHS` | `arm64 arm64e` |
| Package compression | gzip level 9 for every member (fixed with `:=`; `validate.sh` §3a rejects anything else) |
| Canonical compiler | Xcode's clang on `macos-15` (GitHub Actions) — native iOS 14+ arm64e ABI |

## Canonical (macOS / Xcode)

The **HCG Animation Center build** workflow (`.github/workflows/hcg-animationcenter.yml`): host tests, schema and
format tests, `scripts/build.sh` (build + `validate.sh --require-new-abi`), upload of the validated `.deb` as artifact
`hcg-animationcenter-rootless-deb`, and the Simulator runtime tests in a separate job. Only this artifact is
distributed. Locally on a Mac: `scripts/macos-build.sh` (preflight, full log under `build-logs/`).

## Linux (test builds only)

```bash
THEOS=~/theos ALLEMANDE=/path/to/allemande scripts/build.sh
```

The open-source toolchain emits the legacy arm64e ABI; `HAC_ABI_CONVERT=1` converts the staged binaries with
allemande and re-signs them. `validate.sh` then reports one warning per binary (*allemande-converted, test build
only*). This build was used during development to compile, package and validate on Linux before each CI run.

## Versioning

`./control` is the single source of the version. Both binaries embed `HCGANIMATIONCENTER-VERSION:<version>` and
`HCGANIMATIONCENTER-BUILD:<commit>` (`-dirty` with uncommitted changes). `validate.sh --require-new-abi` fails a dirty
build, so a distributable package always maps to one commit.

## Previews (Simulator)

`scripts/run-simulator-tests.sh` and `scripts/preview.sh` (workflow **HCG Animation Center preview**) build for the
iOS Simulator directly with `xcrun clang`; they never produce a package.
