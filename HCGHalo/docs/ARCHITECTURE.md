# HCG Halo architecture

## Overview

```
SpringBoard process                                         Settings app (Preferences)
───────────────────                                         ──────────────────────────
%ctor ── HaloControllerBootstrap                            HaloRootListController (PSListController)
  │      kill switch? interfaces present? launch guard?       ├─ HaloHeaderView: live preview (HaloRenderer)
  │                                                           ├─ HaloColoursController
  ├─ Darwin: …/preferences-changed ◄────────── writes ──────  ├─ HaloPresetsController
  ├─ Darwin: …/status-request ◄───────────── asks status ──── ├─ HaloProfileController
  │          …/status-updated ──────────────────────────────► └─ reads status
  │
  ├─ HaloController (main thread)                 HaloPreferences.m  ◄── shared validator, presets, status
  │    ├─ finds the Home Screen window             HaloConfig.c       ◄── shared pure C: appearance, plans, visibility
  │    ├─ HaloOverlayView (non-interactive)        HaloGeometry.c     ◄── shared pure C: border path
  │    │    └─ HaloRenderer (Core Animation)       HaloProfiles*.c    ◄── shared pure C: device profiles
  │    └─ observers: screen blank, lock state, Reduce Motion, Low Power, window hidden
  │
  └─ the one hook: -[SpringBoard frontDisplayDidChange:]  (%orig first; "is an app in front?")
```

Preferences are stored with CFPreferences in the domain `com.hakmicapitalgroup.halo`
(`/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.plist`). SpringBoard writes its status to
`com.hakmicapitalgroup.halo.status`. Both processes compile the same validator, so a value is either valid in both
or replaced by its default in both.

## Where the border lives

HCG Halo does **not** hook any Home Screen, gesture, touch or accessibility code. After SpringBoard finishes
launching, it looks for the Home Screen window:

1. a window of class `SBHomeScreenWindow`, among the connected window scenes' windows and `UIApplication.windows`;
2. otherwise, the window of `+[SBIconController sharedInstance]`'s view.

It adds one `HaloOverlayView` there, covering the window. If neither exists on an iOS version, it does nothing and
Settings reads *Incompatible*. If the window isn't found within 30 s (15 attempts, 2 s apart), it reports the same.
If SpringBoard rebuilds the window later, the overlay notices that it left the window and looks again.

With **Show Halo on: Home Screen Only** (the default, and the only choice before 0.3.0~beta1) the overlay is inside
the Home Screen window, so the border appears only on the Home Screen. The Today View, App Library, Spotlight and
open folders belong to that window, so the border also shows over them. **These sub-pages have not been checked
separately.**

### Show Halo on (0.3.0~beta1)

The other choices draw beyond the Home Screen, so the overlay moves to HCG Halo's own window,
`HaloEdgeWindow` (`src/HaloEdgeWindow.m`):

- created on SpringBoard's main window scene (the Home Screen window's scene, or the foreground scene on the main
  screen), sized to the screen, level 2050 (above system alerts);
- never interactive: `userInteractionEnabled = NO`, `-hitTest:` returns `nil`, never key, never affects the status
  bar, hidden from accessibility; its root view declines touches too;
- asks for a secure context (private overrides `_shouldCreateContextAsSecure` / `_isSecure`) so it can be shown
  above the Lock Screen. If UIKit stops calling them, the window simply stays under the Lock Screen;
- **hidden whenever the border is hidden**, so a hidden border costs no compositing.

Changing the choice re-hosts the overlay at once (Home Screen window ↔ overlay window); no respring. The HCG Nexus
panel border never uses this setting: it lives inside the Nexus panel and follows the panel's own visibility.
**Device behaviour (levels relative to the real Lock Screen, Control Center, the App Switcher, screenshots) is not
verified.**

### Never intercepting touches or accessibility

`HaloOverlayView` (`src/HaloOverlayView.m`):

- `userInteractionEnabled = NO`, so UIKit hit-testing skips the view and its subtree;
- `-hitTest:withEvent:` returns `nil` and `-pointInside:withEvent:` returns `NO`;
- no gesture recognisers, `canBecomeFocused`/`canBecomeFirstResponder` return `NO`;
- `isAccessibilityElement = NO` and `accessibilityElementsHidden = YES`, so VoiceOver, Switch Control and Full
  Keyboard Access never see it;
- `layer.zPosition` keeps it drawn above Home Screen content. Hit-testing ignores `zPosition`.

`tests/test_runtime.m` checks every point of this in the iOS Simulator. A touch at the screen edge reaches the view
underneath, never the overlay. That is a UIKit test, not a SpringBoard test.

### Orientation and the notch

