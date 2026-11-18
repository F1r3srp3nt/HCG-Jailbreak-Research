//
//  VortexIconEffects.h
//  HCG Vortex — Hakmi Capital Group
//
//  Every per-icon effect behind one dispatcher. Pure C: no UIKit, no ObjC,
//  no allocation, no hidden state. Each visual is a function of the raw
//  gesture progress (the shared, normalised progress model), so for every
//  effect pausing holds, reversing unwinds and cancelling restores.
//  Unit-tested by tests/test_icon_effects.c.
//
//  Shared model: each page has its own travel u (outgoing u = progress,
//  incoming u = 1 - progress). u = 0 is the icon in its grid; u = 1 is the
//  icon fully away (invisible, or off-screen with its page for Magnetic Grid).
//

#ifndef HCG_VORTEX_ICON_EFFECTS_H
#define HCG_VORTEX_ICON_EFFECTS_H

#include "VortexTornado.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VortexIconEffectTornado = 0,
    VortexIconEffectOrbital,
    VortexIconEffectWarp,
    VortexIconEffectHolographic,
    VortexIconEffectCircuitFlow,
    VortexIconEffectMagnetic,
    VortexIconEffectCount
} VortexIconEffectKind;

typedef struct {
    double radius;               ///< 0.20 .. 0.48: outer ring radius, fraction of page width.
    int rings;                   ///< 2 .. 5 concentric rings.
    double tilt;                 ///< 0 .. 1: ring-plane tilt (0 = flat circles, 1 = 70°), the depth variation.
    double speed;                ///< 0.25 .. 2.0: turns of the outer ring over a full swipe (inner rings faster).
    VortexSpinDirection direction;
} VortexOrbitalParameters;

typedef struct {
    double intensity;            ///< 0.1 .. 1.0: how deep icons travel into the tunnel.
    double perspective;          ///< 0.2 .. 1.0: camera closeness (strength of the perspective).
} VortexWarpParameters;

typedef struct {
    double depth;                ///< 0 .. 1: layer separation (parallax, float, translucency).
    double tilt;                 ///< 0 .. 1: 3-D tilt of the icons during the swipe (up to ~34°).
    int layers;                  ///< 2 .. 4 depth layers.
} VortexHoloParameters;

typedef struct {
    double trail;                ///< 0.1 .. 0.6: trail length, fraction of page width.
    double glow;                 ///< 0 .. 1: glow width/opacity around the trace.
    double intensity;            ///< 0.1 .. 1.0: trace brightness.
} VortexCircuitParameters;

typedef struct {
    double strength;             ///< 0.1 .. 1.0: how far icons separate (max ~14 pt).
    double snap;                 ///< 0 .. 1: the single small overshoot as icons lock into the grid (max ~3 pt).
} VortexMagneticParameters;

typedef struct {
    VortexTornadoParameters tornado;
    VortexOrbitalParameters orbital;
    VortexWarpParameters warp;
    VortexHoloParameters holo;
    VortexCircuitParameters circuit;
    VortexMagneticParameters magnetic;
} VortexIconEffectSettings;

VortexIconEffectSettings vortex_icon_settings_defaults(void);
VortexIconEffectSettings vortex_icon_settings_sanitize(VortexIconEffectSettings s);

/// 1: both pages are pinned to the screen centre and the icons do all the
/// moving. 0: pages move exactly as in iOS (Magnetic Grid).
int vortex_icon_effect_pins_pages(VortexIconEffectKind kind);

VortexPageVisual vortex_icon_effect_page(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                         VortexNavigationDirection navigation, const VortexEffectParameters *params);

/// Per-icon visual. Contract (tested for every kind, every role, 1..24 icons):
///   progress 0: outgoing identity; incoming opacity 0 (or, when pages are
///               not pinned, identity on an off-screen page)
///   progress 1: incoming identity; outgoing opacity 0 (same exception)
///   continuous in progress.
VortexIconVisual vortex_icon_effect_visual(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                           VortexNavigationDirection navigation, VortexIconSlot slot,
                                           double pageWidth, double pageHeight,
                                           const VortexIconEffectSettings *settings,
                                           const VortexEffectParameters *params);

/// Explicit fallback for widgets / oversized icon views.
VortexIconVisual vortex_icon_effect_fallback(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                             const VortexEffectParameters *params);

/// Circuit Flow's illuminated trace behind one icon: a polyline (points
/// relative to the page centre) and an alpha. count == 0 (nothing to draw)
/// for every other effect and at both ends of the swipe.
#define VORTEX_TRACE_MAX_POINTS 4
typedef struct {
    int count;
    VortexVec2 points[VORTEX_TRACE_MAX_POINTS];
    double alpha;                ///< 0..1 brightness of this trace segment.
} VortexTrace;

VortexTrace vortex_icon_effect_trace(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                     VortexNavigationDirection navigation, VortexIconSlot slot,
                                     double pageWidth, double pageHeight,
                                     const VortexIconEffectSettings *settings,
                                     const VortexEffectParameters *params);

#ifdef __cplusplus
}
#endif

#endif /* HCG_VORTEX_ICON_EFFECTS_H */
