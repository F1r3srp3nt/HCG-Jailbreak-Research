# HCG Vortex

**Advanced Home Screen Animation Engine** — Hakmi Capital Group
Version `0.1.0-alpha` · `com.hakmicapitalgroup.vortex` · rootless · free

HCG Vortex decouples *where you navigate* from *how the transition looks*.
Swipe left and you still land on the next Home Screen page — but the current
page can fall away downward while the next one drops in from above, slide
the opposite way, or move along any of eight directions.

## Status

| Stage | State |
|---|---|
| Source implemented | ✅ |
| Linux build + validation | ✅ open-source toolchain + allemande; `validate.sh` 0 failures, 1 expected warning |
| macOS (Xcode) compilation | ⏳ not verified — `macos-14` runner label rejected by GitHub, CI moved to `macos-15`; `scripts/macos-build.sh` ready for a local Mac |
| Package validated | ✅ `scripts/validate.sh` (one expected warning on Linux builds) |
| Device installation | ⏳ not performed — needs authorization |
| Runtime behaviour verified | ⏳ not performed |

See [docs/TESTING.md](docs/TESTING.md) for the device test plan.

## Features (v0.1.0)

- **Reverse Slide**, **Vertical Rise**, **Vertical Fall**, iOS Default, **Custom Directions**
- Separate effects for swipe-left / swipe-right; reverse toggle
- Duration (presentation smoothing), speed multiplier, intensity, 5 easing modes, page fade
- Live settings (no respring), engine status & diagnostics in Settings
- Safety: runtime compatibility gate, master switch, kill switch, exception
  circuit breaker, exact restoration of every modified layer; folders, Today
  View, App Library and edit mode stay stock

## How it works (one paragraph)

Two hooks on `SBFolderView` (`scrollViewDidScroll:`, `layoutSubviews`) call
SpringBoard's original implementation first, then read the page geometry,
compute each page's role and progress in a tested pure-C core, and set the
page's `layer.sublayerTransform` so it *appears* where the effect wants.
SpringBoard's content offset, page index, frames and hit-testing are never
modified. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/SPRINGBOARD_RESEARCH.md](docs/SPRINGBOARD_RESEARCH.md).

## Build

```sh
export THEOS=~/theos
scripts/build.sh            # macOS: native; Linux: needs ALLEMANDE=/path/to/allemande
make -C tests test          # math unit tests (any host)
scripts/validate.sh         # package validation
```
Full instructions and dependency list: [docs/BUILD.md](docs/BUILD.md).

## Install / remove

Install the `.deb` with Sileo or Zebra (or `sudo dpkg -i …`) and respring.
Remove from the package manager. Recovery options including SSH and the
kill switch: [docs/RECOVERY.md](docs/RECOVERY.md).

## Layout

```
HCGVortex/
├── Makefile, control, HCGVortex.plist (filter: SpringBoard)
├── src/          Tweak.x · VortexCore · VortexNavigation · VortexAnimationEngine
│                 VortexPreferences (shared) · VortexMath.c (pure C core)
├── effects/      VortexEffect.h · ReverseSlide · VerticalRise · VerticalFall · registry
├── preferences/  Settings bundle (PreferenceLoader)
├── layout/       DEBIAN/postrm (purge-only cleanup)
├── tests/        host unit tests for the math core
├── scripts/      build.sh · validate.sh · generate_root_plist.py · repo_entry.py
├── distribution/ HCG Repo listing kit (depiction, icon, screenshot placeholders)
└── docs/         ARCHITECTURE · SPRINGBOARD_RESEARCH · COMPATIBILITY · TESTING · RECOVERY · BUILD
```

Deviations from the suggested structure: `Tweak.x` instead of `Tweak.xm`
(Objective-C, no C++ runtime in SpringBoard); extra `VortexMath.c`,
`VortexPreferences.m`, `VortexSpringBoard.h`, `VortexLog.h` and an effect
registry file; `layout/` and `tests/` per Theos and testing needs.

## Privacy

No network connections, analytics, telemetry or automatic updates.
