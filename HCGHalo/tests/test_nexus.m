//
//  test_nexus.m
//  HCG Halo — runtime tests for the HCG Nexus panel border, run in the iOS
//  Simulator with test_runtime.m (scripts/run-simulator-tests.sh).
//
//  Covers: the border-definition validator (fixtures written at run time;
//  the real file is HCG Nexus's Prefs/Resources/HaloBorder.plist), the panel
//  border view (geometry, masking, touches, effects, cleanup), and the link's
//  behaviour for every combination: Nexus absent, incompatible interface,
//  missing / malformed / outdated definition, panel not built, Nexus updated
//  but not resprung, attached, events (valid, forged, malformed), screen off,
//  Halo disabled, interface removed, repeated open/close.
//
//  The link is driven by a TEST DOUBLE registered at run time under the
//  interface's class name. It checks Halo's side of the contract only; the
//  combined preview app (preview/, CI) runs Halo against HCG Nexus's real
//  panel code. Neither replaces a device test.
//

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "HaloConfig.h"
#import "HaloNexusDefinition.h"
#import "HaloNexusLink.h"
#import "HaloPanelBorderView.h"
#import "HaloPreferences.h"

#include <math.h>

static long gNexusChecks = 0, gNexusFailures = 0;

#define NCHECK(cond, ...)                                                                   \
    do {                                                                                    \
        gNexusChecks++;                                                                     \
        if (!(cond)) {                                                                      \
            gNexusFailures++;                                                               \
            fprintf(stderr, "FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond);                \
            fprintf(stderr, "%s\n", [[NSString stringWithFormat:__VA_ARGS__] UTF8String]);  \
        }                                                                                   \
    } while (0)

#pragma mark - Fixtures

static NSMutableDictionary *ValidDefinition(NSString *version) {
    return [@{
        @"schema" : @"com.hakmicapitalgroup.hcgnexus.halo-border",
        @"schemaVersion" : @1,
        @"interfaceVersion" : @1,
        @"interfaceClass" : @"HCGNexusBorderInterface",
        @"nexusVersion" : version,
        @"shape" : @{@"kind" : @"rounded-rect", @"cornerRadius" : @22, @"cornerCurve" : @"continuous"},
        @"anchors" : @{@"host" : @"panel", @"outset" : @2, @"glowMargin" : @36, @"clipInterior" : @YES},
        @"capabilities" : @[ @"live-geometry", @"open-close-events", @"presentation-progress", @"workspace-events",
                             @"orientation", @"keyboard-resize" ],
        @"style" : @{@"defaultPreset" : @"builtin.nexus-signature"},
    } mutableCopy];
}

static NSData *Encode(id plist, NSPropertyListFormat format) {
    return [NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:nil];
}

static NSString *gFixtureDir;

static NSString *WriteFixture(NSString *name, NSData *data) {
    NSString *path = [gFixtureDir stringByAppendingPathComponent:name];
    [data writeToFile:path atomically:YES];
    return path;
}

#pragma mark - Definition validator

static void TestDefinition(void) {
    NSString *error = nil;
    for (NSNumber *format in @[ @(NSPropertyListXMLFormat_v1_0), @(NSPropertyListBinaryFormat_v1_0) ]) {
        NSString *path = WriteFixture(@"valid.plist", Encode(ValidDefinition(@"0.2.2~beta1"), format.unsignedIntegerValue));
        error = nil;
        HaloNexusDefinition *d = [HaloNexusDefinition definitionAtPath:path error:&error];
        NCHECK(d && !error, @"valid definition (%@) rejected: %@", format, error);
        NCHECK(d.cornerRadius == 22 && d.continuousCorners && d.outset == 2 && d.glowMargin == 36 && d.clipInterior,
               @"parsed shape/anchors");
        NCHECK([d hasCapability:@"live-geometry"] && ![d hasCapability:@"teleport"], @"capabilities");
        NCHECK([d.nexusVersion isEqualToString:@"0.2.2~beta1"] && [d.defaultPreset isEqualToString:@"builtin.nexus-signature"],
               @"version / preset");
    }

    error = nil;
    NCHECK(![HaloNexusDefinition definitionAtPath:[gFixtureDir stringByAppendingPathComponent:@"missing.plist"] error:&error] &&
               [error containsString:@"not installed"],
           @"missing file: %@", error);

    typedef void (^Mutate)(NSMutableDictionary *);
    NSDictionary<NSString *, Mutate> *broken = @{
        @"wrong schema" : ^(NSMutableDictionary *d) { d[@"schema"] = @"com.example.other"; },
        @"schema version 2" : ^(NSMutableDictionary *d) { d[@"schemaVersion"] = @2; },
        @"interface version 2" : ^(NSMutableDictionary *d) { d[@"interfaceVersion"] = @2; },
        @"unknown key" : ^(NSMutableDictionary *d) { d[@"script"] = @"rm -rf /"; },
        @"missing anchors" : ^(NSMutableDictionary *d) { [d removeObjectForKey:@"anchors"]; },
        @"radius out of range" : ^(NSMutableDictionary *d) {
            d[@"shape"] = @{@"kind" : @"rounded-rect", @"cornerRadius" : @500, @"cornerCurve" : @"continuous"};
        },
        @"radius wrong type" : ^(NSMutableDictionary *d) {
            d[@"shape"] = @{@"kind" : @"rounded-rect", @"cornerRadius" : @"22", @"cornerCurve" : @"continuous"};
        },
        @"unknown shape" : ^(NSMutableDictionary *d) {
            d[@"shape"] = @{@"kind" : @"star", @"cornerRadius" : @22, @"cornerCurve" : @"continuous"};
        },
        @"glow margin too large" : ^(NSMutableDictionary *d) {
            d[@"anchors"] = @{@"host" : @"panel", @"outset" : @2, @"glowMargin" : @400, @"clipInterior" : @YES};
        },
        @"unknown capability" : ^(NSMutableDictionary *d) { d[@"capabilities"] = @[ @"live-geometry", @"execute" ]; },
        @"older Nexus" : ^(NSMutableDictionary *d) { d[@"nexusVersion"] = @"0.2.1~beta1"; },
        @"bad version text" : ^(NSMutableDictionary *d) { d[@"nexusVersion"] = @"../../etc"; },
        @"wrong class" : ^(NSMutableDictionary *d) { d[@"interfaceClass"] = @"NSFileManager"; },
    };
    for (NSString *name in broken) {
        NSMutableDictionary *d = ValidDefinition(@"0.2.2~beta1");
        broken[name](d);
        NSString *path = WriteFixture(@"broken.plist", Encode(d, NSPropertyListXMLFormat_v1_0));
        error = nil;
        NCHECK(![HaloNexusDefinition definitionAtPath:path error:&error] && error.length, @"%@ accepted", name);
    }
    NSString *path = WriteFixture(@"garbage.plist", [@"<plist><dict><key>x" dataUsingEncoding:NSUTF8StringEncoding]);
    NCHECK(![HaloNexusDefinition definitionAtPath:path error:&error], @"malformed plist accepted");
    path = WriteFixture(@"array.plist", Encode(@[ @1 ], NSPropertyListXMLFormat_v1_0));
    NCHECK(![HaloNexusDefinition definitionAtPath:path error:&error], @"non-dictionary accepted");
    NSMutableData *huge = [NSMutableData dataWithLength:64 * 1024];
    path = WriteFixture(@"huge.plist", huge);
    NCHECK(![HaloNexusDefinition definitionAtPath:path error:&error], @"oversized file accepted");
    NCHECK(![HaloNexusDefinition definitionAtPath:gFixtureDir error:&error], @"directory accepted");

    NCHECK([HaloNexusDefinition compareVersion:@"0.2.2~beta1" to:@"0.3.0"] < 0, @"~ sorts before release");
    NCHECK([HaloNexusDefinition compareVersion:@"0.2.2~beta2" to:@"0.2.2~beta1"] > 0, @"beta2 > beta1");
    NCHECK([HaloNexusDefinition compareVersion:@"0.10.0" to:@"0.9.9"] > 0, @"numeric compare");
    NCHECK([HaloNexusDefinition compareVersion:@"0.2.2~beta1" to:@"0.2.2~beta1"] == 0, @"equal");

    NSString *jb = @"/private/preboot/ABC/jb-XYZ/procursus";
    NCHECK([[HaloNexusLink definitionPathFromImagePath:[jb stringByAppendingString:@"/usr/lib/TweakInject/HCGHalo.dylib"]]
               isEqualToString:[jb stringByAppendingString:@"/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist"]],
           @"jbroot from TweakInject path");
    NCHECK([[HaloNexusLink definitionPathFromImagePath:@"/var/jb/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib"]
               isEqualToString:@"/var/jb/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist"],
           @"jbroot from /var/jb");
    NCHECK([HaloNexusLink definitionPathFromImagePath:@"/usr/lib/libobjc.dylib"] == nil, @"unrelated image");
}

#pragma mark - Panel border view

static HaloNexusDefinition *LoadValid(NSString *version) {
    NSString *path = WriteFixture(@"definition.plist", Encode(ValidDefinition(version), NSPropertyListXMLFormat_v1_0));
    return [HaloNexusDefinition definitionAtPath:path error:nil];
}

static BOOL LayerHasAnimation(CALayer *layer, NSString *key) {
    return [layer animationForKey:key] != nil;
}

static void TestPanelBorderView(void) {
    HaloNexusDefinition *def = LoadValid(@"0.2.2~beta1");
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 414, 896)];
    window.hidden = NO;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(40, 100, 320, 480)];
    UIView *host = [[UIView alloc] initWithFrame:panel.bounds];
    [panel addSubview:host];
    [window addSubview:panel];

    HaloPanelBorderView *v = [[HaloPanelBorderView alloc] initWithDefinition:def];
    HaloAppearance a = [HaloPreferences nexusSignatureAppearance];
    HaloRenderPlan plan = halo_render_plan(a.mode, 0, 0, HaloLowPowerStatic);
    [v setAppearance:a plan:plan reduceTransparency:NO];
    [v attachToHostView:host];
    NCHECK(v.superview == host, @"attached to the host");
    NCHECK(CGRectEqualToRect(v.frame, CGRectInset(host.bounds, -36, -36)), @"frame = host ± glow margin: %@",
           NSStringFromCGRect(v.frame));
    NCHECK(!v.userInteractionEnabled && [v hitTest:CGPointMake(50, 50) withEvent:nil] == nil &&
               ![v pointInside:CGPointMake(50, 50) withEvent:nil],
           @"never interactive");
    NCHECK(v.accessibilityElementsHidden && !v.isAccessibilityElement, @"hidden from accessibility");
    // A button inside the panel still receives the touch.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 320, 60);
    [panel insertSubview:button belowSubview:host];
    host.userInteractionEnabled = NO;
    UIView *hit = [panel hitTest:CGPointMake(10, 10) withEvent:nil];
    NCHECK(hit == button, @"panel control receives the touch, got %@", hit);
    [button removeFromSuperview];

    // Interior masked out (even-odd): a point inside the panel is not drawn,
    // a point in the ring around it is.
    CAShapeLayer *mask = (CAShapeLayer *)v.layer.mask;
    NCHECK([mask isKindOfClass:[CAShapeLayer class]] && [mask.fillRule isEqualToString:kCAFillRuleEvenOdd], @"interior mask");
    CGPoint interior = CGPointMake(36 + 160, 36 + 240), ring = CGPointMake(36 - 3, 36 + 240);
    NCHECK(!CGPathContainsPoint(mask.path, NULL, interior, true) && CGPathContainsPoint(mask.path, NULL, ring, true),
           @"mask excludes the panel interior and keeps the edge ring");
    double panelPerimeter = 2 * (320 + 480) - 8 * 22 + 2 * M_PI * 22;
    NCHECK(v.renderer.layerCount > 0 && v.renderer.perimeter > panelPerimeter && v.renderer.perimeter < panelPerimeter + 60,
           @"line runs just outside the panel edge: %.1f vs %.1f", v.renderer.perimeter, panelPerimeter);

    // Live geometry: the host resizes (keyboard, rotation) -> the border follows.
    host.frame = CGRectMake(0, 0, 320, 300);
    [v relayout];
    NCHECK(CGRectEqualToRect(v.frame, CGRectInset(host.bounds, -36, -36)), @"follows host resize");
    v.panelCornerRadius = 30;
    NCHECK(v.renderer.perimeter > 0, @"live corner radius");

    // Effects.
    [v playOpeningTraceWithDuration:0.34];
    NCHECK(v.tracing, @"opening trace running");
    [v cancelOpeningTrace];
    NCHECK(!v.tracing, @"trace cancelled (reversed / cancelled transition)");
    [v playWorkspacePulseReducedMotion:NO];
    __block BOOL pulse = NO;
    for (CALayer *l in v.layer.sublayers) pulse |= LayerHasAnimation(l, @"halo.workspace-pulse");
    NCHECK(pulse, @"workspace pulse animation");

    // Reduce Transparency: no glow layers' shadow.
    [v setAppearance:a plan:plan reduceTransparency:YES];
    NCHECK(v.renderer.layerCount > 0, @"reduce transparency still draws the line");

    // Inactive: hidden and frozen.
    v.active = NO;
    NCHECK(v.hidden && v.renderer.paused, @"inactive -> hidden, paused");
    v.active = YES;
    NCHECK(!v.hidden, @"active again");
    HaloRenderPlan hidden = halo_render_plan(a.mode, 0, 1, HaloLowPowerHide);
    [v setAppearance:a plan:hidden reduceTransparency:NO];
    NCHECK(v.hidden && v.renderer.paused, @"Low Power: Hide Border");

    [v teardown];
    NCHECK(v.superview == nil && host.subviews.count == 0, @"teardown removes the view");
    window.hidden = YES;
}

