//
//  HaloPreferences.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloPreferences.h"

#include <math.h>
#include <notify.h>

NSString *const HaloPreferencesDomain = @HALO_BUNDLE_ID;
NSString *const HaloStatusDomain = @HALO_BUNDLE_ID ".status";
NSString *const HaloPreferencesChangedNotification = @HALO_BUNDLE_ID "/preferences-changed";
NSString *const HaloStatusRequestNotification = @HALO_BUNDLE_ID "/status-request";
NSString *const HaloStatusUpdatedNotification = @HALO_BUNDLE_ID "/status-updated";
NSString *const HaloKillSwitchPath = @"/var/mobile/Library/Preferences/" HALO_BUNDLE_ID ".disabled";

NSString *const HaloKeyEnabled = @"enabled";
NSString *const HaloKeyMode = @"mode";
NSString *const HaloKeyColourStyle = @"colourStyle";
NSString *const HaloKeyColours = @"colours";
NSString *const HaloKeyBrightness = @"brightness";
NSString *const HaloKeyThickness = @"thickness";
NSString *const HaloKeyGlow = @"glow";
NSString *const HaloKeyInset = @"inset";
NSString *const HaloKeySpeed = @"speed";
NSString *const HaloKeyDirection = @"direction";
NSString *const HaloKeyColourRepeat = @"colourRepeat";
NSString *const HaloKeySegments = @"segments";
NSString *const HaloKeySegmentLength = @"segmentLength";
NSString *const HaloKeyLowPower = @"lowPower";
NSString *const HaloKeyProfile = @"profile";
NSString *const HaloKeyCutoutMode = @"cutoutMode";
NSString *const HaloKeyCalCornerRadius = @"calCornerRadius";
NSString *const HaloKeyCalNotchWidth = @"calNotchWidth";
NSString *const HaloKeyCalNotchHeight = @"calNotchHeight";
NSString *const HaloKeyCalNotchOffset = @"calNotchOffset";
NSString *const HaloKeyPresets = @"presets";
NSString *const HaloKeyDiagnosticLogging = @"diagnosticLogging";
NSString *const HaloKeyPulse = @"pulse";
NSString *const HaloKeyTarget = @"target";
NSString *const HaloKeyNexusMatchScreen = @"nexusMatchScreen";
NSString *const HaloKeyNexusAppearance = @"nexusAppearance";
NSString *const HaloKeyNexusOpenTrace = @"nexusOpenTrace";
NSString *const HaloKeyNexusCloseFade = @"nexusCloseFade";
NSString *const HaloKeyNexusWorkspacePulse = @"nexusWorkspacePulse";
NSString *const HaloKeyShowOn = @"showOn";
NSString *const HaloKeyShowOnApp = @"showOnApp";
NSString *const HaloKeyShowOnAppName = @"showOnAppName";

NSString *const HaloStatusKeyState = @"state";
NSString *const HaloStatusKeyDetail = @"detail";
NSString *const HaloStatusKeyRendering = @"rendering";
NSString *const HaloStatusKeyHost = @"host";
NSString *const HaloStatusKeyFrontDetection = @"frontDetection";
NSString *const HaloStatusKeyScreen = @"screen";
NSString *const HaloStatusKeyProfileMatch = @"profileMatch";
NSString *const HaloStatusKeyTweakVersion = @"tweakVersion";
NSString *const HaloStatusKeyBuildID = @"buildID";
NSString *const HaloStatusKeySystemVersion = @"systemVersion";
NSString *const HaloStatusKeyTimestamp = @"timestamp";
NSString *const HaloStatusKeyUnstableLaunches = @"unstableLaunches";
NSString *const HaloStatusKeyNexusState = @"nexusState";
NSString *const HaloStatusKeyShowOn = @"showOn";
NSString *const HaloStatusKeyFrontApp = @"frontApp";
NSString *const HaloStatusKeySurfaceHost = @"surfaceHost";
NSString *const HaloStatusKeyScreenFit = @"screenFit";
NSString *const HaloStatusKeyNexusDetail = @"nexusDetail";
NSString *const HaloStatusKeyNexusRendering = @"nexusRendering";

NSString *const HaloEngineStateActive = @"active";
NSString *const HaloEngineStateDisabled = @"disabled";
NSString *const HaloEngineStateWaiting = @"waiting";
NSString *const HaloEngineStateIncompatible = @"incompatible";
NSString *const HaloEngineStateKillSwitch = @"kill-switch";
NSString *const HaloEngineStateAutoDisabled = @"auto-disabled";
NSString *const HaloEngineStateFault = @"fault";

NSString *const HaloPresetKeyID = @"id";
NSString *const HaloPresetKeyName = @"name";
NSString *const HaloPresetKeyAppearance = @"appearance";
NSString *const HaloBuiltInPresetPrefix = @"builtin.";

static NSString *const kStatusRecordKey = @"status";

