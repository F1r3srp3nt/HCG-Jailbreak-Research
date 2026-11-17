# HCG Halo

**Animated neon edge lighting for the iPhone Home Screen.** A rootless jailbreak tweak by Hakmi Capital Group.

> **0.1.0~beta1: free public beta demo, not yet device-tested.** It builds, packages and passes validation.
> It has **not** been installed or run on any iPhone yet. See [Status](#status).

HCG Halo draws a precise, glowing light border around the screen edge. The border follows the display's rounded
corners and the notch. It sits in its own view inside the Home Screen window, never receives touches and is hidden
from accessibility. It is separate from HCG Vortex and shares none of its code at runtime.

## Features (in code)

| | |
|---|---|
| **Modes** | Static · Breathing · Colour Flow · Orbit · Sci-Fi Circuit. All five are implemented and offered. |
| **Colours** | Single colour, multiple colours in bands, or a smooth gradient. 1–6 colours, colour picker, quick palettes |
| **Appearance** | Brightness, border thickness, glow strength, edge inset |
| **Animation** | Speed, direction (clockwise or counter-clockwise), colour spacing, Orbit segment count and length |
| **Presets** | Six built-ins. Save, rename, duplicate and delete your own; apply with a confirmation |
| **Device profile** | Manual selector. **iPhone 11 Pro Max** is implemented, but not yet device-tested. Other models are listed as *planned* and cannot be selected. *Automatic — Coming soon* is shown disabled |
| **Calibration** | Corner radius, notch width, notch depth and notch position. The notch is traced, or you can choose a straight edge |
| **Settings** | Dark HCG pane with a live preview, plus engine status, rendering state, version and build ID |
| **Safety** | Off after installation. Master switch, kill switch file, crash-loop guard and a fault fallback that removes the border |
| **Efficiency** | Core Animation only (no per-frame code in SpringBoard). Pauses and hides when the screen is off, when the phone is locked or when an app is in front. Follows Reduce Motion; Low Power behaviour is configurable |
| **Privacy** | No account, payment, telemetry or network access. The validator checks the binaries for networking APIs |

Everything applies immediately, with no respring. Only the recovery mechanisms need one: the kill switch file, and
re-arming after the crash-loop guard has stopped Halo.

## Status

| Check | Result |
|---|---|
| Host unit tests (geometry, config, profiles: ~9.4 M checks, ASan/UBSan) | Pass (Linux; also run in CI) |
| iOS Simulator runtime tests (renderer, overlay hit-testing, preferences) | Run in macOS CI: see the PR / `docs/TESTING.md` |
| Linux test build + `validate.sh` | Pass, with 0 failures and 2 expected warnings (legacy arm64e ABI converted with allemande; uncommitted tree) |
| Canonical macOS/Xcode build + `validate.sh --require-new-abi` | CI workflow **HCG Halo build**: see `distribution/handoff/` |
| Installed on a device | **No** |
| Runtime on a device | **Not tested** |

The first test device is an **iPhone 11 Pro Max**. Its iOS version and jailbreak are not yet confirmed and are
needed before installation: see [`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md).

## Layout

```
HCGHalo/
├── control, Makefile, HCGHalo.plist   package metadata, build, injection filter (SpringBoard only)
├── data/profiles.json                 device profiles: the only source; generates src/HaloProfiles.generated.c
├── src/                               tweak: C core (geometry, config, profiles) + Objective-C (renderer, overlay, controller)
├── preferences/                       Settings bundle (root pane, colours, presets, device profile, live preview)
├── layout/                            PreferenceLoader entry, postrm (purge-only cleanup)
├── scripts/                           build, validate, generate, simulator tests, icon, SDK install
├── tests/                             host tests (C), simulator runtime tests (Obj-C), packaging-format tests
├── docs/                              architecture, build, compatibility, profiles, testing, recovery, device checklist
└── distribution/                      HCG Repo kit: import manifest, listing, changelog, handoff, provisional icon
```

## Build

```sh
cd HCGHalo
THEOS=~/theos scripts/install-sdk.sh       # once: the pinned patched iPhoneOS16.5 SDK
THEOS=~/theos scripts/macos-build.sh       # macOS + Xcode: the canonical build (also what CI runs)
```

The build and every validation check are covered in [`docs/BUILD.md`](docs/BUILD.md).

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): how it works, the hook, visibility, rendering, safety
- [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md): iOS range and why, the interfaces used, and what is untested
- [`docs/PROFILES.md`](docs/PROFILES.md): device profiles, adding one, implemented compared with device-tested
- [`docs/TESTING.md`](docs/TESTING.md): what each test proves and what it does not
- [`docs/RECOVERY.md`](docs/RECOVERY.md): turning Halo off, the kill switch, uninstalling
- [`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md): the first device test, step by step
- [`distribution/README.md`](distribution/README.md): the HCG Repo candidate kit
- [`CHANGELOG.md`](CHANGELOG.md)

## Licence

Proprietary freeware ([`LICENSE`](LICENSE)), the same model as HCG Vortex. The icon is **provisional** original
artwork (`scripts/make_icon.py`) until official HCG artwork exists.
