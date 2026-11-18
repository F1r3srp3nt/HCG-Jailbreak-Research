//
//  test_icon_effects.c — host tests for every per-icon effect.
//
//  Shared contract (all six effects, both roles, 1..24 icons, default and
//  extreme settings, both swipe directions), continuity, pause/reverse/cancel
//  through the real navigation state machine, plus a shape test per effect.
//  Geometry and restoration logic only; not on-device rendering.
//

#include "../src/VortexIconEffects.h"
#include "../src/VortexMath.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_failures = 0, g_checks = 0;
#define CHECK(cond, ...)                                                                    \
    do {                                                                                    \
        g_checks++;                                                                         \
        if (!(cond)) {                                                                      \
            g_failures++;                                                                   \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);                            \
            fprintf(stderr, __VA_ARGS__);                                                   \
            fprintf(stderr, "\n");                                                          \
        }                                                                                   \
    } while (0)

static const double W = 390.0, H = 844.0;
static const char *NAMES[] = { "tornado", "orbital", "warp", "holographic", "circuit-flow", "magnetic" };

static int make_grid(VortexIconSlot *slots, int count) {
    int n = 0;
    for (int row = 0; row < 6 && n < count; row++)
        for (int col = 0; col < 4 && n < count; col++, n++) {
            slots[n].homeX = -146.25 + col * 97.5;
            slots[n].homeY = -300.0 + row * 110.0;
        }
    vortex_tornado_rank(slots, n, 8.0);
    return n;
}

static VortexIconEffectSettings settings_variant(int i) {
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    if (i == 1) { /* minimums */
        s.tornado = vortex_tornado_preset(VortexTornadoPresetSubtle);
        s.orbital.radius = 0.2; s.orbital.rings = 2; s.orbital.tilt = 0; s.orbital.speed = 0.25;
        s.warp.intensity = 0.1; s.warp.perspective = 0.2;
        s.holo.depth = 0; s.holo.tilt = 0; s.holo.layers = 2;
        s.circuit.trail = 0.1; s.circuit.glow = 0; s.circuit.intensity = 0.1;
        s.magnetic.strength = 0.1; s.magnetic.snap = 0;
    } else if (i == 2) { /* maximums */
        s.tornado = vortex_tornado_preset(VortexTornadoPresetSciFi);
        s.orbital.radius = 0.48; s.orbital.rings = 5; s.orbital.tilt = 1; s.orbital.speed = 2;
        s.orbital.direction = VortexSpinCounterclockwise;
        s.warp.intensity = 1; s.warp.perspective = 1;
        s.holo.depth = 1; s.holo.tilt = 1; s.holo.layers = 4;
        s.circuit.trail = 0.6; s.circuit.glow = 1; s.circuit.intensity = 1;
        s.magnetic.strength = 1; s.magnetic.snap = 1;
    }
    return s;
}

static VortexEffectParameters params_variant(int i) {
    VortexEffectParameters p = vortex_default_parameters();
    if (i == 1) p.easing = VortexEasingEaseInOut;
    if (i == 2) { p.reverse = 1; p.speed = 0.5; }
    return p;
}

static VortexIconVisual visual(int kind, int role, double p, int nav, VortexIconSlot slot,
                               const VortexIconEffectSettings *s, const VortexEffectParameters *ep) {
    return vortex_icon_effect_visual((VortexIconEffectKind)kind, (VortexPageRole)role, p,
                                     (VortexNavigationDirection)nav, slot, W, H, s, ep);
}

