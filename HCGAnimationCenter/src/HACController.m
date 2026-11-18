//
//  HACController.m
//  HCG Animation Center — Hakmi Capital Group
//
//  Lifecycle (all on the main thread):
//
//    %ctor ─ bootstrap: kill switch? interfaces? launch guard?
//            register for preference, status and probe requests
//    SpringBoard finished launching ─ apply()
//    apply(): enabled → activate: start observers, install the front-display
//                       hook once, attach each assigned surface's view
//             disabled → deactivate: remove every view (players freed),
//                       stop every observer. The system wallpaper was never
//                       touched, so it is simply visible again.
//
//  Each surface (Home Screen, Lock Screen) owns one HCGBackgroundView. What it
//  shows comes from hac_decide() (HACPolicy.c) on every input change:
//    system  → view hidden, no decoder        still  → still image, no decoder
//    paused  → current frame, rate 0; the decoder is released after
//              HAC_RELEASE_HIDDEN_AFTER_SECONDS hidden
//    playing → video plays
//  The Lock Screen view is hidden outright while unlocked, so a wallpaper view
//  shared with the Home Screen never shows it there.
//
//  Failure policy: an exception removes every view and reports "fault"; a
//  media failure falls back to that surface's still (or the system
//  wallpaper). SpringBoard's own views are never modified, only added to.
//

#import "HACController.h"
#import "HACHosts.h"
#import "HACLog.h"
#import "HACPreferences.h"
#import "HACProbe.h"
#import "HACSpringBoard.h"
#import "HCGBackgroundView.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>

// SpringBoard's display and lock notifications. Preview builds use their own
// names so they never read the Simulator's real SpringBoard state.
#ifndef HAC_BLANKED_NOTIFICATION
#define HAC_BLANKED_NOTIFICATION "com.apple.springboard.hasBlankedScreen"
#endif
#ifndef HAC_LOCKSTATE_NOTIFICATION
#define HAC_LOCKSTATE_NOTIFICATION "com.apple.springboard.lockstate"
#endif

static const NSInteger kAttachAttempts = 15;
static const NSTimeInterval kAttachInterval = 2.0;

#pragma mark - Surface view

@class HACSurfaceSlot;

@interface HACController : NSObject
+ (instancetype)shared;
- (void)surfaceLostHost:(HACSurfaceSlot *)slot;
- (void)surfaceMediaFailed:(HACSurfaceSlot *)slot;
@end

/// The background view, tagged so the hierarchy probe can point it out, and
/// reporting when SpringBoard removes its host.
@interface HACSurfaceView : HCGBackgroundView
@property (nonatomic, weak) HACSurfaceSlot *owner;
@end

#pragma mark - Surface

@interface HACSurfaceSlot : NSObject <HCGBackgroundViewDelegate>
@property (nonatomic, readonly) HACSurface surface;
@property (nonatomic, strong, nullable) HACSurfaceView *view;
@property (nonatomic, strong, nullable) HACHost *host;
@property (nonatomic, copy) NSString *hostProblem;
@property (nonatomic, copy) NSString *rendering;
@property (nonatomic, copy) NSString *placementRequested;
@property (nonatomic, copy, nullable) NSString *presetID;
@property (nonatomic) BOOL mediaFailed;
@property (nonatomic, copy) NSString *failure;
@property (nonatomic) BOOL released;
@property (nonatomic) NSUInteger attachGeneration;
@property (nonatomic) NSInteger attachAttempts;
@property (nonatomic) NSUInteger hideGeneration;
@property (nonatomic) BOOL hideTimerRunning;
- (instancetype)initWithSurface:(HACSurface)surface;
@end

@implementation HACSurfaceView

- (void)didMoveToWindow {
    [super didMoveToWindow];
    HACSurfaceSlot *slot = self.owner;
    if (slot && self.superview && !self.window) [[HACController shared] surfaceLostHost:slot];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.owner && !self.superview) [[HACController shared] surfaceLostHost:self.owner];
}

@end

@implementation HACSurfaceSlot

- (instancetype)initWithSurface:(HACSurface)surface {
    if ((self = [super init])) {
        _surface = surface;
        _hostProblem = @"";
        _rendering = @"Not drawing";
        _placementRequested = @"automatic";
        _failure = @"";
    }
    return self;
}

