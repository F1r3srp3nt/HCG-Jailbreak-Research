//
//  VortexMath.c
//  HCG Vortex — Hakmi Capital Group
//

#include "VortexMath.h"

#include <math.h>
#include <string.h>

/* ---- Parameters ---------------------------------------------------------- */

VortexEffectParameters vortex_default_parameters(void) {
    VortexEffectParameters p;
    p.intensity = 1.0;
    p.speed = 1.0;
    p.easing = VortexEasingLinear;
    p.fadePages = 0;
    p.reverse = 0;
    return p;
}

static double vortex_clamp(double v, double lo, double hi) {
    if (isnan(v)) return lo;
    return v < lo ? lo : (v > hi ? hi : v);
}

VortexEffectParameters vortex_sanitize_parameters(VortexEffectParameters p) {
    p.intensity = vortex_clamp(p.intensity, 0.1, 1.0);
    p.speed = vortex_clamp(p.speed, 0.25, 4.0);
    if ((int)p.easing < 0 || p.easing >= VortexEasingCount) p.easing = VortexEasingLinear;
    p.fadePages = p.fadePages ? 1 : 0;
    p.reverse = p.reverse ? 1 : 0;
    return p;
}

/* ---- Directions ---------------------------------------------------------- */

static const struct {
    VortexDirection dir;
    const char *name;
    double x, y;
} kDirectionTable[] = {
    { VortexDirectionLeft,      "left",       -1.0,  0.0 },
    { VortexDirectionRight,     "right",       1.0,  0.0 },
    { VortexDirectionUp,        "up",          0.0, -1.0 },
    { VortexDirectionDown,      "down",        0.0,  1.0 },
    { VortexDirectionUpLeft,    "up-left",    -1.0, -1.0 },
    { VortexDirectionUpRight,   "up-right",    1.0, -1.0 },
    { VortexDirectionDownLeft,  "down-left",  -1.0,  1.0 },
    { VortexDirectionDownRight, "down-right",  1.0,  1.0 },
};
#define kDirectionTableCount ((int)(sizeof(kDirectionTable) / sizeof(kDirectionTable[0])))

VortexVec2 vortex_direction_vector(VortexDirection d) {
    VortexVec2 v = { 0.0, 0.0 };
    for (int i = 0; i < kDirectionTableCount; i++) {
        if (kDirectionTable[i].dir == d) {
            v.x = kDirectionTable[i].x;
            v.y = kDirectionTable[i].y;
            break;
        }
    }
    return v;
}

VortexDirection vortex_direction_opposite(VortexDirection d) {
    VortexVec2 v = vortex_direction_vector(d);
    for (int i = 0; i < kDirectionTableCount; i++) {
        if (kDirectionTable[i].x == -v.x && kDirectionTable[i].y == -v.y) return kDirectionTable[i].dir;
    }
    return VortexDirectionNone;
}

VortexDirection vortex_direction_from_string(const char *s) {
    if (!s) return VortexDirectionNone;
    for (int i = 0; i < kDirectionTableCount; i++) {
        if (strcmp(kDirectionTable[i].name, s) == 0) return kDirectionTable[i].dir;
    }
    return VortexDirectionNone;
}

const char *vortex_direction_to_string(VortexDirection d) {
    for (int i = 0; i < kDirectionTableCount; i++) {
        if (kDirectionTable[i].dir == d) return kDirectionTable[i].name;
    }
    return "none";
}

/* ---- Easing / timing ----------------------------------------------------- */

double vortex_clamp01(double t) {
    return vortex_clamp(t, 0.0, 1.0);
}

double vortex_ease(VortexEasing easing, double t) {
    t = vortex_clamp01(t);
    switch (easing) {
        case VortexEasingEaseIn:
            return t * t * t;
        case VortexEasingEaseOut: {
            double u = 1.0 - t;
            return 1.0 - u * u * u;
        }
        case VortexEasingEaseInOut:
            return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
        case VortexEasingSine:
            return 0.5 - 0.5 * cos(3.14159265358979323846 * t);
        case VortexEasingLinear:
        default:
            return t;
    }
}

double vortex_speed_warp(double t, double speed) {
    t = vortex_clamp01(t);
    speed = vortex_clamp(speed, 0.25, 4.0);
    if (t <= 0.0 || t >= 1.0 || speed == 1.0) return t;
    return pow(t, 1.0 / speed);
}

double vortex_presented_progress(double t, const VortexEffectParameters *p) {
    VortexEffectParameters params = p ? vortex_sanitize_parameters(*p) : vortex_default_parameters();
    return vortex_ease(params.easing, vortex_speed_warp(t, params.speed));
}

double vortex_smooth_step(double presented, double target, double dt, double duration) {
    if (isnan(presented) || duration <= 0.0) return target;
    double gap = target - presented;
    if (fabs(gap) > VORTEX_SMOOTH_MAX_GAP) return target;
    dt = vortex_clamp(dt, 0.0, 0.1);
    double tau = duration / 4.6; /* e^-4.6 ~= 1% remaining after `duration` */
    double next = presented + gap * (1.0 - exp(-dt / tau));
    if (fabs(target - next) < VORTEX_SMOOTH_SNAP) return target;
    return next;
}