static void test_contract(void) {
    VortexIconSlot slots[24];
    for (int kind = 0; kind < VortexIconEffectCount; kind++) {
        int pinned = vortex_icon_effect_pins_pages((VortexIconEffectKind)kind);
        for (int count = 1; count <= 24; count++) {
            int n = make_grid(slots, count);
            for (int sv = 0; sv < 3; sv++) {
                VortexIconEffectSettings s = settings_variant(sv);
                for (int pv = 0; pv < 3; pv++) {
                    VortexEffectParameters ep = params_variant(pv);
                    for (int nav = -1; nav <= 1; nav += 2) {
                        for (int i = 0; i < n; i++) {
                            VortexIconVisual o0 = visual(kind, VortexPageRoleOutgoing, 0, nav, slots[i], &s, &ep);
                            VortexIconVisual i1 = visual(kind, VortexPageRoleIncoming, 1, nav, slots[i], &s, &ep);
                            VortexIconVisual i0 = visual(kind, VortexPageRoleIncoming, 0, nav, slots[i], &s, &ep);
                            VortexIconVisual o1 = visual(kind, VortexPageRoleOutgoing, 1, nav, slots[i], &s, &ep);
                            CHECK(vortex_icon_is_identity(o0), "%s: p=0 outgoing in its grid (n=%d sv=%d)", NAMES[kind], count, sv);
                            CHECK(vortex_icon_is_identity(i1), "%s: p=1 incoming in its grid (n=%d sv=%d pv=%d)", NAMES[kind], count, sv, pv);
                            if (pinned) {
                                CHECK(i0.opacity <= 1e-9, "%s: p=0 incoming hidden (%.4f)", NAMES[kind], i0.opacity);
                                CHECK(o1.opacity <= 1e-9, "%s: p=1 outgoing hidden (%.4f)", NAMES[kind], o1.opacity);
                            } else {
                                CHECK(vortex_icon_is_identity(i0) && vortex_icon_is_identity(o1),
                                      "%s: icons at rest on an off-screen page", NAMES[kind]);
                            }
                        }
                    }
                }
            }
        }
        /* Page visuals: same contract as page effects. */
        VortexEffectParameters ep = vortex_default_parameters();
        VortexPageVisual po0 = vortex_icon_effect_page(kind, VortexPageRoleOutgoing, 0, 1, &ep);
        VortexPageVisual pi1 = vortex_icon_effect_page(kind, VortexPageRoleIncoming, 1, 1, &ep);
        VortexPageVisual pi0 = vortex_icon_effect_page(kind, VortexPageRoleIncoming, 0, 1, &ep);
        VortexPageVisual po1 = vortex_icon_effect_page(kind, VortexPageRoleOutgoing, 1, 1, &ep);
        CHECK(vortex_visual_is_identity(po0) && vortex_visual_is_identity(pi1), "%s: page endpoints identity", NAMES[kind]);
        CHECK(pi0.opacity <= 1e-9 || fabs(pi0.translation.x) >= 1.0 || fabs(pi0.translation.y) >= 1.0,
              "%s: incoming page hidden at p=0", NAMES[kind]);
        CHECK(po1.opacity <= 1e-9 || fabs(po1.translation.x) >= 1.0 || fabs(po1.translation.y) >= 1.0,
              "%s: outgoing page hidden at p=1", NAMES[kind]);
        /* Widget fallback. */
        CHECK(vortex_icon_is_identity(vortex_icon_effect_fallback(kind, VortexPageRoleOutgoing, 0, &ep)) &&
                  vortex_icon_is_identity(vortex_icon_effect_fallback(kind, VortexPageRoleIncoming, 1, &ep)),
              "%s: fallback endpoints", NAMES[kind]);
        CHECK(vortex_icon_is_identity(visual(kind, VortexPageRoleNone, 0.5, 1, slots[0], NULL, &ep)),
              "%s: pages outside the transition never move", NAMES[kind]);
    }
}

static void worst_step(int kind, int role, int nav, VortexIconSlot *slots, int n, const VortexIconEffectSettings *s,
                       const VortexEffectParameters *ep, int steps, double *move, double *op, double *tilt) {
    *move = *op = *tilt = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual prev = visual(kind, role, 0, nav, slots[i], s, ep);
        for (int k = 1; k <= steps; k++) {
            VortexIconVisual cur = visual(kind, role, (double)k / steps, nav, slots[i], s, ep);
            double m = hypot(cur.tx - prev.tx, cur.ty - prev.ty);
            if (m > *move) *move = m;
            if (fabs(cur.opacity - prev.opacity) > *op) *op = fabs(cur.opacity - prev.opacity);
            double t = fabs(cur.tiltX - prev.tiltX) + fabs(cur.tiltY - prev.tiltY) + fabs(cur.scale - prev.scale);
            if (t > *tilt) *tilt = t;
            CHECK(isfinite(cur.tx) && isfinite(cur.ty) && isfinite(cur.scale) && isfinite(cur.z) &&
                      isfinite(cur.tiltX) && isfinite(cur.tiltY) && cur.opacity >= 0 && cur.opacity <= 1 &&
                      cur.scale > 0.1 && cur.scale < 1.4,
                  "%s: finite and restrained (scale %.3f)", NAMES[kind], cur.scale);
            prev = cur;
        }
    }
}

