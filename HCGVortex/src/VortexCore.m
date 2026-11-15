//
//  VortexCore.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexCore.h"
#import "VortexAnimationEngine.h"
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

static Class gRootFolderViewClass = Nil;
static BOOL gHooksInstalled = NO;

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

static NSString *VortexRequireClass(const char *name, Class superclass, Class *out) {
    Class cls = objc_getClass(name);
    if (!cls) return [NSString stringWithFormat:@"class %s not found", name];
    if (superclass && ![cls isSubclassOfClass:superclass])
        return [NSString stringWithFormat:@"class %s is not a %@", name, NSStringFromClass(superclass)];
    if (out) *out = cls;
    return nil;
}

static NSString *VortexRequireInstanceMethod(Class cls, SEL sel) {
    if (!class_getInstanceMethod(cls, sel))
        return [NSString stringWithFormat:@"-[%@ %@] not found", NSStringFromClass(cls), NSStringFromSelector(sel)];
    return nil;
}

NSString *VortexCoreCompatibilityFailure(void) {
    Class folderView = Nil, rootFolderView = Nil, scrollView = Nil, listView = Nil;
    NSString *failure = nil;
    if ((failure = VortexRequireClass(VORTEX_SB_FOLDER_VIEW_CLASS, [UIView class], &folderView))) return failure;
    if ((failure = VortexRequireClass(VORTEX_SB_ROOT_FOLDER_VIEW_CLASS, folderView, &rootFolderView))) return failure;
    if ((failure = VortexRequireClass(VORTEX_SB_ICON_SCROLL_VIEW_CLASS, [UIScrollView class], &scrollView))) return failure;
    if ((failure = VortexRequireClass(VORTEX_SB_ICON_LIST_VIEW_CLASS, [UIView class], &listView))) return failure;

    // Hooked selectors.
    if ((failure = VortexRequireInstanceMethod(folderView, @selector(scrollViewDidScroll:)))) return failure;
    if ((failure = VortexRequireInstanceMethod(folderView, @selector(layoutSubviews)))) return failure;
    // Read-only accessors the engine depends on.
    if ((failure = VortexRequireInstanceMethod(rootFolderView, @selector(scrollView)))) return failure;

    // Hook-engine safety: we hook SBFolderView's OWN implementations, never
    // an inherited one, so %orig always has a real IMP to call.
    unsigned int count = 0;
    BOOL ownsScroll = NO, ownsLayout = NO;
    Method *methods = class_copyMethodList(folderView, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (sel == @selector(scrollViewDidScroll:)) ownsScroll = YES;
        if (sel == @selector(layoutSubviews)) ownsLayout = YES;
    }
    free(methods);
    if (!ownsScroll) return @"SBFolderView does not implement -scrollViewDidScroll: itself";
    if (!ownsLayout) return @"SBFolderView does not implement -layoutSubviews itself";

    gRootFolderViewClass = rootFolderView;
    return nil;
}

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
    if (v.majorVersion != 17) [notes addObject:[NSString stringWithFormat:@"iOS %ld is outside the v0.1.0 test target (17.4)", (long)v.majorVersion]];
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

        VortexConfiguration *config = [VortexPreferences loadConfiguration];
        VortexDiagnosticLoggingEnabled = config.diagnosticLogging;
        [VortexAnimationEngine sharedEngine].configuration = config;

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, VortexPreferencesChanged,
                                        (__bridge CFStringRef)VortexPreferencesChangedNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        @try {
            installer();
            gHooksInstalled = YES;
        } @catch (NSException *exception) {
            VortexReportStatus(@"fault", [NSString stringWithFormat:@"hook installation raised %@", exception.reason]);
            return;
        }
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
