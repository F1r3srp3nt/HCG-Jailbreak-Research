//
//  PortalController.m
//  HCG Portal — Hakmi Capital Group
//
//  See PortalController.h. Decisions are made by the pure C core
//  (PortalCore.c): visibility, render plan, layout, menu geometry and the
//  pending protected action. This file gathers the inputs and applies the
//  results.
//
//  Security (0.1.0~beta4): Portal is an extension of the UNLOCKED iPhone.
//    - iOS decides. Portal exists on screen only while every lock-state
//      source iOS offers reports the device unlocked: the keybag
//      (-[UIApplication isProtectedDataAvailable], NO before the first unlock
//      after a reboot), SpringBoard's lock state (Darwin
//      com.apple.springboard.lockstate) and -[SBLockScreenManager isUILocked].
//      Any "locked", or any source that cannot be read, keeps it closed
//      (PortalCore portal_access). Face ID / Touch ID / passcode are never
//      touched, hooked or requested: Portal only reads the outcome.
//    - So on the locked Lock Screen nothing of Portal exists: no view, no
//      control, no accessibility element. It appears on the Cover Sheet only
//      when that is pulled down on an unlocked iPhone.
//    - Locking (lock state, screen off, keybag, Cover Sheet re-appearing)
//      revokes access at once: the overlay is removed and any pending action
//      discarded. Each revocation starts a new access epoch.
//    - Privileged actions re-check at the boundary: on selection, again when
//      the Cover Sheet has closed (portal_pending_resolve with the access
//      session), and again in the launcher right before it calls iOS.
//    - Nothing private is read: no notification content, no credentials, no
//      passcode, no biometric data. Obstacles are measured by frame only.
//    - No device command is ever executed. Devices shows "Not connected".
//

#import "PortalController.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <notify.h>

#import "PortalCompanions.h"
#import "PortalCore.h"
#import "PortalHost.h"
#import "PortalLauncher.h"
#import "PortalLog.h"
#import "PortalOverlayView.h"
#import "PortalPreferences.h"
#import "PortalView.h"

#ifndef PORTAL_BLANKED_NOTIFICATION
#define PORTAL_BLANKED_NOTIFICATION "com.apple.springboard.hasBlankedScreen"
#endif
#ifndef PORTAL_LOCKSTATE_NOTIFICATION
#define PORTAL_LOCKSTATE_NOTIFICATION "com.apple.springboard.lockstate"
#endif

@interface UIImage (PortalAppIcon)
+ (nullable UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@interface NSObject (PortalSpringBoard)
+ (id)sharedInstance;
- (id)coverSheetViewController;
- (BOOL)isVisible;
- (BOOL)isPresented;
- (BOOL)isUILocked;     // SBLockScreenManager (iOS 17.0.3 header: SBLockScreenManager.h)
- (BOOL)isInSecureApp;  // SBCoverSheetPresentationManager (iOS 17.0.3 header)
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated withCompletion:(void (^)(void))completion;
@end

static id PortalSharedInstance(NSString *className) {
    Class cls = NSClassFromString(className);
    if (![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    return [cls sharedInstance];
}

static NSString *const kOverlayIdentifier = @"com.hakmicapitalgroup.portal.overlay";

@interface PortalController : NSObject <PortalOverlayDelegate>
+ (instancetype)shared;
@end

@implementation PortalController {
    PortalHookInstaller _hookInstaller;
    BOOL _hooksInstalled;
    NSString *_hooksSummary;
    BOOL _blocked;
    BOOL _launched;
    BOOL _faulted;
    BOOL _active;
    NSString *_state;
    NSString *_detail;
    PortalSettings *_settings;

    int _blankToken, _lockToken;
    BOOL _screenOn, _locked;
    BOOL _coverSheetVisibleByHook;
    BOOL _opening;                  // a selected destination is opening (Cover Sheet closing)
    BOOL _flourishPending;          // play the opening animation the first time Portal shows after an unlock
    PortalAccessSession _access;    // iOS unlock state, as last read (closed at start)
    PortalAccess _accessDecision;
    NSString *_accessDetail;
    __weak UIViewController *_coverSheet;
    NSMutableArray *_observerTokens;
    NSTimer *_measureTimer;
    BOOL _relayoutScheduled;
    BOOL _statusScheduled;

    PortalOverlayView *_overlay;
    NSString *_hostSummary;
    PortalHostMeasurement *_measurement;
    PortalLayout _layout;
    PortalRenderPlan _plan;
    PortalVisibility _visibility;

    PortalLauncher *_launcher;
    PortalPending _pending;
    BOOL _updating;                 // update is not re-entrant
    CFTimeInterval _lastRaise;      // last bringSubviewToFront (rate-limited)
    NSUInteger _attachRetries;      // per Lock Screen session
    NSString *_phase;               // last breadcrumb written
    NSString *_previousSession;     // what the previous SpringBoard launch last recorded
    PortalDestinationProbe _probeCache;
    BOOL _probeValid;
    NSArray<PortalAppShortcut *> *_installedApps;
    NSString *_lastAction;
    NSMutableDictionary<NSString *, NSNumber *> *_counters;

    int _previewReduceMotion, _previewLowPower; // -1 = use the system
    int _previewProtectedData;                  // -1 = use the system
}

+ (instancetype)shared {
    static PortalController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[PortalController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = PortalEngineStateWaiting;
        _detail = @"";
        _blankToken = _lockToken = NOTIFY_TOKEN_INVALID;
        _screenOn = YES;
        _observerTokens = [NSMutableArray array];
        _counters = [NSMutableDictionary dictionary];
        _lastAction = @"none";
        _hooksSummary = @"not installed (Portal not enabled since this respring)";
        _hostSummary = @"none";
        _previewReduceMotion = _previewLowPower = _previewProtectedData = -1;
        portal_pending_init(&_pending);
        portal_access_session_init(&_access);
        _accessDecision = PORTAL_ACCESS_UNVERIFIED;
        _accessDetail = @"not checked (Portal inactive)";
        _visibility = PORTAL_VIS_DISABLED;
    }
    return self;
}

- (void)count:(NSString *)name {
    _counters[name] = @(_counters[name].integerValue + 1);
}

#pragma mark - Bootstrap

static void PortalPreferencesChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[PortalController shared] preferencesChanged];
    });
}

