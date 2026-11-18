//
//  VortexPreferences.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexPreferences.h"
#import "VortexMath.h"

#include <math.h>
#include <notify.h>

NSString *const VortexPreferencesDomain = @VORTEX_BUNDLE_ID;
NSString *const VortexStatusDomain = @VORTEX_BUNDLE_ID ".status";
NSString *const VortexPreferencesChangedNotification = @VORTEX_BUNDLE_ID "/preferences-changed";
NSString *const VortexKillSwitchPath = @"/var/mobile/Library/Preferences/" VORTEX_BUNDLE_ID ".disabled";

NSString *const VortexKeyEnabled = @"enabled";
NSString *const VortexKeyPreset = @"preset";
NSString *const VortexKeySwipeLeftEffect = @"swipeLeftEffect";
NSString *const VortexKeySwipeRightEffect = @"swipeRightEffect";
NSString *const VortexKeyIncomingDirection = @"incomingDirection";
NSString *const VortexKeyOutgoingDirection = @"outgoingDirection";
NSString *const VortexKeyReverseAnimation = @"reverseAnimation";
NSString *const VortexKeyDuration = @"duration";
NSString *const VortexKeySpeed = @"speed";
NSString *const VortexKeyIntensity = @"intensity";
NSString *const VortexKeyEasing = @"easing";
NSString *const VortexKeyFadePages = @"fadePages";
NSString *const VortexKeyDiagnosticLogging = @"diagnosticLogging";
NSString *const VortexKeyTornadoPreset = @"tornadoPreset";
NSString *const VortexKeyTornadoIntensity = @"tornadoIntensity";
NSString *const VortexKeyTornadoRadius = @"tornadoRadius";
NSString *const VortexKeyTornadoTipRadius = @"tornadoTipRadius";
NSString *const VortexKeyTornadoHeight = @"tornadoHeight";
NSString *const VortexKeyTornadoRotations = @"tornadoRotations";
NSString *const VortexKeyTornadoDirection = @"tornadoDirection";
NSString *const VortexKeyTornadoTravel = @"tornadoTravel";
NSString *const VortexKeyTornadoDepth = @"tornadoDepth";
NSString *const VortexKeyTornadoIconSpin = @"tornadoIconSpin";
NSString *const VortexKeyOrbitalRadius = @"orbitalRadius";
NSString *const VortexKeyOrbitalRings = @"orbitalRings";
NSString *const VortexKeyOrbitalTilt = @"orbitalTilt";
NSString *const VortexKeyOrbitalSpeed = @"orbitalSpeed";
NSString *const VortexKeyOrbitalDirection = @"orbitalDirection";
NSString *const VortexKeyWarpIntensity = @"warpIntensity";
NSString *const VortexKeyWarpPerspective = @"warpPerspective";
NSString *const VortexKeyHoloDepth = @"holoDepth";
NSString *const VortexKeyHoloTilt = @"holoTilt";
NSString *const VortexKeyHoloLayers = @"holoLayers";
NSString *const VortexKeyCircuitTrail = @"circuitTrail";
NSString *const VortexKeyCircuitIntensity = @"circuitIntensity";
NSString *const VortexKeyMagneticStrength = @"magneticStrength";
NSString *const VortexKeyMagneticSnap = @"magneticSnap";
NSString *const VortexKeyAccentColor = @"accentColor";
NSString *const VortexKeyGlowIntensity = @"glowIntensity";

NSString *const VortexStatusKeyState = @"state";
NSString *const VortexStatusKeyDetail = @"detail";
NSString *const VortexStatusKeySystemVersion = @"systemVersion";
NSString *const VortexStatusKeyTweakVersion = @"tweakVersion";
NSString *const VortexStatusKeyTimestamp = @"timestamp";
NSString *const VortexStatusKeyUnstableLaunches = @"unstableLaunches";