/* ---- Effects ------------------------------------------------------------- */

void vortex_builtin_directions(VortexBuiltinEffect effect,
                               VortexNavigationDirection nav,
                               VortexDirection *incomingFrom,
                               VortexDirection *outgoingTo) {
    /* Natural iOS motion: navigating forward, the next page enters from the
       right and the current page exits to the left. */
    VortexDirection stockIn = (nav == VortexNavigationBackward) ? VortexDirectionLeft : VortexDirectionRight;
    VortexDirection stockOut = vortex_direction_opposite(stockIn);
    VortexDirection in = stockIn, out = stockOut;

    switch (effect) {
        case VortexBuiltinEffectReverseSlide:
            in = stockOut;   /* enters from the side the stock page would exit to */
            out = stockIn;
            break;
        case VortexBuiltinEffectVerticalRise:
            in = VortexDirectionDown;  /* rises from below */
            out = VortexDirectionUp;   /* outgoing moves upward */
            break;
        case VortexBuiltinEffectVerticalFall:
            in = VortexDirectionUp;    /* enters from above */
            out = VortexDirectionDown; /* outgoing moves downward */
            break;
        case VortexBuiltinEffectStock:
        default:
            break;
    }
    if (incomingFrom) *incomingFrom = in;
    if (outgoingTo) *outgoingTo = out;
}

static const char *const kBuiltinEffectNames[VortexBuiltinEffectCount] = {
    "stock", "reverse-slide", "vertical-rise", "vertical-fall",
};

VortexBuiltinEffect vortex_builtin_effect_from_string(const char *s, int *ok) {
    if (s) {
        for (int i = 0; i < VortexBuiltinEffectCount; i++) {
            if (strcmp(kBuiltinEffectNames[i], s) == 0) {
                if (ok) *ok = 1;
                return (VortexBuiltinEffect)i;
            }
        }
    }
    if (ok) *ok = 0;
    return VortexBuiltinEffectStock;
}

const char *vortex_builtin_effect_to_string(VortexBuiltinEffect e) {
    if ((int)e < 0 || e >= VortexBuiltinEffectCount) return "stock";
    return kBuiltinEffectNames[e];
}

VortexPageVisual vortex_identity_visual(void) {
    VortexPageVisual v;
    v.translation.x = 0.0;
    v.translation.y = 0.0;
    v.opacity = 1.0;
    v.scale = 1.0;
    v.rotationY = 0.0;
    v.perspective = 0.0;
    return v;
}

int vortex_visual_is_identity(VortexPageVisual v) {
    const double e = 1e-6;
    return fabs(v.translation.x) < e && fabs(v.translation.y) < e &&
           fabs(v.opacity - 1.0) < e && fabs(v.scale - 1.0) < e &&
           fabs(v.rotationY) < e && fabs(v.perspective) < e;
}

VortexPageVisual vortex_directional_visual(VortexPageRole role,
                                           double progress,
                                           VortexDirection incomingFrom,
                                           VortexDirection outgoingTo,
                                           const VortexEffectParameters *params) {
    VortexEffectParameters p = params ? vortex_sanitize_parameters(*params) : vortex_default_parameters();
    VortexPageVisual v = vortex_identity_visual();
    double t = vortex_presented_progress(progress, &p);
    double sign = p.reverse ? -1.0 : 1.0;

    if (role == VortexPageRoleOutgoing) {
        VortexVec2 d = vortex_direction_vector(outgoingTo);
        /* Outgoing travel is scaled by intensity. When it does not travel the
           full distance it would still be on screen at t=1, so it must fade out
           to keep the hand-off to the next transition seamless. */
        v.translation.x = sign * d.x * t * p.intensity;
        v.translation.y = sign * d.y * t * p.intensity;
        if (p.intensity < 0.999 || p.fadePages) v.opacity = 1.0 - t;
    } else if (role == VortexPageRoleIncoming) {
        VortexVec2 d = vortex_direction_vector(incomingFrom);
        /* Incoming always starts fully off-screen so nothing "pops in". */
        v.translation.x = sign * d.x * (1.0 - t);
        v.translation.y = sign * d.y * (1.0 - t);
        if (p.fadePages) v.opacity = t;
    }
    return v;
}

/* ---- Navigation state machine ------------------------------------------- */

void vortex_nav_reset(VortexNavState *state) {
    if (!state) return;
    state->base = 0.0;
    state->hasBase = 0;
}

static int vortex_nearest_index(const double *positions, int count, double x) {
    int best = -1;
    double bestDistance = INFINITY;
    for (int i = 0; i < count; i++) {
        double d = fabs(positions[i] - x);
        if (d < bestDistance) {
            bestDistance = d;
            best = i;
        }
    }
    return best;
}