static void PortalStatusRequested(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[PortalController shared] writeStatusNow];
    });
}

- (void)bootstrapWithHookInstaller:(PortalHookInstaller)installer {
    _hookInstaller = installer;
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, NULL, PortalStatusRequested,
                                    (__bridge CFStringRef)PortalStatusRequestNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    if ([[NSFileManager defaultManager] fileExistsAtPath:PortalKillSwitchPath]) {
        [self block:PortalEngineStateKillSwitch
             detail:[NSString stringWithFormat:@"%@ exists: HCG Portal does nothing. Delete it and respring to undo.",
                                               PortalKillSwitchPath]];
        return;
    }

    _settings = [PortalPreferences loadSettings];
    PortalDiagnosticLoggingEnabled = _settings.diagnosticLogging;
    _previousSession = [PortalPreferences previousSessionSummary];
    [self breadcrumb:@"bootstrap"];

    if (!NSClassFromString(@"CSCoverSheetViewController") || !NSClassFromString(@"SBLockScreenManager")) {
        [self block:PortalEngineStateIncompatible
             detail:@"This iOS version has no CSCoverSheetViewController / SBLockScreenManager. Nothing is shown."];
        return;
    }

    // Crash guard, counted on EVERY SpringBoard launch with Portal installed, enabled or not
    // (0.1.0~beta1/2 counted only while enabled, so a crash in the disabled path never tripped it).
    {
        NSInteger unstable = [PortalPreferences consecutiveUnstableLaunches];
        if (portal_launch_guard_blocks(unstable, PORTAL_MAX_UNSTABLE_LAUNCHES)) {
            [self block:PortalEngineStateAutoDisabled
                 detail:[NSString stringWithFormat:@"%ld SpringBoard launches in a row ended within %.0f s with HCG "
                                                   @"Portal installed. Portal does nothing this launch. Turn Enable off "
                                                   @"and on (or reset), then respring, to try again.",
                                                   (long)unstable, PORTAL_STABLE_AFTER_SECONDS]];
            return;
        }
        [PortalPreferences setConsecutiveUnstableLaunches:unstable + 1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PORTAL_STABLE_AFTER_SECONDS * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [PortalPreferences setConsecutiveUnstableLaunches:0];
                           PortalLogDebug("launch marked stable");
                       });
    }

    CFNotificationCenterAddObserver(darwin, NULL, PortalPreferencesChanged,
                                    (__bridge CFStringRef)PortalPreferencesChangedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    __weak PortalController *weakSelf = self;
    __block id launchToken =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          [[NSNotificationCenter defaultCenter] removeObserver:launchToken];
                                                          launchToken = nil;
                                                          [weakSelf springBoardLaunched];
                                                      }];
    // Late injection: the launch notification was missed. Carry on anyway.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf springBoardLaunched];
    });
    [self setState:_settings.enabled ? PortalEngineStateWaiting : PortalEngineStateDisabled
            detail:_settings.enabled ? @"Waiting for SpringBoard to finish launching." : @""];
    [self writeStatusNow];
}

- (void)block:(NSString *)state detail:(NSString *)detail {
    _blocked = YES;
    [self setState:state detail:detail];
    [self writeStatusNow];
}

- (void)springBoardLaunched {
    if (_launched) return;
    _launched = YES;
    [self apply];
}

- (void)setState:(NSString *)state detail:(NSString *)detail {
    _state = state;
    _detail = detail ?: @"";
    PortalLogInfo("state %{public}@: %{public}@", state, _detail);
}

#pragma mark - Reconciliation

- (void)preferencesChanged {
    if (_blocked) return;
    @try {
        _settings = [PortalPreferences loadSettings];
        PortalDiagnosticLoggingEnabled = _settings.diagnosticLogging;
        if (!_settings.enabled) _faulted = NO; // Enable off clears a fault; on again retries
        PortalLogDebug("preferences %{public}@", _settings.description);
        [self apply];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"reload: %@", exception.reason]];
    }
}

- (void)apply {
    if (_blocked || !_launched) return;
    @try {
        if (_settings.enabled && !_faulted) {
            if ([self activate]) [self setState:PortalEngineStateActive detail:@""];
        } else {
            [self deactivate];
            if (!_faulted) [self setState:PortalEngineStateDisabled detail:@""];
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"apply: %@", exception.reason]];
        return;
    }
    [self scheduleStatus];
}

- (void)fault:(NSString *)reason {
    PortalLogError("fault: %{public}@", reason);
    _faulted = YES;
    @try {
        [self deactivate];
    } @catch (NSException *exception) {
        PortalLogError("deactivate after fault raised %{public}@", exception.reason);
    }
    [self setState:PortalEngineStateFault
            detail:[NSString stringWithFormat:@"%@ — Portal was removed from the Lock Screen. Turn Enable off and on "
                                              @"to retry.",
                                              reason]];
    [self writeStatusNow];
}

- (BOOL)activate {
    if (!_hooksInstalled && _hookInstaller) {
        [self breadcrumb:@"installing hooks"];
        NSString *failure = _hookInstaller();
        [self breadcrumb:failure ? @"hooks unavailable" : @"hooks installed"];
        if (failure) {
            // Nothing was hooked or attached: SpringBoard and the Lock Screen are untouched.
            [self noteHooks:[NSString stringWithFormat:@"none: %@", failure]];
            [self setState:PortalEngineStateIncompatible
                    detail:[NSString stringWithFormat:@"%@ HCG Portal stays inactive and the Lock Screen is unchanged. "
                                                      @"Turn Enable off and on, or respring, to try again.",
                                                      failure]];
            return NO;
        }
        _hooksInstalled = YES;
    }
    if (!_launcher) _launcher = [[PortalLauncher alloc] init];
    if (!_active) {
        _active = YES;
        [self startSystemObservers];
    }
    _probeValid = NO;
    [self refreshApps];
    [self update];
    return YES;
}