// Exported (so never dead-stripped) and compiled into both binaries:
// scripts/validate.sh reads them to prove the package was rebuilt from this
// version and commit, not renamed.
__attribute__((visibility("default"))) const char HaloVersionMarker[] = "HCGHALO-VERSION:" HALO_VERSION;
__attribute__((visibility("default"))) const char HaloBuildMarker[] = "HCGHALO-BUILD:" HALO_BUILD_ID;

static NSString *HaloString(const char *s) {
    return s ? @(s) : @"";
}

static double HaloRound3(double v) {
    return round(v * 1000.0) / 1000.0;
}

#pragma mark - Settings snapshot

@interface HaloSettings ()
- (instancetype)initWithDictionary:(NSDictionary *)values;
@end

@implementation HaloSettings

- (instancetype)initWithDictionary:(NSDictionary *)v {
    if ((self = [super init])) {
        _enabled = [v[HaloKeyEnabled] boolValue];
        _appearance = [HaloPreferences appearanceFromDictionary:v];
        HaloLowPowerPolicy policy = HaloLowPowerStatic;
        halo_low_power_from_id([v[HaloKeyLowPower] UTF8String], &policy);
        _lowPowerPolicy = policy;
        HaloCutoutMode cutout = HaloCutoutTrace;
        halo_cutout_mode_from_id([v[HaloKeyCutoutMode] UTF8String], &cutout);
        _cutoutMode = cutout;
        _profileIdentifier = [v[HaloKeyProfile] copy];
        _profile = halo_profile_find(_profileIdentifier.UTF8String);
        HaloCalibration cal = {[v[HaloKeyCalCornerRadius] doubleValue], [v[HaloKeyCalNotchWidth] doubleValue],
                               [v[HaloKeyCalNotchHeight] doubleValue], [v[HaloKeyCalNotchOffset] doubleValue]};
        _calibration = halo_sanitize_calibration(cal);
        _geometry = halo_profile_geometry(_profile, _calibration);
        _diagnosticLogging = [v[HaloKeyDiagnosticLogging] boolValue];
        NSString *target = v[HaloKeyTarget];
        _target = [target isEqualToString:@"nexus"] ? HaloTargetNexus : ([target isEqualToString:@"both"] ? HaloTargetBoth : HaloTargetScreen);
        _nexusMatchScreen = [v[HaloKeyNexusMatchScreen] boolValue];
        _nexusAppearance = [HaloPreferences appearanceFromDictionary:v[HaloKeyNexusAppearance]];
        _nexusOpenTrace = [v[HaloKeyNexusOpenTrace] boolValue];
        _nexusCloseFade = [v[HaloKeyNexusCloseFade] boolValue];
        _nexusWorkspacePulse = [v[HaloKeyNexusWorkspacePulse] boolValue];
        HaloShowOn showOn = HaloShowOnHome;
        halo_show_on_from_id([v[HaloKeyShowOn] UTF8String], &showOn);
        _showOn = showOn;
        _showOnApp = [HaloPreferences sanitizedBundleIdentifier:v[HaloKeyShowOnApp]];
        _showOnAppName = [v[HaloKeyShowOnAppName] isKindOfClass:[NSString class]] ? [v[HaloKeyShowOnAppName] copy] : @"";
    }
    return self;
}

- (BOOL)targetsScreen {
    return self.target != HaloTargetNexus;
}

- (BOOL)targetsNexus {
    return self.target != HaloTargetScreen;
}

- (HaloAppearance)effectiveNexusAppearance {
    return self.nexusMatchScreen ? self.appearance : self.nexusAppearance;
}

- (NSString *)description {
    HaloAppearance a = self.appearance;
    return [NSString stringWithFormat:@"<HaloSettings enabled=%d mode=%s style=%s colours=%d brightness=%.2f thickness=%.1f "
                                      @"glow=%.2f inset=%.1f speed=%.2f cw=%d repeat=%d segments=%d len=%.2f profile=%@ "
                                      @"showOn=%s app=%@>",
                                      self.enabled, halo_mode_id(a.mode), halo_colour_style_id(a.colourStyle),
                                      a.colourCount, a.brightness, a.thickness, a.glow, a.inset, a.speed, a.clockwise,
                                      a.colourRepeat, a.segments, a.segmentLength, self.profileIdentifier,
                                      halo_show_on_id(self.showOn), self.showOnApp];
}

@end

#pragma mark - Preferences

@implementation HaloPreferences

+ (NSArray<NSString *> *)defaultColourStrings {
    HaloAppearance d = halo_default_appearance();
    NSMutableArray *colours = [NSMutableArray array];
    for (int i = 0; i < d.colourCount; i++) {
        char hex[8];
        halo_format_hex(d.colours[i], hex);
        [colours addObject:@(hex)];
    }
    return colours;
}

