//
//  test_math.c — host unit tests for the HCG Vortex math core.
//
//  Build & run (any host with a C compiler):
//      make -C tests            or     scripts/validate.sh
//
//  These tests exercise the exact pipeline the SpringBoard engine uses
//  (vortex_nav_step + vortex_compose_page). They verify the math, not the
//  on-device SpringBoard integration.
//

#include "../src/VortexMath.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

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

/* ---- Effect trampolines (mirror the ObjC effect classes) ------------------ */

typedef struct {
    VortexBuiltinEffect forward;
    VortexBuiltinEffect backward;
} EffectPair;

static VortexPageVisual builtin_effect(void *ctx, VortexPageRole role, double progress,
                                       VortexNavigationDirection dir, const VortexEffectParameters *p) {
    EffectPair *pair = (EffectPair *)ctx;
    VortexBuiltinEffect e = dir == VortexNavigationBackward ? pair->backward : pair->forward;
    VortexDirection in, out;
    vortex_builtin_directions(e, dir, &in, &out);
    return vortex_directional_visual(role, progress, in, out, p);
}

/* On-screen state of a page after the solver: where the user SEES it. */
typedef struct {
    double x, y, opacity;
} Seen;

static Seen seen_for(VortexPageVisual solved, double position, double actual) {
    Seen s;
    s.x = solved.translation.x + (position - actual);
    s.y = solved.translation.y;
    s.opacity = solved.opacity;
    return s;
}

static int seen_visible(Seen s) {
    return fabs(s.x) < 0.999 && fabs(s.y) < 0.999 && s.opacity > 0.001;
}

/* Fraction of the screen the page covers, weighted by opacity (0..1). */
static double seen_amount(Seen s) {
    double ax = 1.0 - fabs(s.x), ay = 1.0 - fabs(s.y);
    if (ax < 0) ax = 0;
    if (ay < 0) ay = 0;
    return ax * ay * (s.opacity < 0 ? 0 : s.opacity);
}

/* ---- Tests ---------------------------------------------------------------- */

static void test_easing(void) {
    for (int e = 0; e < VortexEasingCount; e++) {
        CHECK(NEAR(vortex_ease((VortexEasing)e, 0.0), 0.0, 1e-12), "ease %d f(0)", e);
        CHECK(NEAR(vortex_ease((VortexEasing)e, 1.0), 1.0, 1e-12), "ease %d f(1)", e);
        double prev = 0.0;
        for (int i = 1; i <= 1000; i++) {
            double v = vortex_ease((VortexEasing)e, i / 1000.0);
            CHECK(v >= prev - 1e-12, "ease %d monotonic at %d", e, i);
            prev = v;
        }
        CHECK(NEAR(vortex_ease((VortexEasing)e, -5), 0.0, 1e-12), "ease %d clamps low", e);
        CHECK(NEAR(vortex_ease((VortexEasing)e, 5), 1.0, 1e-12), "ease %d clamps high", e);
    }
    CHECK(NEAR(vortex_ease((VortexEasing)999, 0.3), 0.3, 1e-12), "unknown easing -> linear");
}

static void test_speed_warp(void) {
    double speeds[] = { 0.25, 0.5, 1.0, 2.0, 4.0, 100.0, -1.0, NAN };
    for (unsigned i = 0; i < sizeof(speeds) / sizeof(speeds[0]); i++) {
        CHECK(NEAR(vortex_speed_warp(0.0, speeds[i]), 0.0, 1e-12), "warp(0) speed %g", speeds[i]);
        CHECK(NEAR(vortex_speed_warp(1.0, speeds[i]), 1.0, 1e-12), "warp(1) speed %g", speeds[i]);
    }
    CHECK(vortex_speed_warp(0.25, 2.0) > 0.25, "speed>1 is ahead of linear");
    CHECK(vortex_speed_warp(0.25, 0.5) < 0.25, "speed<1 is behind linear");
}

