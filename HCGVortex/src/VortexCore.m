//
//  VortexCore.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexCore.h"
#import "VortexAnimationEngine.h"
#import "VortexCompatibility.h"
#import "VortexLog.h"
#import "VortexPreferences.h"
#import "VortexSpringBoard.h"

#import <objc/runtime.h>

BOOL VortexDiagnosticLoggingEnabled = NO;

os_log_t VortexLogHandle(void) {
    static os_log_t handle = NULL;
    if (!handle) handle = os_log_create(VORTEX_BUNDLE_ID, "engine");
    return handle;
}

static Class gFolderViewClass = Nil;
static Class gRootFolderViewClass = Nil;
static BOOL gHooksInstalled = NO;
static BOOL gListLayoutHookInstalled = NO;

#pragma mark - Status

static void VortexReportStatus(NSString *state, NSString *detail) {
    NSDictionary *status = @{
        VortexStatusKeyState : state ?: @"unknown",
        VortexStatusKeyDetail : detail ?: @"",
        VortexStatusKeySystemVersion : [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"",
        VortexStatusKeyTweakVersion : @VORTEX_VERSION,
        VortexStatusKeyTimestamp : [NSDate date],
    };
    @try {
        [VortexPreferences writeStatus:status];
    } @catch (NSException *exception) {
        VortexLogError("could not write status: %{public}@", exception.reason);
    }
    VortexLogInfo("status %{public}@: %{public}@", state, detail);
}

static NSString *VortexStateForConfiguration(VortexConfiguration *config) {
    if (!config.enabled) return @"disabled";
    return @"active";
}

#pragma mark - Compatibility

NSString *VortexCoreCompatibilityFailure(void) {
    VortexResolvedClasses classes;
    NSString *failure = VortexCheckCompatibility(&VortexDefaultSpringBoardClassNames, [UIView class],
                                                 [UIScrollView class], &classes);
    if (!failure) {
        gFolderViewClass = classes.folderView;
        gRootFolderViewClass = classes.rootFolderView;
    }
    return failure;
}

#pragma mark - Launch guard

/// Marks this SpringBoard launch as stable once it has run long enough.
@interface VortexLaunchGuard : NSObject
+ (void)markStable;
@end

@implementation VortexLaunchGuard
+ (void)markStable {
    [VortexPreferences setConsecutiveUnstableLaunches:0];
    VortexLogDebug("launch marked stable");
}
@end

/// Non-fatal observations worth surfacing in diagnostics.
static NSString *VortexCompatibilityNotes(void) {
    NSMutableArray *notes = [NSMutableArray array];
    Class folderView = objc_getClass(VORTEX_SB_FOLDER_VIEW_CLASS);
    Class root = objc_getClass(VORTEX_SB_ROOT_FOLDER_VIEW_CLASS);
    if (folderView && root &&
        class_getMethodImplementation(root, @selector(scrollViewDidScroll:)) !=
            class_getMethodImplementation(folderView, @selector(scrollViewDidScroll:))) {
        [notes addObject:@"SBRootFolderView overrides -scrollViewDidScroll: (effects run only if it calls super)"];
    }
    if (root && !class_getInstanceMethod(root, @selector(iconListViews)))
        [notes addObject:@"-iconListViews missing; using scroll view subviews"];
    if (root && !class_getInstanceMethod(root, @selector(isEditing)))
        [notes addObject:@"-isEditing missing; edit-mode bypass unavailable"];
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    [notes addObject:gListLayoutHookInstalled ? @"icon-list layout hook active"
                                              : @"icon-list layout hook not installed (first-frame guard only)"];
    if (v.majorVersion != 17) [notes addObject:[NSString stringWithFormat:@"iOS %ld: hooks were designed from iOS 17 headers; this version is untested", (long)v.majorVersion]];
    return [notes componentsJoinedByString:@"; "];
}

#pragma mark - Preferences

static void VortexReloadConfiguration(void) {
    VortexConfiguration *config = [VortexPreferences loadConfiguration];
    VortexDiagnosticLoggingEnabled = config.diagnosticLogging;
    [VortexAnimationEngine sharedEngine].configuration = config;
    if (gHooksInstalled) VortexReportStatus(VortexStateForConfiguration(config), VortexCompatibilityNotes());
}

static void VortexPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    @try {
        VortexReloadConfiguration();
    } @catch (NSException *exception) {
        [[VortexAnimationEngine sharedEngine] tripWithReason:[NSString stringWithFormat:@"reload: %@", exception.reason]];
    }
}

#pragma mark - Bootstrap