+ (NSDictionary<NSString *, id> *)defaultValues {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        HaloAppearance d = halo_default_appearance();
        NSMutableDictionary *m = [[self dictionaryFromAppearance:d] mutableCopy];
        [m addEntriesFromDictionary:@{
            HaloKeyEnabled : @NO, // off after installation
            HaloKeyLowPower : HaloString(halo_low_power_id(HaloLowPowerStatic)),
            HaloKeyProfile : HaloString(halo_default_profile_id()),
            HaloKeyCutoutMode : HaloString(halo_cutout_mode_id(HaloCutoutTrace)),
            HaloKeyCalCornerRadius : @0.0,
            HaloKeyCalNotchWidth : @0.0,
            HaloKeyCalNotchHeight : @0.0,
            HaloKeyCalNotchOffset : @0.0,
            HaloKeyPresets : @[],
            HaloKeyDiagnosticLogging : @NO,
            HaloKeyTarget : @"screen", // existing users keep the screen-edge border
            HaloKeyNexusMatchScreen : @NO,
            HaloKeyNexusAppearance : [self dictionaryFromAppearance:[self nexusSignatureAppearance]],
            HaloKeyNexusOpenTrace : @YES,
            HaloKeyNexusCloseFade : @YES,
            HaloKeyNexusWorkspacePulse : @YES,
            HaloKeyShowOn : @"home", // existing users keep Home Screen Only
            HaloKeyShowOnApp : @"",
            HaloKeyShowOnAppName : @"",
        }];
        defaults = [m copy];
    });
    return defaults;
}

+ (NSArray<NSString *> *)allKeys {
    return [[self defaultValues].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<NSString *> *)appearanceKeys {
    return @[
        HaloKeyMode, HaloKeyColourStyle, HaloKeyColours, HaloKeyBrightness, HaloKeyThickness, HaloKeyGlow, HaloKeyInset,
        HaloKeySpeed, HaloKeyDirection, HaloKeyColourRepeat, HaloKeySegments, HaloKeySegmentLength, HaloKeyPulse
    ];
}

+ (NSArray<NSString *> *)nexusLightingKeys {
    return @[ HaloKeyNexusMatchScreen, HaloKeyNexusAppearance, HaloKeyNexusOpenTrace, HaloKeyNexusCloseFade,
              HaloKeyNexusWorkspacePulse ];
}

+ (NSArray<NSString *> *)validTargets {
    return @[ @"screen", @"nexus", @"both" ];
}

+ (NSArray<NSString *> *)validShowOn {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < HaloShowOnCount; i++) [a addObject:HaloString(halo_show_on_id((HaloShowOn)i))];
    return a;
}

+ (NSString *)sanitizedBundleIdentifier:(id)value {
    if (![value isKindOfClass:[NSString class]]) return @"";
    NSString *s = value;
    if (!s.length || s.length > 255) return @"";
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:
                                       @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"] invertedSet];
    });
    if ([s rangeOfCharacterFromSet:invalid].location != NSNotFound) return @"";
    if ([s hasPrefix:@"."] || [s hasSuffix:@"."] || [s containsString:@".."]) return @"";
    return [s copy];
}

// Built from a struct, never through the validator, so +defaultValues can use
// it inside its dispatch_once without recursion.
+ (HaloAppearance)nexusSignatureAppearance {
    HaloAppearance a = halo_default_appearance();
    a.mode = HaloModeFlow;
    a.colourStyle = HaloColourGradient;
    a.colourCount = 2;
    halo_parse_hex("#00E5FF", &a.colours[0]);
    halo_parse_hex("#7B61FF", &a.colours[1]);
    a.brightness = 0.85;
    a.thickness = 2.0;
    a.glow = 0.45;
    a.inset = 0;
    a.speed = 0.5;
    return halo_sanitize_appearance(a);
}

+ (NSArray<NSString *> *)calibrationKeys {
    return @[ HaloKeyCalCornerRadius, HaloKeyCalNotchWidth, HaloKeyCalNotchHeight, HaloKeyCalNotchOffset ];
}

+ (NSArray<NSString *> *)validModes {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < HaloModeCount; i++) [a addObject:HaloString(halo_mode_id((HaloMode)i))];
    return a;
}

+ (NSArray<NSString *> *)validColourStyles {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < HaloColourStyleCount; i++) [a addObject:HaloString(halo_colour_style_id((HaloColourStyle)i))];
    return a;
}

+ (NSArray<NSString *> *)validDirections {
    return @[ @"clockwise", @"counterclockwise" ];
}

+ (NSArray<NSString *> *)validLowPowerPolicies {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < HaloLowPowerPolicyCount; i++) [a addObject:HaloString(halo_low_power_id((HaloLowPowerPolicy)i))];
    return a;
}

+ (NSArray<NSString *> *)validCutoutModes {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < HaloCutoutModeCount; i++) [a addObject:HaloString(halo_cutout_mode_id((HaloCutoutMode)i))];
    return a;
}

