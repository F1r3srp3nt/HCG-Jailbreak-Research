//
//  HaloController.m
//  HCG Halo — Hakmi Capital Group
//
//  Lifecycle (all on the main thread):
//
//    %ctor ─ bootstrap: kill switch? interfaces present? launch guard?
//            register for preference changes and status requests
//    SpringBoard finished launching ─ apply()
//    apply(): enabled → activate (attach overlay to the Home Screen window,
//             start system observers, install the front-display hook once)
//             disabled → deactivate (remove overlay, stop every observer)
//
//  Visibility ("Show Halo on", 0.3.0~beta1; HaloConfig.c, halo_surface_block):
//    Home Screen Only (default) — the 0.2.0 rules, in the Home Screen window:
//      screen on, unlocked, no app in front, Home Screen window visible.
//    Selected App Only — screen on, unlocked, the chosen app in front.
//    Always / Always Except When Screen Is Off — screen on (lit Lock Screen,
//      Home Screen and apps).
//    Always Except Lock Screen — screen on and unlocked.
//  Every policy but Home Screen Only draws in HCG Halo's own non-interactive
//  overlay window (HaloEdgeWindow), above apps and the Lock Screen. Whenever
//  the border is hidden the overlay is hidden AND its layer clock is frozen
//  (and the overlay window is hidden), so it costs nothing; a dark display
//  always hides it. Reduce Motion and Low Power Mode change the render plan
//  (halo_render_plan) under every policy. The policy never affects the HCG
//  Nexus panel border, which follows the panel's own visibility.
//
//  Targets (0.2.0~beta1): the screen edge (default), the HCG Nexus panel, or
//  both. The panel border is owned by HaloNexusLink, which attaches to the
//  live Nexus panel through Nexus's versioned interface; it shares this
//  controller's enable switch, kill switch, launch guard, fault handling and
//  screen-off / Reduce Motion / Low Power inputs. Without a compatible Nexus
//  it stays off with a reason and the screen edge is unaffected.
//
//  Failure policy: anything unexpected removes the overlay and reports
//  "fault" in Settings; Home Screen behaviour is never touched.
//

#import "HaloController.h"
#import "HaloEdgeWindow.h"
#import "HaloLog.h"
#import "HaloNexusLink.h"
#import "HaloOverlayView.h"
#import "HaloPreferences.h"
#import "HaloScreen.h"
#import "HaloSpringBoard.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>

// SpringBoard's display and lock notifications. The Simulator preview
// (preview/HaloSurfacesPreview.m) builds this file with its own names so it
// never touches the Simulator's real SpringBoard state.
#ifndef HALO_BLANKED_NOTIFICATION
#define HALO_BLANKED_NOTIFICATION "com.apple.springboard.hasBlankedScreen"
#endif
#ifndef HALO_LOCKSTATE_NOTIFICATION
#define HALO_LOCKSTATE_NOTIFICATION "com.apple.springboard.lockstate"
#endif
static NSString *const kBlankedNotification = @HALO_BLANKED_NOTIFICATION;
static NSString *const kLockStateNotification = @HALO_LOCKSTATE_NOTIFICATION;

static const NSInteger kAttachAttempts = 15;
static const NSTimeInterval kAttachInterval = 2.0;

@interface HaloController : NSObject <HaloOverlayViewDelegate>
+ (instancetype)shared;
- (void)bootstrapWithHookInstaller:(HaloHookInstaller)installer;
- (void)frontDisplayDidChange:(id)display;
@end

@implementation HaloController {
    HaloHookInstaller _hookInstaller;
    HaloSettings *_settings;

    // Engine state shown in Settings.
    NSString *_state;
    NSString *_detail;
    BOOL _blocked;  // kill switch / incompatible / auto-disabled: never activate this launch
    BOOL _faulted;  // cleared by turning Enable off
    BOOL _launched;
    BOOL _active;

    // Overlay
    HaloOverlayView *_overlay;
    __weak UIWindow *_host;
    HaloEdgeWindow *_edgeWindow; // owned; only for the policies beyond the Home Screen
    BOOL _hostIsEdge;
    NSString *_hostDescription;
    NSUInteger _attachGeneration;
    NSInteger _attachAttempts;

    // Visibility inputs
    BOOL _screenOn;
    BOOL _unlocked;
    BOOL _homeInFront;
    NSString *_frontApp;   // bundle identifier of the app in front, "" if none
    BOOL _frontHookActive; // app changes are reported (frontDisplayDidChange: hook installed)
    HaloScreenFit _screenFit;
    double _lengthScale;
    int _blankToken;
    int _lockToken;
    NSMutableArray<id> *_observerTokens;
    BOOL _hookAttempted;
    NSString *_frontDetection;
    NSString *_rendering;

    // HCG Nexus panel border
    HaloNexusLink *_link;
}

