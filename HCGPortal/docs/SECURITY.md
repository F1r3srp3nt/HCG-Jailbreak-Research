# HCG Portal security model (0.1.0~beta4)

HCG Portal is an extension of the **unlocked** iPhone. It is never a route around the device's security.

## Principles

1. **iOS is the authority.** Portal never asks for, performs, hooks or observes Face ID, Touch ID or passcode
   verification. It only reads the lock state iOS reports afterwards. `validate.sh` fails the build if either binary
   references an unlock request (`unlockWithRequest`, `createUnlockRequest`, `SBLockScreenUnlockRequest`,
   `unlockUIFromSource`) or any passcode, keybag, authentication-controller or LocalAuthentication API.
2. **Fail closed.** Every required source must say "unlocked". Any "locked", or any source that cannot be read on
   this iOS version, keeps Portal closed.
3. **Nothing on the locked Lock Screen.** While closed, Portal has no view, no control, no accessibility element and
   no animation in SpringBoard's hierarchy. It does not exist on screen.
4. **Revocation is immediate.** Locking removes Portal and discards anything pending, before any other work.
5. **Checks at the privileged boundary**, not just in the UI.

## Sources (read only, every time access is evaluated)

| Source | Interface | Required | Notes |
|---|---|---|---|
| Data protection | `-[UIApplication isProtectedDataAvailable]` (public) | yes | NO while locked (after the short data-protection grace period) and **before the first unlock after a restart** |
| SpringBoard lock state | Darwin state `com.apple.springboard.lockstate` (`notify_get_state`) | yes | non-zero while the Lock Screen UI is locked; unreadable counts as unknown |
| SpringBoard UI lock | `-[SBLockScreenManager isUILocked]` | yes | iOS 17.0.3 header `SBLockScreenManager.h`; missing selector counts as unknown |
| Secure app | `-[SBCoverSheetPresentationManager isInSecureApp]` | locks if YES | camera opened from the Lock Screen |
| Screen | Darwin state `com.apple.springboard.hasBlankedScreen` | closes if off | |

The decision is `portal_access()` in `src/PortalCore.c`:
- **Granted** only if data protection = YES, lock state = unlocked, UI lock = NO, no secure app and the screen not off.
- **Locked** if any source reports locked.
- **Unverified (closed)** if a required source is unknown.

The host tests enumerate all 3⁵ combinations.

What each state means for Portal:
- **Face ID matched but still on the Lock Screen** is *not* unlocked. The UI lock and lock state still say locked, so
  Portal waits until iOS dismisses the Lock Screen. It never infers authentication from the padlock animation, screen
  visibility or SpringBoard being present.
- **After a restart,** data protection is unavailable until the first unlock, so Portal stays closed even if another
  source misreports.
- **Face ID, Touch ID and passcode** all reach Portal as the same signals. Portal cannot tell them apart and does not
  need to.

## Where Portal appears

On the **Cover Sheet pulled down over the unlocked iPhone** (Notification Centre), below the clock and above
notifications. That is the same view hierarchy as before (`CSCoverSheetViewController.mainPageContentViewController`),
now only while access is granted.

## Revocation triggers

- Darwin lock state changes.
- The screen blanks.
- `UIApplicationProtectedDataWillBecomeUnavailable` / `DidBecomeAvailable`.
- The Cover Sheet's `viewWillAppear:` (locking brings the Cover Sheet back).
- Every update, including the 1.5 s re-measure while Portal is on screen.

On revocation (`-accessRevoked:`), all of the following happen synchronously on the main thread:
- the menu collapses;
- the overlay leaves the hierarchy and its timers and callbacks are cancelled;
- any pending action is discarded;
- the access **epoch** advances.

## Actions and races

An action carries the access epoch it was selected in. The epoch advances on **every** opening or closing of access.
So nothing selected before a lock can run after it, even if the iPhone is unlocked again within the same second. The
host tests run 200,000-step storms of locks and unlocks against this.

1. **Selection:** the sources are read again. If access is closed, nothing happens.
2. **Preparation:** the Cover Sheet is closed, as a swipe up would close it
   (`-[SBCoverSheetPresentationManager setCoverSheetPresented:animated:withCompletion:]`, iOS 17.0.3 header).
3. **Before running:** the sources are read again, and `portal_pending_resolve` runs the action only if the epoch is
   unchanged and access is granted now.
4. **In the launcher:** the gate is asked again on the main thread, right before LaunchServices is called and again
   before the SpringBoard fallback. If it says no, iOS is asked for nothing.

Residual window: LaunchServices runs off the main thread. A lock in the few milliseconds between the last check and
iOS acting on the request cannot be caught by Portal. iOS itself still never shows an app over a locked device.

## Compatibility limits

- The interfaces are verified against the **iOS 17.0.3** class dump only. On other versions, a missing selector makes
  Portal stay closed (Settings › HCG Portal › *iPhone lock state: unverified: …*). It never opens Portal.
- `isProtectedDataAvailable` inside SpringBoard has not yet been observed on the test iPhone. If it misreports NO
  while unlocked, Portal stays hidden and Settings says *protected data unavailable*. That would be a device finding
  to report, not a reason to weaken the gate.
- Without a passcode, iOS has no locked data-protection state. Portal then depends on the lock state and the UI lock
  only, both of which still require the Lock Screen to be dismissed.

## Not touched

Face ID, Touch ID, passcode verification, authentication enforcement, keybag, SpringBoard's lock and unlock methods,
notification content and other products' preferences. Portal injects into SpringBoard only (`HCGPortal.plist`), with
the three `CSCoverSheetViewController` hooks. Each hook calls the original first.
