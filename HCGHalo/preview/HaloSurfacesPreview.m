//
//  HaloSurfacesPreview.m
//  HCG Halo — PREVIEW of "Show Halo on" (iOS Simulator only).
//
//  Built by scripts/surfaces-preview.sh. Runs HCG Halo's REAL SpringBoard
//  code — HaloController (lifecycle, policies, hosts), HaloEdgeWindow,
//  HaloOverlayView, HaloRenderer, HaloPreferences — inside a Simulator app
//  that stands in for SpringBoard:
//    * the app's UIApplication class is named SpringBoard and implements
//      -frontDisplayDidChange: (hooked by the controller's installer, as the
//      tweak's Logos hook does) and -_accessibilityFrontMostApplication;
//    * its main window is an SBHomeScreenWindow;
//    * "apps" are SBApplication objects with a bundle identifier;
//    * lock and screen-off are Darwin notifications with notify state, like
//      SpringBoard's, but under preview names (HALO_LOCKSTATE_NOTIFICATION /
//      HALO_BLANKED_NOTIFICATION), so the Simulator's real SpringBoard is
//      never touched.
//  Settings changes are written to the real preference domain and announced
//  with the real Darwin notification, as the Settings pane does.
//
//  What is NOT real: SpringBoard itself, its window levels, a real Lock
//  Screen, a real dark display, Low Power Mode, a device and its
//  performance. This is preview evidence, not a device result.
//
//  Prints "HALO-SURFACES-STATE <name> | ..." per state and
//  "HALO-SURFACES-CHECK PASS|FAIL <what>" per check, then
//  "HALO-SURFACES-DONE failures=N".
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "HaloConfig.h"
#import "HaloController.h"
#import "HaloEdgeWindow.h"
#import "HaloPreferences.h"
#import "HaloScreen.h"

#include <notify.h>

static int gFailures = 0;

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
    Say(@"HALO-SURFACES-CHECK %@ %@", ok ? @"PASS" : @"FAIL", what);
}

#pragma mark - Stand-ins for the SpringBoard classes HCG Halo looks up

@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@end

@implementation SBApplication
@end

@interface SBHomeScreenWindow : UIWindow
@end

@implementation SBHomeScreenWindow
@end

static SBApplication *gFront; // the "app in front" (nil = Home Screen)

@interface SpringBoard : UIApplication
- (void)frontDisplayDidChange:(id)display;
- (id)_accessibilityFrontMostApplication;
@end

@implementation SpringBoard
- (void)frontDisplayDidChange:(id)display {
}
- (id)_accessibilityFrontMostApplication {
    return gFront;
}
@end

/// The tweak's %hook, done by hand: %orig first, then tell HCG Halo.
static void HaloPreviewInstallHook(void) {
    Class cls = objc_getClass("SpringBoard");
    Method method = class_getInstanceMethod(cls, @selector(frontDisplayDidChange:));
    __block IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id self_, id display) {
        ((void (*)(id, SEL, id))original)(self_, @selector(frontDisplayDidChange:), display);
        HaloControllerFrontDisplayDidChange(display);
    });
    method_setImplementation(method, replacement);
}

#pragma mark - System state (preview notification names)

static void PostState(const char *name, uint64_t value) {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return;
    notify_set_state(token, value);
    notify_post(name);
    notify_cancel(token);
}

static void WritePrefs(NSDictionary *values) {
    [HaloPreferences writeValues:values];
    [HaloPreferences postChangeNotification];
}

#pragma mark - Inspection

static NSArray<UIWindow *> *AllWindows(void) {
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    return windows;
}

static void Collect(UIView *view, NSMutableArray *out) {
    if ([view.accessibilityIdentifier isEqualToString:@"HCGHaloOverlay"]) [out addObject:view];
    for (UIView *sub in view.subviews) Collect(sub, out);
}

static NSArray<UIView *> *Overlays(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIWindow *window in AllWindows()) Collect(window, out);
    return out;
}

static NSArray<UIWindow *> *EdgeWindows(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIWindow *window in AllWindows())
        if ([window isKindOfClass:[HaloEdgeWindow class]]) [out addObject:window];
    return out;
}