+ (instancetype)shared {
    static HaloController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [[HaloController alloc] init];
    });
    return controller;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = HaloEngineStateDisabled;
        _detail = @"";
        _screenOn = YES;
        _unlocked = YES;
        _homeInFront = YES;
        _frontApp = @"";
        _lengthScale = 1;
        _blankToken = NOTIFY_TOKEN_INVALID;
        _lockToken = NOTIFY_TOKEN_INVALID;
        _observerTokens = [NSMutableArray array];
        _frontDetection = @"not started";
        _rendering = @"Not drawing";
        _hostDescription = @"";
        _link = [[HaloNexusLink alloc] init];
        Dl_info info;
        if (dladdr((const void *)&HaloControllerBootstrap, &info) && info.dli_fname)
            _link.fallbackDefinitionPath = [HaloNexusLink definitionPathFromImagePath:@(info.dli_fname)];
        __weak HaloController *weakSelf = self;
        _link.stateDidChange = ^(HaloNexusLink *link) {
            [weakSelf nexusLinkChanged];
        };
    }
    return self;
}

#pragma mark - Darwin notifications (always registered)

static void HaloPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HaloController shared] preferencesChanged];
    });
}

static void HaloStatusRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HaloController *controller = [HaloController shared];
        [controller writeStatus];
        notify_post(HaloStatusUpdatedNotification.UTF8String);
    });
}

#pragma mark - Bootstrap

- (void)bootstrapWithHookInstaller:(HaloHookInstaller)installer {
    _hookInstaller = installer;
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, NULL, HaloStatusRequested, (__bridge CFStringRef)HaloStatusRequestNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    if ([[NSFileManager defaultManager] fileExistsAtPath:HaloKillSwitchPath]) {
        [self block:HaloEngineStateKillSwitch
             detail:[NSString stringWithFormat:@"%@ exists: HCG Halo does nothing. Delete it and respring to undo.",
                                               HaloKillSwitchPath]];
        return;
    }

    _settings = [HaloPreferences loadSettings];
    HaloDiagnosticLoggingEnabled = _settings.diagnosticLogging;

    NSString *missing = [self missingInterfaces];
    if (missing) {
        [self block:HaloEngineStateIncompatible detail:missing];
        return;
    }

    if (_settings.enabled) {
        NSInteger unstable = [HaloPreferences consecutiveUnstableLaunches];
        if (unstable >= HALO_MAX_UNSTABLE_LAUNCHES) {
            [self block:HaloEngineStateAutoDisabled
                 detail:[NSString stringWithFormat:@"%ld SpringBoard launches in a row ended within %.0f s while HCG Halo "
                                                   @"was enabled. Nothing is drawn. Turn Enable off and on, then "
                                                   @"respring, to try again.",
                                                   (long)unstable, HALO_STABLE_AFTER_SECONDS]];
            return;
        }
        [HaloPreferences setConsecutiveUnstableLaunches:unstable + 1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(HALO_STABLE_AFTER_SECONDS * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [HaloPreferences setConsecutiveUnstableLaunches:0];
                           HaloLogDebug("launch marked stable");
                       });
    }

    CFNotificationCenterAddObserver(darwin, NULL, HaloPreferencesChanged,
                                    (__bridge CFStringRef)HaloPreferencesChangedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    __weak HaloController *weakSelf = self;
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
    [self setState:_settings.enabled ? HaloEngineStateWaiting : HaloEngineStateDisabled
            detail:_settings.enabled ? @"Waiting for SpringBoard to finish launching." : @""];
    [self writeStatus];
}

- (void)block:(NSString *)state detail:(NSString *)detail {
    _blocked = YES;
    [self setState:state detail:detail];
    [self writeStatus];
}

- (NSString *)missingInterfaces {
    BOOL window = objc_getClass(HALO_SB_HOME_WINDOW_CLASS) != Nil;
    Class iconController = objc_getClass(HALO_SB_ICON_CONTROLLER_CLASS);
    BOOL controller = iconController && [iconController respondsToSelector:@selector(sharedInstance)];
    if (!window && !controller)
        return @"Neither SBHomeScreenWindow nor +[SBIconController sharedInstance] exists on this iOS version, so HCG "
               @"Halo cannot find the Home Screen. Nothing is drawn.";
    if (!objc_getClass(HALO_SB_SPRINGBOARD_CLASS)) return @"SpringBoard class missing. Nothing is drawn.";
    return nil;
}

- (void)springBoardLaunched {
    if (_launched) return;
    _launched = YES;
    [self apply];
}

#pragma mark - Reconciliation

- (void)preferencesChanged {
    if (_blocked) return;
    @try {
        _settings = [HaloPreferences loadSettings];
        HaloDiagnosticLoggingEnabled = _settings.diagnosticLogging;
        if (!_settings.enabled) _faulted = NO; // Enable off clears a fault; on again retries
        HaloLogDebug("preferences %{public}@", _settings.description);
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
            if (!_faulted) [self setState:HaloEngineStateDisabled detail:@""];
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"apply: %@", exception.reason]];
        return;
    }
    [self writeStatus];
}