#pragma mark - Test double of the Nexus interface (registered at run time)

static NSInteger gDoubleVersion = 1;
static NSString *gDoublePath;
static id gDoubleActive;

@interface HaloNexusInterfaceDouble : NSObject
@property (nonatomic, copy) NSString *nexusVersion;
@property (nonatomic, weak) UIView *borderHostView;
@property (nonatomic) CGFloat panelCornerRadius;
@property (nonatomic, copy) NSString *panelState;
@property (nonatomic) NSTimeInterval transitionDuration;
@property (nonatomic) BOOL reducedMotionTransition;
@property (nonatomic) NSUInteger generation;
@end

@implementation HaloNexusInterfaceDouble
+ (NSInteger)interfaceVersion {
    return gDoubleVersion;
}
+ (id)activeInterface {
    return gDoubleActive;
}
+ (NSString *)borderDefinitionPath {
    return gDoublePath;
}
- (void)post:(NSString *)event duration:(NSTimeInterval)duration {
    if ([event isEqualToString:@"will-open"]) self.panelState = @"opening", self.generation++;
    if ([event isEqualToString:@"did-open"]) self.panelState = @"open";
    if ([event isEqualToString:@"will-close"]) self.panelState = @"closing", self.generation++;
    if ([event isEqualToString:@"did-close"]) self.panelState = @"closed";
    self.transitionDuration = duration;
    [[NSNotificationCenter defaultCenter] postNotificationName:HaloNexusBorderEventNotification
                                                        object:self
                                                      userInfo:@{
                                                          @"event" : event,
                                                          @"generation" : @(self.generation),
                                                          @"duration" : @(duration),
                                                          @"interfaceVersion" : @1,
                                                      }];
}
@end

