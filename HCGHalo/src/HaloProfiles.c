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

static void portrait(double *w, double *h) {
    if (*w > *h) {
        double t = *w;
        *w = *h;
        *h = t;
    }
}

const char *halo_screen_fit_id(HaloScreenFit fit) {
    switch (fit) {
    case HaloScreenFitMatch: return "match";
    case HaloScreenFitDisplayZoom: return "displayZoom";
    case HaloScreenFitMismatch: return "mismatch";
    case HaloScreenFitUnknown:
    default: return "unknown";
    }
}

HaloScreenFit halo_profile_fit(const HaloProfile *profile, HaloScreenMeasure m, double *lengthScale) {
    if (lengthScale) *lengthScale = 1;
    if (!profile || !profile->implemented || !(profile->screenWidth > 0) || !(profile->screenHeight > 0))
        return HaloScreenFitUnknown;
    double pw = m.pointWidth, ph = m.pointHeight;
    if (!isfinite(pw) || !isfinite(ph) || !(pw > 0) || !(ph > 0)) return HaloScreenFitUnknown;
    portrait(&pw, &ph);
    if (halo_profile_matches_screen(profile, pw, ph)) return HaloScreenFitMatch;
    double xw = m.pixelWidth, xh = m.pixelHeight;
    if (isfinite(xw) && isfinite(xh) && xw > 0 && xh > 0 && profile->scale > 0) {
        portrait(&xw, &xh);
        double ew = profile->screenWidth * profile->scale, eh = profile->screenHeight * profile->scale;
        if (fabs(xw - ew) < 1.5 && fabs(xh - eh) < 1.5) {
            // Same panel. Display Zoom shows it with fewer points; both axes shrink
            // by the same factor (iOS rounds the point size, so allow 1 pt).
            double sx = pw / profile->screenWidth;
            if (sx < 1 && sx > 0.5 && fabs(sx * profile->screenHeight - ph) < 1.0 + 1e-9) {
                if (lengthScale) *lengthScale = sx;
                return HaloScreenFitDisplayZoom;
            }
        }
    }
    return HaloScreenFitMismatch;
}

HaloDisplayGeometry halo_profile_geometry_for_screen(const HaloProfile *profile, HaloCalibration calibration,
                                                     HaloScreenMeasure screen, HaloScreenFit *fitOut,
                                                     double *lengthScaleOut) {
    double k = 1;
    HaloScreenFit fit = halo_profile_fit(profile, screen, &k);
    if (fitOut) *fitOut = fit;
    if (lengthScaleOut) *lengthScaleOut = k;
    HaloDisplayGeometry g;
    memset(&g, 0, sizeof g);
    if (!profile || !profile->implemented) return halo_sanitize_geometry(g);
    g = profile->geometry;
    if (fit != HaloScreenFitUnknown) {
        double pw = screen.pointWidth, ph = screen.pointHeight;
        portrait(&pw, &ph);
        g.width = pw;
        g.height = ph;
    }
    g.cornerRadius *= k;
    g.notchWidth *= k;
    g.notchHeight *= k;
    g.notchOuterRadius *= k;
    g.notchInnerRadius *= k;
    g.notchOffsetX *= k;
    HaloCalibration c = halo_sanitize_calibration(calibration);
    g.cornerRadius += c.cornerRadius;
    if (g.cutout == HaloCutoutNotch) {
        g.notchWidth += c.notchWidth;
        g.notchHeight += c.notchHeight;
        g.notchOffsetX += c.notchOffsetX;
    }
    return halo_sanitize_geometry(g);
}