- (void)fault:(NSString *)reason {
    HaloLogError("fault: %{public}@", reason);
    _faulted = YES;
    @try {
        [self deactivate];
    } @catch (NSException *exception) {
        HaloLogError("deactivate after fault raised %{public}@", exception.reason);
    }
    [self setState:HaloEngineStateFault
            detail:[NSString stringWithFormat:@"%@ — the border was removed. Turn Enable off and on to retry.", reason]];
    [self writeStatus];
}

- (void)setState:(NSString *)state detail:(NSString *)detail {
    _state = state;
    _detail = detail ?: @"";
    HaloLogInfo("state %{public}@: %{public}@", state, _detail);
}

#pragma mark - Activation

- (void)activate {
    if (!_active) {
        _active = YES;
        [self startSystemObservers];
    }
    if (_settings.targetsScreen) {
        [self installFrontDisplayHookOnce]; // only the screen edge needs app-in-front detection
        BOOL wantEdge = halo_show_on_uses_overlay_window(_settings.showOn);
        if (_overlay.window && wantEdge != _hostIsEdge) {
            // "Show Halo on" moved between the Home Screen window and the overlay window: re-host at once.
            HaloLogInfo("show-on %{public}s: moving the border to the %{public}s", halo_show_on_id(_settings.showOn),
                        wantEdge ? "overlay window" : "Home Screen window");
            [self removeOverlay];
        }
        if (!_overlay.window) {
            [self attachWithRetry];
        } else {
            [self configureOverlay];
            [self updateVisibility];
            [self setState:HaloEngineStateActive detail:[self compatibilityNotes]];
        }
    } else {
        [self removeOverlay];
        [self setState:HaloEngineStateActive detail:@"Target: HCG Nexus panel only (the screen edge is off)."];
    }
    [self applyNexusLink];
}

- (void)removeOverlay {
    _attachGeneration++; // cancels pending attach retries
    if (_overlay) {
        _overlay.delegate = nil;
        [_overlay teardown];
        [_overlay removeFromSuperview];
        _overlay = nil;
    }
    if (_edgeWindow) {
        _edgeWindow.hidden = YES;
        _edgeWindow = nil; // released: UIKit drops the window
    }
    _host = nil;
    _hostIsEdge = NO;
    _rendering = @"Not drawing";
}

/// The panel border follows the same switches as the screen edge.
- (void)applyNexusLink {
    BOOL enabled = _active && _settings.enabled && !_faulted && !_blocked && _settings.targetsNexus;
    [_link applySettings:_settings
                   enabled:enabled
              reduceMotion:UIAccessibilityIsReduceMotionEnabled()
              lowPowerMode:[NSProcessInfo processInfo].lowPowerModeEnabled
        reduceTransparency:UIAccessibilityIsReduceTransparencyEnabled()
                  screenOn:_screenOn];
}

- (void)nexusLinkChanged {
    if (!_settings.targetsScreen && _active && !_faulted && !_blocked)
        [self setState:HaloEngineStateActive detail:@"Target: HCG Nexus panel only (the screen edge is off)."];
}

- (void)deactivate {
    [self removeOverlay];
    [_link stop];
    if (_active) {
        [self stopSystemObservers];
        _active = NO;
    }
}