+ (NSArray<NSString *> *)validProfiles {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < halo_profile_count(); i++) {
        const HaloProfile *p = halo_profile_at(i);
        if (p->implemented) [a addObject:HaloString(p->identifier)];
    }
    return a;
}

#pragma mark Validation

static NSNumber *HaloClampNumber(id value, double lo, double hi, NSNumber *fallback, BOOL integral) {
    if (![value isKindOfClass:[NSNumber class]]) return fallback;
    double v = [value doubleValue];
    if (!isfinite(v)) return fallback;
    if (integral) v = round(v);
    v = v < lo ? lo : (v > hi ? hi : v);
    return integral ? @((NSInteger)v) : @(v);
}

static NSString *HaloNormaliseHex(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    HaloRGB rgb;
    if (!halo_parse_hex([value UTF8String], &rgb)) return nil;
    char hex[8];
    halo_format_hex(rgb, hex);
    return @(hex);
}

+ (NSDictionary *)sanitizedPreset:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) return nil;
    NSString *identifier = value[HaloPresetKeyID];
    NSString *name = value[HaloPresetKeyName];
    NSDictionary *appearance = value[HaloPresetKeyAppearance];
    if (![identifier isKindOfClass:[NSString class]] || !identifier.length || [identifier hasPrefix:HaloBuiltInPresetPrefix])
        return nil;
    if (![name isKindOfClass:[NSString class]]) return nil;
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) return nil;
    if (name.length > HALO_PRESET_NAME_MAX) name = [name substringToIndex:HALO_PRESET_NAME_MAX];
    if (![appearance isKindOfClass:[NSDictionary class]]) return nil;
    return @{
        HaloPresetKeyID : identifier,
        HaloPresetKeyName : name,
        HaloPresetKeyAppearance : [self dictionaryFromAppearance:[self appearanceFromDictionary:appearance]],
    };
}

+ (id)sanitizedValue:(id)value forKey:(NSString *)key {
    NSDictionary *defaults = [self defaultValues];
    id fallback = defaults[key];
    if (!fallback) return value; // unknown key: caller's responsibility

    if ([key isEqualToString:HaloKeyEnabled] || [key isEqualToString:HaloKeyDiagnosticLogging] ||
        [key isEqualToString:HaloKeyNexusMatchScreen] || [key isEqualToString:HaloKeyNexusOpenTrace] ||
        [key isEqualToString:HaloKeyNexusCloseFade] || [key isEqualToString:HaloKeyNexusWorkspacePulse]) {
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : fallback;
    }
    NSDictionary<NSString *, NSArray *> *enums = @{
        HaloKeyMode : [self validModes],
        HaloKeyColourStyle : [self validColourStyles],
        HaloKeyDirection : [self validDirections],
        HaloKeyLowPower : [self validLowPowerPolicies],
        HaloKeyCutoutMode : [self validCutoutModes],
        HaloKeyProfile : [self validProfiles], // "automatic" is never valid until implemented
        HaloKeyTarget : [self validTargets],
        HaloKeyShowOn : [self validShowOn],
    };
    if (enums[key]) {
        return ([value isKindOfClass:[NSString class]] && [enums[key] containsObject:value]) ? value : fallback;
    }
    if ([key isEqualToString:HaloKeyBrightness])
        return HaloClampNumber(value, HALO_BRIGHTNESS_MIN, HALO_BRIGHTNESS_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyThickness])
        return HaloClampNumber(value, HALO_THICKNESS_MIN, HALO_THICKNESS_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyGlow]) return HaloClampNumber(value, HALO_GLOW_MIN, HALO_GLOW_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyInset]) return HaloClampNumber(value, HALO_INSET_MIN, HALO_INSET_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeySpeed]) return HaloClampNumber(value, HALO_SPEED_MIN, HALO_SPEED_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyColourRepeat])
        return HaloClampNumber(value, HALO_REPEAT_MIN, HALO_REPEAT_MAX, fallback, YES);
    if ([key isEqualToString:HaloKeySegments])
        return HaloClampNumber(value, HALO_SEGMENTS_MIN, HALO_SEGMENTS_MAX, fallback, YES);
    if ([key isEqualToString:HaloKeySegmentLength])
        return HaloClampNumber(value, HALO_SEGMENT_LENGTH_MIN, HALO_SEGMENT_LENGTH_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyPulse]) return HaloClampNumber(value, HALO_PULSE_MIN, HALO_PULSE_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyShowOnApp]) return [self sanitizedBundleIdentifier:value];
    if ([key isEqualToString:HaloKeyShowOnAppName]) {
        if (![value isKindOfClass:[NSString class]]) return fallback;
        NSString *name = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return name.length > 80 ? [name substringToIndex:80] : name;
    }
    if ([key isEqualToString:HaloKeyNexusAppearance]) {
        if (![value isKindOfClass:[NSDictionary class]]) return fallback;
        return [self dictionaryFromAppearance:[self appearanceFromDictionary:value]];
    }
    if ([key isEqualToString:HaloKeyCalCornerRadius])
        return HaloClampNumber(value, HALO_CAL_CORNER_MIN, HALO_CAL_CORNER_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyCalNotchWidth])
        return HaloClampNumber(value, HALO_CAL_NOTCH_WIDTH_MIN, HALO_CAL_NOTCH_WIDTH_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyCalNotchHeight])
        return HaloClampNumber(value, HALO_CAL_NOTCH_HEIGHT_MIN, HALO_CAL_NOTCH_HEIGHT_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyCalNotchOffset])
        return HaloClampNumber(value, HALO_CAL_NOTCH_OFFSET_MIN, HALO_CAL_NOTCH_OFFSET_MAX, fallback, NO);
    if ([key isEqualToString:HaloKeyColours]) {
        if (![value isKindOfClass:[NSArray class]]) return fallback;
        NSMutableArray *colours = [NSMutableArray array];
        for (id item in value) {
            NSString *hex = HaloNormaliseHex(item);
            if (!hex) return fallback; // one bad entry invalidates the list
            [colours addObject:hex];
        }
        if (colours.count < 1 || colours.count > HALO_MAX_COLOURS) return fallback;
        return colours;
    }
    if ([key isEqualToString:HaloKeyPresets]) {
        if (![value isKindOfClass:[NSArray class]]) return fallback;
        NSMutableArray *presets = [NSMutableArray array];
        NSMutableSet *ids = [NSMutableSet set];
        for (id item in value) {
            NSDictionary *preset = [self sanitizedPreset:item];
            if (!preset || [ids containsObject:preset[HaloPresetKeyID]]) continue;
            [ids addObject:preset[HaloPresetKeyID]];
            [presets addObject:preset];
            if (presets.count >= HALO_MAX_PRESETS) break;
        }
        return presets;
    }
    return fallback;
}

