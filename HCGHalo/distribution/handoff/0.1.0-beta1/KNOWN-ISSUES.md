# HCG Halo 0.1.0~beta1: known issues

**Free public beta demo — not yet device-tested.**

1. **Not installed or run on any device.** Everything below is from build validation and simulator tests only.
2. **The first device's iOS version and jailbreak are unconfirmed.** The iPhone 11 Pro Max must be confirmed with
   `scripts/device-info.sh` before installation.
3. **SpringBoard interfaces are unverified on a device.** Halo needs `SBHomeScreenWindow` (or
   `+[SBIconController sharedInstance]`). If neither is present it stays inactive and reports *Incompatible*. For
   app-in-front detection it hooks `-[SpringBoard frontDisplayDidChange:]`; if that is missing, the border keeps
   animating, hidden, behind apps.
4. **The iPhone 11 Pro Max profile uses reference values** (corner radius 39 pt; notch about 209 × 30 pt) from public
   measurements, not measured by HCG. It may need calibration.
5. **The border also shows over the Today View, App Library and open folders**, because they are part of the Home
   Screen window. This has not been checked separately.
6. **Battery, GPU and frame-rate impact are unmeasured.** A gradient border that is animating uses one masked
   full-screen offscreen pass per frame while visible. It is paused and hidden when not visible.
7. **May crash SpringBoard.** The safety mechanisms reduce but cannot rule out crashes (`docs/RECOVERY.md`).
8. **The icon is provisional.**
9. **The licence wording is the HCG Vortex freeware licence with the product name changed.** It has not been
   reviewed by counsel; the owner should confirm it applies to Halo.
