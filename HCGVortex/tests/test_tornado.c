//
//  test_tornado.c — host unit tests for the Tornado effect geometry.
//
//  Tests the exact C functions the SpringBoard engine calls per icon
//  (vortex_tornado_icon / _page / _rank), driven through the same navigation
//  state machine (vortex_nav_step). They verify geometry and restoration
//  logic, not on-device SpringBoard rendering.
//

#include "../src/VortexMath.h"
#include "../src/VortexTornado.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        g_checks++;                                                            \
        if (!(cond)) {                                                         \
            g_failures++;                                                      \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);               \
            fprintf(stderr, __VA_ARGS__);                                      \
            fprintf(stderr, "\n");                                             \
        }                                                                      \
    } while (0)

#define NEAR(a, b, eps) (fabs((a) - (b)) <= (eps))

/* iPhone-like page: 390 x 844 pt, 4 x 6 grid. */
static const double W = 390.0, H = 844.0;

static int make_grid(VortexIconSlot *slots, int count) {
    int n = 0;
    for (int row = 0; row < 6 && n < count; row++) {
        for (int col = 0; col < 4 && n < count; col++) {
            slots[n].homeX = -146.25 + col * 97.5;
            slots[n].homeY = -300.0 + row * 110.0 + ((col & 1) ? 0.4 : 0.0); /* sub-point jitter */
            n++;
        }
    }
    vortex_tornado_rank(slots, n, 8.0);
    return n;
}

static VortexTornadoParameters tornado_variant(int i) {
    VortexTornadoParameters t = vortex_tornado_defaults();
    switch (i % 6) {
        case 1: t.intensity = 0.1; t.radius = 0.15; t.rotations = 1.0; break;
        case 2: t.intensity = 1.0; t.radius = 0.6; t.rotations = 4.0; break;
        case 3: t.direction = VortexSpinClockwise; t.depth = 0; break;
        case 4: t.direction = VortexSpinCounterclockwise; t.iconSpin = 1; break;
        case 5: t.iconSpin = 1; t.depth = 1; t.intensity = 0.5; break;
        default: break;
    }
    return t;
}

static VortexEffectParameters params_variant(int i) {
    VortexEffectParameters p = vortex_default_parameters();
    switch (i % 5) {
        case 1: p.easing = VortexEasingEaseInOut; break;
        case 2: p.easing = VortexEasingSine; p.speed = 2.0; break;
        case 3: p.speed = 0.5; p.reverse = 1; break;
        case 4: p.easing = VortexEasingEaseOut; p.speed = 4.0; break;
        default: break;
    }
    return p;
}

static void test_defaults_and_sanitize(void) {
    VortexTornadoParameters d = vortex_tornado_defaults();
    CHECK(d.depth == 1 && d.iconSpin == 0 && d.direction == VortexSpinFollowSwipe, "defaults: readable icons, depth on");
    VortexTornadoParameters bad = { NAN, 99.0, -5.0, (VortexSpinDirection)17, 9, -2 };
    VortexTornadoParameters s = vortex_tornado_sanitize(bad);
    CHECK(s.intensity == d.intensity && s.radius == 0.6 && s.rotations == 1.0 && s.direction == VortexSpinFollowSwipe &&
              s.depth == 1 && s.iconSpin == 1,
          "sanitize clamps (%.2f %.2f %.2f %d)", s.intensity, s.radius, s.rotations, (int)s.direction);
}