- (void)installFrontDisplayHookOnce {
    if (_hookAttempted) return;
    _hookAttempted = YES;
    Class springBoard = objc_getClass(HALO_SB_SPRINGBOARD_CLASS);
    SEL selector = @selector(frontDisplayDidChange:);
    Method method = springBoard ? class_getInstanceMethod(springBoard, selector) : NULL;
    if (!method || !_hookInstaller) {
        _frontDetection = @"unavailable: -[SpringBoard frontDisplayDidChange:] missing; the border keeps running behind apps";
        return;
    }
    IMP before = method_getImplementation(method);
    _hookInstaller();
    IMP after = method_getImplementation(class_getInstanceMethod(springBoard, selector));
    _frontHookActive = before != after;
    _frontDetection = _frontHookActive ? @"active (frontDisplayDidChange: hook)"
                                       : @"unavailable: the hook did not install; the border keeps running behind apps";
}

#pragma mark Home Screen window

static NSArray<UIWindow *> *HaloAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        if (![windows containsObject:window]) [windows addObject:window];
    }
#pragma clang diagnostic pop
    return windows;
}

static UIWindow *HaloFindHomeScreenWindow(NSString **how) {
    Class windowClass = objc_getClass(HALO_SB_HOME_WINDOW_CLASS);
    if (windowClass) {
        for (UIWindow *window in HaloAllWindows()) {
            if ([window isKindOfClass:windowClass]) {
                *how = @"SBHomeScreenWindow";
                return window;
            }
        }
    }
    Class iconControllerClass = objc_getClass(HALO_SB_ICON_CONTROLLER_CLASS);
    if ([iconControllerClass respondsToSelector:@selector(sharedInstance)]) {
        id controller = [(id)iconControllerClass sharedInstance];
        if ([controller isKindOfClass:[UIViewController class]]) {
            UIWindow *window = ((UIViewController *)controller).viewIfLoaded.window;
            if (window) {
                *how = [NSString stringWithFormat:@"SBIconController's window (%@)", NSStringFromClass([window class])];
                return window;
            }
        }
    }
    return nil;
}

/// SpringBoard's main-display window scene (for the overlay window).
static UIWindowScene *HaloFindMainWindowScene(void) {
    NSString *how = nil;
    UIWindow *home = HaloFindHomeScreenWindow(&how);
    if (home.windowScene) return home.windowScene;
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.screen != UIScreen.mainScreen) continue;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) return windowScene;
        if (!fallback) fallback = windowScene;
    }
    return fallback;
}

- (void)attachWithRetry {
    NSUInteger generation = ++_attachGeneration;
    _attachAttempts = 0;
    [self setState:HaloEngineStateWaiting
            detail:halo_show_on_uses_overlay_window(_settings.showOn) ? @"Looking for SpringBoard's window scene."
                                                                      : @"Looking for the Home Screen window."];
    [self tryAttach:generation];
}

- (void)tryAttach:(NSUInteger)generation {
    if (generation != _attachGeneration || !_active || !_settings.targetsScreen) return;
    @try {
        if (halo_show_on_uses_overlay_window(_settings.showOn)) {
            UIWindowScene *scene = HaloFindMainWindowScene();
            if (scene) {
                [self attachToEdgeWindowOnScene:scene];
                return;
            }
        } else {
            NSString *how = nil;
            UIWindow *window = HaloFindHomeScreenWindow(&how);
            if (window) {
                [self attachToWindow:window how:how];
                return;
            }
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"attach: %@", exception.reason]];
        return;
    }
    if (++_attachAttempts >= kAttachAttempts) {
        [self setState:HaloEngineStateIncompatible
                detail:[NSString stringWithFormat:@"%@ was not found after %.0f s. Nothing is drawn.",
                                                  halo_show_on_uses_overlay_window(_settings.showOn)
                                                      ? @"SpringBoard's window scene"
                                                      : @"The Home Screen window",
                                                  kAttachAttempts * kAttachInterval]];
        [self writeStatus];
        return;
    }
    __weak HaloController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAttachInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf tryAttach:generation];
    });
}

- (void)attachToWindow:(UIWindow *)window how:(NSString *)how {
    if (!_overlay) {
        _overlay = [[HaloOverlayView alloc] initWithFrame:window.bounds];
        _overlay.delegate = self;
    }
    _overlay.frame = window.bounds;
    _host = window;
    _hostIsEdge = NO;
    _hostDescription = how ?: @"";
    _overlay.hidden = YES; // configured hidden; updateVisibility decides
    [window addSubview:_overlay];
    [self configureOverlay];
    [self updateVisibility];
    [self setState:HaloEngineStateActive detail:[self compatibilityNotes]];
    [self writeStatus];
}

