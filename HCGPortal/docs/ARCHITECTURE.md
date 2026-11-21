# HCG Portal architecture

## Overview

```
SpringBoard process                                              Settings app (Preferences)
───────────────────                                              ──────────────────────────
%ctor ── PortalControllerBootstrap                               PortalRootListController
  │      kill switch? CSCoverSheetViewController + SBLockScreenManager?   ├─ PortalPreviewView (live mini Lock Screen,
  │      launch guard?                                            │    real PortalView + real layout solver)
  ├─ Darwin: …portal/preferences-changed ◄───── writes ────────── ├─ PortalPlacementController (drag, sliders, Reset)
  ├─ Darwin: …portal/status-request ◄────── asks status ───────── ├─ PortalAppsController (HCG Apps, ≤ 6)
  │          …portal/status-updated ──────────────────────────► └─ reads status
  ├─ Darwin (read-only): com.apple.springboard.lockstate, …hasBlankedScreen
  ├─ Reduce Motion / Low Power Mode observers
  │
  ├─ PortalController (main thread) ── decisions in PortalCore.c (pure C, host-tested)
  │    ├─ PortalHost: find the Lock Screen's main page; measure clock/widgets and obstacles (frames only)
  │    ├─ PortalOverlayView (interactive only on visible controls)
  │    │    ├─ orb (PortalCircleControl) └─ PortalView (Core Animation: rings, glow, particles, core)
  │    │    └─ radial menu items (64 pt discs), message line
  │    ├─ PortalAuth: SpringBoard's own unlock request (Face ID / Touch ID / passcode)
  │    ├─ PortalLauncher: LSApplicationWorkspace (as HCG Nexus 0.3.1)
  │    └─ PortalCompanions: Nexus / Animation Center / Halo, all optional
  │
  └─ three hooks, installed only when first enabled, call the original method first:
       -[CSCoverSheetViewController viewWillAppear:], viewDidDisappear:, viewDidLayoutSubviews
```

Preferences: CFPreferences domain `com.hakmicapitalgroup.portal`. Status: `com.hakmicapitalgroup.portal.status`.
Both processes compile the same validator (`PortalPreferences.m`) and the same rules (`PortalCore.c`).

## Startup (0.1.0~beta2)

The dylib has no load-time dependency beyond system frameworks (no Substrate load command; `validate.sh` §5 enforces
it). Its constructor only queues `PortalControllerBootstrap` on the main queue. The bootstrap reads Portal's own
preferences, checks the kill switch and the launch guard, registers Darwin observers and writes a status that is built
from Portal's own state and installed files only. Nothing in SpringBoard's Lock Screen (`SBLockScreenManager`,
`SBCoverSheetPresentationManager`, the Cover Sheet) and no companion code is called until Portal is enabled **and**
SpringBoard has finished launching. Then `MSHookMessageEx` is resolved with `dlsym`; if it is missing, Portal stays
inactive (*Incompatible: inactive*, with the reason in Settings) and nothing is hooked or attached.

## Lock Screen lifecycle (0.1.0~beta3)

- **Eligible** = SpringBoard launched, screen on, Cover Sheet visible, phone locked. Only then does Portal attach.
- **Attach** once per host: `addSubview:` into the main page, breadcrumb *on the Lock Screen*. Later updates only lay
  out; `bringSubviewToFront:` runs at most once a second and only if something else is above the portal. If the host
  is not ready yet, up to 6 retries 250 ms apart, then *no-host*.
- **Detach** when no longer eligible (Cover Sheet gone, screen off, unlocked, disabled, fault): stop the measure timer,
  `-prepareForDetach` (bump the callback generations, collapse, hide the message, pause, remove animations), remove
  from the superview, breadcrumb *off the Lock Screen*.
- **Delayed work** (idle collapse, message fade, tap-outside collapse, relayout) holds the overlay or controller
  weakly, checks a generation number, and does nothing without a superview.
- **Re-entrancy:** `-update` ignores calls made while it runs; layout passes are coalesced to one per 250 ms.
- **Breadcrumbs:** each lifecycle step is written to the status domain on change (`breadcrumb` = step, time,
  version). The next launch reads it before writing its own and shows it in Settings as *Diagnostics*.

## Where the portal lives

