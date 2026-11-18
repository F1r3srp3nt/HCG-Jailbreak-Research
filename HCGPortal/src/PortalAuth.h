//
//  PortalAuth.h
//  HCG Portal — Hakmi Capital Group
//
//  Requests the NORMAL iOS authentication (Face ID, Touch ID or passcode,
//  whatever the phone is set to) through SpringBoard's own Lock Screen unlock
//  request, and reports success or cancellation. Portal never sees, stores or
//  checks a passcode or a biometric result, and never unlocks anything itself:
//  SpringBoard decides. LocalAuthentication is not used (it would be a second,
//  separate prompt that does not unlock the phone).
//
//  Route (iOS 13 – 17, checked at run time; iOS 17.0.3 header evidence in
//  docs/SPRINGBOARD_RESEARCH.md):
//    request = [[SBLockScreenManager.sharedInstance.coverSheetViewController
//                 coverSheetContext] createUnlockRequest]        (CoverSheet's own defaults)
//              … else [[SBLockScreenUnlockRequest alloc] init] with name, source 17, intent 3
//    -[SBLockScreenManager unlockWithRequest:completion:]  → completion(BOOL success)
//
//  If the manager or the selector is missing, `available` is NO and every
//  protected destination fails closed ("Unlock your iPhone first").
//
//  The completion runs exactly once, on the main thread. A request SpringBoard
//  refuses synchronously completes with PortalAuthOutcomeRefused.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PortalAuthOutcome) {
    PortalAuthOutcomeAuthenticated = 0, // SpringBoard reported success
    PortalAuthOutcomeCancelled,         // SpringBoard reported failure or cancellation
    PortalAuthOutcomeRefused,           // SpringBoard refused the request (nothing was shown)
    PortalAuthOutcomeUnavailable,       // no authentication route on this iOS
};

typedef void (^PortalAuthCompletion)(PortalAuthOutcome outcome);

@interface PortalAuthBroker : NSObject
@property (nonatomic, readonly) BOOL available;
/// "coverSheetContext", "constructed request" or "unavailable: <reason>".
@property (nonatomic, readonly, copy) NSString *route;
- (void)refresh;
/// `name` is a non-private label for SpringBoard's logs ("HCG Portal: Open app").
- (void)requestAuthenticationNamed:(NSString *)name completion:(PortalAuthCompletion)completion;
@end

NS_ASSUME_NONNULL_END
