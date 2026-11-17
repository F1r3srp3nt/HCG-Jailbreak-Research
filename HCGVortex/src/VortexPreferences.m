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
NSString *const VortexEffectIdentifierCustom = @"custom";
NSString *const VortexPresetPerDirection = @"per-direction";

#pragma mark - Configuration

@interface VortexConfiguration ()
- (instancetype)initWithDictionary:(NSDictionary *)values;
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
                                      @"duration=%.2f speed=%.2f intensity=%.2f easing=%d fade=%d reverse=%d>",
                                      self.enabled, self.preset, self.swipeLeftEffect, self.swipeRightEffect,
                                      vortex_direction_to_string(self.incomingDirection),
                                      vortex_direction_to_string(self.outgoingDirection), self.duration, p.speed,
                                      p.intensity, (int)p.easing, p.fadePages, p.reverse];
}

@end

#pragma mark - Preferences

@implementation VortexPreferences

+ (NSDictionary<NSString *, id> *)defaultValues {
    // Rebuilt on each call on purpose: not a hot path, and avoids static
    // block-based initialisation in SpringBoard.
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
    };
}

+ (BOOL)isBooleanKey:(NSString *)key {
    return [@[ VortexKeyEnabled, VortexKeyReverseAnimation, VortexKeyFadePages, VortexKeyDiagnosticLogging ]
        containsObject:key];
}

+ (NSArray<NSString *> *)allKeys {
    return [[self defaultValues].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)validEffectIdentifiers {
    return @[ VortexEffectIdentifierReverseSlide, VortexEffectIdentifierVerticalRise, VortexEffectIdentifierVerticalFall,
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
    if ([key isEqualToString:VortexKeyDuration]) return [self clampedNumber:value min:0.0 max:1.0] ?: fallback;
    if ([key isEqualToString:VortexKeySpeed]) return [self clampedNumber:value min:0.25 max:4.0] ?: fallback;
    if ([key isEqualToString:VortexKeyIntensity]) return [self clampedNumber:value min:0.1 max:1.0] ?: fallback;

    if (![value isKindOfClass:[NSString class]]) return fallback;
    NSArray *allowed = nil;
    if ([key isEqualToString:VortexKeyPreset]) allowed = [self validPresets];
    else if ([key isEqualToString:VortexKeySwipeLeftEffect] || [key isEqualToString:VortexKeySwipeRightEffect])
        allowed = [self validEffectIdentifiers];
    else if ([key isEqualToString:VortexKeyIncomingDirection] || [key isEqualToString:VortexKeyOutgoingDirection])
        allowed = [self validDirections];
    else if ([key isEqualToString:VortexKeyEasing]) allowed = [self validEasings];
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
