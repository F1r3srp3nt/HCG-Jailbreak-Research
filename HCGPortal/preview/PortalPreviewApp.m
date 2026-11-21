//
//  PortalPreviewApp.m
//  HCG Portal — PREVIEW and integration run (iOS Simulator only).
//
//  Built by scripts/preview.sh. One app plays two roles:
//
//  1. A stand-in Cover Sheet running the REAL tweak code (PortalController,
//     PortalHost, PortalOverlayView, PortalView, PortalLauncher,
//     PortalCompanions) the way SpringBoard would: a CSCoverSheetViewController
//     stand-in with a clock, widgets, notifications, a media platter and the
//     flashlight / camera buttons, its main page inside a scroll view that
//     carries SpringBoard-like tap and long-press recognizers (iOS 17.0.3
//     headers); lock state as SpringBoard reports it (Darwin lock state,
//     -isUILocked, the keybag through a preview override); screen state as
//     Darwin notifications (preview names). The three Cover Sheet hooks are
//     called by this harness exactly where Tweak.m calls them.
//
//  2. Settings: loads the REAL HCGPortalPrefs.bundle (compiled for the
//     Simulator) with Preferences.framework from the Simulator runtime and
//     shows the root page, Position & Size and HCG Apps.
//
//  Touches (0.1.0~beta4): "finger" steps inject real UITouch / UIEvent objects
//  through -[UIApplication sendEvent:] (preview/PortalTouchSynth.m), so UIKit's
//  hit-testing, gesture arbitration and scroll-view delays decide, as for a
//  finger on the Simulator. Other steps activate controls the way VoiceOver
//  does. Face ID, Touch ID and the passcode are never simulated: Portal only
//  sees the lock state iOS reports afterwards, which is identical for all
//  three, so the device rows cover each method.
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
#import "PortalTouchSynth.h"
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

/// Counts a gesture recognizer's recognitions (touch-path experiments).
@interface PTSRecorder : NSObject
@property (nonatomic) NSInteger count;
- (void)fire:(UIGestureRecognizer *)recognizer;
@end
@implementation PTSRecorder
- (void)fire:(UIGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateBegan) self.count++;
}
@end

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
    return [v accessibilityActivate];
}

#pragma mark Phone state, as SpringBoard reports it to Portal

/// The iPhone locks: lock state and UI lock set, the Cover Sheet comes back as the Lock Screen.
- (void)lockPhone {
    [self setLocked:YES];
    [self showCoverSheet:YES];
    [self relayout];
}

/// A successful Face ID, Touch ID or passcode unlock, as Portal sees it: lock state 0,
/// -isUILocked NO, keybag unlocked, and the Lock Screen dismissed. Portal cannot tell the
/// three methods apart (it never sees them), so one transition stands for all three here.
- (void)unlockPhone {
    [self setLocked:NO];
    [self showCoverSheet:NO];
}

/// The Cover Sheet pulled down over the unlocked iPhone.
- (void)pullDownCoverSheet {
    [self showCoverSheet:YES];
    [self relayout];
}

#pragma mark Finger taps (synthesised touches through UIKit)

- (BOOL)fingerTap:(CGPoint)windowPoint hold:(NSTimeInterval)hold {
    return PTSTap(self.window, windowPoint, hold);
}

- (BOOL)fingerTapOrb {
    if (![self overlay].superview) return NO;
    return PTSTap(self.window, [self orbCentre], 0.08);
}

- (BOOL)fingerTapItemTitled:(NSString *)title {
    PortalOverlayView *o = [self overlay];
    for (NSUInteger i = 0; i < o.currentItems.count && i < o.itemControls.count; i++) {
        if (![o.currentItems[i].title isEqualToString:title]) continue;
        UIControl *c = o.itemControls[i];
        return PTSTap(self.window, [c convertPoint:CGPointMake(CGRectGetMidX(c.bounds), CGRectGetMidY(c.bounds)) toView:self.window], 0.08);
    }
    return NO;
}

/// A point on the Cover Sheet that belongs to nothing (no Portal, no notification, no button).
- (CGPoint)emptyPoint {
    CGPoint orb = [self orbCentre];
    return CGPointMake(24, orb.y > 0 ? orb.y : 420);
}