- (void)attachToEdgeWindowOnScene:(UIWindowScene *)scene {
    if (!_edgeWindow) _edgeWindow = [[HaloEdgeWindow alloc] initForScene:scene];
    UIView *content = _edgeWindow.contentView;
    if (!_overlay) {
        _overlay = [[HaloOverlayView alloc] initWithFrame:content.bounds];
        _overlay.delegate = self;
    }
    _overlay.frame = content.bounds;
    _host = _edgeWindow;
    _hostIsEdge = YES;
    _hostDescription = [NSString stringWithFormat:@"HCG Halo overlay window (level %.0f)", HALO_EDGE_WINDOW_LEVEL];
    _overlay.hidden = YES;
    [content addSubview:_overlay];
    [self configureOverlay];
    [self updateVisibility];
    [self setState:HaloEngineStateActive detail:[self compatibilityNotes]];
    [self writeStatus];
}

- (void)haloOverlayViewDidChangeWindow:(HaloOverlayView *)view {
    if (view != _overlay) return;
    if (!view.window && _active && _settings.targetsScreen) {
        // The host window went away (SpringBoard rebuilt it): find it again.
        HaloLogInfo("overlay lost its window; re-attaching");
        _host = nil;
        [self attachWithRetry];
        return;
    }
    [self updateVisibility];
}

#pragma mark Configuration and visibility

- (HaloRenderPlan)currentPlan {
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    BOOL lowPower = [NSProcessInfo processInfo].lowPowerModeEnabled;
    return halo_render_plan(_settings.appearance.mode, reduceMotion, lowPower, _settings.lowPowerPolicy);
}

/// The profile for THIS screen: under Display Zoom the corners and notch are
/// scaled to the zoomed point size (halo_profile_geometry_for_screen).
- (HaloDisplayGeometry)screenGeometry {
    HaloScreenFit fit = HaloScreenFitUnknown;
    double k = 1;
    HaloDisplayGeometry g = halo_profile_geometry_for_screen(_settings.profile, _settings.calibration,
                                                             HaloCurrentScreenMeasure(), &fit, &k);
    if (fit != _screenFit || k != _lengthScale)
        HaloLogInfo("screen fit %s, corner/notch scale %.4f", halo_screen_fit_id(fit), k);
    _screenFit = fit;
    _lengthScale = k;
    return g;
}

- (void)configureOverlay {
    if (!_overlay) return;
    [_overlay setDisplayGeometry:[self screenGeometry] traceCutout:_settings.cutoutMode == HaloCutoutTrace];
    [_overlay setAppearance:_settings.appearance plan:[self currentPlan]];
}

- (void)updateVisibility {
    [_link setScreenOn:_screenOn];
    if (!_overlay) {
        _rendering = @"Not drawing";
        return;
    }
    UIWindow *host = _host;
    HaloSurfaceInputs inputs = {
        .base =
            {
                .enabled = _settings.enabled && !_faulted,
                .attached = _overlay.window != nil,
                .screenOn = _screenOn,
                .unlocked = _unlocked,
                .homeInFront = _homeInFront,
                // HCG Halo shows and hides its own overlay window itself.
                .hostVisible = _hostIsEdge ? host != nil : (host && !host.hidden && host.alpha > 0.01),
            },
        .showOn = _settings.showOn,
        .appChosen = _settings.showOnApp.length > 0,
        .frontAppKnown = _frontHookActive,
        .chosenAppInFront = _settings.showOnApp.length > 0 && [_frontApp isEqualToString:_settings.showOnApp],
    };
    const char *block = halo_surface_block(&inputs);
    HaloRenderPlan plan = [self currentPlan];
    BOOL visible = !block && !plan.hidden;
    BOOL wasHidden = _overlay.hidden;
    [_overlay setVisible:visible animating:plan.animated];
    if (_hostIsEdge) {
        if (_edgeWindow.hidden == visible) _edgeWindow.hidden = !visible; // no window, no compositing, while hidden
    } else if (visible && wasHidden) {
        [host bringSubviewToFront:_overlay];
    }

    NSString *mode = @(halo_mode_title(plan.mode));
    if (block) {
        _rendering = [NSString stringWithFormat:@"Hidden: %s", block];
    } else if (plan.hidden) {
        _rendering = @"Hidden: Low Power Mode";
    } else if (plan.animated) {
        _rendering = [NSString stringWithFormat:@"Animating: %@", mode];
    } else {
        _rendering = plan.reason[0] ? [NSString stringWithFormat:@"Static (%s)", plan.reason] : @"Static";
    }
    HaloLogDebug("visibility: %{public}@", _rendering);
}