#pragma mark Appearance <-> dictionary

+ (HaloAppearance)appearanceFromDictionary:(NSDictionary *)dictionary {
    HaloAppearance a = halo_default_appearance();
    NSDictionary *d = [dictionary isKindOfClass:[NSDictionary class]] ? dictionary : @{};
    HaloMode mode;
    if (halo_mode_from_id([[self sanitizedValue:d[HaloKeyMode] forKey:HaloKeyMode] UTF8String], &mode)) a.mode = mode;
    HaloColourStyle style;
    if (halo_colour_style_from_id([[self sanitizedValue:d[HaloKeyColourStyle] forKey:HaloKeyColourStyle] UTF8String], &style))
        a.colourStyle = style;
    NSArray *colours = [self sanitizedValue:d[HaloKeyColours] forKey:HaloKeyColours];
    a.colourCount = 0;
    for (NSString *hex in colours) {
        if (a.colourCount >= HALO_MAX_COLOURS) break;
        if (halo_parse_hex(hex.UTF8String, &a.colours[a.colourCount])) a.colourCount++;
    }
    a.brightness = [[self sanitizedValue:d[HaloKeyBrightness] forKey:HaloKeyBrightness] doubleValue];
    a.thickness = [[self sanitizedValue:d[HaloKeyThickness] forKey:HaloKeyThickness] doubleValue];
    a.glow = [[self sanitizedValue:d[HaloKeyGlow] forKey:HaloKeyGlow] doubleValue];
    a.inset = [[self sanitizedValue:d[HaloKeyInset] forKey:HaloKeyInset] doubleValue];
    a.speed = [[self sanitizedValue:d[HaloKeySpeed] forKey:HaloKeySpeed] doubleValue];
    a.clockwise = ![[self sanitizedValue:d[HaloKeyDirection] forKey:HaloKeyDirection] isEqualToString:@"counterclockwise"];
    a.colourRepeat = (int)[[self sanitizedValue:d[HaloKeyColourRepeat] forKey:HaloKeyColourRepeat] integerValue];
    a.segments = (int)[[self sanitizedValue:d[HaloKeySegments] forKey:HaloKeySegments] integerValue];
    a.segmentLength = [[self sanitizedValue:d[HaloKeySegmentLength] forKey:HaloKeySegmentLength] doubleValue];
    a.pulseDepth = [[self sanitizedValue:d[HaloKeyPulse] forKey:HaloKeyPulse] doubleValue];
    return halo_sanitize_appearance(a);
}