The border path is built in the screen's **fixed portrait** coordinate space (`UIScreen.fixedCoordinateSpace`).
The overlay converts three points from that space into its own, which gives one affine transform. The notch
therefore stays on the physical top edge whatever the interface orientation, and the conic gradient is rotated with
the display. If the Home Screen window does not rotate, the transform is the identity and nothing changes.

## The border path (`src/HaloGeometry.c`)

The display outline is a rounded rectangle with a notch, taken from the device profile plus calibration. The
light's centre line is `offset = inset + thickness / 2` points inside the edge.

- **Convex corners** (screen corners, the notch's top flares) with boundary radius ρ have their centre at max(ρ, d)
  and radius max(ρ, d) − d. A radius of 0 gives a sharp corner, which the round line join softens.
- **Concave corners** (the notch's bottom corners) keep their centre and grow to radius ρ + d.
- **Deep insets.** Once the inset is deeper than the notch's straight sides, the top edge meets the bottom-corner
  circle directly. This is the exact offset curve, so the dip keeps the notch's depth.
- **Straight Edge** mode and profiles without a cutout run straight along the top edge.

The path runs **clockwise on screen**. Arcs are stored as centre, radius and angles and converted to cubic Béziers
(at most 90° per piece) in C. Core Graphics' arc-direction convention is therefore never involved. Landmarks (corner
midpoints, notch points and edge midpoints) place the Sci-Fi Circuit nodes.

The host tests check closure, continuity, the analytic perimeter and orientation. They also check that the path
stays inside the display at offsets from 0 to 26 pt, at every calibration extreme, and across 4,000 random
geometries.

## Rendering (`src/HaloRenderer.m`)

The renderer is shared by SpringBoard and the Settings preview. It uses **Core Animation only**. Every animation
runs in the render server, so SpringBoard does no per-frame work, no `drawRect:` and no timers.

```
root (opacity = brightness; Breathing animates it)
├─ colourHost (mask = maskLayer)                  ← gradient styles only; one offscreen pass
│   └─ conic CAGradientLayer (Colour Flow rotates it)
│   maskLayer: glow strokes (3, widest first) + core stroke, white with alpha
└─ "hot core": a thin white stroke over the core (neon-tube look)
```

A **single colour** strokes the shape layers in that colour directly: no mask, no gradient, the cheapest tree.
**Static** and **Breathing** with a gradient rasterise the masked subtree once (`shouldRasterize`), so a frame only
composites a cached bitmap, with only its opacity changing for Breathing.

| Mode | What moves | How |
|---|---|---|
| Static | nothing | no animations at all |
| Breathing | brightness 100% ↔ 20% of the setting | `opacity`, ease-in-out, autoreverse, 4 s / speed per cycle |
| Colour Flow | the palette travels around the edge | conic gradient `transform.rotation.z` (additive), 8 s / speed per lap. A single colour flows as a bright-to-dim band |
| Orbit | 1–4 segments, each a comet: a bright head with glow and two fading tail stages | `lineDashPhase` on dashed strokes. dash + gap = perimeter / segments exactly, so the loop is seamless; one lap takes 6 s / speed |
| Sci-Fi Circuit | dim trace, irregular circuit segments drifting slowly, fast pulses with glow, and blinking "via" nodes at corners and notch points | dash phase (the pattern is scaled to fit the perimeter exactly); per-node `opacity` keyframes, out of step |

The direction setting reverses the dash phase and the gradient rotation. Colour Spacing repeats the palette 1–4
times around the edge.

**Pause.** `-setPaused:` freezes the root layer's clock (`speed = 0`, keeping `timeOffset`, as in Apple's
QA1673). A hidden overlay is also paused, so it costs no animation work. Resuming continues from the same phase.

**Rebuilds** happen only when the appearance, geometry or plan changes. All of these are user actions or rotations.

## Visibility (`HaloController.m`, `halo_surface_block`)

Per **Show Halo on** choice, the screen-edge border draws when:

| Choice | Screen lit | Unlocked | Front | Host |
|---|---|---|---|---|
| Home Screen Only (default) | required | required | Home Screen (no app) | Home Screen window visible |
| Selected App Only | required | required | the chosen app (bundle identifier); needs the hook — without it, nothing is drawn | overlay window |
| Always | required | — (lit Lock Screen included) | anything | overlay window |
| Always Except Lock Screen | required | required | anything | overlay window |
| Always Except When Screen Is Off | required | — | anything | overlay window |