- (void)frontDisplayDidChange:(id)display {
    if (!_active) return;
    @try {
        // Fail open: only an application counts as covering the Home Screen.
        Class applicationClass = objc_getClass(HALO_SB_APPLICATION_CLASS);
        BOOL app = display && applicationClass && [display isKindOfClass:applicationClass];
        _homeInFront = !app;
        _frontApp = app ? HaloBundleIdentifier(display) : @"";
        [self updateVisibility];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"front display: %@", exception.reason]];
    }
}

static NSString *HaloBundleIdentifier(id application) {
    if (![application respondsToSelector:@selector(bundleIdentifier)]) return @"";
    id identifier = [application bundleIdentifier];
    return [identifier isKindOfClass:[NSString class]] ? identifier : @"";
}

#pragma mark System observers

static BOOL HaloReadNotifyState(int token, uint64_t *state) {
    if (token == NOTIFY_TOKEN_INVALID) return NO;
    return notify_get_state(token, state) == NOTIFY_STATUS_OK;
}

- (void)startSystemObservers {
    __weak HaloController *weakSelf = self;
    dispatch_queue_t main = dispatch_get_main_queue();

    // Screen blanked (1) / lit (0). If unreadable, assume lit (fail open).
    if (notify_register_dispatch(kBlankedNotification.UTF8String, &_blankToken, main, ^(int token) {
            uint64_t state = 0;
            HaloController *strong = weakSelf;
            if (!strong) return;
            strong->_screenOn = HaloReadNotifyState(token, &state) ? state == 0 : YES;
            [strong updateVisibility];
        }) != NOTIFY_STATUS_OK) {
        _blankToken = NOTIFY_TOKEN_INVALID;
    }
    uint64_t state = 0;
    _screenOn = HaloReadNotifyState(_blankToken, &state) ? state == 0 : YES;

    // Locked (non-zero) / unlocked (0). If unreadable, assume unlocked.
    if (notify_register_dispatch(kLockStateNotification.UTF8String, &_lockToken, main, ^(int token) {
            uint64_t value = 0;
            HaloController *strong = weakSelf;
            if (!strong) return;
            strong->_unlocked = HaloReadNotifyState(token, &value) ? value == 0 : YES;
            [strong updateVisibility];
        }) != NOTIFY_STATUS_OK) {
        _lockToken = NOTIFY_TOKEN_INVALID;
    }
    state = 0;
    _unlocked = HaloReadNotifyState(_lockToken, &state) ? state == 0 : YES;

    // Initial app-in-front state, if SpringBoard can tell us.
    _homeInFront = YES;
    _frontApp = @"";
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
        id front = [(SpringBoard *)app _accessibilityFrontMostApplication];
        _homeInFront = front == nil;
        _frontApp = front ? HaloBundleIdentifier(front) : @"";
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^refresh)(NSNotification *) = ^(NSNotification *note) {
        [weakSelf configureOverlay];
        [weakSelf updateVisibility];
        [weakSelf applyNexusLink];
    };
    [_observerTokens addObject:[center addObserverForName:UIAccessibilityReduceTransparencyStatusDidChangeNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:refresh]];
    [_observerTokens addObject:[center addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:refresh]];
    [_observerTokens addObject:[center addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:refresh]];
    void (^windowChanged)(NSNotification *) = ^(NSNotification *note) {
        HaloController *strong = weakSelf;
        if (strong && note.object == strong->_host) [strong updateVisibility];
    };
    [_observerTokens addObject:[center addObserverForName:UIWindowDidBecomeHiddenNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:windowChanged]];
    [_observerTokens addObject:[center addObserverForName:UIWindowDidBecomeVisibleNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:windowChanged]];
}

