# Effects

| Effect | Identifier | Moves | Since |
|---|---|---|---|
| Reverse Slide | `reverse-slide` | whole pages | 0.1.0 |
| Vertical Rise | `vertical-rise` | whole pages | 0.1.0 |
| Vertical Fall | `vertical-fall` | whole pages | 0.1.0 |
| Custom Directions | `custom` | whole pages | 0.1.0 |
| **Tornado** | `tornado` | **individual icons** | 0.2.0 |
| iOS Default | `stock` | nothing | 0.1.0 |

Every effect is optional and selectable as the preset or per swipe direction.

## Tornado

During a Home Screen page swipe, the icons of the outgoing page lift out of the grid and form a three-dimensional
tornado: a tapered helical funnel (wide opening at the top, narrow tip at the bottom, several spiral turns around a
vertical axis). The funnel travels across the screen with the swipe and turns as you drag. The incoming page's icons
are interleaved on the same helix and unwind out of it into their exact grid positions.

![Tornado geometry at several points of a swipe](media/tornado-sheet.png)

`media/tornado-swipe.gif` shows a swipe, a pause, a reversal back to the start and a completed swipe. Both images are
drawn from the **real** geometry functions (`tests/build/tornado_frames` → `scripts/render_tornado_preview.py`) with
mock icons. **They are not captures of SpringBoard on a device.**

### How it is built

- **Geometry:** `src/VortexTornado.c`, pure C with no state. Every icon's offset, scale, depth, rotation and opacity is
  a function of the swipe progress. So pausing holds the formation, reversing unwinds it, and cancelling returns
  every icon to its grid position, with no animation state to get out of sync.
- **Choreography:** each page has its own travel u (outgoing: progress; incoming: 1 − progress).
  - u 0 → ~0.45: icons lift and gather into the funnel, top rows first.
  - Then they climb and swirl along it.
  - u 0.72 → 0.97: they fade.
  - At mid-swipe both pages are fully in the funnel together.
- **Engine:** `VortexIconEffect` (`effects/VortexEffect.h`) is an optional extension of the effect interface.
  - The page visual pins both pages to the screen centre.
  - The engine then sets, on each `SBIconView` of the outgoing and incoming pages, `layer.sublayerTransform`
    (offset, scale, optional spin), `layer.zPosition` (depth order within the page) and `layer.opacity`.
  - None of these change frames, centres, subview order, icon order or the saved layout, and none affect
    hit-testing.
- **Restoration:** each touched icon layer's original zPosition and opacity are recorded.
  - Every icon is restored when the swipe settles or is cancelled, the effect or tweak is disabled, the configuration
    changes, edit mode starts, the Home Screen leaves the window, Reduce Motion changes, or a fault trips the engine.
  - Any icon not updated in a frame is restored at the end of that frame: its page left the transition, or the icon
    was removed.
- **Not ordinary icons:** icon views wider or taller than 30 % of the page (widgets) do not join the funnel. They
  fade in place (`vortex_tornado_fallback_icon`).
- **Exclusions:** unchanged. Folders, Today View, App Library and edit mode stay stock.
- **Reduce Motion:** Tornado resolves to the stock animation while it is on. Page effects are unchanged.
- **Kill switch / master switch / launch guard:** unchanged. They act before any effect runs.

### Controls (Settings › HCG Vortex › Tornado)

| Control | Key | Range | Default |
|---|---|---|---|
| Tornado Intensity | `tornadoIntensity` | 0.1 – 1.0 | 0.7 |
| Spiral Radius (upper opening, × screen width) | `tornadoRadius` | 0.15 – 0.60 | 0.36 |
| Spiral Turns | `tornadoRotations` | 1 – 4 | 2.5 |
| Spin Direction | `tornadoDirection` | Follow Swipe / Clockwise / Counterclockwise | Follow Swipe |
| Depth & Scale (perspective, depth order, dimmer back side) | `tornadoDepth` | on / off | on |
| Spin Icons (rotate each icon about its own centre) | `tornadoIconSpin` | on / off | **off** (icons stay readable) |

The shared Speed, Easing and Reverse Animation settings also apply. Reverse flips the funnel's travel direction.

The section has a **live preview**: `VortexTornadoPreviewCell` runs the same C geometry on mock tiles with your current
settings. It shows a still frame when Reduce Motion is on.

### Verified so far

- **Host tests** (`tests/test_tornado.c`, in `make -C tests test` and `validate.sh`):
  - endpoints for both roles, 1–24 icons, every parameter set and both swipe directions;
  - continuity (frame-step halving) for every parameter set;
  - pause gives the identical formation; reversal unwinds;
  - cancel and rapid flicks driven through the real navigation state machine;
  - funnel shape at mid-swipe: taper, height, front and back depth, perspective, back-side dimming;
  - spin direction, travel direction, readable-by-default;
  - degenerate input.
- **Build:** compiles with `-Werror`; the package passes `validate.sh`.

### Not yet verified (needs a device)

- That `SBIconView`s are direct subviews of `SBIconListView` on the tested iOS version. If they are not, Tornado
  degrades to a centred cross-fade.
- Frame rate, smoothness and battery impact on real hardware.
- Icon taps opening the right app after a completed and after a cancelled swipe. Hit-testing is never modified,
  but this is not yet observed.
- Widgets, App Library and Today View behaviour on a device.
- Coexistence with HCG Halo or HCG Nexus. **Not tested; no compatibility is claimed.**
