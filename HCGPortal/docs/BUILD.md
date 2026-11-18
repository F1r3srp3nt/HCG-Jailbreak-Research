# Building HCG Portal

The distributable package is built **only** by the *HCG Portal build* workflow on macOS with Xcode
(`.github/workflows/hcg-portal.yml`), the same toolchain as HCG Halo, Vortex and Animation Center:

| | |
|---|---|
| Runner | `macos-15`, Xcode's clang (native arm64e ABI, `cpusubtype 0x80000002`) |
| Theos | pinned `8167f59de02fd32cf45b16bfcb1330dfa5c9974c` |
| SDK | patched `iPhoneOS16.5.sdk` from theos/sdks `0222fd5413cf…` (`scripts/install-sdk.sh`) |
| Target | `iphone:clang:16.5:15.0`, `arm64 arm64e`, rootless |
| Package format | gzip `control.tar.gz` / `data.tar.gz`, level 9 (fixed in the Makefile; `validate.sh` §3a rejects anything else) |
| Version | `control` only (`0.1.0~beta1`), compiled into both binaries with the source commit as build ID |

```sh
cd HCGPortal
THEOS=~/theos scripts/install-sdk.sh      # once
THEOS=~/theos scripts/macos-build.sh      # macOS: build + validate --require-new-abi, timestamped log
```

`scripts/build.sh` checks Root.plist is generated (`scripts/generate_root_plist.py`), builds `package FINALPACKAGE=1`
and runs `scripts/validate.sh` (§1 host tests, §2 Settings ↔ code consistency, §3/3a metadata and gzip format, §4
payload and permissions, §4a version/build ID in both binaries, §5 Mach-O slices and ABI, §6 SpringBoard filter,
expected interfaces and **no passcode / unlock-bypass, notification-content or other-product preference reference**,
§7 no network/process/keychain/LocalAuthentication/URL, §8 dpkg install/remove simulation, §9 checksums).

Linux builds (with allemande ABI conversion) are for testing only and are never distributed.

Other workflows: *HCG Portal Linux check* (host tests with GCC and Clang, Root.plist, packaging-format tests, script
syntax) and *HCG Portal preview* (`scripts/preview.sh`: Simulator integration run with video and screenshots).
None of them publishes anything or touches a device.
