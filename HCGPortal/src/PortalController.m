//
//  PortalController.m
//  HCG Portal — Hakmi Capital Group
//
//  See PortalController.h. Decisions are made by the pure C core
//  (PortalCore.c): visibility, render plan, layout, menu geometry and the
//  pending protected action. This file gathers the inputs and applies the
//  results.
//
//  Privacy and authentication:
//    - Nothing private is read: no notification content, no credentials, no
//      passcode, no biometric data. Obstacles are measured by frame only.
//    - Every destination that opens something requests the normal iOS
//      authentication first (PortalAuth). Only the selected action of that
//      same request runs, once, after SpringBoard reports success. Failure,
//      cancellation, a refused request, screen-off, disabling, a fault or a
//      90 s timeout discard it.
//    - No device command is ever executed. Devices shows "Not connected".
//

#import "PortalController.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <notify.h>

#import "PortalAuth.h"
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
@end

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
    BOOL _lockScreenSession;
    BOOL _authenticationVisible;
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

    PortalAuthBroker *_auth;
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
        _previewReduceMotion = _previewLowPower = -1;
        portal_pending_init(&_pending);
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
    if (!_auth) _auth = [[PortalAuthBroker alloc] init];
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
    _authenticationVisible = NO;
    _active = NO;
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
    _screenOn = PortalReadNotifyState(_blankToken, &state) ? state == 0 : YES; // unreadable: assume lit
    state = 0;
    _locked = PortalReadNotifyState(_lockToken, &state) ? state != 0 : NO;
    if (_locked) _lockScreenSession = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
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
                // The phone went dark while authentication was up: never act later.
                portal_pending_cancel(&_pending);
                _authenticationVisible = NO;
                [self count:@"actionsDiscarded"];
                _lastAction = @"Screen turned off: the pending action was discarded";
            }
        }
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"screen state: %@", exception.reason]];
    }
}

- (void)lockStateChanged {
    @try {
        uint64_t state = 0;
        BOOL wasLocked = _locked;
        _locked = PortalReadNotifyState(_lockToken, &state) ? state != 0 : NO;
        if (_locked) _lockScreenSession = YES;
        if (wasLocked && !_locked) {
            // A successful unlock (Face ID, Touch ID or passcode). The flourish is
            // decoration inside the Cover Sheet: it never delays the dismissal.
            if (_visibility == PORTAL_VIS_VISIBLE && _plan.unlockAnimation) {
                [_overlay collapseAnimated:NO];
                [_overlay.portalView playUnlockFlourish];
                [self count:@"unlockFlourishes"];
                [PortalCompanions postLightingEvent:@"unlock" palette:_settings.appearance.palette
                                          intensity:_settings.appearance.intensity];
            }
        }
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"lock state: %@", exception.reason]];
    }
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

/// Attaches the single overlay to the Lock Screen's main page, once per host. Called only
/// while the Lock Screen is on screen as the Lock Screen (see -update). Returns the host,
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
        if (_locked) _lockScreenSession = YES;
        _attachRetries = 0;
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
        _lockScreenSession = _locked; // a new session starts at the next lock
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
        BOOL coverSheetVisible = [self coverSheetVisible];
        if (!coverSheetVisible && !_locked) _lockScreenSession = NO;

        // Attached only while the Lock Screen is on screen as the Lock Screen; detached otherwise.
        BOOL eligible = _launched && _screenOn && coverSheetVisible && _lockScreenSession;
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
        v.lockScreenSession = _lockScreenSession;
        v.authenticationVisible = _authenticationVisible;
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
            _authenticationVisible = NO;
            [self count:@"actionsDiscarded"];
            _lastAction = @"Authentication did not finish in time: the pending action was discarded";
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
    p.authAvailable = _auth.available;
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
        case PORTAL_AVAIL_AUTH_UNAVAILABLE: return @"Unlock first";
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
    if (_pending.awaiting) {
        [_overlay showMessage:@"Waiting for Face ID, Touch ID or your passcode…"];
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
    if (!portal_destination_requires_auth(item.destination)) return;

    unsigned generation = portal_pending_begin(&_pending, item.destination, item.item, CACurrentMediaTime());
    if (!generation) return;
    [self count:@"authRequests"];
    [self breadcrumb:@"requesting authentication"];
    _authenticationVisible = YES;
    _overlay.portalView.waiting = YES;
    [_overlay collapseAnimated:NO];
    [self update];
    [PortalCompanions postLightingEvent:@"authenticating" palette:_settings.appearance.palette intensity:_settings.appearance.intensity];
    NSString *name = [NSString stringWithFormat:@"HCG Portal: %s", portal_destination_id(item.destination)];
    __weak PortalController *weakSelf = self;
    [_auth requestAuthenticationNamed:name
                           completion:^(PortalAuthOutcome outcome) {
                               [weakSelf authenticationFinished:generation outcome:outcome];
                           }];
}

