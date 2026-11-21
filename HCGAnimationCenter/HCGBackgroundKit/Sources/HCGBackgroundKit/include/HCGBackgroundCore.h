//
//  HCGBackgroundCore.h
//  HCGBackgroundKit — Hakmi Capital Group
//
//  The pure C core of the HCG background preset format: limits, layout
//  geometry (fill / fit / crop), the numeric rules every preset obeys, and
//  GIF frame timing. No Foundation, no UIKit: the same code runs in the
//  SpringBoard tweak, the Settings bundle, any app that adopts
//  HCGBackgroundKit, and the Linux host tests (tests/test_core.c).
//
//  Coordinates: sizes and rectangles are in the caller's units (points or
//  pixels); a crop rectangle is normalised to the media's DISPLAY size
//  (after its rotation), origin top-left, so (0, 0, 1, 1) is the whole frame.
//

#ifndef HCG_BACKGROUND_CORE_H
#define HCG_BACKGROUND_CORE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- Format identity -------------------------------------------------------

/// Value of the "format" key in every preset document.
#define HCGBG_FORMAT_ID "com.hakmicapitalgroup.background-preset"
/// The major format version this code reads and writes. A document with a
/// higher major version is refused (never guessed at); unknown keys inside a
/// supported version are ignored, so minor additions stay compatible.
#define HCGBG_FORMAT_VERSION 1

// ---- Limits ----------------------------------------------------------------

#define HCGBG_SPEED_MIN 0.25
#define HCGBG_SPEED_MAX 2.0
#define HCGBG_SPEED_DEFAULT 1.0
/// Shortest playable clip after trimming, seconds.
#define HCGBG_MIN_CLIP_SECONDS 0.5
/// Longest source a preset may describe, seconds (10 minutes).
#define HCGBG_MAX_SOURCE_SECONDS 600.0
/// Media pixel dimensions accepted in a preset.
#define HCGBG_MIN_DIMENSION 16
#define HCGBG_MAX_DIMENSION 8192
/// Smallest crop side, as a fraction of the media (a 10x zoom).
#define HCGBG_CROP_MIN 0.1
/// Largest crop zoom the editor offers (1 / HCGBG_CROP_MIN).
#define HCGBG_ZOOM_MAX 10.0

// ---- Enumerations (stable identifiers are the JSON strings) -----------------

typedef enum {
    HCGBGScalingFill = 0, ///< "fill": aspect-fill the whole frame (the default)
    HCGBGScalingFit = 1,  ///< "fit": aspect-fit, bars in the background colour
    HCGBGScalingCrop = 2, ///< "crop": aspect-fill the chosen crop rectangle
} HCGBGScaling;

typedef struct {
    double x, y, width, height;
} HCGBGRect;

typedef struct {
    double width, height;
} HCGBGSize;

/// "fill" | "fit" | "crop", or NULL for an out-of-range value.
const char *hcgbg_scaling_id(HCGBGScaling scaling);
/// Parses an identifier; returns false (and leaves *out alone) if unknown.
bool hcgbg_scaling_parse(const char *identifier, HCGBGScaling *out);

// ---- Geometry --------------------------------------------------------------

/// A crop rectangle made valid: finite, each side in [HCGBG_CROP_MIN, 1],
/// inside the unit square. A non-finite rectangle becomes (0, 0, 1, 1).
HCGBGRect hcgbg_crop_clamp(HCGBGRect crop);

/// Where to draw the WHOLE media frame, in container coordinates, so the
/// container shows what the scaling asks for:
///   fill — the frame covers the container, centred;
///   fit  — the frame fits inside the container, centred;
///   crop — the crop rectangle covers the container, centred on the crop's
///          centre, then moved the least distance needed so the frame still
///          covers the container (no gaps at the edges).
/// Degenerate inputs (zero, negative or non-finite sizes) return the
/// container rectangle itself.
HCGBGRect hcgbg_layout(HCGBGSize container, HCGBGSize media, HCGBGScaling scaling, HCGBGRect crop);

/// The crop rectangle the editor's zoom and centre describe for a container
/// of this aspect: the region a "fill" shows, shrunk by zoom (>= 1), centred
/// at (centerX, centerY) (normalised media coordinates) and kept inside the
/// frame.
HCGBGRect hcgbg_crop_from_zoom(HCGBGSize container, HCGBGSize media, double zoom, double centerX, double centerY);

/// The editor's zoom (>= 1) for an existing crop rectangle in this container.
double hcgbg_zoom_for_crop(HCGBGSize container, HCGBGSize media, HCGBGRect crop);

// ---- Playback numbers --------------------------------------------------------

typedef struct {
    double duration;   ///< source duration, seconds (> 0)
    double trimStart;  ///< seconds, >= 0
    double trimEnd;    ///< seconds; <= 0 means "to the end"
    double speed;      ///< playback rate
    double posterTime; ///< seconds into the source for the still
    double width;      ///< media display width, pixels
    double height;     ///< media display height, pixels
    HCGBGRect crop;
} HCGBGPlayback;

/// Problems hcgbg_playback_sanitize found. Values that can be repaired are
/// repaired (and flagged); a preset with any "fatal" flag must be refused.
typedef enum {
    HCGBGIssueNone = 0,
    HCGBGIssueDurationInvalid = 1 << 0,  ///< fatal: not finite, <= 0 or too long
    HCGBGIssueDimensionsInvalid = 1 << 1, ///< fatal: outside the dimension limits
    HCGBGIssueTrimClamped = 1 << 2,
    HCGBGIssueSpeedClamped = 1 << 3,
    HCGBGIssuePosterClamped = 1 << 4,
    HCGBGIssueCropClamped = 1 << 5,
    HCGBGIssueClipTooShort = 1 << 6,     ///< fatal: the source is shorter than the minimum clip
} HCGBGIssue;

