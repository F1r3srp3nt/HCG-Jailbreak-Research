//
//  VortexCore.h
//  HCG Vortex — Hakmi Capital Group
//
//  Tweak lifecycle: process check, kill switch, SpringBoard compatibility
//  gate, preference wiring, status reporting, hook installation and fault
//  isolation for the hook entry points.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*VortexHookInstaller)(void);

/// Called from %ctor. Installs hooks (via `installer`) only when every
/// safety and compatibility check passes.
void VortexCoreBootstrap(VortexHookInstaller installer);

/// Returns nil when this SpringBoard exposes everything Vortex needs, else a
/// human-readable reason. Pure runtime inspection; installs nothing.
NSString *_Nullable VortexCoreCompatibilityFailure(void);

/// Hook entry points (called AFTER %orig). Never throw.
void VortexCoreHandleScroll(UIView *folderView, UIScrollView *scrollView);
void VortexCoreHandleLayout(UIView *folderView);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