+ (NSDictionary<NSString *, id> *)dictionaryFromAppearance:(HaloAppearance)input {
    HaloAppearance a = halo_sanitize_appearance(input);
    NSMutableArray *colours = [NSMutableArray array];
    for (int i = 0; i < a.colourCount; i++) {
        char hex[8];
        halo_format_hex(a.colours[i], hex);
        [colours addObject:@(hex)];
    }
    return @{
        HaloKeyMode : HaloString(halo_mode_id(a.mode)),
        HaloKeyColourStyle : HaloString(halo_colour_style_id(a.colourStyle)),
        HaloKeyColours : colours,
        HaloKeyBrightness : @(HaloRound3(a.brightness)),
        HaloKeyThickness : @(HaloRound3(a.thickness)),
        HaloKeyGlow : @(HaloRound3(a.glow)),
        HaloKeyInset : @(HaloRound3(a.inset)),
        HaloKeySpeed : @(HaloRound3(a.speed)),
        HaloKeyDirection : a.clockwise ? @"clockwise" : @"counterclockwise",
        HaloKeyColourRepeat : @(a.colourRepeat),
        HaloKeySegments : @(a.segments),
        HaloKeySegmentLength : @(HaloRound3(a.segmentLength)),
        HaloKeyPulse : @(HaloRound3(a.pulseDepth)),
    };
}

#pragma mark Storage

+ (NSDictionary *)currentDictionary {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloPreferencesDomain);
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in [self allKeys]) {
        id raw = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                             (__bridge CFStringRef)HaloPreferencesDomain));
        values[key] = [self sanitizedValue:raw forKey:key];
    }
    return values;
}

+ (HaloSettings *)settingsFromDictionary:(NSDictionary *)dictionary {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in [self allKeys]) values[key] = [self sanitizedValue:dictionary[key] forKey:key];
    return [[HaloSettings alloc] initWithDictionary:values];
}

+ (HaloSettings *)loadSettings {
    return [[HaloSettings alloc] initWithDictionary:[self currentDictionary]];
}

+ (id)readValueForKey:(NSString *)key {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloPreferencesDomain);
    id raw = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)HaloPreferencesDomain));
    return [self sanitizedValue:raw forKey:key];
}

+ (void)writeValue:(id)value forKey:(NSString *)key {
    [self writeValues:@{key : value ?: [NSNull null]}];
}

+ (void)writeValues:(NSDictionary<NSString *, id> *)values {
    for (NSString *key in values) {
        id value = values[key];
        id stored = nil;
        if (value != [NSNull null]) stored = [self sanitizedValue:value forKey:key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)stored,
                                 (__bridge CFStringRef)HaloPreferencesDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloPreferencesDomain);
}

+ (void)postChangeNotification {
    notify_post(HaloPreferencesChangedNotification.UTF8String);
}

+ (void)resetAppearance {
    NSMutableDictionary *removals = [NSMutableDictionary dictionary];
    for (NSString *key in [self appearanceKeys]) removals[key] = [NSNull null];
    [self writeValues:removals];
}

+ (void)resetNexusLighting {
    NSMutableDictionary *removals = [NSMutableDictionary dictionary];
    for (NSString *key in [self nexusLightingKeys]) removals[key] = [NSNull null];
    [self writeValues:removals];
}

+ (void)resetCalibration {
    NSMutableDictionary *removals = [NSMutableDictionary dictionary];
    for (NSString *key in [self calibrationKeys]) removals[key] = [NSNull null];
    [self writeValues:removals];
}

#pragma mark Presets

+ (NSDictionary *)builtIn:(NSString *)identifier name:(NSString *)name values:(NSDictionary *)values {
    NSMutableDictionary *d = [[self dictionaryFromAppearance:halo_default_appearance()] mutableCopy];
    [d addEntriesFromDictionary:values];
    return @{
        HaloPresetKeyID : [HaloBuiltInPresetPrefix stringByAppendingString:identifier],
        HaloPresetKeyName : name,
        HaloPresetKeyAppearance : [self dictionaryFromAppearance:[self appearanceFromDictionary:d]],
    };
}

