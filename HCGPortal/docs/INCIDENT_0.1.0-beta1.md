# Incident: SpringBoard Safe Mode with HCG Portal 0.1.0~beta1

**Status: cause not confirmed.** No SpringBoard crash report (`SpringBoard-*.ips`) from the incident has been reviewed.
Builds 0.1.0~beta2 and 0.1.0~beta3 remove every hazard below; the device test in `DEVICE_TEST_CHECKLIST.md` decides.

## What is known

- Build: `com.hakmicapitalgroup.portal_0.1.0~beta1_iphoneos-arm64.deb`, SHA-256
  `9ccfeb9b6b832edb3e8745c8e1774d93cc5623ebde1023102cf95bb139220dae`, commit `4bfed33`, run 44395826216. This is the
  only Portal build published to HCG Repo Candidate (still published there).
- Recording: Sileo reached *Setting up HCG Portal*, then SpringBoard entered Safe Mode.
- Phone on record for HCG testing: iPhone 11 Pro Max, iOS 17.4, Dopamine 2.x (rootless). **Not confirmed for this
  incident.**
- The rest of the Lock Screen lifecycle (lock / wake / unlock with the menu) was never exercised on a device.

## Hypotheses and how the next test tells them apart

0.1.0~beta3 writes a breadcrumb (the last lifecycle step, its time and Portal's version) to
`com.hakmicapitalgroup.portal.status` whenever the step changes. After the next launch, Settings › HCG Portal ›
*Diagnostics* shows it, together with whether the previous launch ended within 30 s.

| # | Hypothesis | Fixed in | Breadcrumb / evidence if it were still happening |
|---|---|---|---|
| H1 | Launch path, Portal off: beta1's constructor-time bootstrap created `SBCoverSheetPresentationManager` / `SBLockScreenManager` singletons on every launch, before SpringBoard did | beta2 | *bootstrap*, ended within 30 s, while Portal is off (P1). Crash report: crashed thread in SpringBoard launch with `HCGPortal.dylib` frames |
| H2 | Hook installation (injector's `MSHookMessageEx`) | beta2 (resolved with `dlsym`, no Substrate load command) | *installing hooks* |
| H3 | Attach churn: every update and layout pass re-inserted the overlay and brought it to the front inside SpringBoard's own layout (a layout loop / recursion) | beta3 | *attaching to the Lock Screen* or *on the Lock Screen*; crash report: very deep stack in `layoutSubviews` / watchdog |
| H4 | Fallback to the Cover Sheet's own view when the main page was unavailable | beta3 (no fallback) | Settings: *Lock Screen container unavailable: …* instead of a crash |
| H5 | Timers and blocks outliving the overlay after unlock / screen off | beta3 (weak, generation-checked) | *off the Lock Screen*, crash shortly after unlock |
| H6 | Authentication / launch path | unchanged logic; guarded by the pending-action rules | *requesting authentication* or *opening …* |
| H7 | Not Portal: another tweak or the package installation itself | — | crash report without `HCGPortal.dylib` frames; Safe Mode persists after Portal is removed |

Breadcrumbs are written through cfprefsd, so the very last step before a crash can be lost; the crash report is the
definitive evidence and is still needed.
