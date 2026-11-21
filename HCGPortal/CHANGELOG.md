# Changelog

## 0.1.0~beta4

Unlock-gated access, and a repair for "the portal is drawn but does not respond". **Development build: Simulator
validated; the iPhone test is pending.** The screen recording and device logs mentioned in the report did not reach
this session, so the cause comes from iOS 17.0.3 header evidence and the code. A Simulator run reproduces the
mechanism. See `docs/DIAGNOSIS_0.1.0-beta3-unresponsive.md`.

- **Only on an unlocked iPhone** (`docs/SECURITY.md`).
  - Portal is granted only while data protection (`isProtectedDataAvailable`), SpringBoard's lock state (Darwin
    `com.apple.springboard.lockstate`) and `-[SBLockScreenManager isUILocked]` all say unlocked, no secure app is up
    and the screen is on.
  - Any "locked", or any source this iOS cannot provide, keeps it closed.
  - Nothing of Portal exists on the locked Lock Screen. It appears on the Cover Sheet pulled down after unlocking.
  - Face ID matched while the Lock Screen is still up does not count as unlocked.
  - Locking removes Portal at once.
- **No authentication code at all.** The `unlockWithRequest:` path (`PortalAuth`) is removed. Portal never requests,
  performs or observes Face ID, Touch ID or passcode verification. `validate.sh` fails the build if an unlock request
  is referenced.
- **Race-free actions.** An action carries its access epoch, which changes on every lock and unlock. It runs only if
  the epoch is still current, with checks:
  - at selection;
  - after the Cover Sheet closes;
  - in the launcher right before it calls iOS.

  A lock while something is opening discards it, even if the iPhone is unlocked again at once.
- **Touches reach Portal.** The orb and the items activate through Portal's own tap recognizer. SpringBoard's tap
  recognizers on the Cover Sheet scroll view (iOS 17.0.3: background content, quick note) wait for it, only for touches
  on Portal's controls. Long presses (poster switcher) and pans (scrolling, dismissing) are untouched, and nothing in
  SpringBoard is hooked or reconfigured.
- **Opening a destination closes the Cover Sheet first**, as a swipe up would, then opens Settings, the app or Nexus.
- **Settings › HCG Portal diagnostics:** *iPhone lock state* (and why), *Touches* (down, up, cancelled, taps,
  activations, last cancelled by), *Breadcrumb*.
- *Opening Animation on Unlock* now plays the first time the portal appears after an unlock.
- Tests:
  - host: all 3⁵ access inputs, lock/unlock epoch storms;
  - runtime: recognizer arbitration, the launcher gate;
  - preview: real UIKit touch events injected into a Cover Sheet stand-in with SpringBoard-like recognizers, the
    locked / before-first-unlock / unlocked matrix, relock while opening, missing sources, Animation Center present
    and absent, and 20 finger lock/unlock cycles.

## 0.1.0~beta3

Lock Screen lifecycle hardening after the SpringBoard Safe Mode incident with 0.1.0~beta1. **Test build only. The
cause is not confirmed:** no SpringBoard crash report from the incident has been reviewed yet. This build removes every
lifecycle hazard found in review and records where SpringBoard was in Portal's lifecycle when it last stopped, so the
next device test can tell the possible causes apart (`docs/INCIDENT_0.1.0-beta1.md`).

- **Attach once, detach on leave.** Portal joins the Lock Screen's main page once per Lock Screen session and leaves it
  when the Cover Sheet disappears, the screen turns off, the phone unlocks or Portal is turned off. Before, every
  update and every layout pass re-inserted the overlay and brought it to the front, inside SpringBoard's own layout.
  Bringing it to the front now happens at most once a second.
- **No fallback container.** If the Lock Screen's main page is missing, not loaded, not the expected class or not in a
  window, Portal stays hidden and the Lock Screen carries on; Settings shows *Lock Screen container unavailable* and
  why. 0.1.0~beta1/2 fell back to the Cover Sheet's own view.
- **Callbacks cannot outlive the view.** The idle collapse (12 s), message fade (3.5 s), tap-outside collapse and
  relayout timers hold Portal weakly and do nothing once it has left the Lock Screen. The measure timer stops on detach.