/// Nearest page strictly on `dir` side of `from` (at least a quarter page away).
static int vortex_neighbor_index(const double *positions, int count, double from, int dir) {
    int best = -1;
    double bestDistance = INFINITY;
    for (int i = 0; i < count; i++) {
        double d = (positions[i] - from) * (double)dir;
        if (d > 0.25 && d < bestDistance) {
            bestDistance = d;
            best = i;
        }
    }
    return best;
}

static VortexNavSnapshot vortex_inactive_snapshot(double base) {
    VortexNavSnapshot s;
    s.inRange = 1;
    s.active = 0;
    s.direction = VortexNavigationNone;
    s.progress = 0.0;
    s.base = base;
    return s;
}

VortexNavSnapshot vortex_nav_step(VortexNavState *state,
                                  double presented,
                                  const double *positions,
                                  int count) {
    if (!state || !positions || count <= 0 || isnan(presented)) {
        if (state) vortex_nav_reset(state);
        VortexNavSnapshot out = vortex_inactive_snapshot(0.0);
        out.inRange = 0;
        return out;
    }

    double lo = positions[0], hi = positions[0];
    for (int i = 1; i < count; i++) {
        if (positions[i] < lo) lo = positions[i];
        if (positions[i] > hi) hi = positions[i];
    }
    /* Today View / App Library / rubber-banding past the ends: stay stock. */
    if (presented < lo - VORTEX_SETTLE_EPSILON || presented > hi + VORTEX_SETTLE_EPSILON) {
        vortex_nav_reset(state);
        VortexNavSnapshot out = vortex_inactive_snapshot(presented);
        out.inRange = 0;
        return out;
    }

    /* Re-anchor if we have no base, or the base page vanished (page added /
       removed / relayout). */
    if (state->hasBase) {
        int idx = vortex_nearest_index(positions, count, state->base);
        if (idx < 0 || fabs(positions[idx] - state->base) > 0.01) state->hasBase = 0;
        else state->base = positions[idx];
    }
    if (!state->hasBase) {
        state->base = positions[vortex_nearest_index(positions, count, presented)];
        state->hasBase = 1;
    }

    /* Advance the base when the presented position reaches the neighbour.
       This hand-off happens exactly where both pages are at rest, so the
       switch of roles is visually seamless (see tests). */
    int neighbor = -1;
    int dir = 0;
    for (int guard = 0; guard <= count; guard++) {
        double delta = presented - state->base;
        if (fabs(delta) < VORTEX_SETTLE_EPSILON) {
            dir = 0;
            break;
        }
        dir = delta > 0 ? 1 : -1;
        neighbor = vortex_neighbor_index(positions, count, state->base, dir);
        if (neighbor < 0) {
            dir = 0;
            break;
        }
        double span = fabs(positions[neighbor] - state->base);
        if (fabs(delta) >= span - VORTEX_SETTLE_EPSILON) {
            state->base = positions[neighbor];
            continue;
        }
        break;
    }

    if (dir == 0 || neighbor < 0) {
        int idx = vortex_nearest_index(positions, count, presented);
        state->base = positions[idx];
        return vortex_inactive_snapshot(state->base);
    }

    VortexNavSnapshot s;
    s.inRange = 1;
    s.active = 1;
    s.direction = dir > 0 ? VortexNavigationForward : VortexNavigationBackward;
    s.base = state->base;
    s.progress = vortex_clamp01(fabs(presented - state->base) / fabs(positions[neighbor] - state->base));
    return s;
}

VortexPageRole vortex_nav_role(const VortexNavSnapshot *snap, double position) {
    if (!snap || !snap->active) return VortexPageRoleNone;
    double rel = position - snap->base;
    if (fabs(rel) < 0.25) return VortexPageRoleOutgoing;
    /* The incoming page is the nearest page on the navigation side. Pages are
       normalised to ~1 unit apart, so anything within (0.25, 1.75) qualifies. */
    double d = rel * (double)snap->direction;
    if (d > 0.25 && d < 1.75) return VortexPageRoleIncoming;
    return VortexPageRoleNone;
}

/* ---- Solver -------------------------------------------------------------- */

VortexPageVisual vortex_solve_page(VortexPageVisual desired, double position, double actual) {
    VortexPageVisual v = desired;
    /* The scroll view already places this page at (position - actual) page
       units from the screen centre horizontally; compensate for it. */
    v.translation.x = desired.translation.x - (position - actual);
    return v;
}

VortexPageVisual vortex_compose_page(const VortexNavSnapshot *snap,
                                     double position,
                                     double presented,
                                     double actual,
                                     VortexEffectFunction effect,
                                     void *context,
                                     const VortexEffectParameters *params) {
    if (!snap || !snap->inRange) return vortex_identity_visual();

    VortexPageRole role = vortex_nav_role(snap, position);
    VortexPageVisual desired;
    if (role == VortexPageRoleNone || !effect) {
        /* Not part of the transition: show it where it would naturally be at
           the PRESENTED position. With no smoothing (presented == actual) this
           solves to identity. */
        desired = vortex_identity_visual();
        desired.translation.x = position - presented;
    } else {
        desired = effect(context, role, snap->progress, snap->direction, params);
    }
    return vortex_solve_page(desired, position, actual);
}