static void test_directions(void) {
    for (int d = VortexDirectionLeft; d < VortexDirectionCount; d++) {
        const char *name = vortex_direction_to_string((VortexDirection)d);
        CHECK((int)vortex_direction_from_string(name) == d, "roundtrip %s", name);
        VortexDirection o = vortex_direction_opposite((VortexDirection)d);
        VortexVec2 a = vortex_direction_vector((VortexDirection)d), b = vortex_direction_vector(o);
        CHECK(a.x == -b.x && a.y == -b.y, "opposite of %s", name);
        CHECK(fabs(a.x) + fabs(a.y) >= 1.0, "%s non-zero", name);
    }
    CHECK(vortex_direction_from_string("sideways") == VortexDirectionNone, "unknown direction");
    CHECK(vortex_direction_from_string(NULL) == VortexDirectionNone, "NULL direction");
    VortexVec2 up = vortex_direction_vector(VortexDirectionUp);
    CHECK(up.x == 0 && up.y == -1, "up is -y (UIKit)");
}

static void test_builtin_table(void) {
    VortexDirection in, out;
    vortex_builtin_directions(VortexBuiltinEffectStock, VortexNavigationForward, &in, &out);
    CHECK(in == VortexDirectionRight && out == VortexDirectionLeft, "stock forward");
    vortex_builtin_directions(VortexBuiltinEffectStock, VortexNavigationBackward, &in, &out);
    CHECK(in == VortexDirectionLeft && out == VortexDirectionRight, "stock backward");
    vortex_builtin_directions(VortexBuiltinEffectReverseSlide, VortexNavigationForward, &in, &out);
    CHECK(in == VortexDirectionLeft && out == VortexDirectionRight, "reverse forward");
    vortex_builtin_directions(VortexBuiltinEffectReverseSlide, VortexNavigationBackward, &in, &out);
    CHECK(in == VortexDirectionRight && out == VortexDirectionLeft, "reverse backward");
    for (int n = -1; n <= 1; n += 2) {
        vortex_builtin_directions(VortexBuiltinEffectVerticalRise, (VortexNavigationDirection)n, &in, &out);
        CHECK(in == VortexDirectionDown && out == VortexDirectionUp, "rise nav %d", n);
        vortex_builtin_directions(VortexBuiltinEffectVerticalFall, (VortexNavigationDirection)n, &in, &out);
        CHECK(in == VortexDirectionUp && out == VortexDirectionDown, "fall nav %d", n);
    }
    for (int e = 0; e < VortexBuiltinEffectCount; e++) {
        int ok = 0;
        const char *name = vortex_builtin_effect_to_string((VortexBuiltinEffect)e);
        CHECK((int)vortex_builtin_effect_from_string(name, &ok) == e && ok, "effect roundtrip %s", name);
    }
    int ok = 1;
    CHECK(vortex_builtin_effect_from_string("cube", &ok) == VortexBuiltinEffectStock && !ok, "unknown effect");
}

static VortexEffectParameters params_variant(int i) {
    VortexEffectParameters p = vortex_default_parameters();
    double intensities[] = { 1.0, 0.6, 0.1 };
    p.intensity = intensities[i % 3];
    p.easing = (VortexEasing)((i / 3) % VortexEasingCount);
    p.fadePages = (i / 15) % 2;
    p.reverse = (i / 30) % 2;
    double speeds[] = { 1.0, 0.25, 4.0 };
    p.speed = speeds[(i / 60) % 3];
    return p;
}
#define PARAM_VARIANTS 180