/// Visible = the overlay and every ancestor (and its window) are shown.
static BOOL OverlayShown(UIView *overlay) {
    if (!overlay || !overlay.window || overlay.window.hidden) return NO;
    for (UIView *v = overlay; v; v = v.superview)
        if (v.hidden || v.alpha < 0.01) return NO;
    return YES;
}

static BOOL OverlayPaused(UIView *overlay) {
    CALayer *root = overlay.layer.sublayers.firstObject;
    return root && root.speed == 0;
}

static NSString *HostName(UIView *overlay) {
    if (!overlay.window) return @"none";
    if ([overlay.window isKindOfClass:[HaloEdgeWindow class]]) return @"edge";
    if ([overlay.window isKindOfClass:[SBHomeScreenWindow class]]) return @"home";
    return NSStringFromClass([overlay.window class]);
}

#pragma mark - Scene

@interface HaloSurfacesController : UIViewController
@end

@implementation HaloSurfacesController {
    UILabel *_caption;
    UIWindow *_appWindow;   // the "app in front"
    UILabel *_appLabel;
    UIWindow *_lockWindow;  // the "Lock Screen"
    UIWindow *_darkWindow;  // the "display off": black, above everything
    NSMutableArray<void (^)(void)> *_steps;
    NSMutableArray<NSDictionary *> *_alwaysTrace;
    NSMutableArray<NSDictionary *> *_screenOffTrace;
    NSString *_policy;
    BOOL _locked, _dark;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.03 green:0.05 blue:0.10 alpha:1];
    UILabel *banner = [UILabel new];
    banner.numberOfLines = 0;
    banner.textAlignment = NSTextAlignmentCenter;
    banner.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    banner.textColor = UIColor.blackColor;
    banner.backgroundColor = [UIColor colorWithRed:1 green:0.71 blue:0.28 alpha:1];
    banner.text = @"PREVIEW · iOS Simulator · real HCG Halo controller + overlay · stand-in SpringBoard · NOT a device result";
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:banner];

    UILabel *home = [UILabel new];
    home.text = @"HOME SCREEN";
    home.font = [UIFont systemFontOfSize:28 weight:UIFontWeightHeavy];
    home.textColor = [UIColor colorWithWhite:1 alpha:0.35];
    home.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:home];

    _caption = [UILabel new];
    _caption.numberOfLines = 0;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    _caption.textColor = UIColor.whiteColor;
    _caption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_caption];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [banner.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [banner.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [banner.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [home.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [home.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_caption.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-40],
        [_caption.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [_caption.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];
}

- (UIWindow *)windowWithLevel:(CGFloat)level colour:(UIColor *)colour text:(NSString *)text label:(UILabel **)labelOut {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:self.view.window.windowScene];
    window.frame = self.view.window.bounds;
    window.windowLevel = level;
    window.backgroundColor = colour;
    window.userInteractionEnabled = NO;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = colour;
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    ]];
    window.rootViewController = vc;
    window.hidden = YES;
    if (labelOut) *labelOut = label;
    return window;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_steps) return;
    _appWindow = [self windowWithLevel:UIWindowLevelNormal + 1
                                colour:[UIColor colorWithRed:0.10 green:0.12 blue:0.18 alpha:1]
                                  text:@"APP"
                                 label:&_appLabel];
    _lockWindow = [self windowWithLevel:1000
                                 colour:[UIColor colorWithRed:0.05 green:0.02 blue:0.12 alpha:1]
                                   text:@"LOCK SCREEN\n9:41"
                                  label:NULL];
    _darkWindow = [self windowWithLevel:3000 colour:UIColor.blackColor text:@"" label:NULL];
    _alwaysTrace = [NSMutableArray array];
    _screenOffTrace = [NSMutableArray array];
    [self buildSteps];
    [self next];
}

#pragma mark Stand-in SpringBoard actions

