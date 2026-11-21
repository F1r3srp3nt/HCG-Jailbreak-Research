# Compatibility

## Requirements

| | Value | Why |
|---|---|---|
| Package scheme | rootless (`/var/jb`), `iphoneos-arm64` | HCG Repo / Halo / Vortex toolchain |
| Slices | `arm64` + `arm64e` (fat), native iOS 14+ arm64e ABI from Xcode | A12+ SpringBoard and Preferences are arm64e |
| Minimum iOS | **15.0** (`firmware (>= 15.0)`, `LC_BUILD_VERSION` 15.0) | rootless floor; newest APIs used: `PHPickerViewController` (14), `UTType` (14), `UIButtonConfiguration` (15), `audiovisualBackgroundPlaybackPolicy` (15, guarded) |
| Depends | `mobilesubstrate (>= 0.9.5000)` (ElleKit), `preferenceloader`, `firmware (>= 15.0)` | |

**15.0 is a build setting, not a compatibility claim.** iOS versions outside 15–17 add an "untested" note to the
status. SpringBoard interfaces are checked at run time (`SPRINGBOARD_RESEARCH.md`); when one is missing, that surface
draws nothing and says why.

## Verification status (0.2.0~alpha1, development build)

| Item | Status |
|---|---|
| Host tests (C core incl. transforms 137,986 checks; schema 59; 1.0 core unchanged) | Pass |
| Simulator runtime tests (orientation, placements, packs, performance) | Pass, 236 checks (run 44885278113) |
| Package build + validation (`--require-new-abi`), CI and independent re-check | Pass, 0 failures / 0 warnings (commit `4fbebd2`) |
| HCG Animation Center for Mac readers on the iOS-exported pack | Pass (`validate_pack.py`, `hcgpack validate`) |
| Device installation / runtime | **Not performed** |

## Verification status (0.1.0~beta1)

See `TESTING.md` for the numbers and run links.

| Item | Status |
|---|---|
| Host unit tests (C core, schema, packaging format) | Pass (Linux GCC/Clang, macOS) |
| Simulator runtime tests (format, importer, renderer, preferences, AI rules) | Pass, 103 checks (run 44242604467) |
| Simulator preview (real tweak code + Settings in a stand-in SpringBoard; real Halo / Vortex / Nexus code) | Pass, 53 checks (run 44249973461) |
| Package build + validation (macOS / Xcode, `--require-new-abi`) | Pass, 0 failures / 0 warnings (run 44242604467, commit `2d642bd`) |
| Device installation | **Not performed** |
| Runtime behaviour on a device | **Not verified** |

## Orientation and transformation (0.2.0~alpha1) — format and app compatibility

| Item | 0.2 behaviour | Older readers |
|---|---|---|
| Presets with no transform (everything made by 0.1, the Mac app, or 0.2 without using the new controls) | Read and written **byte-identically** (`transform` / `sourceRotation` are only written when used) | unchanged |
| Presets with `layout.transform` (`formatVersion` stays 1) | rotation, flips, stretch, region in every mode | **0.1 tweak, kit 1.0, HCG Animation Center for Mac (current)**: accepted (unknown keys ignored, the 1.0 schema validates them); shown **upright, unflipped**, Stretch as **fill**, Fit ignores zoom/position. Never refused |
| `library.json` | version 2: entries stay plain v1 presets + `placements.lock-screen` | 0.1 reads it (Home settings; Lock own settings ignored) |
| `.hcgbackground` export | one placement, with its transform | readable by every preset reader (see row 2) |
| `.hcgpack` export | `app-background` (default, = Home) + `home-screen` + `lock-screen`; `preset.json` = default; sizes and SHA-256 for every file | Mac app / `hcgpack` / `validate_pack.py`: `app-background` is a known placement; the two new ids are ignored with a note. A placement with a transform shows upright on the Mac (row 2) |
| `.hcgpack` import (from the Mac app) | `home-screen`, else the default placement, else the first known (`app-background`, `desktop`, `loading-screen`, `banner`) → Home; `lock-screen` → Lock | — |
| C core | `HCGBackgroundCore.c/.h` 1.0 code unchanged; 1.1 is an appended section (`tests/test_core_compat.py` strips it and compares with the SHA-256s the Mac app vendors) | the Mac app's vendored 1.0 core stays valid; re-vendoring 1.1 is needed only for the Mac to *render* transforms |