- (void)deactivate {
    if (_pending.awaiting) {
        portal_pending_cancel(&_pending);
        [self count:@"actionsDiscarded"];
        _lastAction = @"Portal turned off: the pending action was discarded";
    }
    _opening = NO;
    _flourishPending = NO;
    _active = NO;
    portal_access_session_apply(&_access, PORTAL_ACCESS_UNVERIFIED); // closed; a new epoch on the next grant
    _accessDecision = PORTAL_ACCESS_UNVERIFIED;
    _accessDetail = @"not checked (Portal inactive)";
    [self stopSystemObservers];
    [_measureTimer invalidate];
    _measureTimer = nil;
    if (_overlay) {
        [self detachOverlay];
        _overlay.delegate = nil;
        _overlay = nil;
        [PortalCompanions postLightingEvent:@"hidden" palette:_settings.appearance.palette intensity:0];
    }
    _hostSummary = @"none";
    _visibility = _blocked ? PORTAL_VIS_KILL_SWITCH : PORTAL_VIS_DISABLED;
}

#pragma mark - System observers

static BOOL PortalReadNotifyState(int token, uint64_t *state) {
    if (token == NOTIFY_TOKEN_INVALID) return NO;
    return notify_get_state(token, state) == NOTIFY_STATUS_OK;
}

- (void)startSystemObservers {
    __weak PortalController *weakSelf = self;
    dispatch_queue_t main = dispatch_get_main_queue();
    if (notify_register_dispatch(PORTAL_BLANKED_NOTIFICATION, &_blankToken, main, ^(int token) {
            [weakSelf blankedChanged];
        }) != NOTIFY_STATUS_OK)
        _blankToken = NOTIFY_TOKEN_INVALID;
    if (notify_register_dispatch(PORTAL_LOCKSTATE_NOTIFICATION, &_lockToken, main, ^(int token) {
            [weakSelf lockStateChanged];
        }) != NOTIFY_STATUS_OK)
        _lockToken = NOTIFY_TOKEN_INVALID;
    uint64_t state = 0;
    _screenOn = PortalReadNotifyState(_blankToken, &state) ? state == 0 : YES; // unreadable: assume lit (access decides)
    state = 0;
    _locked = PortalReadNotifyState(_lockToken, &state) ? state != 0 : YES; // unreadable: locked

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    // The keybag locking or unlocking (public notifications): re-read every source.
    for (NSNotificationName name in @[
             UIApplicationProtectedDataWillBecomeUnavailable, UIApplicationProtectedDataDidBecomeAvailable
         ]) {
        [_observerTokens addObject:[center addObserverForName:name
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
                                                       [weakSelf accessSourceChanged:@"keybag"];
                                                   }]];
    }
    for (NSNotificationName name in @[
             UIAccessibilityReduceMotionStatusDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification
         ]) {
        [_observerTokens addObject:[center addObserverForName:name
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
                                                       [weakSelf update];
                                                   }]];
    }
}

- (void)stopSystemObservers {
    if (_blankToken != NOTIFY_TOKEN_INVALID) notify_cancel(_blankToken);
    if (_lockToken != NOTIFY_TOKEN_INVALID) notify_cancel(_lockToken);
    _blankToken = _lockToken = NOTIFY_TOKEN_INVALID;
    for (id token in _observerTokens) [[NSNotificationCenter defaultCenter] removeObserver:token];
    [_observerTokens removeAllObjects];
}

- (void)blankedChanged {
    @try {
        uint64_t state = 0;
        _screenOn = PortalReadNotifyState(_blankToken, &state) ? state == 0 : YES;
        if (_screenOn) {
            [self refreshApps]; // an app may have been removed meanwhile
            _probeValid = NO;
        }
        if (!_screenOn) {
            [_overlay collapseAnimated:NO];
            if (_pending.awaiting) {
                // The phone went dark while something was opening: never act later.
                portal_pending_cancel(&_pending);
                _opening = NO;
                [self count:@"actionsDiscarded"];
                _lastAction = @"Screen turned off: the pending action was discarded";
            }
        }
        [self refreshAccess:@"screen"];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"screen state: %@", exception.reason]];
    }
}

- (void)lockStateChanged {
    @try {
        uint64_t state = 0;
        _locked = PortalReadNotifyState(_lockToken, &state) ? state != 0 : YES; // unreadable: locked
        [self refreshAccess:@"lock state"];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"lock state: %@", exception.reason]];
    }
}

- (void)accessSourceChanged:(NSString *)source {
    @try {
        [self refreshAccess:source];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"%@: %@", source, exception.reason]];
    }
}

#pragma mark - Access (the iOS unlock state)

static int PortalSignal(BOOL known, BOOL value) {
    return known ? (value ? PORTAL_SIGNAL_YES : PORTAL_SIGNAL_NO) : PORTAL_SIGNAL_UNKNOWN;
}

/// Reads every lock-state source iOS offers, without changing anything. Only while Portal is
/// active and SpringBoard has finished launching (SpringBoard's singletons are never created
/// by Portal).
- (PortalAccessInput)readAccessInput:(NSString **)detail {
    PortalAccessInput in;
    NSMutableArray<NSString *> *notes = [NSMutableArray array];
    BOOL protectedData = [UIApplication sharedApplication].isProtectedDataAvailable;
#ifdef PORTAL_PREVIEW_HOST
    if (_previewProtectedData >= 0) protectedData = _previewProtectedData != 0;
#endif
    in.protectedDataAvailable = protectedData ? PORTAL_SIGNAL_YES : PORTAL_SIGNAL_NO;
    if (!protectedData) [notes addObject:@"keybag locked (protected data unavailable)"];

    uint64_t state = 0;
    BOOL readable = PortalReadNotifyState(_lockToken, &state);
    in.lockStateLocked = PortalSignal(readable, state != 0);
    if (!readable) [notes addObject:@"lockstate unreadable"];
    else if (state != 0) [notes addObject:@"lockstate locked"];

    id manager = PortalSharedInstance(@"SBLockScreenManager");
    BOOL hasUILocked = [manager respondsToSelector:@selector(isUILocked)];
    BOOL uiLocked = hasUILocked && [manager isUILocked];
    in.uiLocked = PortalSignal(hasUILocked, uiLocked);
    if (!hasUILocked) [notes addObject:@"SBLockScreenManager -isUILocked unavailable"];
    else if (uiLocked) [notes addObject:@"Lock Screen UI locked"];

    id presentation = PortalSharedInstance(@"SBCoverSheetPresentationManager");
    BOOL hasSecureApp = [presentation respondsToSelector:@selector(isInSecureApp)];
    BOOL secureApp = hasSecureApp && [presentation isInSecureApp];
    in.inSecureApp = PortalSignal(hasSecureApp, secureApp);
    if (secureApp) [notes addObject:@"camera over the Lock Screen"];

    uint64_t blank = 0;
    BOOL blankReadable = PortalReadNotifyState(_blankToken, &blank);
    in.screenOn = PortalSignal(blankReadable, blank == 0);
    if (blankReadable && blank != 0) [notes addObject:@"screen off"];

    if (detail) *detail = notes.count ? [notes componentsJoinedByString:@", "] : @"every source reports unlocked";
    return in;
}

