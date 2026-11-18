# Changelog — HCG Vortex

## 0.3.0-beta1 (Debian version `0.3.0~beta1`)

Free experimental beta. **Not yet installed or tested on a device.**

### Added
- **Orbital**, **Warp**, **Holographic Layers**, **Circuit Flow** and **Magnetic Grid** icon effects, each optional and
  selectable as the preset or per swipe direction (see `docs/EFFECTS.md`).
- **Tornado controls:** funnel height, upper and lower radius, depth & perspective (0–1), travel (follow / against /
  centred), and presets Subtle, Classic Tornado (default) and Sci-Fi Vortex.
- **Settings:** a page per effect with a description, live preview, controls and Reset to Defaults; Appearance (accent
  colour, glow); Accessibility & Performance; "Reset & Diagnostics".
- **Engine:** generic per-icon effect class over one C dispatcher; 3-D tilt; Circuit Flow trace layers, removed on
  every restore path; Reduce Motion covers all icon effects.
- **Tests:** `tests/test_icon_effects.c` (shared contract and shape tests for all six effects). `validate.sh` checks
  every Settings pane.

### Changed
- Tornado's `tornadoDepth` is now 0–1 (was on/off), and Spiral Radius is now the exact upper radius.

### Unchanged
- Page effects, exclusions, kill switch, launch guard, and gzip packaging with Theos pinned to `8167f59`.

## 0.2.0-beta1 (Debian version `0.2.0~beta1`)

Free experimental beta. **Not yet installed or tested on a device.**

### Added
- **Tornado** effect, selectable as the preset or per swipe direction. The icons lift out of the grid into a tapered
  3-D helical funnel that travels with the swipe and turns as you drag; the next page's icons unwind out of it into
  their exact grid positions. Driven directly by the gesture: pause holds, reverse unwinds, cancel restores.
  Controls: intensity, spiral radius, spiral turns, spin direction (follow swipe / clockwise / counterclockwise),
  depth & scale, optional icon spin (off by default so icons stay readable). Live preview in Settings.
  See `docs/EFFECTS.md`.
- Engine: optional per-icon effect interface (`VortexIconEffect`). Icon layer state (sublayerTransform, zPosition,
  opacity) is recorded and restored on every exit path; icons not updated in a frame are restored that frame.
- Reduce Motion: per-icon effects use the stock animation while it is on.
- Tests: `tests/test_tornado.c`. Preview tooling: `tests/tornado_frames.c`, `scripts/render_tornado_preview.py`.
- `validate.sh` requires the binary to reference `SBIconView` and `setZPosition:`.

### Unchanged
- Reverse Slide, Vertical Rise, Vertical Fall, Custom Directions and iOS Default.
- Packaging: gzip members (`data.tar.gz`, `control.tar.gz`), Theos pinned to `8167f59`.

## 0.1.0-beta2 (Debian version `0.1.0~beta2`)

**Packaging compatibility candidate — installation fix not yet device-verified.**

Packaging-only rebuild. The tweak source, hooks, settings and dependencies are the same as 0.1.0~beta1.

### Why
- 0.1.0~beta1 failed to install on one phone (iPhone 11 Pro Max, iOS 17.4, Dopamine, Zebra, as recorded in
  HCG-repo). Download worked; unpacking failed with `dpkg-deb: error: <decompress> subprocess was killed by signal
  (Bus error: 10)`. Nothing was installed, so the tweak never ran.
- beta1's `data.tar.lzma` is lzma-alone with a 64 MiB dictionary (Theos's defaults). That file is intact and
  decompresses on Linux. **The cause of the phone failure is not confirmed.** It is under investigation
  (`docs/INSTALL-FAILURE-0.1.0-beta1.md`).

### Changed
- Package members are now all gzip (`control.tar.gz`, `data.tar.gz`), set in `Makefile` through Theos's supported
  `THEOS_PLATFORM_DEB_COMPRESSION_TYPE` / `_LEVEL`.
- CI pins Theos to `8167f59de02fd32cf45b16bfcb1330dfa5c9974c`, the commit that built beta1.
- The description starts with the candidate label above.

### Added
- `scripts/check_deb_format.py` and `validate.sh` section 3a: the members must be exactly `debian-binary`,
  `control.tar.gz` and `data.tar.gz`, each fully decompressed with CRC-32 and length checked, and
  `dpkg-deb --fsys-tarfile` must succeed with the same size.
- `tests/test_deb_format.py` (`make -C tests deb-format`, run in both CI workflows), including a beta1-shaped lzma
  case that must be rejected.
- `scripts/compare_debs.py`: accounts for every byte that differs between two builds.

### Not changed
- beta1's file and SHA-256 (`bb0af727…07673eea`) are kept exactly as they are. They are never rebuilt or relabelled.
- Runtime behaviour is **untested** on any device, for beta1 and beta2 alike.

## 0.1.0-beta1 (Debian version `0.1.0~beta1`)

First public beta release candidate: free and experimental. Device testing is
recorded in PR #1 / the release summary before publication.

### Added
- Startup safety: tested compatibility gate (`VortexCompatibility.m`), hook
  installation verified after `%init`, launch guard after 3 quick SpringBoard
  restarts, `-fobjc-arc-exceptions`.
- Device-test handoff (`docs/DEVICE_TEST_HANDOFF.md`) and read-only device
  report (`scripts/device-info.sh`).
- HCG-repo listing proposal: package metadata, BETA header, changelog, pinned
  import request.

### Changed
- Package name shows **(Beta)**; description starts "Free experimental beta."
- The version comes only from `control`; `validate.sh` fails if the binaries or
  the Settings bundle carry a different one (rebuild, never rename).
- Build SDK pinned to the patched iOS 16.5 SDK on every platform; Xcode compiles
  on macOS (native arm64e).

## 0.1.0-alpha (Debian version `0.1.0~alpha`)

First alpha. **Not yet verified on a device** — see docs/TESTING.md.

### Added
- Animation engine that separates real page navigation from presentation:
  SpringBoard's paging, page index, layout and touch handling are untouched;
  only page *contents* are transformed (`sublayerTransform`).
- Effects: **Reverse Slide**, **Vertical Rise**, **Vertical Fall**, plus
  iOS Default and **Custom Directions** (8-way direction matrix, independent
  incoming/outgoing directions).
- Per-swipe-direction effects, Reverse Animation, Duration (presentation
  smoothing), Speed Multiplier, Intensity (parallax + fade), five easing
  modes, optional page fade.
- Native Settings pane with HCG branding, live apply (no respring), engine
  status and compatibility diagnostics.
- Safety: runtime compatibility gate (no hooks unless every SpringBoard
  selector is present), master switch, file-based kill switch, exception
  circuit breaker, full transform restoration on settle/cancel/disable,
  stock behaviour for folders, Today View, App Library and edit mode.
- Host unit tests for the math core; package validation script; macOS CI.
