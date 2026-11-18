//
//  VortexIconEffects.c
//  HCG Vortex — Hakmi Capital Group
//

#include "VortexIconEffects.h"
#include "VortexMath.h"

#include <math.h>

#define PI 3.14159265358979323846

static double clampd(double v, double lo, double hi) {
    if (isnan(v)) return lo;
    return v < lo ? lo : (v > hi ? hi : v);
}

static double smoothstep(double e0, double e1, double x) {
    if (e1 <= e0) return x >= e1 ? 1.0 : 0.0;
    double t = clampd((x - e0) / (e1 - e0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

static double presented(double progress, const VortexEffectParameters *params) {
    double t = vortex_clamp01(progress);
    return params ? vortex_presented_progress(t, params) : t;
}

/// Per-page travel: 0 = in the grid, 1 = fully away.
static double travel_u(VortexPageRole role, double pp) {
    return role == VortexPageRoleOutgoing ? pp : 1.0 - pp;
}

/// +1 when the outgoing page should leave towards screen right, -1 towards
/// screen left. Follows the finger (forward = finger moves left); Reverse
/// Animation flips it.
static double exit_sign(VortexNavigationDirection navigation, const VortexEffectParameters *params) {
    double s = navigation == VortexNavigationBackward ? 1.0 : -1.0;
    if (params && params->reverse) s = -s;
    return s;
}

/* ---- Settings ------------------------------------------------------------ */

VortexIconEffectSettings vortex_icon_settings_defaults(void) {
    VortexIconEffectSettings s;
    s.tornado = vortex_tornado_defaults();
    s.orbital.radius = 0.44;
    s.orbital.rings = 3;
    s.orbital.tilt = 0.35;
    s.orbital.speed = 0.75;
    s.orbital.direction = VortexSpinFollowSwipe;
    s.warp.intensity = 0.6;
    s.warp.perspective = 0.5;
    s.holo.depth = 0.6;
    s.holo.tilt = 0.5;
    s.holo.layers = 3;
    s.circuit.trail = 0.30;
    s.circuit.glow = 0.5;
    s.circuit.intensity = 0.8;
    s.magnetic.strength = 0.5;
    s.magnetic.snap = 0.5;
    return s;
}

static double fin(double v, double lo, double hi, double fallback) {
    return isfinite(v) ? clampd(v, lo, hi) : fallback;
}

VortexIconEffectSettings vortex_icon_settings_sanitize(VortexIconEffectSettings s) {
    VortexIconEffectSettings d = vortex_icon_settings_defaults();
    s.tornado = vortex_tornado_sanitize(s.tornado);
    s.orbital.radius = fin(s.orbital.radius, 0.20, 0.48, d.orbital.radius);
    s.orbital.rings = s.orbital.rings < 2 ? 2 : (s.orbital.rings > 5 ? 5 : s.orbital.rings);
    s.orbital.tilt = fin(s.orbital.tilt, 0.0, 1.0, d.orbital.tilt);
    s.orbital.speed = fin(s.orbital.speed, 0.25, 2.0, d.orbital.speed);
    if ((int)s.orbital.direction < 0 || s.orbital.direction >= VortexSpinCount) s.orbital.direction = d.orbital.direction;
    s.warp.intensity = fin(s.warp.intensity, 0.1, 1.0, d.warp.intensity);
    s.warp.perspective = fin(s.warp.perspective, 0.2, 1.0, d.warp.perspective);
    s.holo.depth = fin(s.holo.depth, 0.0, 1.0, d.holo.depth);
    s.holo.tilt = fin(s.holo.tilt, 0.0, 1.0, d.holo.tilt);
    s.holo.layers = s.holo.layers < 2 ? 2 : (s.holo.layers > 4 ? 4 : s.holo.layers);
    s.circuit.trail = fin(s.circuit.trail, 0.1, 0.6, d.circuit.trail);
    s.circuit.glow = fin(s.circuit.glow, 0.0, 1.0, d.circuit.glow);
    s.circuit.intensity = fin(s.circuit.intensity, 0.1, 1.0, d.circuit.intensity);
    s.magnetic.strength = fin(s.magnetic.strength, 0.1, 1.0, d.magnetic.strength);
    s.magnetic.snap = fin(s.magnetic.snap, 0.0, 1.0, d.magnetic.snap);
    return s;
}

int vortex_icon_effect_pins_pages(VortexIconEffectKind kind) {
    return kind != VortexIconEffectMagnetic;
}

VortexPageVisual vortex_icon_effect_page(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                         VortexNavigationDirection navigation, const VortexEffectParameters *params) {
    if (kind == VortexIconEffectMagnetic) {
        /* Pages move exactly like iOS; only the icons separate and snap. */
        VortexDirection in = VortexDirectionNone, out = VortexDirectionNone;
        vortex_builtin_directions(VortexBuiltinEffectStock, navigation, &in, &out);
        VortexEffectParameters plain = params ? *params : vortex_default_parameters();
        plain.intensity = 1.0;
        plain.fadePages = 0;
        plain.reverse = 0;
        return vortex_directional_visual(role, progress, in, out, &plain);
    }
    return vortex_tornado_page(role, progress, params);
}

VortexIconVisual vortex_icon_effect_fallback(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                             const VortexEffectParameters *params) {
    if (kind == VortexIconEffectMagnetic) return vortex_icon_identity(); /* travels with its page */
    return vortex_tornado_fallback_icon(role, progress, params);
}

/* ---- Orbital: concentric rings around a shared centre --------------------- */

/// Ring for an icon: rings get icons in proportion to their circumference.
static void orbital_ring(int index, int count, int rings, int *ring, double *localFraction, double *ringShare) {
    double total = 0.0;
    for (int j = 0; j < rings; j++) total += 0.35 + 0.65 * (double)j / (double)(rings - 1);
    double f = ((double)index + 0.5) / (double)(count > 0 ? count : 1);
    double cum = 0.0;
    for (int j = 0; j < rings; j++) {
        double share = (0.35 + 0.65 * (double)j / (double)(rings - 1)) / total;
        if (f < cum + share || j == rings - 1) {
            *ring = j;
            *localFraction = clampd((f - cum) / share, 0.0, 1.0);
            *ringShare = share;
            return;
        }
        cum += share;
    }
}

static VortexIconVisual orbital_icon(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                                     VortexIconSlot slot, double W, double H, const VortexOrbitalParameters *op,
                                     const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    double u = travel_u(role, pp);
    int count = slot.count > 0 ? slot.count : 1;
    int ring = 0;
    double local = 0.0, share = 1.0;
    orbital_ring(slot.index, count, op->rings, &ring, &local, &share);
    double ringFrac = (double)ring / (double)(op->rings - 1);           /* 0 inner .. 1 outer */
    double rMax = op->radius * W;
    double r = rMax * (0.24 + 0.76 * ringFrac);

    /* Outer rings gather first; every icon is in orbit by u = 0.45. */
    double start = 0.12 * (1.0 - ringFrac);
    double gather = smoothstep(start, start + 0.33, u);
    double a = clampd((u - start) / (1.0 - start), 0.0, 1.0);

    double spin = vortex_tornado_spin_sign(op->direction, navigation);
    double perRing = share * count;                                     /* icons on this ring (approx.) */
    double spacing = 2.0 * PI / (perRing > 1.0 ? perRing : 1.0);
    double theta0 = 2.0 * PI * local + (role == VortexPageRoleIncoming ? 0.5 * spacing : 0.0) + 0.7 * ring;
    double kepler = sqrt(rMax / r);                                     /* inner rings travel faster */
    double theta = theta0 + spin * 2.0 * PI * op->speed * kepler * pp + spin * 0.25 * PI * a;

    double tiltAngle = op->tilt * 70.0 * PI / 180.0;
    double X = r * cos(theta);
    double Y = r * sin(theta) * cos(tiltAngle);
    double Z = r * sin(theta) * sin(tiltAngle);                         /* lower half of each ring is nearer */
    double camera = 2.5 * rMax + 0.6 * W;
    double persp = clampd(camera / (camera - 0.6 * Z), 0.85, 1.15);     /* subtle depth variation */

    double cx = -exit_sign(navigation, params) * 0.12 * W * (1.0 - 2.0 * pp);
    double cy = -0.04 * H;
    v.tx = (cx + X * persp - slot.homeX) * gather;
    v.ty = (cy + Y * persp - slot.homeY) * gather;
    v.scale = 1.0 + (0.50 * persp - 1.0) * gather;
    v.z = Z * gather;
    double fade = 1.0 - smoothstep(0.72, 0.97, u);
    double back = r > 1e-9 ? 0.5 * (1.0 - Z / (r * (sin(tiltAngle) > 1e-9 ? sin(tiltAngle) : 1.0))) : 0.0;
    double dim = 1.0 - 0.25 * op->tilt * gather * clampd(back, 0.0, 1.0);
    v.opacity = clampd(fade * dim, 0.0, 1.0);
    return v;
}

/* ---- Warp: into a short tunnel towards a vanishing point ----------------- */

static VortexIconVisual warp_icon(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                                  VortexIconSlot slot, double W, double H, const VortexWarpParameters *wp,
                                  const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    double u = travel_u(role, pp);
    double vx = -exit_sign(navigation, params) * 0.08 * W * (1.0 - 2.0 * pp);
    double vy = -0.04 * H;
    double dx = slot.homeX - vx, dy = slot.homeY - vy;
    double rho = sqrt(dx * dx + dy * dy);
    double phi = atan2(dy, dx);

    double c = smoothstep(0.0, 0.85, u);                                /* how deep into the tunnel */
    double camera = W * (2.2 - 1.6 * wp->perspective);
    double z = camera * (1.0 + 4.0 * wp->intensity) * c;
    double p = camera / (camera + z);                                   /* perspective: 1 .. ~0.17 */
    double wall = 0.42 * W;
    double rhoT = rho + (wall - rho) * smoothstep(0.0, 0.5, u);         /* icons line up on the tunnel wall */
    double twist = 0.6 * wp->intensity * c;

    double x = vx + p * rhoT * cos(phi + twist);
    double y = vy + p * rhoT * sin(phi + twist);
    v.tx = x - slot.homeX;
    v.ty = y - slot.homeY;
    v.scale = p;
    v.z = -100.0 * c;                                                   /* deeper icons drawn behind */
    v.opacity = clampd(1.0 - smoothstep(0.62, 0.95, u), 0.0, 1.0);      /* gentle, monotonic: no flashing */
    return v;
}

/* ---- Holographic layers: parallax slide in depth layers ------------------ */

static VortexIconVisual holo_icon(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                                  VortexIconSlot slot, double W, double H, const VortexHoloParameters *hp,
                                  const VortexEffectParameters *params) {
    (void)H;
    VortexIconVisual v = vortex_icon_identity();
    double u = travel_u(role, pp);
    int layers = hp->layers;
    int layer = slot.index % layers;                                    /* neighbours sit in different layers */
    double depthFrac = (double)layer / (double)(layers - 1);            /* 0 back .. 1 front */
    double out = exit_sign(navigation, params);
    double side = role == VortexPageRoleOutgoing ? out : -out;          /* incoming arrives from the other side */
    double bell = sin(PI * u);

    double speed = 0.75 + 0.5 * depthFrac * hp->depth;                  /* front layers move faster: parallax */
    v.tx = side * 1.1 * W * u * speed;
    v.ty = -14.0 * hp->depth * depthFrac * bell;                        /* front layers float up */
    v.scale = 1.0 + (0.07 * depthFrac - 0.08 * (1.0 - depthFrac)) * hp->depth * bell;
    v.tiltY = side * 0.6 * hp->tilt * bell;
    v.tiltX = -0.15 * hp->tilt * bell;
    v.z = (depthFrac - 0.5) * 80.0 * hp->depth * bell;
    double translucency = 1.0 - 0.3 * (1.0 - depthFrac) * hp->depth * bell;
    v.opacity = clampd(translucency * (1.0 - smoothstep(0.8, 1.0, u)), 0.0, 1.0);
    return v;
}

/* ---- Circuit Flow: icons run along right-angle traces --------------------- */

typedef struct {
    VortexVec2 p0, p1, p2;     /* home -> lane -> edge */
    double l1, length;
    double t;                  /* 0..1 along the run (staggered) */
    double s;                  /* distance travelled from home */
} CircuitRun;

static CircuitRun circuit_run(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                              VortexIconSlot slot, double W, double H, const VortexEffectParameters *params) {
    CircuitRun run;
    double u = travel_u(role, pp);
    double out = exit_sign(navigation, params);
    double edge = (role == VortexPageRoleOutgoing ? out : -out) * (0.5 * W + 80.0);
    double lane = slot.homeY + ((slot.index & 1) ? 1.0 : -1.0) * 0.06 * H;   /* bus lanes between rows */
    run.p0.x = slot.homeX; run.p0.y = slot.homeY;
    run.p1.x = slot.homeX; run.p1.y = lane;
    run.p2.x = edge;       run.p2.y = lane;
    run.l1 = fabs(lane - slot.homeY);
    run.length = run.l1 + fabs(edge - slot.homeX);
    double start = 0.3 * clampd(slot.rank, 0.0, 1.0);                     /* packets leave one after another */
    run.t = clampd((u - start) / (1.0 - start), 0.0, 1.0);
    run.s = run.length * smoothstep(0.0, 1.0, run.t);
    return run;
}

static VortexVec2 circuit_point(const CircuitRun *run, double s) {
    VortexVec2 q;
    if (s <= run->l1) {
        double k = run->l1 > 1e-9 ? s / run->l1 : 1.0;
        q.x = run->p0.x;
        q.y = run->p0.y + (run->p1.y - run->p0.y) * k;
    } else {
        double l2 = run->length - run->l1;
        double k = l2 > 1e-9 ? (s - run->l1) / l2 : 1.0;
        q.x = run->p1.x + (run->p2.x - run->p1.x) * k;
        q.y = run->p1.y;
    }
    return q;
}

static VortexIconVisual circuit_icon(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                                     VortexIconSlot slot, double W, double H, const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    CircuitRun run = circuit_run(role, pp, navigation, slot, W, H, params);
    VortexVec2 q = circuit_point(&run, run.s);
    v.tx = q.x - slot.homeX;
    v.ty = q.y - slot.homeY;
    v.scale = 1.0 - 0.08 * sin(PI * run.t);
    v.opacity = clampd(1.0 - smoothstep(0.85, 1.0, run.t), 0.0, 1.0);
    return v;
}

VortexTrace vortex_icon_effect_trace(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                     VortexNavigationDirection navigation, VortexIconSlot slot,
                                     double pageWidth, double pageHeight,
                                     const VortexIconEffectSettings *settings,
                                     const VortexEffectParameters *params) {
    VortexTrace trace;
    trace.count = 0;
    trace.alpha = 0.0;
    if (kind != VortexIconEffectCircuitFlow) return trace;
    if (role != VortexPageRoleOutgoing && role != VortexPageRoleIncoming) return trace;
    if (!(pageWidth > 1.0) || !(pageHeight > 1.0) || !isfinite(slot.homeX) || !isfinite(slot.homeY)) return trace;
    VortexIconEffectSettings s = vortex_icon_settings_sanitize(settings ? *settings : vortex_icon_settings_defaults());
    double pp = presented(progress, params);
    CircuitRun run = circuit_run(role, pp, navigation, slot, pageWidth, pageHeight, params);
    double alpha = s.circuit.intensity * sin(PI * run.t);   /* brief: dark at both ends of the run */
    if (alpha < 0.01) return trace;
    double L = s.circuit.trail * pageWidth;
    /* The trail lies behind the icon's direction of travel: outgoing icons move
       away from home (s grows), incoming icons move towards it (s shrinks). */
    double a = role == VortexPageRoleOutgoing ? run.s - L : run.s;
    double b = role == VortexPageRoleOutgoing ? run.s : run.s + L;
    a = clampd(a, 0.0, run.length);
    b = clampd(b, 0.0, run.length);
    if (b - a < 1.0) return trace;
    trace.points[trace.count++] = circuit_point(&run, a);
    if (a < run.l1 && b > run.l1) trace.points[trace.count++] = run.p1;  /* the right-angle corner */
    trace.points[trace.count++] = circuit_point(&run, b);
    trace.alpha = clampd(alpha, 0.0, 1.0);
    return trace;
}

/* ---- Magnetic grid: gentle separation, one controlled snap --------------- */

static VortexIconVisual magnetic_icon(VortexPageRole role, double pp, VortexNavigationDirection navigation,
                                      VortexIconSlot slot, double W, const VortexMagneticParameters *mp,
                                      const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    double u = travel_u(role, pp);
    double len = sqrt(slot.homeX * slot.homeX + slot.homeY * slot.homeY);
    double dx = len > 1.0 ? slot.homeX / len : 0.0;
    double dy = len > 1.0 ? slot.homeY / len : -1.0;
    double A = 14.0 * mp->strength;
    double m = A * sin(PI * u);
    if (role == VortexPageRoleIncoming) {
        /* Snap: over the last 12 % of the arrival the icon is pulled slightly
           past its slot (at most ~3 pt) and lands exactly on it at progress 1.
           Driven by progress, so nothing moves after the page has arrived. */
        const double zone = 0.12;
        if (u < zone) m -= 3.0 * mp->snap * sin(PI * u / zone);
    }
    /* Icons trail the page a little; outer columns more, so the grid loosens. */
    double lag = -exit_sign(navigation, params) * (role == VortexPageRoleOutgoing ? 1.0 : -1.0) *
                 6.0 * mp->strength * sin(PI * u) * (0.6 + 0.8 * fabs(slot.homeX) / (W > 1.0 ? W : 1.0));
    v.tx = dx * m + lag;
    v.ty = dy * m;
    v.scale = 1.0 - 0.03 * mp->strength * sin(PI * u);
    return v;
}

/* ---- Dispatcher ---------------------------------------------------------- */

VortexIconVisual vortex_icon_effect_visual(VortexIconEffectKind kind, VortexPageRole role, double progress,
                                           VortexNavigationDirection navigation, VortexIconSlot slot,
                                           double pageWidth, double pageHeight,
                                           const VortexIconEffectSettings *settings,
                                           const VortexEffectParameters *params) {
    VortexIconVisual v = vortex_icon_identity();
    if (role != VortexPageRoleOutgoing && role != VortexPageRoleIncoming) return v;
    if (!(pageWidth > 1.0) || !(pageHeight > 1.0) || !isfinite(slot.homeX) || !isfinite(slot.homeY)) return v;
    VortexIconEffectSettings s = vortex_icon_settings_sanitize(settings ? *settings : vortex_icon_settings_defaults());
    double pp = presented(progress, params);
    switch (kind) {
        case VortexIconEffectTornado:
            return vortex_tornado_icon(role, progress, navigation, slot, pageWidth, pageHeight, &s.tornado, params);
        case VortexIconEffectOrbital:
            return orbital_icon(role, pp, navigation, slot, pageWidth, pageHeight, &s.orbital, params);
        case VortexIconEffectWarp:
            return warp_icon(role, pp, navigation, slot, pageWidth, pageHeight, &s.warp, params);
        case VortexIconEffectHolographic:
            return holo_icon(role, pp, navigation, slot, pageWidth, pageHeight, &s.holo, params);
        case VortexIconEffectCircuitFlow:
            return circuit_icon(role, pp, navigation, slot, pageWidth, pageHeight, params);
        case VortexIconEffectMagnetic:
            return magnetic_icon(role, pp, navigation, slot, pageWidth, &s.magnetic, params);
        default:
            return v;
    }
}
