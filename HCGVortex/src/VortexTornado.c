//
//  VortexTornado.c
//  HCG Vortex — Hakmi Capital Group
//

#include "VortexTornado.h"
#include "VortexMath.h"

#include <math.h>

#define VORTEX_PI 3.14159265358979323846

/* Choreography constants (tuned with scripts/render_tornado_preview.py so the
   funnel is fully formed, holding both pages, through mid-swipe). */
#define TORNADO_STAGGER      0.15   /* top rows lift first / settle last */
#define TORNADO_GATHER       0.30   /* travel an icon takes to join the funnel */
#define TORNADO_FADE_START   0.72   /* travel at which a swept icon starts to vanish */
#define TORNADO_FADE_END     0.97
#define TORNADO_RISE         0.12   /* swept icons climb this fraction of the funnel height */
#define TORNADO_TAPER        1.5    /* > 1: concave funnel wall */
#define TORNADO_TRAVEL       0.20   /* axis travel either side of centre, fraction of width */
#define TORNADO_LEAN         0.08   /* tip trails the opening by this fraction of width */
#define TORNADO_ICON_SCALE   0.70   /* icon size inside the funnel (before perspective) */
#define TORNADO_BACK_DIM     0.40   /* opacity lost at the back of the funnel (depth on) */

static double clampd(double v, double lo, double hi) {
    if (isnan(v)) return lo;
    return v < lo ? lo : (v > hi ? hi : v);
}