static Class gInterfaceClass;

static HaloSettings *Settings(NSDictionary *extra) {
    NSMutableDictionary *d = [@{HaloKeyEnabled : @YES, HaloKeyTarget : @"nexus"} mutableCopy];
    [d addEntriesFromDictionary:extra];
    return [HaloPreferences settingsFromDictionary:d];
}

static void Apply(HaloNexusLink *link, HaloSettings *s, BOOL enabled, BOOL screenOn) {
    [link applySettings:s enabled:enabled reduceMotion:NO lowPowerMode:NO reduceTransparency:NO screenOn:screenOn];
}

static void TestLink(void) {
    HaloNexusLink *link = [[HaloNexusLink alloc] init];
    HaloSettings *s = Settings(@{});

    // 1. Nexus absent: no class registered under the interface name.
    NCHECK(NSClassFromString(@"HCGNexusBorderInterface") == Nil, @"precondition: no interface class yet");
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable] && [link.detail hasPrefix:@"Requires compatible HCG Nexus"],
           @"absent: %@ / %@", link.state, link.detail);
    NCHECK(link.borderView == nil, @"absent: nothing drawn");

    // 2. Halo disabled / target excludes the panel.
    Apply(link, s, NO, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateOff], @"disabled -> off");

    // Register the double under the real class name (cannot be undone; the
    // remaining cases change its behaviour instead).
    gInterfaceClass = objc_allocateClassPair([HaloNexusInterfaceDouble class], "HCGNexusBorderInterface", 0);
    objc_registerClassPair(gInterfaceClass);

    // 3. Incompatible interface version.
    gDoubleVersion = 2;
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable] && [link.detail containsString:@"interface 2"],
           @"interface 2: %@", link.detail);
    gDoubleVersion = 1;

    // 4. Definition missing, then malformed.
    gDoublePath = [gFixtureDir stringByAppendingPathComponent:@"nope.plist"];
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable], @"missing definition: %@", link.detail);
    NSMutableDictionary *bad = ValidDefinition(@"0.2.2~beta1");
    bad[@"schemaVersion"] = @9;
    gDoublePath = WriteFixture(@"link.plist", Encode(bad, NSPropertyListXMLFormat_v1_0));
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable] && [link.detail containsString:@"Incompatible"],
           @"malformed definition: %@", link.detail);

    // 5. Valid definition, panel not built yet.
    gDoublePath = WriteFixture(@"link.plist", Encode(ValidDefinition(@"0.2.2~beta1"), NSPropertyListXMLFormat_v1_0));
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateWaiting], @"waiting: %@ %@", link.state, link.detail);

    // 6. Panel built, but the running Nexus is a different version (updated, no respring).
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(20, 80, 340, 520)];
    UIView *host = [[UIView alloc] initWithFrame:panel.bounds];
    [panel addSubview:host];
    HaloNexusInterfaceDouble *nexus = [[gInterfaceClass alloc] init];
    nexus.nexusVersion = @"0.2.2~beta0";
    nexus.borderHostView = host;
    nexus.panelCornerRadius = 22;
    nexus.panelState = @"closed";
    gDoubleActive = nexus;
    Apply(link, s, YES, YES);
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable] && [link.detail containsString:@"Respring"],
           @"version mismatch: %@", link.detail);
    NCHECK(host.subviews.count == 0, @"nothing attached on mismatch");

    // 7. Compatible: attached, hidden while the panel is closed.
    nexus.nexusVersion = @"0.2.2~beta1";
    [nexus post:@"installed" duration:0];
    NCHECK([link.state isEqualToString:HaloNexusLinkStateAttached], @"attached after 'installed': %@", link.detail);
    HaloPanelBorderView *border = link.borderView;
    NCHECK(border.superview == host && host.subviews.count == 1, @"border inside the live host");
    NCHECK(border.hidden && border.renderer.paused, @"closed panel -> hidden, paused");

    // 8. Opening: visible, trace plays; did-open settles.
    [nexus post:@"will-open" duration:0.34];
    NCHECK(!border.hidden && border.tracing, @"will-open -> visible + trace");
    [nexus post:@"did-open" duration:0.34];
    NCHECK(!border.hidden, @"open");

    // 9. Forged and malformed events are ignored.
    HaloNexusInterfaceDouble *impostor = [[gInterfaceClass alloc] init];
    [impostor post:@"did-close" duration:0];
    NCHECK(!border.hidden, @"event from a non-active interface ignored");
    [[NSNotificationCenter defaultCenter] postNotificationName:HaloNexusBorderEventNotification object:@"x"
                                                      userInfo:@{@"event" : @"did-close"}];
    NCHECK(!border.hidden, @"event from a non-interface sender ignored");
    NSString *reason = nil;
    NSArray *malformed = @[
        @{@"event" : @"did-close", @"generation" : @1, @"duration" : @99, @"interfaceVersion" : @1},
        @{@"event" : @"did-close", @"generation" : @1, @"duration" : @0, @"interfaceVersion" : @2},
        @{@"event" : @"explode", @"generation" : @1, @"duration" : @0, @"interfaceVersion" : @1},
        @{@"event" : @7, @"generation" : @1, @"duration" : @0, @"interfaceVersion" : @1},
        @{@"event" : @"did-close", @"duration" : @0, @"interfaceVersion" : @1},
        @{@"event" : @"did-close", @"generation" : @1, @"duration" : @(NAN), @"interfaceVersion" : @1},
    ];
    for (NSDictionary *info in malformed) {
        NSNotification *note = [NSNotification notificationWithName:HaloNexusBorderEventNotification object:nexus userInfo:info];
        NCHECK([HaloNexusLink validatedEventFromNotification:note expectedInterface:nexus reason:&reason] == nil,
               @"malformed accepted: %@", info);
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
    NCHECK(!border.hidden, @"malformed events changed nothing");
    NSNotification *good = [NSNotification notificationWithName:HaloNexusBorderEventNotification object:nexus
                                                        userInfo:@{@"event" : @"geometry", @"generation" : @1, @"duration" : @0,
                                                                   @"interfaceVersion" : @1}];
    NCHECK([[HaloNexusLink validatedEventFromNotification:good expectedInterface:nexus reason:&reason] isEqualToString:@"geometry"],
           @"well-formed event accepted: %@", reason);

    // 10. Geometry and workspace events.
    host.frame = CGRectMake(0, 0, 340, 300);
    [nexus post:@"geometry" duration:0];
    NCHECK(CGRectEqualToRect(border.frame, CGRectInset(host.bounds, -36, -36)), @"geometry event -> relayout");
    [nexus post:@"workspace-changed" duration:0];
    __block BOOL pulse = NO;
    for (CALayer *l in border.layer.sublayers) pulse |= [l animationForKey:@"halo.workspace-pulse"] != nil;
    NCHECK(pulse, @"workspace pulse");

    // 11. Reversed opening (open → close before it finishes): trace stops.
    [nexus post:@"did-close" duration:0];
    [nexus post:@"will-open" duration:0.34];
    NCHECK(border.tracing, @"tracing");
    [nexus post:@"will-close" duration:0.34];
    NCHECK(!border.tracing && !border.hidden, @"reversal cancels the trace; border fades with the panel");
    [nexus post:@"did-close" duration:0];
    NCHECK(border.hidden && border.renderer.paused, @"did-close -> hidden, paused");

    // 12. Fade With Panel off: hidden as soon as closing starts.
    Apply(link, Settings(@{HaloKeyNexusCloseFade : @NO}), YES, YES);
    [nexus post:@"will-open" duration:0.34];
    [nexus post:@"did-open" duration:0.34];
    [nexus post:@"will-close" duration:0.34];
    NCHECK(link.borderView.hidden, @"close fade off -> hidden at will-close");
    [nexus post:@"did-close" duration:0];

    // 13. Opening trace off / Reduce Motion: no trace.
    Apply(link, Settings(@{HaloKeyNexusOpenTrace : @NO}), YES, YES);
    [nexus post:@"will-open" duration:0.34];
    NCHECK(!link.borderView.tracing && !link.borderView.hidden, @"trace off");
    [nexus post:@"did-close" duration:0];
    [link applySettings:s enabled:YES reduceMotion:YES lowPowerMode:NO reduceTransparency:NO screenOn:YES];
    [nexus post:@"will-open" duration:0.18];
    NCHECK(!link.borderView.tracing, @"Reduce Motion: no trace");
    [nexus post:@"did-open" duration:0.18];

    // 14. Screen off: hidden and frozen; back on: visible.
    [link setScreenOn:NO];
    NCHECK(link.borderView.hidden && link.borderView.renderer.paused, @"screen off");
    [link setScreenOn:YES];
    NCHECK(!link.borderView.hidden, @"screen on");

    // 15. Halo disabled while the panel is open: removed immediately.
    Apply(link, s, NO, YES);
    NCHECK(link.borderView == nil && host.subviews.count == 0 && [link.state isEqualToString:HaloNexusLinkStateOff],
           @"disable removes the border at once");
    Apply(link, s, YES, YES);
    NCHECK(link.borderView.superview == host && !link.borderView.hidden, @"re-enable re-attaches to the open panel");

    // 16. Repeated open/close: one view, no leftovers.
    for (int i = 0; i < 60; i++) {
        [nexus post:@"will-close" duration:0.34];
        [nexus post:@"did-close" duration:0];
        [nexus post:@"will-open" duration:0.34];
        if (i % 3 == 0) [nexus post:@"workspace-changed" duration:0];
        if (i % 4 == 0) [nexus post:@"will-close" duration:0.34]; // gesture reversed
        else [nexus post:@"did-open" duration:0.34];
    }
    NCHECK(host.subviews.count == 1, @"one border view after 60 cycles (%lu)", (unsigned long)host.subviews.count);
    [nexus post:@"did-close" duration:0];

    // 17. Nexus updated on disk (definition now describes another version) and
    //     the panel re-installed: the new file is re-read and refused until respring.
    gDoublePath = WriteFixture(@"link.plist", Encode(ValidDefinition(@"0.3.1~beta1"), NSPropertyListXMLFormat_v1_0));
    [nexus post:@"installed" duration:0];
    NCHECK([link.state isEqualToString:HaloNexusLinkStateUnavailable] && host.subviews.count == 0,
           @"updated Nexus without respring -> unavailable, border removed: %@", link.detail);
    nexus.nexusVersion = @"0.3.1~beta1"; // after a respring the running version matches
    [nexus post:@"installed" duration:0];
    NCHECK([link.state isEqualToString:HaloNexusLinkStateAttached], @"respring -> attached again");

    // 18. Interface removed (Nexus tears its panel down).
    gDoubleActive = nil;
    [nexus post:@"removed" duration:0];
    NCHECK(link.borderView == nil && host.subviews.count == 0 && [link.state isEqualToString:HaloNexusLinkStateWaiting],
           @"removed -> detached, waiting");

    // 19. Host view deallocated with the panel: no orphan, link survives.
    gDoubleActive = nexus;
    @autoreleasepool {
        UIView *temporary = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        nexus.borderHostView = temporary;
        [nexus post:@"installed" duration:0];
        NCHECK(link.borderView.superview == temporary, @"attached to temporary host");
        temporary = nil;
    }
    Apply(link, s, YES, YES);
    NCHECK(![link.state isEqualToString:HaloNexusLinkStateAttached], @"no attachment to a released host: %@", link.state);

    [link stop];
    NCHECK([link.state isEqualToString:HaloNexusLinkStateOff] && link.borderView == nil, @"stop");
    gDoubleActive = nil;
}

