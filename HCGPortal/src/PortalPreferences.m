//
//  PortalPreferences.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalPreferences.h"

NSString *const PortalPreferencesDomain = @PORTAL_BUNDLE_ID;
NSString *const PortalStatusDomain = @PORTAL_BUNDLE_ID ".status";
NSString *const PortalPreferencesChangedNotification = @PORTAL_BUNDLE_ID "/preferences-changed";
NSString *const PortalStatusRequestNotification = @PORTAL_BUNDLE_ID "/status-request";
NSString *const PortalStatusUpdatedNotification = @PORTAL_BUNDLE_ID "/status-updated";
NSString *const PortalKillSwitchPath = @"/var/mobile/Library/Preferences/" PORTAL_BUNDLE_ID ".disabled";

NSString *const PortalKeyEnabled = @"enabled";
NSString *const PortalKeyPalette = @"palette";
NSString *const PortalKeyBrightness = @"brightness";
NSString *const PortalKeySpeed = @"speed";
NSString *const PortalKeyIntensity = @"intensity";
NSString *const PortalKeySize = @"size";
NSString *const PortalKeyOffsetX = @"offsetX";
NSString *const PortalKeyOffsetY = @"offsetY";
NSString *const PortalKeyUnlockAnimation = @"unlockAnimation";
NSString *const PortalKeyLowPower = @"lowPower";
NSString *const PortalKeyApps = @"apps";
NSString *const PortalKeyDiagnosticLogging = @"diagnosticLogging";

NSString *const PortalStatusKeyState = @"state";
NSString *const PortalStatusKeyDetail = @"detail";
NSString *const PortalStatusKeyVisibility = @"visibility";
NSString *const PortalStatusKeyLayout = @"layout";
NSString *const PortalStatusKeyPlan = @"plan";
NSString *const PortalStatusKeyHost = @"host";
NSString *const PortalStatusKeyScene = @"scene";
NSString *const PortalStatusKeyAuthRoute = @"authRoute";
NSString *const PortalStatusKeyLauncher = @"launcher";
NSString *const PortalStatusKeyCompanions = @"companions";
NSString *const PortalStatusKeyLastAction = @"lastAction";
NSString *const PortalStatusKeyCounters = @"counters";
NSString *const PortalStatusKeyHooks = @"hooks";
NSString *const PortalStatusKeyTweakVersion = @"tweakVersion";
NSString *const PortalStatusKeyBuildID = @"buildID";
NSString *const PortalStatusKeySystemVersion = @"systemVersion";
NSString *const PortalStatusKeyTimestamp = @"timestamp";
NSString *const PortalStatusKeyUnstableLaunches = @"unstableLaunches";

NSString *const PortalEngineStateDisabled = @"disabled";
NSString *const PortalEngineStateWaiting = @"waiting";
NSString *const PortalEngineStateActive = @"active";
NSString *const PortalEngineStateKillSwitch = @"kill-switch";
NSString *const PortalEngineStateIncompatible = @"incompatible";
NSString *const PortalEngineStateAutoDisabled = @"auto-disabled";
NSString *const PortalEngineStateFault = @"fault";

static NSString *const kStatusRecordKey = @"status";

// Exported markers: validate.sh checks both binaries carry the control version
// and one source build ID (rebuilt, never renamed).
__attribute__((visibility("default"))) const char PortalVersionMarker[] = "HCGPORTAL-VERSION:" PORTAL_VERSION;
__attribute__((visibility("default"))) const char PortalBuildMarker[] = "HCGPORTAL-BUILD:" PORTAL_BUILD_ID;

#pragma mark - Shortcut

@interface PortalAppShortcut ()
@property (nonatomic, readwrite, copy) NSString *bundleIdentifier;
@property (nonatomic, readwrite, copy) NSString *name;
@end

@implementation PortalAppShortcut

static BOOL PortalValidBundleIdentifier(NSString *s) {
    if (s.length < 3 || s.length > 155) return NO;
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if ([s rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    return [s rangeOfString:@"."].location != NSNotFound && ![s hasPrefix:@"."] && ![s hasSuffix:@"."];
}

+ (instancetype)shortcutWithDictionary:(id)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    id identifier = dictionary[@"id"];
    id name = dictionary[@"name"];
    if (![identifier isKindOfClass:[NSString class]] || !PortalValidBundleIdentifier(identifier)) return nil;
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = identifier;
    if ([name length] > 40) name = [name substringToIndex:40];
    return [self shortcutWithIdentifier:identifier name:name];
}

+ (instancetype)shortcutWithIdentifier:(NSString *)identifier name:(NSString *)name {
    PortalAppShortcut *s = [[PortalAppShortcut alloc] init];
    s.bundleIdentifier = identifier;
    s.name = name.length ? name : identifier;
    return s;
}

- (NSDictionary *)dictionary {
    return @{@"id" : _bundleIdentifier, @"name" : _name};
}

@end

#pragma mark - Settings

@interface PortalSettings ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) PortalAppearance appearance;
@property (nonatomic, readwrite) PortalPlacement placement;
@property (nonatomic, readwrite) BOOL unlockAnimation;
@property (nonatomic, readwrite) int lowPowerPolicy;
@property (nonatomic, readwrite, copy) NSArray<PortalAppShortcut *> *apps;
@property (nonatomic, readwrite) BOOL diagnosticLogging;
@end