static void test_endpoint_invariants(void) {
    for (int v = 0; v < PARAM_VARIANTS; v++) {
        VortexEffectParameters p = params_variant(v);
        for (int din = VortexDirectionLeft; din < VortexDirectionCount; din++) {
            for (int dout = VortexDirectionLeft; dout < VortexDirectionCount; dout++) {
                VortexPageVisual o0 = vortex_directional_visual(VortexPageRoleOutgoing, 0, din, dout, &p);
                CHECK(vortex_visual_is_identity(o0), "outgoing identity at 0 (v%d %d/%d)", v, din, dout);
                VortexPageVisual i1 = vortex_directional_visual(VortexPageRoleIncoming, 1, din, dout, &p);
                CHECK(vortex_visual_is_identity(i1), "incoming identity at 1 (v%d %d/%d)", v, din, dout);
                VortexPageVisual i0 = vortex_directional_visual(VortexPageRoleIncoming, 0, din, dout, &p);
                Seen si0 = { i0.translation.x, i0.translation.y, i0.opacity };
                CHECK(!seen_visible(si0), "incoming hidden at 0 (v%d %d/%d)", v, din, dout);
                VortexPageVisual o1 = vortex_directional_visual(VortexPageRoleOutgoing, 1, din, dout, &p);
                Seen so1 = { o1.translation.x, o1.translation.y, o1.opacity };
                CHECK(!seen_visible(so1), "outgoing hidden at 1 (v%d %d/%d)", v, din, dout);
                VortexPageVisual n = vortex_directional_visual(VortexPageRoleNone, 0.5, din, dout, &p);
                CHECK(vortex_visual_is_identity(n), "role none identity");
            }
        }
    }
}

static void test_stock_is_noop(void) {
    /* With the stock effect and linear/1x/intensity 1, the solver must apply
       no transform at all: Vortex never fights native motion. */
    EffectPair stock = { VortexBuiltinEffectStock, VortexBuiltinEffectStock };
    VortexEffectParameters p = vortex_default_parameters();
    double positions[] = { 0, 1, 2, 3 };
    VortexNavState st;
    vortex_nav_reset(&st);
    for (double s = 0; s <= 3.0; s += 0.01) {
        VortexNavSnapshot snap = vortex_nav_step(&st, s, positions, 4);
        for (int i = 0; i < 4; i++) {
            VortexPageVisual v = vortex_compose_page(&snap, positions[i], s, s, builtin_effect, &stock, &p);
            CHECK(fabs(v.translation.x) < 1e-9 && fabs(v.translation.y) < 1e-9 && NEAR(v.opacity, 1, 1e-9),
                  "stock no-op s=%.2f page %d (%.4f,%.4f)", s, i, v.translation.x, v.translation.y);
        }
    }
}

static void test_reverse_slide_mirror(void) {
    EffectPair rev = { VortexBuiltinEffectReverseSlide, VortexBuiltinEffectReverseSlide };
    VortexEffectParameters p = vortex_default_parameters();
    double positions[] = { 0, 1, 2 };
    VortexNavState st;
    vortex_nav_reset(&st);
    for (double s = 0.05; s < 0.96; s += 0.05) {
        VortexNavSnapshot snap = vortex_nav_step(&st, s, positions, 3);
        for (int i = 0; i < 2; i++) {
            VortexPageVisual v = vortex_compose_page(&snap, positions[i], s, s, builtin_effect, &rev, &p);
            Seen seen = seen_for(v, positions[i], s);
            CHECK(NEAR(seen.x, -(positions[i] - s), 1e-9), "mirror s=%.2f page %d seen %.4f", s, i, seen.x);
            CHECK(NEAR(seen.y, 0, 1e-12), "mirror stays horizontal");
        }
    }
}

static void test_vertical_rise_geometry(void) {
    EffectPair rise = { VortexBuiltinEffectVerticalRise, VortexBuiltinEffectVerticalRise };
    VortexEffectParameters p = vortex_default_parameters();
    double positions[] = { 0, 1, 2 };
    /* Forward (swipe left) from page 1 to 2 and backward from 1 to 0: in both
       cases the outgoing page goes UP and the incoming rises from BELOW, with
       zero horizontal motion on screen. */
    for (int dir = -1; dir <= 1; dir += 2) {
        VortexNavState st;
        vortex_nav_reset(&st);
        vortex_nav_step(&st, 1.0, positions, 3);
        double s = 1.0 + 0.4 * dir;
        VortexNavSnapshot snap = vortex_nav_step(&st, s, positions, 3);
        CHECK(snap.active && snap.direction == dir && NEAR(snap.progress, 0.4, 1e-9), "rise snapshot dir %d", dir);
        Seen out = seen_for(vortex_compose_page(&snap, 1, s, s, builtin_effect, &rise, &p), 1, s);
        Seen in = seen_for(vortex_compose_page(&snap, 1 + dir, s, s, builtin_effect, &rise, &p), 1 + dir, s);
        CHECK(NEAR(out.x, 0, 1e-9) && NEAR(out.y, -0.4, 1e-9), "rise outgoing up (dir %d): %.3f,%.3f", dir, out.x, out.y);
        CHECK(NEAR(in.x, 0, 1e-9) && NEAR(in.y, 0.6, 1e-9), "rise incoming below (dir %d): %.3f,%.3f", dir, in.x, in.y);
    }
}

