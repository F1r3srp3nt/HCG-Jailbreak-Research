//
//  test_runtime.m
//  HCG Portal — runtime tests in the iOS Simulator (scripts/run-simulator-tests.sh).
//
//  Runs the REAL Objective-C code headless with `simctl spawn`: the renderer
//  (PortalView), the interactive overlay's touch decisions and radial menu,
//  the authentication broker against a stand-in SBLockScreenManager (scripted
//  success, cancellation, refusal, replay), the launcher's preview handler,
//  preference validation and the companion probes / Nexus contract double.
//
//  The integrated flow inside a stand-in Cover Sheet (layout around
//  notifications, unlock, recovery, Settings) is in preview/PortalPreviewApp.m.
//  Neither is SpringBoard and neither replaces a device test.
//

#import <UIKit/UIKit.h>

#import "PortalAuth.h"
#import "PortalCompanions.h"
#import "PortalCore.h"
#import "PortalLauncher.h"
#import "PortalOverlayView.h"
#import "PortalPreferences.h"
#import "PortalStandIns.h"
#import "PortalView.h"

static int gChecks = 0, gFailures = 0;

static void Check(BOOL ok, NSString *what) {
    gChecks++;
    if (!ok) gFailures++;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
}

static BOOL Spin(NSTimeInterval timeout, BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [limit timeIntervalSinceNow] > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    return done();
}

@interface Recorder : NSObject <PortalOverlayDelegate>
@property (nonatomic, strong) NSMutableArray<PortalMenuItem *> *selected;
@property (nonatomic) int expanded, collapsed;
@end
@implementation Recorder
- (instancetype)init {
    if ((self = [super init])) _selected = [NSMutableArray array];
    return self;
}
- (void)portalOverlay:(PortalOverlayView *)overlay didSelectItem:(PortalMenuItem *)item {
    [_selected addObject:item];
}
- (void)portalOverlayDidExpand:(PortalOverlayView *)overlay {
    _expanded++;
}
- (void)portalOverlayDidCollapse:(PortalOverlayView *)overlay {
    _collapsed++;
}
@end

static PortalRenderPlan Plan(int reduceMotion, int lowPower, int policy) {
    PortalAppearance a;
    portal_appearance_defaults(&a);
    return portal_render_plan(&a, reduceMotion, lowPower, policy, 1);
}

