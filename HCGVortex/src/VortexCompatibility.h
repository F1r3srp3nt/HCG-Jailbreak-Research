//
//  VortexCompatibility.h
//  HCG Vortex — Hakmi Capital Group
//
//  The SpringBoard compatibility gate, hook-installation check and launch
//  guard, kept free of UIKit so they can be unit-tested against fake runtime
//  classes on a Mac (tests/test_compat.m). VortexCore calls these with the
//  real class names and UIView / UIScrollView.
//
//  Contract: if anything Vortex needs is missing or different, the gate
//  returns a reason and NO hooks are installed. The Home Screen stays stock.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *folderView;      // "SBFolderView"
    const char *rootFolderView;  // "SBRootFolderView"
    const char *iconScrollView;  // "SBIconScrollView"
    const char *iconListView;    // "SBIconListView"
} VortexSpringBoardClassNames;

extern const VortexSpringBoardClassNames VortexDefaultSpringBoardClassNames;

typedef struct {
    Class _Nullable folderView;
    Class _Nullable rootFolderView;
    Class _Nullable iconScrollView;
    Class _Nullable iconListView;
} VortexResolvedClasses;

/// nil = compatible (and `resolved` is filled). Otherwise a human-readable
/// reason; `resolved` is left zeroed. Pure runtime inspection, installs nothing.
///   viewBase:       UIView on device
///   scrollViewBase: UIScrollView on device
NSString *_Nullable VortexCheckCompatibility(const VortexSpringBoardClassNames *names,
                                             Class viewBase,
                                             Class scrollViewBase,
                                             VortexResolvedClasses *resolved);

/// Implementations of the two hooked selectors on the folder-view class.
typedef struct {
    IMP _Nullable scrollViewDidScroll;
    IMP _Nullable layoutSubviews;
} VortexHookIMPs;

VortexHookIMPs VortexCurrentHookIMPs(Class folderView);

/// nil when both hooked selectors now point at different implementations than
/// before installation (i.e. the hook engine really swapped them).
NSString *_Nullable VortexVerifyHooksInstalled(VortexHookIMPs before, VortexHookIMPs after);

/// Crash-loop guard. Each SpringBoard launch that installs hooks counts as
/// "unstable" until it has run for VORTEX_STABLE_AFTER_SECONDS. When the count
/// of consecutive unstable launches reaches VORTEX_UNSTABLE_LAUNCH_LIMIT, the
/// next launch installs no hooks until the user re-enables Vortex.
#define VORTEX_UNSTABLE_LAUNCH_LIMIT 3
#define VORTEX_STABLE_AFTER_SECONDS 30.0
BOOL VortexLaunchGuardShouldDisable(NSInteger consecutiveUnstableLaunches);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
