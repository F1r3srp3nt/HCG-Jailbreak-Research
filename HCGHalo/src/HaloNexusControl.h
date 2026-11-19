//
//  HaloNexusControl.h
//  HCG Halo — Hakmi Capital Group
//
//  The HCG Halo-owned switch for the HCG Nexus panel border (contract HCGHaloNexusControl, version 1).
//
//  HCG Nexus shows "Use HCG Halo border" in its Appearance settings. It never writes HCG Halo's settings
//  itself: it finds this class with NSClassFromString (in SpringBoard from HCGHalo.dylib, in Settings from
//  HCGHaloPrefs.bundle, whose Info.plist declares HCGHaloNexusControl = 1), checks +controlVersion and
//  calls +setNexusBorderEnabled:error:. HCG Halo alone decides how its own keys change, so that turning the
//  panel border on NEVER turns on the screen-edge light:
//
//    turn ON   master off            -> enabled = YES, target = "nexus"   (screen edge stays off)
//              master on, "screen"   -> target = "both"                   (screen edge was already on)
//              master on, nexus/both -> no change
//    turn OFF  "both"                -> target = "screen"                 (screen edge stays as it was)
//              "nexus"               -> enabled = NO
//              master off / "screen" -> no change
//
//  Refused (nothing written) while the kill switch file exists or the launch guard has turned HCG Halo off:
//  those are safety stops only the user lifts, in HCG Halo. Compiled into both HCG Halo binaries, Foundation
//  only. Documented in docs/NEXUS.md ("Switching from HCG Nexus").
//
#import <Foundation/Foundation.h>
#import "HaloPreferences.h"

NS_ASSUME_NONNULL_BEGIN

#define HALO_NEXUS_CONTROL_VERSION 1

@interface HaloNexusControl : NSObject

+ (NSInteger)controlVersion;

/// What HCG Nexus may show: enabled (master), target, panelBorderOn, state (engine), nexusState,
/// nexusDetail, haloVersion. Values come from HCG Halo's own settings and status.
+ (NSDictionary<NSString *, id> *)nexusBorderStatus;

/// YES if the setting now matches `enabled` (also when nothing had to change). NO with a reason, and
/// nothing written, when refused.
+ (BOOL)setNexusBorderEnabled:(BOOL)enabled error:(NSString *_Nullable *_Nullable)error;

/// The rules above as a pure function (for tests): the keys to write, empty when nothing changes, or nil
/// with a reason when refused.
+ (nullable NSDictionary<NSString *, id> *)changesForNexusBorderEnabled:(BOOL)enabled
                                                           masterEnabled:(BOOL)masterEnabled
                                                                  target:(HaloTarget)target
                                                              killSwitch:(BOOL)killSwitch
                                                            autoDisabled:(BOOL)autoDisabled
                                                                  reason:(NSString *_Nullable *_Nullable)reason;
@end

NS_ASSUME_NONNULL_END