static void test_navigation_state(void) {
    double positions[] = { 0, 1, 2, 3, 4 };
    VortexNavState st;
    vortex_nav_reset(&st);
    VortexNavSnapshot s = vortex_nav_step(&st, 2.0, positions, 5);
    CHECK(s.inRange && !s.active && NEAR(s.base, 2, 1e-12), "settled at 2");
    s = vortex_nav_step(&st, 2.3, positions, 5);
    CHECK(s.active && s.direction == VortexNavigationForward && NEAR(s.progress, 0.3, 1e-9), "forward 0.3");
    CHECK(vortex_nav_role(&s, 2) == VortexPageRoleOutgoing, "page 2 outgoing");
    CHECK(vortex_nav_role(&s, 3) == VortexPageRoleIncoming, "page 3 incoming");
    CHECK(vortex_nav_role(&s, 1) == VortexPageRoleNone, "page 1 none");
    /* Interrupted gesture reversing past the base: roles flip cleanly. */
    s = vortex_nav_step(&st, 1.8, positions, 5);
    CHECK(s.active && s.direction == VortexNavigationBackward && NEAR(s.base, 2, 1e-12) && NEAR(s.progress, 0.2, 1e-9),
          "reversal keeps base");
    CHECK(vortex_nav_role(&s, 1) == VortexPageRoleIncoming, "page 1 incoming after reversal");
    /* Crossing a page without settling advances the base. */
    s = vortex_nav_step(&st, 2.5, positions, 5);
    s = vortex_nav_step(&st, 3.25, positions, 5);
    CHECK(s.active && NEAR(s.base, 3, 1e-12) && NEAR(s.progress, 0.25, 1e-9), "base advanced to 3");
    /* Big jump (e.g. page-dot scrub). */
    s = vortex_nav_step(&st, 0.5, positions, 5);
    CHECK(s.active && NEAR(s.base, 1, 1e-12) && s.direction == VortexNavigationBackward, "jump back re-bases");
    /* Out of the icon pages (Today View on the left, App Library on the right). */
    s = vortex_nav_step(&st, -0.4, positions, 5);
    CHECK(!s.inRange && !s.active, "today view out of range");
    s = vortex_nav_step(&st, 4.6, positions, 5);
    CHECK(!s.inRange && !s.active, "app library out of range");
    /* Page removed underneath the base: re-anchors safely. */
    double fewer[] = { 0, 1 };
    vortex_nav_reset(&st);
    vortex_nav_step(&st, 3.0, positions, 5);
    s = vortex_nav_step(&st, 0.5, fewer, 2);
    CHECK(s.active && (NEAR(s.base, 0, 1e-12) || NEAR(s.base, 1, 1e-12)), "re-anchor after page removal");
    /* Degenerate input. */
    s = vortex_nav_step(&st, 1.0, positions, 0);
    CHECK(!s.inRange && !s.active, "no pages");
    s = vortex_nav_step(&st, NAN, positions, 5);
    CHECK(!s.inRange && !s.active, "NaN position");
    /* Non-unit spacing (pitch estimated slightly off). */
    double spaced[] = { 0.5, 1.52, 2.54 };
    vortex_nav_reset(&st);
    vortex_nav_step(&st, 0.5, spaced, 3);
    s = vortex_nav_step(&st, 1.01, spaced, 3);
    CHECK(s.active && NEAR(s.progress, 0.5, 1e-9), "progress normalised by real span (%.4f)", s.progress);
}

