//
//  HaloScreen.h
//  HCG Halo — Hakmi Capital Group
//
//  What the real screen measures, and how it relates to the selected device
//  profile. Shared by SpringBoard (geometry, status) and Settings (Device
//  Profile page), so both explain a mismatch the same way.
//
//  The measurement HCG Halo uses for the border is
//  UIScreen.mainScreen.fixedCoordinateSpace.bounds: the screen in POINTS,
//  portrait, whatever the interface orientation. Display Zoom ("Larger Text"
//  in Display & Brightness) shows the same panel with fewer points: an iPhone
//  11 Pro Max reports 375 × 812 pt instead of 414 × 896 pt while nativeBounds
//  stays 1242 × 2688 px. halo_profile_fit() tells that apart from a different
//  model by the pixel size.
//

#import <UIKit/UIKit.h>

#import "HaloProfiles.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Points from fixedCoordinateSpace, pixels from nativeBounds.
HaloScreenMeasure HaloCurrentScreenMeasure(void);
/// hw.machine, e.g. "iPhone12,5" ("arm64"/"x86_64" in the Simulator).
NSString *HaloMachineIdentifier(void);
/// "375 × 812 pt @3x · 1242 × 2688 px (native scale 3.31)".
NSString *HaloScreenSummary(void);
/// iPhone models with an Always-On display that HCG Halo knows of (by model identifier).
BOOL HaloDeviceHasAlwaysOnDisplay(NSString *machine);
/// One user-facing sentence about the fit (empty if no profile).
NSString *HaloScreenFitSentence(const HaloProfile *_Nullable profile, HaloScreenMeasure screen);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
