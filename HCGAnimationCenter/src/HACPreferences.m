//
//  HACPreferences.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACPreferences.h"

NSString *const HACPreferencesDomain = @HAC_BUNDLE_ID;
NSString *const HACStatusDomain = @HAC_BUNDLE_ID ".status";
NSString *const HACPreferencesChangedNotification = @HAC_BUNDLE_ID "/preferences-changed";
NSString *const HACStatusRequestNotification = @HAC_BUNDLE_ID "/status-request";
NSString *const HACStatusUpdatedNotification = @HAC_BUNDLE_ID "/status-updated";
NSString *const HACProbeRequestNotification = @HAC_BUNDLE_ID "/probe-request";
NSString *const HACKillSwitchPath = @"/var/mobile/Library/Preferences/" HAC_BUNDLE_ID ".disabled";

NSString *const HACKeyEnabled = @"enabled";
NSString *const HACKeyHomeEnabled = @"homeEnabled";
NSString *const HACKeyLockEnabled = @"lockEnabled";
NSString *const HACKeyHomePreset = @"homePreset";
NSString *const HACKeyLockPreset = @"lockPreset";
NSString *const HACKeyLockSource = @"lockSource";
NSString *const HACKeyReduceMotion = @"reduceMotion";
NSString *const HACKeyLowPower = @"lowPower";
NSString *const HACKeyHomePlacement = @"homePlacement";
NSString *const HACKeyLockPlacement = @"lockPlacement";
NSString *const HACKeyDiagnosticLogging = @"diagnosticLogging";

NSString *const HACStatusKeyState = @"state";
NSString *const HACStatusKeyDetail = @"detail";
NSString *const HACStatusKeyHome = @"home";
NSString *const HACStatusKeyLock = @"lock";
NSString *const HACStatusKeyEnvironment = @"environment";
NSString *const HACStatusKeyFrontDetection = @"frontDetection";
NSString *const HACStatusKeyProbePath = @"probePath";
NSString *const HACStatusKeyTweakVersion = @"tweakVersion";
NSString *const HACStatusKeyBuildID = @"buildID";
NSString *const HACStatusKeySystemVersion = @"systemVersion";
NSString *const HACStatusKeyTimestamp = @"timestamp";
NSString *const HACStatusKeyUnstableLaunches = @"unstableLaunches";
NSString *const HACSurfaceStatusKeyRendering = @"rendering";
NSString *const HACSurfaceStatusKeyHost = @"host";
NSString *const HACSurfaceStatusKeyPlacement = @"placement";
NSString *const HACSurfaceStatusKeyPreset = @"preset";

NSString *const HACEngineStateDisabled = @"disabled";
NSString *const HACEngineStateWaiting = @"waiting";
NSString *const HACEngineStateActive = @"active";
NSString *const HACEngineStateKillSwitch = @"kill-switch";
NSString *const HACEngineStateIncompatible = @"incompatible";
NSString *const HACEngineStateAutoDisabled = @"auto-disabled";
NSString *const HACEngineStateFault = @"fault";

static NSString *const kStatusRecordKey = @"status";

// Exported markers: validate.sh checks both binaries carry the control
// version and one source build ID (rebuilt, never renamed).
__attribute__((visibility("default"))) const char HACVersionMarker[] = "HCGANIMATIONCENTER-VERSION:" HAC_VERSION;
__attribute__((visibility("default"))) const char HACBuildMarker[] = "HCGANIMATIONCENTER-BUILD:" HAC_BUILD_ID;

static NSString *gStoreRootOverride;

@interface HACSettings ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) BOOL homeEnabled;
@property (nonatomic, readwrite) BOOL lockEnabled;
@property (nonatomic, readwrite) BOOL lockSameAsHome;
@property (nonatomic, readwrite, nullable) HCGBackgroundPreset *homePreset;
@property (nonatomic, readwrite, nullable) HCGBackgroundPreset *lockPreset;
@property (nonatomic, readwrite, copy) NSString *homePresetProblem;
@property (nonatomic, readwrite, copy) NSString *lockPresetProblem;
@property (nonatomic, readwrite) HACReduceMotionPolicy reduceMotionPolicy;
@property (nonatomic, readwrite) HACLowPowerPolicy lowPowerPolicy;
@property (nonatomic, readwrite, copy) NSString *homePlacement;
@property (nonatomic, readwrite, copy) NSString *lockPlacement;
@property (nonatomic, readwrite) BOOL diagnosticLogging;
@end

@implementation HACSettings

- (HCGBackgroundPreset *)presetForSurface:(HACSurface)surface {
    return surface == HACSurfaceLock ? _lockPreset : _homePreset;
}

- (BOOL)surfaceEnabled:(HACSurface)surface {
    return surface == HACSurfaceLock ? _lockEnabled : _homeEnabled;
}

- (NSString *)placementForSurface:(HACSurface)surface {
    return surface == HACSurfaceLock ? _lockPlacement : _homePlacement;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"enabled=%d home=%d(%@) lock=%d(%@%@) rm=%s lp=%s placement=%@/%@",
                                      _enabled, _homeEnabled, _homePreset.name ?: @"-", _lockEnabled,
                                      _lockSameAsHome ? @"same:" : @"", _lockPreset.name ?: @"-",
                                      hac_reduce_motion_id(_reduceMotionPolicy), hac_low_power_id(_lowPowerPolicy),
                                      _homePlacement, _lockPlacement];
}

@end

@implementation HACPreferences

+ (id)valueForKey:(NSString *)key {
    return CFBridgingRelease(
        CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)HACPreferencesDomain));
}

