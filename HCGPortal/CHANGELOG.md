# Changelog

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
