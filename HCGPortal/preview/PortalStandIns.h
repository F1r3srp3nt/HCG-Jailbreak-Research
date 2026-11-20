//
//  PortalStandIns.h
//  HCG Portal — Simulator stand-ins for the SpringBoard classes Portal looks up.
//
//  PREVIEW / TESTS ONLY. Never compiled into the package. Each class has the
//  name and the selectors HCG Portal checks for (iOS 17.0.3 header evidence,
//  docs/SPRINGBOARD_RESEARCH.md), with just enough behaviour to drive Portal's
//  REAL code: a Cover Sheet with a clock, widgets, notifications, a media
//  platter and the flashlight / camera buttons; a Lock Screen manager whose
//  authentication is scripted (hold, succeed, cancel, refuse) and which shows a
//  clearly labelled stand-in for the system authentication sheet; and a test
//  double of the PROPOSED HCGNexusPortalInterface v1 (docs/INTEGRATIONS.md).
//
//  What is NOT real: SpringBoard, the real Lock Screen layout, the real
//  Face ID / passcode UI, touches from a finger, window levels and the device.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PSIAuthMode) {
    PSIAuthHold = 0, // keep the request pending until -resolvePending:
    PSIAuthSucceed,
    PSIAuthCancel,
    PSIAuthRefuse,   // -unlockWithRequest:completion: returns NO, never calls back
};

@interface SBLockScreenUnlockRequest : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) int source;
@property (nonatomic) int intent;
@property (nonatomic) BOOL wantsBiometricPresentation;
@property (nonatomic) BOOL fromContext;
@end

@interface SBDefaultCoverSheetContext : NSObject
- (SBLockScreenUnlockRequest *)createUnlockRequest;
@end

@interface CSMainPageContentViewController : UIViewController
@end

@interface SBFLockScreenDateView : UIView
@end

@interface CSComplicationContainerViewController : UIViewController
@end

@interface NCNotificationListCell : UIView
@end

@interface CSAdjunctItemView : UIView
@end

@interface CSQuickActionsButton : UIControl
@end

@interface CSCoverSheetViewController : UIViewController
/// How many times the class's own (original) -viewWillAppear: ran: proves a hook calls the original.
@property (class, nonatomic, readonly) NSUInteger originalWillAppearCalls;
@property (nonatomic, readonly) CSMainPageContentViewController *mainPageContentViewController;
@property (nonatomic, readonly) CSComplicationContainerViewController *complicationContainerViewController;
@property (nonatomic, readonly) SBFLockScreenDateView *dateView;
@property (nonatomic, readonly) SBDefaultCoverSheetContext *coverSheetContext;
@property (nonatomic, readonly) NSArray<NCNotificationListCell *> *notificationCells;
@property (nonatomic, readonly, nullable) CSAdjunctItemView *mediaView;
@property (nonatomic, readonly) CSQuickActionsButton *flashlight;
@property (nonatomic, readonly) CSQuickActionsButton *camera;
@property (nonatomic, readonly) UILabel *caption;
- (void)setNotificationCount:(NSUInteger)count;
- (void)setShowsMedia:(BOOL)shows;
@end

@interface SBLockScreenManager : NSObject
/// What Portal calls. Counted: Portal must not call it while inactive (0.1.0~beta1 did, at launch).
+ (instancetype)sharedInstance;
/// The same object for the harness, NOT counted.
+ (instancetype)standIn;
@property (class, nonatomic, readonly) NSUInteger sharedInstanceCalls;
@property (nonatomic, strong, nullable) CSCoverSheetViewController *coverSheetViewController;
@property (nonatomic) PSIAuthMode authMode;
@property (nonatomic) BOOL uiLocked;
@property (nonatomic, readonly) NSUInteger requestCount;
@property (nonatomic, readonly, nullable) SBLockScreenUnlockRequest *lastRequest;
@property (nonatomic, readonly) BOOL hasPendingRequest;
- (BOOL)isUILocked;
- (BOOL)unlockWithRequest:(id)request completion:(void (^)(BOOL success))completion;
/// Completes the held request (YES = authenticated). Returns the completion so tests can replay it.
- (nullable void (^)(BOOL))resolvePending:(BOOL)success;
@end

@interface SBCoverSheetPresentationManager : NSObject
+ (instancetype)sharedInstance; // counted, as above
+ (instancetype)standIn;        // not counted
@property (class, nonatomic, readonly) NSUInteger sharedInstanceCalls;
@property (nonatomic) BOOL visible;
- (BOOL)isVisible;
@end

/// Test double of the PROPOSED Nexus interface (Nexus 0.3.1~beta1 has none).
@interface HCGNexusPortalInterface : NSObject
+ (NSInteger)interfaceVersion;
+ (nullable instancetype)activeInterface;
+ (void)setStandInActive:(BOOL)active;
@property (class, nonatomic, readonly) NSUInteger openCount;
@property (class, nonatomic, readonly, nullable) NSString *lastSource;
- (BOOL)canOpenPanel;
- (void)openPanelFromSource:(NSString *)source completion:(void (^)(BOOL opened, NSString *_Nullable reason))completion;
@end

/// A stand-in for the injector's MSHookMessageEx (ElleKit / Substrate semantics: an
/// inherited method is first added to the class, *original receives the previous IMP).
void PSIHookMessageEx(Class cls, SEL selector, IMP replacement, IMP _Nullable *_Nullable original);

/// Darwin state as SpringBoard publishes it (preview names).
void PSIPostState(const char *name, uint64_t value);

NS_ASSUME_NONNULL_END