**A display that is fully off can't show a border**, so every choice hides the border and pauses rendering while
the screen is blanked. HCG Halo has **no Always-On display mode**: Always and Always Except When Screen Is Off use
the same rule, so they behave identically on every iPhone (on an Always-On model, whether SpringBoard reports the
dimmed Always-On Lock Screen as blanked is not verified). The host tests check every choice against every
combination of inputs, and that Home Screen Only equals the 0.2.0 rules. *Always Except Lock Screen* follows the
lock state: after Face ID unlocks but before you swipe up, the phone is no longer locked, so the border can appear
on the Lock Screen then (device check S8).

Home Screen Only uses exactly the 0.2.0 inputs:

| Input | Source | If unreadable |
|---|---|---|
| enabled | master switch, and no fault | — |
| attached | overlay is in a window | — |
| screen on | Darwin `com.apple.springboard.hasBlankedScreen` state = 0 | assume on |
| unlocked | Darwin `com.apple.springboard.lockstate` state = 0 | assume unlocked |
| Home Screen in front | the `frontDisplayDidChange:` hook: only an `SBApplication` counts as covering it. Initial value from `_accessibilityFrontMostApplication` | assume in front. Settings then says app detection is unavailable, and the border keeps running behind apps |
| host visible | Home Screen window not hidden and alpha > 0 | — |
| app in front (Selected App Only) | the same hook: the `SBApplication`'s `bundleIdentifier` | nothing is drawn: Selected App Only fails *closed*, since it cannot know which app is in front |

Each fallback fails *open*: the border keeps showing rather than vanishing for an unknown reason. Settings shows
the actual state: *Animating: Orbit*, *Static (Reduce Motion: static)* or *Hidden: app in front*. Settings is itself
an app, so while you look at it, SpringBoard truthfully reports *Hidden: app in front*.

### Render plan (`halo_render_plan`)

| Condition | Result |
|---|---|
| Reduce Motion on | every mode is drawn as **Static** (Breathing included). Follows the setting live |
| Low Power Mode on, policy *Static Border* (default) | Static |
| Low Power Mode on, policy *Keep Animating* | unchanged |
| Low Power Mode on, policy *Hide Border* | nothing drawn |

## Safety

| Mechanism | Effect |
|---|---|
| **Off by default** | `enabled` defaults to `NO`. Installing changes nothing until you turn it on |
| **Master switch** | Turning it off removes the overlay, cancels every observer and notification token, and stops attach retries. Immediate |
| **Kill switch** | If `/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.disabled` exists at launch, Halo does nothing (respring to apply) |
| **Interface gate** | No Home Screen window class or controller means no overlay, and *Incompatible* in Settings |
| **Launch guard** | Counted only while enabled. Three SpringBoard launches in a row that each end within 30 s → *Auto-disabled*, nothing drawn. Turn Enable off and on, then respring, to re-arm |
| **Fault fallback** | Every entry point is wrapped in `@try`. An Objective-C exception removes the overlay and reports *Fault*. Turning Enable off and on retries |
| **The hook** | Installed once, only when Halo is first activated and SpringBoard implements the method. Calls `%orig` first and never changes arguments or return values. Halo checks the hook really replaced the method; if not, it reports app detection as unavailable |

These reduce risk; they are not a guarantee. A hard crash in SpringBoard cannot be caught. That is why the launch
guard and the kill switch exist. **No crash-prevention claim is made, and nothing has run on a device yet.**

## Settings

- **Root pane** (`Root.plist`, generated by `scripts/generate.py`): master switch, status, rendering state, display
  context, mode, presets, colours, appearance sliders, animation, device profile and calibration, reset, recovery,
  diagnostic logging, and about.
- **Live preview** in the header. It uses the same renderer on a miniature of the selected profile, with a notch
  silhouette and a faint Home Screen grid. Widths are exaggerated so thin lines stay visible. It follows Reduce
  Motion and Low Power Mode and pauses off screen.
- **Status** comes from SpringBoard. Settings posts `…/status-request`, SpringBoard writes the status and posts
  `…/status-updated`, and Settings reloads. The footer shows when it was reported. If the installed version differs
  from the running one, it says to respring.
- **Theme.** A dark navy background, cyan and violet accents, and text colours chosen for readability on the panel
  colour. Settings' shared navigation bar tint is restored when the pane closes.
- **Presets** store only the appearance keys (`+[HaloPreferences appearanceKeys]`). **Reset Appearance** and
  **Reset Calibration** remove only their own keys. Presets, the profile, the Low Power policy and the switch are
  untouched (tested in the simulator).

## Privacy

There is no networking code, no URL, no account, no analytics and no identifiers. `validate.sh` section 7 fails the
build if either binary references sockets, URL loading, WebKit, process spawning, privilege changes, the keychain,
LocalAuthentication, advertising identifiers or any URL. Logging uses `os_log` on the device only, and verbose logs
appear only with *Diagnostic Logging* on.
