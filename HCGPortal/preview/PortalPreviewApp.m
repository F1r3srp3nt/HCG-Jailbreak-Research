//
//  PortalPreviewApp.m
//  HCG Portal — PREVIEW and integration run (iOS Simulator only).
//
//  Built by scripts/preview.sh. One app plays two roles:
//
//  1. A stand-in Lock Screen running the REAL tweak code (PortalController,
//     PortalHost, PortalOverlayView, PortalView, PortalAuth, PortalCompanions)
//     the way SpringBoard would: a CSCoverSheetViewController stand-in with a
//     clock, widgets, notifications, a media platter and the flashlight /
//     camera buttons; an SBLockScreenManager stand-in whose authentication is
//     scripted (hold / succeed / cancel / refuse); lock and screen state as
//     Darwin notifications with notify state (preview names). The three
//     Cover Sheet hooks are called by this harness exactly where Tweak.m calls
//     them.
//
//  2. Settings: loads the REAL HCGPortalPrefs.bundle (compiled for the
//     Simulator) with Preferences.framework from the Simulator runtime and
//     shows the root page, Position & Size and HCG Apps.
//
//  Touches: the harness asks the real window to hit-test a point (the same
//  call UIKit makes for a finger) and sends the control's action, or calls the
//  overlay's own touch decision for a tap outside. Real fingers, gestures and
//  the system authentication UI are NOT exercised: those are device rows.
//
//  Prints "PORTAL-PREVIEW-STATE <name> | …", "PORTAL-PREVIEW-SHOT <name>" (the
//  script takes a Simulator screenshot), "PORTAL-PREVIEW-CHECK PASS|FAIL
//  <what>", then "PORTAL-PREVIEW-DONE failures=N".
//

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "PortalCompanions.h"
#import "PortalController.h"
#import "PortalCore.h"
#import "PortalLauncher.h"
#import "PortalOverlayView.h"
#import "PortalPreferences.h"
#import "PortalStandIns.h"
#import "PortalView.h"

#include <dlfcn.h>
#include <notify.h>

static int gFailures = 0;
static IMP gLaunchWillAppearIMP; // CSCoverSheetViewController's own viewWillAppear: before anything could hook it
static NSMutableArray<NSString *> *gLaunches;

static void Say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static void Check(BOOL ok, NSString *what) {
    if (!ok) gFailures++;
    Say(@"PORTAL-PREVIEW-CHECK %@ %@", ok ? @"PASS" : @"FAIL", what);
}