+ (NSArray<NSDictionary *> *)builtInPresets {
    static NSArray *presets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets = @[
            [self builtIn:@"signature" name:@"HCG Signature"
                   values:@{HaloKeyMode : @"flow", HaloKeyColourStyle : @"gradient",
                            HaloKeyColours : @[ @"#00E5FF", @"#7B61FF", @"#C026FF" ], HaloKeyGlow : @0.55}],
            [self builtIn:@"neon" name:@"Neon Static"
                   values:@{HaloKeyMode : @"static", HaloKeyColourStyle : @"gradient",
                            HaloKeyColours : @[ @"#00E5FF", @"#C026FF" ], HaloKeyThickness : @2.5, HaloKeyGlow : @0.7}],
            [self builtIn:@"pulse" name:@"Cyan Pulse"
                   values:@{HaloKeyMode : @"breathing", HaloKeyColourStyle : @"single",
                            HaloKeyColours : @[ @"#00E5FF" ], HaloKeyGlow : @0.6}],
            [self builtIn:@"orbit" name:@"Twin Orbit"
                   values:@{HaloKeyMode : @"orbit", HaloKeyColourStyle : @"gradient", HaloKeySegments : @2,
                            HaloKeySegmentLength : @0.2, HaloKeyThickness : @3.5, HaloKeyGlow : @0.7}],
            [self builtIn:@"circuit" name:@"Circuit Runner"
                   values:@{HaloKeyMode : @"circuit", HaloKeyColourStyle : @"multi",
                            HaloKeyColours : @[ @"#00E5FF", @"#C026FF" ], HaloKeySegments : @2,
                            HaloKeyThickness : @2.5, HaloKeyGlow : @0.5}],
            [self builtIn:@"aurora" name:@"Aurora"
                   values:@{HaloKeyMode : @"flow", HaloKeyColourStyle : @"gradient",
                            HaloKeyColours : @[ @"#00FFA3", @"#00E5FF", @"#7B61FF", @"#FF3CAC" ],
                            HaloKeyColourRepeat : @2, HaloKeySpeed : @0.6}],
            // Visual presets made for the HCG Nexus panel (usable anywhere). They do not
            // represent any system activity.
            @{
                HaloPresetKeyID : @"builtin.nexus-signature",
                HaloPresetKeyName : @"Nexus Signature",
                HaloPresetKeyAppearance : [self dictionaryFromAppearance:[self nexusSignatureAppearance]],
            },
            [self builtIn:@"reactor" name:@"Reactor"
                   values:@{HaloKeyMode : @"orbit", HaloKeyColourStyle : @"gradient",
                            HaloKeyColours : @[ @"#00E5FF", @"#7B61FF", @"#C026FF" ], HaloKeySegments : @2,
                            HaloKeySegmentLength : @0.22, HaloKeyThickness : @2.5, HaloKeyGlow : @0.6,
                            HaloKeySpeed : @0.8, HaloKeyPulse : @0.25, HaloKeyInset : @0}],
            [self builtIn:@"hologram" name:@"Hologram"
                   values:@{HaloKeyMode : @"static", HaloKeyColourStyle : @"single", HaloKeyColours : @[ @"#7FE9FF" ],
                            HaloKeyThickness : @1.0, HaloKeyGlow : @0.15, HaloKeyBrightness : @0.6, HaloKeyInset : @0}],
        ];
    });
    return presets;
}

+ (NSArray<NSDictionary *> *)userPresets {
    return [self readValueForKey:HaloKeyPresets];
}

+ (BOOL)isBuiltInPreset:(NSString *)identifier {
    return [identifier hasPrefix:HaloBuiltInPresetPrefix];
}

+ (NSDictionary *)presetWithIdentifier:(NSString *)identifier {
    for (NSDictionary *p in [[self builtInPresets] arrayByAddingObjectsFromArray:[self userPresets]])
        if ([p[HaloPresetKeyID] isEqualToString:identifier]) return p;
    return nil;
}

+ (NSString *)uniquePresetName:(NSString *)proposed excluding:(NSString *)identifier {
    NSString *base = [proposed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!base.length) return nil;
    if (base.length > HALO_PRESET_NAME_MAX) base = [base substringToIndex:HALO_PRESET_NAME_MAX];
    NSMutableSet *taken = [NSMutableSet set];
    for (NSDictionary *p in [self userPresets]) {
        if (identifier && [p[HaloPresetKeyID] isEqualToString:identifier]) continue;
        [taken addObject:[p[HaloPresetKeyName] lowercaseString]];
    }
    NSString *candidate = base;
    for (int n = 2; [taken containsObject:candidate.lowercaseString] && n < 1000; n++) {
        NSString *suffix = [NSString stringWithFormat:@" %d", n];
        NSUInteger room = HALO_PRESET_NAME_MAX - suffix.length;
        candidate = [(base.length > room ? [base substringToIndex:room] : base) stringByAppendingString:suffix];
    }
    return candidate;
}

+ (NSString *)addUserPresetNamed:(NSString *)name appearance:(NSDictionary *)appearance {
    NSMutableArray *presets = [[self userPresets] mutableCopy];
    if (presets.count >= HALO_MAX_PRESETS) return nil;
    NSString *unique = [self uniquePresetName:name excluding:nil];
    if (!unique) return nil;
    NSString *identifier = [@"user." stringByAppendingString:[NSUUID UUID].UUIDString];
    [presets addObject:@{HaloPresetKeyID : identifier, HaloPresetKeyName : unique, HaloPresetKeyAppearance : appearance}];
    [self writeValue:presets forKey:HaloKeyPresets];
    return identifier;
}

+ (NSString *)saveCurrentAppearanceAsPresetNamed:(NSString *)name {
    NSDictionary *appearance = [self dictionaryFromAppearance:[self loadSettings].appearance];
    return [self addUserPresetNamed:name appearance:appearance];
}