`PortalHost` uses `CSCoverSheetViewController.mainPageContentViewController.view` (the Lock Screen's main page) only.
If it is missing, not loaded, not a `CSMainPageContentViewController` or not in a visible window, Portal stays hidden
with the reason *Lock Screen container unavailable: …*; there is no fallback to `CSCoverSheetViewController.view`. The Cover Sheet controller comes from the hook or from
`+[SBLockScreenManager sharedInstance].coverSheetViewController`. Living inside the main page means the portal
scrolls away with the camera and Today pages and slides up with the unlock gesture, with no work from Portal.

### Placement and coexistence (`portal_layout`)

Measured each time the Cover Sheet lays out (hook) and, while the portal is shown, at most every 1.5 s (a safety net
for notifications that arrive without a layout pass):

- **Anchor:** the lowest visible edge of `dateView`, the Lock Screen widgets (`complicationContainerViewController`)
  and any visible view whose class name contains `DateView`, `ProminentDisplay`, `ProminentTime` or
  `ComplicationContainer`, in the upper half. If none is found, 30 % of the safe area (estimated).
- **Obstacles:** visible views named like notifications (`NotificationListCell`, `NotificationShortLook`), media and
  Live Activities (`AdjunctItemView`, `MediaControls`, `PlatterView`, `ActivityItem`), the flashlight and camera
  (`QuickActionsButton`, `QuickActionsView`), `PageControl`, `CallToActionLabel`, `TeachableMoments`. **Frames only**:
  no notification content is ever read.
- **Floor:** the highest obstacle edge in the portal's column, otherwise 128 pt above the bottom of the safe area.
- **Decision:** the chosen size if it fits between anchor + 12 pt and floor − 12 pt (*full*); otherwise as large as
  fits down to 96 pt (*reduced*, centred); otherwise a 56 pt orb (*compact*); otherwise **hidden** (nothing drawn,
  nothing intercepted). Horizontal offset is clamped 16 pt inside the screen.

Host tests check, over 200,000 random screens and obstacle sets, that the portal never covers an obstacle below the
clock, never rises above the anchor, never enters the bottom reserve and keeps a ≥ 44 pt target.

## Touches

`PortalOverlayView` covers its host but takes a touch only where a visible control is:

| State | Takes the touch | Everything else |
|---|---|---|
| collapsed | the orb's **circle** (≥ 44 pt; the square corners pass through) | passes through |
| expanded | the orb and each 64 pt item disc | passes through **and** collapses the menu (tap outside) |
| hidden / no room / disabled | nothing | passes through |

Rings, glow, particles, labels and the message line never take touches; the overlay adds **no gesture recognisers**.
The unlock swipe, the home indicator, Notification Centre, the camera page swipe, notifications, media controls,
the flashlight and the camera keep working because their touches never reach Portal (Simulator-checked with the
window's own hit-test; device rows U1–U6). The menu also collapses after 12 s idle, on screen-off and when the Cover
Sheet disappears.

Accessibility: the orb is a button (*HCG Portal*, hint *Shows Portal destinations*); when expanded each destination is
a button, unavailable ones carry *Not enabled* and their status as value. Messages are announced.

## Rendering (`PortalView`)

Core Animation only; no timers, display links or `drawRect:` in SpringBoard.

| Layer | Look | Motion (full plan) |
|---|---|---|
| shadow | soft radial black below the portal: depth on the wallpaper | — |
| glow | radial primary → secondary → clear, 1.6 × diameter | — |
| outer ring | conic cyan/violet gradient masked to a 2.6 pt ring, glow shadow | one lap per 24 s ÷ speed |
| middle ring | dashed violet ring | opposite direction, 1.6 × slower |
| inner ring | cyan 72 % arc | 0.65 × the outer period |
| particles | ≤ 6 soft motes per second drifting off the outer ring (additive) | — |
| core | dark translucent radial navy → black, glass rim and highlight, inner glow | inner glow breathes (3.2 s ÷ speed) |

Rings are rasterised once, so rotation only composites a cached bitmap. Brightness scales the energy layers, not the
dark core. Expanded: ×1.06 and brighter glow. Waiting for authentication: faster core pulse.

**Pause** freezes the stage clock (`speed = 0`, QA1673) and stops the emitter. The portal is paused whenever it is not
visible: screen off, Cover Sheet gone, authentication up, no room, Low Power *Hide*, disabled.

### Render plan (`portal_render_plan`)

| Condition | Result |
|---|---|
| normal | animating; particles if intensity > 5 %; 1–3 glow layers from intensity; unlock flourish if enabled |
| Reduce Motion | **static** appearance, no particles, no flourish (wins over every policy that still draws) |
| Low Power, *Static* (default) | static, one glow layer, no particles, no flourish |
| Low Power, *Economy* | rings at half speed, one glow layer, no particles, no flourish |
| Low Power, *Hide* | nothing drawn |

## Visibility (`portal_visibility`)

Shown only when all hold: enabled, no kill switch, no fault, host found, screen lit, Cover Sheet visible **as the Lock
Screen** (a lock happened since it appeared — Notification Centre pulled over an unlocked phone does not count),
authentication UI not up, the plan draws, and the layout found room. Each failing condition has a name shown in
Settings (*Paused: screen off*, *Hidden: no room*, …). Host tests check all 2,048 input combinations.

## Authentication and the pending action

1. Tapping **Nexus**, **Backgrounds** or an **app** (all open something outside the Lock Screen) checks availability
   first. Unavailable → a message, nothing else (no authentication request).
2. Otherwise `portal_pending_begin` records exactly that destination and item with a new generation; a second request
   while one waits is ignored.
3. The portal collapses and hides; `PortalAuth` asks SpringBoard: the Cover Sheet context's own `createUnlockRequest`
   (fallback: an `SBLockScreenUnlockRequest` with source 17, intent 3), named *HCG Portal: <destination>*, biometrics
   allowed, sent to `-[SBLockScreenManager unlockWithRequest:completion:]`. iOS shows its normal Face ID / Touch ID /
   passcode UI. Portal never sees or handles a passcode.
4. `portal_pending_resolve`: only the waiting generation, reporting **success**, within 90 s, performs — once.
   Cancellation, failure, a refused request, a stale or repeated callback, screen-off, disabling, a fault or the
   timeout discard it (host-tested over 200,000 random sequences; Simulator-tested end to end).
5. Perform: an app → the launcher; Backgrounds → Settings; Nexus → `HCGNexusPortalInterface` (when it exists).

If `unlockWithRequest:completion:` is missing, every protected destination fails closed (*Unlock your iPhone first*).
`validate.sh` fails the build if either binary references a passcode, keybag or unlock-without-authentication API
(`attemptUnlockWithPasscode`, `unlockUIFromSource`, `MKBUnlockDevice`, `LAContext`, …) or notification-content API.

## Unlock

When `com.apple.springboard.lockstate` goes from locked to unlocked while the portal is visible, the menu collapses and
a 0.5 s flourish plays (rings expand and fade, the core opens). It is decoration inside the Cover Sheet, which is
already sliding away: nothing waits for it (the Simulator measures Portal's dismissal handler returning in < 50 ms).
Skipped with Reduce Motion, in Low Power Mode, or when *Opening Animation on Unlock* is off.

## Safety

| Mechanism | Effect |
|---|---|
| **Off by default** | `enabled` defaults to NO. Installing changes nothing until you turn it on |
| **Master switch** | Off removes the overlay, cancels any pending action, stops observers and timers; the hooks then return after the original method. Immediate, no respring |
| **Kill switch** | `/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.disabled` at launch → Portal does nothing (respring to apply) |
| **Interface gate** | No `CSCoverSheetViewController` / `SBLockScreenManager` → nothing, *Incompatible* |
| **Launch guard** | Three SpringBoard launches in a row ending within 30 s while enabled → *Auto-disabled*. Enable off/on + respring re-arms |
| **Fault fallback** | Every entry point is in `@try`; an Objective-C exception removes the overlay and reports *Fault*. Enable off/on retries |
| **Hooks** | Three, call the original method first, installed once when first enabled, never change arguments or return values |

A hard crash cannot be caught; that is what the launch guard and kill switch are for. No crash-prevention claim is
made, and nothing has run on a device yet.

## Privacy

No networking, URLs, accounts, analytics or identifiers (`validate.sh` section 7). Logging is `os_log` only; verbose
logs need *Diagnostic Logging*. While locked the portal shows only the four destination names, their availability
and — when you open the HCG Apps ring — the icons and names of apps **you** chose.