static void test_continuity(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    for (int kind = 0; kind < VortexIconEffectCount; kind++)
        for (int sv = 0; sv < 3; sv++)
            for (int pv = 0; pv < 2; pv++)
                for (int role = 1; role <= 2; role++) {
                    VortexIconEffectSettings s = settings_variant(sv);
                    VortexEffectParameters ep = params_variant(pv);
                    double m1, o1, t1, m2, o2, t2;
                    worst_step(kind, role, 1, slots, n, &s, &ep, 1000, &m1, &o1, &t1);
                    worst_step(kind, role, 1, slots, n, &s, &ep, 8000, &m2, &o2, &t2);
                    CHECK(m2 < 0.2 * m1 + 1e-9 && o2 < 0.2 * o1 + 1e-9 && t2 < 0.2 * t1 + 1e-9,
                          "%s: continuous (sv=%d pv=%d role=%d: %.3f->%.3f pt, %.4f->%.4f)", NAMES[kind], sv, pv,
                          role, m1, m2, o1, o2);
                }
}

/* Pause holds, reverse unwinds, cancel restores — through vortex_nav_step. */
static void test_pause_reverse_cancel(void) {
    double positions[] = { 0, 1, 2 };
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    VortexEffectParameters ep = vortex_default_parameters();
    for (int kind = 0; kind < VortexIconEffectCount; kind++) {
        VortexNavState st;
        vortex_nav_reset(&st);
        vortex_nav_step(&st, 1.0, positions, 3);
        VortexNavSnapshot a = vortex_nav_step(&st, 1.5, positions, 3);
        VortexIconVisual held = visual(kind, vortex_nav_role(&a, 1), a.progress, a.direction, slots[10], &s, &ep);
        VortexNavSnapshot b = vortex_nav_step(&st, 1.5, positions, 3);
        VortexIconVisual again = visual(kind, vortex_nav_role(&b, 1), b.progress, b.direction, slots[10], &s, &ep);
        CHECK(memcmp(&held, &again, sizeof held) == 0, "%s: pause holds", NAMES[kind]);
        CHECK(!vortex_icon_is_identity(held), "%s: mid-swipe icon moves", NAMES[kind]);
        VortexNavSnapshot c = vortex_nav_step(&st, 1.0, positions, 3);
        CHECK(!c.active, "%s: cancel settles", NAMES[kind]);
        for (int i = 0; i < n; i++)
            CHECK(vortex_icon_is_identity(visual(kind, vortex_nav_role(&c, 1), c.progress, c.direction, slots[i], &s, &ep)),
                  "%s: cancelled page fully restored", NAMES[kind]);
    }
}

static double centre_dist(double x, double y, double cx, double cy) { return hypot(x - cx, y - cy); }

