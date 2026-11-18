//
//  HACController.h
//  HCG Animation Center — Hakmi Capital Group
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*HACHookInstaller)(void);

/// Called from %ctor. Decides whether HCG Animation Center may run this
/// launch (kill switch, launch guard, interfaces) and, if so, waits for
/// SpringBoard to finish launching. `installFrontDisplayHook` is called at
/// most once, only when the tweak is enabled.
void HACControllerBootstrap(HACHookInstaller installFrontDisplayHook);

/// From the -[SpringBoard frontDisplayDidChange:] hook, after %orig.
void HACControllerFrontDisplayDidChange(id display);

#ifdef HAC_PREVIEW_HOST
/// Preview / tests only (never in the package). Lock and screen state come
/// from the preview-named Darwin notifications (HAC_*_NOTIFICATION).
NSDictionary *HACControllerPreviewStatus(void);
id HACControllerPreviewSurfaceView(int surface);
#endif

#ifdef __cplusplus
}
#endif
