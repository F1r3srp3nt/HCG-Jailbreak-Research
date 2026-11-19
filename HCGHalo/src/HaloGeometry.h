//
//  HaloGeometry.h
//  HCG Halo — Hakmi Capital Group
//
//  Pure C (no Apple frameworks) so it is unit-tested on the build host.
//
//  Builds the closed border path that the light follows, in the display's
//  FIXED portrait coordinate space (origin top-left, y down, points). The
//  path is the stroke's centre line, `offset` points inside the display edge.
//  It follows the display's rounded corners and, optionally, the outline of
//  the notch. The SpringBoard side maps it into the view's coordinate space,
//  so orientation is handled by one affine transform (HaloRenderer.m).
//
//  Direction: the path runs clockwise as seen on screen. Arcs are stored as
//  centre/radius/angles (y-down, atan2 convention: increasing angle is
//  clockwise on screen) and converted to cubic Béziers for Core Graphics by
//  halo_border_to_beziers(), so no Core Graphics arc-direction convention is
//  involved anywhere.
//

#ifndef HALO_GEOMETRY_H
#define HALO_GEOMETRY_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    HaloCutoutNone = 0,
    HaloCutoutNotch = 1,
} HaloCutoutKind;

/// Physical display outline in portrait points. Values come from a device
/// profile plus the user's calibration (HaloProfiles.h).
typedef struct {
    double width;            // portrait width (pt)
    double height;           // portrait height (pt)
    double cornerRadius;     // display corner radius (pt), circular approximation
    HaloCutoutKind cutout;
    double notchWidth;       // width of the notch body at the top edge (pt)
    double notchHeight;      // depth of the notch from the top edge (pt)
    double notchOuterRadius; // flare where the notch meets the top edge (pt)
    double notchInnerRadius; // the notch's two bottom corners (pt)
    double notchOffsetX;     // horizontal shift of the notch centre from the screen centre (pt)
} HaloDisplayGeometry;

typedef enum {
    HaloSegmentLine = 0,
    HaloSegmentArc = 1,
} HaloSegmentKind;

typedef struct {
    HaloSegmentKind kind;
    double x0, y0, x1, y1;      // start and end points
    double cx, cy, radius;      // arcs only
    double startAngle, endAngle; // arcs only (radians, y-down atan2 convention)
    double length;
} HaloSegment;

#define HALO_MAX_SEGMENTS 40
#define HALO_MAX_LANDMARKS 16

typedef struct {
    HaloSegment segments[HALO_MAX_SEGMENTS];
    int count;
    double length;                          // total perimeter of the centre line
    double landmarks[HALO_MAX_LANDMARKS];   // arc-length positions of corners / notch points (Sci-Fi Circuit nodes)
    int landmarkCount;
    int tracesCutout;                       // 1 if the path follows the notch outline
} HaloBorderPath;

typedef enum {
    HaloBezierMove = 0,
    HaloBezierLine = 1,
    HaloBezierCurve = 2,
    HaloBezierClose = 3,
} HaloBezierOpKind;

typedef struct {
    HaloBezierOpKind kind;
    double x, y;            // end point (move / line / curve)
    double c1x, c1y;        // curve control points
    double c2x, c2y;
} HaloBezierOp;

/// Returns `g` with every value finite, non-negative and mutually consistent:
/// the notch fits between the screen corners, its radii fit its depth, etc.
HaloDisplayGeometry halo_sanitize_geometry(HaloDisplayGeometry g);

/// Largest centre-line offset that still leaves a usable path for `g`.
double halo_max_offset(const HaloDisplayGeometry *g);

/// Builds the border centre line `offset` points inside the display edge.
/// traceCutout: follow the notch outline (1) or run straight along the top
/// edge behind it (0). Ignored when the geometry has no cutout.
/// Returns 1 on success, 0 if the geometry is unusable (out is then empty).
int halo_build_border(const HaloDisplayGeometry *g, double offset, int traceCutout, HaloBorderPath *out);

/// Point at arc length `s` (wrapped into [0, length)).
void halo_point_at(const HaloBorderPath *path, double s, double *x, double *y);

/// Converts the path into move/line/cubic/close operations (arcs split into
/// at most 90° pieces). Returns the number of operations written, or -1 if
/// `capacity` is too small.
int halo_border_to_beziers(const HaloBorderPath *path, HaloBezierOp *ops, int capacity);

#ifdef __cplusplus
}
#endif

#endif /* HALO_GEOMETRY_H */