/// Re-reads the unlock state and applies it. Revocation is immediate: the overlay leaves the
/// Cover Sheet and anything pending is discarded. Never calls -update (callers do).
- (BOOL)refreshAccess:(NSString *)trigger {
    if (!_active || !_launched) {
        portal_access_session_apply(&_access, PORTAL_ACCESS_UNVERIFIED);
        _accessDecision = PORTAL_ACCESS_UNVERIFIED;
        return NO;
    }
    NSString *detail = nil;
    PortalAccessInput input = [self readAccessInput:&detail];
    PortalAccess decision = portal_access(&input);
    BOOL wasGranted = _access.granted;
    BOOL revoked = portal_access_session_apply(&_access, decision);
    _accessDecision = decision;
    _accessDetail = detail;
    if (revoked) [self accessRevoked:trigger ?: @"update"];
    if (!wasGranted && _access.granted) {
        [self count:@"accessGrants"];
        _flourishPending = YES;
        _probeValid = NO;
        [self refreshApps];
    }
    if (wasGranted != _access.granted) {
        PortalLogInfo("access %{public}s (%{public}@): %{public}@", portal_access_name(decision), trigger ?: @"update", detail);
        [self scheduleStatus];
    }
    return _access.granted;
}

- (void)accessRevoked:(NSString *)trigger {
    [self count:@"accessRevocations"];
    _flourishPending = NO;
    if (_overlay.expanded) [_overlay collapseAnimated:NO];
    [self detachOverlay];
    if (_pending.awaiting) {
        portal_pending_cancel(&_pending);
        [self count:@"actionsDiscarded"];
        _lastAction = [NSString stringWithFormat:@"iPhone locked (%@): the pending action was discarded", trigger];
    }
    _opening = NO;
}

/// Whether something selected at `epoch` may still run: re-reads the sources now.
- (BOOL)accessPermitsEpoch:(unsigned)epoch {
    [self refreshAccess:@"action"];
    return portal_access_permits(&_access, epoch);
}

- (BOOL)reduceMotion {
    return _previewReduceMotion >= 0 ? _previewReduceMotion : UIAccessibilityIsReduceMotionEnabled();
}

- (BOOL)lowPower {
    return _previewLowPower >= 0 ? _previewLowPower : [NSProcessInfo processInfo].lowPowerModeEnabled;
}

#pragma mark - Cover Sheet

- (UIViewController *)currentCoverSheet {
    UIViewController *cs = _coverSheet;
    if (cs) return cs;
    Class manager = NSClassFromString(@"SBLockScreenManager");
    if ([manager respondsToSelector:@selector(sharedInstance)]) {
        id m = [manager sharedInstance];
        if ([m respondsToSelector:@selector(coverSheetViewController)]) {
            id vc = [m coverSheetViewController];
            if ([vc isKindOfClass:[UIViewController class]]) cs = vc;
        }
    }
    _coverSheet = cs;
    return cs;
}

- (BOOL)coverSheetVisible {
    Class cls = NSClassFromString(@"SBCoverSheetPresentationManager");
    if ([cls respondsToSelector:@selector(sharedInstance)]) {
        id m = [cls sharedInstance];
        if ([m respondsToSelector:@selector(isVisible)]) return [m isVisible];
        if ([m respondsToSelector:@selector(isPresented)]) return [m isPresented];
    }
    if (_coverSheetVisibleByHook) return YES;
    UIViewController *cs = [self currentCoverSheet];
    return cs.isViewLoaded && cs.view.window && !cs.view.window.hidden;
}

- (void)adoptCoverSheet:(UIViewController *)coverSheet {
    if (coverSheet) _coverSheet = coverSheet; // weak: never keeps SpringBoard's controller alive
}

/// Attaches the single overlay to the Cover Sheet's main page, once per host. Called only
/// while the Cover Sheet is on screen AND iOS reports the device unlocked (see -update). Returns the host,
/// or nil: then Portal stays hidden and the Lock Screen is left exactly as it is.
- (UIView *)attachIfPossible {
    UIViewController *cs = [self currentCoverSheet];
    NSString *reason = nil;
    UIView *host = [PortalHost hostViewForCoverSheet:cs reason:&reason];
    if (!host) {
        _hostSummary = reason ?: @"Lock Screen container unavailable";
        [self detachOverlay];
        return nil;
    }
    if (!_overlay) {
        _overlay = [[PortalOverlayView alloc] initWithFrame:host.bounds];
        _overlay.accessibilityIdentifier = kOverlayIdentifier;
        _overlay.delegate = self;
        _overlay.hidden = YES;
    }
    if (_overlay.superview != host) {
        [self breadcrumb:@"attaching to the Lock Screen"];
        if (_overlay.superview) [self detachOverlay];
        _overlay.hidden = YES; // shown by -update once measured
        _overlay.frame = host.bounds;
        [host addSubview:_overlay];
        _lastRaise = CACurrentMediaTime();
        [self count:@"attaches"];
        [self breadcrumb:@"on the Lock Screen"];
    } else if (host.subviews.lastObject != _overlay) {
        // Something was added above the portal: raise it, at most once a second, so it
        // never fights the Lock Screen's own layout. Too soon: check again shortly (coalesced).
        if (CACurrentMediaTime() - _lastRaise > 1.0) {
            [host bringSubviewToFront:_overlay];
            _lastRaise = CACurrentMediaTime();
            [self count:@"raises"];
        } else {
            [self scheduleRelayout];
        }
    }
    _hostSummary = reason;
    return host;
}