#pragma mark - Preferences (Nexus lighting)

static void TestNexusPreferences(void) {
    HaloSettings *defaults = [HaloPreferences settingsFromDictionary:@{}];
    NCHECK(defaults.target == HaloTargetScreen && defaults.targetsScreen && !defaults.targetsNexus,
           @"default target is the screen edge");
    NCHECK(defaults.nexusOpenTrace && defaults.nexusCloseFade && defaults.nexusWorkspacePulse && !defaults.nexusMatchScreen,
           @"effect defaults");
    HaloAppearance sig = [HaloPreferences nexusSignatureAppearance];
    NCHECK(defaults.nexusAppearance.mode == sig.mode && defaults.nexusAppearance.colourCount == sig.colourCount,
           @"Nexus Signature is the default panel look");
    HaloSettings *junk = [HaloPreferences settingsFromDictionary:@{HaloKeyTarget : @"moon", HaloKeyNexusAppearance : @"x"}];
    NCHECK(junk.target == HaloTargetScreen && junk.nexusAppearance.mode == sig.mode, @"invalid values fall back");
    HaloSettings *both = [HaloPreferences settingsFromDictionary:@{HaloKeyTarget : @"both"}];
    NCHECK(both.targetsScreen && both.targetsNexus, @"both");
    HaloSettings *match = [HaloPreferences settingsFromDictionary:@{HaloKeyNexusMatchScreen : @YES, HaloKeyMode : @"orbit"}];
    NCHECK(match.effectiveNexusAppearance.mode == HaloModeOrbit, @"match screen edge");
    for (NSString *identifier in @[ @"builtin.nexus-signature", @"builtin.reactor", @"builtin.hologram" ])
        NCHECK([HaloPreferences presetWithIdentifier:identifier] != nil, @"preset %@", identifier);
    HaloAppearance reactor = [HaloPreferences appearanceFromDictionary:
                                                  [HaloPreferences presetWithIdentifier:@"builtin.reactor"][HaloPresetKeyAppearance]];
    NCHECK(reactor.mode == HaloModeOrbit && reactor.pulseDepth > 0, @"Reactor: travelling segments + soft pulse");
}

int HaloRunNexusTests(long *checks, long *failures) {
    gFixtureDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"halo-nexus-tests"];
    [[NSFileManager defaultManager] createDirectoryAtPath:gFixtureDir withIntermediateDirectories:YES attributes:nil error:nil];
    TestDefinition();
    TestPanelBorderView();
    TestLink();
    TestNexusPreferences();
    [[NSFileManager defaultManager] removeItemAtPath:gFixtureDir error:nil];
    *checks += gNexusChecks;
    *failures += gNexusFailures;
    printf("Nexus panel border: %ld checks, %ld failed\n", gNexusChecks, gNexusFailures);
    return gNexusFailures == 0;
}