### HCG Animation Center for Mac — notes for its maintainers

- To show iOS transforms on the Mac: re-vendor `HCGBackgroundCore.c/.h` 1.1 and the schema (additions only), read
  `layout.transform` in the Swift preset reader, and lay out with `hcgbg_layout_transformed`. Until then the Mac shows
  those placements upright (safe fallback).
- **Re-saving** a transformed preset or pack in the current Mac app **drops `transform`** (it writes only the keys it
  knows). Keep the iOS export if the transformation matters.
- `home-screen` / `lock-screen` could be added to the Mac's known placements as a minor addition (portrait canvas,
  same rules as `app-background`).

### Media handling

- No transcoding for orientation: the file's metadata is applied at display time, the editor's transform by Core
  Animation. Passthrough budget: long side ≤ 4096 px and ≤ 4.19 MP; larger clips are converted once, upright, aspect
  kept (previously: long side ≤ 2688 px, else boxed to 1920 × 1080).
- Unusual aspect ratios: the layout core is tested from 16 × 8192 (1:512) to 8192 × 16 and up to 8K, every rotation,
  flip and mode. Zoom/position round trips are exact except beyond the 1.0 crop minimum (0.1 of a side), where the
  region is clamped and stays valid.
- Mirrored orientation metadata (rare; some front-camera files) is honoured by AVFoundation as before; it is not
  recorded in the preset (`sourceRotation` records the quarter turn only).

## Surfaces

| Surface | Default | Status |
|---|---|---|
| Home Screen | On when a background is assigned; `SBHomeScreenWindow` index 0 | Implemented first; the window Halo already uses on the test phone |
| Lock Screen | **Off** (experimental); Lock wallpaper view, else Cover Sheet window | Implemented; placement on PosterBoard (iOS 16+) unconfirmed |

## Coexistence with HCG tweaks

| With | Expectation | Evidence |
|---|---|---|
| **HCG Halo** (screen-edge border) | Halo adds its border **on top** of `SBHomeScreenWindow`; the background is at **index 0** of the same window, so the border stays above it. Both hook `frontDisplayDidChange:` with `%orig` first (a chain). Halo's own overlay window (other *Show Halo on* modes, level 2050) is above everything. Disabling one never touches the other. | Simulator preview with Halo 0.3.0's **real controller** (checks order, both present, Halo unaffected by disabling) |
| **HCG Vortex** (page transitions) | Vortex transforms `SBIconListView` pages inside `SBRootFolderView`; the background is not inside the folder view, so it does not move with the pages, and Vortex's icons stay above it. No shared hooks. | Preview with Vortex 0.3.1's **real engine** on stand-in folder classes (checks pages transformed, background steady and still index 0 during a swipe) |
| **HCG Nexus** (panel) | The panel is above the Home Screen; the background keeps playing below it (it is still the Home Screen). | Preview with Nexus 0.3.1's **real panel** (preview platform) |
| Other wallpaper tweaks | Untested. Two video backgrounds would stack; the higher one wins | — |
| Tweaks that hook `frontDisplayDidChange:` | Hook chains are designed for this; `%orig` first | — |

**Not device-tested.** The preview runs the other projects' real code in a stand-in SpringBoard, not in SpringBoard.
Rows C1–C9 of `DEVICE_TEST_CHECKLIST.md` cover the device check.

## Performance and memory (design; not measured on a device)

- At most one decoder per surface, and the two surfaces are never on screen together; hidden decoders are freed after
  8 s and on memory warnings.
- Decode size limited to what the layout needs at screen scale (`preferredMaximumResolution`); 1 s forward buffer;
  still decoded at screen size.
- GIFs are hardware-decoded video, not bitmap frames.
- Battery: video decoding costs power; Low Power Mode shows the still by default. **Not measured.**
