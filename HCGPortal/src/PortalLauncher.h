//
//  PortalLauncher.h
//  HCG Portal — Hakmi Capital Group
//
//  Opens an installed app by bundle identifier from inside SpringBoard. The
//  same verified route HCG Nexus 0.3.1~beta1 uses (HCG-Nexus
//  Sources/Platform/SpringBoard/HCGSpringBoardLauncher.m):
//    -[LSApplicationWorkspace openApplicationWithBundleID:] on a background queue,
//    falling back to SpringBoard's -launchApplicationWithIdentifier:suspended:
//    on the main thread. Both are checked at run time.
//
//  Called ONLY after the authentication for that exact action succeeded
//  (PortalController); the launcher itself never checks the lock state.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PortalLaunchCompletion)(BOOL launched);

@interface PortalLauncher : NSObject
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly, copy) NSString *route;
- (BOOL)isApplicationInstalled:(NSString *)bundleIdentifier;
- (void)openApplication:(NSString *)bundleIdentifier completion:(PortalLaunchCompletion)completion;
#ifdef PORTAL_PREVIEW_HOST
/// Preview / tests only (never in the package): records launches instead of opening apps.
+ (void)setPreviewLaunchHandler:(nullable BOOL (^)(NSString *bundleIdentifier))handler;
+ (void)setPreviewInstalledHandler:(nullable BOOL (^)(NSString *bundleIdentifier))handler;
#endif
@end

/// The Settings app: the supported route to HCG Animation Center's page.
FOUNDATION_EXPORT NSString *const PortalSettingsBundleIdentifier; // "com.apple.Preferences"

NS_ASSUME_NONNULL_END