static void test_orbital_rings(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexEffectParameters ep = vortex_default_parameters();
    for (int rings = 2; rings <= 5; rings++) {
        VortexIconEffectSettings s = vortex_icon_settings_defaults();
        s.orbital.rings = rings;
        s.orbital.tilt = 0.0; /* flat: radial distance == ring radius exactly */
        double p = 0.6;      /* every outgoing icon is in orbit (u >= 0.45) */
        double cx = 0.12 * W * (1.0 - 2.0 * p) * 1.0, cy = -0.04 * H; /* forward: centre travels right -> left */
        double radii[8];
        int distinct = 0;
        for (int i = 0; i < n; i++) {
            VortexIconVisual v = visual(VortexIconEffectOrbital, VortexPageRoleOutgoing, p, 1, slots[i], &s, &ep);
            double r = centre_dist(slots[i].homeX + v.tx, slots[i].homeY + v.ty, cx, cy);
            int found = 0;
            for (int k = 0; k < distinct; k++) found |= fabs(radii[k] - r) < 0.5;
            if (!found && distinct < 8) radii[distinct++] = r;
        }
        CHECK(distinct == rings, "orbital: icons sit on exactly %d concentric rings (found %d)", rings, distinct);
    }
    /* Tilted rings give subtle depth only. */
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    s.orbital.tilt = 1.0;
    double zmin = 1e9, zmax = -1e9, smin = 9, smax = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = visual(VortexIconEffectOrbital, VortexPageRoleOutgoing, 0.6, 1, slots[i], &s, &ep);
        zmin = fmin(zmin, v.z); zmax = fmax(zmax, v.z); smin = fmin(smin, v.scale); smax = fmax(smax, v.scale);
    }
    CHECK(zmin < -20 && zmax > 20, "orbital: depth varies around the rings");
    CHECK(smax / smin < 1.45, "orbital: depth scaling stays subtle (%.2f..%.2f)", smin, smax);
}

static void test_warp_tunnel(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    VortexEffectParameters ep = vortex_default_parameters();
    double vx = 0.08 * W * 0.0, vy = -0.04 * H; /* p = 0.5: vanishing point centred horizontally */
    double homeMean = 0, midMean = 0, smax = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = visual(VortexIconEffectWarp, VortexPageRoleOutgoing, 0.5, 1, slots[i], &s, &ep);
        homeMean += centre_dist(slots[i].homeX, slots[i].homeY, vx, vy) / n;
        midMean += centre_dist(slots[i].homeX + v.tx, slots[i].homeY + v.ty, vx, vy) / n;
        smax = fmax(smax, v.scale);
    }
    CHECK(midMean < 0.6 * homeMean, "warp: icons compress towards the vanishing point (%.0f vs %.0f pt)", midMean, homeMean);
    CHECK(smax < 0.75, "warp: receding icons shrink (max scale %.2f)", smax);
    /* Opacity and scale change monotonically: no flashing or pulsing. */
    for (int i = 0; i < n; i++) {
        double prevO = 2, prevS = 2;
        int mono = 1;
        for (int k = 0; k <= 400; k++) {
            VortexIconVisual v = visual(VortexIconEffectWarp, VortexPageRoleOutgoing, k / 400.0, 1, slots[i], &s, &ep);
            mono &= v.opacity <= prevO + 1e-12 && v.scale <= prevS + 1e-12;
            prevO = v.opacity; prevS = v.scale;
        }
        CHECK(mono, "warp: outgoing opacity and scale never increase (icon %d)", i);
    }
}

static void test_holographic_layers(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexEffectParameters ep = vortex_default_parameters();
    for (int layers = 2; layers <= 4; layers++) {
        VortexIconEffectSettings s = vortex_icon_settings_defaults();
        s.holo.layers = layers;
        s.holo.depth = 1.0;
        double zs[8];
        int distinct = 0;
        double frontMove = 0, backMove = 1e9;
        for (int i = 0; i < n; i++) {
            VortexIconVisual v = visual(VortexIconEffectHolographic, VortexPageRoleOutgoing, 0.4, 1, slots[i], &s, &ep);
            int found = 0;
            for (int k = 0; k < distinct; k++) found |= fabs(zs[k] - v.z) < 0.5;
            if (!found && distinct < 8) zs[distinct++] = v.z;
            int layer = slots[i].index % layers;
            if (layer == layers - 1) frontMove = fmax(frontMove, fabs(v.tx));
            if (layer == 0) backMove = fmin(backMove, fabs(v.tx));
            CHECK(fabs(v.tiltY) > 0.05, "holographic: icons tilt mid-swipe");
        }
        CHECK(distinct == layers, "holographic: %d depth layers (found %d)", layers, distinct);
        CHECK(frontMove > backMove + 5.0, "holographic: front layers move further (parallax %.0f vs %.0f)", frontMove, backMove);
    }
    /* Tilt 0 means no 3-D tilt at all; depth 0 means one plane. */
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    s.holo.tilt = 0;
    s.holo.depth = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = visual(VortexIconEffectHolographic, VortexPageRoleIncoming, 0.5, -1, slots[i], &s, &ep);
        CHECK(v.tiltX == 0 && v.tiltY == 0 && fabs(v.z) < 1e-9, "holographic: flat with tilt 0 and depth 0");
    }
}

