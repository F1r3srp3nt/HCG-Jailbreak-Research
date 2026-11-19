# Compatibility

## Verification status (0.1.0~beta1)

| Item | Status |
|---|---|
| Source implemented | Yes: five modes, Settings, presets and the iPhone 11 Pro Max profile |
| Host unit tests (C core) | Pass (Linux GCC/Clang, macOS) |
| iOS Simulator runtime tests (renderer, overlay, preferences) | Pass, 310 checks (macOS CI run 44062061609) |
| Package build + validation (macOS / Xcode) | Pass, 0 failures, 0 warnings (run 44062061609, commit `ab439f8`; native arm64e ABI `0x80000002`) |
| Device installation | **Not performed** |
| Runtime behaviour on a device | **Not verified** |

## Requirements

| Requirement | Value | Why |
|---|---|---|
| Package scheme | rootless (`/var/jb`) | the HCG Repo / Vortex toolchain; rootful is not built |
| Package architecture | `iphoneos-arm64` | rootless |
| Binary slices | `arm64` + `arm64e` (fat) | A11 and earlier use arm64; A12 and later load arm64e into SpringBoard |
| Minimum iOS | **15.0** (`firmware (>= 15.0)`, `LC_BUILD_VERSION` minos 15.0) | the rootless floor. Every API used exists on iOS 15 (table below) |
| Depends | `mobilesubstrate (>= 0.9.5000)` (ElleKit on rootless jailbreaks), `preferenceloader`, `firmware (>= 15.0)` | |

### Where the iOS 15.0 minimum comes from

These are the newest APIs the binaries use. Each exists on iOS 15.0, so 15.0 is set by the rootless scheme, not by an
API.

| API | Introduced | Used for |
|---|---|---|
| `kCAGradientLayerConic` | iOS 12 | gradient around the edge |
| `UIWindowScene`, `windowScene.screen`, `connectedScenes` | iOS 13 | finding windows and screens |
| `overrideUserInterfaceStyle` | iOS 13 | dark Settings pane |
| `UIColorPickerViewController` | iOS 14 | colour editing |
| `-colorPickerViewController:didSelectColor:continuously:` | iOS 15 | colour editing |
| `UITableViewStyleInsetGrouped`, `UIContextualAction` | iOS 13 / 11 | sub-pages |

**15.0 is a build setting, not a compatibility claim.** There is no upper bound in the package. Halo's private
SpringBoard dependencies (`SBHomeScreenWindow`, `SBIconController`, `-[SpringBoard frontDisplayDidChange:]`,
`_accessibilityFrontMostApplication`) are checked at runtime. If they are missing, Halo degrades as documented in
`ARCHITECTURE.md` and says so in Settings. On iOS versions outside 15–17, the status detail adds that the version is
untested.

## arm64e ABI

The same as HCG Vortex: A12 and newer devices on iOS 14+ require the new pointer-authentication ABI for SpringBoard.

- **macOS + Xcode** builds emit it natively (`cpusubtype 0x80000002`). Only this build is distributed;
  `validate.sh --require-new-abi` enforces it in CI.
- **Linux** test builds emit the legacy ABI and are converted with allemande. `validate.sh` reports a warning. They
  are never distributed.

The iPhone 11 Pro Max (A13) needs the arm64e slice.

## Devices

| Device | Profile | Device-tested |
|---|---|---|
| iPhone 11 Pro Max | **Implemented** (reference values; calibrate on the device) | **No** |
| Other iPhones in `data/profiles.json` | Planned: listed, not selectable | No |
| Any other device | None | No |

A profile list is **not** a support claim. See `PROFILES.md`. iPad is not considered.

## First test device: unconfirmed

The first test device is an **iPhone 11 Pro Max**. Its iOS version, build and jailbreak have **not been confirmed**
for HCG Halo, and nothing is assumed from other projects' tests. Before installation, record the real values with
the checklist in `DEVICE_TEST_CHECKLIST.md`, step 0.

## Private interfaces added in 0.3.0~beta1

Each is optional and guarded; when one is missing Halo degrades as stated, never guesses.

| Interface | Where | Used for | If missing |
|---|---|---|---|
| `-[SBApplication bundleIdentifier]` (via `frontDisplayDidChange:`) | SpringBoard | Selected App Only | Selected App Only draws nothing |
| `UIWindow` overrides `_shouldCreateContextAsSecure`, `_isSecure`, `_canAffectStatusBarAppearance`, `_canBecomeKeyWindow`, `_ignoresHitTest` | SpringBoard (`HaloEdgeWindow`) | show over the Lock Screen; never key, never hit, no status-bar influence | overrides are simply not called: the window stays under the Lock Screen; the public `canBecomeKeyWindow`, `hitTest:` and `userInteractionEnabled` still keep it inert |
| `LSApplicationWorkspace` `allInstalledApplications`, `LSApplicationRecord` enumeration, `LSApplicationProxy` | Settings (app picker) | list installed apps (read-only) | the picker says so and offers *Enter Bundle ID* |
| `+[UIImage _applicationIconImageForBundleIdentifier:format:scale:]` | Settings (app picker) | app icons | rows without icons |

## Coexistence

| With | Expectation |
|---|---|
| HCG Vortex | Independent: separate package, preferences and hook. Vortex hooks `SBFolderView` and Halo adds an overlay. Not tested together |
| Other Home Screen or edge-light tweaks | Untested. Two overlays may stack |
| Tweaks that add SpringBoard windows above apps or the Lock Screen | Untested. Halo's overlay window (level 2050) never takes touches, so stacking is visual only |
| Tweaks that hook `-[SpringBoard frontDisplayDidChange:]` | Hook chains are designed for this; Halo calls `%orig` first. Untested |
