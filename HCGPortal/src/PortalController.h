//
//  PortalController.h
//  HCG Portal — Hakmi Capital Group
//
//  The SpringBoard engine. Main thread only.
//
//    %ctor ─ bootstrap: kill switch? Cover Sheet interfaces? launch guard?
//      ├─ Darwin observers: preferences-changed, status-request,
//      │  com.apple.springboard.lockstate, com.apple.springboard.hasBlankedScreen
//      ├─ Reduce Motion / Low Power observers
//      └─ the hooks (installed once, only when enabled): CSCoverSheetViewController
//         viewWillAppear: / viewDidDisappear: / viewDidLayoutSubviews, all %orig first
//
//  Turning Enable off removes the overlay, cancels any pending action, stops
//  every observer and timer; the hooks then return straight after %orig, so the
//  Lock Screen behaves exactly as without HCG Portal.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*PortalHookInstaller)(void);

/// Called from %ctor. `installHooks` runs at most once, only when enabled.
void PortalControllerBootstrap(PortalHookInstaller installHooks);
/// Tweak.x reports which hooks it installed ("viewWillAppear:, …" or the reason none were).
void PortalControllerNoteHooks(NSString *summary);

// From the hooks, after %orig.
void PortalControllerCoverSheetWillAppear(id coverSheet);
void PortalControllerCoverSheetDidDisappear(id coverSheet);
void PortalControllerCoverSheetDidLayout(id coverSheet);

#ifdef PORTAL_PREVIEW_HOST
/// Preview / tests only (never in the package). Lock and screen state come
/// from the preview-named Darwin notifications (PORTAL_*_NOTIFICATION).
NSDictionary *PortalControllerPreviewStatus(void);
id PortalControllerPreviewOverlay(void);
/// Re-reads preferences synchronously (tests do not wait for Darwin delivery).
void PortalControllerPreviewReload(void);
/// Simulates the Low Power / Reduce Motion inputs (the Simulator cannot toggle them).
void PortalControllerPreviewSetSystemInputs(int reduceMotion, int lowPower);
/// Forces an immediate re-measure and layout.
void PortalControllerPreviewRelayout(void);
#endif

#ifdef __cplusplus
}
#endif
