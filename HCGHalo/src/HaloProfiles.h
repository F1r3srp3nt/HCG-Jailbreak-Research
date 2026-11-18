//
//  HaloProfiles.h
//  HCG Halo — Hakmi Capital Group
//
//  Device profiles. The table itself is generated from data/profiles.json
//  into HaloProfiles.generated.c by scripts/generate.py (validate.sh fails if
//  it is stale). Pure C; unit-tested on the build host.
//
//  "Implemented" means the geometry is entered and the profile can be
//  selected. It is NOT a claim that the profile has been tested on a device:
//  that is the separate `deviceTested` flag, false until a test is recorded.
//

#ifndef HALO_PROFILES_H
#define HALO_PROFILES_H

#include "HaloGeometry.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *identifier;
    const char *name;
    const char *machines;     // comma-separated hw.machine identifiers (informational)
    int implemented;          // selectable, geometry present
    int deviceTested;         // observed on a real device (recorded in docs/PROFILES.md)
    double screenWidth;       // portrait points
    double screenHeight;
    double scale;
    HaloDisplayGeometry geometry;
    const char *sources;      // where the reference values come from
} HaloProfile;

/// Manual calibration, applied on top of a profile (deltas, points).
typedef struct {
    double cornerRadius;  // added to the profile's corner radius
    double notchWidth;    // added to the notch width
    double notchHeight;   // added to the notch depth
    double notchOffsetX;  // horizontal shift of the notch
} HaloCalibration;

#define HALO_CAL_CORNER_MIN (-20.0)
#define HALO_CAL_CORNER_MAX 20.0
#define HALO_CAL_NOTCH_WIDTH_MIN (-40.0)
#define HALO_CAL_NOTCH_WIDTH_MAX 40.0
#define HALO_CAL_NOTCH_HEIGHT_MIN (-15.0)
#define HALO_CAL_NOTCH_HEIGHT_MAX 15.0
#define HALO_CAL_NOTCH_OFFSET_MIN (-20.0)
#define HALO_CAL_NOTCH_OFFSET_MAX 20.0

/// Reserved identifier for automatic detection. It is NOT implemented: it is
/// never accepted as a stored value and the Settings row is disabled.
#define HALO_PROFILE_AUTOMATIC "automatic"

/// The generated table (HaloProfiles.generated.c). Use the functions below.
extern const HaloProfile kHaloProfiles[];
extern const int kHaloProfileCount;
extern const char *const kHaloDefaultProfileID;

int halo_profile_count(void);
const HaloProfile *halo_profile_at(int index);
/// Returns NULL for unknown identifiers and for "automatic".
const HaloProfile *halo_profile_find(const char *identifier);
const char *halo_default_profile_id(void);

/// Clamps each calibration delta into range (non-finite values become 0).
HaloCalibration halo_sanitize_calibration(HaloCalibration calibration);

/// Profile geometry plus calibration, sanitised (halo_sanitize_geometry).
HaloDisplayGeometry halo_profile_geometry(const HaloProfile *profile, HaloCalibration calibration);

/// 1 if a screen of `width` x `height` points (either orientation) matches the profile.
int halo_profile_matches_screen(const HaloProfile *profile, double width, double height);

/// How the real screen relates to a profile.
typedef enum {
    HaloScreenFitUnknown = 0,     // no implemented profile, or no usable screen measurement
    HaloScreenFitMatch = 1,       // same point size: the profile applies as is
    HaloScreenFitDisplayZoom = 2, // same physical panel (same pixels), fewer points: Display Zoom
    HaloScreenFitMismatch = 3,    // a different display: the profile's corners and notch do not apply
} HaloScreenFit;

/// Measurement of the real screen (portrait or landscape; order does not matter).
typedef struct {
    double pointWidth, pointHeight; // UIScreen.fixedCoordinateSpace bounds (pt)
    double pixelWidth, pixelHeight; // UIScreen.nativeBounds (px); 0 if unknown
} HaloScreenMeasure;

/// Classifies the screen against the profile. *lengthScale receives the factor
/// from profile points to screen points for corner and notch lengths (1 unless
/// Display Zoom). Under Display Zoom the same panel is drawn with fewer, larger
/// points, so every physical length shrinks by the same factor in points.
HaloScreenFit halo_profile_fit(const HaloProfile *profile, HaloScreenMeasure screen, double *lengthScale);
const char *halo_screen_fit_id(HaloScreenFit fit);

/// Profile geometry for the real screen: width/height are the screen's points,
/// corner and notch lengths are scaled by halo_profile_fit()'s factor, then the
/// calibration deltas (screen points) are added and the result sanitised.
/// For a Mismatch the profile lengths are kept unscaled (the frame fits the
/// screen, but the corners and notch belong to another display).
HaloDisplayGeometry halo_profile_geometry_for_screen(const HaloProfile *profile, HaloCalibration calibration,
                                                     HaloScreenMeasure screen, HaloScreenFit *fit, double *lengthScale);

#ifdef __cplusplus
}
#endif

#endif /* HALO_PROFILES_H */