/* Sweep the presented position in small steps through every effect and
   parameter set; no visible page may jump between consecutive frames. */
static void test_continuity_sweep(void) {
    double positions[] = { 0, 1, 2, 3 };
    const int N = 4;
    double path[] = { 1.0, 2.0, 1.35, 3.0, 0.0, 0.6, 0.0 }; /* includes reversals & interruptions */
    const int P = (int)(sizeof(path) / sizeof(path[0]));
    const double step = 0.002;
    const double maxJump = 0.03; /* page units per 0.002 step; eased curves stay well below */

    for (int fe = 0; fe < VortexBuiltinEffectCount; fe++) {
        for (int be = 0; be < VortexBuiltinEffectCount; be++) {
            EffectPair pair = { (VortexBuiltinEffect)fe, (VortexBuiltinEffect)be };
            for (int v = 0; v < PARAM_VARIANTS; v += 7) {
                VortexEffectParameters p = params_variant(v);
                if (p.speed != 1.0) continue; /* steep warp near 0 is checked separately */
                VortexNavState st;
                vortex_nav_reset(&st);
                Seen prev[4];
                int havePrev = 0;
                for (int seg = 0; seg + 1 < P; seg++) {
                    double a = path[seg], b = path[seg + 1];
                    int steps = (int)ceil(fabs(b - a) / step);
                    for (int k = 0; k <= steps; k++) {
                        double s = a + (b - a) * ((double)k / (double)(steps ? steps : 1));
                        VortexNavSnapshot snap = vortex_nav_step(&st, s, positions, N);
                        for (int i = 0; i < N; i++) {
                            VortexPageVisual vis = vortex_compose_page(&snap, positions[i], s, s, builtin_effect, &pair, &p);
                            Seen cur = seen_for(vis, positions[i], s);
                            if (havePrev) {
                                double aNow = seen_amount(cur), aPrev = seen_amount(prev[i]);
                                /* A page that is (nearly) off-screen in either frame may be
                                   re-homed to another off-screen edge; what must not happen
                                   is a visible pop. Otherwise its on-screen position and
                                   opacity must move continuously. */
                                double jump = (aNow < maxJump || aPrev < maxJump)
                                                  ? fabs(aNow - aPrev)
                                                  : fabs(cur.x - prev[i].x) + fabs(cur.y - prev[i].y) +
                                                        fabs(cur.opacity - prev[i].opacity);
                                {
                                    CHECK(jump < maxJump,
                                          "jump fe=%d be=%d v=%d s=%.3f page %d: (%.3f,%.3f,%.2f)->(%.3f,%.3f,%.2f)",
                                          fe, be, v, s, i, prev[i].x, prev[i].y, prev[i].opacity, cur.x, cur.y, cur.opacity);
                                }
                            }
                            prev[i] = cur;
                        }
                        havePrev = 1;
                    }
                }
                /* Path ends settled on page 0: everything must be identity. */
                VortexNavSnapshot snap = vortex_nav_step(&st, 0.0, positions, N);
                for (int i = 0; i < N; i++) {
                    VortexPageVisual vis = vortex_compose_page(&snap, positions[i], 0.0, 0.0, builtin_effect, &pair, &p);
                    CHECK(vortex_visual_is_identity(vis), "settled identity page %d", i);
                }
            }
        }
    }
}

