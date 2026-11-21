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
//  Every call carries a gate (PortalController: "iOS still reports the device
//  unlocked and nothing relocked it since the action was selected"). The
//  launcher asks the gate on the main thread right before it calls iOS, and
//  again before the fallback; if the gate says no, nothing is opened.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PortalLaunchResult) {
    PortalLaunchResultOpened = 0,
    PortalLaunchResultFailed,      // iOS did not open it
    PortalLaunchResultRefused,     // the gate said no (locked): nothing was asked of iOS
    PortalLaunchResultUnavailable, // no launch route on this iOS
};
typedef void (^PortalLaunchCompletion)(PortalLaunchResult result);
typedef BOOL (^PortalLaunchGate)(void);

/// "opened", "could not be opened", "not opened: iPhone locked", "not opened: no launch route".
NSString *PortalLaunchResultText(PortalLaunchResult result);

@interface PortalLauncher : NSObject
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly, copy) NSString *route;
- (BOOL)isApplicationInstalled:(NSString *)bundleIdentifier;
/// Main thread only. `gate` is evaluated on the main thread right before each call into iOS.
- (void)openApplication:(NSString *)bundleIdentifier gate:(PortalLaunchGate)gate completion:(PortalLaunchCompletion)completion;
#ifdef PORTAL_PREVIEW_HOST
/// Preview / tests only (never in the package): records launches instead of opening apps.
+ (void)setPreviewLaunchHandler:(nullable BOOL (^)(NSString *bundleIdentifier))handler;
+ (void)setPreviewInstalledHandler:(nullable BOOL (^)(NSString *bundleIdentifier))handler;
#endif
@end

/// The Settings app: the supported route to HCG Animation Center's page.
FOUNDATION_EXPORT NSString *const PortalSettingsBundleIdentifier; // "com.apple.Preferences"

NS_ASSUME_NONNULL_END
