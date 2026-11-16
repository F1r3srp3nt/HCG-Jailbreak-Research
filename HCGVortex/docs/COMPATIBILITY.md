# Compatibility

## Verification status (v0.1.0-alpha)

| Item | Status |
|---|---|
| Target: iPhone 11 Pro Max (A13, arm64e), iOS 17.4, Dopamine rootless | **Not yet tested on device** |
| Source implemented | Yes |
| Math core | Unit-tested on host (2.2 M checks) |
| Build (Linux, open-source toolchain + allemande) | Successful, validated |
| Build (macOS, Xcode — canonical) | **Not yet verified.** `macos-14` CI jobs were rejected ("configuration 'macos-14-arm64-us-default' is not supported"); workflow moved to `macos-15`. Local `scripts/macos-build.sh` provided, not yet executed |
| Package validated (metadata, paths, slices, signatures, removal simulation) | Yes (`scripts/validate.sh`) |
| Device installation | Not performed (requires explicit authorization) |
| Runtime behaviour | Not verified |

## Requirements

| Requirement | Value |
|---|---|
| Package scheme | rootless (`/var/jb`) |
| Package architecture | `iphoneos-arm64` |
| Binary slices | `arm64` + `arm64e` (fat) |
| Deployment target | iOS 15.0 (rootless floor); behaviour gated at runtime |
| Depends | `mobilesubstrate (>= 0.9.5000)` (provided by ElleKit on Dopamine), `preferenceloader`, `firmware (>= 15.0)` |

## Jailbreak note — please confirm

As far as public information goes up to this project's knowledge, Dopamine's
published support range was iOS 15.0–16.x. The brief states the test device
runs **Dopamine on iOS 17.4**; please confirm the exact Dopamine build in use.
Nothing in HCG Vortex is specific to one jailbreak: it needs a rootless
`/var/jb` layout, a Substrate-compatible hooking library (ElleKit) and
PreferenceLoader.

## arm64e ABI (important for A12 and newer)

SpringBoard and Preferences on A12+ are arm64e and require the iOS 14+
pointer-authentication ABI.

* **macOS + Xcode builds** emit the new ABI natively → `cpusubtype 0x80000002`.
  This is the build intended for distribution.
* **Linux / open-source toolchains** emit the legacy ABI (`0x2`). Theos'
  documented workaround is **allemande**, which re-signs the pointers whose
  discrimination changed (ObjC `isa`, method lists, CFString). The subtype
  stays `0x2`. `scripts/validate.sh` reports this as a warning and fails a
  package whose arm64e slice was *not* converted.
* The code is written to minimise ABI surface: Objective-C only (no C++, no
  Swift — allemande does not support Swift), no static blocks in the tweak
  except UIKit-facing alert handlers in the Settings bundle.

## iOS versions

| iOS | Expectation |
|---|---|
| 17.4 | Primary target. Selectors match the 17.0.3 dump; runtime gate confirms. |
| other 17.x | Expected to behave like 17.4 if the gate passes; untested. |
| 15.x – 16.x | Classes/selectors historically present; gate decides; untested. Status shows a "outside the v0.1.0 test target" note. |
| 18+ | Unknown. Gate fails safely (stock Home Screen) if anything changed. |

## Device form factors

* iPhone only tested conceptually; iPad Home Screen uses the same classes but
  different page spacing/dock geometry — untested.
* Page pitch is measured from the actual page layout, so different screen
  sizes need no constants.

## Tweak conflicts (likely)

Any tweak that transforms Home Screen pages during scrolling will conflict
(e.g. Cylinder-family tweaks, page-transition effect tweaks). Vortex refuses
to modify a page layer whose `sublayerTransform` is already non-identity, so
it backs off rather than fighting — but install only one page-transition
tweak at a time. Home Screen layout tweaks (grid size, hidden labels) should
be compatible because Vortex measures geometry instead of assuming it.

## Unsupported / out of scope in v0.1.0

Folders (stock paging, by design), Today View and App Library transitions
(stock), edit (jiggle) mode (stock), landscape Home Screen (untested),
iPad (untested).