- (void)bringApp:(NSString *)identifier name:(NSString *)name {
    SBApplication *app = nil;
    if (identifier) {
        app = [SBApplication new];
        app.bundleIdentifier = identifier;
        app.displayName = name;
    }
    gFront = app;
    _appLabel.text = name ?: @"";
    _appWindow.hidden = app == nil;
    [(SpringBoard *)UIApplication.sharedApplication frontDisplayDidChange:app];
}

- (void)setLocked:(BOOL)locked {
    _locked = locked;
    _lockWindow.hidden = !locked;
    PostState(HALO_LOCKSTATE_NOTIFICATION, locked ? 1 : 0);
}

- (void)setDark:(BOOL)dark {
    _dark = dark;
    _darkWindow.hidden = !dark;
    PostState(HALO_BLANKED_NOTIFICATION, dark ? 1 : 0);
}

- (void)setPolicy:(NSString *)policy {
    _policy = policy;
    WritePrefs(@{HaloKeyShowOn : policy});
}

#pragma mark Reporting

- (NSDictionary *)snapshot {
    NSArray *overlays = Overlays();
    UIView *overlay = overlays.firstObject;
    return @{
        @"count" : @(overlays.count),
        @"edgeWindows" : @(EdgeWindows().count),
        @"host" : HostName(overlay),
        @"shown" : @(OverlayShown(overlay)),
        @"paused" : @(overlay ? OverlayPaused(overlay) : YES),
    };
}

- (void)state:(NSString *)name {
    NSDictionary *s = [self snapshot];
    NSString *line = [NSString stringWithFormat:@"%@ | showOn=%@ front=%@ locked=%d dark=%d | host=%@ shown=%@ paused=%@ "
                                                @"overlays=%@ edgeWindows=%@",
                                                name, _policy, gFront.bundleIdentifier ?: @"home", _locked, _dark,
                                                s[@"host"], s[@"shown"], s[@"paused"], s[@"count"], s[@"edgeWindows"]];
    _caption.text = [NSString stringWithFormat:@"%@\nShow Halo on: %@\nfront: %@ · %@%@\nborder: %@",
                                               name, _policy, gFront.displayName ?: @"Home Screen",
                                               _locked ? @"locked" : @"unlocked", _dark ? @" · screen off" : @"",
                                               [s[@"shown"] boolValue] ? @"SHOWN" : @"hidden"];
    Say(@"HALO-SURFACES-STATE %@", line);
}

/// Checks visibility and, when shown, that it is animating; when hidden, paused.
- (void)expect:(BOOL)shown host:(NSString *)host what:(NSString *)what {
    NSDictionary *s = [self snapshot];
    BOOL okShown = [s[@"shown"] boolValue] == shown;
    BOOL okPaused = [s[@"paused"] boolValue] == !shown;
    BOOL okHost = !host || [s[@"host"] isEqualToString:host];
    BOOL okCount = [s[@"count"] integerValue] == 1 && [s[@"edgeWindows"] integerValue] <= 1;
    Check(okShown && okPaused && okHost && okCount,
          [NSString stringWithFormat:@"%@: %@%@ (got shown=%@ paused=%@ host=%@ overlays=%@)", what,
                                     shown ? @"shown, animating" : @"hidden, paused", host ? [@" in " stringByAppendingString:host] : @"",
                                     s[@"shown"], s[@"paused"], s[@"host"], s[@"count"]]);
    if ([_policy isEqualToString:@"always"]) [_alwaysTrace addObject:@{@"what" : what, @"shown" : s[@"shown"]}];
    if ([_policy isEqualToString:@"exceptScreenOff"]) [_screenOffTrace addObject:@{@"what" : what, @"shown" : s[@"shown"]}];
}

#pragma mark Script

- (void)next {
    if (!_steps.count) return;
    void (^step)(void) = _steps.firstObject;
    [_steps removeObjectAtIndex:0];
    step();
}

