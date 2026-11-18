//
//  test_runtime.m
//  HCG Halo — runtime tests for the Objective-C layer, run in the iOS
//  Simulator by CI (scripts/run-simulator-tests.sh). No SpringBoard: this
//  checks the renderer's layer trees and animations, the overlay's touch and
//  accessibility behaviour, and preferences / presets through real
//  CFPreferences. It does NOT show that anything works inside SpringBoard on
//  a device.
//

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#import "HaloConfig.h"
#import "HaloGeometry.h"
#import "HaloOverlayView.h"
#import "HaloPreferences.h"
#import "HaloProfiles.h"
#import "HaloRenderer.h"

#include <math.h>

static long gChecks = 0, gFailures = 0;

#define CHECK(cond, ...)                                                          \
    do {                                                                          \
        gChecks++;                                                                \
        if (!(cond)) {                                                            \
            gFailures++;                                                          \
            fprintf(stderr, "FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond);      \
            fprintf(stderr, "%s\n", [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); \
        }                                                                         \
    } while (0)

static void Walk(CALayer *layer, void (^visit)(CALayer *)) {
    visit(layer);
    for (CALayer *sub in layer.sublayers) Walk(sub, visit);
    if (layer.mask) Walk(layer.mask, visit);
}

static NSCountedSet *AnimationKeys(CALayer *root) {
    NSCountedSet *keys = [NSCountedSet set];
    Walk(root, ^(CALayer *l) {
        for (NSString *key in l.animationKeys) [keys addObject:key];
    });
    return keys;
}

static HaloDisplayGeometry Geometry11ProMax(void) {
    HaloCalibration zero = {0, 0, 0, 0};
    return halo_profile_geometry(halo_profile_find("iphone-11-pro-max"), zero);
}

#pragma mark - Renderer

static void TestRendererModes(void) {
    HaloDisplayGeometry g = Geometry11ProMax();
    CGRect bounds = CGRectMake(0, 0, 414, 896);
    const char *styles[] = {"single", "multi", "gradient"};
    for (int m = 0; m < HaloModeCount; m++) {
        for (int st = 0; st < HaloColourStyleCount; st++) {
            HaloAppearance a = halo_default_appearance();
            a.mode = (HaloMode)m;
            a.colourStyle = (HaloColourStyle)st;
            a.segments = 3;
            HaloRenderer *r = [[HaloRenderer alloc] initWithContentsScale:3];
            [r setGeometry:g traceCutout:YES transform:CGAffineTransformIdentity unitScale:1 bounds:bounds];
            HaloRenderPlan plan = halo_render_plan(a.mode, 0, 0, HaloLowPowerStatic);
            [r setAppearance:a plan:plan];
            NSString *label = [NSString stringWithFormat:@"%s/%s", halo_mode_id(a.mode), styles[st]];

            HaloBorderPath path;
            halo_build_border(&g, a.inset + a.thickness / 2, 1, &path);
            CHECK(r.layerCount > 0 && fabs(r.perimeter - path.length) < 1e-6, @"%@: layers %lu perimeter %.3f", label,
                  (unsigned long)r.layerCount, r.perimeter);
            CHECK(CGRectEqualToRect(r.layer.frame, bounds), @"%@: root frame", label);
            CHECK(fabs(r.layer.opacity - a.brightness) < 1e-6, @"%@: brightness -> opacity", label);

            __block BOOL anyMask = NO, scaleOK = YES, anyGradient = NO;
            __block NSUInteger shapes = 0;
            __block NSMutableArray<CAShapeLayer *> *dashed = [NSMutableArray array];
            Walk(r.layer, ^(CALayer *l) {
                if (l.mask) anyMask = YES;
                if ([l isKindOfClass:[CAGradientLayer class]]) anyGradient = YES;
                if ([l isKindOfClass:[CAShapeLayer class]]) {
                    shapes++;
                    if (l.contentsScale != 3) scaleOK = NO;
                    CAShapeLayer *s = (CAShapeLayer *)l;
                    if (s.lineDashPattern.count == 2) [dashed addObject:s];
                }
            });
            BOOL gradientExpected = st != HaloColourSingle || m == HaloModeFlow; // a single colour flows as a band
            CHECK(anyMask == gradientExpected && anyGradient == gradientExpected, @"%@: mask %d gradient %d", label, anyMask,
                  anyGradient);
            CHECK(scaleOK && shapes > 0, @"%@: every shape layer at screen scale", label);

            NSCountedSet *keys = AnimationKeys(r.layer);
            switch (m) {
            case HaloModeStatic:
                CHECK(keys.count == 0, @"%@: static has no animations (%@)", label, keys);
                break;
            case HaloModeBreathing:
                CHECK([r.layer animationForKey:@"halo.breathe"] != nil && keys.count == 1, @"%@: breathing %@", label, keys);
                break;
            case HaloModeFlow:
                CHECK([keys countForObject:@"halo.flow"] == 1 && keys.count == 1, @"%@: flow %@", label, keys);
                break;
            case HaloModeOrbit: {
                CHECK([keys countForObject:@"halo.phase"] >= 3, @"%@: orbit phase animations %@", label, keys);
                for (CAShapeLayer *s in dashed) {
                    double period = [s.lineDashPattern[0] doubleValue] + [s.lineDashPattern[1] doubleValue];
                    CHECK(fabs(period * a.segments - path.length) < 1e-3, @"%@: orbit dash period %.3f x %d != %.3f", label,
                          period, a.segments, path.length);
                    CABasicAnimation *anim = (CABasicAnimation *)[s animationForKey:@"halo.phase"];
                    double delta = [anim.toValue doubleValue] - [anim.fromValue doubleValue];
                    CHECK(fabs(delta + period) < 1e-6, @"%@: clockwise phase moves by -period (%.3f)", label, delta);
                    CHECK(anim.repeatCount == HUGE_VALF && !anim.removedOnCompletion, @"%@: repeats forever", label);
                }
                break;
            }
            case HaloModeCircuit:
                CHECK([keys countForObject:@"halo.phase"] >= 3, @"%@: circuit pulses %@", label, keys);
                CHECK([keys countForObject:@"halo.blink"] == (NSUInteger)path.landmarkCount, @"%@: one blinking node per landmark (%lu vs %d)",
                      label, (unsigned long)[keys countForObject:@"halo.blink"], path.landmarkCount);
                break;
            }

            // Static / Breathing rasterise the masked gradient once.
            if (gradientExpected && (m == HaloModeStatic || m == HaloModeBreathing)) {
                __block BOOL rasterised = NO;
                Walk(r.layer, ^(CALayer *l) {
                    if (l.mask && l.shouldRasterize && l.rasterizationScale == 3) rasterised = YES;
                });
                CHECK(rasterised, @"%@: masked subtree rasterised", label);
            }

            // Pause / resume / hide / teardown.
            [r setPaused:YES];
            CHECK(r.paused && r.layer.speed == 0, @"%@: paused freezes the clock", label);
            [r setPaused:NO];
            CHECK(!r.paused && r.layer.speed == 1, @"%@: resumed", label);
            HaloRenderPlan hidden = halo_render_plan(a.mode, 0, 1, HaloLowPowerHide);
            [r setAppearance:a plan:hidden];
            CHECK(r.layerCount == 0 && r.layer.sublayers.count == 0, @"%@: hidden plan draws nothing", label);
            [r setAppearance:a plan:plan];
            [r teardown];
            CHECK(r.layer.sublayers.count == 0 && r.layer.animationKeys.count == 0, @"%@: teardown clears", label);
        }
    }
}

static void TestRendererPlans(void) {
    HaloDisplayGeometry g = Geometry11ProMax();
    HaloAppearance a = halo_default_appearance();
    a.mode = HaloModeFlow;
    HaloRenderer *r = [[HaloRenderer alloc] initWithContentsScale:3];
    [r setGeometry:g traceCutout:YES transform:CGAffineTransformIdentity unitScale:1 bounds:CGRectMake(0, 0, 414, 896)];
    [r setAppearance:a plan:halo_render_plan(a.mode, 1, 0, HaloLowPowerStatic)];
    CHECK(AnimationKeys(r.layer).count == 0, @"Reduce Motion: no animations");
    [r setAppearance:a plan:halo_render_plan(a.mode, 0, 1, HaloLowPowerStatic)];
    CHECK(AnimationKeys(r.layer).count == 0, @"Low Power static: no animations");
    [r setAppearance:a plan:halo_render_plan(a.mode, 0, 1, HaloLowPowerAnimate)];
    CHECK(AnimationKeys(r.layer).count == 1, @"Low Power animate keeps the animation");

    // Counter-clockwise reverses travel.
    a.mode = HaloModeOrbit;
    a.clockwise = 0;
    [r setAppearance:a plan:halo_render_plan(a.mode, 0, 0, HaloLowPowerStatic)];
    __block int checked = 0;
    Walk(r.layer, ^(CALayer *l) {
        CABasicAnimation *anim = (CABasicAnimation *)[l animationForKey:@"halo.phase"];
        if (!anim) return;
        checked++;
        CHECK([anim.toValue doubleValue] > [anim.fromValue doubleValue], @"counter-clockwise phase increases");
    });
    CHECK(checked >= 3, @"counter-clockwise orbit animated");

    // Landscape: the path and gradient follow a 90° rotation into an 896 x 414 view.
    CGAffineTransform landscape = CGAffineTransformMake(0, 1, -1, 0, 896, 0); // fixed (x,y) -> (896 - y, x)
    a.mode = HaloModeFlow;
    a.clockwise = 1;
    [r setGeometry:g traceCutout:YES transform:landscape unitScale:1 bounds:CGRectMake(0, 0, 896, 414)];
    [r setAppearance:a plan:halo_render_plan(a.mode, 0, 0, HaloLowPowerStatic)];
    __block CAShapeLayer *core = nil;
    __block CAGradientLayer *gradient = nil;
    Walk(r.layer, ^(CALayer *l) {
        if ([l isKindOfClass:[CAGradientLayer class]]) gradient = (CAGradientLayer *)l;
        if ([l isKindOfClass:[CAShapeLayer class]] && !core) core = (CAShapeLayer *)l;
    });
    CGRect box = CGPathGetPathBoundingBox(core.path);
    CHECK(CGRectGetWidth(box) > CGRectGetHeight(box) && CGRectContainsRect(CGRectInset(CGRectMake(0, 0, 896, 414), -0.01, -0.01), box),
          @"landscape path fits the rotated view: %@", NSStringFromCGRect(box));
    CHECK(fabs(atan2(gradient.affineTransform.b, gradient.affineTransform.a) - M_PI / 2) < 1e-6,
          @"gradient rotated with the display");
    // Notch on the physical top edge = the right-hand side of this landscape view.
    HaloBorderPath path;
    halo_build_border(&g, a.inset + a.thickness / 2, 1, &path);
    double fx, fy;
    halo_point_at(&path, 0, &fx, &fy); // bottom-centre of the notch dip, in fixed space
    CGPoint p = CGPointApplyAffineTransform(CGPointMake(fx, fy), landscape);
    CHECK(p.x > 896 - 40 && fabs(p.y - 207) < 1, @"notch maps to the right edge in landscape: %@", NSStringFromCGPoint(p));

    // Preview scale: dash maths follow the path scale, widths the unit scale.
    a.mode = HaloModeOrbit;
    a.segments = 2;
    CGFloat s = 0.2f;
    [r setGeometry:g traceCutout:YES transform:CGAffineTransformMakeScale(s, s) unitScale:0.48f bounds:CGRectMake(0, 0, 414 * s, 896 * s)];
    [r setAppearance:a plan:halo_render_plan(a.mode, 0, 0, HaloLowPowerStatic)];
    Walk(r.layer, ^(CALayer *l) {
        if (![l isKindOfClass:[CAShapeLayer class]] || ((CAShapeLayer *)l).lineDashPattern.count != 2) return;
        NSArray *d = ((CAShapeLayer *)l).lineDashPattern;
        double period = [d[0] doubleValue] + [d[1] doubleValue];
        CHECK(fabs(period * 2 - path.length * s) < 1e-3, @"preview dash period follows the path scale");
    });
}

#pragma mark - Overlay

static void TestOverlay(void) {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 414, 896)];
    UIButton *target = [UIButton buttonWithType:UIButtonTypeSystem];
    target.frame = container.bounds;
    [container addSubview:target];
    UIView *edgeTarget = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 414, 20)];
    [container addSubview:edgeTarget];
    HaloOverlayView *overlay = [[HaloOverlayView alloc] initWithFrame:container.bounds];
    [container addSubview:overlay]; // on top, exactly as in SpringBoard

    CHECK(!overlay.userInteractionEnabled, @"overlay ignores touches");
    CHECK(overlay.gestureRecognizers.count == 0, @"overlay has no gesture recognisers");
    CHECK(!overlay.isAccessibilityElement && overlay.accessibilityElementsHidden, @"overlay hidden from accessibility");
    CHECK(overlay.layer.zPosition > 0, @"overlay draws above siblings");
    const CGPoint points[] = {{1, 1}, {207, 10}, {2, 448}, {412, 894}, {207, 448}};
    for (int i = 0; i < 5; i++) {
        CHECK([overlay hitTest:points[i] withEvent:nil] == nil && ![overlay pointInside:points[i] withEvent:nil],
              @"overlay never hit at %@", NSStringFromCGPoint(points[i]));
        UIView *hit = [container hitTest:points[i] withEvent:nil];
        CHECK(hit != nil && hit != overlay && ![hit isDescendantOfView:overlay],
              @"touch at %@ reaches %@, not the overlay", NSStringFromCGPoint(points[i]), hit);
    }
    CHECK([container hitTest:CGPointMake(207, 10) withEvent:nil] == edgeTarget, @"edge touches reach the edge view");

    [overlay setVisible:NO animating:YES];
    CHECK(overlay.hidden, @"invisible overlay hidden");
    [overlay setVisible:YES animating:NO];
    CHECK(!overlay.hidden, @"visible overlay shown");
    [overlay teardown];
    [overlay removeFromSuperview];
}

