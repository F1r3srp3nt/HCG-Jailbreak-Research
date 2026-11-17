//
//  HaloProfiles.c
//  HCG Halo — Hakmi Capital Group
//
//  Lookup and calibration. The table is in HaloProfiles.generated.c.
//

#include "HaloProfiles.h"

#include <math.h>
#include <string.h>

int halo_profile_count(void) {
    return kHaloProfileCount;
}

const HaloProfile *halo_profile_at(int index) {
    if (index < 0 || index >= kHaloProfileCount) return NULL;
    return &kHaloProfiles[index];
}

const HaloProfile *halo_profile_find(const char *identifier) {
    if (!identifier || strcmp(identifier, HALO_PROFILE_AUTOMATIC) == 0) return NULL;
    for (int i = 0; i < kHaloProfileCount; i++) {
        if (strcmp(kHaloProfiles[i].identifier, identifier) == 0) return &kHaloProfiles[i];
    }
    return NULL;
}

const char *halo_default_profile_id(void) {
    return kHaloDefaultProfileID;
}

static double clamp(double v, double lo, double hi) {
    if (!isfinite(v)) return 0;
    return v < lo ? lo : (v > hi ? hi : v);
}

HaloCalibration halo_sanitize_calibration(HaloCalibration c) {
    c.cornerRadius = clamp(c.cornerRadius, HALO_CAL_CORNER_MIN, HALO_CAL_CORNER_MAX);
    c.notchWidth = clamp(c.notchWidth, HALO_CAL_NOTCH_WIDTH_MIN, HALO_CAL_NOTCH_WIDTH_MAX);
    c.notchHeight = clamp(c.notchHeight, HALO_CAL_NOTCH_HEIGHT_MIN, HALO_CAL_NOTCH_HEIGHT_MAX);
    c.notchOffsetX = clamp(c.notchOffsetX, HALO_CAL_NOTCH_OFFSET_MIN, HALO_CAL_NOTCH_OFFSET_MAX);
    return c;
}

HaloDisplayGeometry halo_profile_geometry(const HaloProfile *profile, HaloCalibration calibration) {
    HaloDisplayGeometry g;
    memset(&g, 0, sizeof g);
    if (!profile || !profile->implemented) return halo_sanitize_geometry(g);
    HaloCalibration c = halo_sanitize_calibration(calibration);
    g = profile->geometry;
    g.cornerRadius += c.cornerRadius;
    if (g.cutout == HaloCutoutNotch) {
        g.notchWidth += c.notchWidth;
        g.notchHeight += c.notchHeight;
        g.notchOffsetX += c.notchOffsetX;
    }
    return halo_sanitize_geometry(g);
}

int halo_profile_matches_screen(const HaloProfile *profile, double width, double height) {
    if (!profile || !profile->implemented) return 0;
    double w = profile->screenWidth, h = profile->screenHeight;
    return (fabs(width - w) < 0.5 && fabs(height - h) < 0.5) || (fabs(width - h) < 0.5 && fabs(height - w) < 0.5);
}