static void test_circuit_traces(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexIconEffectSettings s = vortex_icon_settings_defaults();
    VortexEffectParameters ep = vortex_default_parameters();
    int drew = 0;
    for (int role = 1; role <= 2; role++)
        for (int i = 0; i < n; i++)
            for (int k = 0; k <= 200; k++) {
                double p = k / 200.0;
                VortexIconVisual v = visual(VortexIconEffectCircuitFlow, role, p, 1, slots[i], &s, &ep);
                /* Right-angle routing: either still in its column or on its lane. */
                double lane = slots[i].homeY + ((slots[i].index & 1) ? 1.0 : -1.0) * 0.06 * H;
                CHECK(fabs(v.tx) < 1e-6 || fabs(slots[i].homeY + v.ty - lane) < 1e-6,
                      "circuit: icon %d off its trace at p=%.3f", i, p);
                VortexTrace t = vortex_icon_effect_trace(VortexIconEffectCircuitFlow, role, p, 1, slots[i], W, H, &s, &ep);
                if (k == 0 || k == 200) CHECK(t.count == 0, "circuit: no trace at rest (p=%.2f)", p);
                if (t.count) {
                    drew++;
                    double len = 0;
                    for (int q = 1; q < t.count; q++) {
                        double dx = t.points[q].x - t.points[q - 1].x, dy = t.points[q].y - t.points[q - 1].y;
                        CHECK(fabs(dx) < 1e-6 || fabs(dy) < 1e-6, "circuit: trace segments are axis-aligned");
                        len += fabs(dx) + fabs(dy);
                    }
                    CHECK(len <= s.circuit.trail * W + 1e-6, "circuit: trail no longer than set (%.1f)", len);
                    CHECK(t.alpha > 0 && t.alpha <= s.circuit.intensity + 1e-12, "circuit: trace alpha within intensity");
                    /* The trail ends at the icon (behind it). */
                    VortexVec2 icon = { slots[i].homeX + v.tx, slots[i].homeY + v.ty };
                    VortexVec2 end = role == VortexPageRoleOutgoing ? t.points[t.count - 1] : t.points[0];
                    CHECK(hypot(end.x - icon.x, end.y - icon.y) < 1e-6, "circuit: trail attached to its icon");
                }
            }
    CHECK(drew > 1000, "circuit: traces drawn during the swipe (%d)", drew);
    for (int kind = 0; kind < VortexIconEffectCount; kind++) {
        if (kind == VortexIconEffectCircuitFlow) continue;
        VortexTrace t = vortex_icon_effect_trace(kind, VortexPageRoleOutgoing, 0.5, 1, slots[3], W, H, &s, &ep);
        CHECK(t.count == 0, "%s: draws no traces", NAMES[kind]);
    }
}

static void test_magnetic_snap(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexEffectParameters ep = vortex_default_parameters();
    CHECK(!vortex_icon_effect_pins_pages(VortexIconEffectMagnetic), "magnetic: pages move like iOS");
    for (int sv = 0; sv < 3; sv++) {
        VortexIconEffectSettings s = settings_variant(sv);
        double maxSep = 0, maxOvershoot = 0;
        for (int i = 0; i < n; i++) {
            double len = hypot(slots[i].homeX, slots[i].homeY);
            double dx = len > 1 ? slots[i].homeX / len : 0, dy = len > 1 ? slots[i].homeY / len : -1;
            int signChanges = 0;
            double prevRadial = 0;
            for (int k = 0; k <= 2000; k++) {
                VortexIconVisual v = visual(VortexIconEffectMagnetic, VortexPageRoleIncoming, k / 2000.0, 1, slots[i], &s, &ep);
                maxSep = fmax(maxSep, hypot(v.tx, v.ty));
                double radial = v.tx * dx + v.ty * dy;
                if (k > 1800 && radial < 0) maxOvershoot = fmax(maxOvershoot, -radial);
                if (k > 1800 && fabs(radial) > 1e-6 && fabs(prevRadial) > 1e-6 && (radial > 0) != (prevRadial > 0)) signChanges++;
                if (fabs(radial) > 1e-6) prevRadial = radial;
            }
            CHECK(signChanges <= 1, "magnetic: at most one overshoot, no bouncing (icon %d: %d)", i, signChanges);
        }
        CHECK(maxSep <= 14.0 * s.magnetic.strength + 6.0 * s.magnetic.strength * 1.4 + 3.0 * s.magnetic.snap + 1e-6,
              "magnetic: gentle separation (max %.1f pt)", maxSep);
        CHECK(maxOvershoot <= 3.0 * s.magnetic.snap + 1e-6, "magnetic: overshoot bounded (%.2f pt)", maxOvershoot);
        if (s.magnetic.snap >= 0.5) CHECK(maxOvershoot > 0.3, "magnetic: the snap is visible (%.2f pt)", maxOvershoot);
    }
}