static NSString *Status(NSString *key) {
    id v = PortalControllerPreviewStatus()[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static BOOL IsInside(UIView *view, UIView *ancestor) {
    for (UIView *v = view; v; v = v.superview)
        if (v == ancestor) return YES;
    return NO;
}

@interface PortalPreviewController : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIWindow *settingsWindow;
@property (nonatomic, strong) UINavigationController *settingsNav;
@property (nonatomic, strong) CSCoverSheetViewController *coverSheet;
@property (nonatomic, strong) NSMutableArray *steps;
@property (nonatomic, copy) NSString *jbroot;
@end

@implementation PortalPreviewController

- (PortalOverlayView *)overlay {
    return PortalControllerPreviewOverlay();
}

- (void)state:(NSString *)name caption:(NSString *)caption {
    _coverSheet.caption.text = [NSString stringWithFormat:@"PREVIEW · iOS Simulator stand-in, not a device · %@", caption];
    Say(@"PORTAL-PREVIEW-STATE %@ | visibility=%@ | layout=%@ | plan=%@ | last=%@", name, Status(PortalStatusKeyVisibility),
        Status(PortalStatusKeyLayout), Status(PortalStatusKeyPlan), Status(PortalStatusKeyLastAction));
}

- (void)shot:(NSString *)name {
    [CATransaction flush];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *ack = [[docs stringByAppendingPathComponent:@"shot-ack"] stringByAppendingPathComponent:name];
    Say(@"PORTAL-PREVIEW-SHOT %@", name);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (![[NSFileManager defaultManager] fileExistsAtPath:ack] && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:ack]) Say(@"PORTAL-PREVIEW-NOTE no screenshot ack for %@", name);
}

- (void)next {
    if (!_steps.count) return;
    void (^step)(void) = _steps.firstObject;
    [_steps removeObjectAtIndex:0];
    step();
}

- (void)setPrefs:(NSDictionary *)values {
    for (NSString *key in values) {
        id v = values[key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, v == [NSNull null] ? NULL : (__bridge CFPropertyListRef)v,
                                 (__bridge CFStringRef)PortalPreferencesDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalPreferencesDomain);
    PortalControllerPreviewReload();
}

- (void)setLocked:(BOOL)locked {
    [SBLockScreenManager standIn].uiLocked = locked;
    PSIPostState(PORTAL_LOCKSTATE_NOTIFICATION, locked ? 1 : 0);
}

- (void)setScreenOn:(BOOL)on {
    PSIPostState(PORTAL_BLANKED_NOTIFICATION, on ? 0 : 1);
}

- (void)showCoverSheet:(BOOL)show {
    [SBCoverSheetPresentationManager standIn].visible = show;
    if (show) {
        _window.hidden = NO;
        [_coverSheet beginAppearanceTransition:YES animated:NO];
        [_coverSheet endAppearanceTransition];
        PortalControllerCoverSheetWillAppear(_coverSheet); // as the viewWillAppear: hook does
    } else {
        _window.hidden = YES;
        PortalControllerCoverSheetDidDisappear(_coverSheet); // as the viewDidDisappear: hook does
    }
}

- (void)relayout {
    [_coverSheet.view layoutIfNeeded];
    PortalControllerCoverSheetDidLayout(_coverSheet); // as the viewDidLayoutSubviews hook does
    PortalControllerPreviewRelayout();
}

/// UIKit's own hit-test for a finger at `point` (window coordinates).
- (UIView *)hit:(CGPoint)point {
    return [_window hitTest:point withEvent:nil];
}

- (CGPoint)orbCentre {
    PortalOverlayView *o = [self overlay];
    return [o convertPoint:CGPointMake(CGRectGetMidX(o.orbFrame), CGRectGetMidY(o.orbFrame)) toView:_window];
}

- (BOOL)tapOrb {
    UIView *v = [self hit:[self orbCentre]];
    if (![v isKindOfClass:[UIControl class]] || !IsInside(v, [self overlay])) return NO;
    [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

- (BOOL)tapItemTitled:(NSString *)title {
    PortalOverlayView *o = [self overlay];
    for (NSUInteger i = 0; i < o.currentItems.count && i < o.itemControls.count; i++) {
        if (![o.currentItems[i].title isEqualToString:title]) continue;
        UIControl *c = o.itemControls[i];
        CGPoint p = [c convertPoint:CGPointMake(CGRectGetMidX(c.bounds), CGRectGetMidY(c.bounds)) toView:_window];
        UIView *v = [self hit:p];
        if (v != c) {
            NSMutableString *chain = [NSMutableString string];
            for (UIView *s = v; s; s = s.superview) [chain appendFormat:@" < %@", NSStringFromClass([s class])];
            Say(@"PORTAL-PREVIEW-NOTE tap %@: hit %@ (ring %@, expanded %d, hidden %d, alpha %.2f, overlay index %lu of %lu)",
                  title, chain, o.ringName, o.expanded, o.hidden, o.alpha,
                  (unsigned long)[o.superview.subviews indexOfObject:o], (unsigned long)o.superview.subviews.count);
            return NO;
        }
        [c sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return NO;
}

- (NSString *)statusTextOfItem:(NSString *)title {
    for (PortalMenuItem *i in [self overlay].currentItems)
        if ([i.title isEqualToString:title]) return i.statusText;
    return nil;
}

- (void)installCompanion:(NSString *)relativePath {
    NSString *path = [_jbroot stringByAppendingPathComponent:relativePath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

/// Loads the REAL Settings bundle once and shows a fresh root page.
- (UIViewController *)showSettingsRoot {
    static BOOL loaded;
    NSBundle *bundle = [NSBundle bundleWithPath:[NSBundle.mainBundle pathForResource:@"HCGPortalPrefs" ofType:@"bundle"]];
    if (!loaded) {
        void *prefs = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_NOW | RTLD_GLOBAL);
        Check(prefs != NULL, @"Preferences.framework loaded from the Simulator runtime");
        NSError *error = nil;
        Check([bundle loadAndReturnError:&error], [NSString stringWithFormat:@"Settings bundle loads (%@)", error.localizedDescription ?: @"ok"]);
        loaded = YES;
    }
    UIViewController *root = [[bundle.principalClass alloc] init];
    [self.settingsNav setViewControllers:@[ root ] animated:NO];
    self.settingsWindow.hidden = NO;
    [root loadViewIfNeeded];
    return root;
}

/// What the REAL Settings controller displays in its Status and "On the Lock Screen" rows and
/// in the status footer (the same getter methods and specifier Settings' table cells use).
- (NSString *)settingsText:(UIViewController *)root {
    [root valueForKey:@"specifiers"]; // loads Root.plist and fills the dynamic footers
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *getter in @[ @"engineStatus:", @"visibilityStatus:" ]) {
        SEL sel = NSSelectorFromString(getter);
        if ([root respondsToSelector:sel]) {
            id value = ((id(*)(id, SEL, id))objc_msgSend)(root, sel, nil);
            if ([value isKindOfClass:[NSString class]]) [parts addObject:value];
        }
    }
    id group = ((id(*)(id, SEL, id))objc_msgSend)(root, NSSelectorFromString(@"specifierForID:"), @"statusDetailGroup");
    id footer = [group respondsToSelector:NSSelectorFromString(@"propertyForKey:")]
                    ? ((id(*)(id, SEL, id))objc_msgSend)(group, NSSelectorFromString(@"propertyForKey:"), @"footerText")
                    : nil;
    if ([footer isKindOfClass:[NSString class]]) [parts addObject:footer];
    return [parts componentsJoinedByString:@" | "];
}

/// Portal overlays anywhere in the Lock Screen window (there must never be more than one).
- (NSUInteger)portalViewsInWindow {
    NSUInteger n = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:self.window];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:[PortalOverlayView class]]) n++;
        [stack addObjectsFromArray:v.subviews];
    }
    return n;
}

- (NSInteger)counter:(NSString *)name {
    NSDictionary *c = PortalControllerPreviewStatus()[PortalStatusKeyCounters];
    return [c[name] integerValue];
}

- (BOOL)orbClearOfObstacles {
    PortalOverlayView *o = [self overlay];
    CGRect orb = [o convertRect:o.orbFrame toView:_window];
    NSMutableArray *views = [NSMutableArray arrayWithArray:_coverSheet.notificationCells];
    [views addObject:_coverSheet.flashlight];
    [views addObject:_coverSheet.camera];
    if (_coverSheet.mediaView) [views addObject:_coverSheet.mediaView];
    [views addObject:_coverSheet.dateView];
    [views addObject:_coverSheet.complicationContainerViewController.view];
    for (UIView *v in views) {
        if (v.hidden) continue;
        if (CGRectIntersectsRect(orb, [v convertRect:v.bounds toView:_window])) return NO;
    }
    return YES;
}

- (void)buildScript {
    __weak PortalPreviewController *weakSelf = self;
#define STEP(delay, ...)                                                                                   \
    [_steps addObject:^{                                                                                   \
        [NSTimer scheduledTimerWithTimeInterval:(delay)                                                    \
                                        repeats:NO                                                         \
                                          block:^(NSTimer *timer_) {                                       \
                                              PortalPreviewController *self = weakSelf;                    \
                                              if (!self) return;                                           \
                                              @try {                                                       \
                                                  __VA_ARGS__;                                             \
                                              } @catch (NSException * e) {                                 \
                                                  Check(NO, [NSString stringWithFormat:@"exception: %@ — %@", e.name, e.reason]); \
                                              }                                                            \
                                              [self next];                                                 \
                                          }];                                                              \
    }]
#define WAIT_UNTIL(timeout, cond)                                                                          \
    do {                                                                                                   \
        NSDate *limit_ = [NSDate dateWithTimeIntervalSinceNow:(timeout)];                                   \
        while (!(cond) && [limit_ timeIntervalSinceNow] > 0)                                               \
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; \
    } while (0)

    // ---- 0. Installed, off -------------------------------------------------------
    STEP(1.0, {
        Check([self overlay] == nil, @"off after installation: no portal on the Lock Screen");
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateDisabled], @"engine state: disabled");
        Check(!PortalPreferences.loadSettings.enabled, @"fresh install: Enable defaults to off");
        // The bootstrap ran from the real Tweak.m constructor and wrote its status; Settings asks again.
        notify_post(PortalStatusRequestNotification.UTF8String);
        WAIT_UNTIL(1.5, NO);
        Check(SBLockScreenManager.sharedInstanceCalls == 0 && SBCoverSheetPresentationManager.sharedInstanceCalls == 0,
              [NSString stringWithFormat:@"while off: SpringBoard's Lock Screen singletons never touched (SBLockScreenManager %lu, "
                                         @"SBCoverSheetPresentationManager %lu calls)",
                                         (unsigned long)SBLockScreenManager.sharedInstanceCalls,
                                         (unsigned long)SBCoverSheetPresentationManager.sharedInstanceCalls]);
        Check([Status(PortalStatusKeyHooks) hasPrefix:@"not installed"], @"while off: no hook installed");
        Check(class_getMethodImplementation([CSCoverSheetViewController class], @selector(viewWillAppear:)) == gLaunchWillAppearIMP &&
                  CSCoverSheetViewController.originalWillAppearCalls >= 1,
              @"while off: the Lock Screen's own viewWillAppear: is not replaced and still runs");
        [self state:@"00-off" caption:@"HCG Portal installed, off"];
        [self shot:@"00-off"];
    });

    // ---- 0b. Enabled while the injector's hook API is unavailable ---------------------
    STEP(0.5, {
        IMP before = class_getMethodImplementation(NSClassFromString(@"CSCoverSheetViewController"), @selector(viewWillAppear:));
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        WAIT_UNTIL(1, NO);
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateIncompatible],
              [NSString stringWithFormat:@"hook API unavailable: Portal stays inactive (state %@)", Status(PortalStatusKeyState)]);
        Check([Status(PortalStatusKeyDetail) containsString:@"MSHookMessageEx"] && [Status(PortalStatusKeyDetail) containsString:@"stays inactive"],
              [NSString stringWithFormat:@"hook API unavailable: clear reason (%@)", Status(PortalStatusKeyDetail)]);
        Check([self overlay] == nil, @"hook API unavailable: nothing added to the Lock Screen");
        Check(class_getMethodImplementation(NSClassFromString(@"CSCoverSheetViewController"), @selector(viewWillAppear:)) == before,
              @"hook API unavailable: no method replaced");
        Check(SBLockScreenManager.sharedInstanceCalls == 0 && SBCoverSheetPresentationManager.sharedInstanceCalls == 0,
              @"hook API unavailable: SpringBoard's Lock Screen singletons still untouched");
        UIViewController *root = [self showSettingsRoot];
        WAIT_UNTIL(0.8, NO);
        NSString *text = [self settingsText:root];
        Check([text containsString:@"Incompatible: inactive"] && [text containsString:@"Not shown (inactive)"] &&
                  [text containsString:@"MSHookMessageEx"],
              [NSString stringWithFormat:@"Settings shows the state and the reason (%@)", [text substringToIndex:MIN((NSUInteger)240, text.length)]]);
        [self state:@"00b-hook-api-unavailable" caption:@"Enabled without the injector's hook API: inactive, reason in Settings"];
        [self shot:@"00b-settings-hook-api-unavailable"];
        self.settingsWindow.hidden = YES;
    });

    // ---- 0c. The hook API becomes available: Enable off and on retries -------------------
    STEP(0.5, {
        PortalPreviewSetHookAPI(PSIHookMessageEx);
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        WAIT_UNTIL(1, [Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive]);
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"Enable off and on with the hook API present: active");
        Check([Status(PortalStatusKeyHooks) hasPrefix:@"CSCoverSheetViewController viewWillAppear:"], @"the three Cover Sheet hooks are installed");
        NSUInteger originals = CSCoverSheetViewController.originalWillAppearCalls;
        Check(class_getMethodImplementation([CSCoverSheetViewController class], @selector(viewWillAppear:)) != gLaunchWillAppearIMP,
              @"viewWillAppear: now goes through Portal's hook");
        [self.coverSheet viewWillAppear:NO]; // dispatches through the installed hook
        Check(CSCoverSheetViewController.originalWillAppearCalls == originals + 1,
              @"the installed viewWillAppear: hook calls the original exactly once");
        [self setPrefs:@{PortalKeyEnabled : @NO}]; // step 1 enables it as before
    });

    // ---- 1. Enabled: idle portal below the clock --------------------------------
    STEP(0.5, {
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        [self relayout];
        WAIT_UNTIL(3, [self overlay].superview != nil);
        PortalOverlayView *o = [self overlay];
        Check(o.superview == self.coverSheet.mainPageContentViewController.view, @"hosted in the Lock Screen's main page");
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"visible"], @"visible on the lit Lock Screen");
        Check(o.layout.mode == PORTAL_LAYOUT_FULL && o.layout.diameter == PORTAL_SIZE_DEFAULT, @"full size by default (132 pt)");
        CGRect orb = [o convertRect:o.orbFrame toView:self.window];
        CGFloat widgetsBottom = CGRectGetMaxY([self.coverSheet.complicationContainerViewController.view
            convertRect:self.coverSheet.complicationContainerViewController.view.bounds toView:self.window]);
        Check(CGRectGetMinY(orb) >= widgetsBottom, @"below the clock and widgets");
        Check(CGRectGetMaxY(orb) <= CGRectGetMinY(self.coverSheet.flashlight.frame), @"above the flashlight and camera");
        Check([Status(PortalStatusKeyLayout) containsString:@"SBFLockScreenDateView"], @"anchor measured from the date view");
        Check(o.portalView.runningAnimationCount >= 4 && o.portalView.emitterActive && !o.portalView.isPaused,
              @"idle: slow rotating rings, restrained particles");
        Check([Status(PortalStatusKeyAuthRoute) isEqualToString:@"coverSheetContext"], @"authentication route: CoverSheet context");
        UIView *clockHit = [self hit:CGPointMake(self.window.bounds.size.width / 2, 140)];
        Check(!IsInside(clockHit, o), @"the clock area is not intercepted");
        UIView *bottom = [self hit:CGPointMake(self.window.bounds.size.width / 2, self.window.bounds.size.height - 10)];
        Check(!IsInside(bottom, o), @"the unlock-gesture area is not intercepted");
        Check([self hit:self.coverSheet.camera.center] == self.coverSheet.camera, @"camera button still takes its touch");
        Check([self hit:self.coverSheet.flashlight.center] == self.coverSheet.flashlight, @"flashlight button still takes its touch");
        [self state:@"01-idle" caption:@"Idle: rings turn slowly below the clock"];
        [self shot:@"01-idle"];
    });

    // ---- 2. Tap: radial menu; tap outside: collapse ---------------------------------
    STEP(0.8, {
        Check([self tapOrb], @"tap on the orb reaches the orb through the window's hit-test");
        WAIT_UNTIL(1, [self overlay].expanded);
        PortalOverlayView *o = [self overlay];
        Check(o.expanded && o.itemControls.count == 4, @"tap: the radial menu expands with four destinations");
        NSArray *titles = [o.currentItems valueForKey:@"title"];
        Check([titles isEqualToArray:@[ @"Nexus", @"Backgrounds", @"Devices", @"HCG Apps" ]], @"Nexus, Backgrounds, Devices, HCG Apps");
        Check([[self statusTextOfItem:@"Nexus"] isEqualToString:@"Not installed"] &&
                  [[self statusTextOfItem:@"Backgrounds"] isEqualToString:@"Not installed"] &&
                  [[self statusTextOfItem:@"Devices"] isEqualToString:@"Not connected"],
              @"missing companions show clear unavailable states");
        WAIT_UNTIL(0.6, NO);
        [self state:@"02-expanded" caption:@"Tap: radial menu (companions not installed)"];
        [self shot:@"02-expanded"];
    });
    STEP(0.3, {
        PortalOverlayView *o = [self overlay];
        CGPoint outside = CGPointMake(60, 120);
        UIView *under = [self hit:outside];
        Check(!IsInside(under, o), @"tap outside: the touch passes through to the Lock Screen");
        [o portalHitTest:[o convertPoint:outside fromView:self.window] touch:YES timestamp:CACurrentMediaTime()];
        WAIT_UNTIL(1.5, ![self overlay].expanded);
        Check(!o.expanded, @"tap outside: the menu collapses");
        [self state:@"03-collapsed" caption:@"Tap outside: collapsed"];
        [self shot:@"03-collapsed"];
    });

    // ---- 3. Unavailable states: nothing launches, no authentication -------------------
    STEP(0.5, {
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        NSUInteger requests = [SBLockScreenManager standIn].requestCount;
        Check([self tapItemTitled:@"Nexus"], @"Nexus item reachable");
        Check([[self overlay].visibleMessage isEqualToString:@"HCG Nexus isn't installed."], @"Nexus absent: says so");
        Check([self tapItemTitled:@"Devices"], @"Devices item reachable");
        Check([[self overlay].visibleMessage hasPrefix:@"Not connected."], @"Devices: Not connected");
        Check([SBLockScreenManager standIn].requestCount == requests && gLaunches.count == 0,
              @"unavailable destinations request no authentication and launch nothing");
        WAIT_UNTIL(0.4, NO);
        [self state:@"04-not-connected" caption:@"Devices: Not connected (no Connector/Origin integration exists)"];
        [self shot:@"04-not-connected"];
        [[self overlay] collapseAnimated:NO];
    });

    // ---- 4. Companions installed (Nexus 0.3.1~beta1 has no open interface) -------------
    STEP(0.5, {
        [self installCompanion:@"Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle/Info.plist"];
        [self installCompanion:@"Library/PreferenceLoader/Preferences/HCGAnimationCenterPrefs.plist"];
        [self installCompanion:@"Library/PreferenceBundles/HCGNexusPrefs.bundle/Info.plist"];
        PortalControllerPreviewRelayout();
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([[self statusTextOfItem:@"Nexus"] isEqualToString:@"Update needed"], @"Nexus installed without the interface: Update needed");
        Check([[self statusTextOfItem:@"Backgrounds"] isEqualToString:@""], @"Animation Center installed: Backgrounds available");
        [self tapItemTitled:@"Nexus"];
        Check([[self overlay].visibleMessage containsString:@"needs a Nexus update"], @"Nexus: explains the update it needs");
        WAIT_UNTIL(0.4, NO);
        [self state:@"05-companions" caption:@"Animation Center installed; HCG Nexus 0.3.1 lacks the open interface"];
        [self shot:@"05-companions"];
    });

    // ---- 5. Backgrounds: authentication, then Settings opens ------------------------------
    STEP(0.5, {
        SBLockScreenManager *m = [SBLockScreenManager standIn];
        m.authMode = PSIAuthHold;
        NSUInteger before = m.requestCount;
        if (![self overlay].expanded) {
            [self tapOrb];
            WAIT_UNTIL(1, [self overlay].expanded);
        }
        Check([self tapItemTitled:@"Backgrounds"], @"Backgrounds selected");
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"authenticating"]);
        Check(m.requestCount == before + 1 && m.hasPendingRequest, @"protected destination: authentication requested");
        Check(gLaunches.count == 0, @"nothing opens before authentication succeeds");
        Check([self overlay].hidden && [self overlay].portalView.isPaused, @"portal hidden and paused while iOS authenticates");
        [self state:@"06-authenticating" caption:@"Backgrounds: waiting for Face ID / passcode (stand-in sheet)"];
        [self shot:@"06-authenticating"];
    });
    STEP(0.3, {
        [[SBLockScreenManager standIn] resolvePending:YES];
        WAIT_UNTIL(2, gLaunches.count > 0);
        Check(gLaunches.count == 1 && [gLaunches[0] isEqualToString:@"com.apple.Preferences"],
              @"after success: exactly the selected action ran (Settings opened for Animation Center)");
        WAIT_UNTIL(2, [Status(PortalStatusKeyLastAction) containsString:@"Settings opened"]);
        Check([Status(PortalStatusKeyLastAction) containsString:@"Settings opened"], @"last action recorded");
        [self state:@"07-opened-settings" caption:@"Authenticated: Settings opened for HCG Animation Center"];
    });

    // ---- 6. HCG Apps ring; cancellation discards ----------------------------------
    STEP(0.5, {
        [gLaunches removeAllObjects];
        [self relayout];
        WAIT_UNTIL(1, ![self overlay].hidden);
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self tapItemTitled:@"HCG Apps"], @"HCG Apps selected");
        WAIT_UNTIL(1, [[self overlay].ringName isEqualToString:@"apps"]);
        PortalOverlayView *o = [self overlay];
        Check([o.ringName isEqualToString:@"apps"] && o.itemControls.count == 3, @"app ring: the three chosen apps");
        Check([SBLockScreenManager standIn].requestCount > 0 && gLaunches.count == 0, @"showing the ring launches nothing");
        WAIT_UNTIL(0.6, NO);
        [self state:@"08-apps-ring" caption:@"HCG Apps: user-selected shortcuts"];
        [self shot:@"08-apps-ring"];
    });
    STEP(0.3, {
        SBLockScreenManager *m = [SBLockScreenManager standIn];
        m.authMode = PSIAuthHold;
        Check([self tapItemTitled:@"HCG News"], @"app 2 selected");
        WAIT_UNTIL(1, m.hasPendingRequest);
        void (^replay)(BOOL) = [m resolvePending:NO];
        WAIT_UNTIL(1, ![self overlay].hidden);
        Check(gLaunches.count == 0, @"cancelled: the pending action is discarded, nothing opens");
        Check([Status(PortalStatusKeyLastAction) containsString:@"cancelled"], @"cancellation recorded");
        if (replay) replay(YES);
        WAIT_UNTIL(0.5, NO);
        Check(gLaunches.count == 0, @"a late success for the cancelled request is ignored");
        Check(![self overlay].hidden, @"portal back after cancellation");
        [self state:@"09-cancelled" caption:@"Cancelled: nothing opened"];
        [self shot:@"09-cancelled"];
    });

    // ---- 7. App launch after success; screen-off discards ----------------------------
    STEP(0.4, {
        SBLockScreenManager *m = [SBLockScreenManager standIn];
        m.authMode = PSIAuthSucceed;
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self tapItemTitled:@"HCG Apps"];
        Check([self tapItemTitled:@"HCG Terminal"], @"app 1 selected");
        WAIT_UNTIL(2, gLaunches.count > 0);
        Check(gLaunches.count == 1 && [gLaunches[0] isEqualToString:@"com.hakmicapitalgroup.hcgterminal"],
              @"after success: exactly that app opened, once");
        [gLaunches removeAllObjects];

        m.authMode = PSIAuthHold;
        [self relayout];
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self tapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(1, m.hasPendingRequest);
        [self setScreenOn:NO];
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"screen-off"]);
        Check([self overlay].portalView.isPaused, @"screen off: rendering paused");
        [m resolvePending:YES];
        WAIT_UNTIL(0.5, NO);
        Check(gLaunches.count == 0, @"screen turned off during authentication: the action is discarded");
        [self setScreenOn:YES];
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check(![self overlay].portalView.isPaused, @"screen on: rendering resumes");

        m.authMode = PSIAuthRefuse;
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self tapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(1, [self overlay].visibleMessage != nil);
        Check(gLaunches.count == 0 && [[self overlay].visibleMessage hasPrefix:@"Couldn't ask"], @"a refused request opens nothing and says so");
    });

    // ---- 8. Nexus through the proposed interface (test double) -----------------------
    STEP(0.4, {
        [HCGNexusPortalInterface setStandInActive:YES];
        [SBLockScreenManager standIn].authMode = PSIAuthSucceed;
        PortalControllerPreviewRelayout();
        [[self overlay] collapseAnimated:NO];
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([[self statusTextOfItem:@"Nexus"] isEqualToString:@""], @"with HCGNexusPortalInterface v1: Nexus available");
        [self tapItemTitled:@"Nexus"];
        WAIT_UNTIL(2, HCGNexusPortalInterface.openCount > 0);
        Check(HCGNexusPortalInterface.openCount == 1 && [HCGNexusPortalInterface.lastSource isEqualToString:@"hcg-portal"],
              @"after authentication Nexus is asked once to open its panel (contract double)");
        [HCGNexusPortalInterface setStandInActive:NO];
    });

    // ---- 9. Coexistence: notifications and media -------------------------------------
    STEP(0.5, {
        [self.coverSheet setNotificationCount:2];
        [self relayout];
        PortalOverlayView *o = [self overlay];
        WAIT_UNTIL(1, NO);
        Check(o.layout.mode == PORTAL_LAYOUT_FULL && [self orbClearOfObstacles], @"two notifications: full size, nothing covered");
        NCNotificationListCell *cell = self.coverSheet.notificationCells.firstObject;
        Check(IsInside([self hit:[cell convertPoint:CGPointMake(100, 30) toView:self.window]], cell), @"notifications keep their touches");
        Check([Status(PortalStatusKeyLayout) containsString:@"NCNotificationListCell×2"], @"notifications measured as obstacles");
        [self state:@"10-notifications" caption:@"Two notifications: the portal stays above them"];
        [self shot:@"10-notifications"];
    });
    STEP(0.4, {
        [self.coverSheet setNotificationCount:4];
        [self.coverSheet setShowsMedia:YES];
        [self relayout];
        WAIT_UNTIL(1, NO);
        PortalOverlayView *o = [self overlay];
        Check(o.layout.mode == PORTAL_LAYOUT_COMPACT,
              [NSString stringWithFormat:@"media + four notifications: compact orb (%s)", portal_layout_mode_name(o.layout.mode)]);
        Check([self orbClearOfObstacles], @"still clear of notifications and media controls");
        CSAdjunctItemView *media = self.coverSheet.mediaView;
        Check(IsInside([self hit:[media convertPoint:CGPointMake(40, 40) toView:self.window]], media), @"media controls keep their touches");
        [self state:@"11-compact" caption:@"Media + notifications: collapsed to a compact orb"];
        [self shot:@"11-compact"];
    });
    STEP(0.4, {
        Check([self tapOrb], @"the compact orb still opens the menu");
        WAIT_UNTIL(1, [self overlay].expanded);
        [self state:@"12-compact-expanded" caption:@"Compact orb: menu opens over the Lock Screen"];
        [self shot:@"12-compact-expanded"];
        [[self overlay] collapseAnimated:NO];
    });
    STEP(0.4, {
        [self.coverSheet setNotificationCount:7];
        [self relayout];
        WAIT_UNTIL(1, NO);
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"no-room"] && [self overlay].hidden,
              @"no room left: hidden, nothing intercepted");
        Check([self overlay].portalView.isPaused, @"hidden: rendering paused");
        [self state:@"13-no-room" caption:@"Notifications fill the screen: the portal steps aside"];
        [self shot:@"13-no-room"];
        [self.coverSheet setNotificationCount:0];
        [self.coverSheet setShowsMedia:NO];
        [self relayout];
    });

    // ---- 10. Reduce Motion / Low Power -------------------------------------------
    STEP(0.4, {
        PortalControllerPreviewSetSystemInputs(1, 0);
        PortalView *v = [self overlay].portalView;
        Check(v.runningAnimationCount == 0 && !v.emitterActive, @"Reduce Motion: static appearance");
        [self state:@"14-reduce-motion" caption:@"Reduce Motion: static"];
        [self shot:@"14-reduce-motion"];
        PortalControllerPreviewSetSystemInputs(0, 1);
        Check(v.runningAnimationCount == 0 && !v.emitterActive, @"Low Power (default): static");
        [self setPrefs:@{PortalKeyLowPower : @"economy"}];
        Check(v.runningAnimationCount >= 4 && !v.emitterActive, @"Low Power economy: slow rings, no particles");
        [self setPrefs:@{PortalKeyLowPower : @"hide"}];
        Check([self overlay].hidden && [Status(PortalStatusKeyVisibility) isEqualToString:@"low-power-hidden"], @"Low Power hide: hidden");
        [self setPrefs:@{PortalKeyLowPower : [NSNull null]}];
        PortalControllerPreviewSetSystemInputs(0, 0);
        Check(v.runningAnimationCount >= 4 && ![self overlay].hidden, @"back to full animation");
    });

    // ---- 11. Appearance and placement --------------------------------------------
    NSArray *palettes = @[ @"aurora", @"solar", @"mono" ];
    for (NSString *palette in palettes) {
        STEP(0.4, {
            [self setPrefs:@{PortalKeyPalette : palette, PortalKeyIntensity : @0.9}];
            WAIT_UNTIL(0.5, NO);
            [self state:[NSString stringWithFormat:@"15-%@", palette] caption:[NSString stringWithFormat:@"Colour: %@", palette]];
            [self shot:[NSString stringWithFormat:@"15-palette-%@", palette]];
        });
    }
    STEP(0.4, {
        [self setPrefs:@{PortalKeyPalette : [NSNull null], PortalKeyIntensity : [NSNull null], PortalKeySize : @170, PortalKeyOffsetY : @70,
                         PortalKeyOffsetX : @-60}];
        [self relayout];
        PortalOverlayView *o = [self overlay];
        Check(o.layout.diameter == 170 && o.layout.cx < self.window.bounds.size.width / 2, @"size and position follow the settings");
        WAIT_UNTIL(0.5, NO);
        [self state:@"16-placement" caption:@"Position & Size: 170 pt, moved left and down"];
        [self shot:@"16-placement"];
        [PortalPreferences removeKeys:[PortalPreferences placementKeys]];
        PortalControllerPreviewReload();
        [self relayout];
        Check([self overlay].layout.diameter == PORTAL_SIZE_DEFAULT, @"Reset Position & Size: back to the defaults");
    });

    // ---- 12. Unlock, Notification Centre, lock again -----------------------------------
    STEP(0.4, {
        PortalView *v = [self overlay].portalView;
        self.window.layer.speed = 0.15f; // slow motion so the screenshot catches the flourish
        [self setLocked:NO];
        WAIT_UNTIL(1, v.flourishPlayed);
        Check(v.flourishPlayed, @"successful unlock: brief opening animation");
        WAIT_UNTIL(0.25, NO);
        [self state:@"17-unlock" caption:@"Unlock: brief opening flourish (slowed for the screenshot)"];
        [self shot:@"17-unlock"];
        self.window.layer.speed = 1;
        // As SpringBoard dismisses the Cover Sheet, then calls the viewDidDisappear: hook:
        // time only Portal's handler.
        [SBCoverSheetPresentationManager standIn].visible = NO;
        self.window.hidden = YES;
        CFTimeInterval t1 = CACurrentMediaTime();
        PortalControllerCoverSheetDidDisappear(self.coverSheet);
        CFTimeInterval dismissal = CACurrentMediaTime() - t1;
        Check(dismissal < 0.05, [NSString stringWithFormat:@"dismissal is never delayed (Portal returned in %.1f ms)", dismissal * 1000]);
        Check([self overlay].hidden && [self overlay].portalView.isPaused, @"after unlock: hidden and paused");
    });
    STEP(0.4, {
        [self showCoverSheet:YES]; // Notification Centre pulled down while unlocked
        WAIT_UNTIL(1, NO);
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"not-lock-screen"] && [self overlay].hidden,
              @"Notification Centre over an unlocked phone: no portal");
        [self showCoverSheet:NO];
        [self setLocked:YES];
        [self showCoverSheet:YES];
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check(![self overlay].hidden, @"locked again: the portal is back");
    });

    // ---- 12b. Lifecycle regression (0.1.0~beta3): repeated lock / wake / unlock with the menu ----
    STEP(0.5, {
        __block int bad = 0;
        NSMutableArray *problems = [NSMutableArray array];
        NSInteger attaches0 = [self counter:@"attaches"], detaches0 = [self counter:@"detaches"];
        BOOL attachedAtStart = [self overlay].superview != nil;
        for (int i = 0; i < 20; i++) {
            [self setLocked:YES];
            [self showCoverSheet:YES];
            [self relayout];
            WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
            if (![Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: not visible (%@)", i, Status(PortalStatusKeyVisibility)]]; }
            if ([self portalViewsInWindow] != 1 || [self overlay].superview != self.coverSheet.mainPageContentViewController.view) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: %lu overlays", i, (unsigned long)[self portalViewsInWindow]]]; }
            if (![self tapOrb]) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: orb not reachable", i]]; }
            WAIT_UNTIL(1, [self overlay].expanded);
            if (![self overlay].expanded) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: menu did not open", i]]; }
            PortalOverlayView *o = [self overlay];
            [o portalHitTest:[o convertPoint:CGPointMake(60, 120) fromView:self.window] touch:YES timestamp:CACurrentMediaTime()];
            WAIT_UNTIL(1, ![self overlay].expanded);
            if ([self overlay].expanded) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: menu did not close", i]]; }
            if (i % 4 == 1) { // display sleeps and wakes on the Lock Screen
                [self tapOrb];
                [self setScreenOn:NO];
                WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"screen-off"]);
                if ([self portalViewsInWindow] != 0 || [self overlay].expanded || PortalControllerPreviewMeasureTimerRunning()) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: screen off left Portal attached/expanded/timed", i]]; }
                [self setScreenOn:YES];
                WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
                if ([self portalViewsInWindow] != 1) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: not back after wake", i]]; }
            }
            if (i % 3 == 2) [self tapOrb]; // unlock with the menu open
            [self setLocked:NO];
            WAIT_UNTIL(0.3, NO);
            [SBCoverSheetPresentationManager standIn].visible = NO;
            self.window.hidden = YES;
            PortalControllerCoverSheetDidDisappear(self.coverSheet);
            if ([self portalViewsInWindow] != 0 || [self overlay].superview != nil || PortalControllerPreviewMeasureTimerRunning()) { bad++; [problems addObject:[NSString stringWithFormat:@"%d: still attached after unlock", i]]; }
            self.window.hidden = NO;
        }
        [self setLocked:YES];
        [self showCoverSheet:YES];
        [self relayout];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        NSInteger attaches = [self counter:@"attaches"] - attaches0, detaches = [self counter:@"detaches"] - detaches0;
        Check(bad == 0, [NSString stringWithFormat:@"20 x lock / wake / menu open-close / unlock: %d problems %@", bad, problems]);
        Check(attaches == detaches + (attachedAtStart ? 0 : 1) && detaches >= 20,
              [NSString stringWithFormat:@"one attach per Lock Screen session, one detach per unlock or sleep (%ld / %ld)", (long)attaches, (long)detaches]);
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"no fault after the cycles");
        Check([Status(PortalStatusKeyPhase) isEqualToString:@"on the Lock Screen"], [NSString stringWithFormat:@"breadcrumb: %@", Status(PortalStatusKeyPhase)]);
        [self state:@"17b-after-cycles" caption:@"After 20 lock / wake / unlock cycles"];
        [self shot:@"17b-after-20-cycles"];
    });
    STEP(0.4, {
        NSInteger updates = [self counter:@"updates"], raises = [self counter:@"raises"];
        for (int i = 0; i < 300; i++) PortalControllerCoverSheetDidLayout(self.coverSheet); // a layout storm
        WAIT_UNTIL(1.0, NO);
        NSInteger delta = [self counter:@"updates"] - updates;
        Check(delta <= 6, [NSString stringWithFormat:@"300 Lock Screen layout passes coalesced into %ld updates", (long)delta]);
        Check([self counter:@"raises"] == raises, @"no hierarchy changes while nothing covers the portal");
        Check([self portalViewsInWindow] == 1, @"still exactly one overlay");
    });
    STEP(0.4, {
        __weak UIView *oldHost = self.coverSheet.mainPageContentViewController.view;
        [self.coverSheet rebuildMainPage];
        [self relayout];
        WAIT_UNTIL(1.5, [self overlay].superview == self.coverSheet.mainPageContentViewController.view);
        Check([self overlay].superview == self.coverSheet.mainPageContentViewController.view && [self portalViewsInWindow] == 1,
              @"SpringBoard rebuilt the main page: Portal moved to the new one, exactly one overlay");
        BOOL leftover = NO;
        for (UIView *v in oldHost.subviews) if ([v isKindOfClass:[PortalOverlayView class]]) leftover = YES;
        Check(!leftover, @"nothing of Portal's left in the old main page");
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"visible"], @"visible again after the rebuild");
    });
    STEP(0.4, {
        self.coverSheet.mainPageAvailable = NO;
        [self relayout];
        WAIT_UNTIL(2.5, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && [Status(PortalStatusKeyVisibility) isEqualToString:@"no-host"],
              [NSString stringWithFormat:@"container unavailable: Portal hidden and detached (%@)", Status(PortalStatusKeyVisibility)]);
        Check([Status(PortalStatusKeyHost) hasPrefix:@"Lock Screen container unavailable"], [NSString stringWithFormat:@"reason: %@", Status(PortalStatusKeyHost)]);
        UIView *camera = self.coverSheet.camera;
        Check([self hit:[camera.superview convertPoint:camera.center toView:self.window]] == camera,
              @"container unavailable: the normal Lock Screen keeps its touches (camera)");
        BOOL foreign = NO;
        for (UIView *v in self.coverSheet.view.subviews) if ([v isKindOfClass:[PortalOverlayView class]]) foreign = YES;
        Check(!foreign, @"no fallback: nothing added to the Cover Sheet's own view");
        [self state:@"17c-no-container" caption:@"Lock Screen container unavailable: Portal hidden, Lock Screen normal"];
        [self shot:@"17c-container-unavailable"];
        self.coverSheet.mainPageAvailable = YES;
        [self relayout];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check([self portalViewsInWindow] == 1, @"container available again: Portal back");
    });
    STEP(0.4, {
        // Arm every delayed callback (idle collapse 12 s, message fade 3.5 s), then tear down.
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self tapItemTitled:@"Devices"];
        PortalOverlayView *detached = [self overlay];
        [self setLocked:NO];
        [SBCoverSheetPresentationManager standIn].visible = NO;
        self.window.hidden = YES;
        PortalControllerCoverSheetDidDisappear(self.coverSheet);
        WAIT_UNTIL(13, NO); // every pending callback fires now
        Check(detached.superview == nil && !detached.expanded && [self portalViewsInWindow] == 0,
              @"callbacks that fire after teardown do nothing (no re-attach, no menu)");
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"no fault from late callbacks");
        self.window.hidden = NO;
        [self setLocked:YES];
        [self showCoverSheet:YES];
        [self relayout];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
    });
    STEP(0.4, {
        NSString *hooks = Status(PortalStatusKeyHooks);
        int bad = 0;
        for (int i = 0; i < 10; i++) {
            [self setPrefs:@{PortalKeyEnabled : @NO}];
            if ([self overlay] != nil || [self portalViewsInWindow] != 0) bad++;
            [self setPrefs:@{PortalKeyEnabled : @YES}];
            [self relayout];
            WAIT_UNTIL(2, [self portalViewsInWindow] == 1);
            if ([self portalViewsInWindow] != 1) bad++;
        }
        Check(bad == 0, [NSString stringWithFormat:@"10 x disable / re-enable on the Lock Screen: %d problems", bad]);
        Check([Status(PortalStatusKeyHooks) isEqualToString:hooks], @"hooks installed once, not again on re-enable");
        // An authentication that finishes after Portal was turned off opens nothing.
        [SBLockScreenManager standIn].authMode = PSIAuthHold;
        [gLaunches removeAllObjects];
        [self tapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self tapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(1, [SBLockScreenManager standIn].hasPendingRequest);
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        [[SBLockScreenManager standIn] resolvePending:YES];
        WAIT_UNTIL(0.5, NO);
        Check(gLaunches.count == 0, @"authentication completing after Portal was turned off opens nothing");
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        [self relayout];
        WAIT_UNTIL(2, [self portalViewsInWindow] == 1);
        [SBLockScreenManager standIn].authMode = PSIAuthSucceed;
    });

    // ---- 13. Recovery ----------------------------------------------------------
    STEP(0.4, {
        CGPoint orb = [self orbCentre];
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        Check([self overlay] == nil, @"Enable off: the portal is removed from the Lock Screen at once");
        Check(![[self hit:orb] isKindOfClass:[UIControl class]], @"Enable off: the touch where the orb was reaches the normal Lock Screen");
        NSUInteger subviews = 0;
        for (UIView *v in self.coverSheet.mainPageContentViewController.view.subviews)
            if ([NSStringFromClass([v class]) hasPrefix:@"Portal"]) subviews++;
        Check(subviews == 0, @"Enable off: no Portal view remains in the hierarchy");
        [self state:@"18-disabled" caption:@"Enable off: normal Lock Screen"];
        [self shot:@"18-disabled"];
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        [self relayout];
        WAIT_UNTIL(1, [self overlay].superview != nil);
        Check([self overlay].superview != nil, @"Enable on: back without a respring");
        PortalControllerPreviewInjectFault();
        Check([self overlay] == nil && [Status(PortalStatusKeyState) isEqualToString:PortalEngineStateFault],
              @"fault fallback: removed, state Fault");
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        [self relayout];
        WAIT_UNTIL(1, [self overlay].superview != nil);
        Check([self overlay].superview != nil && [Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive],
              @"Enable off and on after a fault: recovered");
    });

    // ---- 14. Settings: the real Settings bundle -----------------------------------
    __block UIViewController *settingsRoot = nil;
    STEP(0.5, {
        settingsRoot = [self showSettingsRoot];
        Check([NSStringFromClass([settingsRoot class]) isEqualToString:@"PortalRootListController"], @"principal class PortalRootListController");
        NSArray *specifiers = [settingsRoot valueForKey:@"specifiers"];
        Check(specifiers.count >= 25, [NSString stringWithFormat:@"root page has its rows (%lu specifiers)", (unsigned long)specifiers.count]);
        WAIT_UNTIL(0.8, NO);
        [self state:@"19-settings" caption:@"Settings › HCG Portal"];
        [self shot:@"19-settings-root"];
    });
    STEP(0.5, {
        UIViewController *placement = [[NSClassFromString(@"PortalPlacementController") alloc] init];
        [self.settingsNav pushViewController:placement animated:NO];
        [placement loadViewIfNeeded];
        UISegmentedControl *sample = [placement valueForKey:@"_sample"];
        sample.selectedSegmentIndex = 1;
        [sample sendActionsForControlEvents:UIControlEventValueChanged];
        WAIT_UNTIL(0.8, NO);
        [self state:@"20-position" caption:@"Settings › Position & Size (preview with notifications)"];
        [self shot:@"20-settings-position-size"];
        [self.settingsNav popViewControllerAnimated:NO];
    });
    STEP(0.5, {
        UIViewController *apps = [[NSClassFromString(@"PortalAppsController") alloc] init];
        [self.settingsNav pushViewController:apps animated:NO];
        WAIT_UNTIL(0.8, NO);
        [self state:@"21-apps" caption:@"Settings › HCG Apps"];
        [self shot:@"21-settings-hcg-apps"];
        self.settingsWindow.hidden = YES;
    });

    STEP(0.5, {
        Say(@"PORTAL-PREVIEW-STATUS %@", PortalControllerPreviewStatus());
        Say(@"PORTAL-PREVIEW-DONE failures=%d", gFailures);
    });
#undef STEP
#undef WAIT_UNTIL
}