- (void)backgroundView:(HCGBackgroundView *)view didFailWithError:(NSError *)error {
    if (view != _view) return;
    _mediaFailed = YES;
    _failure = error.localizedDescription ?: @"The video can't be played.";
    HACLogError("%{public}s: media failed: %{public}@", hac_surface_id(_surface), _failure);
    [[HACController shared] surfaceMediaFailed:self];
}

- (void)backgroundViewDidBecomeReady:(HCGBackgroundView *)view {
    HACLogDebug("%{public}s: first frame on screen", hac_surface_id(_surface));
}

@end

#pragma mark - Controller

@implementation HACController {
    HACHookInstaller _hookInstaller;
    HACSettings *_settings;
    NSString *_state;
    NSString *_detail;
    BOOL _blocked;
    BOOL _faulted;
    BOOL _launched;
    BOOL _active;

    HACSurfaceSlot *_slots[HAC_SURFACE_COUNT];

    BOOL _screenOn;
    BOOL _locked;
    BOOL _appInFront;
    BOOL _frontHookActive;
    BOOL _hookAttempted;
    NSString *_frontDetection;
    int _blankToken;
    int _lockToken;
    NSMutableArray<id> *_observerTokens;
    NSString *_probePath;
    NSDictionary<NSString *, NSString *> *_environment;
}

+ (instancetype)shared {
    static HACController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [[HACController alloc] init];
    });
    return controller;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = HACEngineStateDisabled;
        _detail = @"";
        _screenOn = YES;
        _locked = NO;
        _frontDetection = @"not started";
        _blankToken = NOTIFY_TOKEN_INVALID;
        _lockToken = NOTIFY_TOKEN_INVALID;
        _observerTokens = [NSMutableArray array];
        _probePath = @"";
        for (int s = 0; s < HAC_SURFACE_COUNT; s++) _slots[s] = [[HACSurfaceSlot alloc] initWithSurface:(HACSurface)s];
    }
    return self;
}

#pragma mark Darwin notifications (always registered)

static void HACPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                  CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HACController shared] preferencesChanged];
    });
}

static void HACStatusRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HACController shared] writeStatus];
        notify_post(HACStatusUpdatedNotification.UTF8String);
    });
}

static void HACProbeRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                              CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HACController shared] writeProbe];
        notify_post(HACStatusUpdatedNotification.UTF8String);
    });
}

#pragma mark Bootstrap

- (void)bootstrapWithHookInstaller:(HACHookInstaller)installer {
    _hookInstaller = installer;
    _environment = HACEnvironmentReport();
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, NULL, HACStatusRequested, (__bridge CFStringRef)HACStatusRequestNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, NULL, HACProbeRequested, (__bridge CFStringRef)HACProbeRequestNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    if ([[NSFileManager defaultManager] fileExistsAtPath:HACKillSwitchPath]) {
        [self block:HACEngineStateKillSwitch
             detail:[NSString stringWithFormat:@"%@ exists: HCG Animation Center does nothing. Delete it and respring "
                                               @"to undo.",
                                               HACKillSwitchPath]];
        return;
    }

    _settings = [HACPreferences loadSettings];
    HACDiagnosticLoggingEnabled = _settings.diagnosticLogging;

    if (!objc_getClass(HAC_SB_SPRINGBOARD_CLASS)) {
        [self block:HACEngineStateIncompatible detail:@"SpringBoard class missing. Nothing is drawn."];
        return;
    }

    if (_settings.enabled) {
        NSInteger unstable = [HACPreferences consecutiveUnstableLaunches];
        if (unstable >= HAC_MAX_UNSTABLE_LAUNCHES) {
            [self block:HACEngineStateAutoDisabled
                 detail:[NSString stringWithFormat:@"%ld SpringBoard launches in a row ended within %.0f s while HCG "
                                                   @"Animation Center was enabled. Nothing is drawn and the system "
                                                   @"wallpaper shows. Turn Enable off and on, then respring, to try "
                                                   @"again.",
                                                   (long)unstable, HAC_STABLE_AFTER_SECONDS]];
            return;
        }
        [HACPreferences setConsecutiveUnstableLaunches:unstable + 1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(HAC_STABLE_AFTER_SECONDS * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [HACPreferences setConsecutiveUnstableLaunches:0];
                           HACLogDebug("launch marked stable");
                       });
    }

    CFNotificationCenterAddObserver(darwin, NULL, HACPreferencesChanged,
                                    (__bridge CFStringRef)HACPreferencesChangedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    __weak HACController *weakSelf = self;
    __block id launchToken =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
                                                          [[NSNotificationCenter defaultCenter] removeObserver:launchToken];
                                                          launchToken = nil;
                                                          [weakSelf springBoardLaunched];
                                                      }];
    // If the notification was missed (late injection), carry on anyway.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf springBoardLaunched];
    });
    [self setState:_settings.enabled ? HACEngineStateWaiting : HACEngineStateDisabled
            detail:_settings.enabled ? @"Waiting for SpringBoard to finish launching." : @""];
    [self writeStatus];
}

