//
//  PortalLauncher.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalLauncher.h"

#import <UIKit/UIKit.h>

NSString *const PortalSettingsBundleIdentifier = @"com.apple.Preferences";

// Private LaunchServices API, declared locally and verified at run time.
@interface NSObject (PortalLSApplicationWorkspace)
+ (id)defaultWorkspace;
- (BOOL)applicationIsInstalled:(NSString *)bundleIdentifier;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleIdentifier;
@end

// SpringBoard's own launcher, used only as a verified fallback.
@interface UIApplication (PortalSpringBoardLaunch)
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

#ifdef PORTAL_PREVIEW_HOST
static BOOL (^gPreviewLaunch)(NSString *);
static BOOL (^gPreviewInstalled)(NSString *);
#endif

@implementation PortalLauncher {
    id _workspace;
    BOOL _canCheckInstalled;
    BOOL _canOpen;
    BOOL _canFallback;
}

- (instancetype)init {
    if ((self = [super init])) {
        Class cls = NSClassFromString(@"LSApplicationWorkspace");
        if ([cls respondsToSelector:@selector(defaultWorkspace)]) _workspace = [cls defaultWorkspace];
        _canCheckInstalled = [_workspace respondsToSelector:@selector(applicationIsInstalled:)];
        _canOpen = [_workspace respondsToSelector:@selector(openApplicationWithBundleID:)];
        _canFallback = [[UIApplication sharedApplication] respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)];
        _available = _canOpen || _canFallback;
        _route = [NSString stringWithFormat:@"%@%@%@", _canOpen ? @"LSApplicationWorkspace" : @"",
                                            _canOpen && _canFallback ? @" + " : @"",
                                            _canFallback ? @"launchApplicationWithIdentifier:suspended:" : @""];
        if (!_available) _route = @"unavailable";
#ifdef PORTAL_PREVIEW_HOST
        _available = YES;
        _route = @"preview handler";
#endif
    }
    return self;
}

#ifdef PORTAL_PREVIEW_HOST
+ (void)setPreviewLaunchHandler:(BOOL (^)(NSString *))handler {
    gPreviewLaunch = [handler copy];
}
+ (void)setPreviewInstalledHandler:(BOOL (^)(NSString *))handler {
    gPreviewInstalled = [handler copy];
}
#endif

- (BOOL)isApplicationInstalled:(NSString *)bundleIdentifier {
#ifdef PORTAL_PREVIEW_HOST
    if (gPreviewInstalled) return gPreviewInstalled(bundleIdentifier);
#endif
    if (!_canCheckInstalled) return YES; // cannot tell: let the launch report the problem
    return [_workspace applicationIsInstalled:bundleIdentifier];
}

NSString *PortalLaunchResultText(PortalLaunchResult result) {
    switch (result) {
        case PortalLaunchResultOpened: return @"opened";
        case PortalLaunchResultFailed: return @"could not be opened";
        case PortalLaunchResultRefused: return @"not opened: iPhone locked";
        case PortalLaunchResultUnavailable: return @"not opened: no launch route";
    }
    return @"not opened";
}

- (void)openApplication:(NSString *)bundleIdentifier gate:(PortalLaunchGate)gate completion:(PortalLaunchCompletion)completion {
    // Privileged action boundary: nothing is asked of iOS unless the gate passes right now.
    if (!gate || !gate()) {
        completion(PortalLaunchResultRefused);
        return;
    }
#ifdef PORTAL_PREVIEW_HOST
    if (gPreviewLaunch) {
        BOOL launched = gPreviewLaunch(bundleIdentifier);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(launched ? PortalLaunchResultOpened : PortalLaunchResultFailed);
        });
        return;
    }
#endif
    if (!_available) {
        completion(PortalLaunchResultUnavailable);
        return;
    }
    id workspace = _canOpen ? _workspace : nil;
    BOOL canFallback = _canFallback;
    NSString *bundle = [bundleIdentifier copy];
    PortalLaunchGate checkAgain = [gate copy];
    // LaunchServices IPC off the main thread; it is user-initiated, never part
    // of a SpringBoard lifecycle callback. (iOS itself still refuses to show an
    // app over a locked device; the gate is Portal's own boundary.)
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ok = workspace ? [workspace openApplicationWithBundleID:bundle] : NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                completion(PortalLaunchResultOpened);
                return;
            }
            if (!canFallback) {
                completion(PortalLaunchResultFailed);
                return;
            }
            if (!checkAgain()) { // the phone may have locked while LaunchServices answered
                completion(PortalLaunchResultRefused);
                return;
            }
            BOOL launched = [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundle suspended:NO];
            completion(launched ? PortalLaunchResultOpened : PortalLaunchResultFailed);
        });
    });
}

@end