static void test_rank(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    CHECK(n == 24, "grid");
    CHECK(slots[0].index == 0 && NEAR(slots[0].rank, 0.0, 1e-12), "top-left first");
    CHECK(slots[3].index == 3, "jittered row stays one row (index %d)", slots[3].index);
    CHECK(slots[23].index == 23 && NEAR(slots[23].rank, 1.0, 1e-12), "bottom-right last");
    VortexIconSlot one[1] = { { 0, 0, 0, 0, 0 } };
    vortex_tornado_rank(one, 1, 8.0);
    CHECK(NEAR(one[0].rank, 0.5, 1e-12) && one[0].index == 0, "single icon ranks mid-funnel");
    vortex_tornado_rank(NULL, 3, 8.0); /* must not crash */
    vortex_tornado_rank(slots, 0, 8.0);
    /* Shuffled input gives the same ranks. */
    VortexIconSlot shuffled[24];
    for (int i = 0; i < 24; i++) shuffled[i] = slots[(i * 7) % 24];
    vortex_tornado_rank(shuffled, 24, 8.0);
    int same = 1;
    for (int i = 0; i < 24; i++) same &= shuffled[i].index == slots[(i * 7) % 24].index;
    CHECK(same, "rank independent of subview order");
}

static void test_endpoints(void) {
    VortexIconSlot slots[24];
    for (int count = 1; count <= 24; count++) {
        int n = make_grid(slots, count);
        for (int tv = 0; tv < 6; tv++) {
            VortexTornadoParameters tp = tornado_variant(tv);
            for (int pv = 0; pv < 5; pv++) {
                VortexEffectParameters ep = params_variant(pv);
                for (int nav = -1; nav <= 1; nav += 2) {
                    for (int i = 0; i < n; i++) {
                        VortexIconVisual o0 = vortex_tornado_icon(VortexPageRoleOutgoing, 0.0, nav, slots[i], W, H, &tp, &ep);
                        VortexIconVisual i0 = vortex_tornado_icon(VortexPageRoleIncoming, 0.0, nav, slots[i], W, H, &tp, &ep);
                        VortexIconVisual o1 = vortex_tornado_icon(VortexPageRoleOutgoing, 1.0, nav, slots[i], W, H, &tp, &ep);
                        VortexIconVisual i1 = vortex_tornado_icon(VortexPageRoleIncoming, 1.0, nav, slots[i], W, H, &tp, &ep);
                        CHECK(vortex_icon_is_identity(o0), "p=0 outgoing identity (n=%d tv=%d pv=%d)", count, tv, pv);
                        CHECK(i0.opacity <= 1e-9, "p=0 incoming hidden (%.4f)", i0.opacity);
                        CHECK(vortex_icon_is_identity(i1), "p=1 incoming identity (n=%d tv=%d pv=%d)", count, tv, pv);
                        CHECK(o1.opacity <= 1e-9, "p=1 outgoing hidden (%.4f)", o1.opacity);
                    }
                }
            }
        }
    }
    /* Page-level contract (same as every page effect). */
    VortexEffectParameters ep = vortex_default_parameters();
    CHECK(vortex_visual_is_identity(vortex_tornado_page(VortexPageRoleOutgoing, 0.0, &ep)), "page out p=0 identity");
    CHECK(vortex_tornado_page(VortexPageRoleIncoming, 0.0, &ep).opacity <= 1e-9, "page in p=0 hidden");
    CHECK(vortex_visual_is_identity(vortex_tornado_page(VortexPageRoleIncoming, 1.0, &ep)), "page in p=1 identity");
    CHECK(vortex_tornado_page(VortexPageRoleOutgoing, 1.0, &ep).opacity <= 1e-9, "page out p=1 hidden");
    VortexPageVisual mid = vortex_tornado_page(VortexPageRoleOutgoing, 0.5, &ep);
    CHECK(NEAR(mid.translation.x, 0, 1e-12) && NEAR(mid.translation.y, 0, 1e-12) && NEAR(mid.opacity, 1, 1e-12),
          "pages stay centred and opaque mid-swipe");
    /* Fallback (widgets etc.). */
    CHECK(vortex_icon_is_identity(vortex_tornado_fallback_icon(VortexPageRoleOutgoing, 0.0, &ep)), "fallback out p=0");
    CHECK(vortex_icon_is_identity(vortex_tornado_fallback_icon(VortexPageRoleIncoming, 1.0, &ep)), "fallback in p=1");
    CHECK(vortex_tornado_fallback_icon(VortexPageRoleIncoming, 0.0, &ep).opacity <= 1e-9, "fallback in p=0 hidden");
    CHECK(vortex_tornado_fallback_icon(VortexPageRoleOutgoing, 1.0, &ep).opacity <= 1e-9, "fallback out p=1 hidden");
    /* Role none never moves. */
    CHECK(vortex_icon_is_identity(vortex_tornado_icon(VortexPageRoleNone, 0.5, 1, slots[0], W, H, NULL, &ep)), "role none");
}