- (void)block:(NSString *)state detail:(NSString *)detail {
    _blocked = YES;
    [self setState:state detail:detail];
    [self writeStatus];
}

- (void)springBoardLaunched {
    if (_launched) return;
    _launched = YES;
    [self apply];
}

#pragma mark Reconciliation

- (void)preferencesChanged {
    if (_blocked) return;
    @try {
        _settings = [HACPreferences loadSettings];
        HACDiagnosticLoggingEnabled = _settings.diagnosticLogging;
        if (!_settings.enabled) _faulted = NO; // Enable off clears a fault; on again retries
        HACLogDebug("preferences %{public}@", _settings.description);
        [self apply];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"reload: %@", exception.reason]];
    }
}

- (void)apply {
    if (_blocked || !_launched) return;
    @try {
        if (_settings.enabled && !_faulted) {
            [self activate];
        } else {
            [self deactivate];
            if (!_faulted) [self setState:HACEngineStateDisabled detail:@""];
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"apply: %@", exception.reason]];
        return;
    }
    [self writeStatus];
}

- (void)fault:(NSString *)reason {
    HACLogError("fault: %{public}@", reason);
    _faulted = YES;
    @try {
        [self deactivate];
    } @catch (NSException *exception) {
        HACLogError("deactivate after fault raised %{public}@", exception.reason);
    }
    [self setState:HACEngineStateFault
            detail:[NSString stringWithFormat:@"%@ — every background was removed and the system wallpaper shows. "
                                              @"Turn Enable off and on to retry.",
                                              reason]];
    [self writeStatus];
}

- (void)setState:(NSString *)state detail:(NSString *)detail {
    _state = state;
    _detail = detail ?: @"";
    HACLogInfo("state %{public}@: %{public}@", state, _detail);
}

#pragma mark Activation

- (void)activate {
    if (!_active) {
        _active = YES;
        [self startSystemObservers];
    }
    [self installFrontDisplayHookOnce];
    for (int s = 0; s < HAC_SURFACE_COUNT; s++) [self configureSlot:_slots[s]];
    [self updateAll];
    [self setState:HACEngineStateActive detail:[self activeDetail]];
}

- (void)deactivate {
    for (int s = 0; s < HAC_SURFACE_COUNT; s++) [self detachSlot:_slots[s]];
    if (_active) {
        [self stopSystemObservers];
        _active = NO;
    }
}

- (NSString *)activeDetail {
    NSMutableArray *notes = [NSMutableArray array];
    [notes addObject:[NSString stringWithFormat:@"App detection: %@.", _frontDetection]];
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion < 15 || v.majorVersion > 17)
        [notes addObject:[NSString stringWithFormat:@"iOS %ld is outside the iOS 15–17 interfaces this beta was written "
                                                    @"against; untested.",
                                                    (long)v.majorVersion]];
    return [notes componentsJoinedByString:@" "];
}

- (void)installFrontDisplayHookOnce {
    if (_hookAttempted) return;
    _hookAttempted = YES;
    Class springBoard = objc_getClass(HAC_SB_SPRINGBOARD_CLASS);
    SEL selector = @selector(frontDisplayDidChange:);
    Method method = springBoard ? class_getInstanceMethod(springBoard, selector) : NULL;
    if (!method || !_hookInstaller) {
        _frontDetection = @"unavailable: -[SpringBoard frontDisplayDidChange:] missing; the Home Screen background "
                          @"pauses only when the screen is off or locked";
        return;
    }
    IMP before = method_getImplementation(method);
    _hookInstaller();
    IMP after = method_getImplementation(class_getInstanceMethod(springBoard, selector));
    _frontHookActive = before != after;
    _frontDetection = _frontHookActive ? @"active (frontDisplayDidChange: hook)"
                                       : @"unavailable: the hook did not install; the Home Screen background pauses "
                                         @"only when the screen is off or locked";
}