NSString *const VortexEffectIdentifierStock = @"stock";
NSString *const VortexEffectIdentifierReverseSlide = @"reverse-slide";
NSString *const VortexEffectIdentifierVerticalRise = @"vertical-rise";
NSString *const VortexEffectIdentifierVerticalFall = @"vertical-fall";
NSString *const VortexEffectIdentifierTornado = @"tornado";
NSString *const VortexEffectIdentifierOrbital = @"orbital";
NSString *const VortexEffectIdentifierWarp = @"warp";
NSString *const VortexEffectIdentifierHolographic = @"holographic";
NSString *const VortexEffectIdentifierCircuitFlow = @"circuit-flow";
NSString *const VortexEffectIdentifierMagnetic = @"magnetic";
NSString *const VortexEffectIdentifierCustom = @"custom";
NSString *const VortexPresetPerDirection = @"per-direction";

#pragma mark - Configuration

@interface VortexConfiguration ()
- (instancetype)initWithDictionary:(NSDictionary *)values;
@end

@interface VortexPreferences (Lookup)
/// Index of `value` in `allowed`, or 0 (the default entry) when absent.
+ (NSInteger)index:(id)value in:(NSArray<NSString *> *)allowed;
@end

@implementation VortexConfiguration

- (instancetype)initWithDictionary:(NSDictionary *)values {
    if ((self = [super init])) {
        _enabled = [values[VortexKeyEnabled] boolValue];
        _preset = [values[VortexKeyPreset] copy];
        _swipeLeftEffect = [values[VortexKeySwipeLeftEffect] copy];
        _swipeRightEffect = [values[VortexKeySwipeRightEffect] copy];
        _incomingDirection = vortex_direction_from_string([values[VortexKeyIncomingDirection] UTF8String]);
        _outgoingDirection = vortex_direction_from_string([values[VortexKeyOutgoingDirection] UTF8String]);
        _duration = [values[VortexKeyDuration] doubleValue];
        _diagnosticLogging = [values[VortexKeyDiagnosticLogging] boolValue];

        VortexEffectParameters p = vortex_default_parameters();
        p.intensity = [values[VortexKeyIntensity] doubleValue];
        p.speed = [values[VortexKeySpeed] doubleValue];
        p.easing = [VortexPreferences easingFromString:values[VortexKeyEasing]];
        p.fadePages = [values[VortexKeyFadePages] boolValue] ? 1 : 0;
        p.reverse = [values[VortexKeyReverseAnimation] boolValue] ? 1 : 0;
        _parameters = vortex_sanitize_parameters(p);

        VortexIconEffectSettings x = vortex_icon_settings_defaults();
        VortexTornadoParameters t = x.tornado;
        t.intensity = [values[VortexKeyTornadoIntensity] doubleValue];
        t.radius = [values[VortexKeyTornadoRadius] doubleValue];
        t.tipRadius = [values[VortexKeyTornadoTipRadius] doubleValue];
        t.height = [values[VortexKeyTornadoHeight] doubleValue];
        t.rotations = [values[VortexKeyTornadoRotations] doubleValue];
        t.direction = (VortexSpinDirection)[VortexPreferences index:values[VortexKeyTornadoDirection]
                                                                 in:[VortexPreferences validTornadoDirections]];
        t.travel = (VortexTravelMode)[VortexPreferences index:values[VortexKeyTornadoTravel]
                                                           in:[VortexPreferences validTravelModes]];
        t.depth = [values[VortexKeyTornadoDepth] doubleValue];
        t.iconSpin = [values[VortexKeyTornadoIconSpin] boolValue] ? 1 : 0;
        x.tornado = t;
        x.orbital.radius = [values[VortexKeyOrbitalRadius] doubleValue];
        x.orbital.rings = [values[VortexKeyOrbitalRings] intValue];
        x.orbital.tilt = [values[VortexKeyOrbitalTilt] doubleValue];
        x.orbital.speed = [values[VortexKeyOrbitalSpeed] doubleValue];
        x.orbital.direction = (VortexSpinDirection)[VortexPreferences index:values[VortexKeyOrbitalDirection]
                                                                         in:[VortexPreferences validTornadoDirections]];
        x.warp.intensity = [values[VortexKeyWarpIntensity] doubleValue];
        x.warp.perspective = [values[VortexKeyWarpPerspective] doubleValue];
        x.holo.depth = [values[VortexKeyHoloDepth] doubleValue];
        x.holo.tilt = [values[VortexKeyHoloTilt] doubleValue];
        x.holo.layers = [values[VortexKeyHoloLayers] intValue];
        x.circuit.trail = [values[VortexKeyCircuitTrail] doubleValue];
        x.circuit.intensity = [values[VortexKeyCircuitIntensity] doubleValue];
        x.circuit.glow = [values[VortexKeyGlowIntensity] doubleValue];
        x.magnetic.strength = [values[VortexKeyMagneticStrength] doubleValue];
        x.magnetic.snap = [values[VortexKeyMagneticSnap] doubleValue];
        _iconEffectSettings = vortex_icon_settings_sanitize(x);
        _tornadoParameters = _iconEffectSettings.tornado;
        _accentRGB = [[VortexPreferences rgbForAccentColor:values[VortexKeyAccentColor]] copy];
    }
    return self;
}