/// Removes the overlay from SpringBoard's view hierarchy and cancels everything that could
/// call back into it. Between Lock Screen sessions Portal leaves nothing inside the Cover Sheet.
- (void)detachOverlay {
    [_measureTimer invalidate];
    _measureTimer = nil;
    if (!_overlay.superview) return;
    [_overlay prepareForDetach];
    _overlay.hidden = YES;
    [_overlay removeFromSuperview];
    [self count:@"detaches"];
    [self breadcrumb:@"off the Lock Screen"];
}

- (void)breadcrumb:(NSString *)phase {
    if ([phase isEqualToString:_phase]) return;
    _phase = [phase copy];
    [PortalPreferences recordPhase:phase];
}

- (void)coverSheetWillAppear:(id)coverSheet {
    if (!_active) return;
    @try {
        _coverSheetVisibleByHook = YES;
        _attachRetries = 0;
        [self refreshAccess:@"Cover Sheet appeared"]; // locking brings the Cover Sheet back
        [self adoptCoverSheet:[coverSheet isKindOfClass:[UIViewController class]] ? coverSheet : nil];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"appear: %@", exception.reason]];
    }
}

- (void)coverSheetDidDisappear:(id)coverSheet {
    if (!_active) return;
    @try {
        _coverSheetVisibleByHook = NO;
        [self detachOverlay];         // whatever SpringBoard's own state says, leave the Cover Sheet now
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"disappear: %@", exception.reason]];
    }
}

- (void)coverSheetDidLayout:(id)coverSheet {
    if (!_active || _visibility == PORTAL_VIS_SCREEN_OFF) return;
    [self scheduleRelayout];
}

- (void)scheduleRelayout {
    // Lock Screen layout passes (dozens per second during transitions) are coalesced into at
    // most one update every 250 ms, always outside SpringBoard's own layout pass.
    if (_relayoutScheduled || !_active) return;
    _relayoutScheduled = YES;
    __weak PortalController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PortalController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_relayoutScheduled = NO;
        [strongSelf update];
    });
}

#pragma mark - Update (the one place that applies decisions)

- (void)update {
    if (!_active) return;
    if (_updating) { // never re-entered from a callback it triggers
        [self scheduleRelayout];
        return;
    }
    _updating = YES;
    [self count:@"updates"];
    @try {
        PortalAppearance appearance = _settings.appearance;
        _plan = portal_render_plan(&appearance, [self reduceMotion], [self lowPower], _settings.lowPowerPolicy,
                                   _settings.unlockAnimation);
        [self refreshAccess:nil]; // every update re-reads the unlock state first
        BOOL coverSheetVisible = [self coverSheetVisible];

        // Attached only while the Cover Sheet is on screen on an UNLOCKED iPhone; detached otherwise.
        BOOL eligible = _launched && _screenOn && coverSheetVisible && _access.granted;
        UIView *host = nil;
        if (eligible) {
            host = [self attachIfPossible];
            if (!host && _attachRetries < 6) { // the main page may not be in its window yet
                _attachRetries++;
                [self scheduleRelayout];
            }
        } else {
            [self detachOverlay];
        }
        if (host) {
            _overlay.frame = host.bounds;
            _measurement = [PortalHost measureHost:host coverSheet:[self currentCoverSheet] exclude:_overlay];
            PortalLayoutInput input = _measurement.input;
            PortalPlacement placement = _settings.placement;
            _layout = portal_layout(&input, &placement);
        }

        PortalVisibilityInput v;
        memset(&v, 0, sizeof v);
        v.enabled = _settings.enabled;
        v.killSwitch = 0;
        v.fault = _faulted;
        v.hostAttached = host != nil || !eligible; // when not eligible, report the real reason
        v.coverSheetVisible = coverSheetVisible;
        v.screenOn = _screenOn;
        v.accessGranted = _access.granted;
        v.opening = _opening;
        v.layoutMode = _layout.mode;
        v.planDraws = _plan.draw;
        PortalVisibility previous = _visibility;
        _visibility = portal_visibility(&v);
        BOOL visible = _visibility == PORTAL_VIS_VISIBLE;

        if (_overlay.superview) {
            _overlay.animationsAllowed = _plan.animate;
            _overlay.palette = _settings.appearance.palette;
            [_overlay.portalView applyAppearance:_settings.appearance plan:_plan];
            if (visible) {
                PortalLayoutInput input = _measurement.input;
                [_overlay applyLayout:_layout safe:input.safe animated:previous == PORTAL_VIS_VISIBLE];
                // Availability is refreshed while collapsed, so an open menu never rebuilds under a finger.
                if (!_overlay.expanded) [_overlay setMainItems:[self mainItems]];
                if (_flourishPending && previous != PORTAL_VIS_VISIBLE) {
                    // The first appearance after an unlock ("Opening animation on unlock").
                    _flourishPending = NO;
                    if (_plan.unlockAnimation) {
                        [_overlay.portalView playUnlockFlourish];
                        [self count:@"unlockFlourishes"];
                        [PortalCompanions postLightingEvent:@"unlock" palette:_settings.appearance.palette
                                                  intensity:_settings.appearance.intensity];
                    }
                }
            } else if (_overlay.expanded) {
                [_overlay collapseAnimated:NO];
            }
            _overlay.hidden = !visible;
            _overlay.portalView.paused = !visible; // hidden or dark: no animation work at all
        }
        if (visible) {
            if (!_measureTimer) {
                // A slow safety net for layout changes the hook does not report
                // (a notification arriving). Only while the portal is on screen.
                __weak PortalController *weakSelf = self;
                _measureTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                                repeats:YES
                                                                  block:^(NSTimer *t) {
                                                                      [weakSelf update];
                                                                  }];
                _measureTimer.tolerance = 0.5;
            }
        } else {
            [_measureTimer invalidate];
            _measureTimer = nil;
        }
        if (previous != _visibility) {
            PortalLogDebug("visibility %s -> %s", portal_visibility_name(previous), portal_visibility_name(_visibility));
            if (!visible && previous == PORTAL_VIS_VISIBLE)
                [PortalCompanions postLightingEvent:@"hidden" palette:_settings.appearance.palette intensity:0];
            [self scheduleStatus];
        }
        if (portal_pending_expire(&_pending, CACurrentMediaTime())) {
            _opening = NO;
            [self count:@"actionsDiscarded"];
            _lastAction = @"The destination did not open in time: the pending action was discarded";
        }
    } @catch (NSException *exception) {
        _updating = NO;
        [self fault:[NSString stringWithFormat:@"update: %@", exception.reason]];
        return;
    }
    _updating = NO;
}