- (void)buildSteps {
    _steps = [NSMutableArray array];
    __weak HaloSurfacesController *weakSelf = self;
#define STEP(delay, ...)                                                                                      \
    [_steps addObject:^{                                                                                      \
        HaloSurfacesController *self = weakSelf;                                                              \
        if (!self) return;                                                                                    \
        __VA_ARGS__;                                                                                          \
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay) * NSEC_PER_SEC)),                   \
                       dispatch_get_main_queue(), ^{                                                          \
                           [weakSelf next];                                                                   \
                       });                                                                                    \
    }]

    // --- A. Home Screen Only (default) -------------------------------------
    STEP(3.0, {
        HaloSettings *settings = [HaloPreferences loadSettings];
        self->_policy = @(halo_show_on_id(settings.showOn));
        Check(settings.showOn == HaloShowOnHome, @"default Show Halo on is Home Screen Only");
    });
    STEP(1.5, {
        [self expect:YES host:@"home" what:@"A1 Home Screen Only, Home Screen in front"];
        [self state:@"A1-home"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:NO host:@"home" what:@"A2 Home Screen Only, app opened"];
        [self state:@"A2-home-app-open"];
        [self bringApp:nil name:nil];
    });
    STEP(1.5, {
        [self expect:YES host:@"home" what:@"A3 Home Screen Only, back to the Home Screen"];
        [self setLocked:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"home" what:@"A4 Home Screen Only, locked (lit)"];
        [self state:@"A4-home-locked"];
        [self setDark:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"home" what:@"A5 Home Screen Only, screen off"];
        [self setDark:NO];
    });
    STEP(1.5, {
        [self expect:NO host:@"home" what:@"A6 Home Screen Only, woken but still locked"];
        [self setLocked:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"home" what:@"A7 Home Screen Only, unlocked"];

        // --- B. Always ------------------------------------------------------
        [self setPolicy:@"always"];
    });
    STEP(2.0, {
        [self expect:YES host:@"edge" what:@"B1 Always: moved to the overlay window at once"];
        UIWindow *edge = EdgeWindows().firstObject;
        CGPoint centre = CGPointMake(CGRectGetMidX(edge.bounds), CGRectGetMidY(edge.bounds));
        Check(edge && [edge hitTest:centre withEvent:nil] == nil && [edge hitTest:CGPointMake(2, 2) withEvent:nil] == nil,
              @"overlay window never takes a touch (centre and edge)");
        Check(edge && !edge.canBecomeKeyWindow && !edge.isKeyWindow, @"overlay window never becomes key");
        Check(edge && !edge.userInteractionEnabled && edge.windowLevel == HALO_EDGE_WINDOW_LEVEL,
              [NSString stringWithFormat:@"overlay window non-interactive, level %.0f", edge.windowLevel]);
        Check(edge && CGRectEqualToRect(edge.bounds, UIScreen.mainScreen.bounds), @"overlay window covers the screen");
        [self state:@"B1-always-home"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"B2 Always, over an app"];
        [self state:@"B2-always-app"];
        [self setLocked:YES];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"B3 Always, lit Lock Screen"];
        [self state:@"B3-always-lock-screen"];
        [self setDark:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"B4 Always, screen off: hidden, paused"];
        Check(EdgeWindows().firstObject.hidden, @"B4 overlay window itself hidden while the screen is off");
        [self state:@"B4-always-screen-off"];
        [self setDark:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"B5 Always, woken on the Lock Screen"];
        [self setLocked:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"B6 Always, unlocked into the app"];
        [self bringApp:nil name:nil];
    });
    STEP(1.0, {
        // --- C. Always Except When Screen Is Off: same transitions ----------
        [self setPolicy:@"exceptScreenOff"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"C1 Except Screen Off: in the overlay window"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"C2 Except Screen Off, over an app"];
        [self setLocked:YES];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"C3 Except Screen Off, lit Lock Screen"];
        [self state:@"C3-except-screen-off-lock-screen"];
        [self setDark:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"C4 Except Screen Off, screen off: hidden, paused"];
        [self state:@"C4-except-screen-off-dark"];
        [self setDark:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"C5 Except Screen Off, woken on the Lock Screen"];
        [self setLocked:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"C6 Except Screen Off, unlocked into the app"];
        NSMutableArray *a = [NSMutableArray array], *b = [NSMutableArray array];
        for (NSDictionary *d in self->_alwaysTrace) [a addObject:d[@"shown"]];
        for (NSDictionary *d in self->_screenOffTrace) [b addObject:d[@"shown"]];
        Check(a.count == 6 && [a isEqualToArray:b],
              [NSString stringWithFormat:@"Always and Always Except When Screen Is Off behave identically here (%@ vs %@)",
                                         [a componentsJoinedByString:@""], [b componentsJoinedByString:@""]]);

        // --- D. Always Except Lock Screen --------------------------------
        [self setPolicy:@"exceptLock"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"D1 Except Lock Screen, over an app"];
        [self state:@"D1-except-lock-app"];
        [self setLocked:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"D2 Except Lock Screen, locked (lit): hidden"];
        [self state:@"D2-except-lock-locked"];
        [self setDark:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"D3 Except Lock Screen, screen off"];
        [self setDark:NO];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"D4 Except Lock Screen, woken, still locked"];
        [self setLocked:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"D5 Except Lock Screen, unlocked"];
        [self bringApp:nil name:nil];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"D6 Except Lock Screen, Home Screen"];

        // --- E. Selected App Only ----------------------------------------
        WritePrefs(@{HaloKeyShowOnApp : @"", HaloKeyShowOn : @"app"});
        self->_policy = @"app";
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E1 Selected App Only, no app chosen"];
        WritePrefs(@{HaloKeyShowOnApp : @"com.apple.mobilesafari", HaloKeyShowOnAppName : @"Safari"});
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E2 Safari chosen, Home Screen in front"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"E3 Safari in front"];
        [self state:@"E3-app-safari"];
        [self bringApp:@"com.apple.Maps" name:@"Maps"];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E4 switched to Maps"];
        [self state:@"E4-app-maps"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"E5 back to Safari"];
        [self setLocked:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E6 Safari, locked"];
        [self setDark:YES];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E7 Safari, screen off"];
        [self setDark:NO];
        [self setLocked:NO];
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"E8 woken and unlocked into Safari"];
        [self bringApp:nil name:nil];
    });
    STEP(1.5, {
        [self expect:NO host:@"edge" what:@"E9 Home Screen (Safari closed)"];

        // --- F. back to Home Screen Only -----------------------------------
        [self setPolicy:@"home"];
    });
    STEP(2.0, {
        [self expect:YES host:@"home" what:@"F1 Home Screen Only again: back in the Home Screen window"];
        Check(EdgeWindows().count == 0, @"F1 overlay window released");
        [self state:@"F1-home-again"];
        [self bringApp:@"com.apple.mobilesafari" name:@"Safari"];
    });
    STEP(1.5, {
        [self expect:NO host:@"home" what:@"F2 Home Screen Only, app open"];
        [self bringApp:nil name:nil];

        // --- G. target HCG Nexus panel only: no screen edge at all ---------
        WritePrefs(@{HaloKeyShowOn : @"always", HaloKeyTarget : @"nexus"});
        self->_policy = @"always";
    });
    STEP(1.5, {
        Check(Overlays().count == 0 && EdgeWindows().count == 0,
              @"G1 target HCG Nexus panel only: no screen-edge overlay under any Show Halo on choice");
        WritePrefs(@{HaloKeyTarget : @"screen"});
    });
    STEP(1.5, {
        [self expect:YES host:@"edge" what:@"G2 target screen again: Always restored"];

        // --- H. rapid transitions --------------------------------------------
        NSArray *apps = @[ @"com.apple.mobilesafari", @"com.apple.Maps", @"" ];
        NSArray *policies = @[ @"home", @"app", @"always", @"exceptLock", @"exceptScreenOff" ];
        srand48(7);
        int maxOverlays = 0, maxEdge = 0;
        for (int i = 0; i < 60; i++) {
            switch (lrand48() % 4) {
            case 0: {
                NSString *app = apps[lrand48() % apps.count];
                [self bringApp:app.length ? app : nil name:app.length ? app : nil];
                break;
            }
            case 1: [self setLocked:!self->_locked]; break;
            case 2: [self setDark:!self->_dark]; break;
            default: [self setPolicy:policies[lrand48() % policies.count]]; break;
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
            maxOverlays = MAX(maxOverlays, (int)Overlays().count);
            maxEdge = MAX(maxEdge, (int)EdgeWindows().count);
        }
        Check(maxOverlays <= 1 && maxEdge <= 1,
              [NSString stringWithFormat:@"H1 60 rapid transitions: at most one overlay (%d) and one overlay window (%d)",
                                         maxOverlays, maxEdge]);
        [self setDark:NO];
        [self setLocked:NO];
        [self bringApp:nil name:nil];
        [self setPolicy:@"always"];
    });
    STEP(2.0, {
        [self expect:YES host:@"edge" what:@"H2 settled after the rapid transitions"];
        [self setPolicy:@"home"];
    });
    STEP(2.0, {
        [self expect:YES host:@"home" what:@"H3 Home Screen Only after the rapid transitions"];
        [self state:@"H3-final"];

        // --- Geometry on this Simulator --------------------------------------
        HaloSettings *settings = [HaloPreferences loadSettings];
        HaloScreenMeasure m = HaloCurrentScreenMeasure();
        HaloScreenFit fit = HaloScreenFitUnknown;
        double k = 1;
        HaloDisplayGeometry g = halo_profile_geometry_for_screen(settings.profile, settings.calibration, m, &fit, &k);
        Say(@"HALO-SURFACES-GEOMETRY model=%@ screen=%@ fit=%s scale=%.4f corner=%.2f notch=%.2fx%.2f | %@",
            HaloMachineIdentifier(), HaloScreenSummary(), halo_screen_fit_id(fit), k, g.cornerRadius, g.notchWidth,
            g.notchHeight, HaloScreenFitSentence(settings.profile, m));
        if ([HaloMachineIdentifier() isEqualToString:@"iPhone12,5"])
            Check(fit == HaloScreenFitMatch && g.cornerRadius == 39 && g.width == 414,
                  @"iPhone 11 Pro Max Simulator: 414 × 896 pt, profile applies unscaled");
        else
            Check(fit != HaloScreenFitDisplayZoom, @"a different Simulator model is never mistaken for Display Zoom");
        HaloScreenMeasure zoomed = {375, 812, 1242, 2688};
        HaloDisplayGeometry z = halo_profile_geometry_for_screen(settings.profile, settings.calibration, zoomed, &fit, &k);
        Check(fit == HaloScreenFitDisplayZoom && fabs(z.cornerRadius - 39 * 375.0 / 414.0) < 0.01,
              [NSString stringWithFormat:@"Display Zoom measurement (375 × 812 pt, 1242 × 2688 px): corner %.2f pt, notch "
                                         @"%.2f × %.2f pt",
                                         z.cornerRadius, z.notchWidth, z.notchHeight]);
    });
    STEP(1.0, {
        Say(@"HALO-SURFACES-DONE failures=%d", gFailures);
    });
#undef STEP
}

@end

#pragma mark - App

@interface HaloSurfacesAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HaloSurfacesAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[SBHomeScreenWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HaloSurfacesController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Start state: enabled, screen edge, Home Screen Only (the default), an animated mode.
        NSMutableDictionary *reset = [NSMutableDictionary dictionary];
        for (NSString *key in [HaloPreferences allKeys]) reset[key] = [NSNull null];
        [HaloPreferences writeValues:reset];
        [HaloPreferences writeValues:@{HaloKeyEnabled : @YES, HaloKeyMode : @"flow", HaloKeyThickness : @4.0}];
        [HaloPreferences setConsecutiveUnstableLaunches:0];
        PostState(HALO_LOCKSTATE_NOTIFICATION, 0);
        PostState(HALO_BLANKED_NOTIFICATION, 0);
        Say(@"HALO-SURFACES-START HCG Halo %s, model %@", HALO_VERSION, HaloMachineIdentifier());
        HaloControllerBootstrap(HaloPreviewInstallHook); // as the tweak's %ctor does
        return UIApplicationMain(argc, argv, @"SpringBoard", NSStringFromClass([HaloSurfacesAppDelegate class]));
    }
}
