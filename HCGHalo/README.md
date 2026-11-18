# HCG Halo

**Animated neon edge lighting for the iPhone screen.** A rootless jailbreak tweak by Hakmi Capital Group.

> **0.3.0~beta1 (this branch): free public beta demo.** It adds **Show Halo on** (Home Screen only, one chosen
> app, everywhere, everywhere except the Lock Screen, or everywhere while the display is lit) and corrects the
> corner and notch size under Display Zoom. Simulator-tested; **real-device testing pending.**
>
> **0.2.0~beta1** (with HCG Nexus 0.3.1~beta1) is the current published candidate and stays unchanged.
>
> **Baseline: 0.1.0~beta1** (SHA-256 `c0a3301c…24c9af`). The owner reports it runs on their phone. That is not
> proof that every mode, device or compatibility case has passed. Its package is preserved unchanged. See
> [Status](#status).

HCG Halo draws a precise, glowing light border around the screen edge. The border follows the display's rounded
corners and the notch. By default it sits in its own view inside the Home Screen window; the
other *Show Halo on* choices draw it in HCG Halo's own overlay window. Either way it never receives touches and is
hidden from accessibility. It is separate from HCG Vortex and shares none of its code at runtime.

**Border target** (0.2.0~beta1): *Screen Edge* (the default, unchanged for existing users), *HCG Nexus Panel*
or *Both*. With HCG Nexus 0.3.1~beta1 (or another build with its border interface) installed, Halo reads the border definition that Nexus installs on
the phone. It then draws its border around the live Nexus panel, following its real shape, movement and size;
see [`docs/NEXUS.md`](docs/NEXUS.md). Without a compatible Nexus, the panel targets show *Requires compatible HCG
Nexus* and the screen edge works as before.

## Features (in code)

| | |
|---|---|
| **Modes** | Static · Breathing · Colour Flow · Orbit · Sci-Fi Circuit. All five are implemented and offered. |
| **Colours** | Single colour, multiple colours in bands, or a smooth gradient. 1–6 colours, colour picker, quick palettes |
| **Appearance** | Brightness, border thickness, glow strength, edge inset |
| **Animation** | Speed, direction (clockwise or counter-clockwise), colour spacing, Orbit segment count and length |
| **Presets** | Nine built-ins, including the panel looks *Nexus Signature*, *Reactor* and *Hologram* (visual styles only). Save, rename, duplicate and delete your own; apply with a confirmation |
| **Soft Pulse** | Optional gentle brightness swell on top of any mode except Breathing |
| **HCG Nexus panel** | Separate look or *Match Screen Edge*; its own presets, colours, thickness, glow, speed, direction and pulse; opening trace, fade with the panel and workspace pulse effects; *Reset Nexus Lighting*. Also reachable from Settings › HCG Nexus › Appearance › Halo border |
| **Show Halo on** (0.3.0~beta1) | Screen edge only: *Home Screen Only* (default, unchanged for existing users), *Selected App Only* (installed-app picker), *Always* (lit Lock Screen, Home Screen and apps), *Always Except Lock Screen*, *Always Except When Screen Is Off*. A fully off display can't show a border: every choice hides it and pauses rendering then. No Always-On display mode, so *Always* and *Always Except When Screen Is Off* behave identically. The HCG Nexus panel border is unaffected |
| **Device profile** | Manual selector. **iPhone 11 Pro Max** is implemented, but not yet device-tested. Other models are listed as *planned* and cannot be selected. *Automatic — Coming soon* is shown disabled |
| **Calibration** | Corner radius, notch width, notch depth and notch position. The notch is traced, or you can choose a straight edge |
| **Settings** | Dark HCG pane with a live preview, plus engine status, rendering state, version and build ID |
| **Safety** | Off after installation. Master switch, kill switch file, crash-loop guard and a fault fallback that removes the border |
| **Efficiency** | Core Animation only (no per-frame code in SpringBoard). Pauses and hides whenever the border is hidden: always when the screen is off, and on the Lock Screen or behind apps as *Show Halo on* says. Follows Reduce Motion; Low Power behaviour is configurable |
| **Privacy** | No account, payment, telemetry or network access. The validator checks the binaries for networking APIs |

Everything applies immediately, with no respring. Only the recovery mechanisms need one: the kill switch file, and
re-arming after the crash-loop guard has stopped Halo.

## Status

**0.3.0~beta1** (this branch): Show Halo on and Display Zoom geometry. Simulator-tested; device rows S0–S16 in
[`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md) are pending. The 375 × 812 pt investigation is in
[`docs/PROFILES.md`](docs/PROFILES.md).

**Candidate build (commit `e22527d`, macOS CI):**
`com.hakmicapitalgroup.halo_0.3.0~beta1_iphoneos-arm64.deb`, 431,720 bytes, SHA-256
`bd8a926667b8ebec5b2a200fc8d8a14bcd21a9a2919e0475ec97a479381defc5` (build run 44246501375, artifact
`hcg-halo-rootless-deb` 14402121490). Earlier 0.3.0~beta1 builds from this branch (`53f55bab…`, `5522441f…`) had
the two bugs below and must not be used.

| Check | Result |
|---|---|
| Host unit tests (Linux and macOS, ASan/UBSan) | pass, 9.4 M checks, including every Show Halo on choice × every input combination and the screen-fit cases |
| Build + `validate.sh --require-new-abi` | pass (run 44246501375) |
| iOS Simulator runtime tests | 446/446 (run 44246501375) |
| Nexus panel preview (with HCG Nexus 0.3.1~beta1) | 17/17 (preview run 44246501303) |
| Settings preview (both real Settings bundles; Show Halo on row, footer, app picker with 24 installed apps, choosing an app) | all checks passed, `failures=0` (run 44246501303) |
| Show Halo on surfaces preview (real controller in a stand-in SpringBoard, iPhone 11 Pro Max Simulator) | 51/51 (run 44246501303): app switching, lock, wake and screen-off under all five choices; live re-hosting; 60 rapid transitions; Always ≡ Always Except When Screen Is Off |
| Device | **not tested** — rows S0–S16 |

Found and fixed by the previews before this build: the overlay window never showed the border (its content
view was installed only once the window was shown), and Settings crashed once an app was chosen (a BOOL private
method read as an object).

**0.2.0~beta1**: build, validation, simulator and preview results are recorded in the pull request
and in [`docs/NEXUS.md`](docs/NEXUS.md#status). Device testing is pending.

**0.1.0~beta1** (baseline):

| Check | Result |
|---|---|
| Host unit tests (geometry, config, profiles: ~9.4 M checks, ASan/UBSan) | **Pass**: Linux (GCC, Clang) and macOS CI |
| iOS Simulator runtime tests (310 checks: renderer, overlay hit-testing, preferences) | **Pass**: macOS CI run [44062061609](https://github.com/F1r3srp3nt/HCG-Jailbreak-Research/actions/runs/44062061609) |
| Canonical macOS/Xcode build + `validate.sh --require-new-abi` | **Pass, 0 failures, 0 warnings**: run 44062061609, commit `ab439f8`, native arm64e ABI |
| Package | `com.hakmicapitalgroup.halo_0.1.0~beta1_iphoneos-arm64.deb`, 264,782 bytes, SHA-256 `c0a3301c9b38cdac812d439fb919c3a77bfcb7999c52ea174d799e88ba24c9af`, artifact `hcg-halo-rootless-deb` (ID 14317739735) |
| HCG-repo dry run with its own tools (Linux test build) | `inspect`, candidate import, `validate`, `build`, `smoke` and candidate `verify`: OK; promotion to stable refused |
| Installed on a device | **Yes** (owner-reported, iPhone 11 Pro Max) |
| Runtime on a device | **Runs** (owner-reported). Not every mode, setting or compatibility case is confirmed |

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
├── preview/                           Halo × Nexus preview app (simulator only; built with Nexus's real panel code)
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
- [`docs/NEXUS.md`](docs/NEXUS.md): the HCG Nexus panel border (contract, combinations, preview evidence)
- [`docs/RECOVERY.md`](docs/RECOVERY.md): turning Halo off, the kill switch, uninstalling
- [`docs/DEVICE_TEST_CHECKLIST.md`](docs/DEVICE_TEST_CHECKLIST.md): the first device test, step by step
- [`distribution/README.md`](distribution/README.md): the HCG Repo candidate kit
- [`CHANGELOG.md`](CHANGELOG.md)

## Licence

Proprietary freeware ([`LICENSE`](LICENSE)), the same model as HCG Vortex. The icon is **provisional** original
artwork (`scripts/make_icon.py`) until official HCG artwork exists.