@end

@interface PortalPreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) PortalPreviewController *controller;
@end

@implementation PortalPreviewAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    PortalPreviewController *c = [[PortalPreviewController alloc] init];
    self.controller = c;
    c.jbroot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"jbroot"];
    [[NSFileManager defaultManager] removeItemAtPath:c.jbroot error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:c.jbroot withIntermediateDirectories:YES attributes:nil error:NULL];
    [PortalCompanions setJailbreakRootForTesting:c.jbroot];

    gLaunchWillAppearIMP = class_getMethodImplementation([CSCoverSheetViewController class], @selector(viewWillAppear:));
    c.coverSheet = [[CSCoverSheetViewController alloc] init];
    [SBLockScreenManager standIn].coverSheetViewController = c.coverSheet;
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = c.coverSheet;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    c.window = window;
    self.window = window;
    [window makeKeyAndVisible];

    c.settingsNav = [[UINavigationController alloc] init];
    c.settingsNav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    c.settingsNav.navigationBar.prefersLargeTitles = NO;
    c.settingsWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    c.settingsWindow.rootViewController = c.settingsNav;
    c.settingsWindow.windowLevel = UIWindowLevelNormal + 10;
    c.settingsWindow.hidden = YES;

    [c setLocked:YES];
    [c setScreenOn:YES];
    [c showCoverSheet:YES];
    c.steps = [NSMutableArray array];
    [c buildScript];
    dispatch_async(dispatch_get_main_queue(), ^{
        [c next];
    });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:@"shot-ack"] error:NULL];
        // Fresh preferences: the package's defaults (off), plus three chosen apps.
        CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)PortalPreferencesDomain, kCFPreferencesCurrentUser,
                                                   kCFPreferencesAnyHost);
        if (keys) {
            CFPreferencesSetMultiple(NULL, keys, (__bridge CFStringRef)PortalPreferencesDomain, kCFPreferencesCurrentUser,
                                     kCFPreferencesAnyHost);
            CFRelease(keys);
        }
        NSArray *apps = @[
            @{@"id" : @"com.hakmicapitalgroup.hcgterminal", @"name" : @"HCG Terminal"},
            @{@"id" : @"com.hakmicapitalgroup.hcgnews", @"name" : @"HCG News"},
            @{@"id" : @"com.hakmicapitalgroup.sentinel", @"name" : @"HCG Sentinel"},
        ];
        CFPreferencesSetAppValue((__bridge CFStringRef)PortalKeyApps, (__bridge CFPropertyListRef)apps,
                                 (__bridge CFStringRef)PortalPreferencesDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)PortalPreferencesDomain);
        [PortalPreferences setConsecutiveUnstableLaunches:0];
        gLaunches = [NSMutableArray array];
        [PortalLauncher setPreviewInstalledHandler:^BOOL(NSString *bundle) {
            return YES;
        }];
        [PortalLauncher setPreviewLaunchHandler:^BOOL(NSString *bundle) {
            [gLaunches addObject:bundle];
            Say(@"PORTAL-PREVIEW-LAUNCH %@", bundle);
            return YES;
        }];
        Say(@"PORTAL-PREVIEW-START HCG Portal %s", PORTAL_VERSION);
        // No explicit bootstrap: the REAL src/Tweak.m constructor queued it on the main queue
        // when this executable loaded, exactly as in SpringBoard. The hook API starts out
        // unavailable (PortalPreviewSetHookAPI not called yet), as in a SpringBoard without ElleKit.
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PortalPreviewAppDelegate class]));
    }
}