/* Worst per-frame change over a sweep of `steps` frames, every icon. */
static void sweep_worst(const VortexIconSlot *slots, int n, int role, int nav, const VortexTornadoParameters *tp,
                        const VortexEffectParameters *ep, double from, int steps, double *move, double *opacity) {
    *move = 0;
    *opacity = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual prev = vortex_tornado_icon(role, from, nav, slots[i], W, H, tp, ep);
        for (int k = 1; k <= steps; k++) {
            VortexIconVisual cur = vortex_tornado_icon(role, from + (1.0 - from) * k / steps, nav, slots[i], W, H, tp, ep);
            double m = hypot(cur.tx - prev.tx, cur.ty - prev.ty);
            if (m > *move) *move = m;
            double d = fabs(cur.opacity - prev.opacity);
            if (d > *opacity) *opacity = d;
            CHECK(isfinite(cur.tx) && isfinite(cur.ty) && isfinite(cur.scale) && isfinite(cur.z) &&
                      isfinite(cur.rotation) && cur.opacity >= 0 && cur.opacity <= 1 && cur.scale > 0.4 && cur.scale < 1.2,
                  "finite and restrained (scale %.3f)", cur.scale);
            prev = cur;
        }
    }
}

/* Pausing holds, reversing unwinds: the visual is a pure function of progress,
   and consecutive frames never jump. Continuity is checked by halving the
   frame step: a real jump would not shrink. */
static void test_continuity(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    for (int tv = 0; tv < 6; tv++) {
        VortexTornadoParameters tp = tornado_variant(tv);
        for (int pv = 0; pv < 5; pv++) {
            VortexEffectParameters ep = params_variant(pv);
            for (int role = VortexPageRoleOutgoing; role <= VortexPageRoleIncoming; role++) {
                double m1, o1, m2, o2;
                int nav = tv & 1 ? -1 : 1;
                /* The shared Speed setting warps progress as t^(1/speed), whose slope is
                   infinite at 0 for speed > 1 (every effect shares this). Those variants are
                   step-tested from 0.01; the limit at 0 is checked separately below. */
                double from = ep.speed > 1.0 ? 0.01 : 0.0;
                sweep_worst(slots, n, role, nav, &tp, &ep, from, 1000, &m1, &o1);
                sweep_worst(slots, n, role, nav, &tp, &ep, from, 8000, &m2, &o2);
                CHECK(m2 < 0.2 * m1 + 1e-9, "continuous position (tv=%d pv=%d role=%d: %.3f -> %.3f pt)", tv, pv, role, m1, m2);
                CHECK(o2 < 0.2 * o1 + 1e-9, "continuous opacity (tv=%d pv=%d role=%d: %.4f -> %.4f)", tv, pv, role, o1, o2);
                if (from > 0.0) {
                    for (int i = 0; i < n; i++) {
                        VortexIconVisual at0 = vortex_tornado_icon(role, 0.0, nav, slots[i], W, H, &tp, &ep);
                        VortexIconVisual near0 = vortex_tornado_icon(role, 1e-12, nav, slots[i], W, H, &tp, &ep);
                        int invisible = near0.opacity < 0.01 && at0.opacity < 0.01; /* motion while hidden is unseen */
                        CHECK((invisible || hypot(near0.tx - at0.tx, near0.ty - at0.ty) < 2.0) &&
                                  fabs(near0.opacity - at0.opacity) < 0.01,
                              "continuous at progress 0 under speed warp (tv=%d pv=%d)", tv, pv);
                    }
                }
            }
        }
    }
    /* Default settings: gentle per-frame motion (2000 frames per swipe). */
    VortexTornadoParameters tp = vortex_tornado_defaults();
    VortexEffectParameters ep = vortex_default_parameters();
    double m, o;
    sweep_worst(slots, n, VortexPageRoleOutgoing, 1, &tp, &ep, 0.0, 2000, &m, &o);
    CHECK(m < 4.0 && o < 0.01, "defaults: worst %.2f pt and %.4f opacity per 1/2000 swipe", m, o);

    /* Pure function: going forward then back gives exactly the same frames. */
    VortexIconVisual direct = vortex_tornado_icon(VortexPageRoleOutgoing, 0.3, 1, slots[5], W, H, &tp, &ep);
    for (int k = 0; k <= 60; k++) (void)vortex_tornado_icon(VortexPageRoleOutgoing, k / 100.0, 1, slots[5], W, H, &tp, &ep);
    VortexIconVisual again = vortex_tornado_icon(VortexPageRoleOutgoing, 0.3, 1, slots[5], W, H, &tp, &ep);
    CHECK(memcmp(&direct, &again, sizeof direct) == 0, "pausing/reversing returns the identical formation");
}

