//
//  HaloScreen.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloScreen.h"

#include <sys/utsname.h>

HaloScreenMeasure HaloCurrentScreenMeasure(void) {
    UIScreen *screen = UIScreen.mainScreen;
    CGSize points = screen.fixedCoordinateSpace.bounds.size;
    CGSize pixels = screen.nativeBounds.size; // always portrait, in pixels
    HaloScreenMeasure m = {points.width, points.height, pixels.width, pixels.height};
    return m;
}

NSString *HaloMachineIdentifier(void) {
    const char *simulated = getenv("SIMULATOR_MODEL_IDENTIFIER"); // the iOS Simulator's emulated model
    if (simulated && *simulated) return @(simulated);
    struct utsname info;
    if (uname(&info) != 0) return @"unknown";
    return @(info.machine);
}

NSString *HaloScreenSummary(void) {
    UIScreen *screen = UIScreen.mainScreen;
    HaloScreenMeasure m = HaloCurrentScreenMeasure();
    NSMutableString *text = [NSMutableString
        stringWithFormat:@"%.0f × %.0f pt @%.0fx", m.pointWidth, m.pointHeight, screen.scale];
    if (m.pixelWidth > 0 && m.pixelHeight > 0) {
        [text appendFormat:@" · %.0f × %.0f px", m.pixelWidth, m.pixelHeight];
        if (fabs(screen.nativeScale - screen.scale) > 0.01)
            [text appendFormat:@" (native scale %.2f)", screen.nativeScale];
    }
    return text;
}

NSString *HaloScreenFitSentence(const HaloProfile *profile, HaloScreenMeasure m) {
    if (!profile || !profile->implemented) return @"";
    double k = 1;
    HaloScreenFit fit = halo_profile_fit(profile, m, &k);
    double pw = profile->screenWidth, ph = profile->screenHeight;
    double xw = pw * profile->scale, xh = ph * profile->scale;
    switch (fit) {
    case HaloScreenFitMatch:
        return [NSString stringWithFormat:@"Screen size matches %s (%.0f × %.0f pt).", profile->name, pw, ph];
    case HaloScreenFitDisplayZoom:
        return [NSString
            stringWithFormat:@"Display Zoom: this screen reports %.0f × %.0f pt, the zoomed size of %s (%.0f × %.0f pt on "
                             @"the same %.0f × %.0f px panel). HCG Halo scales the profile's corners and notch by %.3f "
                             @"so they still match the glass.",
                             fmin(m.pointWidth, m.pointHeight), fmax(m.pointWidth, m.pointHeight), profile->name, pw,
                             ph, xw, xh, k];
    case HaloScreenFitMismatch:
        return [NSString
            stringWithFormat:@"MISMATCH: this screen is %.0f × %.0f pt (%.0f × %.0f px) but %s is %.0f × %.0f pt "
                             @"(%.0f × %.0f px): a different display, not Display Zoom. The border is fitted to the "
                             @"screen edge, but the profile's corners and notch will not line up. Choose this iPhone's "
                             @"profile.",
                             fmin(m.pointWidth, m.pointHeight), fmax(m.pointWidth, m.pointHeight),
                             fmin(m.pixelWidth, m.pixelHeight), fmax(m.pixelWidth, m.pixelHeight), profile->name, pw,
                             ph, xw, xh];
    case HaloScreenFitUnknown:
    default:
        return @"The screen size could not be read.";
    }
}

BOOL HaloDeviceHasAlwaysOnDisplay(NSString *machine) {
    // iPhone 14 Pro / Pro Max (iPhone15,2 / 15,3), 15 Pro / Pro Max (iPhone16,1 / 16,2),
    // 16 Pro / Pro Max (iPhone17,1 / 17,2), and the 2025 iPhone 17 line (iPhone18,1–18,4).
    // Only the wording in Settings depends on this list.
    static NSSet<NSString *> *models;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        models = [NSSet setWithArray:@[ @"iPhone15,2", @"iPhone15,3", @"iPhone16,1", @"iPhone16,2", @"iPhone17,1",
                                        @"iPhone17,2", @"iPhone18,1", @"iPhone18,2", @"iPhone18,3", @"iPhone18,4" ]];
    });
    return [models containsObject:machine];
}