#pragma mark Surfaces

- (void)configureSlot:(HACSurfaceSlot *)slot {
    HACSurface surface = slot.surface;
    HCGBackgroundPreset *preset = [_settings presetForSurface:surface];
    if (![_settings surfaceEnabled:surface] || !preset) {
        [self detachSlot:slot];
        NSString *problem = surface == HACSurfaceLock ? _settings.lockPresetProblem : _settings.homePresetProblem;
        slot.rendering = ![_settings surfaceEnabled:surface] ? @"Off for this surface"
                         : problem.length                     ? [NSString stringWithFormat:@"Not drawing: %@", problem]
                                                              : @"No background assigned";
        return;
    }
    if (![slot.presetID isEqualToString:preset.identifier] || !slot.view) {
        slot.mediaFailed = NO; // a new background gets a fresh chance
        slot.failure = @"";
    }
    slot.presetID = preset.identifier;
    if (!slot.view) {
        HACSurfaceView *view = [[HACSurfaceView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        view.owner = slot;
        view.delegate = slot;
        view.accessibilityIdentifier =
            [NSString stringWithFormat:@"HCGAnimationCenter.%s", hac_surface_id(surface)];
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        slot.view = view;
    }
    [slot.view setPreset:preset folder:[HACPreferences mediaFolder]];
    NSString *placement = [_settings placementForSurface:surface];
    BOOL placementChanged = ![placement isEqualToString:slot.placementRequested];
    slot.placementRequested = placement;
    if (placementChanged && slot.view.superview) {
        HACLogInfo("%{public}s: placement %{public}@: re-attaching", hac_surface_id(surface), placement);
        [self removeViewOfSlot:slot];
    }
    if (!slot.view.superview) [self attachWithRetry:slot];
}

- (void)removeViewOfSlot:(HACSurfaceSlot *)slot {
    slot.attachGeneration++; // cancels pending retries
    HACSurfaceView *view = slot.view;
    view.owner = nil; // our own removal is not a lost host
    view.display = HCGBackgroundDisplayNone;
    [view releasePlayer];
    [view removeFromSuperview];
    view.owner = slot;
    slot.host = nil;
}

- (void)detachSlot:(HACSurfaceSlot *)slot {
    if (slot.view) {
        [self removeViewOfSlot:slot];
        slot.view.owner = nil;
        slot.view.delegate = nil;
        [slot.view setPreset:nil folder:nil];
        slot.view = nil;
    }
    slot.hideGeneration++;
    slot.hideTimerRunning = NO;
    slot.released = NO;
    slot.presetID = nil;
    slot.hostProblem = @"";
    slot.rendering = @"Not drawing";
}

- (void)attachWithRetry:(HACSurfaceSlot *)slot {
    NSUInteger generation = ++slot.attachGeneration;
    slot.attachAttempts = 0;
    [self tryAttach:slot generation:generation];
}

- (void)tryAttach:(HACSurfaceSlot *)slot generation:(NSUInteger)generation {
    if (generation != slot.attachGeneration || !_active || !slot.view) return;
    NSString *why = nil;
    HACHost *host = nil;
    @try {
        host = HACFindHost(slot.surface, slot.placementRequested, &why);
        if (host.container) {
            UIView *container = host.container;
            HACSurfaceView *view = slot.view;
            view.frame = container.bounds;
            view.display = HCGBackgroundDisplayNone; // updateAll decides
            if (host.atBottom) {
                [container insertSubview:view atIndex:0];
            } else {
                [container addSubview:view];
            }
            slot.host = host;
            slot.hostProblem = @"";
            HACLogInfo("%{public}s attached: %{public}@", hac_surface_id(slot.surface), host.summary);
            [self updateAll];
            [self writeStatus];
            return;
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"attach %s: %@", hac_surface_id(slot.surface), exception.reason]];
        return;
    }
    slot.hostProblem = why ?: @"no host";
    if (++slot.attachAttempts >= kAttachAttempts) {
        slot.rendering = [NSString stringWithFormat:@"Not drawing: no place found after %.0f s (%@)",
                                                    kAttachAttempts * kAttachInterval, slot.hostProblem];
        HACLogError("%{public}s: %{public}@", hac_surface_id(slot.surface), slot.rendering);
        [self writeStatus];
        return;
    }
    __weak HACController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAttachInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf tryAttach:slot generation:generation];
    });
}