static BOOL Bool(NSDictionary *d, NSString *key, BOOL fallback) {
    id v = d[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : fallback;
}

static double Number(NSDictionary *d, NSString *key, double fallback) {
    id v = d[key];
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : fallback;
}

static NSString *String(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

@implementation PortalSettings

+ (PortalSettings *)settingsWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) d = @{};
    PortalSettings *s = [[PortalSettings alloc] init];
    s.enabled = Bool(d, PortalKeyEnabled, NO);

    PortalAppearance a;
    portal_appearance_defaults(&a);
    a.palette = portal_palette_from_id(String(d, PortalKeyPalette).UTF8String);
    a.brightness = Number(d, PortalKeyBrightness, a.brightness);
    a.speed = Number(d, PortalKeySpeed, a.speed);
    a.intensity = Number(d, PortalKeyIntensity, a.intensity);
    portal_appearance_clamp(&a);
    s.appearance = a;

    PortalPlacement p;
    portal_placement_defaults(&p);
    p.size = Number(d, PortalKeySize, p.size);
    p.offsetX = Number(d, PortalKeyOffsetX, p.offsetX);
    p.offsetY = Number(d, PortalKeyOffsetY, p.offsetY);
    portal_placement_clamp(&p);
    s.placement = p;

    s.unlockAnimation = Bool(d, PortalKeyUnlockAnimation, YES);
    s.lowPowerPolicy = portal_low_power_from_id(String(d, PortalKeyLowPower).UTF8String);

    NSMutableArray *apps = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    id list = d[PortalKeyApps];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id item in list) {
            PortalAppShortcut *shortcut = [PortalAppShortcut shortcutWithDictionary:item];
            if (!shortcut || [seen containsObject:shortcut.bundleIdentifier]) continue;
            [seen addObject:shortcut.bundleIdentifier];
            [apps addObject:shortcut];
            if (apps.count == PORTAL_MAX_APPS) break;
        }
    }
    s.apps = apps;
    s.diagnosticLogging = Bool(d, PortalKeyDiagnosticLogging, NO);
    return s;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"enabled=%d palette=%s brightness=%.2f speed=%.2f intensity=%.2f size=%.0f offset=(%.0f,%.0f) unlock=%d lowPower=%s apps=%lu",
                                      _enabled, portal_palette_id(_appearance.palette), _appearance.brightness,
                                      _appearance.speed, _appearance.intensity, _placement.size, _placement.offsetX,
                                      _placement.offsetY, _unlockAnimation, portal_low_power_id(_lowPowerPolicy),
                                      (unsigned long)_apps.count];
}

@end

#pragma mark - Preferences

@implementation PortalPreferences

+ (id)valueForKey:(NSString *)key {
    return CFBridgingRelease(
        CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)PortalPreferencesDomain));
}

+ (void)setValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)PortalPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalPreferencesDomain);
    [self postChanged];
}

+ (void)removeKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)PortalPreferencesDomain);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalPreferencesDomain);
    [self postChanged];
}

+ (void)postChanged {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)PortalPreferencesChangedNotification, NULL, NULL, YES);
}

+ (NSArray<NSString *> *)appearanceKeys {
    return @[ PortalKeyPalette, PortalKeyBrightness, PortalKeySpeed, PortalKeyIntensity ];
}

+ (NSArray<NSString *> *)placementKeys {
    return @[ PortalKeySize, PortalKeyOffsetX, PortalKeyOffsetY ];
}

+ (NSArray<NSString *> *)validPalettes {
    return @[ @"signature", @"aurora", @"solar", @"mono" ];
}

+ (NSArray<NSString *> *)validLowPowerPolicies {
    return @[ @"static", @"economy", @"hide" ];
}

+ (PortalSettings *)loadSettings {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalPreferencesDomain);
    NSDictionary *d = nil;
    CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)PortalPreferencesDomain, kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost);
    if (keys) {
        d = CFBridgingRelease(CFPreferencesCopyMultiple(keys, (__bridge CFStringRef)PortalPreferencesDomain,
                                                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keys);
    }
    return [PortalSettings settingsWithDictionary:d ?: @{}];
}

#pragma mark Status

+ (NSDictionary<NSString *, id> *)readStatus {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalStatusDomain);
    id status = CFBridgingRelease(
        CFPreferencesCopyAppValue((__bridge CFStringRef)kStatusRecordKey, (__bridge CFStringRef)PortalStatusDomain));
    return [status isKindOfClass:[NSDictionary class]] ? status : @{};
}

+ (void)writeStatus:(NSDictionary<NSString *, id> *)status {
    CFPreferencesSetAppValue((__bridge CFStringRef)kStatusRecordKey, (__bridge CFPropertyListRef)status,
                             (__bridge CFStringRef)PortalStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalStatusDomain);
}

+ (NSInteger)consecutiveUnstableLaunches {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalStatusDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)PortalStatusKeyUnstableLaunches,
                                                           (__bridge CFStringRef)PortalStatusDomain));
    return [value isKindOfClass:[NSNumber class]] ? MAX(0, [value integerValue]) : 0;
}

+ (void)setConsecutiveUnstableLaunches:(NSInteger)count {
    CFPreferencesSetAppValue((__bridge CFStringRef)PortalStatusKeyUnstableLaunches,
                             (__bridge CFPropertyListRef) @(MAX(0, count)), (__bridge CFStringRef)PortalStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)PortalStatusDomain);
}

@end