static void test_settings(void) {
    VortexIconEffectSettings bad = vortex_icon_settings_defaults();
    bad.orbital.rings = 99; bad.orbital.radius = NAN; bad.warp.perspective = -4; bad.holo.layers = -1;
    bad.circuit.trail = 9; bad.magnetic.snap = NAN; bad.orbital.direction = (VortexSpinDirection)44;
    VortexIconEffectSettings s = vortex_icon_settings_sanitize(bad);
    VortexIconEffectSettings d = vortex_icon_settings_defaults();
    CHECK(s.orbital.rings == 5 && s.orbital.radius == d.orbital.radius && s.warp.perspective == 0.2 && s.holo.layers == 2 &&
              s.circuit.trail == 0.6 && s.magnetic.snap == d.magnetic.snap && s.orbital.direction == VortexSpinFollowSwipe,
          "settings sanitize");
    VortexIconEffectSettings dd = vortex_icon_settings_sanitize(d);
    /* Field-wise: struct padding bytes are unspecified, so never memcmp settings structs. */
    CHECK(d.orbital.radius == dd.orbital.radius && d.orbital.rings == dd.orbital.rings && d.orbital.tilt == dd.orbital.tilt &&
              d.orbital.speed == dd.orbital.speed && d.orbital.direction == dd.orbital.direction &&
              d.warp.intensity == dd.warp.intensity && d.warp.perspective == dd.warp.perspective &&
              d.holo.depth == dd.holo.depth && d.holo.tilt == dd.holo.tilt && d.holo.layers == dd.holo.layers &&
              d.circuit.trail == dd.circuit.trail && d.circuit.glow == dd.circuit.glow &&
              d.circuit.intensity == dd.circuit.intensity && d.magnetic.strength == dd.magnetic.strength &&
              d.magnetic.snap == dd.magnetic.snap && d.tornado.radius == dd.tornado.radius &&
              d.tornado.depth == dd.tornado.depth && d.tornado.travel == dd.tornado.travel,
          "defaults are valid");
    VortexIconSlot s1 = { .homeX = NAN, .rank = 0.5, .count = 3 };
    for (int kind = 0; kind < VortexIconEffectCount; kind++) {
        CHECK(vortex_icon_is_identity(visual(kind, 1, 0.5, 1, s1, NULL, NULL)), "%s: NaN home is ignored", NAMES[kind]);
        VortexIconSlot ok = { .homeX = 10, .homeY = 5, .rank = 0.5, .index = 1, .count = 1 };
        VortexIconVisual v = vortex_icon_effect_visual(kind, 1, NAN, 0, ok, W, H, NULL, NULL);
        CHECK(isfinite(v.tx) && isfinite(v.opacity), "%s: NaN progress, no navigation: finite", NAMES[kind]);
        CHECK(vortex_icon_is_identity(vortex_icon_effect_visual(kind, 1, 0.5, 1, ok, 0, 0, NULL, NULL)),
              "%s: zero-size page is ignored", NAMES[kind]);
    }
}

int main(void) {
    test_contract();
    test_continuity();
    test_pause_reverse_cancel();
    test_orbital_rings();
    test_warp_tunnel();
    test_holographic_layers();
    test_circuit_traces();
    test_magnetic_snap();
    test_settings();
    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