- (void)authenticationFinished:(unsigned)generation outcome:(PortalAuthOutcome)outcome {
    @try {
        BOOL success = outcome == PortalAuthOutcomeAuthenticated;
        BOOL current = _pending.awaiting && _pending.generation == generation;
        PortalPendingOutcome o = portal_pending_resolve(&_pending, generation, success, CACurrentMediaTime());
        if (current) {
            _authenticationVisible = NO;
            _overlay.portalView.waiting = NO;
        }
        if (!o.perform) {
            if (current) {
                [self count:success ? @"actionsDiscarded" : @"authCancelled"];
                _lastAction = outcome == PortalAuthOutcomeRefused     ? @"SpringBoard refused the authentication request: nothing was done"
                              : outcome == PortalAuthOutcomeUnavailable ? @"No authentication route: nothing was done"
                              : success                                  ? @"Authenticated too late: the action was discarded"
                                                                         : @"Authentication cancelled: the action was discarded";
                [self update];
                if (outcome == PortalAuthOutcomeRefused)
                    [_overlay showMessage:@"Couldn't ask for authentication. Unlock your iPhone, then try again."];
            }
            [self scheduleStatus];
            return;
        }
        [self count:@"authSucceeded"];
        [self perform:o];
        [self update];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"authentication result: %@", exception.reason]];
    }
}

- (void)perform:(PortalPendingOutcome)o {
    [self count:@"actionsPerformed"];
    [self breadcrumb:[NSString stringWithFormat:@"opening %s", portal_destination_id(o.destination)]];
    [PortalCompanions postLightingEvent:@"opened" palette:_settings.appearance.palette intensity:_settings.appearance.intensity];
    __weak PortalController *weakSelf = self;
    switch (o.destination) {
        case PORTAL_DEST_APP_ITEM: {
            if (o.item < 0 || o.item >= (int)_installedApps.count) {
                _lastAction = @"The chosen app disappeared before it could open";
                break;
            }
            NSString *bundle = _installedApps[o.item].bundleIdentifier;
            int index = o.item + 1;
            _lastAction = [NSString stringWithFormat:@"Opening app %d after authentication", index];
            [_launcher openApplication:bundle
                            completion:^(BOOL launched) {
                                [weakSelf noteAction:[NSString stringWithFormat:@"App %d %@ after authentication", index,
                                                                                launched ? @"opened" : @"could not be opened"]];
                            }];
            break;
        }
        case PORTAL_DEST_BACKGROUNDS: {
            _lastAction = @"Opening Settings (HCG Animation Center) after authentication";
            [_launcher openApplication:PortalSettingsBundleIdentifier
                            completion:^(BOOL launched) {
                                [weakSelf noteAction:launched ? @"Settings opened for HCG Animation Center after authentication"
                                                              : @"Settings could not be opened"];
                            }];
            break;
        }
        case PORTAL_DEST_NEXUS: {
            _lastAction = @"Opening HCG Nexus after authentication";
            [PortalCompanions openNexusPanelWithCompletion:^(BOOL opened, NSString *reason) {
                [weakSelf noteAction:opened ? @"HCG Nexus opened after authentication"
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
    NSString *scene = live ? [NSString stringWithFormat:@"screen %@, %@, Cover Sheet %@, Lock Screen session %@",
                                                        _screenOn ? @"on" : @"off", _locked ? @"locked" : @"unlocked",
                                                        [self coverSheetVisibleSafe] ? @"visible" : @"hidden",
                                                        _lockScreenSession ? @"yes" : @"no"]
                           : @"not observed (Portal inactive)";
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
        PortalStatusKeyAuthRoute : _auth.route ?: @"not checked",
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
#endif
