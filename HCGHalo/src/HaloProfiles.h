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

#ifdef __cplusplus
}
#endif

#endif /* HALO_PROFILES_H */