#pragma mark - Destinations

- (PortalDestinationProbe)probe {
    // File and class checks are cached; refreshed on enable, screen on and when the menu opens.
    if (_probeValid) return _probeCache;
    PortalDestinationProbe p;
    memset(&p, 0, sizeof p);
    p.launcherAvailable = _launcher.available;
    p.nexusInstalled = [PortalCompanions nexusInstalled];
    p.nexusOpenInterface = [PortalCompanions nexusOpenInterfaceAvailable];
    p.animationCenterInstalled = [PortalCompanions animationCenterInstalled];
    p.appCount = (int)_installedApps.count;
    _probeCache = p;
    _probeValid = YES;
    return p;
}

- (void)refreshApps {
    NSMutableArray *apps = [NSMutableArray array];
    for (PortalAppShortcut *app in _settings.apps)
        if ([_launcher isApplicationInstalled:app.bundleIdentifier]) [apps addObject:app];
    _installedApps = apps;
    _probeValid = NO;
}

static NSString *PortalStatusText(PortalAvailability a) {
    switch (a) {
        case PORTAL_AVAIL_AVAILABLE: return @"";
        case PORTAL_AVAIL_NOT_INSTALLED: return @"Not installed";
        case PORTAL_AVAIL_NEEDS_INTERFACE: return @"Update needed";
        case PORTAL_AVAIL_NOT_CONNECTED: return @"Not connected";
        case PORTAL_AVAIL_NO_APPS: return @"None chosen";
        case PORTAL_AVAIL_LAUNCHER_UNAVAILABLE: return @"Unavailable";
    }
    return @"Unavailable";
}

- (NSArray<PortalMenuItem *> *)mainItems {
    PortalDestinationProbe probe = [self probe];
    NSArray *spec = @[
        @[ @(PORTAL_DEST_NEXUS), @"circle.hexagongrid.fill" ], @[ @(PORTAL_DEST_BACKGROUNDS), @"photo.on.rectangle.angled" ],
        @[ @(PORTAL_DEST_DEVICES), @"dot.radiowaves.left.and.right" ], @[ @(PORTAL_DEST_APPS), @"square.grid.2x2.fill" ]
    ];
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *s in spec) {
        int dest = [s[0] intValue];
        PortalMenuItem *item = [PortalMenuItem itemWithTitle:[PortalCompanions titleForDestination:dest]
                                                      symbol:s[1]
                                                 destination:dest
                                                        item:-1];
        item.availability = portal_destination_availability(dest, &probe);
        item.statusText = PortalStatusText(item.availability);
        [items addObject:item];
    }
    return items;
}

- (NSArray<PortalMenuItem *> *)appItems {
    PortalDestinationProbe probe = [self probe];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < _installedApps.count && i < PORTAL_MENU_MAX_ITEMS; i++) {
        PortalAppShortcut *app = _installedApps[i];
        PortalMenuItem *item = [PortalMenuItem itemWithTitle:app.name symbol:@"app.fill" destination:PORTAL_DEST_APP_ITEM item:(int)i];
        if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
            item.image = [UIImage _applicationIconImageForBundleIdentifier:app.bundleIdentifier format:0 scale:UIScreen.mainScreen.scale];
        item.availability = portal_destination_availability(PORTAL_DEST_APP_ITEM, &probe);
        item.statusText = PortalStatusText(item.availability);
        [items addObject:item];
    }
    return items;
}

#pragma mark PortalOverlayDelegate

- (void)portalOverlayWillExpand:(PortalOverlayView *)overlay {
    // Companions may have been installed or removed since the last probe: check again so the
    // menu that is about to open shows the current availability.
    _probeValid = NO;
    [overlay setMainItems:[self mainItems]];
}

- (void)portalOverlayDidExpand:(PortalOverlayView *)overlay {
    [self count:@"expansions"];
    [PortalCompanions postLightingEvent:@"expanded" palette:_settings.appearance.palette intensity:_settings.appearance.intensity];
}

- (void)portalOverlayDidCollapse:(PortalOverlayView *)overlay {
    [self count:@"collapses"];
    [PortalCompanions postLightingEvent:@"collapsed" palette:_settings.appearance.palette intensity:_settings.appearance.intensity];
}

- (void)portalOverlay:(PortalOverlayView *)overlay didSelectItem:(PortalMenuItem *)item {
    @try {
        [self select:item];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"select: %@", exception.reason]];
    }
}

- (void)select:(PortalMenuItem *)item {
    // Action boundary 1: iOS must report the device unlocked right now. If not, the overlay is
    // already gone (refreshAccess revoked it) and nothing happens.
    if (![self refreshAccess:@"selection"]) {
        [self count:@"selectionsRefused"];
        [self update];
        return;
    }
    if (_pending.awaiting) {
        [_overlay showMessage:@"Opening…"];
        return;
    }
    PortalDestinationProbe probe = [self probe];
    PortalAvailability availability = portal_destination_availability(item.destination, &probe);
    if (availability != PORTAL_AVAIL_AVAILABLE) {
        [self count:@"unavailableTaps"];
        [_overlay showMessage:[PortalCompanions messageForDestination:item.destination availability:availability]];
        return;
    }
    if (item.destination == PORTAL_DEST_APPS) {
        [self refreshApps];
        [_overlay showAppItems:[self appItems]];
        return;
    }
    if (item.destination == PORTAL_DEST_APP_ITEM && (item.item < 0 || item.item >= (int)_installedApps.count)) {
        [_overlay showMessage:@"That app is no longer installed."];
        return;
    }
    if (!portal_destination_performs_action(item.destination)) return;

    unsigned generation =
        portal_pending_begin(&_pending, item.destination, item.item, CACurrentMediaTime(), _access.epoch);
    if (!generation) return;
    [self count:@"actionsRequested"];
    [self breadcrumb:[NSString stringWithFormat:@"selected %s", portal_destination_id(item.destination)]];
    _opening = YES;
    [_overlay collapseAnimated:NO];
    [self update];
    __weak PortalController *weakSelf = self;
    [self closeCoverSheetThen:^(BOOL closed) {
        [weakSelf openingPrepared:generation closed:closed];
    }];
}

