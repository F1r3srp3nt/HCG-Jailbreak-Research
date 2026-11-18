//
//  VortexTornado.h
//  HCG Vortex — Hakmi Capital Group
//
//  Pure C geometry for the Tornado effect: per-ICON visuals (the page-level
//  effects only move whole pages). No UIKit, no ObjC, no allocation, no
//  hidden state: every visual is a function of the gesture progress, so
//  pausing holds the formation, reversing unwinds it and cancelling returns
//  to the grid. Unit-tested on the host by tests/test_math.c.
//
//  Model (all lengths in points, relative to the page centre; +y is down):
//    - Each icon has a slot: its grid position (home) and a rank 0..1
//      (row-major order: top-left icon 0, bottom-right icon 1).
//    - A helical funnel: wide opening at the top, narrow tip at the bottom,
//      `rotations` spiral turns around a vertical axis whose centre travels
//      across the screen with the swipe. Icons sit ALONG the helix in rank
//      order; the incoming page's icons are interleaved half a step apart, so
//      at mid-swipe both pages form one continuous funnel.
//    - Per-page travel u: outgoing u = progress, incoming u = 1 - progress.
//      0..~0.45: icons lift out of the grid and gather (top rows first);
//      then they climb and swirl along the funnel, which turns with the
//      gesture; 0.72..0.97: they fade. Incoming icons run the same path
//      backwards, unwinding out of the funnel into their grid positions.
//    - Icons stay facing the viewer (readable) unless iconSpin is set.
//

#ifndef HCG_VORTEX_TORNADO_H
#define HCG_VORTEX_TORNADO_H

#include "VortexTypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VortexSpinFollowSwipe = 0,   ///< Finger swipes left -> front of the funnel moves left.
    VortexSpinClockwise,         ///< Clockwise seen from above the funnel.
    VortexSpinCounterclockwise,
    VortexSpinCount
} VortexSpinDirection;

typedef enum {
    VortexTravelFollowSwipe = 0, ///< The funnel crosses the screen in the finger's direction.
    VortexTravelAgainstSwipe,    ///< ... in the opposite direction.
    VortexTravelCentred,         ///< The funnel stays centred.
    VortexTravelCount
} VortexTravelMode;

typedef struct {
    double intensity;            ///< 0.1 .. 1.0: how fast the funnel turns and how far icons climb.
    double radius;               ///< 0.15 .. 0.60: upper opening radius, fraction of page width.
    double tipRadius;            ///< 0.02 .. 0.25: lower tip radius, fraction of page width (< radius).
    double height;               ///< 0.35 .. 0.85: funnel height, fraction of page height (centred 8 % above the page centre).
    double rotations;            ///< 0.5 .. 3.0: turns of each spiral strand from opening to tip.
    VortexSpinDirection direction;
    VortexTravelMode travel;
    double depth;                ///< 0 .. 1: perspective scale, depth ordering and back-side dimming.
    int iconSpin;                ///< Bool: icons also rotate about their own centres (off = readable).
} VortexTornadoParameters;

/// What one icon should look like, relative to its grid position.
typedef struct {
    double tx, ty;               ///< Offset from the grid position, points.
    double scale;                ///< 1 = neutral.
    double rotation;             ///< Radians about the icon's own centre (screen plane). 0 = neutral.
    double tiltX, tiltY;         ///< Radians: 3-D tilt about the icon's horizontal / vertical axis. 0 = neutral.
    double z;                    ///< Depth (points, + towards the viewer), for ordering only. 0 = neutral.
    double opacity;              ///< 0..1 multiplier.
} VortexIconVisual;

typedef struct {
    double homeX, homeY;         ///< Icon centre relative to the page centre, points.
    double rank;                 ///< 0..1, row-major order (0 = top-left icon, 1 = bottom-right).
    int index;                   ///< Stable order on the page.
    int count;                   ///< Icons ranked together on this page.
} VortexIconSlot;

#define VORTEX_TORNADO_MAX_ICONS 64

/// Classic Tornado (the default preset).
VortexTornadoParameters vortex_tornado_defaults(void);

typedef enum {
    VortexTornadoPresetSubtle = 0,
    VortexTornadoPresetClassic,
    VortexTornadoPresetSciFi,
    VortexTornadoPresetCount
} VortexTornadoPreset;
VortexTornadoParameters vortex_tornado_preset(VortexTornadoPreset preset);
VortexTornadoParameters vortex_tornado_sanitize(VortexTornadoParameters p);

VortexIconVisual vortex_icon_identity(void);
int vortex_icon_is_identity(VortexIconVisual v);

/// +1: the front of the funnel moves towards +x (screen right); -1: towards -x.
double vortex_tornado_spin_sign(VortexSpinDirection direction, VortexNavigationDirection navigation);

/// Fill rank and index for n slots from their home positions (row-major,
/// rows grouped within `rowTolerance` points). n <= VORTEX_TORNADO_MAX_ICONS.
void vortex_tornado_rank(VortexIconSlot *slots, int n, double rowTolerance);

/// Page-level visual for a Tornado page: pinned to the screen centre so the
/// funnel can be laid out in screen space; brief fades only at the very ends
/// (non-icon content). Satisfies the shared page contract.
VortexPageVisual vortex_tornado_page(VortexPageRole role, double progress, const VortexEffectParameters *params);

/// Per-icon visual. progress is the RAW transition progress (0..1); speed and
/// easing from `params` are applied inside, exactly as for page effects.
/// Contract (tested):
///   progress 0: outgoing icons identity, incoming icons opacity 0
///   progress 1: incoming icons identity, outgoing icons opacity 0
///   continuous in progress for every slot and parameter set.
VortexIconVisual vortex_tornado_icon(VortexPageRole role,
                                     double progress,
                                     VortexNavigationDirection navigation,
                                     VortexIconSlot slot,
                                     double pageWidth,
                                     double pageHeight,
                                     const VortexTornadoParameters *tornado,
                                     const VortexEffectParameters *params);

/// Explicit fallback for page content that is not an ordinary app icon
/// (widgets, oversized views): stays in place and cross-fades.
VortexIconVisual vortex_tornado_fallback_icon(VortexPageRole role,
                                              double progress,
                                              const VortexEffectParameters *params);

/// Funnel axis centre x (points from the page centre) at a raw progress.
/// Exposed for tests and the preview.
double vortex_tornado_centre_x(double progress, VortexNavigationDirection navigation, double pageWidth,
                               VortexTravelMode travel, const VortexEffectParameters *params);

#ifdef __cplusplus
}
#endif

#endif /* HCG_VORTEX_TORNADO_H */
