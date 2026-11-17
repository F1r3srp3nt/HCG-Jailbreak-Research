//
//  HaloController.h
//  HCG Halo — Hakmi Capital Group
//
//  SpringBoard side. Main thread only. See docs/ARCHITECTURE.md.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*HaloHookInstaller)(void);

/// Called once from %ctor. `installFrontDisplayHook` is invoked at most once,
/// only when Halo is first activated and -[SpringBoard frontDisplayDidChange:]
/// exists.
void HaloControllerBootstrap(HaloHookInstaller installFrontDisplayHook);

/// From the -[SpringBoard frontDisplayDidChange:] hook, after %orig.
void HaloControllerFrontDisplayDidChange(id _Nullable display);

/// Launches that end within this many seconds count as unstable.
#define HALO_STABLE_AFTER_SECONDS 30.0
/// After this many unstable launches in a row, Halo stays out of SpringBoard.
#define HALO_MAX_UNSTABLE_LAUNCHES 3

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