void VortexCoreBootstrap(VortexHookInstaller installer) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return; // filter plist should guarantee this

        if ([[NSFileManager defaultManager] fileExistsAtPath:VortexKillSwitchPath]) {
            VortexReportStatus(@"kill-switch", [NSString stringWithFormat:@"%@ exists; no hooks installed", VortexKillSwitchPath]);
            return;
        }

        NSString *failure = nil;
        @try {
            failure = VortexCoreCompatibilityFailure();
        } @catch (NSException *exception) {
            failure = [NSString stringWithFormat:@"compatibility check raised %@", exception.reason];
        }
        if (failure) {
            // Safe fallback: the Home Screen stays completely stock.
            VortexReportStatus(@"incompatible", failure);
            return;
        }

        // Crash-loop guard: Objective-C exceptions are caught below, but a
        // hard crash is not. After repeated launches that end quickly, stay
        // out of SpringBoard until the user re-enables Vortex in Settings.
        NSInteger unstable = [VortexPreferences consecutiveUnstableLaunches];
        if (VortexLaunchGuardShouldDisable(unstable)) {
            VortexReportStatus(@"auto-disabled",
                               [NSString stringWithFormat:@"%ld consecutive SpringBoard launches ended within %.0f s; "
                                                          @"no hooks installed. Turn Enable Vortex off and on to retry.",
                                                          (long)unstable, VORTEX_STABLE_AFTER_SECONDS]);
            return;
        }
        [VortexPreferences setConsecutiveUnstableLaunches:unstable + 1];
        [[VortexLaunchGuard class] performSelector:@selector(markStable)
                                        withObject:nil
                                        afterDelay:VORTEX_STABLE_AFTER_SECONDS
                                           inModes:@[ NSRunLoopCommonModes ]];

        VortexConfiguration *config = [VortexPreferences loadConfiguration];
        VortexDiagnosticLoggingEnabled = config.diagnosticLogging;
        [VortexAnimationEngine sharedEngine].configuration = config;

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, VortexPreferencesChanged,
                                        (__bridge CFStringRef)VortexPreferencesChangedNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        VortexHookIMPs before = VortexCurrentHookIMPs(gFolderViewClass);
        @try {
            installer();
        } @catch (NSException *exception) {
            VortexReportStatus(@"fault", [NSString stringWithFormat:@"hook installation raised %@", exception.reason]);
            return;
        }
        // Only report "active" if the hook engine really replaced both methods.
        NSString *notInstalled = VortexVerifyHooksInstalled(before, VortexCurrentHookIMPs(gFolderViewClass));
        if (notInstalled) {
            VortexReportStatus(@"fault", notInstalled);
            return;
        }
        gHooksInstalled = YES;
        VortexReportStatus(VortexStateForConfiguration(config), VortexCompatibilityNotes());
    }
}

#pragma mark - Hook entry points

static BOOL VortexIsRootFolderView(UIView *view) {
    return gRootFolderViewClass && [view isKindOfClass:gRootFolderViewClass];
}

void VortexCoreHandleScroll(UIView *folderView, UIScrollView *scrollView) {
    VortexAnimationEngine *engine = [VortexAnimationEngine sharedEngine];
    if (engine.tripped) return;
    @try {
        if (!VortexIsRootFolderView(folderView)) return; // folders keep stock paging
        id<VortexFolderViewLike> folder = (id<VortexFolderViewLike>)folderView;
        // Only the icon page scroller — not e.g. the pull-down search scroller.
        if (![folder respondsToSelector:@selector(scrollView)] || [folder scrollView] != scrollView) return;
        [engine folderView:folderView didScroll:scrollView];
    } @catch (NSException *exception) {
        [engine tripWithReason:[NSString stringWithFormat:@"scroll: %@", exception.reason]];
        VortexReportStatus(@"fault", exception.reason);
    }
}

BOOL VortexCoreListLayoutHookAvailable(void) {
    return VortexClassImplementsSelector(objc_getClass(VORTEX_SB_ICON_LIST_VIEW_CLASS), @selector(layoutSubviews));
}

void VortexCoreNoteListLayoutHookInstalled(BOOL installed) {
    gListLayoutHookInstalled = installed;
}

void VortexCoreHandleListLayout(UIView *iconListView) {
    VortexAnimationEngine *engine = [VortexAnimationEngine sharedEngine];
    if (engine.tripped) return;
    @try {
        [engine iconListViewDidLayout:iconListView];
    } @catch (NSException *exception) {
        [engine tripWithReason:[NSString stringWithFormat:@"list layout: %@", exception.reason]];
        VortexReportStatus(@"fault", exception.reason);
    }
}

void VortexCoreHandleLayout(UIView *folderView) {
    VortexAnimationEngine *engine = [VortexAnimationEngine sharedEngine];
    if (engine.tripped) return;
    @try {
        if (!VortexIsRootFolderView(folderView)) return;
        [engine folderViewDidLayout:folderView];
    } @catch (NSException *exception) {
        [engine tripWithReason:[NSString stringWithFormat:@"layout: %@", exception.reason]];
        VortexReportStatus(@"fault", exception.reason);
    }
}