/// Closes the Cover Sheet (as a swipe up would) so the destination opens in front, then calls
/// `next` once on the main queue. Without SpringBoard's interface it just continues: opening an
/// app takes the Cover Sheet away itself.
- (void)closeCoverSheetThen:(void (^)(BOOL closed))next {
    __block BOOL called = NO;
    void (^once)(BOOL) = ^(BOOL closed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (called) return;
            called = YES;
            next(closed);
        });
    };
    id manager = PortalSharedInstance(@"SBCoverSheetPresentationManager");
    if ([self coverSheetVisible] && [manager respondsToSelector:@selector(setCoverSheetPresented:animated:withCompletion:)]) {
        @try {
            [manager setCoverSheetPresented:NO
                                   animated:YES
                             withCompletion:^{
                                 once(YES);
                             }];
        } @catch (NSException *exception) {
            PortalLogError("closing the Cover Sheet raised %{public}@", exception.reason);
            once(NO);
        }
    } else {
        once(YES);
    }
}

- (void)openingPrepared:(unsigned)generation closed:(BOOL)closed {
    @try {
        BOOL current = _pending.awaiting && _pending.generation == generation;
        // Action boundary 2: every source is read again now. A relock since the selection (even
        // if unlocked again meanwhile) changed the access epoch and discards the action.
        [self refreshAccess:@"before opening"];
        PortalPendingOutcome o = portal_pending_resolve(&_pending, generation, closed, CACurrentMediaTime(), &_access);
        if (current) _opening = NO;
        if (!o.perform) {
            if (current) {
                [self count:@"actionsDiscarded"];
                _lastAction = !_access.granted ? @"iPhone locked before it opened: nothing was done"
                              : closed         ? @"Locked and unlocked again, or too late: nothing was done"
                                               : @"The Cover Sheet did not close: nothing was done";
            }
            [self update];
            [self scheduleStatus];
            return;
        }
        [self perform:o];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"opening: %@", exception.reason]];
    }
}

- (void)perform:(PortalPendingOutcome)o {
    [self count:@"actionsPerformed"];
    [self breadcrumb:[NSString stringWithFormat:@"opening %s", portal_destination_id(o.destination)]];
    [PortalCompanions postLightingEvent:@"opened" palette:_settings.appearance.palette intensity:_settings.appearance.intensity];
    __weak PortalController *weakSelf = self;
    unsigned epoch = _access.epoch;
    // Action boundary 3: the launcher asks again right before it calls iOS.
    BOOL (^gate)(void) = ^BOOL {
        PortalController *strongSelf = weakSelf;
        return strongSelf && [strongSelf accessPermitsEpoch:epoch];
    };
    switch (o.destination) {
        case PORTAL_DEST_APP_ITEM: {
            if (o.item < 0 || o.item >= (int)_installedApps.count) {
                _lastAction = @"The chosen app disappeared before it could open";
                break;
            }
            NSString *bundle = _installedApps[o.item].bundleIdentifier;
            int index = o.item + 1;
            _lastAction = [NSString stringWithFormat:@"Opening app %d", index];
            [_launcher openApplication:bundle
                                  gate:gate
                            completion:^(PortalLaunchResult result) {
                                [weakSelf noteAction:[NSString stringWithFormat:@"App %d %@", index, PortalLaunchResultText(result)]];
                            }];
            break;
        }
        case PORTAL_DEST_BACKGROUNDS: {
            _lastAction = @"Opening Settings (HCG Animation Center)";
            [_launcher openApplication:PortalSettingsBundleIdentifier
                                  gate:gate
                            completion:^(PortalLaunchResult result) {
                                [weakSelf noteAction:[NSString stringWithFormat:@"Settings for HCG Animation Center %@",
                                                                                PortalLaunchResultText(result)]];
                            }];
            break;
        }
        case PORTAL_DEST_NEXUS: {
            if (!gate()) {
                _lastAction = @"iPhone locked: HCG Nexus was not opened";
                break;
            }
            _lastAction = @"Opening HCG Nexus";
            [PortalCompanions openNexusPanelWithCompletion:^(BOOL opened, NSString *reason) {
                [weakSelf noteAction:opened ? @"HCG Nexus opened"
                                            : [NSString stringWithFormat:@"HCG Nexus did not open: %@", reason ?: @"no reason"]];
            }];
            break;
        }
        default:
            _lastAction = @"Nothing to do";
            break;
    }
    [self scheduleStatus];
}

- (void)noteAction:(NSString *)action {
    _lastAction = action;
    PortalLogInfo("%{public}@", action);
    [self scheduleStatus];
}

#pragma mark - Status

