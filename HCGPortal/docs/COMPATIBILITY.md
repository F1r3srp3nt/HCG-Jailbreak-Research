# Compatibility, device facts and the SpringBoard interfaces used

## The device: what is recorded, what is confirmed

The brief asked to confirm the device, iOS version and jailbreak before choosing hooks. **This session has no access to
the phone**, so nothing was confirmed on it. What the records say:

| Fact | Value | Source | Confirmed for Portal? |
|---|---|---|---|
| Device | iPhone 11 Pro Max (A13, arm64e) | HCG-repo `docs/device-tests/2026-11-18-owner-device-evidence.md` (owner's phone; also seen on video) | **No** |
| iOS | 17.4 | same record: "the owner's confirmed setup of this phone on 17 Nov 2026" | **No** |
| Jailbreak | Dopamine 2.x, rootless (`/var/jb`), ElleKit, Zebra 1.1.x | same record; HCG Vortex `docs/INSTALL-FAILURE-0.1.0-beta1.md` | **No** |
| Is that combination possible? | Dopamine 3.0.13's README: "iOS 15.0 – 18.7.1 … (A12/A13)" | quoted in Agent-Runtime `HCG-Agent-Runtime/docs/platforms/IOS.md` (branch `claude/brave-rubin-7vwtg1`, unmerged) | plausible; note the record says Dopamine **2.x** |
| Another HCG test phone | iPhone 13 Pro, iOS 16.5, Dopamine | HCG-repo Nexus listing | not this phone |

**Decision:** hooks were chosen so that they do not depend on the exact version: three appearance/layout callbacks on
`CSCoverSheetViewController`, present from iOS 13 through the iOS 17.0.3 header dump, every other interface looked up
and checked at run time, with a fail-safe for each. **Step 0 of `DEVICE_TEST_CHECKLIST.md` runs `scripts/device-info.sh`
(read-only) and must be done before installation**; if the phone is not on iOS 15–17 with a rootless jailbreak, stop.

## Requirements

| Requirement | Value | Why |
|---|---|---|
| Package scheme | rootless (`/var/jb`), `iphoneos-arm64` | the HCG Repo / Halo / Vortex / Animation Center toolchain |
| Binary slices | `arm64` + `arm64e` (fat), native iOS 14+ arm64e ABI from Xcode | A12+ SpringBoard and Preferences are arm64e |
| Minimum iOS | 15.0 (`firmware (>= 15.0)`, `LC_BUILD_VERSION` 15.0) | the rootless floor; newest APIs used: `UIImageSymbolConfiguration` (13), `kCAGradientLayerConic` (12), `UISegmentedControl`/`UISearchController` (all older) |
| Depends | `mobilesubstrate (>= 0.9.5000)`, `preferenceloader`, `firmware (>= 15.0)` | |
| Companions | **none required** (see `INTEGRATIONS.md`) | |

15.0 is a build setting, not a compatibility claim. On iOS versions where an interface below is missing, Portal does
what the table says and Settings shows why.

## SpringBoard interfaces (header evidence)

Evidence: `MTACS/iOS-17-Runtime-Headers` @ `d1d960d` (class-dump of iOS **17.0.3**; the same source HCG Animation
Center used), CoverSheet.framework and SpringBoard.framework. No 17.4 dump was available.

| Interface | 17.0.3 evidence | Used for | If missing |
|---|---|---|---|
| `CSCoverSheetViewController` `viewWillAppear:` / `viewDidDisappear:` / `viewDidLayoutSubviews` (hooked, `%orig` first) | class present (UIViewController) | Lock Screen shown / hidden / laid out | class missing → *Incompatible*, nothing drawn. If the callbacks are not called, visibility falls back to `SBCoverSheetPresentationManager -isVisible` and the 1.5 s re-measure |
| `+[SBLockScreenManager sharedInstance]`, `-coverSheetViewController`, `-isUILocked` | `SBLockScreenManager.h` lines 56, 64, 82 | find the Cover Sheet | *Incompatible* |
| `-[SBLockScreenManager unlockWithRequest:completion:]` | line 286 | normal authentication before a protected action | protected destinations fail closed |
| `-[CSCoverSheetViewController coverSheetContext]` → `-[SBDefaultCoverSheetContext createUnlockRequest]` | `CSCoverSheetViewController.h` 196; `SBDefaultCoverSheetContext.h` 115 | the request with CoverSheet's own defaults | constructed `SBLockScreenUnlockRequest` (source 17, intent 3: community-documented values, **unverified**; Settings › Status shows which route ran) |
| `SBLockScreenUnlockRequest` `name`, `wantsBiometricPresentation` | `SBLockScreenUnlockRequest.h` | label, allow Face ID | not set |
| `-mainPageContentViewController` | `CSCoverSheetViewController.h` 246 | host view (scrolls/slides with the page) | `CSCoverSheetViewController.view` |
| `-dateView`, `-complicationContainerViewController` | 193, 601 | anchor (clock and widgets) | class-name scan, then 30 % estimate |
| `SBCoverSheetPresentationManager -isVisible` / `-isPresented` | (HCG Nexus uses it on 16.5) | Cover Sheet visibility | hook state |
| `LSApplicationWorkspace openApplicationWithBundleID:` / `applicationIsInstalled:`; `-[SpringBoard launchApplicationWithIdentifier:suspended:]` | HCG Nexus 0.3.1~beta1 `HCGSpringBoardLauncher.m` | open an app / Settings after authentication | apps and Backgrounds: *Unavailable* |
| Darwin `com.apple.springboard.lockstate`, `…hasBlankedScreen` | public; Halo, Animation Center, Nexus | lock, unlock, screen off | assume unlocked / lit (fail open for drawing; authentication still decides) |
| `+[UIImage _applicationIconImageForBundleIdentifier:format:scale:]` | Halo's app picker | app icons | first-letter-free symbol |

Class-name tokens used for measuring (`NotificationListCell`, `AdjunctItemView`, `QuickActionsButton`, …) are listed
in `ARCHITECTURE.md`. Which ones the phone really has is reported in Settings › Status › Layout (device row L2).

## Coexistence

| With | Expectation | Evidence |
|---|---|---|
| **HCG Animation Center** (Lock Screen background) | It draws at index 0 of the Lock wallpaper view or the Cover Sheet window; Portal draws on top of the Lock Screen's main page. No shared hooks (AC hooks `frontDisplayDidChange:`), no shared preferences. | design; not run together |
| **HCG Halo** | Halo's border may show on the Lock Screen (*Show Halo on: Always*); its overlay window (level 2050) never takes touches. Optional lighting events: `INTEGRATIONS.md` §3 | design; not run together |
| **HCG Nexus** | Nexus shows only while unlocked; Portal only on the Lock Screen. Opening Nexus needs a Nexus update (`INTEGRATIONS.md` §1) | test double |
| **HCG Vortex** | Home Screen only; no overlap | — |
| Other Lock Screen tweaks (clock, notification, widget tweaks) | Untested. If one moves the clock or notifications, Portal measures the new frames; if one hides them in unknown classes, Portal may not see them as obstacles | — |
| Tweaks that hook `CSCoverSheetViewController` appearance methods | Hook chains are designed for this; Portal calls `%orig` first | — |
