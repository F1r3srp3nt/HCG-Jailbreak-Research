//
//  HaloNexusControl.m
//  HCG Halo — Hakmi Capital Group
//
#import "HaloNexusControl.h"

@implementation HaloNexusControl

+ (NSInteger)controlVersion {
    return HALO_NEXUS_CONTROL_VERSION;
}

static NSString *HaloTargetName(HaloTarget target) {
    switch (target) {
        case HaloTargetNexus: return @"nexus";
        case HaloTargetBoth: return @"both";
        case HaloTargetScreen: return @"screen";
    }
    return @"screen";
}

+ (NSDictionary<NSString *, id> *)changesForNexusBorderEnabled:(BOOL)enabled
                                                 masterEnabled:(BOOL)masterEnabled
                                                        target:(HaloTarget)target
                                                    killSwitch:(BOOL)killSwitch
                                                  autoDisabled:(BOOL)autoDisabled
                                                        reason:(NSString **)reason {
    if (killSwitch) {
        if (reason) *reason = @"HCG Halo is stopped by its kill switch. Remove the kill switch file and respring first.";
        return nil;
    }
    if (autoDisabled) {
        if (reason) *reason = @"HCG Halo turned itself off after repeated SpringBoard restarts. Turn it back on in Settings › HCG Halo first.";
        return nil;
    }
    BOOL panelOn = masterEnabled && (target == HaloTargetNexus || target == HaloTargetBoth);
    if (enabled == panelOn) return @{};
    if (enabled) {
        // Never turn the screen edge on: with the master switch off, light the panel only.
        if (!masterEnabled) return @{ HaloKeyEnabled : @YES, HaloKeyTarget : @"nexus" };
        return @{ HaloKeyTarget : @"both" }; // master on with "screen": the screen edge was already on
    }
    if (target == HaloTargetBoth) return @{ HaloKeyTarget : @"screen" };
    return @{ HaloKeyEnabled : @NO }; // "nexus" only
}

static BOOL HaloKillSwitchPresent(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:HaloKillSwitchPath];
}

+ (NSDictionary<NSString *, id> *)nexusBorderStatus {
    HaloSettings *settings = [HaloPreferences loadSettings];
    NSDictionary *status = [HaloPreferences readStatus];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"] = @(settings.enabled);
    d[@"target"] = HaloTargetName(settings.target);
    d[@"panelBorderOn"] = @(settings.enabled && settings.targetsNexus);
    d[@"haloVersion"] = @HALO_VERSION;
    d[@"killSwitch"] = @(HaloKillSwitchPresent());
    for (NSString *key in @[ HaloStatusKeyState, HaloStatusKeyNexusState, HaloStatusKeyNexusDetail ]) {
        id value = status[key];
        if ([value isKindOfClass:[NSString class]]) d[key] = value;
    }
    return d;
}

+ (BOOL)setNexusBorderEnabled:(BOOL)enabled error:(NSString **)error {
    HaloSettings *settings = [HaloPreferences loadSettings];
    NSDictionary *status = [HaloPreferences readStatus];
    BOOL autoDisabled = [status[HaloStatusKeyState] isEqual:HaloEngineStateAutoDisabled];
    NSString *reason = nil;
    NSDictionary *changes = [self changesForNexusBorderEnabled:enabled masterEnabled:settings.enabled target:settings.target
                                                    killSwitch:HaloKillSwitchPresent() autoDisabled:autoDisabled reason:&reason];
    if (!changes) {
        if (error) *error = reason;
        return NO;
    }
    if (changes.count) {
        [HaloPreferences writeValues:changes];
        [HaloPreferences postChangeNotification];
    }
    return YES;
}

@end