- (NSDictionary *)statusDictionary {
    PortalLayoutInput input = _measurement.input;
    // SpringBoard's Lock Screen objects (SBLockScreenManager, SBCoverSheetPresentationManager)
    // and companions' runtime interfaces are only consulted while Portal is active, which is
    // never before SpringBoard has finished launching. The bootstrap writes this status from
    // the constructor's queue on every launch, enabled or not: it must not create or call
    // SpringBoard singletons there (0.1.0~beta1 did; see CHANGELOG 0.1.0~beta2).
    BOOL live = _active && _launched;
    NSString *scene = live ? [NSString stringWithFormat:@"screen %@, lockstate %@, Cover Sheet %@",
                                                        _screenOn ? @"on" : @"off", _locked ? @"locked" : @"unlocked",
                                                        [self coverSheetVisibleSafe] ? @"visible" : @"hidden"]
                           : @"not observed (Portal inactive)";
    NSDictionary *touches = PortalOverlayTouchDiagnostics();
    NSString *touch = [NSString stringWithFormat:@"%@ down, %@ up, %@ cancelled, %@ taps, %@ activations; last cancelled by %@",
                                                 touches[@"down"], touches[@"up"], touches[@"cancelled"], touches[@"taps"],
                                                 touches[@"activations"], touches[@"lastCanceller"]];
    return @{
        PortalStatusKeyState : _state ?: @"",
        PortalStatusKeyDetail : _detail ?: @"",
        PortalStatusKeyVisibility : @(portal_visibility_name(_visibility)),
        PortalStatusKeyLayout : _measurement ? [NSString stringWithFormat:@"%s, %.0f pt at (%.0f, %.0f); anchor %@ at %.0f; obstacles: %@",
                                                                           portal_layout_mode_name(_layout.mode), _layout.diameter,
                                                                           _layout.cx, _layout.cy, _measurement.anchorSource,
                                                                           input.anchorKnown ? input.anchorBottom : _layout.anchor,
                                                                           _measurement.obstacleSummary]
                                             : @"not measured yet",
        PortalStatusKeyPlan : [NSString stringWithFormat:@"%@%@%@", _plan.draw ? (_plan.animate ? @"animating" : @"static") : @"hidden",
                                                         _plan.particles ? @", particles" : @"",
                                                         _plan.reason == PORTAL_PLAN_REDUCE_MOTION      ? @" (Reduce Motion)"
                                                         : _plan.reason == PORTAL_PLAN_LOW_POWER_STATIC ? @" (Low Power: static)"
                                                         : _plan.reason == PORTAL_PLAN_LOW_POWER_ECONOMY ? @" (Low Power: economy)"
                                                         : _plan.reason == PORTAL_PLAN_LOW_POWER_HIDDEN  ? @" (Low Power: hidden)"
                                                                                                         : @""],
        PortalStatusKeyHost : _hostSummary ?: @"none",
        PortalStatusKeyScene : scene,
        PortalStatusKeyAccess : [NSString stringWithFormat:@"%s: %@", portal_access_name(_accessDecision), _accessDetail ?: @""],
        PortalStatusKeyTouch : touch,
        PortalStatusKeyLauncher : _launcher.route ?: @"not checked",
        PortalStatusKeyCompanions : [PortalCompanions summaryIncludingRuntime:live],
        PortalStatusKeyLastAction : _lastAction ?: @"none",
        PortalStatusKeyCounters : [_counters copy],
        PortalStatusKeyHooks : _hooksSummary ?: @"",
        PortalStatusKeyPreviousSession : _previousSession ?: @"",
        PortalStatusKeyPhase : _phase ?: @"",
        PortalStatusKeyTweakVersion : @PORTAL_VERSION,
        PortalStatusKeyBuildID : @PORTAL_BUILD_ID,
        PortalStatusKeySystemVersion : [NSProcessInfo processInfo].operatingSystemVersionString ?: @"",
        PortalStatusKeyTimestamp : [NSDate date],
    };
}

- (BOOL)coverSheetVisibleSafe {
    if (!_active || !_launched) return NO; // never touch SpringBoard's singletons while inactive
    @try {
        return [self coverSheetVisible];
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)scheduleStatus {
    if (_statusScheduled) return;
    _statusScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_statusScheduled = NO;
        [self writeStatusNow];
    });
}

- (void)writeStatusNow {
    @try {
        [PortalPreferences writeStatus:[self statusDictionary]];
        notify_post(PortalStatusUpdatedNotification.UTF8String);
    } @catch (NSException *exception) {
        PortalLogError("could not write status: %{public}@", exception.reason);
    }
}

#pragma mark - Preview hooks

- (void)noteHooks:(NSString *)summary {
    _hooksSummary = [summary copy];
}

#ifdef PORTAL_PREVIEW_HOST
- (PortalOverlayView *)previewOverlay {
    return _overlay;
}
- (BOOL)previewMeasureTimerRunning {
    return _measureTimer.isValid;
}
- (void)previewSetReduceMotion:(int)rm lowPower:(int)lp {
    _previewReduceMotion = rm;
    _previewLowPower = lp;
    [self update];
}
- (void)previewSetProtectedData:(int)available {
    _previewProtectedData = available;
    [self accessSourceChanged:@"keybag"];
}
#endif

@end

#pragma mark - C entry points

void PortalControllerBootstrap(PortalHookInstaller installHooks) {
    @autoreleasepool {
#ifndef PORTAL_PREVIEW_HOST
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
#endif
        @try {
            [[PortalController shared] bootstrapWithHookInstaller:installHooks];
        } @catch (NSException *exception) {
            PortalLogError("bootstrap raised %{public}@; HCG Portal stays inactive", exception.reason);
        }
    }
}

void PortalControllerNoteHooks(NSString *summary) {
    [[PortalController shared] noteHooks:summary];
}

void PortalControllerCoverSheetWillAppear(id coverSheet) {
    [[PortalController shared] coverSheetWillAppear:coverSheet];
}

void PortalControllerCoverSheetDidDisappear(id coverSheet) {
    [[PortalController shared] coverSheetDidDisappear:coverSheet];
}

void PortalControllerCoverSheetDidLayout(id coverSheet) {
    [[PortalController shared] coverSheetDidLayout:coverSheet];
}

#ifdef PORTAL_PREVIEW_HOST
NSDictionary *PortalControllerPreviewStatus(void) {
    return [[PortalController shared] statusDictionary];
}

id PortalControllerPreviewOverlay(void) {
    return [[PortalController shared] previewOverlay];
}

void PortalControllerPreviewReload(void) {
    [[PortalController shared] preferencesChanged];
}

void PortalControllerPreviewSetSystemInputs(int reduceMotion, int lowPower) {
    [[PortalController shared] previewSetReduceMotion:reduceMotion lowPower:lowPower];
}

void PortalControllerPreviewRelayout(void) {
    [[PortalController shared] update];
}

void PortalControllerPreviewInjectFault(void) {
    [[PortalController shared] fault:@"preview-injected exception"];
}

BOOL PortalControllerPreviewMeasureTimerRunning(void) {
    return [[PortalController shared] previewMeasureTimerRunning];
}

void PortalControllerPreviewSetProtectedData(int available) {
    [[PortalController shared] previewSetProtectedData:available];
}
#endif