#define HCGBG_FATAL_ISSUES (HCGBGIssueDurationInvalid | HCGBGIssueDimensionsInvalid | HCGBGIssueClipTooShort)

/// Repairs what can be repaired and reports every issue (bitwise OR of
/// HCGBGIssue). After it returns without a fatal issue:
///   0 <= trimStart < trimEnd <= duration, trimEnd - trimStart >= min clip,
///   speed in [min, max], trimStart <= posterTime <= trimEnd, crop clamped.
unsigned hcgbg_playback_sanitize(HCGBGPlayback *playback);

/// The trimmed clip's length at speed 1, seconds (0 if invalid).
double hcgbg_clip_seconds(const HCGBGPlayback *playback);

// ---- GIF timing (import) ------------------------------------------------------

/// The delay a browser would use for a GIF frame: delays of 10 ms or less
/// (including 0 and missing) are shown for 100 ms; at most 10 s.
double hcgbg_gif_frame_delay(double declared);

/// Output size for transcoding: the source scaled down (never up) so its
/// longer side is at most maxLongSide, both sides even and at least 16.
HCGBGSize hcgbg_even_fit(HCGBGSize source, double maxLongSide);

// ---- Colours --------------------------------------------------------------

/// Parses "#RRGGBB" (case-insensitive) into components in [0, 1].
bool hcgbg_parse_hex_colour(const char *text, double *r, double *g, double *b);

// ---- Orientation and transformation (kit 1.1; format v1 minor addition) ------
//
// A preset's optional "layout.transform" rotates (clockwise, in quarter turns)
// and flips the picture AFTER the source's own orientation metadata, and can
// stretch it to the container. Everything above this section is unchanged, so
// renderers that predate it (and copies vendored elsewhere) keep their exact
// behaviour; they simply ignore the transform.
//
// Frames: "media" is the display size after the source's metadata rotation
// (as in a preset); "oriented" is that size after the user's rotation (sides
// swapped for 90 / 270). The crop rectangle (zoom and position) is normalised
// to the ORIENTED, flipped picture — what the viewer sees.

typedef struct {
    int rotation;          ///< 0, 90, 180 or 270 degrees clockwise
    bool flipHorizontal;   ///< mirror left / right (after rotating)
    bool flipVertical;     ///< mirror top / bottom (after rotating)
    bool stretch;          ///< fill the container exactly, ignoring the aspect ratio
    /// The preset has a transform object: "fit" and "stretch" then use the
    /// crop rectangle as the region to show (zoom and position for every
    /// mode). Without it, "fit" shows the whole frame, as before.
    bool regionAllModes;
} HCGBGTransform;

/// No rotation, no flip, no stretch, legacy region rules.
HCGBGTransform hcgbg_transform_identity(void);
/// True if it changes nothing (rotation 0, no flips, no stretch).
bool hcgbg_transform_is_identity(HCGBGTransform t);

/// Degrees to the nearest quarter turn in [0, 360): 450 → 90, -90 → 270,
/// 100 → 90. *exact is set to whether the input already was a quarter turn
/// (finite and a multiple of 90). Non-finite → 0, not exact.
int hcgbg_rotation_normalize(double degrees, bool *exact);

/// The quarter turn a video track's preferred transform (a, b, c, d of its
/// affine matrix) applies, for reporting the source's orientation metadata;
/// -1 if it is not a quarter turn (skew or arbitrary angle). Mirroring in the
/// metadata is reported through *mirrored.
int hcgbg_rotation_from_matrix(double a, double b, double c, double d, bool *mirrored);

/// The media size after a rotation (width and height swapped for 90 / 270).
HCGBGSize hcgbg_oriented_size(HCGBGSize media, int rotation);

typedef struct {
    HCGBGRect frame;       ///< the transformed picture's bounding box, container coordinates
    HCGBGSize bounds;      ///< the untransformed layer's size (frame size, swapped for 90 / 270)
    double a, b, c, d;     ///< 2×2 matrix to apply about the frame's centre: rotate, then flip
} HCGBGPlacement;

/// Lays out a transformed picture:
///   stretch          — the region (crop with regionAllModes, else the whole
///                      frame) is scaled non-uniformly onto the container;
///   fit              — the region fits inside the container, centred on the
///                      region's centre (whole frame without regionAllModes);
///   fill / crop      — exactly hcgbg_layout() on the oriented size.
/// Without a transform (identity, no regionAllModes) the frame equals
/// hcgbg_layout()'s for the same inputs and the matrix is the identity.
HCGBGPlacement hcgbg_layout_transformed(HCGBGSize container, HCGBGSize media, HCGBGScaling scaling, HCGBGRect crop,
                                        HCGBGTransform transform);

/// The region (crop rectangle) for an editor's zoom (>= 1) and centre, in
/// the oriented frame: fill / crop as hcgbg_crop_from_zoom(); fit and stretch
/// start from the whole frame. Kept inside the frame.
HCGBGRect hcgbg_region_from_zoom(HCGBGScaling scaling, bool stretch, HCGBGSize container, HCGBGSize oriented,
                                 double zoom, double centerX, double centerY);
/// Inverse of hcgbg_region_from_zoom() (zoom >= 1).
double hcgbg_zoom_for_region(HCGBGScaling scaling, bool stretch, HCGBGSize container, HCGBGSize oriented,
                             HCGBGRect region);

#ifdef __cplusplus
}
#endif

#endif