- **Layout storms are coalesced** (one relayout per 250 ms) and an update can no longer re-enter itself.
- **The radial menu is rebuilt only when its items change**, not on every update.
- **Crash guard counts every launch**, enabled or not (0.1.0~beta1/2 counted only while enabled, so a crash on the
  disabled path never tripped it).
- **Breadcrumbs.** Portal records its lifecycle step (*bootstrap*, *installing hooks*, *attaching to the Lock Screen*,
  *on the Lock Screen*, *off the Lock Screen*, *requesting authentication*, …) in its status file when it changes.
  After the next launch Settings › HCG Portal › *Diagnostics* shows the step the previous launch ended on and whether
  it ended within 30 s.
- Simulator preview: 20 lock / wake / menu / unlock cycles, a 300-pass layout storm, SpringBoard rebuilding the main
  page, the container unavailable, late callbacks after teardown, 10 disable / re-enable cycles and an authentication
  completing after Portal was turned off.

## 0.1.0~beta2

Startup hardening after an observed SpringBoard Safe Mode incident (Sileo reached *Setting up HCG Portal*, then
SpringBoard entered Safe Mode). Test build only; root cause and device recovery still need confirmation on the
affected phone (the SpringBoard crash report has not been reviewed yet).

- **No SpringBoard Lock Screen objects at launch.** In 0.1.0~beta1 the bootstrap ran from the dylib constructor on
  every SpringBoard launch, enabled or not, and ended by writing its status. Building that status called
  `+[SBCoverSheetPresentationManager sharedInstance]` and could fall through to `+[SBLockScreenManager sharedInstance]`,
  creating SpringBoard's own Lock Screen singletons before SpringBoard does. The status path now consults them, and
  companions' runtime interfaces, only while Portal is active, which never happens before SpringBoard has finished
  launching. The preview checks that neither is touched while Portal is off or inactive.
- **No load-time Substrate dependency.** The hooks are plain Objective-C (`src/Tweak.m`, no Logos), and the injector's
  `MSHookMessageEx` is resolved with `dlsym` only when Portal is enabled. If it is unavailable, Portal stays inactive
  and Settings shows why (*Incompatible: inactive* plus the reason); Enable off and on retries. `validate.sh` fails if
  either slice links Substrate. (Published HCG Halo and Vortex builds do link it and run on the same phone, so this
  alone is not thought to be the cause.)
- The bootstrap is queued on the main queue from the constructor.
- The hooks fall back to the superclass implementation should the injector ever report no original.

## 0.1.0~beta1

First beta, free public candidate demo.

First version of `com.hakmicapitalgroup.portal`.

- **Lock Screen portal** below the clock and widgets, above notifications: dark translucent centre, cyan-and-violet
  energy rings turning slowly in opposite directions, soft glow, sparse particles and a shadow for depth.
- **Tap → radial menu** (Nexus, Backgrounds, Devices, HCG Apps); tap outside, 12 s idle, screen-off or leaving the Lock
  Screen collapses it. Only the orb and the 64 pt item discs take touches; everything else passes through.
- **Authentication first:** Nexus, Backgrounds and every app open only after the normal iOS Face ID / Touch ID /
  passcode request succeeds, and only the selected action runs, once. Cancelling, a refused request, screen-off,
  disabling or a 90 s timeout discards it.
- **Destinations:** Backgrounds opens Settings for HCG Animation Center; HCG Apps holds up to six apps you choose;
  Devices shows *Not connected*; Nexus shows *Update needed* until HCG Nexus adds `HCGNexusPortalInterface` v1 (Portal's
  side is ready). Missing companions show *Not installed*.
- **Coexistence:** measures the clock, widgets, notifications, media controls, Live Activities, flashlight and camera
  and moves, shrinks, collapses to a compact orb or hides so it never covers them.
- **Settings:** live mini Lock Screen preview; Position & Size (drag, pinch, sliders, sample notifications, Reset);
  colour (HCG Signature, Aurora, Solar, Mono), brightness, animation speed, intensity; opening animation on unlock;
  Low Power Mode (Static / Economy / Hide); HCG Apps; status, recovery and diagnostics.
- **Efficiency:** Core Animation only; paused whenever not visible. Reduce Motion → static.
- **Safety:** off by default, master switch, kill switch, launch guard, fault fallback; three `%orig`-first hooks.
  Optional lighting events (v1) for a future HCG Halo.
- **Not yet device-tested.** Simulator-tested only.