+ (BOOL)renamePreset:(NSString *)identifier to:(NSString *)name {
    if ([self isBuiltInPreset:identifier]) return NO;
    NSString *unique = [self uniquePresetName:name excluding:identifier];
    if (!unique) return NO;
    NSMutableArray *presets = [[self userPresets] mutableCopy];
    for (NSUInteger i = 0; i < presets.count; i++) {
        if (![presets[i][HaloPresetKeyID] isEqualToString:identifier]) continue;
        NSMutableDictionary *p = [presets[i] mutableCopy];
        p[HaloPresetKeyName] = unique;
        presets[i] = p;
        [self writeValue:presets forKey:HaloKeyPresets];
        return YES;
    }
    return NO;
}

+ (NSString *)duplicatePreset:(NSString *)identifier {
    NSDictionary *source = [self presetWithIdentifier:identifier];
    if (!source) return nil;
    NSString *name = [source[HaloPresetKeyName] stringByAppendingString:@" Copy"];
    return [self addUserPresetNamed:name appearance:source[HaloPresetKeyAppearance]];
}

+ (BOOL)deletePreset:(NSString *)identifier {
    if ([self isBuiltInPreset:identifier]) return NO;
    NSMutableArray *presets = [[self userPresets] mutableCopy];
    NSUInteger before = presets.count;
    [presets filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *p, NSDictionary *bindings) {
                 return ![p[HaloPresetKeyID] isEqualToString:identifier];
             }]];
    if (presets.count == before) return NO;
    [self writeValue:presets forKey:HaloKeyPresets];
    return YES;
}

+ (BOOL)applyPreset:(NSString *)identifier {
    NSDictionary *preset = [self presetWithIdentifier:identifier];
    if (!preset) return NO;
    NSDictionary *appearance = [self dictionaryFromAppearance:[self appearanceFromDictionary:preset[HaloPresetKeyAppearance]]];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in [self appearanceKeys]) values[key] = appearance[key] ?: [NSNull null];
    [self writeValues:values];
    return YES;
}

+ (BOOL)applyPresetToNexus:(NSString *)identifier {
    NSDictionary *preset = [self presetWithIdentifier:identifier];
    if (!preset) return NO;
    NSDictionary *appearance = [self dictionaryFromAppearance:[self appearanceFromDictionary:preset[HaloPresetKeyAppearance]]];
    [self writeValues:@{HaloKeyNexusAppearance : appearance, HaloKeyNexusMatchScreen : @NO}];
    return YES;
}

+ (NSString *)matchingNexusPresetIdentifier {
    NSDictionary *current = [self dictionaryFromAppearance:[self loadSettings].nexusAppearance];
    for (NSDictionary *p in [[self builtInPresets] arrayByAddingObjectsFromArray:[self userPresets]]) {
        NSDictionary *candidate = [self dictionaryFromAppearance:[self appearanceFromDictionary:p[HaloPresetKeyAppearance]]];
        if ([candidate isEqualToDictionary:current]) return p[HaloPresetKeyID];
    }
    return nil;
}

+ (void)writeNexusAppearanceValue:(id)value forKey:(NSString *)key {
    if (![[self appearanceKeys] containsObject:key]) return;
    NSMutableDictionary *appearance = [[self dictionaryFromAppearance:[self loadSettings].nexusAppearance] mutableCopy];
    appearance[key] = [self sanitizedValue:value forKey:key];
    [self writeValue:appearance forKey:HaloKeyNexusAppearance];
}

+ (NSString *)matchingPresetIdentifier {
    NSDictionary *current = [self dictionaryFromAppearance:[self loadSettings].appearance];
    for (NSDictionary *p in [[self builtInPresets] arrayByAddingObjectsFromArray:[self userPresets]]) {
        NSDictionary *candidate = [self dictionaryFromAppearance:[self appearanceFromDictionary:p[HaloPresetKeyAppearance]]];
        if ([candidate isEqualToDictionary:current]) return p[HaloPresetKeyID];
    }
    return nil;
}

#pragma mark Status

+ (NSDictionary<NSString *, id> *)readStatus {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloStatusDomain);
    id status = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)kStatusRecordKey,
                                                            (__bridge CFStringRef)HaloStatusDomain));
    return [status isKindOfClass:[NSDictionary class]] ? status : @{};
}

+ (void)writeStatus:(NSDictionary<NSString *, id> *)status {
    CFPreferencesSetAppValue((__bridge CFStringRef)kStatusRecordKey, (__bridge CFPropertyListRef)status,
                             (__bridge CFStringRef)HaloStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloStatusDomain);
}

+ (NSInteger)consecutiveUnstableLaunches {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloStatusDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)HaloStatusKeyUnstableLaunches,
                                                           (__bridge CFStringRef)HaloStatusDomain));
    return [value isKindOfClass:[NSNumber class]] ? MAX(0, [value integerValue]) : 0;
}

+ (void)setConsecutiveUnstableLaunches:(NSInteger)count {
    CFPreferencesSetAppValue((__bridge CFStringRef)HaloStatusKeyUnstableLaunches,
                             (__bridge CFPropertyListRef) @(MAX(0, count)), (__bridge CFStringRef)HaloStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)HaloStatusDomain);
}

@end
