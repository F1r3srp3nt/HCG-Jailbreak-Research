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