static double smoothstep(double e0, double e1, double x) {
    if (e1 <= e0) return x >= e1 ? 1.0 : 0.0;
    double t = clampd((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

VortexTornadoParameters vortex_tornado_preset(VortexTornadoPreset preset) {
    VortexTornadoParameters p;
    p.direction = VortexSpinFollowSwipe;
    p.travel = VortexTravelFollowSwipe;
    p.iconSpin = 0;
    switch (preset) {
        case VortexTornadoPresetSubtle:
            p.intensity = 0.4; p.radius = 0.26; p.tipRadius = 0.06; p.height = 0.45; p.rotations = 1.5; p.depth = 0.4;
            break;
        case VortexTornadoPresetSciFi:
            p.intensity = 1.0; p.radius = 0.48; p.tipRadius = 0.03; p.height = 0.75; p.rotations = 3.5; p.depth = 1.0;
            break;
        case VortexTornadoPresetClassic:
        default:
            p.intensity = 0.7; p.radius = 0.32; p.tipRadius = 0.05; p.height = 0.60; p.rotations = 2.5; p.depth = 0.7;
            break;
    }
    return p;
}

VortexTornadoParameters vortex_tornado_defaults(void) {
    return vortex_tornado_preset(VortexTornadoPresetClassic);
}

VortexTornadoParameters vortex_tornado_sanitize(VortexTornadoParameters p) {
    VortexTornadoParameters d = vortex_tornado_defaults();
    p.intensity = isfinite(p.intensity) ? clampd(p.intensity, 0.1, 1.0) : d.intensity;
    p.radius = isfinite(p.radius) ? clampd(p.radius, 0.15, 0.60) : d.radius;
    p.tipRadius = isfinite(p.tipRadius) ? clampd(p.tipRadius, 0.02, 0.25) : d.tipRadius;
    if (p.tipRadius > 0.9 * p.radius) p.tipRadius = 0.9 * p.radius;   /* always a taper */
    p.height = isfinite(p.height) ? clampd(p.height, 0.35, 0.85) : d.height;
    p.rotations = isfinite(p.rotations) ? clampd(p.rotations, 1.0, 4.0) : d.rotations;
    if ((int)p.direction < 0 || p.direction >= VortexSpinCount) p.direction = d.direction;
    if ((int)p.travel < 0 || p.travel >= VortexTravelCount) p.travel = d.travel;
    p.depth = isfinite(p.depth) ? clampd(p.depth, 0.0, 1.0) : d.depth;
    p.iconSpin = p.iconSpin ? 1 : 0;
    return p;
}

VortexIconVisual vortex_icon_identity(void) {
    VortexIconVisual v;
    v.tx = 0.0;
    v.ty = 0.0;
    v.scale = 1.0;
    v.rotation = 0.0;
    v.tiltX = 0.0;
    v.tiltY = 0.0;
    v.z = 0.0;
    v.opacity = 1.0;
    return v;
}

int vortex_icon_is_identity(VortexIconVisual v) {
    const double e = 1e-6;
    return fabs(v.tx) < e && fabs(v.ty) < e && fabs(v.scale - 1.0) < e && fabs(v.rotation) < e &&
           fabs(v.tiltX) < e && fabs(v.tiltY) < e &&
           fabs(v.z) < e && fabs(v.opacity - 1.0) < e;
}

double vortex_tornado_spin_sign(VortexSpinDirection direction, VortexNavigationDirection navigation) {
    switch (direction) {
        case VortexSpinClockwise: return -1.0;        /* seen from above: the front moves left */
        case VortexSpinCounterclockwise: return 1.0;
        case VortexSpinFollowSwipe:
        default:
            /* Forward == finger swipes left: the front of the funnel moves left with it. */
            return navigation == VortexNavigationBackward ? 1.0 : -1.0;
    }
}

void vortex_tornado_rank(VortexIconSlot *slots, int n, double rowTolerance) {
    if (!slots || n <= 0) return;
    if (n > VORTEX_TORNADO_MAX_ICONS) n = VORTEX_TORNADO_MAX_ICONS;
    int order[VORTEX_TORNADO_MAX_ICONS];
    for (int i = 0; i < n; i++) order[i] = i;
    /* Insertion sort, row-major: rows by y (within tolerance), then x. Stable. */
    for (int i = 1; i < n; i++) {
        int key = order[i];
        int j = i - 1;
        while (j >= 0) {
            const VortexIconSlot *a = &slots[order[j]], *b = &slots[key];
            double dy = a->homeY - b->homeY;
            int after = (dy > rowTolerance) || (fabs(dy) <= rowTolerance && a->homeX > b->homeX);
            if (!after) break;
            order[j + 1] = order[j];
            j--;
        }
        order[j + 1] = key;
    }
    for (int k = 0; k < n; k++) {
        slots[order[k]].index = k;
        slots[order[k]].count = n;
        slots[order[k]].rank = n > 1 ? (double)k / (double)(n - 1) : 0.5;
    }
}

static double travel_sign(VortexNavigationDirection navigation, VortexTravelMode travel,
                          const VortexEffectParameters *params) {
    if (travel == VortexTravelCentred) return 0.0;
    double s = navigation == VortexNavigationBackward ? -1.0 : 1.0;   /* follow: forward goes right -> left */
    if (travel == VortexTravelAgainstSwipe) s = -s;
    if (params && params->reverse) s = -s;
    return s;
}

static double presented(double progress, const VortexEffectParameters *params) {
    return params ? vortex_presented_progress(vortex_clamp01(progress), params) : vortex_clamp01(progress);
}

double vortex_tornado_centre_x(double progress, VortexNavigationDirection navigation, double pageWidth,
                               VortexTravelMode travel, const VortexEffectParameters *params) {
    double pp = presented(progress, params);
    return travel_sign(navigation, travel, params) * TORNADO_TRAVEL * pageWidth * (1.0 - 2.0 * pp);
}

VortexPageVisual vortex_tornado_page(VortexPageRole role, double progress, const VortexEffectParameters *params) {
    VortexPageVisual v = vortex_identity_visual();
    double pp = presented(progress, params);
    /* Both pages stay centred on screen; the icons do the moving. */
    if (role == VortexPageRoleOutgoing) {
        v.opacity = 1.0 - smoothstep(0.92, 1.0, pp);
    } else if (role == VortexPageRoleIncoming) {
        v.opacity = smoothstep(0.0, 0.08, pp);
    }
    return v;
}

VortexIconVisual vortex_tornado_fallback_icon(VortexPageRole role, double progress,
                                              const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    double pp = presented(progress, params);
    if (role == VortexPageRoleOutgoing) {
        v.opacity = 1.0 - smoothstep(0.0, 0.5, pp);
        v.scale = 1.0 - 0.06 * smoothstep(0.0, 0.5, pp);
    } else if (role == VortexPageRoleIncoming) {
        v.opacity = smoothstep(0.5, 1.0, pp);
        v.scale = 1.0 - 0.06 * (1.0 - smoothstep(0.5, 1.0, pp));
    }
    return v;
}

VortexIconVisual vortex_tornado_icon(VortexPageRole role,
                                     double progress,
                                     VortexNavigationDirection navigation,
                                     VortexIconSlot slot,
                                     double pageWidth,
                                     double pageHeight,
                                     const VortexTornadoParameters *tornado,
                                     const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    if (role != VortexPageRoleOutgoing && role != VortexPageRoleIncoming) return v;
    if (!(pageWidth > 1.0) || !(pageHeight > 1.0) || !isfinite(slot.homeX) || !isfinite(slot.homeY)) return v;

    VortexTornadoParameters tp = vortex_tornado_sanitize(tornado ? *tornado : vortex_tornado_defaults());
    double pp = presented(progress, params);
    double u = role == VortexPageRoleOutgoing ? pp : 1.0 - pp;
    double rank = clampd(slot.rank, 0.0, 1.0);

    /* Lift and gather (staggered), then travel along the funnel. */
    double start = TORNADO_STAGGER * rank;
    double gather = smoothstep(start, start + TORNADO_GATHER, u);
    double a = clampd((u - start) / (1.0 - start), 0.0, 1.0);

    /* Place along the helix: icons in rank order from the opening to the tip,
       the incoming page interleaved half a step from the outgoing page. */
    int count = slot.count > 0 ? slot.count : 1;
    double step = 1.0 / (double)count;
    double h = clampd(rank * (1.0 - step) + (role == VortexPageRoleIncoming ? 0.75 : 0.25) * step, 0.0, 1.0);

    double spin = vortex_tornado_spin_sign(tp.direction, navigation);
    double travel = travel_sign(navigation, tp.travel, params);
    double rTop = tp.radius * pageWidth;
    double rTip = tp.tipRadius * pageWidth;
    double height = tp.height * pageHeight;
    double top = -0.5 * height;
    double level = clampd(h - TORNADO_RISE * a, 0.0, 1.0);         /* swept icons climb towards the opening */
    double y = top + level * height;
    double r = rTip + (rTop - rTip) * pow(1.0 - level, TORNADO_TAPER);
    double axis = vortex_tornado_centre_x(progress, navigation, pageWidth, tp.travel, params) +
                  travel * TORNADO_LEAN * pageWidth * (level - 0.5);

    /* Helix angle + the whole funnel turning with the gesture. */
    double turning = (0.75 + 0.75 * tp.intensity) * pp + 0.25 * a;
    double theta = 2.0 * VORTEX_PI * (tp.rotations * h + spin * turning);
    double X = r * sin(theta);
    double Z = r * cos(theta);                                      /* + towards the viewer */

    double persp = 1.0;
    if (tp.depth > 0.0) {
        double camera = 2.4 * rTop + 0.6 * pageWidth;
        persp = clampd(camera / (camera - Z * tp.depth), 0.7, 1.35);
    }
    double fx = axis + X * persp;
    double fy = y;
    double funnelScale = clampd(TORNADO_ICON_SCALE * persp, 0.5, 1.1);

    v.tx = (fx - slot.homeX) * gather;
    v.ty = (fy - slot.homeY) * gather;
    v.scale = 1.0 + (funnelScale - 1.0) * gather;
    v.z = tp.depth > 0.0 ? Z * gather : 0.0;
    v.rotation = tp.iconSpin ? spin * 2.0 * VORTEX_PI * (0.5 + tp.intensity) * a * gather : 0.0;

    double fade = 1.0 - smoothstep(TORNADO_FADE_START, TORNADO_FADE_END, u);
    double dim = 1.0;
    if (tp.depth > 0.0 && r > 1e-9) {
        double front = 0.5 * (Z / r + 1.0);                         /* 0 back .. 1 front */
        dim = 1.0 - TORNADO_BACK_DIM * tp.depth * gather * (1.0 - front);
    }
    v.opacity = clampd(fade * dim, 0.0, 1.0);
    return v;
}