- (NSInteger)touchStat:(NSString *)key {
    return [PortalOverlayTouchDiagnostics()[key] integerValue];
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
        return [c accessibilityActivate];
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

    // ---- T0. Touch-path experiment (0.1.0~beta4 diagnosis; reported as notes) -------------
    // iOS 17.0.3 headers: CSCoverSheetView installs SpringBoard's own recognizers ON ITS SCROLL VIEW
    // (-_setupBackgroundContentGestureOnScrollView:, -_setupQuickNoteGestureOnScrollView:, … ;
    // UITapGestureRecognizer *backgroundContentGestureRecognizer, *quickNoteGestureRecognizer;
    // UILongPressGestureRecognizer *complicationGestureRecognizer), i.e. on an ancestor of Portal's
    // overlay. Question: does a plain UIControl (how 0.1.0~beta1–3 build the orb and the items)
    // still receive its tap inside such a scroll view?
    STEP(0.5, {
        NSString *why = nil;
        BOOL synth = PTSAvailable(&why);
        Say(@"PORTAL-PREVIEW-NOTE T0 touch synthesis: %@", synth ? @"available" : why);
        if (synth) {
            UIWindow *w = [[UIWindow alloc] initWithWindowScene:self.window.windowScene];
            w.frame = self.window.bounds;
            w.windowLevel = UIWindowLevelAlert + 20;
            w.backgroundColor = UIColor.blackColor;
            w.rootViewController = [[UIViewController alloc] init];
            w.hidden = NO;
            UIView *root = w.rootViewController.view;
            root.frame = w.bounds;
            __block NSInteger calButton = 0, calControl = 0, control = 0, button = 0;
            UIButton *b0 = [UIButton buttonWithType:UIButtonTypeSystem primaryAction:[UIAction actionWithHandler:^(UIAction *a) { calButton++; }]];
            b0.frame = CGRectMake(20, 80, 120, 60);
            [root addSubview:b0];
            UIControl *c0 = [[UIControl alloc] initWithFrame:CGRectMake(180, 80, 120, 60)];
            c0.backgroundColor = UIColor.darkGrayColor;
            [c0 addAction:[UIAction actionWithHandler:^(UIAction *a) { calControl++; }] forControlEvents:UIControlEventTouchUpInside];
            [root addSubview:c0];

            UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 200, w.bounds.size.width, w.bounds.size.height - 200)];
            scroll.contentSize = scroll.bounds.size;
            scroll.alwaysBounceVertical = YES; // as the Cover Sheet's list area
            [root addSubview:scroll];
            PTSRecorder *tapRec = [PTSRecorder new], *pressRec = [PTSRecorder new];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:tapRec action:@selector(fire:)];
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:pressRec action:@selector(fire:)];
            [scroll addGestureRecognizer:tap];
            [scroll addGestureRecognizer:press];
            UIView *page = [[UIView alloc] initWithFrame:scroll.bounds];
            [scroll addSubview:page];
            UIControl *c1 = [[UIControl alloc] initWithFrame:CGRectMake(40, 40, 120, 120)];
            c1.backgroundColor = UIColor.purpleColor;
            [c1 addAction:[UIAction actionWithHandler:^(UIAction *a) { control++; }] forControlEvents:UIControlEventTouchUpInside];
            [page addSubview:c1];
            UIButton *b1 = [UIButton buttonWithType:UIButtonTypeSystem primaryAction:[UIAction actionWithHandler:^(UIAction *a) { button++; }]];
            b1.frame = CGRectMake(200, 40, 120, 120);
            [page addSubview:b1];
            WAIT_UNTIL(0.3, NO);

            PTSTap(w, [b0 convertPoint:CGPointMake(60, 30) toView:w], 0.08);
            PTSTap(w, [c0 convertPoint:CGPointMake(60, 30) toView:w], 0.08);
            Say(@"PORTAL-PREVIEW-NOTE T0 calibration (no recognizers): UIButton %ld, plain UIControl %ld (1 each = synthesis delivers taps)",
                (long)calButton, (long)calControl);
            NSInteger t0 = tapRec.count;
            PTSTap(w, [c1 convertPoint:CGPointMake(60, 60) toView:w], 0.08);
            Say(@"PORTAL-PREVIEW-NOTE T0 plain UIControl inside a scroll view with a tap recognizer: control %ld, scroll-view tap %ld",
                (long)control, (long)(tapRec.count - t0));
            t0 = tapRec.count;
            PTSTap(w, [b1 convertPoint:CGPointMake(60, 60) toView:w], 0.08);
            Say(@"PORTAL-PREVIEW-NOTE T0 UIButton inside the same scroll view: button %ld, scroll-view tap %ld", (long)button, (long)(tapRec.count - t0));
            t0 = tapRec.count;
            PTSTap(w, [page convertPoint:CGPointMake(100, 300) toView:w], 0.08);
            Say(@"PORTAL-PREVIEW-NOTE T0 empty area of the scroll view: scroll-view tap %ld", (long)(tapRec.count - t0));
            NSInteger p0 = pressRec.count, c1Before = control;
            PTSTap(w, [c1 convertPoint:CGPointMake(60, 60) toView:w], 0.9);
            Say(@"PORTAL-PREVIEW-NOTE T0 long press on the plain UIControl: control %ld, long-press recognizer %ld",
                (long)(control - c1Before), (long)(pressRec.count - p0));
            w.hidden = YES;
            [self.window makeKeyAndVisible];
        }
    });

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

    // ---- 1. Enabled on the LOCKED Lock Screen: nothing of Portal exists ------------------------
    STEP(0.5, {
        [SBCoverSheetPresentationManager standIn].dismissHandler = ^{
            PortalPreviewController *strongSelf = weakSelf;
            strongSelf.window.hidden = YES;
            PortalControllerCoverSheetDidDisappear(strongSelf.coverSheet); // as the viewDidDisappear: hook does
        };
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        [self lockPhone];
        WAIT_UNTIL(1.5, [Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive]);
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"enabled: engine active");
        Check([self portalViewsInWindow] == 0 && [self overlay].superview == nil,
              @"locked Lock Screen: no Portal view anywhere in the window");
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"locked"],
              [NSString stringWithFormat:@"locked Lock Screen: visibility 'locked' (%@)", Status(PortalStatusKeyVisibility)]);
        Check([Status(PortalStatusKeyAccess) hasPrefix:@"locked"],
              [NSString stringWithFormat:@"access read from iOS: %@", Status(PortalStatusKeyAccess)]);
        BOOL portalElement = NO;
        for (id e in self.coverSheet.view.accessibilityElements ?: @[])
            if ([NSStringFromClass([e class]) hasPrefix:@"Portal"]) portalElement = YES;
        Check(!portalElement, @"locked: no Portal accessibility element");
        NSInteger bg = self.coverSheet.scrollView.backgroundTaps;
        NSString *why = nil;
        Check(PTSAvailable(&why), [NSString stringWithFormat:@"finger taps can be synthesised on this Simulator (%@)", why ?: @"yes"]);
        [self fingerTap:CGPointMake(self.window.bounds.size.width / 2, 420) hold:0.08];
        Check(self.coverSheet.scrollView.backgroundTaps == bg + 1 && gLaunches.count == 0,
              @"locked: a finger where the portal would be reaches the normal Lock Screen; nothing opens");
        // Face ID matched but the Lock Screen is still up: iOS still reports the UI locked.
        PSIPostState(PORTAL_LOCKSTATE_NOTIFICATION, 1);
        WAIT_UNTIL(0.4, NO);
        Check([self portalViewsInWindow] == 0, @"authenticated but still on the Lock Screen: nothing shown until iOS unlocks");
        [self state:@"01-locked" caption:@"Locked Lock Screen: HCG Portal is not there at all"];
        [self shot:@"01-locked"];
    });

    // ---- 2. After a reboot, before the first unlock (keybag locked) ---------------------------
    STEP(0.4, {
        PortalControllerPreviewSetProtectedData(0);
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(0.6, NO);
        Check([self portalViewsInWindow] == 0 && [Status(PortalStatusKeyAccess) hasPrefix:@"locked"] &&
                  [Status(PortalStatusKeyAccess) containsString:@"protected data unavailable"],
              [NSString stringWithFormat:@"keybag locked (before the first unlock): closed, whatever else says (%@)",
                                         Status(PortalStatusKeyAccess)]);
        PortalControllerPreviewSetProtectedData(-1);
        [self lockPhone];
    });

    // ---- 3. Unlock (Face ID / Touch ID / passcode), pull down the Cover Sheet -----------------
    STEP(0.5, {
        [self unlockPhone];
        WAIT_UNTIL(0.5, NO);
        Check([self portalViewsInWindow] == 0, @"unlocked, Cover Sheet dismissed: no portal (it lives on the Cover Sheet)");
        self.window.layer.speed = 0.15f; // slow motion so the screenshot can catch the opening flourish
        [self pullDownCoverSheet];
        WAIT_UNTIL(3, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        PortalOverlayView *o = [self overlay];
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"visible"] && [Status(PortalStatusKeyAccess) hasPrefix:@"unlocked"],
              [NSString stringWithFormat:@"unlocked: the portal appears on the pulled-down Cover Sheet (%@; %@)",
                                         Status(PortalStatusKeyVisibility), Status(PortalStatusKeyAccess)]);
        Check(o.superview == self.coverSheet.mainPageContentViewController.view && [self portalViewsInWindow] == 1,
              @"hosted once, in the Cover Sheet's main page");
        Check(o.portalView.flourishPlayed, @"first appearance after the unlock: brief opening animation");
        WAIT_UNTIL(0.3, NO);
        [self state:@"02-unlock-flourish" caption:@"Unlocked: the portal opens on the Cover Sheet (slowed)"];
        [self shot:@"02-unlock-flourish"];
        self.window.layer.speed = 1;
        Check(o.layout.mode == PORTAL_LAYOUT_FULL && o.layout.diameter == PORTAL_SIZE_DEFAULT, @"full size by default (132 pt)");
        CGRect orb = [o convertRect:o.orbFrame toView:self.window];
        CGFloat widgetsBottom = CGRectGetMaxY([self.coverSheet.complicationContainerViewController.view
            convertRect:self.coverSheet.complicationContainerViewController.view.bounds toView:self.window]);
        Check(CGRectGetMinY(orb) >= widgetsBottom, @"below the clock and widgets");
        Check(CGRectGetMaxY(orb) <= CGRectGetMinY(self.coverSheet.flashlight.frame), @"above the flashlight and camera");
        Check(!IsInside([self hit:CGPointMake(self.window.bounds.size.width / 2, 140)], o), @"the clock area is not intercepted");
        Check(!IsInside([self hit:CGPointMake(self.window.bounds.size.width / 2, self.window.bounds.size.height - 10)], o),
              @"the home-gesture area is not intercepted");
        Check([self hit:self.coverSheet.camera.center] == self.coverSheet.camera &&
                  [self hit:self.coverSheet.flashlight.center] == self.coverSheet.flashlight,
              @"flashlight and camera keep their touches");
        WAIT_UNTIL(1.0, NO);
        Check(o.portalView.runningAnimationCount >= 4 && !o.portalView.isPaused, @"idle: slow rotating rings");
        [self state:@"03-idle" caption:@"Unlocked, Cover Sheet pulled down: idle portal"];
        [self shot:@"03-idle"];
    });

    // ---- 4. FINGERS: the fix for "renders but does not respond" ------------------------------
    STEP(0.5, {
        CSScrollView *scroll = self.coverSheet.scrollView;
        NSInteger bg = scroll.backgroundTaps, taps = [self touchStat:@"taps"];
        Check([self fingerTapOrb], @"finger tap on the orb delivered through UIKit");
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self overlay].expanded, [NSString stringWithFormat:@"finger tap on the orb opens the radial menu, despite SpringBoard's "
                                                                  @"tap recognizer on the scroll view above it (touches: %@)",
                                                                  Status(PortalStatusKeyTouch)]);
        Check(scroll.backgroundTaps == bg, @"SpringBoard's background tap did not also fire for a tap on the orb");
        Check([self touchStat:@"taps"] == taps + 1, @"Portal's own tap recognizer recognized it");
        NSArray *titles = [[self overlay].currentItems valueForKey:@"title"];
        Check([titles isEqualToArray:@[ @"Nexus", @"Backgrounds", @"Devices", @"HCG Apps" ]], @"Nexus, Backgrounds, Devices, HCG Apps");
        WAIT_UNTIL(0.6, NO);
        [self state:@"04-menu" caption:@"Finger tap: radial menu"];
        [self shot:@"04-menu"];
    });
    STEP(0.4, {
        CSScrollView *scroll = self.coverSheet.scrollView;
        Check([self fingerTapItemTitled:@"Devices"], @"finger tap on Devices delivered");
        WAIT_UNTIL(1, [self overlay].visibleMessage != nil);
        Check([[self overlay].visibleMessage hasPrefix:@"Not connected."], @"finger tap on Devices: Not connected");
        Check([self fingerTapItemTitled:@"Nexus"], @"finger tap on Nexus delivered");
        WAIT_UNTIL(0.5, [[self overlay].visibleMessage hasPrefix:@"HCG Nexus"]);
        Check([[self overlay].visibleMessage isEqualToString:@"HCG Nexus isn't installed."], @"finger tap on Nexus: not installed");
        Check(gLaunches.count == 0 && [SBCoverSheetPresentationManager standIn].dismissRequests == 0,
              @"unavailable destinations open nothing and leave the Cover Sheet alone");
        NSInteger bg = scroll.backgroundTaps;
        CGPoint empty = [self emptyPoint];
        Check(!IsInside([self hit:empty], [self overlay]), @"tap outside: the point is not Portal's");
        [self fingerTap:empty hold:0.08];
        WAIT_UNTIL(1.5, ![self overlay].expanded);
        Check(![self overlay].expanded, @"finger tap outside: the menu closes");
        Check(scroll.backgroundTaps == bg + 1, @"the same tap still reached SpringBoard's own background gesture");
        NSInteger presses = scroll.longPresses;
        [self fingerTap:[self orbCentre] hold:0.9];
        WAIT_UNTIL(0.4, NO);
        Check(scroll.longPresses == presses + 1, @"a long press on the orb still reaches SpringBoard (poster switcher): not held back");
        if ([self overlay].expanded) [[self overlay] collapseAnimated:NO];
        BOOL wasExpanded = [self overlay].expanded;
        PTSDrag(self.window, [self orbCentre], CGPointMake([self orbCentre].x, [self orbCentre].y - 160), 12);
        WAIT_UNTIL(0.5, NO);
        Check([self overlay].expanded == wasExpanded, @"a swipe that starts on the orb is a swipe, not a tap");
        [self.coverSheet.scrollView setContentOffset:CGPointZero animated:NO];
        [self state:@"05-not-connected" caption:@"Devices: Not connected"];
    });

    // ---- 5. Companions installed ----------------------------------------------------------
    STEP(0.4, {
        [self installCompanion:@"Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle/Info.plist"];
        [self installCompanion:@"Library/PreferenceLoader/Preferences/HCGAnimationCenterPrefs.plist"];
        [self installCompanion:@"Library/PreferenceBundles/HCGNexusPrefs.bundle/Info.plist"];
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([[self statusTextOfItem:@"Nexus"] isEqualToString:@"Update needed"], @"Nexus installed without the interface: Update needed");
        Check([[self statusTextOfItem:@"Backgrounds"] isEqualToString:@""], @"Animation Center installed: Backgrounds available");
        WAIT_UNTIL(0.5, NO);
        [self state:@"06-companions" caption:@"Animation Center installed; HCG Nexus lacks the open interface"];
        [self shot:@"06-companions"];
    });

    // ---- 6. Backgrounds: the Cover Sheet closes, then Settings opens, once --------------------
    STEP(0.4, {
        SBCoverSheetPresentationManager *pm = [SBCoverSheetPresentationManager standIn];
        NSUInteger dismissals = pm.dismissRequests;
        [gLaunches removeAllObjects];
        Check([self fingerTapItemTitled:@"Backgrounds"], @"finger tap on Backgrounds delivered");
        WAIT_UNTIL(2, gLaunches.count > 0);
        Check(pm.dismissRequests == dismissals + 1, @"Backgrounds: the Cover Sheet is closed first (as a swipe up)");
        Check(gLaunches.count == 1 && [gLaunches[0] isEqualToString:@"com.apple.Preferences"],
              @"then exactly Settings (for HCG Animation Center) opens, once");
        WAIT_UNTIL(1, [Status(PortalStatusKeyLastAction) containsString:@"opened"]);
        Check([Status(PortalStatusKeyLastAction) containsString:@"opened"], @"last action recorded");
        Check([self portalViewsInWindow] == 0, @"Cover Sheet closed: Portal left with it");
        Check([SBLockScreenManager standIn].requestCount == 0, @"no authentication request: iOS had already unlocked");
    });

    // ---- 7. HCG Apps ring; an app opens ----------------------------------------------------
    STEP(0.4, {
        [gLaunches removeAllObjects];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self fingerTapItemTitled:@"HCG Apps"], @"finger tap on HCG Apps delivered");
        WAIT_UNTIL(1, [[self overlay].ringName isEqualToString:@"apps"]);
        Check([[self overlay].ringName isEqualToString:@"apps"] && [self overlay].itemControls.count == 3 && gLaunches.count == 0,
              @"app ring: the three chosen apps; showing it opens nothing");
        WAIT_UNTIL(0.6, NO);
        [self state:@"07-apps-ring" caption:@"HCG Apps: user-selected shortcuts"];
        [self shot:@"07-apps-ring"];
        Check([self fingerTapItemTitled:@"HCG Terminal"], @"finger tap on an app delivered");
        WAIT_UNTIL(2, gLaunches.count > 0);
        Check(gLaunches.count == 1 && [gLaunches[0] isEqualToString:@"com.hakmicapitalgroup.hcgterminal"],
              @"exactly that app opened, once");
    });

    // ---- 8. Relocked while a destination is opening: nothing runs -----------------------------
    STEP(0.4, {
        SBCoverSheetPresentationManager *pm = [SBCoverSheetPresentationManager standIn];
        [gLaunches removeAllObjects];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        pm.holdsDismissal = YES;
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self fingerTapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"opening"]);
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"opening"], @"selected: waiting for the Cover Sheet to close");
        [self lockPhone]; // the side button, before the Cover Sheet finished closing
        WAIT_UNTIL(1, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && [Status(PortalStatusKeyVisibility) isEqualToString:@"locked"],
              @"locked mid-opening: Portal removed at once");
        [pm finishDismissal];
        WAIT_UNTIL(0.6, NO);
        Check(gLaunches.count == 0, @"the queued action never runs after the lock");
        Check([Status(PortalStatusKeyLastAction) containsString:@"locked"], [NSString stringWithFormat:@"and says why (%@)", Status(PortalStatusKeyLastAction)]);

        // Lock and unlock again before the Cover Sheet finished closing: still nothing.
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self fingerTapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(1, [Status(PortalStatusKeyVisibility) isEqualToString:@"opening"]);
        [self setLocked:YES];
        WAIT_UNTIL(0.3, NO);
        [self setLocked:NO];
        WAIT_UNTIL(0.3, NO);
        [pm finishDismissal];
        WAIT_UNTIL(0.6, NO);
        Check(gLaunches.count == 0, @"rapid lock then unlock while opening: the old action is still discarded (new access epoch)");
        pm.holdsDismissal = NO;
    });

    // ---- 9. Relocked with the menu open; screen off --------------------------------------------
    STEP(0.4, {
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        NSInteger revocations = [self counter:@"accessRevocations"];
        [self lockPhone];
        WAIT_UNTIL(1, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && ![self overlay].expanded && [self counter:@"accessRevocations"] == revocations + 1,
              @"locked with the menu open: menu and portal gone at once");
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check(![self overlay].expanded && [self portalViewsInWindow] == 1, @"unlocked again: a fresh, closed portal");
        [self setScreenOn:NO];
        WAIT_UNTIL(1, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && !PortalControllerPreviewMeasureTimerRunning(), @"screen off: removed, no timers");
        [self setScreenOn:YES];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check([self portalViewsInWindow] == 1, @"screen on, still unlocked: back");
    });

    // ---- 10. Fail closed: a source iOS should provide is missing; the camera over the Lock Screen
    STEP(0.4, {
        [SBLockScreenManager standIn].uiLockedUnavailable = YES;
        [self relayout];
        WAIT_UNTIL(1, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && [Status(PortalStatusKeyAccess) hasPrefix:@"unverified"],
              [NSString stringWithFormat:@"-isUILocked unavailable: closed although unlocked (%@)", Status(PortalStatusKeyAccess)]);
        [SBLockScreenManager standIn].uiLockedUnavailable = NO;
        [SBCoverSheetPresentationManager standIn].inSecureApp = YES;
        [self relayout];
        WAIT_UNTIL(1, NO);
        Check([self portalViewsInWindow] == 0, @"secure app (camera over the Lock Screen): closed");
        [SBCoverSheetPresentationManager standIn].inSecureApp = NO;
        [self relayout];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check([self portalViewsInWindow] == 1, @"sources back: open again");
    });

    // ---- 11. HCG Animation Center present (its Cover Sheet view) and absent --------------------
    STEP(0.4, {
        // HCG Animation Center 0.1.0~beta1 (commit 2d642bd, HACHosts.m / HCGBackgroundView.m) puts a
        // non-interactive background view at index 0 of the Cover Sheet window (hitTest: nil,
        // pointInside: NO, userInteractionEnabled NO). This is that behaviour, not its code.
        UIView *ac = [[UIView alloc] initWithFrame:self.window.bounds];
        ac.userInteractionEnabled = NO;
        ac.backgroundColor = [UIColor colorWithRed:0.2 green:0.05 blue:0.3 alpha:0.35];
        [self.window insertSubview:ac atIndex:0];
        NSInteger bg = self.coverSheet.scrollView.backgroundTaps;
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self overlay].expanded && self.coverSheet.scrollView.backgroundTaps == bg,
              @"with Animation Center's background view: the finger still reaches Portal");
        [[self overlay] collapseAnimated:NO];
        [self lockPhone];
        WAIT_UNTIL(1, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0, @"with Animation Center: locking still removes Portal (it has no say in access)");
        [ac removeFromSuperview];
        [[NSFileManager defaultManager] removeItemAtPath:[self.jbroot stringByAppendingPathComponent:@"Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle"]
                                                   error:NULL];
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([[self statusTextOfItem:@"Backgrounds"] isEqualToString:@"Not installed"] && [self overlay].expanded,
              @"Animation Center absent: Portal works; Backgrounds says Not installed");
        [self fingerTapItemTitled:@"Backgrounds"];
        WAIT_UNTIL(0.5, NO);
        Check(gLaunches.count == 0 && [[self overlay].visibleMessage containsString:@"Animation Center isn't installed"],
              @"Animation Center absent: Backgrounds opens nothing and says why");
        [[self overlay] collapseAnimated:NO];
        [self installCompanion:@"Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle/Info.plist"];
    });

    // ---- 12. Coexistence: notifications and media (unlocked Cover Sheet) ----------------------
    STEP(0.5, {
        [self.coverSheet setNotificationCount:2];
        [self relayout];
        PortalOverlayView *o = [self overlay];
        WAIT_UNTIL(1, NO);
        Check(o.layout.mode == PORTAL_LAYOUT_FULL && [self orbClearOfObstacles], @"two notifications: full size, nothing covered");
        NCNotificationListCell *cell = self.coverSheet.notificationCells.firstObject;
        Check(IsInside([self hit:[cell convertPoint:CGPointMake(100, 30) toView:self.window]], cell), @"notifications keep their touches");
        [self state:@"08-notifications" caption:@"Two notifications: the portal stays above them"];
        [self shot:@"08-notifications"];
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
        Check([self fingerTapOrb], @"finger tap on the compact orb delivered");
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self overlay].expanded, @"the compact orb opens the menu with a finger");
        [self state:@"09-compact-expanded" caption:@"Compact orb: menu opens"];
        [self shot:@"09-compact-expanded"];
        [[self overlay] collapseAnimated:NO];
    });
    STEP(0.4, {
        [self.coverSheet setNotificationCount:7];
        [self relayout];
        WAIT_UNTIL(1, NO);
        Check([Status(PortalStatusKeyVisibility) isEqualToString:@"no-room"] && [self overlay].hidden,
              @"no room left: hidden, nothing intercepted");
        [self.coverSheet setNotificationCount:0];
        [self.coverSheet setShowsMedia:NO];
        [self relayout];
    });

    // ---- 13. Reduce Motion / Low Power; appearance and placement --------------------------------
    STEP(0.4, {
        PortalControllerPreviewSetSystemInputs(1, 0);
        PortalView *v = [self overlay].portalView;
        Check(v.runningAnimationCount == 0 && !v.emitterActive, @"Reduce Motion: static appearance");
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
    NSArray *palettes = @[ @"aurora", @"solar", @"mono" ];
    for (NSString *palette in palettes) {
        STEP(0.4, {
            [self setPrefs:@{PortalKeyPalette : palette, PortalKeyIntensity : @0.9}];
            WAIT_UNTIL(0.5, NO);
            [self state:[NSString stringWithFormat:@"10-%@", palette] caption:[NSString stringWithFormat:@"Colour: %@", palette]];
            [self shot:[NSString stringWithFormat:@"10-palette-%@", palette]];
        });
    }
    STEP(0.4, {
        [self setPrefs:@{PortalKeyPalette : [NSNull null], PortalKeyIntensity : [NSNull null], PortalKeySize : @170, PortalKeyOffsetY : @70,
                         PortalKeyOffsetX : @-60}];
        [self relayout];
        PortalOverlayView *o = [self overlay];
        Check(o.layout.diameter == 170 && o.layout.cx < self.window.bounds.size.width / 2, @"size and position follow the settings");
        [PortalPreferences removeKeys:[PortalPreferences placementKeys]];
        PortalControllerPreviewReload();
        [self relayout];
        Check([self overlay].layout.diameter == PORTAL_SIZE_DEFAULT, @"Reset Position & Size: back to the defaults");
    });

    // ---- 14. Lifecycle: 20 lock / wake / unlock / pull down / finger menu cycles ------------------
    STEP(0.5, {
        NSMutableArray *problems = [NSMutableArray array];
        for (int i = 0; i < 20; i++) {
            [self lockPhone];
            WAIT_UNTIL(0.6, [self portalViewsInWindow] == 0);
            if ([self portalViewsInWindow] != 0) [problems addObject:[NSString stringWithFormat:@"%d: shown while locked", i]];
            if (i % 4 == 1) {
                [self setScreenOn:NO];
                WAIT_UNTIL(0.2, NO);
                [self setScreenOn:YES];
                WAIT_UNTIL(0.3, NO);
                if ([self portalViewsInWindow] != 0) [problems addObject:[NSString stringWithFormat:@"%d: shown after waking locked", i]];
            }
            [self unlockPhone];
            [self pullDownCoverSheet];
            WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
            if ([self portalViewsInWindow] != 1) {
                [problems addObject:[NSString stringWithFormat:@"%d: %lu overlays when unlocked", i, (unsigned long)[self portalViewsInWindow]]];
                continue;
            }
            [self fingerTapOrb];
            WAIT_UNTIL(1, [self overlay].expanded);
            if (![self overlay].expanded) [problems addObject:[NSString stringWithFormat:@"%d: finger did not open the menu", i]];
            if (i % 3 == 2) continue; // lock with the menu still open
            [self fingerTap:[self emptyPoint] hold:0.06];
            WAIT_UNTIL(1, ![self overlay].expanded);
            if ([self overlay].expanded) [problems addObject:[NSString stringWithFormat:@"%d: menu did not close", i]];
            [self showCoverSheet:NO];
            if ([self portalViewsInWindow] != 0 || PortalControllerPreviewMeasureTimerRunning())
                [problems addObject:[NSString stringWithFormat:@"%d: left behind after closing the Cover Sheet", i]];
        }
        Check(problems.count == 0, [NSString stringWithFormat:@"20 cycles of lock / wake / unlock / finger menu: %lu problems %@",
                                                              (unsigned long)problems.count, problems]);
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"no fault after the cycles");
        Check(gLaunches.count == 0, @"nothing opened during the cycles");
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
    });
    STEP(0.4, {
        NSInteger updates = [self counter:@"updates"];
        for (int i = 0; i < 300; i++) PortalControllerCoverSheetDidLayout(self.coverSheet); // a layout storm
        WAIT_UNTIL(1.0, NO);
        NSInteger delta = [self counter:@"updates"] - updates;
        Check(delta <= 6, [NSString stringWithFormat:@"300 Cover Sheet layout passes coalesced into %ld updates", (long)delta]);
        Check([self portalViewsInWindow] == 1, @"still exactly one overlay");
        [self.coverSheet rebuildMainPage];
        [self relayout];
        WAIT_UNTIL(1.5, [self overlay].superview == self.coverSheet.mainPageContentViewController.view);
        Check([self overlay].superview == self.coverSheet.mainPageContentViewController.view && [self portalViewsInWindow] == 1,
              @"SpringBoard rebuilt the main page: Portal moved to the new one, exactly one overlay");
        Check([self fingerTapOrb], @"finger tap after the rebuild delivered");
        WAIT_UNTIL(1, [self overlay].expanded);
        Check([self overlay].expanded, @"the rebuilt page's portal still responds to a finger");
        [[self overlay] collapseAnimated:NO];
    });
    STEP(0.4, {
        self.coverSheet.mainPageAvailable = NO;
        [self relayout];
        WAIT_UNTIL(2.5, [self portalViewsInWindow] == 0);
        Check([self portalViewsInWindow] == 0 && [Status(PortalStatusKeyHost) hasPrefix:@"Lock Screen container unavailable"],
              [NSString stringWithFormat:@"container unavailable: hidden, reason given (%@)", Status(PortalStatusKeyHost)]);
        BOOL foreign = NO;
        for (UIView *v in self.coverSheet.view.subviews)
            if ([v isKindOfClass:[PortalOverlayView class]]) foreign = YES;
        Check(!foreign, @"no fallback: nothing added to the Cover Sheet's own view");
        self.coverSheet.mainPageAvailable = YES;
        [self relayout];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check([self portalViewsInWindow] == 1, @"container available again: Portal back");
    });
    STEP(0.4, {
        // Arm every delayed callback (idle collapse 12 s, message fade 3.5 s), then lock.
        [self fingerTapOrb];
        WAIT_UNTIL(1, [self overlay].expanded);
        [self fingerTapItemTitled:@"Devices"];
        PortalOverlayView *detached = [self overlay];
        [self lockPhone];
        WAIT_UNTIL(13, NO); // every pending callback fires now
        Check(detached.superview == nil && !detached.expanded && [self portalViewsInWindow] == 0,
              @"callbacks that fire after a lock do nothing (no re-attach, no menu)");
        Check([Status(PortalStatusKeyState) isEqualToString:PortalEngineStateActive], @"no fault from late callbacks");
        [self unlockPhone];
        [self pullDownCoverSheet];
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
        Check(bad == 0, [NSString stringWithFormat:@"10 x disable / re-enable on the unlocked Cover Sheet: %d problems", bad]);
        Check([Status(PortalStatusKeyHooks) isEqualToString:hooks], @"hooks installed once, not again on re-enable");
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        [self lockPhone];
        [self setPrefs:@{PortalKeyEnabled : @YES}];
        WAIT_UNTIL(0.8, NO);
        Check([self portalViewsInWindow] == 0, @"enabled while locked: still nothing until iOS unlocks (starts closed)");
        [self unlockPhone];
        [self pullDownCoverSheet];
        WAIT_UNTIL(2, [Status(PortalStatusKeyVisibility) isEqualToString:@"visible"]);
        Check([Status(PortalStatusKeyTouch) containsString:@"activations"],
              [NSString stringWithFormat:@"touch diagnostics recorded for Settings: %@", Status(PortalStatusKeyTouch)]);
    });

    // ---- 15. Recovery ----------------------------------------------------------
    STEP(0.4, {
        CGPoint orb = [self orbCentre];
        [self setPrefs:@{PortalKeyEnabled : @NO}];
        Check([self overlay] == nil, @"Enable off: the portal is removed from the Cover Sheet at once");
        Check(![[self hit:orb] isKindOfClass:[UIControl class]], @"Enable off: the touch where the orb was reaches the normal Cover Sheet");
        NSUInteger subviews = 0;
        for (UIView *v in self.coverSheet.mainPageContentViewController.view.subviews)
            if ([NSStringFromClass([v class]) hasPrefix:@"Portal"]) subviews++;
        Check(subviews == 0, @"Enable off: no Portal view remains in the hierarchy");
        [self state:@"18-disabled" caption:@"Enable off: normal Cover Sheet"];
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

    // ---- 16. Settings: the real Settings bundle -----------------------------------
    __block UIViewController *settingsRoot = nil;
    STEP(0.5, {
        [PortalControllerPreviewStatus() count]; // the status written for Settings is current
        notify_post(PortalStatusRequestNotification.UTF8String);
        WAIT_UNTIL(1, NO);
        settingsRoot = [self showSettingsRoot];
        NSString *text = [self settingsText:settingsRoot];
        Check([text containsString:@"iPhone lock state: unlocked"] && [text containsString:@"Touches:"],
              [NSString stringWithFormat:@"Settings shows the lock state and the touch diagnostics (%@)",
                                         [text substringToIndex:MIN((NSUInteger)300, text.length)]]);
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