+ (void)setValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)HACPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACPreferencesDomain);
    [self postChanged];
}

+ (void)postChanged {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)HACPreferencesChangedNotification, NULL, NULL, YES);
}

+ (NSArray<NSString *> *)validHomePlacements {
    return @[ @"automatic", @"homeWindow", @"wallpaper" ];
}

+ (NSArray<NSString *> *)validLockPlacements {
    return @[ @"automatic", @"wallpaper", @"coverSheet" ];
}

static BOOL Bool(NSDictionary *d, NSString *key, BOOL fallback) {
    id v = d[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : fallback;
}

static NSString *Choice(NSDictionary *d, NSString *key, NSArray<NSString *> *valid, NSString *fallback) {
    id v = d[key];
    return [v isKindOfClass:[NSString class]] && [valid containsObject:v] ? v : fallback;
}

static HCGBackgroundPreset *Preset(NSDictionary *d, NSString *key, NSString **problem) {
    id v = d[key];
    *problem = @"";
    if (!v) return nil;
    if (![v isKindOfClass:[NSDictionary class]]) {
        *problem = @"The stored background is not a preset.";
        return nil;
    }
    NSError *error = nil;
    HCGBackgroundPreset *preset = [HCGBackgroundPreset presetWithDictionary:v error:&error];
    if (!preset) *problem = error.localizedDescription ?: @"The stored background is invalid.";
    return preset;
}

+ (HACSettings *)loadSettings {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACPreferencesDomain);
    NSDictionary *d = nil;
    CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)HACPreferencesDomain, kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost);
    if (keys) {
        d = CFBridgingRelease(CFPreferencesCopyMultiple(keys, (__bridge CFStringRef)HACPreferencesDomain,
                                                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        CFRelease(keys);
    }
    if (![d isKindOfClass:[NSDictionary class]]) d = @{};

    HACSettings *s = [[HACSettings alloc] init];
    s.enabled = Bool(d, HACKeyEnabled, NO);
    s.homeEnabled = Bool(d, HACKeyHomeEnabled, YES);
    s.lockEnabled = Bool(d, HACKeyLockEnabled, NO);
    s.lockSameAsHome = [Choice(d, HACKeyLockSource, @[ @"same", @"own" ], @"own") isEqualToString:@"same"];
    NSString *problem = @"";
    s.homePreset = Preset(d, HACKeyHomePreset, &problem);
    s.homePresetProblem = problem;
    if (s.lockSameAsHome) {
        s.lockPreset = s.homePreset;
        s.lockPresetProblem = s.homePresetProblem;
    } else {
        s.lockPreset = Preset(d, HACKeyLockPreset, &problem);
        s.lockPresetProblem = problem;
    }
    HACReduceMotionPolicy rm = HACReduceMotionStill;
    id rmValue = d[HACKeyReduceMotion];
    if ([rmValue isKindOfClass:[NSString class]]) hac_reduce_motion_parse([rmValue UTF8String], &rm);
    s.reduceMotionPolicy = rm;
    HACLowPowerPolicy lp = HACLowPowerStill;
    id lpValue = d[HACKeyLowPower];
    if ([lpValue isKindOfClass:[NSString class]]) hac_low_power_parse([lpValue UTF8String], &lp);
    s.lowPowerPolicy = lp;
    s.homePlacement = Choice(d, HACKeyHomePlacement, [self validHomePlacements], @"automatic");
    s.lockPlacement = Choice(d, HACKeyLockPlacement, [self validLockPlacements], @"automatic");
    s.diagnosticLogging = Bool(d, HACKeyDiagnosticLogging, NO);
    return s;
}

#pragma mark Store

+ (NSString *)storeRoot {
    return gStoreRootOverride ?: @"/var/mobile/Library/HCGAnimationCenter";
}

+ (void)setStoreRootForTesting:(NSString *)root {
    gStoreRootOverride = [root copy];
}

+ (NSURL *)mediaFolder {
    return [NSURL fileURLWithPath:[[self storeRoot] stringByAppendingPathComponent:@"Media"] isDirectory:YES];
}

+ (NSURL *)diagnosticsFolder {
    return [NSURL fileURLWithPath:[[self storeRoot] stringByAppendingPathComponent:@"Diagnostics"] isDirectory:YES];
}

#pragma mark Status

+ (NSDictionary<NSString *, id> *)readStatus {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACStatusDomain);
    id status = CFBridgingRelease(
        CFPreferencesCopyAppValue((__bridge CFStringRef)kStatusRecordKey, (__bridge CFStringRef)HACStatusDomain));
    return [status isKindOfClass:[NSDictionary class]] ? status : @{};
}

+ (void)writeStatus:(NSDictionary<NSString *, id> *)status {
    CFPreferencesSetAppValue((__bridge CFStringRef)kStatusRecordKey, (__bridge CFPropertyListRef)status,
                             (__bridge CFStringRef)HACStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACStatusDomain);
}

+ (NSInteger)consecutiveUnstableLaunches {
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACStatusDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)HACStatusKeyUnstableLaunches,
                                                           (__bridge CFStringRef)HACStatusDomain));
    return [value isKindOfClass:[NSNumber class]] ? MAX(0, [value integerValue]) : 0;
}

+ (void)setConsecutiveUnstableLaunches:(NSInteger)count {
    CFPreferencesSetAppValue((__bridge CFStringRef)HACStatusKeyUnstableLaunches, (__bridge CFPropertyListRef) @(MAX(0, count)),
                             (__bridge CFStringRef)HACStatusDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)HACStatusDomain);
}

@end
