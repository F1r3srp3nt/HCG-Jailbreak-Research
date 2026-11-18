//
//  PortalAuth.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalAuth.h"

#import "PortalLog.h"

#import <objc/message.h>

// Private SpringBoard interfaces, declared locally and verified at run time.
@interface NSObject (PortalLockScreen)
+ (id)sharedInstance;
- (id)coverSheetViewController;
- (id)coverSheetContext;
- (id)createUnlockRequest;
- (BOOL)unlockWithRequest:(id)request completion:(void (^)(BOOL success))completion;
- (void)setName:(NSString *)name;
- (void)setSource:(int)source;
- (void)setIntent:(int)intent;
- (void)setWantsBiometricPresentation:(BOOL)wants;
@end

@implementation PortalAuthBroker

- (instancetype)init {
    if ((self = [super init])) [self refresh];
    return self;
}

static id PortalLockScreenManager(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    return [cls sharedInstance];
}

- (void)refresh {
    id manager = PortalLockScreenManager();
    if (!manager) {
        _available = NO;
        _route = @"unavailable: SBLockScreenManager missing";
    } else if (![manager respondsToSelector:@selector(unlockWithRequest:completion:)]) {
        _available = NO;
        _route = @"unavailable: unlockWithRequest:completion: missing";
    } else if ([self contextRequest:manager]) {
        _available = YES;
        _route = @"coverSheetContext";
    } else if (NSClassFromString(@"SBLockScreenUnlockRequest")) {
        _available = YES;
        _route = @"constructed request";
    } else {
        _available = NO;
        _route = @"unavailable: SBLockScreenUnlockRequest missing";
    }
}

- (id)contextRequest:(id)manager {
    if (![manager respondsToSelector:@selector(coverSheetViewController)]) return nil;
    id coverSheet = [manager coverSheetViewController];
    if (![coverSheet respondsToSelector:@selector(coverSheetContext)]) return nil;
    id context = [coverSheet coverSheetContext];
    if (![context respondsToSelector:@selector(createUnlockRequest)]) return nil;
    return [context createUnlockRequest];
}

- (void)requestAuthenticationNamed:(NSString *)name completion:(PortalAuthCompletion)completion {
    __block BOOL finished = NO;
    PortalAuthCompletion once = ^(PortalAuthOutcome outcome) {
        void (^deliver)(void) = ^{
            if (finished) return;
            finished = YES;
            completion(outcome);
        };
        if ([NSThread isMainThread]) deliver();
        else dispatch_async(dispatch_get_main_queue(), deliver);
    };

    [self refresh];
    id manager = PortalLockScreenManager();
    if (!_available || !manager) {
        PortalLogInfo("authentication unavailable (%{public}@): failing closed", _route);
        once(PortalAuthOutcomeUnavailable);
        return;
    }
    id request = [self contextRequest:manager];
    if (!request) {
        request = [[NSClassFromString(@"SBLockScreenUnlockRequest") alloc] init];
        // Values used by SpringBoard tweaks for "authenticate, then act" on iOS 13+;
        // unverified on the test phone (device row A1 records which route ran).
        if ([request respondsToSelector:@selector(setSource:)]) [request setSource:17];
        if ([request respondsToSelector:@selector(setIntent:)]) [request setIntent:3];
    }
    if ([request respondsToSelector:@selector(setName:)]) [request setName:name];
    if ([request respondsToSelector:@selector(setWantsBiometricPresentation:)]) [request setWantsBiometricPresentation:YES];

    BOOL accepted = NO;
    @try {
        accepted = [manager unlockWithRequest:request
                                   completion:^(BOOL success) {
                                       once(success ? PortalAuthOutcomeAuthenticated : PortalAuthOutcomeCancelled);
                                   }];
    } @catch (NSException *exception) {
        PortalLogError("unlock request raised %{public}@", exception.reason);
        once(PortalAuthOutcomeCancelled);
        return;
    }
    if (!accepted) {
        // SpringBoard refused the request outright: nothing will be shown.
        PortalLogInfo("unlock request refused by SpringBoard");
        once(PortalAuthOutcomeRefused);
    }
}

@end