/* Cancelling and rapid swipes through the real navigation state machine. */
static void test_navigation_cancel_and_reverse(void) {
    double positions[] = { 0, 1, 2, 3 };
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexTornadoParameters tp = vortex_tornado_defaults();
    VortexEffectParameters ep = vortex_default_parameters();
    VortexNavState st;
    vortex_nav_reset(&st);
    vortex_nav_step(&st, 1.0, positions, 4);
    VortexNavSnapshot s = vortex_nav_step(&st, 1.6, positions, 4); /* finger left, 60 % */
    CHECK(s.active && s.direction == VortexNavigationForward, "forward swipe");
    VortexIconVisual held = vortex_tornado_icon(vortex_nav_role(&s, 1), s.progress, s.direction, slots[9], W, H, &tp, &ep);
    CHECK(!vortex_icon_is_identity(held), "mid-swipe icon is in the funnel");
    s = vortex_nav_step(&st, 1.6, positions, 4); /* pause */
    VortexIconVisual paused = vortex_tornado_icon(vortex_nav_role(&s, 1), s.progress, s.direction, slots[9], W, H, &tp, &ep);
    CHECK(memcmp(&held, &paused, sizeof held) == 0, "pause holds the formation");
    s = vortex_nav_step(&st, 1.2, positions, 4); /* reverse */
    VortexIconVisual unwound = vortex_tornado_icon(vortex_nav_role(&s, 1), s.progress, s.direction, slots[9], W, H, &tp, &ep);
    CHECK(hypot(unwound.tx, unwound.ty) < hypot(held.tx, held.ty), "reversing unwinds towards the grid");
    s = vortex_nav_step(&st, 1.0, positions, 4); /* cancelled: back on the original page */
    CHECK(!s.active, "cancel settles the state machine (engine then restores every icon)");
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = vortex_tornado_icon(vortex_nav_role(&s, 1), s.progress, s.direction, slots[i], W, H, &tp, &ep);
        CHECK(vortex_icon_is_identity(v), "original page restored after cancel (icon %d)", i);
    }
    /* Rapid flick across two pages without settling: the old page ends hidden,
       the destination ends exactly in its grid. */
    s = vortex_nav_step(&st, 1.7, positions, 4);
    s = vortex_nav_step(&st, 2.4, positions, 4);
    CHECK(s.active && NEAR(s.base, 2, 1e-12), "re-based on the intermediate page");
    CHECK(vortex_nav_role(&s, 1) == VortexPageRoleNone, "first page leaves the transition (engine restores it)");
    s = vortex_nav_step(&st, 3.0, positions, 4);
    CHECK(!s.active, "settled on the destination");
}

