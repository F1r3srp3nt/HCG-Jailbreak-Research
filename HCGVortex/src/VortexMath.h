//
//  VortexMath.h
//  HCG Vortex — Hakmi Capital Group
//
//  Pure C animation math: easing, the 8-way direction matrix, the
//  navigation state machine and the per-page solver. No UIKit, no ObjC,
//  no allocation. Unit-tested on the host by tests/test_math.c.
//

#ifndef HCG_VORTEX_MATH_H
#define HCG_VORTEX_MATH_H

#include "VortexTypes.h"

#ifdef __cplusplus
extern "C" {
#endif

#define VORTEX_SETTLE_EPSILON 0.0005   /* page units: |delta| below this == settled */
#define VORTEX_SMOOTH_SNAP    0.0002   /* page units: smoothing snaps when this close */
#define VORTEX_SMOOTH_MAX_GAP 3.0      /* page units: larger jumps snap immediately */

/* ---- Parameters ---------------------------------------------------------- */

VortexEffectParameters vortex_default_parameters(void);
/// Clamp every field into its valid range; unknown easing -> linear.
VortexEffectParameters vortex_sanitize_parameters(VortexEffectParameters p);

/* ---- Directions ---------------------------------------------------------- */

/// Unit-ish vector for a direction (diagonals are (±1,±1): a page leaving
/// diagonally must clear both the width and the height of the screen).
VortexVec2 vortex_direction_vector(VortexDirection d);
VortexDirection vortex_direction_opposite(VortexDirection d);
/// Persisted identifiers: "left","right","up","down","up-left","up-right",
/// "down-left","down-right". Returns VortexDirectionNone for unknown input.
VortexDirection vortex_direction_from_string(const char *s);
const char *vortex_direction_to_string(VortexDirection d);

/* ---- Easing / timing ----------------------------------------------------- */

double vortex_clamp01(double t);
/// Easing curve. f(0)=0, f(1)=1, monotonic for every supported mode.
double vortex_ease(VortexEasing easing, double t);
/// Speed time-warp: t^(1/speed). speed>1 completes the visual transition
/// earlier in the gesture; endpoints are preserved so there is never a jump.
double vortex_speed_warp(double t, double speed);
/// ease(warp(t)) — the presented progress for a raw gesture progress.
double vortex_presented_progress(double t, const VortexEffectParameters *p);

/// Exponential smoothing of the presented scroll position towards the real
/// one. duration<=0 tracks exactly. ~99% converged after `duration` seconds.
double vortex_smooth_step(double presented, double target, double dt, double duration);

/* ---- Effects ------------------------------------------------------------- */

/// Direction an INCOMING page enters from, and an OUTGOING page exits
/// towards, for a built-in effect and a navigation direction.
void vortex_builtin_directions(VortexBuiltinEffect effect,
                               VortexNavigationDirection nav,
                               VortexDirection *incomingFrom,
                               VortexDirection *outgoingTo);

VortexBuiltinEffect vortex_builtin_effect_from_string(const char *s, int *ok);
const char *vortex_builtin_effect_to_string(VortexBuiltinEffect e);

/// Generic directional transition — the basis of every v0.1.0 effect.
/// `progress` is the RAW transition progress 0..1 (outgoing fully on screen
/// at 0, incoming fully on screen at 1); easing/speed are applied inside.
///
/// Invariants (tested):
///   progress 0 -> outgoing at (0,0) opacity 1; incoming fully off-screen.
///   progress 1 -> incoming at (0,0) opacity 1; outgoing off-screen or opacity 0.
VortexPageVisual vortex_directional_visual(VortexPageRole role,
                                           double progress,
                                           VortexDirection incomingFrom,
                                           VortexDirection outgoingTo,
                                           const VortexEffectParameters *params);

VortexPageVisual vortex_identity_visual(void);
int vortex_visual_is_identity(VortexPageVisual v);

/* ---- Navigation state machine ------------------------------------------- */

typedef struct {
    double base;      ///< Position (page units) of the page the transition started from.
    int hasBase;
} VortexNavState;

typedef struct {
    int inRange;                          ///< 0 = presented position is outside the icon pages
                                          ///<     (Today View / App Library): leave everything stock.
    int active;                           ///< 0 = settled or outside the icon pages.
    VortexNavigationDirection direction;
    double progress;                      ///< 0..1 raw progress from base towards neighbour.
    double base;
} VortexNavSnapshot;

void vortex_nav_reset(VortexNavState *state);

/// Advance the state machine.
///  presented: presented scroll position in page units (centre of viewport / pitch)
///  positions: page-centre positions (page units) of the ICON pages only.
/// Positions outside [min,max] (Today View, App Library) make the snapshot
/// inactive so those transitions stay 100% stock.
VortexNavSnapshot vortex_nav_step(VortexNavState *state,
                                  double presented,
                                  const double *positions,
                                  int count);

/// Role of the page at `position` within `snap`.
VortexPageRole vortex_nav_role(const VortexNavSnapshot *snap, double position);

/* ---- Solver -------------------------------------------------------------- */

/// Final translation (page units) that must be applied to a page so it
/// APPEARS at `visual.translation`, given that the scroll view actually
/// places it at (position - actual). Returned visual has the corrected
/// translation; other fields are passed through.
VortexPageVisual vortex_solve_page(VortexPageVisual desired, double position, double actual);

/// Effect callback used by the composer (the ObjC effect registry provides a
/// trampoline; tests provide plain C functions).
typedef VortexPageVisual (*VortexEffectFunction)(void *context,
                                                 VortexPageRole role,
                                                 double progress,
                                                 VortexNavigationDirection direction,
                                                 const VortexEffectParameters *params);

/// Full per-page pipeline shared by the engine and the unit tests:
///   out of range        -> identity (stock behaviour)
///   role none           -> page kept at its *presented* natural position
///   outgoing / incoming -> effect visual
/// then compensated for the page's actual scroll position.
///  position:  page centre (page units)
///  presented: presented scroll position (may lag `actual` when smoothing)
///  actual:    real scroll position from the scroll view
VortexPageVisual vortex_compose_page(const VortexNavSnapshot *snap,
                                     double position,
                                     double presented,
                                     double actual,
                                     VortexEffectFunction effect,
                                     void *context,
                                     const VortexEffectParameters *params);

#ifdef __cplusplus
}
#endif

#endif /* HCG_VORTEX_MATH_H */