- (void)surfaceLostHost:(HACSurfaceSlot *)slot {
    if (!_active || !slot.view || slot.view.owner != slot) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_active || !slot.view || slot.view.window) return;
        HACLogInfo("%{public}s lost its host; re-attaching", hac_surface_id(slot.surface));
        [self removeViewOfSlot:slot];
        [self attachWithRetry:slot];
    });
}

- (void)surfaceMediaFailed:(HACSurfaceSlot *)slot {
    [self updateAll];
    [self writeStatus];
}

#pragma mark Visibility

- (HACSurfaceInputs)inputsForSlot:(HACSurfaceSlot *)slot {
    HACSurface surface = slot.surface;
    HACSurfaceInputs in = {
        .enabled = _settings.enabled && !_faulted && !_blocked && _active,
        .surfaceEnabled = [_settings surfaceEnabled:surface],
        .assigned = [_settings presetForSurface:surface] != nil,
        .mediaPlayable = !slot.mediaFailed,
        .stillAvailable = slot.view.stillLoaded || [_settings presetForSurface:surface].stillFile != nil,
        .attached = slot.view.superview != nil,
        .screenOn = _screenOn,
        .locked = _locked,
        .appInFront = _appInFront,
        .reduceMotion = UIAccessibilityIsReduceMotionEnabled(),
        .lowPower = [NSProcessInfo processInfo].lowPowerModeEnabled,
        .thermalState = (int)[NSProcessInfo processInfo].thermalState,
        .reduceMotionPolicy = _settings.reduceMotionPolicy,
        .lowPowerPolicy = _settings.lowPowerPolicy,
    };
    return in;
}

- (void)updateAll {
    if (!_active) return;
    @try {
        for (int s = 0; s < HAC_SURFACE_COUNT; s++) [self updateSlot:_slots[s]];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"update: %@", exception.reason]];
    }
}

- (void)updateSlot:(HACSurfaceSlot *)slot {
    HACSurfaceView *view = slot.view;
    if (!view) return;
    HACSurfaceInputs inputs = [self inputsForSlot:slot];
    HACDecision d = hac_decide(slot.surface, &inputs);
    HCGBackgroundDisplay display = HCGBackgroundDisplayNone;
    switch (d.show) {
        case HACShowSystem:
            display = HCGBackgroundDisplayNone;
            break;
        case HACShowStill:
            display = HCGBackgroundDisplayStill;
            break;
        case HACShowPaused:
            if (slot.surface == HACSurfaceLock && inputs.screenOn && !inputs.locked) {
                display = HCGBackgroundDisplayNone; // unlocked: never let the Lock view show elsewhere
            } else {
                display = slot.released ? HCGBackgroundDisplayStill : HCGBackgroundDisplayPaused;
                if (!slot.released) [self scheduleReleaseForSlot:slot];
            }
            break;
        case HACShowPlaying:
            display = HCGBackgroundDisplayPlaying;
            break;
    }
    if (d.show != HACShowPaused) {
        slot.released = NO;
        slot.hideGeneration++;
        slot.hideTimerRunning = NO;
    }
    if (display != HCGBackgroundDisplayNone) [self restoreOrderOfSlot:slot];
    view.display = display;

    NSString *name = [_settings presetForSurface:slot.surface].name ?: @"";
    switch (d.show) {
        case HACShowSystem:
            slot.rendering = [NSString stringWithFormat:@"System wallpaper: %s", d.reason];
            break;
        case HACShowStill:
            slot.rendering = [NSString stringWithFormat:@"Still (%s): %@", d.reason, name];
            break;
        case HACShowPaused:
            slot.rendering = [NSString stringWithFormat:@"Paused (%s)%@: %@", d.reason,
                                                        slot.released ? @", decoder released" : @"", name];
            break;
        case HACShowPlaying:
            slot.rendering = [NSString stringWithFormat:@"%@: %@", view.stateDescription, name];
            break;
    }
    if (slot.mediaFailed) slot.rendering = [slot.rendering stringByAppendingFormat:@" — %@", slot.failure];
    HACLogDebug("%{public}s: %{public}@", hac_surface_id(slot.surface), slot.rendering);
}

