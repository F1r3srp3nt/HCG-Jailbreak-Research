# HCG Vortex — Architecture

## Separation of concerns

The spec requires five independent concerns. Each lives in one place:

| Concern | Owner | Writes to SpringBoard? |
|---|---|---|
| 1. Actual page navigation | SpringBoard (unchanged) | — |
| 2. Visual transition direction | effects (`VortexEffect`) + direction matrix | no |
| 3. Animation geometry | `vortex_directional_visual`, `vortex_solve_page` | no |
| 4. Animation timing | easing, speed warp, presentation smoothing (`VortexMath`) | no |
| 5. Animation physics | reserved fields (`scale`, `rotationY`, `perspective`, spring easing slot) | no |

Only `VortexAnimationEngine` writes anything, and only to
`SBIconListView.layer.sublayerTransform` / `.opacity`.

## Components

```
                     ┌───────────────────────── SpringBoard process ─────────────────────────┐
  Settings.app       │                                                                       │
 ┌───────────────┐   │  Tweak.x (Logos)                                                      │
 │HCGVortexPrefs │   │   %hook SBFolderView                                                  │
 │ RootListCtrl  │   │     scrollViewDidScroll: → %orig → VortexCoreHandleScroll             │
 │ HeaderView    │   │     layoutSubviews       → %orig → VortexCoreHandleLayout             │
 └──────┬────────┘   │   %ctor → VortexCoreBootstrap(installer)                              │
        │            │                                                                       │
        │ CFPrefs    │  VortexCore ──── kill switch, compatibility gate, status, @try/@catch │
        ▼            │      │                                                                │
 com.hakmicapital…   │      ▼                                                                │
 group.vortex.plist ◄┼─ VortexPreferences (shared validator) → VortexConfiguration          │
        │            │      │ Darwin notify "…/preferences-changed"                          │
        └─ notify ──►│      ▼                                                                │
                     │  VortexAnimationEngine ── restoreAll / circuit breaker / display link │
                     │      │            │                                                  │
                     │      ▼            ▼                                                  │
                     │  VortexNavigation   VortexEffectRegistry → <VortexEffect>            │
                     │  (geometry, read-    Stock · ReverseSlide · VerticalRise ·           │
                     │   only)              VerticalFall · CustomDirectional               │
                     │      │            │                                                  │
                     │      └─────┬──────┘                                                  │
                     │            ▼                                                         │
                     │  VortexMath.c  (pure C: nav state machine, easing, solver)           │
                     └───────────────────────────────────────────────────────────────────────┘
```

Mapping to the spec's conceptual modules:

| Spec module | Files |
|---|---|
| HCGVortexCore | `src/VortexCore.{h,m}`, `src/Tweak.x`, `src/VortexLog.h`, `src/VortexSpringBoard.h` |
| HCGVortexNavigation | `src/VortexNavigation.{h,m}`, `vortex_nav_*` in `src/VortexMath.c` |
| HCGVortexAnimationEngine | `src/VortexAnimationEngine.{h,m}`, `vortex_compose_page` / `vortex_solve_page` / easing |
| HCGVortexEffects | `effects/*` (`VortexEffect.h` protocol, registry, 3 effects + stock + custom) |
| HCGVortexPreferences | `src/VortexPreferences.{h,m}` (compiled into both binaries) |
| HCGVortexSettings | `preferences/*` |

## Frame pipeline (per `scrollViewDidScroll:`)

1. **Gate** — enabled, not stock, not tripped, root folder view, its icon
   scroller, on screen, not editing.
2. **Measure** (`VortexNavigation`) — collect icon list views, page centres →
   page units; `actual = bounds.midX / pitch`.
3. **Present** — `presented` = `actual` (Duration 0) or chases it with
   exponential smoothing on a `CADisplayLink` (Duration > 0).
   *Gesture progress and visual progress are separate values.*
4. **Navigate** (`vortex_nav_step`) — base page, direction (forward = finger
   swipes left), raw progress 0…1, in-range flag (Today View / App Library →
   out of range → stock).
5. **Compose** (`vortex_compose_page`) for each page —
   role (outgoing / incoming / none) → effect visual → solver subtracts the
   scroll view's own placement so the page *appears* where the effect wants.
6. **Apply** — inside `CATransaction` with actions disabled;
   identity results restore the layer instead of writing identity.

### Why interrupted gestures can't leave a page stranded

* The state machine is driven by *position*, not by gesture events, so a
  grab during deceleration, a reversal past the start page, or a multi-page
  flick are all just new positions (tests: `test_navigation_state`,
  `test_continuity_sweep`).
* Effect contract: outgoing = identity at progress 0, incoming = identity at
  progress 1, the other page invisible at both ends. The base page hand-off
  happens exactly there, so role changes are invisible.
* Settled ⇒ every page solves to identity ⇒ every layer is restored.
* Bail-outs (window gone, edit mode, out of range, disabled, config change,
  exception) all call `restoreAll`.

## Timing model

* `progress` — raw, from geometry.
* `speed` — time-warp `t^(1/speed)` (endpoints fixed → no jumps).
* `easing` — linear, ease-in, ease-out, ease-in-out (cubic), sine.
* `duration` — presentation lag (seconds to ~99 % convergence). 0 = exact
  finger tracking. Gaps > 3 pages snap.
* `intensity` — outgoing travel distance; < 1 adds a compensating fade so the
  outgoing page is invisible at the hand-off.

## Direction matrix

`VortexDirection` has eight values (left, right, up, down and four diagonals),
persisted as strings (`"up-left"`, …) so the enum can grow. Incoming
("enters from") and outgoing ("exits to") are independent. Built-in effects
are rows in `vortex_builtin_directions`:

| Effect | Forward (swipe left) in / out | Backward (swipe right) in / out |
|---|---|---|
| Stock | right / left | left / right |
| Reverse Slide | left / right | right / left |
| Vertical Rise | down / up | down / up |
| Vertical Fall | up / down | up / down |
| Custom | user / user | user / user |

"Reverse Animation" negates every vector.

## Extending (v0.2.0+)

* **New effect** — class conforming to `<VortexEffect>` returning a
  `VortexPageVisual` (translation, opacity, and the already-composed `scale`,
  `rotationY`, `perspective`); register it in
  `-[VortexEffectRegistry registerBuiltins]`; add its identifier to
  `+validEffectIdentifiers` and to `scripts/generate_root_plist.py`.
  `scripts/validate.sh` fails if those drift apart.
* **Spring physics** — `VortexEasingReservedSpring` slot exists; implement it
  as a progress curve that still satisfies f(0)=0, f(1)=1.
* **Haptics** — hook point: base-page hand-off in `vortex_nav_step`
  (expose an event from `VortexNavigation`).
* **Composer / presets (v0.3.0)** — `VortexConfiguration` is immutable and
  built from a dictionary (`+configurationFromDictionary:`), which is the
  import/export format.
* Not implemented (by design for v0.1.0): particles, 3D effects, haptics,
  composer, Nexus integration.

## Threading

Everything runs on SpringBoard's main thread (scroll delegate, layout,
display link, Darwin notification callback). No background threads, timers
other than the display link (only while smoothing), or network activity.