- (NSString *)effectIdentifierForNavigation:(VortexNavigationDirection)navigation {
    if (![self.preset isEqualToString:VortexPresetPerDirection]) return self.preset;
    return navigation == VortexNavigationBackward ? self.swipeRightEffect : self.swipeLeftEffect;
}

- (BOOL)isStock {
    if ([self.preset isEqualToString:VortexEffectIdentifierStock]) return YES;
    BOOL bothStock = [[self effectIdentifierForNavigation:VortexNavigationForward] isEqualToString:VortexEffectIdentifierStock] &&
                     [[self effectIdentifierForNavigation:VortexNavigationBackward] isEqualToString:VortexEffectIdentifierStock];
    VortexEffectParameters p = self.parameters;
    BOOL neutral = !p.reverse && !p.fadePages && p.intensity >= 0.999 && fabs(p.speed - 1.0) < 1e-9 &&
                   p.easing == VortexEasingLinear && self.duration <= 0.0;
    return bothStock && neutral;
}

- (NSString *)description {
    VortexEffectParameters p = self.parameters;
    return [NSString stringWithFormat:@"<VortexConfiguration enabled=%d preset=%@ left=%@ right=%@ in=%s out=%s "
                                      @"duration=%.2f speed=%.2f intensity=%.2f easing=%d fade=%d reverse=%d "
                                      @"tornado=(%.2f %.2f %.2f dir=%d depth=%.2f spin=%d)>",
                                      self.enabled, self.preset, self.swipeLeftEffect, self.swipeRightEffect,
                                      vortex_direction_to_string(self.incomingDirection),
                                      vortex_direction_to_string(self.outgoingDirection), self.duration, p.speed,
                                      p.intensity, (int)p.easing, p.fadePages, p.reverse, self.tornadoParameters.intensity,
                                      self.tornadoParameters.radius, self.tornadoParameters.rotations,
                                      (int)self.tornadoParameters.direction, self.tornadoParameters.depth,
                                      self.tornadoParameters.iconSpin];
}

@end

#pragma mark - Preferences

@implementation VortexPreferences