static void test_exactly_one_page_fully_visible_when_settled(void) {
    EffectPair pair = { VortexBuiltinEffectVerticalFall, VortexBuiltinEffectReverseSlide };
    VortexEffectParameters p = vortex_default_parameters();
    double positions[] = { 0, 1, 2 };
    VortexNavState st;
    vortex_nav_reset(&st);
    for (int target = 0; target < 3; target++) {
        VortexNavSnapshot snap = vortex_nav_step(&st, (double)target, positions, 3);
        int visible = 0;
        for (int i = 0; i < 3; i++) {
            Seen seen = seen_for(vortex_compose_page(&snap, positions[i], target, target, builtin_effect, &pair, &p),
                                 positions[i], target);
            if (seen_visible(seen)) {
                visible++;
                CHECK(i == target, "visible page is the actual current page (page index preserved)");
            }
        }
        CHECK(visible == 1, "one page visible when settled on %d", target);
    }
}

static void test_smoothing(void) {
    CHECK(vortex_smooth_step(0.0, 1.0, 0.016, 0.0) == 1.0, "duration 0 tracks exactly");
    CHECK(vortex_smooth_step(0.0, 5.0, 0.016, 0.5) == 5.0, "large gaps snap");
    CHECK(vortex_smooth_step(NAN, 1.0, 0.016, 0.5) == 1.0, "NaN snaps");
    double x = 0.0, t = 0.0;
    double duration = 0.4;
    int frames = 0;
    while (x != 1.0 && frames < 10000) {
        double nx = vortex_smooth_step(x, 1.0, 1.0 / 60.0, duration);
        CHECK(nx >= x && nx <= 1.0, "smoothing monotonic, no overshoot");
        x = nx;
        t += 1.0 / 60.0;
        frames++;
    }
    CHECK(x == 1.0, "smoothing converges exactly");
    CHECK(t < duration * 2.5, "converges within ~2x duration (%.3fs)", t);
    double mid = 0.0;
    for (int i = 0; i < 24; i++) mid = vortex_smooth_step(mid, 1.0, 1.0 / 60.0, duration); /* 0.4s */
    CHECK(mid > 0.98, "~99%% at duration (%.4f)", mid);
}

static void test_smoothed_pipeline_never_shows_two_pages_stacked(void) {
    /* With presentation lag, a fast jump 0 -> 2 must not leave the real page 2
       visible on top of the presented transition. */
    EffectPair pair = { VortexBuiltinEffectVerticalRise, VortexBuiltinEffectVerticalRise };
    VortexEffectParameters p = vortex_default_parameters();
    double positions[] = { 0, 1, 2, 3 };
    VortexNavState st;
    vortex_nav_reset(&st);
    double presented = 0.0, actual = 2.0;
    vortex_nav_step(&st, presented, positions, 4);
    for (int f = 0; f < 120; f++) {
        presented = vortex_smooth_step(presented, actual, 1.0 / 60.0, 0.5);
        VortexNavSnapshot snap = vortex_nav_step(&st, presented, positions, 4);
        double coverage = 0.0;
        for (int i = 0; i < 4; i++) {
            Seen seen = seen_for(vortex_compose_page(&snap, positions[i], presented, actual, builtin_effect, &pair, &p),
                                 positions[i], actual);
            if (seen_visible(seen)) coverage += (1.0 - fabs(seen.x)) * (1.0 - fabs(seen.y));
        }
        CHECK(coverage < 1.0 + 1e-6, "frame %d: pages overlap (coverage %.3f)", f, coverage);
    }
    CHECK(presented == actual, "presentation converged");
}

static void test_sanitize(void) {
    VortexEffectParameters p = { NAN, 99, (VortexEasing)42, 7, -3 };
    p = vortex_sanitize_parameters(p);
    CHECK(p.intensity == 0.1 && p.speed == 4.0 && p.easing == VortexEasingLinear && p.fadePages == 1 && p.reverse == 1,
          "sanitize clamps");
}

int main(void) {
    test_easing();
    test_speed_warp();
    test_directions();
    test_builtin_table();
    test_endpoint_invariants();
    test_stock_is_noop();
    test_reverse_slide_mirror();
    test_vertical_rise_geometry();
    test_navigation_state();
    test_continuity_sweep();
    test_exactly_one_page_fully_visible_when_settled();
    test_smoothing();
    test_smoothed_pipeline_never_shows_two_pages_stacked();
    test_sanitize();
    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures ? 1 : 0;
}