/// Our view goes back to its documented position (index 0, or on top of the
/// wallpaper view) if something reordered the host.
- (void)restoreOrderOfSlot:(HACSurfaceSlot *)slot {
    UIView *view = slot.view, *container = view.superview;
    if (!container) return;
    if (slot.host.atBottom) {
        if (container.subviews.firstObject != view) [container sendSubviewToBack:view];
    } else if (container.subviews.lastObject != view) {
        [container bringSubviewToFront:view];
    }
}

- (void)scheduleReleaseForSlot:(HACSurfaceSlot *)slot {
    if (slot.hideTimerRunning) return;
    slot.hideTimerRunning = YES;
    NSUInteger generation = ++slot.hideGeneration;
    __weak HACController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(HAC_RELEASE_HIDDEN_AFTER_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (generation != slot.hideGeneration) return;
                       slot.hideTimerRunning = NO;
                       slot.released = YES;
                       [slot.view releasePlayer];
                       HACLogDebug("%{public}s hidden for %.0f s: decoder released", hac_surface_id(slot.surface),
                                   HAC_RELEASE_HIDDEN_AFTER_SECONDS);
                       [weakSelf updateAll];
                   });
}

- (void)frontDisplayDidChange:(id)display {
    if (!_active) return;
    @try {
        // Fail open: only an application counts as covering the Home Screen.
        Class applicationClass = objc_getClass(HAC_SB_APPLICATION_CLASS);
        _appInFront = display && applicationClass && [display isKindOfClass:applicationClass];
        [self updateAll];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"front display: %@", exception.reason]];
    }
}

#pragma mark System observers

static BOOL HACReadNotifyState(int token, uint64_t *state) {
    if (token == NOTIFY_TOKEN_INVALID) return NO;
    return notify_get_state(token, state) == NOTIFY_STATUS_OK;
}

- (void)startSystemObservers {
    __weak HACController *weakSelf = self;
    dispatch_queue_t main = dispatch_get_main_queue();

    // Screen blanked (1) / lit (0). If unreadable, assume lit (fail open).
    if (notify_register_dispatch(HAC_BLANKED_NOTIFICATION, &_blankToken, main, ^(int token) {
            uint64_t state = 0;
            HACController *strong = weakSelf;
            if (!strong) return;
            strong->_screenOn = HACReadNotifyState(token, &state) ? state == 0 : YES;
            [strong updateAll];
        }) != NOTIFY_STATUS_OK) {
        _blankToken = NOTIFY_TOKEN_INVALID;
    }
    uint64_t state = 0;
    _screenOn = HACReadNotifyState(_blankToken, &state) ? state == 0 : YES;

    // Locked (non-zero) / unlocked (0). If unreadable, assume unlocked.
    if (notify_register_dispatch(HAC_LOCKSTATE_NOTIFICATION, &_lockToken, main, ^(int token) {
            uint64_t value = 0;
            HACController *strong = weakSelf;
            if (!strong) return;
            strong->_locked = HACReadNotifyState(token, &value) ? value != 0 : NO;
            [strong updateAll];
        }) != NOTIFY_STATUS_OK) {
        _lockToken = NOTIFY_TOKEN_INVALID;
    }
    state = 0;
    _locked = HACReadNotifyState(_lockToken, &state) ? state != 0 : NO;

    _appInFront = NO;
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_accessibilityFrontMostApplication)])
        _appInFront = [(SpringBoard *)app _accessibilityFrontMostApplication] != nil;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^refresh)(NSNotification *) = ^(NSNotification *note) {
        [weakSelf updateAll];
    };
    for (NSNotificationName name in @[
             UIAccessibilityReduceMotionStatusDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification,
             NSProcessInfoThermalStateDidChangeNotification
         ]) {
        [_observerTokens addObject:[center addObserverForName:name
                                                       object:nil
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:refresh]];
    }
    [_observerTokens addObject:[center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:^(NSNotification *note) {
                                                   [weakSelf memoryWarning];
                                               }]];
}