/* The formation at mid-swipe is a recognisable tapered funnel with depth. */
static void test_funnel_shape(void) {
    VortexIconSlot slots[24];
    int n = make_grid(slots, 24);
    VortexTornadoParameters tp = vortex_tornado_defaults();
    tp.intensity = 1.0;
    VortexEffectParameters ep = vortex_default_parameters();
    double p = 0.6; /* every outgoing icon has fully joined the funnel here */
    double cx = vortex_tornado_centre_x(p, 1, W, &ep);
    double topMax = 0, tipMax = 0, yMin = 1e9, yMax = -1e9, zMin = 1e9, zMax = -1e9;
    double frontScale = 0, backScale = 10, frontOpacity = 0, backOpacity = 1;
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = vortex_tornado_icon(VortexPageRoleOutgoing, p, 1, slots[i], W, H, &tp, &ep);
        double x = slots[i].homeX + v.tx, y = slots[i].homeY + v.ty;
        double radial = fabs(x - cx);
        if (slots[i].rank <= 0.25 && radial > topMax) topMax = radial;
        if (slots[i].rank >= 0.75 && radial > tipMax) tipMax = radial;
        if (y < yMin) yMin = y;
        if (y > yMax) yMax = y;
        if (v.z < zMin) zMin = v.z;
        if (v.z > zMax) zMax = v.z;
        if (v.z > 20 && v.scale > frontScale) frontScale = v.scale;
        if (v.z < -20 && v.scale < backScale) backScale = v.scale;
        if (v.z > 20 && v.opacity > frontOpacity) frontOpacity = v.opacity;
        if (v.z < -20 && v.opacity < backOpacity) backOpacity = v.opacity;
    }
    CHECK(topMax > 2.5 * tipMax, "tapered: opening %.1f pt vs tip %.1f pt", topMax, tipMax);
    CHECK(yMax - yMin > 0.35 * H, "tall: spans %.0f pt of %.0f", yMax - yMin, H);
    CHECK(zMin < -40 && zMax > 40, "icons on the front and back of the funnel (z %.0f..%.0f)", zMin, zMax);
    CHECK(frontScale > backScale, "perspective: front %.2f > back %.2f", frontScale, backScale);
    CHECK(frontOpacity > backOpacity, "back of the funnel dimmer (%.2f vs %.2f)", frontOpacity, backOpacity);

    /* Depth off: no z, no dimming difference from depth. */
    tp.depth = 0;
    for (int i = 0; i < n; i++) {
        VortexIconVisual v = vortex_tornado_icon(VortexPageRoleOutgoing, p, 1, slots[i], W, H, &tp, &ep);
        CHECK(v.z == 0.0, "depth off: z 0");
    }
    /* Mid-swipe: both pages are in the funnel, at the same time. */
    tp = vortex_tornado_defaults();
    int visibleOut = 0, visibleIn = 0;
    for (int i = 0; i < n; i++) {
        if (vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, slots[i], W, H, &tp, &ep).opacity > 0.5) visibleOut++;
        if (vortex_tornado_icon(VortexPageRoleIncoming, 0.5, 1, slots[i], W, H, &tp, &ep).opacity > 0.5) visibleIn++;
    }
    CHECK(visibleOut >= n / 2 && visibleIn >= n / 2, "mid-swipe funnel holds both pages (%d + %d)", visibleOut, visibleIn);
}