+ (NSDictionary<NSString *, id> *)defaultValues {
    // Rebuilt on each call on purpose: not a hot path, and avoids static
    // block-based initialisation in SpringBoard. Effect defaults come from
    // the C defaults, so Settings, SpringBoard and the tests cannot disagree.
    VortexIconEffectSettings d = vortex_icon_settings_defaults();
    return @{
        VortexKeyEnabled : @YES,
        VortexKeyPreset : VortexEffectIdentifierVerticalRise,
        VortexKeySwipeLeftEffect : VortexEffectIdentifierVerticalRise,
        VortexKeySwipeRightEffect : VortexEffectIdentifierVerticalFall,
        VortexKeyIncomingDirection : @"down",
        VortexKeyOutgoingDirection : @"up",
        VortexKeyReverseAnimation : @NO,
        VortexKeyDuration : @0.0,
        VortexKeySpeed : @1.0,
        VortexKeyIntensity : @1.0,
        VortexKeyEasing : @"linear",
        VortexKeyFadePages : @NO,
        VortexKeyDiagnosticLogging : @NO,
        VortexKeyTornadoPreset : @"classic",
        VortexKeyTornadoIntensity : @(d.tornado.intensity),
        VortexKeyTornadoRadius : @(d.tornado.radius),
        VortexKeyTornadoTipRadius : @(d.tornado.tipRadius),
        VortexKeyTornadoHeight : @(d.tornado.height),
        VortexKeyTornadoRotations : @(d.tornado.rotations),
        VortexKeyTornadoDirection : @"follow-swipe",
        VortexKeyTornadoTravel : @"follow-swipe",
        VortexKeyTornadoDepth : @(d.tornado.depth),
        VortexKeyTornadoIconSpin : @NO,
        VortexKeyOrbitalRadius : @(d.orbital.radius),
        VortexKeyOrbitalRings : @(d.orbital.rings),
        VortexKeyOrbitalTilt : @(d.orbital.tilt),
        VortexKeyOrbitalSpeed : @(d.orbital.speed),
        VortexKeyOrbitalDirection : @"follow-swipe",
        VortexKeyWarpIntensity : @(d.warp.intensity),
        VortexKeyWarpPerspective : @(d.warp.perspective),
        VortexKeyHoloDepth : @(d.holo.depth),
        VortexKeyHoloTilt : @(d.holo.tilt),
        VortexKeyHoloLayers : @(d.holo.layers),
        VortexKeyCircuitTrail : @(d.circuit.trail),
        VortexKeyCircuitIntensity : @(d.circuit.intensity),
        VortexKeyMagneticStrength : @(d.magnetic.strength),
        VortexKeyMagneticSnap : @(d.magnetic.snap),
        VortexKeyAccentColor : @"cyan",
        VortexKeyGlowIntensity : @(d.circuit.glow),
    };
}

+ (BOOL)isBooleanKey:(NSString *)key {
    return [@[ VortexKeyEnabled, VortexKeyReverseAnimation, VortexKeyFadePages, VortexKeyDiagnosticLogging,
               VortexKeyTornadoIconSpin ] containsObject:key];
}