#pragma mark - Preferences and presets

static void ClearAll(void) {
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    for (NSString *key in [HaloPreferences allKeys]) all[key] = [NSNull null];
    [HaloPreferences writeValues:all];
}

static void TestPreferences(void) {
    ClearAll();
    HaloSettings *s = [HaloPreferences loadSettings];
    CHECK(!s.enabled, @"off by default");
    CHECK(s.appearance.mode == HaloModeStatic, @"static by default");
    CHECK([s.profileIdentifier isEqualToString:@"iphone-11-pro-max"] && s.profile && s.geometry.width == 414,
          @"default profile");

    [HaloPreferences writeValue:@"rainbow" forKey:HaloKeyMode];
    CHECK([[HaloPreferences readValueForKey:HaloKeyMode] isEqualToString:@"static"], @"invalid mode not stored");
    [HaloPreferences writeValue:@7 forKey:HaloKeyBrightness];
    CHECK([[HaloPreferences readValueForKey:HaloKeyBrightness] doubleValue] == 1.0, @"brightness clamped");
    [HaloPreferences writeValue:@"automatic" forKey:HaloKeyProfile];
    CHECK([[HaloPreferences readValueForKey:HaloKeyProfile] isEqualToString:@"iphone-11-pro-max"], @"automatic refused");
    [HaloPreferences writeValue:@"iphone-xs-max" forKey:HaloKeyProfile];
    CHECK([[HaloPreferences readValueForKey:HaloKeyProfile] isEqualToString:@"iphone-11-pro-max"], @"planned profile refused");
    [HaloPreferences writeValue:@[ @"#00e5ff", @"7b61ff" ] forKey:HaloKeyColours];
    CHECK([[HaloPreferences readValueForKey:HaloKeyColours] isEqualToArray:(@[ @"#00E5FF", @"#7B61FF" ])], @"colours normalised");
    [HaloPreferences writeValue:@[ @"#00E5FF", @"nope" ] forKey:HaloKeyColours];
    CHECK([[HaloPreferences readValueForKey:HaloKeyColours] count] == 3, @"bad colour list -> default");
    [HaloPreferences writeValue:@[ @"#000000", @"#000000", @"#000000", @"#000000", @"#000000", @"#000000", @"#000000" ]
                         forKey:HaloKeyColours];
    CHECK([[HaloPreferences readValueForKey:HaloKeyColours] count] == 3, @"7 colours -> default");
    [HaloPreferences writeValue:@2.6 forKey:HaloKeySegments];
    CHECK([[HaloPreferences readValueForKey:HaloKeySegments] integerValue] == 3, @"integer settings rounded");

    // Presets.
    ClearAll();
    [HaloPreferences writeValues:@{HaloKeyEnabled : @YES, HaloKeyCalCornerRadius : @3, HaloKeyLowPower : @"hide"}];
    NSString *mine = [HaloPreferences saveCurrentAppearanceAsPresetNamed:@"  Mine  "];
    CHECK(mine.length && [[HaloPreferences presetWithIdentifier:mine][HaloPresetKeyName] isEqualToString:@"Mine"], @"save trims name");
    CHECK([HaloPreferences saveCurrentAppearanceAsPresetNamed:@"   "] == nil, @"empty name refused");
    NSString *mine2 = [HaloPreferences saveCurrentAppearanceAsPresetNamed:@"mine"];
    CHECK([[HaloPreferences presetWithIdentifier:mine2][HaloPresetKeyName] isEqualToString:@"mine 2"], @"unique names");
    CHECK([HaloPreferences renamePreset:mine to:@"Night"], @"rename");
    CHECK([[HaloPreferences presetWithIdentifier:mine][HaloPresetKeyName] isEqualToString:@"Night"], @"renamed");
    NSString *copy = [HaloPreferences duplicatePreset:mine];
    CHECK([[HaloPreferences presetWithIdentifier:copy][HaloPresetKeyName] isEqualToString:@"Night Copy"], @"duplicate");
    NSString *builtinCopy = [HaloPreferences duplicatePreset:@"builtin.orbit"];
    CHECK(builtinCopy && ![HaloPreferences isBuiltInPreset:builtinCopy], @"built-in duplicates become user presets");
    CHECK(![HaloPreferences renamePreset:@"builtin.orbit" to:@"x"] && ![HaloPreferences deletePreset:@"builtin.orbit"],
          @"built-ins cannot be renamed or deleted");
    CHECK([HaloPreferences deletePreset:mine2] && ![HaloPreferences presetWithIdentifier:mine2], @"delete");
    CHECK([HaloPreferences userPresets].count == 3, @"three user presets remain");

    CHECK([HaloPreferences applyPreset:@"builtin.orbit"], @"apply built-in");
    s = [HaloPreferences loadSettings];
    CHECK(s.appearance.mode == HaloModeOrbit, @"preset applied");
    CHECK([[HaloPreferences matchingPresetIdentifier] isEqualToString:@"builtin.orbit"] ||
              [[HaloPreferences presetWithIdentifier:[HaloPreferences matchingPresetIdentifier]][HaloPresetKeyName]
                  hasPrefix:@"Twin Orbit"],
          @"current appearance matches the applied preset");
    CHECK(s.enabled && s.calibration.cornerRadius == 3 && s.lowPowerPolicy == HaloLowPowerHide &&
              [HaloPreferences userPresets].count == 3,
          @"applying a preset leaves the switch, calibration, Low Power policy and presets alone");

    [HaloPreferences resetAppearance];
    s = [HaloPreferences loadSettings];
    CHECK(s.appearance.mode == HaloModeStatic && s.enabled && s.calibration.cornerRadius == 3 &&
              [HaloPreferences userPresets].count == 3 && s.lowPowerPolicy == HaloLowPowerHide,
          @"Reset Appearance keeps unrelated preferences");
    [HaloPreferences writeValue:@"circuit" forKey:HaloKeyMode];
    [HaloPreferences resetCalibration];
    s = [HaloPreferences loadSettings];
    CHECK(s.calibration.cornerRadius == 0 && s.appearance.mode == HaloModeCircuit && s.enabled,
          @"Reset Calibration keeps appearance and the switch");

    // Hand-edited preset list: invalid and built-in-prefixed entries dropped.
    [HaloPreferences writeValue:@[
        @{HaloPresetKeyID : @"builtin.fake", HaloPresetKeyName : @"x", HaloPresetKeyAppearance : @{}},
        @{HaloPresetKeyID : @"user.a", HaloPresetKeyName : @"", HaloPresetKeyAppearance : @{}},
        @{HaloPresetKeyID : @"user.b", HaloPresetKeyName : @"ok", HaloPresetKeyAppearance : @{HaloKeyMode : @"orbit"}},
        @"junk",
    ]
                         forKey:HaloKeyPresets];
    NSArray *presets = [HaloPreferences userPresets];
    CHECK(presets.count == 1 && [presets[0][HaloPresetKeyID] isEqualToString:@"user.b"], @"invalid presets dropped");

    [HaloPreferences writeStatus:@{HaloStatusKeyState : HaloEngineStateActive}];
    CHECK([[HaloPreferences readStatus][HaloStatusKeyState] isEqualToString:HaloEngineStateActive], @"status roundtrip");
    [HaloPreferences setConsecutiveUnstableLaunches:2];
    CHECK([HaloPreferences consecutiveUnstableLaunches] == 2, @"launch counter");
    [HaloPreferences setConsecutiveUnstableLaunches:0];
    ClearAll();
}

int HaloRunNexusTests(long *checks, long *failures); // test_nexus.m

int main(void) {
    @autoreleasepool {
        TestRendererModes();
        TestRendererPlans();
        TestOverlay();
        TestPreferences();
        HaloRunNexusTests(&gChecks, &gFailures);
    }
    if (gFailures) {
        printf("%ld of %ld runtime checks FAILED\n", gFailures, gChecks);
        return 1;
    }
    printf("All %ld runtime checks passed (renderer, overlay, preferences, HCG Nexus panel border; iOS Simulator)\n", gChecks);
    return 0;
}