- (void)stopSystemObservers {
    if (_blankToken != NOTIFY_TOKEN_INVALID) notify_cancel(_blankToken);
    if (_lockToken != NOTIFY_TOKEN_INVALID) notify_cancel(_lockToken);
    _blankToken = _lockToken = NOTIFY_TOKEN_INVALID;
    for (id token in _observerTokens) [[NSNotificationCenter defaultCenter] removeObserver:token];
    [_observerTokens removeAllObjects];
}

#pragma mark Status

- (NSString *)compatibilityNotes {
    NSMutableArray *notes = [NSMutableArray array];
    [notes addObject:[NSString stringWithFormat:@"Show Halo on: %s.", halo_show_on_title(_settings.showOn)]];
    [notes addObject:[NSString stringWithFormat:@"%@: %@.", _hostIsEdge ? @"Drawn in" : @"Home Screen window",
                                                _hostDescription]];
    [notes addObject:[NSString stringWithFormat:@"App detection: %@.", _frontDetection]];
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion < 15 || v.majorVersion > 17)
        [notes addObject:[NSString stringWithFormat:@"iOS %ld is outside the iOS 15–17 interfaces HCG Halo was written "
                                                    @"against; untested.",
                                                    (long)v.majorVersion]];
    return [notes componentsJoinedByString:@" "];
}

- (NSString *)screenDescription {
    UIScreen *screen = UIScreen.mainScreen;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@ · %@", HaloScreenSummary(), HaloMachineIdentifier()];
    @try {
        if ([screen respondsToSelector:NSSelectorFromString(@"_displayCornerRadius")]) {
            id radius = [screen valueForKey:@"_displayCornerRadius"];
            if ([radius isKindOfClass:[NSNumber class]] && [radius doubleValue] > 0)
                [text appendFormat:@" · iOS reports corner radius %.1f pt", [radius doubleValue]];
        }
    } @catch (NSException *exception) {
        // Informational only.
    }
    return text;
}

- (NSString *)profileMatch {
    const HaloProfile *profile = _settings.profile;
    if (!profile) return @"No implemented profile selected.";
    return HaloScreenFitSentence(profile, HaloCurrentScreenMeasure());
}

- (void)writeStatus {
    @try {
        NSDictionary *status = @{
            HaloStatusKeyState : _state ?: @"",
            HaloStatusKeyDetail : _detail ?: @"",
            HaloStatusKeyRendering : _rendering ?: @"",
            HaloStatusKeyHost : _hostDescription ?: @"",
            HaloStatusKeyFrontDetection : _frontDetection ?: @"",
            HaloStatusKeyScreen : [self screenDescription],
            HaloStatusKeyProfileMatch : _blocked ? @"" : [self profileMatch],
            HaloStatusKeyTweakVersion : @HALO_VERSION,
            HaloStatusKeyBuildID : @HALO_BUILD_ID,
            HaloStatusKeySystemVersion : [NSProcessInfo processInfo].operatingSystemVersionString ?: @"",
            HaloStatusKeyTimestamp : [NSDate date],
            HaloStatusKeyNexusState : _link.state ?: @"",
            HaloStatusKeyNexusDetail : _link.detail ?: @"",
            HaloStatusKeyNexusRendering : _link.rendering ?: @"",
            HaloStatusKeyShowOn : @(halo_show_on_id(_settings.showOn)),
            HaloStatusKeyFrontApp : _frontHookActive ? (_frontApp ?: @"") : @"(not detected)",
            HaloStatusKeySurfaceHost : !_overlay ? @"" : (_hostIsEdge ? @"HCG Halo overlay window" : @"Home Screen window"),
            HaloStatusKeyScreenFit : @(halo_screen_fit_id(_overlay ? _screenFit
                                                                   : halo_profile_fit(_settings.profile,
                                                                                      HaloCurrentScreenMeasure(), NULL))),
        };
        [HaloPreferences writeStatus:status];
    } @catch (NSException *exception) {
        HaloLogError("could not write status: %{public}@", exception.reason);
    }
}

@end

#pragma mark - C entry points

void HaloControllerBootstrap(HaloHookInstaller installFrontDisplayHook) {
    @autoreleasepool {
#ifndef HALO_PREVIEW_HOST
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
#endif
        @try {
            [[HaloController shared] bootstrapWithHookInstaller:installFrontDisplayHook];
        } @catch (NSException *exception) {
            HaloLogError("bootstrap raised %{public}@; HCG Halo stays inactive", exception.reason);
        }
    }
}

void HaloControllerFrontDisplayDidChange(id display) {
    [[HaloController shared] frontDisplayDidChange:display];
}