+ (NSArray<NSString *> *)allKeys {
    return [[self defaultValues].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)validEffectIdentifiers {
    return @[ VortexEffectIdentifierReverseSlide, VortexEffectIdentifierVerticalRise, VortexEffectIdentifierVerticalFall,
              VortexEffectIdentifierTornado, VortexEffectIdentifierOrbital, VortexEffectIdentifierWarp,
              VortexEffectIdentifierHolographic, VortexEffectIdentifierCircuitFlow, VortexEffectIdentifierMagnetic,
              VortexEffectIdentifierCustom, VortexEffectIdentifierStock ];
}

+ (NSArray<NSString *> *)validPresets {
    return [[self validEffectIdentifiers] arrayByAddingObject:VortexPresetPerDirection];
}

+ (NSArray<NSString *> *)validDirections {
    NSMutableArray *names = [NSMutableArray array];
    for (int d = VortexDirectionLeft; d < VortexDirectionCount; d++) {
        [names addObject:@(vortex_direction_to_string((VortexDirection)d))];
    }
    return names;
}

+ (NSArray<NSString *> *)validEasings {
    return @[ @"linear", @"ease-in", @"ease-out", @"ease-in-out", @"sine" ];
}

+ (NSArray<NSString *> *)validTornadoDirections {
    // Order matches VortexSpinDirection.
    return @[ @"follow-swipe", @"clockwise", @"counterclockwise" ];
}

+ (NSArray<NSString *> *)validTravelModes {
    // Order matches VortexTravelMode.
    return @[ @"follow-swipe", @"against-swipe", @"centred" ];
}

+ (NSArray<NSString *> *)validTornadoPresets {
    // Order matches VortexTornadoPreset, then "custom".
    return @[ @"subtle", @"classic", @"scifi", @"custom" ];
}

+ (NSArray<NSString *> *)validAccentColors {
    return @[ @"cyan", @"purple", @"green", @"amber", @"magenta", @"white" ];
}

+ (NSArray<NSNumber *> *)rgbForAccentColor:(NSString *)name {
    NSUInteger i = [[self validAccentColors] indexOfObject:name ?: @""];
    static const double rgb[][3] = { { 0.00, 0.90, 1.00 }, { 0.62, 0.40, 1.00 }, { 0.20, 0.95, 0.55 },
                                     { 1.00, 0.72, 0.20 }, { 1.00, 0.30, 0.75 }, { 0.95, 0.97, 1.00 } };
    if (i == NSNotFound) i = 0;
    return @[ @(rgb[i][0]), @(rgb[i][1]), @(rgb[i][2]) ];
}

+ (NSInteger)index:(id)value in:(NSArray<NSString *> *)allowed {
    NSUInteger i = [value isKindOfClass:[NSString class]] ? [allowed indexOfObject:value] : NSNotFound;
    return i == NSNotFound ? 0 : (NSInteger)i;
}

+ (BOOL)iconEffectKind:(VortexIconEffectKind *)kind forIdentifier:(NSString *)identifier {
    NSArray *ids = @[ VortexEffectIdentifierTornado, VortexEffectIdentifierOrbital, VortexEffectIdentifierWarp,
                      VortexEffectIdentifierHolographic, VortexEffectIdentifierCircuitFlow, VortexEffectIdentifierMagnetic ];
    NSUInteger i = identifier ? [ids indexOfObject:identifier] : NSNotFound; // order matches VortexIconEffectKind
    if (i == NSNotFound) return NO;
    if (kind) *kind = (VortexIconEffectKind)i;
    return YES;
}

+ (NSArray<NSString *> *)keysForEffectPane:(NSString *)pane {
    NSDictionary *panes = @{
        @"Tornado" : @[ VortexKeyTornadoPreset, VortexKeyTornadoIntensity, VortexKeyTornadoRadius, VortexKeyTornadoTipRadius,
                        VortexKeyTornadoHeight, VortexKeyTornadoRotations, VortexKeyTornadoDirection, VortexKeyTornadoTravel,
                        VortexKeyTornadoDepth, VortexKeyTornadoIconSpin ],
        @"Orbital" : @[ VortexKeyOrbitalRadius, VortexKeyOrbitalRings, VortexKeyOrbitalTilt, VortexKeyOrbitalSpeed,
                        VortexKeyOrbitalDirection ],
        @"Warp" : @[ VortexKeyWarpIntensity, VortexKeyWarpPerspective ],
        @"Holographic" : @[ VortexKeyHoloDepth, VortexKeyHoloTilt, VortexKeyHoloLayers ],
        @"CircuitFlow" : @[ VortexKeyCircuitTrail, VortexKeyCircuitIntensity ],
        @"Magnetic" : @[ VortexKeyMagneticStrength, VortexKeyMagneticSnap ],
        @"Appearance" : @[ VortexKeyAccentColor, VortexKeyGlowIntensity ],
    };
    return panes[pane ?: @""] ?: @[];
}

+ (NSDictionary<NSString *, id> *)valuesForTornadoPreset:(NSString *)preset {
    NSUInteger i = [@[ @"subtle", @"classic", @"scifi" ] indexOfObject:preset ?: @""];
    if (i == NSNotFound) return @{};
    VortexTornadoParameters t = vortex_tornado_preset((VortexTornadoPreset)i);
    return @{
        VortexKeyTornadoIntensity : @(t.intensity), VortexKeyTornadoRadius : @(t.radius),
        VortexKeyTornadoTipRadius : @(t.tipRadius), VortexKeyTornadoHeight : @(t.height),
        VortexKeyTornadoRotations : @(t.rotations), VortexKeyTornadoDepth : @(t.depth),
        VortexKeyTornadoDirection : @"follow-swipe", VortexKeyTornadoTravel : @"follow-swipe",
        VortexKeyTornadoIconSpin : @NO,
    };
}

/// Numeric keys: @[min, max, integer?]. Single table for every slider.
+ (NSDictionary<NSString *, NSArray<NSNumber *> *> *)numericRanges {
    return @{
        VortexKeyDuration : @[ @0.0, @1.0, @NO ], VortexKeySpeed : @[ @0.25, @4.0, @NO ],
        VortexKeyIntensity : @[ @0.1, @1.0, @NO ],
        VortexKeyTornadoIntensity : @[ @0.1, @1.0, @NO ], VortexKeyTornadoRadius : @[ @0.15, @0.6, @NO ],
        VortexKeyTornadoTipRadius : @[ @0.02, @0.25, @NO ], VortexKeyTornadoHeight : @[ @0.35, @0.85, @NO ],
        VortexKeyTornadoRotations : @[ @1.0, @4.0, @NO ], VortexKeyTornadoDepth : @[ @0.0, @1.0, @NO ],
        VortexKeyOrbitalRadius : @[ @0.2, @0.48, @NO ], VortexKeyOrbitalRings : @[ @2, @5, @YES ],
        VortexKeyOrbitalTilt : @[ @0.0, @1.0, @NO ], VortexKeyOrbitalSpeed : @[ @0.25, @2.0, @NO ],
        VortexKeyWarpIntensity : @[ @0.1, @1.0, @NO ], VortexKeyWarpPerspective : @[ @0.2, @1.0, @NO ],
        VortexKeyHoloDepth : @[ @0.0, @1.0, @NO ], VortexKeyHoloTilt : @[ @0.0, @1.0, @NO ],
        VortexKeyHoloLayers : @[ @2, @4, @YES ],
        VortexKeyCircuitTrail : @[ @0.1, @0.6, @NO ], VortexKeyCircuitIntensity : @[ @0.1, @1.0, @NO ],
        VortexKeyMagneticStrength : @[ @0.1, @1.0, @NO ], VortexKeyMagneticSnap : @[ @0.0, @1.0, @NO ],
        VortexKeyGlowIntensity : @[ @0.0, @1.0, @NO ],
    };
}

+ (VortexEasing)easingFromString:(NSString *)string {
    NSUInteger idx = [[self validEasings] indexOfObject:string ?: @""];
    return idx == NSNotFound ? VortexEasingLinear : (VortexEasing)idx;
}

+ (NSNumber *)clampedNumber:(id)value min:(double)lo max:(double)hi {
    if (![value isKindOfClass:[NSNumber class]]) return nil;
    double v = [value doubleValue];
    if (!isfinite(v)) return nil;
    return @(MIN(MAX(v, lo), hi));
}

+ (id)sanitizedValue:(id)value forKey:(NSString *)key {
    id fallback = [self defaultValues][key];
    if (!fallback || !value) return fallback;

    if ([self isBooleanKey:key]) {
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : fallback;
    }
    NSArray<NSNumber *> *range = [self numericRanges][key];
    if (range) {
        NSNumber *n = [self clampedNumber:value min:range[0].doubleValue max:range[1].doubleValue];
        if (!n) return fallback;
        return range[2].boolValue ? @((NSInteger)llround(n.doubleValue)) : n;
    }

    if (![value isKindOfClass:[NSString class]]) return fallback;
    NSArray *allowed = nil;
    if ([key isEqualToString:VortexKeyPreset]) allowed = [self validPresets];
    else if ([key isEqualToString:VortexKeySwipeLeftEffect] || [key isEqualToString:VortexKeySwipeRightEffect])
        allowed = [self validEffectIdentifiers];
    else if ([key isEqualToString:VortexKeyIncomingDirection] || [key isEqualToString:VortexKeyOutgoingDirection])
        allowed = [self validDirections];
    else if ([key isEqualToString:VortexKeyEasing]) allowed = [self validEasings];
    else if ([key isEqualToString:VortexKeyTornadoDirection] || [key isEqualToString:VortexKeyOrbitalDirection])
        allowed = [self validTornadoDirections];
    else if ([key isEqualToString:VortexKeyTornadoTravel]) allowed = [self validTravelModes];
    else if ([key isEqualToString:VortexKeyTornadoPreset]) allowed = [self validTornadoPresets];
    else if ([key isEqualToString:VortexKeyAccentColor]) allowed = [self validAccentColors];
    return [allowed containsObject:value] ? value : fallback;
}

+ (VortexConfiguration *)configurationFromDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in [self allKeys]) {
        values[key] = [self sanitizedValue:dictionary[key] forKey:key];
    }
    return [[VortexConfiguration alloc] initWithDictionary:values];
}