static void TestPortalView(void) {
    PortalView *v = [[PortalView alloc] initWithFrame:CGRectMake(0, 0, 132, 132)];
    PortalAppearance a;
    portal_appearance_defaults(&a);
    [v applyAppearance:a plan:Plan(0, 0, PORTAL_LOWPOWER_STATIC)];
    [v layoutIfNeeded];
    Check(v.runningAnimationCount >= 4, [NSString stringWithFormat:@"full plan: rings and core animate (%lu)", (unsigned long)v.runningAnimationCount]);
    Check(v.emitterActive, @"full plan: restrained particles on");
    Check([v hitTest:CGPointMake(66, 66) withEvent:nil] == nil && !v.userInteractionEnabled, @"PortalView never takes a touch");
    Check(v.accessibilityElementsHidden, @"decoration hidden from accessibility");
    v.paused = YES;
    Check(v.isPaused && !v.emitterActive, @"paused: emitter stopped");
    CALayer *stage = v.layer.sublayers.firstObject;
    Check(stage.speed == 0, @"paused: layer clock frozen (speed 0)");
    v.paused = NO;
    Check(stage.speed == 1 && v.emitterActive, @"resumed: clock running, emitter on");

    [v applyAppearance:a plan:Plan(1, 0, PORTAL_LOWPOWER_STATIC)];
    Check(v.runningAnimationCount == 0 && !v.emitterActive, @"Reduce Motion: static appearance, no animation, no particles");
    [v playUnlockFlourish];
    Check(!v.flourishPlayed, @"Reduce Motion: no unlock flourish");
    [v applyAppearance:a plan:Plan(0, 1, PORTAL_LOWPOWER_STATIC)];
    Check(v.runningAnimationCount == 0 && !v.emitterActive, @"Low Power (static): no animation");
    [v applyAppearance:a plan:Plan(0, 1, PORTAL_LOWPOWER_ECONOMY)];
    Check(v.runningAnimationCount >= 4 && !v.emitterActive, @"Low Power (economy): slow rings, no particles");
    [v applyAppearance:a plan:Plan(0, 0, PORTAL_LOWPOWER_STATIC)];
    [v playUnlockFlourish];
    Check(v.flourishPlayed, @"unlock flourish plays with the full plan");
    v.paused = YES;
    PortalView *w = [[PortalView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    [w applyAppearance:a plan:Plan(0, 0, PORTAL_LOWPOWER_STATIC)];
    w.paused = YES;
    [w playUnlockFlourish];
    Check(!w.flourishPlayed, @"paused view (screen off / hidden) never plays the flourish");
    for (int p = 0; p < PORTAL_PALETTE_COUNT; p++) {
        a.palette = p;
        [w applyAppearance:a plan:Plan(0, 0, PORTAL_LOWPOWER_STATIC)];
        [w layoutIfNeeded];
    }
    Check(YES, @"every palette builds at compact size");
}

static NSArray<PortalMenuItem *> *MainItems(void) {
    NSMutableArray *items = [NSMutableArray array];
    NSArray *titles = @[ @"Nexus", @"Backgrounds", @"Devices", @"HCG Apps" ];
    for (int i = 0; i < 4; i++) {
        PortalMenuItem *item = [PortalMenuItem itemWithTitle:titles[i] symbol:@"circle" destination:i item:-1];
        if (i == PORTAL_DEST_DEVICES) {
            item.availability = PORTAL_AVAIL_NOT_CONNECTED;
            item.statusText = @"Not connected";
        }
        [items addObject:item];
    }
    return items;
}

static void TestOverlay(void) {
    PortalOverlayView *o = [[PortalOverlayView alloc] initWithFrame:CGRectMake(0, 0, 414, 896)];
    Recorder *r = [[Recorder alloc] init];
    o.delegate = r;
    o.animationsAllowed = NO;
    PortalLayout l = {PORTAL_LAYOUT_FULL, 207, 390, 132, 66, 300, 700};
    PortalRect safe = {0, 47, 414, 815};
    [o applyLayout:l safe:safe animated:NO];
    [o setMainItems:MainItems()];

    UIView *hit = [o portalHitTest:CGPointMake(207, 390) touch:YES timestamp:1];
    Check([hit isKindOfClass:[UIControl class]], @"collapsed: the orb takes a touch at its centre");
    Check([o portalHitTest:CGPointMake(207, 390 + 60) touch:YES timestamp:2] != nil, @"collapsed: touch inside the orb circle");
    Check([o portalHitTest:CGPointMake(207 + 62, 390 + 62) touch:YES timestamp:3] == nil,
          @"collapsed: the orb's square corner passes through (circle, not square)");
    Check([o portalHitTest:CGPointMake(207, 150) touch:YES timestamp:4] == nil, @"collapsed: the clock area passes through");
    Check([o portalHitTest:CGPointMake(207, 860) touch:YES timestamp:5] == nil, @"collapsed: the unlock-gesture area passes through");
    Check(o.gestureRecognizers.count == 0, @"the overlay adds no gesture recognisers (unlock and paging gestures untouched)");
    Check(o.accessibilityElements.count == 1, @"collapsed: one accessibility element (the orb)");

    [(UIControl *)hit sendActionsForControlEvents:UIControlEventTouchUpInside];
    Check(o.expanded && r.expanded == 1, @"tap: the radial menu expands");
    Check(o.itemControls.count == 4, @"four destinations");
    Check(o.accessibilityElements.count == 5, @"expanded: orb + four items are accessible");
    PortalMenuLayout m = portal_menu_layout(&l, 4, &safe);
    BOOL allHit = YES, allBig = YES;
    for (NSUInteger i = 0; i < 4; i++) {
        UIView *h = [o portalHitTest:CGPointMake(m.x[i], m.y[i]) touch:YES timestamp:10 + i];
        if (h != o.itemControls[i]) allHit = NO;
        if (o.itemControls[i].bounds.size.width < 44) allBig = NO;
    }
    Check(allHit, @"each item takes the touch at its own centre");
    Check(allBig, @"item touch targets are at least 44 pt (64 pt discs)");
    [o.itemControls[1] sendActionsForControlEvents:UIControlEventTouchUpInside];
    Check(r.selected.count == 1 && r.selected[0].destination == PORTAL_DEST_BACKGROUNDS, @"selecting an item reports exactly that destination");

    Check([o portalHitTest:CGPointMake(30, 120) touch:NO timestamp:0] == nil && o.expanded,
          @"a non-touch hit-test outside never collapses");
    Check([o portalHitTest:CGPointMake(30, 120) touch:YES timestamp:50] == nil, @"expanded: a tap outside passes through");
    Spin(1, ^BOOL {
        return !o.expanded;
    });
    Check(!o.expanded && r.collapsed == 1, @"tap outside: the menu collapses");

    [o expand];
    [o showAppItems:@[ [PortalMenuItem itemWithTitle:@"App" symbol:@"app.fill" destination:PORTAL_DEST_APP_ITEM item:0] ]];
    Check([o.ringName isEqualToString:@"apps"] && o.itemControls.count == 1, @"HCG Apps ring replaces the main ring");
    [(UIControl *)[o portalHitTest:CGPointMake(207, 390) touch:YES timestamp:60] sendActionsForControlEvents:UIControlEventTouchUpInside];
    Check([o.ringName isEqualToString:@"main"] && o.expanded && o.itemControls.count == 4, @"tapping the orb in the app ring goes back");
    [o collapseAnimated:NO];

    PortalLayout c = {PORTAL_LAYOUT_COMPACT, 207, 330, 56, 28, 300, 400};
    [o applyLayout:c safe:safe animated:NO];
    Check([o portalHitTest:CGPointMake(207 + 24, 330) touch:YES timestamp:70] != nil, @"compact orb: 56 pt target");
    Check(CGRectGetWidth(o.orbFrame) == 56, @"compact orb drawn at 56 pt");
    PortalLayout h = {PORTAL_LAYOUT_HIDDEN, 0, 0, 0, 0, 300, 310};
    [o applyLayout:h safe:safe animated:NO];
    Check([o portalHitTest:CGPointMake(207, 330) touch:YES timestamp:80] == nil, @"no room: hidden, every touch passes through");
    Check(o.accessibilityElements.count == 0, @"no room: nothing for VoiceOver");
    [o applyLayout:l safe:safe animated:NO];
    o.hidden = YES;
    Check([o portalHitTest:CGPointMake(207, 390) touch:YES timestamp:90] == nil, @"hidden overlay passes every touch");
    o.hidden = NO;
    [o showMessage:@"Not connected."];
    Check([o.visibleMessage isEqualToString:@"Not connected."], @"messages are shown");
    Check([o portalHitTest:CGPointMake(207, CGRectGetMaxY(o.orbFrame) + 20) touch:YES timestamp:91] == nil,
          @"the message line never takes a touch");
}

static void TestAuth(void) {
    SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
    manager.coverSheetViewController = [[CSCoverSheetViewController alloc] init];
    PortalAuthBroker *auth = [[PortalAuthBroker alloc] init];
    Check(auth.available && [auth.route isEqualToString:@"coverSheetContext"], [NSString stringWithFormat:@"route: %@", auth.route]);

    __block NSMutableArray *outcomes = [NSMutableArray array];
    manager.authMode = PSIAuthSucceed;
    [auth requestAuthenticationNamed:@"HCG Portal: test" completion:^(PortalAuthOutcome o) { [outcomes addObject:@(o)]; }];
    Spin(1, ^BOOL { return outcomes.count > 0; });
    Check(outcomes.count == 1 && [outcomes[0] integerValue] == PortalAuthOutcomeAuthenticated, @"success reported once");
    Check(manager.lastRequest.fromContext && [manager.lastRequest.name isEqualToString:@"HCG Portal: test"] &&
              manager.lastRequest.wantsBiometricPresentation,
          @"the request comes from CoverSheet's own context, named, biometrics allowed");

    [outcomes removeAllObjects];
    manager.authMode = PSIAuthCancel;
    [auth requestAuthenticationNamed:@"x" completion:^(PortalAuthOutcome o) { [outcomes addObject:@(o)]; }];
    Spin(1, ^BOOL { return outcomes.count > 0; });
    Check(outcomes.count == 1 && [outcomes[0] integerValue] == PortalAuthOutcomeCancelled, @"cancellation reported");

    [outcomes removeAllObjects];
    manager.authMode = PSIAuthRefuse;
    [auth requestAuthenticationNamed:@"x" completion:^(PortalAuthOutcome o) { [outcomes addObject:@(o)]; }];
    Check(outcomes.count == 1 && [outcomes[0] integerValue] == PortalAuthOutcomeRefused, @"a refused request is reported at once");

    [outcomes removeAllObjects];
    manager.authMode = PSIAuthHold;
    [auth requestAuthenticationNamed:@"x" completion:^(PortalAuthOutcome o) { [outcomes addObject:@(o)]; }];
    Check(outcomes.count == 0 && manager.hasPendingRequest, @"held: nothing reported while the system UI is up");
    void (^replay)(BOOL) = [manager resolvePending:YES];
    Check(outcomes.count == 1, @"held request completes on success");
    if (replay) replay(NO);
    if (replay) replay(YES);
    Spin(0.2, ^BOOL { return NO; });
    Check(outcomes.count == 1, @"the completion is delivered exactly once, even if SpringBoard calls back again");

    manager.coverSheetViewController = nil;
    [auth refresh];
    Check([auth.route isEqualToString:@"constructed request"], @"without a Cover Sheet context: constructed request");
    manager.authMode = PSIAuthSucceed;
    [outcomes removeAllObjects];
    [auth requestAuthenticationNamed:@"y" completion:^(PortalAuthOutcome o) { [outcomes addObject:@(o)]; }];
    Spin(1, ^BOOL { return outcomes.count > 0; });
    Check(!manager.lastRequest.fromContext && manager.lastRequest.source == 17 && manager.lastRequest.intent == 3,
          @"constructed request: source 17, intent 3");
}

static void TestLauncherAndPreferences(void) {
    NSMutableArray *launched = [NSMutableArray array];
    [PortalLauncher setPreviewLaunchHandler:^BOOL(NSString *bundle) {
        [launched addObject:bundle];
        return YES;
    }];
    PortalLauncher *launcher = [[PortalLauncher alloc] init];
    __block BOOL done = NO;
    [launcher openApplication:@"com.example.app" completion:^(BOOL ok) { done = ok; }];
    Spin(1, ^BOOL { return done; });
    Check(done && launched.count == 1 && [launched[0] isEqualToString:@"com.example.app"], @"launcher opens exactly the app asked for");
    [PortalLauncher setPreviewLaunchHandler:nil];

    PortalSettings *s = [PortalSettings settingsWithDictionary:@{
        @"enabled" : @"yes", @"palette" : @"plaid", @"brightness" : @9, @"speed" : @"fast", @"intensity" : @(-3),
        @"size" : @1000, @"offsetX" : @(-999), @"offsetY" : @(1e9), @"lowPower" : @"turbo", @"unlockAnimation" : @NO,
        @"apps" : @[
            @{@"id" : @"com.a.one", @"name" : @"One"}, @{@"id" : @"com.a.one", @"name" : @"Dup"}, @{@"id" : @"bad id!"},
            @"junk", @{@"id" : @"com.a.two"}, @{@"id" : @"com.a.3"}, @{@"id" : @"com.a.4"}, @{@"id" : @"com.a.5"},
            @{@"id" : @"com.a.6"}, @{@"id" : @"com.a.7"}
        ]
    }];
    Check(!s.enabled, @"a non-boolean Enable is treated as off");
    Check(s.appearance.palette == PORTAL_PALETTE_SIGNATURE && s.appearance.brightness == 1.0 &&
              s.appearance.speed == PORTAL_SPEED_DEFAULT && s.appearance.intensity == 0,
          @"appearance values validated and clamped");
    Check(s.placement.size == PORTAL_SIZE_MAX && s.placement.offsetX == -PORTAL_OFFSET_X_LIMIT &&
              s.placement.offsetY == PORTAL_OFFSET_Y_MAX,
          @"placement clamped");
    Check(s.lowPowerPolicy == PORTAL_LOWPOWER_STATIC && !s.unlockAnimation, @"low power fallback; unlock animation off honoured");
    Check(s.apps.count == PORTAL_MAX_APPS && [s.apps[0].name isEqualToString:@"One"] && [s.apps[1].name isEqualToString:@"com.a.two"],
          @"apps: invalid and duplicate entries dropped, at most six, names default to the identifier");
    PortalSettings *d = [PortalSettings settingsWithDictionary:@{}];
    Check(!d.enabled && d.unlockAnimation && d.apps.count == 0 && d.placement.size == PORTAL_SIZE_DEFAULT,
          @"defaults: off, unlock animation on, no apps, default size");
}

static void TestCompanions(void) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"portal-jbroot"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:root error:NULL];
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
    [PortalCompanions setJailbreakRootForTesting:root];
    [HCGNexusPortalInterface setStandInActive:NO];
    Check(![PortalCompanions animationCenterInstalled] && ![PortalCompanions nexusInstalled], @"nothing installed: both absent");
    NSString *ac = [root stringByAppendingPathComponent:@"Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle"];
    [fm createDirectoryAtPath:ac withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"" writeToFile:[ac stringByAppendingPathComponent:@"Info.plist"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check(![PortalCompanions animationCenterInstalled], @"Animation Center needs its PreferenceLoader entry too");
    NSString *loader = [root stringByAppendingPathComponent:@"Library/PreferenceLoader/Preferences"];
    [fm createDirectoryAtPath:loader withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"" writeToFile:[loader stringByAppendingPathComponent:@"HCGAnimationCenterPrefs.plist"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check([PortalCompanions animationCenterInstalled], @"Animation Center detected from its installed files");
    NSString *nx = [root stringByAppendingPathComponent:@"Library/PreferenceBundles/HCGNexusPrefs.bundle"];
    [fm createDirectoryAtPath:nx withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"" writeToFile:[nx stringByAppendingPathComponent:@"Info.plist"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check([PortalCompanions nexusInstalled] && ![PortalCompanions nexusOpenInterfaceAvailable],
          @"Nexus installed without the open interface (as 0.3.1~beta1)");
    PortalDestinationProbe probe = {1, 1, 1, [PortalCompanions nexusOpenInterfaceAvailable], 1, 0};
    Check(portal_destination_availability(PORTAL_DEST_NEXUS, &probe) == PORTAL_AVAIL_NEEDS_INTERFACE, @"Nexus: needs an update");
    __block BOOL opened = YES;
    __block BOOL answered = NO;
    [PortalCompanions openNexusPanelWithCompletion:^(BOOL ok, NSString *reason) { opened = ok; answered = YES; }];
    Check(answered && !opened, @"without the interface, nothing is opened");
    [HCGNexusPortalInterface setStandInActive:YES];
    Check([PortalCompanions nexusOpenInterfaceAvailable], @"interface v1 double detected");
    answered = NO;
    [PortalCompanions openNexusPanelWithCompletion:^(BOOL ok, NSString *reason) { opened = ok; answered = YES; }];
    Spin(1, ^BOOL { return answered; });
    Check(answered && opened && HCGNexusPortalInterface.openCount == 1 && [HCGNexusPortalInterface.lastSource isEqualToString:@"hcg-portal"],
          @"open request reaches Nexus once, with source hcg-portal");
    [HCGNexusPortalInterface setStandInActive:NO];
    Check([[PortalCompanions summary] containsString:@"Devices: not connected"], @"summary: Devices not connected");

    __block NSDictionary *info = nil;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:PortalLightingEventNotification object:nil queue:nil
                                                             usingBlock:^(NSNotification *n) { info = n.userInfo; }];
    [PortalCompanions postLightingEvent:@"expanded" palette:PORTAL_PALETTE_SIGNATURE intensity:0.6];
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    NSSet *keys = [NSSet setWithArray:info.allKeys];
    Check([keys isEqualToSet:[NSSet setWithArray:@[ @"event", @"interfaceVersion", @"palette", @"intensity" ]]] &&
              [info[@"interfaceVersion"] integerValue] == 1,
          @"lighting event v1: only event, version, palette and intensity (no user data)");
    [PortalCompanions setJailbreakRootForTesting:nil];
    [fm removeItemAtPath:root error:NULL];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("HCG Portal %s runtime tests (iOS Simulator %s)\n", PORTAL_VERSION, UIDevice.currentDevice.systemVersion.UTF8String);
        printf("-- TestPortalView\n");
        TestPortalView();
        printf("-- TestOverlay\n");
        TestOverlay();
        printf("-- TestAuth\n");
        TestAuth();
        printf("-- TestLauncherAndPreferences\n");
        TestLauncherAndPreferences();
        printf("-- TestCompanions\n");
        TestCompanions();
        printf("%d checks, %d failures\n", gChecks, gFailures);
        return gFailures ? 1 : 0;
    }
}