static void test_direction_and_travel(void) {
    CHECK(vortex_tornado_spin_sign(VortexSpinFollowSwipe, VortexNavigationForward) ==
              vortex_tornado_spin_sign(VortexSpinClockwise, VortexNavigationForward),
          "follow swipe (finger left) == clockwise");
    CHECK(vortex_tornado_spin_sign(VortexSpinFollowSwipe, VortexNavigationBackward) ==
              vortex_tornado_spin_sign(VortexSpinCounterclockwise, VortexNavigationBackward),
          "follow swipe (finger right) == counterclockwise");
    CHECK(vortex_tornado_spin_sign(VortexSpinClockwise, VortexNavigationBackward) == -1.0, "clockwise is fixed");

    VortexEffectParameters ep = vortex_default_parameters();
    CHECK(vortex_tornado_centre_x(0, 1, W, &ep) > 0 && vortex_tornado_centre_x(1, 1, W, &ep) < 0,
          "finger left: funnel travels right to left");
    CHECK(vortex_tornado_centre_x(0, -1, W, &ep) < 0 && vortex_tornado_centre_x(1, -1, W, &ep) > 0,
          "finger right: funnel travels left to right");
    ep.reverse = 1;
    CHECK(vortex_tornado_centre_x(0, 1, W, &ep) < 0, "reverse animation flips the travel");

    /* Clockwise and counterclockwise produce different (mirrored-motion) frames. */
    VortexIconSlot slots[24];
    make_grid(slots, 24);
    ep = vortex_default_parameters();
    VortexTornadoParameters cw = vortex_tornado_defaults(), ccw = vortex_tornado_defaults();
    cw.direction = VortexSpinClockwise;
    ccw.direction = VortexSpinCounterclockwise;
    VortexIconVisual a = vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, slots[10], W, H, &cw, &ep);
    VortexIconVisual b = vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, slots[10], W, H, &ccw, &ep);
    CHECK(fabs(a.tx - b.tx) > 1.0 || fabs(a.z - b.z) > 1.0, "spin direction changes the formation");

    /* Readable by default; spinning is opt-in. */
    VortexTornadoParameters tp = vortex_tornado_defaults();
    int anyRot = 0;
    for (int k = 0; k <= 100; k++)
        anyRot |= vortex_tornado_icon(VortexPageRoleOutgoing, k / 100.0, 1, slots[3], W, H, &tp, &ep).rotation != 0.0;
    CHECK(!anyRot, "icons never rotate unless Icon Spin is on");
    tp.iconSpin = 1;
    CHECK(fabs(vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, slots[3], W, H, &tp, &ep).rotation) > 0.1,
          "icon spin rotates icons");
}

static void test_degenerate(void) {
    VortexEffectParameters ep = vortex_default_parameters();
    VortexIconSlot s = { 10, 10, 0.5, 3, 24 };
    CHECK(vortex_icon_is_identity(vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, s, 0, 0, NULL, &ep)),
          "zero-size page: identity");
    VortexIconSlot nanSlot = { NAN, 0, 0.5, 0, 24 };
    CHECK(vortex_icon_is_identity(vortex_tornado_icon(VortexPageRoleOutgoing, 0.5, 1, nanSlot, W, H, NULL, &ep)),
          "NaN home: identity");
    VortexIconVisual v = vortex_tornado_icon(VortexPageRoleOutgoing, NAN, 1, s, W, H, NULL, &ep);
    CHECK(isfinite(v.tx) && isfinite(v.opacity), "NaN progress finite");
    v = vortex_tornado_icon(VortexPageRoleOutgoing, 7.0, 1, s, W, H, NULL, NULL);
    CHECK(v.opacity <= 1e-9, "progress > 1 clamps (swept away)");
    v = vortex_tornado_icon(VortexPageRoleIncoming, 0.5, VortexNavigationNone, s, W, H, NULL, NULL);
    CHECK(isfinite(v.tx), "no navigation direction: finite");
}

int main(void) {
    test_defaults_and_sanitize();
    test_rank();
    test_endpoints();
    test_continuity();
    test_navigation_cancel_and_reverse();
    test_funnel_shape();
    test_direction_and_travel();
    test_degenerate();
    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