- (void)stopSystemObservers {
    if (_blankToken != NOTIFY_TOKEN_INVALID) notify_cancel(_blankToken);
    if (_lockToken != NOTIFY_TOKEN_INVALID) notify_cancel(_lockToken);
    _blankToken = _lockToken = NOTIFY_TOKEN_INVALID;
    for (id token in _observerTokens) [[NSNotificationCenter defaultCenter] removeObserver:token];
    [_observerTokens removeAllObjects];
}

/// Frees every decoder that is not on screen right now.
- (void)memoryWarning {
    for (int s = 0; s < HAC_SURFACE_COUNT; s++) {
        HACSurfaceSlot *slot = _slots[s];
        if (slot.view && slot.view.display != HCGBackgroundDisplayPlaying) {
            slot.released = YES;
            [slot.view releasePlayer];
        }
    }
    HACLogInfo("memory warning: hidden decoders released");
    [self updateAll];
}

#pragma mark Status

- (NSDictionary *)statusForSlot:(HACSurfaceSlot *)slot {
    return @{
        HACSurfaceStatusKeyRendering : slot.rendering ?: @"",
        HACSurfaceStatusKeyHost : slot.host.summary ?: (slot.hostProblem.length ? slot.hostProblem : @""),
        HACSurfaceStatusKeyPlacement : slot.placementRequested ?: @"automatic",
        HACSurfaceStatusKeyPreset : [_settings presetForSurface:slot.surface].name ?: @"",
    };
}

- (NSDictionary *)statusDictionary {
    return @{
        HACStatusKeyState : _state ?: @"",
        HACStatusKeyDetail : _detail ?: @"",
        HACStatusKeyHome : [self statusForSlot:_slots[HACSurfaceHome]],
        HACStatusKeyLock : [self statusForSlot:_slots[HACSurfaceLock]],
        HACStatusKeyEnvironment : HACEnvironmentSummary(_environment ?: HACEnvironmentReport()),
        HACStatusKeyFrontDetection : _frontDetection ?: @"",
        HACStatusKeyProbePath : _probePath ?: @"",
        HACStatusKeyTweakVersion : @HAC_VERSION,
        HACStatusKeyBuildID : @HAC_BUILD_ID,
        HACStatusKeySystemVersion : [NSProcessInfo processInfo].operatingSystemVersionString ?: @"",
        HACStatusKeyTimestamp : [NSDate date],
    };
}

- (void)writeStatus {
    @try {
        [self updateAll];
        [HACPreferences writeStatus:[self statusDictionary]];
    } @catch (NSException *exception) {
        HACLogError("could not write status: %{public}@", exception.reason);
    }
}

- (void)writeProbe {
    @try {
        NSError *error = nil;
        NSString *path = HACWriteHierarchyProbe([self statusDictionary], &error);
        _probePath = path ?: [NSString stringWithFormat:@"failed: %@", error.localizedDescription ?: @"unknown"];
        HACLogInfo("hierarchy probe: %{public}@", _probePath);
    } @catch (NSException *exception) {
        _probePath = [NSString stringWithFormat:@"failed: %@", exception.reason];
    }
    [self writeStatus];
}

#ifdef HAC_PREVIEW_HOST
- (HCGBackgroundView *)previewViewForSurface:(int)surface {
    return surface >= 0 && surface < HAC_SURFACE_COUNT ? _slots[surface].view : nil;
}
#endif

@end

#pragma mark - C entry points

void HACControllerBootstrap(HACHookInstaller installFrontDisplayHook) {
    @autoreleasepool {
#ifndef HAC_PREVIEW_HOST
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
#endif
        @try {
            [[HACController shared] bootstrapWithHookInstaller:installFrontDisplayHook];
        } @catch (NSException *exception) {
            HACLogError("bootstrap raised %{public}@; HCG Animation Center stays inactive", exception.reason);
        }
    }
}

void HACControllerFrontDisplayDidChange(id display) {
    [[HACController shared] frontDisplayDidChange:display];
}

#ifdef HAC_PREVIEW_HOST
NSDictionary *HACControllerPreviewStatus(void) {
    return [[HACController shared] statusDictionary];
}

id HACControllerPreviewSurfaceView(int surface) {
    return [[HACController shared] previewViewForSurface:surface];
}
#endif
