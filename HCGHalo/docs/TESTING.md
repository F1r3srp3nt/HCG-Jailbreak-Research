# Testing HCG Halo

Each layer proves something different. **None of the automated layers proves anything about SpringBoard on a
device.** Only the device checklist does.

| Layer | Where | Proves | Does not prove |
|---|---|---|---|
| **Host unit tests** (`tests/test_core.c`, ~9.4 M checks, ASan + UBSan) | Linux CI (GCC and Clang), macOS CI, any machine with `cc` | The border path is closed, continuous, clockwise and inside the display, with the analytic perimeter, at insets 0–26 pt, every calibration extreme and 4,000 random geometries; the Bézier conversion stays on the arcs. Validation and clamping of every appearance value; gradient stops; Orbit and Circuit dashes fit the perimeter exactly; periods; render plans for Reduce Motion and Low Power; visibility decisions; profiles (exactly one implemented, none device-tested, planned and automatic unusable) | anything about drawing or iOS |
| **iOS Simulator runtime tests** (`tests/test_runtime.m`) | macOS CI (`scripts/run-simulator-tests.sh`) | For all 5 modes × 3 colour styles: the layer tree (mask/gradient only when needed, shape layers at screen scale), exactly the expected animations (Static: none; Breathing: opacity; Flow: rotation; Orbit: dash phase with period × segments = perimeter, direction; Circuit: pulses + one blinking node per landmark), rasterisation of Static/Breathing gradients, pause freezes the clock, the hidden plan draws nothing, teardown clears everything; landscape mapping puts the notch on the physical top edge; preview dash maths. **The overlay never wins hit-testing**: touches at the edges and centre reach the view beneath. Accessibility hidden. Preferences through real CFPreferences: defaults (off), clamping, `automatic` and planned profiles refused, presets save/rename/duplicate/delete/apply and uniqueness, Reset Appearance and Reset Calibration keep unrelated settings | SpringBoard classes, the hook, the Home Screen window, real compositing or power cost |
| **Show Halo on surfaces preview** (`preview/HaloSurfacesPreview.m`, `scripts/surfaces-preview.sh`) | macOS CI (*HCG Halo × Nexus preview* workflow), iPhone 11 Pro Max Simulator when available | The REAL `HaloController`, `HaloEdgeWindow`, overlay and renderer in a stand-in SpringBoard (an app whose `UIApplication` class is `SpringBoard`, an `SBHomeScreenWindow`, `SBApplication` objects, lock/blank Darwin notifications under preview names): app switching, lock, wake and screen-off under all five choices; live re-hosting between the Home Screen window and the overlay window; hidden ⇒ paused; Always ≡ Always Except When Screen Is Off; target Nexus-only draws no screen edge; 60 rapid transitions leave one overlay; the overlay window never takes a touch or becomes key | real SpringBoard windows and levels, the real Lock Screen, the real dark display, Low Power Mode, device power cost |
| **Packaging format tests** (`tests/test_deb_format.py`) | every CI job | the gzip-only check accepts only the intended layout | — |
| **`scripts/validate.sh`** | after every build; `--require-new-abi` in macOS CI | see `BUILD.md`: metadata, archive format, layout, permissions, version and build ID, Mach-O slices, signatures, ABI, injection filter, forbidden APIs, install and remove simulation | that the package installs on a real phone, or runs |
| **Device test** (`DEVICE_TEST_CHECKLIST.md`) | the iPhone 11 Pro Max, once its iOS and jailbreak are confirmed | installation, loading, behaviour, recovery and uninstall | other devices or iOS versions |

## Run locally

```sh
make -C tests test            # host tests (CC=clang or CC=gcc; one build directory per compiler)
make -C tests generated       # generated files are current
make -C tests deb-format      # packaging-format tests
scripts/run-simulator-tests.sh   # macOS + Xcode only
scripts/surfaces-preview.sh      # macOS + Xcode only: Show Halo on in a stand-in SpringBoard
scripts/validate.sh packages/<file>.deb [--require-new-abi]
```

## Not measured

No performance, battery or frame-rate measurement has been made. The design avoids per-frame CPU work (Core
Animation only, paused when hidden, rasterised where static). The GPU cost of a masked full-screen gradient while
animating, and its battery impact, are **unmeasured**. They are listed for the device test.
