//
//  PortalController.h
//  HCG Portal — Hakmi Capital Group
//
//  The SpringBoard engine. Main thread only.
//
//    constructor ─ bootstrap: kill switch? Cover Sheet interfaces? launch guard?
//      ├─ Darwin observers: preferences-changed, status-request,
//      │  com.apple.springboard.lockstate, com.apple.springboard.hasBlankedScreen
//      ├─ Reduce Motion / Low Power observers
//      └─ the hooks (installed once, only when enabled): CSCoverSheetViewController
//         viewWillAppear: / viewDidDisappear: / viewDidLayoutSubviews, all the original method first
//
//  Turning Enable off removes the overlay, cancels any pending action, stops
//  every observer and timer; the hooks then return straight after the original method, so the
//  Lock Screen behaves exactly as without HCG Portal.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Returns nil on success or a message explaining why Portal cannot activate.
typedef NSString *_Nullable (*PortalHookInstaller)(void);

/// Called from the constructor (on the main queue). `installHooks` runs only when
/// Portal is enabled, and is retried on the next enable if it reported a failure.
void PortalControllerBootstrap(PortalHookInstaller _Nullable installHooks);
/// Tweak.m reports which hooks it installed ("viewWillAppear:, …" or the reason none were).
void PortalControllerNoteHooks(NSString *summary);

// From the hooks, after the original method.
void PortalControllerCoverSheetWillAppear(id coverSheet);
void PortalControllerCoverSheetDidDisappear(id coverSheet);
void PortalControllerCoverSheetDidLayout(id coverSheet);

#ifdef PORTAL_PREVIEW_HOST
/// Preview / tests only (never in the package). Lock and screen state come
/// from the preview-named Darwin notifications (PORTAL_*_NOTIFICATION).
NSDictionary *PortalControllerPreviewStatus(void);
id _Nullable PortalControllerPreviewOverlay(void);
/// Re-reads preferences synchronously (tests do not wait for Darwin delivery).
void PortalControllerPreviewReload(void);
/// Simulates the Low Power / Reduce Motion inputs (the Simulator cannot toggle them).
void PortalControllerPreviewSetSystemInputs(int reduceMotion, int lowPower);
/// Forces an immediate re-measure and layout.
void PortalControllerPreviewRelayout(void);
/// Raises the fault fallback, as an Objective-C exception inside SpringBoard would.
void PortalControllerPreviewInjectFault(void);
/// YES while the 1.5 s re-measure timer is scheduled.
BOOL PortalControllerPreviewMeasureTimerRunning(void);
/// The Simulator's keybag is always unlocked: 1 / 0 overrides -isProtectedDataAvailable, -1 restores it.
void PortalControllerPreviewSetProtectedData(int available);

/// The injector's MSHookMessageEx signature.
typedef void (*PortalHookMessageFunction)(Class cls, SEL selector, IMP replacement, IMP _Nullable *_Nullable original);
/// Preview only: what Tweak.m's hook-API lookup finds (NULL = the injector's API is unavailable),
/// in place of dlsym(RTLD_DEFAULT, "MSHookMessageEx").
void PortalPreviewSetHookAPI(PortalHookMessageFunction _Nullable function);
#endif

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