+ (VortexConfiguration *)loadConfiguration {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexPreferencesDomain);
    NSMutableDictionary *raw = [NSMutableDictionary dictionary];
    for (NSString *key in [self allKeys]) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            (__bridge CFStringRef)VortexPreferencesDomain);
        if (value) raw[key] = CFBridgingRelease(value);
    }
    return [self configurationFromDictionary:raw];
}

+ (id)readValueForKey:(NSString *)key {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)VortexPreferencesDomain);
    return [self sanitizedValue:(value ? CFBridgingRelease(value) : nil) forKey:key];
}

+ (void)writeValue:(id)value forKey:(NSString *)key {
    if (![[self defaultValues] objectForKey:key]) return; // unknown keys are never persisted
    id clean = value ? [self sanitizedValue:value forKey:key] : nil;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)clean,
                             (__bridge CFStringRef)VortexPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexPreferencesDomain);
}

+ (void)resetAllValues {
    for (NSString *key in [self allKeys]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)VortexPreferencesDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexPreferencesDomain);
}

+ (void)postChangeNotification {
    notify_post(VORTEX_BUNDLE_ID "/preferences-changed");
}

+ (NSDictionary<NSString *, id> *)readStatus {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexStatusDomain);
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    for (NSString *key in @[ VortexStatusKeyState, VortexStatusKeyDetail, VortexStatusKeySystemVersion,
                             VortexStatusKeyTweakVersion, VortexStatusKeyTimestamp ]) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            (__bridge CFStringRef)VortexStatusDomain);
        if (value) status[key] = CFBridgingRelease(value);
    }
    return status;
}

+ (void)writeStatus:(NSDictionary<NSString *, id> *)status {
    for (NSString *key in status) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)status[key],
                                 (__bridge CFStringRef)VortexStatusDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexStatusDomain);
}

+ (NSInteger)consecutiveUnstableLaunches {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexStatusDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)VortexStatusKeyUnstableLaunches,
                                                        (__bridge CFStringRef)VortexStatusDomain);
    id number = value ? CFBridgingRelease(value) : nil;
    return [number isKindOfClass:[NSNumber class]] ? MAX([number integerValue], 0) : 0;
}

+ (void)setConsecutiveUnstableLaunches:(NSInteger)count {
    CFPreferencesSetAppValue((__bridge CFStringRef)VortexStatusKeyUnstableLaunches,
                             (__bridge CFPropertyListRef)@(MAX(count, 0)), (__bridge CFStringRef)VortexStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)VortexStatusDomain);
}

@end
