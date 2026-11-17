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
//  Visibility: the overlay draws only while the screen is on, the device is
//  unlocked, no app is in front and the Home Screen window is visible. When
//  any of these is false it is hidden AND its layer clock is frozen, so it
//  costs nothing. Reduce Motion and Low Power Mode change the render plan
//  (HaloConfig.c, halo_render_plan).
//
//  Failure policy: anything unexpected removes the overlay and reports
//  "fault" in Settings; Home Screen behaviour is never touched.
//

#import "HaloController.h"
#import "HaloLog.h"
#import "HaloOverlayView.h"
#import "HaloPreferences.h"
#import "HaloSpringBoard.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>

static NSString *const kBlankedNotification = @"com.apple.springboard.hasBlankedScreen";
static NSString *const kLockStateNotification = @"com.apple.springboard.lockstate";

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
    NSString *_hostDescription;
    NSUInteger _attachGeneration;
    NSInteger _attachAttempts;

    // Visibility inputs
    BOOL _screenOn;
    BOOL _unlocked;
    BOOL _homeInFront;
    int _blankToken;
    int _lockToken;
    NSMutableArray<id> *_observerTokens;
    BOOL _hookAttempted;
    NSString *_frontDetection;
    NSString *_rendering;
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
        _blankToken = NOTIFY_TOKEN_INVALID;
        _lockToken = NOTIFY_TOKEN_INVALID;
        _observerTokens = [NSMutableArray array];
        _frontDetection = @"not started";
        _rendering = @"Not drawing";
        _hostDescription = @"";
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
        [self installFrontDisplayHookOnce];
        [self startSystemObservers];
    }
    if (!_overlay.window) {
        [self attachWithRetry];
    } else {
        [self configureOverlay];
        [self updateVisibility];
    }
}

- (void)deactivate {
    _attachGeneration++; // cancels pending attach retries
    if (_overlay) {
        _overlay.delegate = nil;
        [_overlay teardown];
        [_overlay removeFromSuperview];
        _overlay = nil;
    }
    _host = nil;
    if (_active) {
        [self stopSystemObservers];
        _active = NO;
    }
    _rendering = @"Not drawing";
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
    _frontDetection = before != after ? @"active (frontDisplayDidChange: hook)"
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

- (void)attachWithRetry {
    NSUInteger generation = ++_attachGeneration;
    _attachAttempts = 0;
    [self setState:HaloEngineStateWaiting detail:@"Looking for the Home Screen window."];
    [self tryAttach:generation];
}

- (void)tryAttach:(NSUInteger)generation {
    if (generation != _attachGeneration || !_active) return;
    @try {
        NSString *how = nil;
        UIWindow *window = HaloFindHomeScreenWindow(&how);
        if (window) {
            [self attachToWindow:window how:how];
            return;
        }
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"attach: %@", exception.reason]];
        return;
    }
    if (++_attachAttempts >= kAttachAttempts) {
        [self setState:HaloEngineStateIncompatible
                detail:[NSString stringWithFormat:@"The Home Screen window was not found after %.0f s. Nothing is drawn.",
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
    _hostDescription = how ?: @"";
    _overlay.hidden = YES; // configured hidden; updateVisibility decides
    [window addSubview:_overlay];
    [self configureOverlay];
    [self updateVisibility];
    [self setState:HaloEngineStateActive detail:[self compatibilityNotes]];
    [self writeStatus];
}

- (void)haloOverlayViewDidChangeWindow:(HaloOverlayView *)view {
    if (view != _overlay) return;
    if (!view.window && _active) {
        // The Home Screen window went away (SpringBoard rebuilt it): find it again.
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

- (void)configureOverlay {
    if (!_overlay) return;
    [_overlay setDisplayGeometry:_settings.geometry traceCutout:_settings.cutoutMode == HaloCutoutTrace];
    [_overlay setAppearance:_settings.appearance plan:[self currentPlan]];
}

- (void)updateVisibility {
    if (!_overlay) {
        _rendering = @"Not drawing";
        return;
    }
    UIWindow *host = _host;
    HaloVisibilityInputs inputs = {
        .enabled = _settings.enabled && !_faulted,
        .attached = _overlay.window != nil,
        .screenOn = _screenOn,
        .unlocked = _unlocked,
        .homeInFront = _homeInFront,
        .hostVisible = host && !host.hidden && host.alpha > 0.01,
    };
    const char *block = halo_visibility_block(&inputs);
    HaloRenderPlan plan = [self currentPlan];
    BOOL visible = !block && !plan.hidden;
    BOOL wasHidden = _overlay.hidden;
    [_overlay setVisible:visible animating:plan.animated];
    if (visible && wasHidden) [host bringSubviewToFront:_overlay];

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
        [self updateVisibility];
    } @catch (NSException *exception) {
        [self fault:[NSString stringWithFormat:@"front display: %@", exception.reason]];
    }
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
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
        _homeInFront = [(SpringBoard *)app _accessibilityFrontMostApplication] == nil;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    void (^refresh)(NSNotification *) = ^(NSNotification *note) {
        [weakSelf configureOverlay];
        [weakSelf updateVisibility];
    };
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
    [notes addObject:[NSString stringWithFormat:@"Home Screen window: %@.", _hostDescription]];
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
    CGSize size = screen.fixedCoordinateSpace.bounds.size;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%.0f × %.0f pt @%.0fx", size.width, size.height, screen.scale];
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
    CGSize size = UIScreen.mainScreen.fixedCoordinateSpace.bounds.size;
    if (halo_profile_matches_screen(profile, size.width, size.height))
        return [NSString stringWithFormat:@"Screen size matches %s.", profile->name];
    return [NSString stringWithFormat:@"MISMATCH: this screen is %.0f × %.0f pt but %s is %.0f × %.0f pt. The border is "
                                      @"stretched to fit and the corners/notch will be misaligned.",
                                      size.width, size.height, profile->name, profile->screenWidth, profile->screenHeight];
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
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
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
