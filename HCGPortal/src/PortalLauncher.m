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

- (void)openApplication:(NSString *)bundleIdentifier completion:(PortalLaunchCompletion)completion {
#ifdef PORTAL_PREVIEW_HOST
    if (gPreviewLaunch) {
        BOOL launched = gPreviewLaunch(bundleIdentifier);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(launched);
        });
        return;
    }
#endif
    if (!_available) {
        completion(NO);
        return;
    }
    id workspace = _canOpen ? _workspace : nil;
    BOOL canFallback = _canFallback;
    NSString *bundle = [bundleIdentifier copy];
    // LaunchServices IPC off the main thread; it is user-initiated, never part
    // of a SpringBoard lifecycle callback.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ok = workspace ? [workspace openApplicationWithBundleID:bundle] : NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL launched = ok;
            if (!launched && canFallback)
                launched = [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundle suspended:NO];
            completion(launched);
        });
    });
}

@end
