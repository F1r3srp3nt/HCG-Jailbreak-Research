//
//  test_core.c
//  HCG Halo — host unit tests for the pure C core (geometry, config, profiles).
//
//  make -C tests test      (ASan + UBSan; no iOS SDK needed)
//

#include "../src/HaloConfig.h"
#include "../src/HaloGeometry.h"
#include "../src/HaloProfiles.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static long gChecks = 0, gFailures = 0;

#define CHECK(cond, ...)                                                    \
    do {                                                                    \
        gChecks++;                                                          \
        if (!(cond)) {                                                      \
            gFailures++;                                                    \
            if (gFailures <= 40) {                                          \
                fprintf(stderr, "FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond); \
                fprintf(stderr, __VA_ARGS__);                               \
                fprintf(stderr, "\n");                                      \
            }                                                               \
        }                                                                   \
    } while (0)

#define NEAR(a, b, tol) (fabs((a) - (b)) <= (tol))

static HaloDisplayGeometry geometry11ProMax(void) {
    HaloDisplayGeometry g = {414, 896, 39, HaloCutoutNotch, 209, 30, 6, 20, 0};
    return g;
}

/// Continuity, closure, finiteness, inside-the-display and clockwise checks.
static void check_path_invariants(const HaloBorderPath *p, const HaloDisplayGeometry *g, double d, const char *label) {
    CHECK(p->count > 0 && p->length > 0, "%s: empty path", label);
    if (p->count == 0) return;
    double sum = 0;
    for (int i = 0; i < p->count; i++) {
        const HaloSegment *s = &p->segments[i];
        const HaloSegment *prev = &p->segments[(i + p->count - 1) % p->count];
        CHECK(isfinite(s->x0) && isfinite(s->y0) && isfinite(s->x1) && isfinite(s->y1) && isfinite(s->length),
              "%s: non-finite segment %d", label, i);
        CHECK(NEAR(s->x0, prev->x1, 1e-6) && NEAR(s->y0, prev->y1, 1e-6),
              "%s: gap before segment %d: (%.6f,%.6f) vs (%.6f,%.6f)", label, i, s->x0, s->y0, prev->x1, prev->y1);
        CHECK(s->length > 0, "%s: segment %d has length %.9f", label, i, s->length);
        if (s->kind == HaloSegmentArc) {
            CHECK(NEAR(s->length, s->radius * fabs(s->endAngle - s->startAngle), 1e-9), "%s: arc %d length", label, i);
            CHECK(fabs(s->endAngle - s->startAngle) < 2 * M_PI, "%s: arc %d sweep", label, i);
        }
        sum += s->length;
    }
    CHECK(NEAR(sum, p->length, 1e-6), "%s: length %.6f != sum %.6f", label, p->length, sum);

    // Sample the loop: inside the display, and clockwise on screen (positive
    // shoelace area in y-down coordinates).
    const int samples = 2000;
    double area = 0, px = 0, py = 0, fx = 0, fy = 0;
    for (int i = 0; i <= samples; i++) {
        double x, y;
        halo_point_at(p, p->length * i / samples, &x, &y);
        CHECK(x >= d - 1e-6 && x <= g->width - d + 1e-6 && y >= d - 1e-6 && y <= g->height - d + 1e-6,
              "%s: sample %d (%.3f,%.3f) outside the inset rectangle", label, i, x, y);
        if (i == 0) {
            fx = x;
            fy = y;
        } else {
            area += px * y - x * py;
        }
        px = x;
        py = y;
    }
    area += px * fy - fx * py;
    CHECK(area > 0, "%s: path is not clockwise on screen (area %.3f)", label, area);

    double last = -1;
    for (int i = 0; i < p->landmarkCount; i++) {
        CHECK(p->landmarks[i] >= 0 && p->landmarks[i] <= p->length + 1e-9, "%s: landmark %d out of range", label, i);
        CHECK(p->landmarks[i] > last, "%s: landmarks not increasing at %d", label, i);
        last = p->landmarks[i];
    }

    // Bézier conversion: chained, closed, and curves stay on the true arcs.
    HaloBezierOp ops[256];
    int n = halo_border_to_beziers(p, ops, 256);
    CHECK(n > 2, "%s: bezier conversion failed (%d)", label, n);
    if (n > 2) {
        CHECK(ops[0].kind == HaloBezierMove && ops[n - 1].kind == HaloBezierClose, "%s: bezier framing", label);
        CHECK(NEAR(ops[n - 2].x, ops[0].x, 1e-6) && NEAR(ops[n - 2].y, ops[0].y, 1e-6), "%s: bezier not closed", label);
        double cx = ops[0].x, cy = ops[0].y;
        for (int i = 1; i < n - 1; i++) {
            if (ops[i].kind == HaloBezierCurve) {
                // find the arc this piece belongs to (by end point lying on a circle)
                double t = 0.5, mt = 1 - t;
                double bx = mt * mt * mt * cx + 3 * mt * mt * t * ops[i].c1x + 3 * mt * t * t * ops[i].c2x + t * t * t * ops[i].x;
                double by = mt * mt * mt * cy + 3 * mt * mt * t * ops[i].c1y + 3 * mt * t * t * ops[i].c2y + t * t * t * ops[i].y;
                double best = 1e9;
                for (int k = 0; k < p->count; k++) {
                    if (p->segments[k].kind != HaloSegmentArc) continue;
                    double e = fabs(hypot(bx - p->segments[k].cx, by - p->segments[k].cy) - p->segments[k].radius);
                    if (e < best) best = e;
                }
                CHECK(best < 0.01, "%s: bezier midpoint %.4f pt off its arc", label, best);
            }
            cx = ops[i].x;
            cy = ops[i].y;
        }
    }
    CHECK(halo_border_to_beziers(p, ops, 2) == -1, "%s: capacity not enforced", label);
}

static void test_geometry_no_cutout(void) {
    HaloDisplayGeometry g = geometry11ProMax();
    g.cutout = HaloCutoutNone;
    for (double d = 0; d <= 26; d += 0.5) {
        HaloBorderPath p;
        CHECK(halo_build_border(&g, d, 1, &p) == 1, "build failed at d=%.1f", d);
        double Rc = fmax(39, d), rc = Rc - d;
        double expected = 2 * (414 - 2 * Rc) + 2 * (896 - 2 * Rc) + 2 * M_PI * rc;
        CHECK(NEAR(p.length, expected, 1e-6), "no-cutout length %.6f expected %.6f (d=%.1f)", p.length, expected, d);
        CHECK(!p.tracesCutout, "no cutout must not trace");
        double x, y;
        halo_point_at(&p, 0, &x, &y);
        CHECK(NEAR(x, 207, 1e-9) && NEAR(y, d, 1e-9), "start (%.3f,%.3f)", x, y);
        CHECK(p.landmarkCount == 7, "landmarks %d", p.landmarkCount);
        check_path_invariants(&p, &g, d, "no-cutout");
    }
}

static void test_geometry_notch(void) {
    HaloDisplayGeometry g = geometry11ProMax();
    const double W = 414, w = 209, h = 30, ro = 6, ri = 20;
    for (double d = 0; d <= 10; d += 0.25) { // standard case: straight notch sides remain
        HaloBorderPath p;
        CHECK(halo_build_border(&g, d, 1, &p) == 1, "notch build failed d=%.2f", d);
        CHECK(p.tracesCutout, "should trace at d=%.2f", d);
        double Rc = fmax(39, d), rc = Rc - d, F = fmax(ro, d), rf = F - d;
        double straight = 2 * (W - 2 * Rc) + 2 * (896 - 2 * Rc) + 2 * M_PI * rc;
        double expected = straight - (w + 2 * F) + 2 * (M_PI / 2) * rf + 2 * (h - ri - F) +
                          2 * (M_PI / 2) * (ri + d) + (w - 2 * ri);
        CHECK(NEAR(p.length, expected, 1e-6), "notch length %.6f expected %.6f (d=%.2f)", p.length, expected, d);
        double x, y;
        halo_point_at(&p, 0, &x, &y);
        CHECK(NEAR(x, 207, 1e-9) && NEAR(y, h + d, 1e-9), "notch start (%.3f,%.3f) d=%.2f", x, y, d);
        check_path_invariants(&p, &g, d, "notch");
    }
    for (double d = 10.5; d <= 26; d += 0.5) { // inset deeper than the straight sides
        HaloBorderPath p;
        CHECK(halo_build_border(&g, d, 1, &p) == 1, "deep build failed d=%.2f", d);
        CHECK(p.tracesCutout, "should still trace at d=%.2f", d);
        double x, y;
        halo_point_at(&p, 0, &x, &y);
        CHECK(NEAR(y, h + d, 1e-9), "deep notch bottom y=%.3f d=%.2f", y, d);
        check_path_invariants(&p, &g, d, "notch-deep");
    }
    // Straight mode with a notch present: identical to no cutout.
    HaloBorderPath a, b;
    HaloDisplayGeometry none = g;
    none.cutout = HaloCutoutNone;
    halo_build_border(&g, 2, 0, &a);
    halo_build_border(&none, 2, 1, &b);
    CHECK(NEAR(a.length, b.length, 1e-9) && !a.tracesCutout, "straight mode differs from no-cutout");

    // Notch offset moves the dip.
    HaloDisplayGeometry shifted = g;
    shifted.notchOffsetX = 10;
    HaloBorderPath s;
    CHECK(halo_build_border(&shifted, 1.5, 1, &s), "shifted build");
    double x, y;
    halo_point_at(&s, 0, &x, &y);
    CHECK(NEAR(x, 217, 1e-9), "shifted notch start x=%.3f", x);
    check_path_invariants(&s, &shifted, 1.5, "notch-shifted");
}

static void test_geometry_sanitize(void) {
    HaloDisplayGeometry bad = {((double)NAN), 896, 39, HaloCutoutNotch, 209, 30, 6, 20, 0};
    HaloBorderPath p;
    CHECK(halo_build_border(&bad, 1, 1, &p) == 0 && p.count == 0, "NaN width must fail");
    HaloDisplayGeometry tiny = {5, 5, 1, HaloCutoutNone, 0, 0, 0, 0, 0};
    CHECK(halo_build_border(&tiny, 1, 1, &p) == 0, "tiny display must fail");

    HaloDisplayGeometry g = geometry11ProMax();
    g.notchWidth = 1e6;
    g.notchOuterRadius = ((double)INFINITY);
    g.notchInnerRadius = -5;
    g.notchOffsetX = 500;
    g.cornerRadius = 1e6;
    HaloDisplayGeometry s = halo_sanitize_geometry(g);
    CHECK(isfinite(s.notchOuterRadius) && s.notchInnerRadius >= 0, "radii sanitised");
    CHECK(s.cornerRadius <= 414 / 2.0 - 1, "corner radius clamped %.3f", s.cornerRadius);
    CHECK(s.cutout == HaloCutoutNone || s.notchWidth + 2 * s.notchOuterRadius <= 414 - 2 * s.cornerRadius,
          "notch fits");
    CHECK(halo_build_border(&g, 1, 1, &p) == 1, "absurd geometry still builds");
    check_path_invariants(&p, &s, 1, "sanitised");

    HaloDisplayGeometry radii = geometry11ProMax();
    radii.notchOuterRadius = 25;
    radii.notchInnerRadius = 25;
    s = halo_sanitize_geometry(radii);
    CHECK(s.notchOuterRadius + s.notchInnerRadius <= s.notchHeight + 1e-9, "radii scaled to depth");

    HaloDisplayGeometry ng = geometry11ProMax();
    CHECK(halo_build_border(&ng, -10, 1, &p) == 1, "negative offset clamps");
    check_path_invariants(&p, &ng, 0, "negative-offset");
    CHECK(halo_build_border(&ng, ((double)NAN), 1, &p) == 1, "NaN offset clamps");
    CHECK(halo_build_border(&ng, 1e9, 1, &p) == 1, "huge offset clamps");
}

static unsigned long gSeed = 0x48414C4FUL; // "HALO"
static double rnd(double lo, double hi) {
    gSeed = gSeed * 6364136223846793005UL + 1442695040888963407UL;
    return lo + (hi - lo) * ((gSeed >> 11) / 9007199254740992.0);
}

static void test_geometry_fuzz(void) {
    for (int i = 0; i < 4000; i++) {
        HaloDisplayGeometry g = {rnd(300, 450), rnd(600, 960), rnd(0, 60), rnd(0, 1) < 0.7 ? HaloCutoutNotch : HaloCutoutNone,
                                 rnd(80, 260), rnd(15, 40), rnd(0, 12), rnd(0, 30), rnd(-30, 30)};
        double d = rnd(0, 30);
        int trace = rnd(0, 1) < 0.8;
        HaloBorderPath p;
        int ok = halo_build_border(&g, d, trace, &p);
        CHECK(ok, "fuzz %d failed", i);
        if (!ok) continue;
        HaloDisplayGeometry s = halo_sanitize_geometry(g);
        double dd = fmin(d, halo_max_offset(&s));
        char label[32];
        snprintf(label, sizeof label, "fuzz-%d", i);
        long before = gFailures;
        check_path_invariants(&p, &s, dd, label);
        if (gFailures != before) {
            fprintf(stderr, "  geometry: %.2f x %.2f R=%.2f cut=%d w=%.2f h=%.2f ro=%.2f ri=%.2f off=%.2f d=%.2f trace=%d\n",
                    g.width, g.height, g.cornerRadius, g.cutout, g.notchWidth, g.notchHeight, g.notchOuterRadius,
                    g.notchInnerRadius, g.notchOffsetX, d, trace);
            break;
        }
    }
}

static void test_point_at(void) {
    HaloDisplayGeometry g = geometry11ProMax();
    HaloBorderPath p;
    halo_build_border(&g, 1.5, 1, &p);
    double x0, y0, x1, y1;
    halo_point_at(&p, 0, &x0, &y0);
    halo_point_at(&p, p.length, &x1, &y1);
    CHECK(NEAR(x0, x1, 1e-9) && NEAR(y0, y1, 1e-9), "point_at wraps");
    halo_point_at(&p, -p.length / 4, &x1, &y1);
    double x2, y2;
    halo_point_at(&p, p.length * 3 / 4, &x2, &y2);
    CHECK(NEAR(x1, x2, 1e-6) && NEAR(y1, y2, 1e-6), "negative arc length wraps");
    // Adjacent samples are close (no jumps).
    double px = x0, py = y0, worst = 0;
    for (int i = 1; i <= 10000; i++) {
        double x, y;
        halo_point_at(&p, p.length * i / 10000, &x, &y);
        double step = hypot(x - px, y - py);
        if (step > worst) worst = step;
        px = x;
        py = y;
    }
    CHECK(worst <= p.length / 10000 + 1e-6, "sampling jump %.6f", worst);
}

static void test_hex(void) {
    HaloRGB c;
    CHECK(halo_parse_hex("#00E5FF", &c) && NEAR(c.r, 0, 1e-12) && NEAR(c.g, 229 / 255.0, 1e-12) && NEAR(c.b, 1, 1e-12),
          "parse #00E5FF");
    CHECK(halo_parse_hex("7b61ff", &c), "parse lowercase without #");
    char out[8];
    halo_format_hex(c, out);
    CHECK(strcmp(out, "#7B61FF") == 0, "format %s", out);
    const char *bad[] = {NULL, "", "#", "#12345", "#1234567", "#GG0000", "zzzzzz", "#12 456"};
    for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++) CHECK(!halo_parse_hex(bad[i], &c), "accepted bad hex %u", i);
    HaloRGB weird = {((double)NAN), -1, 7};
    halo_format_hex(weird, out);
    CHECK(strcmp(out, "#0000FF") == 0, "format clamps: %s", out);
    for (int v = 0; v < 256; v++) {
        char hex[8], back[8];
        snprintf(hex, sizeof hex, "#%02X%02X%02X", v, 255 - v, (v * 7) & 255);
        CHECK(halo_parse_hex(hex, &c), "parse %s", hex);
        halo_format_hex(c, back);
        CHECK(strcmp(hex, back) == 0, "roundtrip %s -> %s", hex, back);
    }
}

static void test_identifiers(void) {
    for (int m = 0; m < HaloModeCount; m++) {
        HaloMode out;
        CHECK(halo_mode_from_id(halo_mode_id((HaloMode)m), &out) && out == (HaloMode)m, "mode roundtrip %d", m);
        CHECK(strlen(halo_mode_title((HaloMode)m)) > 0, "mode title %d", m);
    }
    for (int s = 0; s < HaloColourStyleCount; s++) {
        HaloColourStyle out;
        CHECK(halo_colour_style_from_id(halo_colour_style_id((HaloColourStyle)s), &out) && out == (HaloColourStyle)s,
              "style %d", s);
    }
    for (int s = 0; s < HaloLowPowerPolicyCount; s++) {
        HaloLowPowerPolicy out;
        CHECK(halo_low_power_from_id(halo_low_power_id((HaloLowPowerPolicy)s), &out) && out == (HaloLowPowerPolicy)s,
              "low power %d", s);
    }
    for (int s = 0; s < HaloCutoutModeCount; s++) {
        HaloCutoutMode out;
        CHECK(halo_cutout_mode_from_id(halo_cutout_mode_id((HaloCutoutMode)s), &out) && out == (HaloCutoutMode)s,
              "cutout %d", s);
    }
    HaloMode m = HaloModeOrbit;
    CHECK(!halo_mode_from_id("rainbow", &m) && m == HaloModeOrbit, "unknown mode leaves output unchanged");
    CHECK(!halo_mode_from_id(NULL, &m), "NULL mode id");
}

static void test_appearance(void) {
    HaloAppearance d = halo_default_appearance();
    CHECK(d.mode == HaloModeStatic, "default mode static");
    HaloAppearance s = halo_sanitize_appearance(d);
    CHECK(memcmp(&s, &d, sizeof s) == 0, "defaults are already sane");

    HaloAppearance a = d;
    a.mode = (HaloMode)99;
    a.colourStyle = (HaloColourStyle)-3;
    a.colourCount = 0;
    a.brightness = ((double)NAN);
    a.thickness = 100;
    a.glow = -1;
    a.inset = ((double)INFINITY);
    a.speed = 0;
    a.clockwise = 42;
    a.colourRepeat = 9;
    a.segments = -2;
    a.segmentLength = 2;
    a.pulseDepth = ((double)NAN);
    s = halo_sanitize_appearance(a);
    CHECK(s.mode == d.mode && s.colourStyle == d.colourStyle && s.colourCount == d.colourCount, "enums reset");
    CHECK(s.brightness == d.brightness && s.thickness == HALO_THICKNESS_MAX && s.glow == HALO_GLOW_MIN, "clamps 1");
    CHECK(s.inset == d.inset && s.speed == HALO_SPEED_MIN && s.clockwise == 1, "clamps 2");
    CHECK(s.colourRepeat == HALO_REPEAT_MAX && s.segments == HALO_SEGMENTS_MIN &&
              s.segmentLength == HALO_SEGMENT_LENGTH_MAX, "clamps 3");
    CHECK(s.pulseDepth == 0, "NaN pulse -> default 0");
    a = d;
    a.pulseDepth = 5;
    CHECK(halo_sanitize_appearance(a).pulseDepth == HALO_PULSE_MAX, "pulse clamped to max");
    a.pulseDepth = -1;
    CHECK(halo_sanitize_appearance(a).pulseDepth == HALO_PULSE_MIN, "pulse clamped to min");

    a = d;
    a.colours[1].r = 7;
    a.colours[2].g = ((double)NAN);
    s = halo_sanitize_appearance(a);
    CHECK(s.colours[1].r == 1 && s.colours[2].g == 0, "colour channels clamped");
}

static void test_gradient(void) {
    HaloAppearance a = halo_default_appearance();
    HaloStop stops[HALO_MAX_STOPS];
    for (int style = 0; style < HaloColourStyleCount; style++) {
        for (int n = 1; n <= HALO_MAX_COLOURS; n++) {
            for (int rep = HALO_REPEAT_MIN; rep <= HALO_REPEAT_MAX; rep++) {
                a.colourStyle = (HaloColourStyle)style;
                a.colourCount = n;
                for (int i = 0; i < n; i++) {
                    a.colours[i].r = i / 6.0;
                    a.colours[i].g = 1 - i / 6.0;
                    a.colours[i].b = 0.5;
                }
                a.colourRepeat = rep;
                int count = halo_gradient_stops(&a, stops, HALO_MAX_STOPS);
                CHECK(count >= 2, "stops style=%d n=%d rep=%d", style, n, rep);
                CHECK(stops[0].location == 0 && stops[count - 1].location == 1, "stops span 0..1");
                for (int i = 1; i < count; i++)
                    CHECK(stops[i].location >= stops[i - 1].location, "stops increasing (style=%d n=%d)", style, n);
                CHECK(memcmp(&stops[0].colour, &stops[count - 1].colour, sizeof(HaloRGB)) == 0,
                      "closed loop style=%d n=%d rep=%d", style, n, rep);
                if (style == HaloColourSingle || n == 1) CHECK(count == 2, "single colour has 2 stops");
                if (style == HaloColourGradient && n > 1) CHECK(count == n * rep + 1, "gradient count");
                if (style == HaloColourMulti && n > 1) CHECK(count == 2 * n * rep + 2, "multi count");
            }
        }
    }
    a.colourStyle = HaloColourMulti;
    a.colourCount = 6;
    a.colourRepeat = 4;
    CHECK(halo_gradient_stops(&a, stops, 10) == 0, "capacity enforced");
}

static void test_patterns(void) {
    for (double P = 100; P < 6000; P += 37.3) {
        for (int seg = 1; seg <= 4; seg++) {
            double dash, gap;
            halo_orbit_dash(P, seg, 0.2, &dash, &gap);
            CHECK(NEAR((dash + gap) * seg, P, 1e-9) && dash > 0 && gap > 0, "orbit P=%.1f seg=%d", P, seg);
        }
        for (double t = 1; t <= 12; t += 1) {
            double pat[16], unit;
            int n = halo_circuit_pattern(P, t, pat, 16, &unit);
            CHECK(n > 0 && n % 2 == 0, "circuit entries %d", n);
            double sum = 0;
            for (int i = 0; i < n; i++) {
                CHECK(pat[i] > 0, "circuit entry positive");
                sum += pat[i];
            }
            CHECK(NEAR(sum, unit, 1e-9), "unit length");
            double reps = P / unit;
            CHECK(NEAR(reps, floor(reps + 0.5), 1e-6), "circuit fits perimeter: P=%.1f t=%.0f reps=%.6f", P, t, reps);
        }
    }
    double pat[4], unit;
    CHECK(halo_circuit_pattern(1000, 3, pat, 4, &unit) == 0, "circuit capacity");
    CHECK(halo_circuit_pattern(0, 3, pat, 16, &unit) == 0 && unit == 0, "circuit zero perimeter");
    for (int m = 0; m < HaloModeCount; m++) {
        CHECK(halo_period((HaloMode)m, 1) > 0, "period > 0");
        CHECK(NEAR(halo_period((HaloMode)m, 2), halo_period((HaloMode)m, 1) / 2, 1e-12), "period scales with speed");
        CHECK(halo_period((HaloMode)m, ((double)NAN)) > 0 && halo_period((HaloMode)m, 1000) > 0, "period sanitises speed");
    }
}

static void test_render_plan(void) {
    for (int m = 0; m < HaloModeCount; m++) {
        HaloRenderPlan p = halo_render_plan((HaloMode)m, 0, 0, HaloLowPowerStatic);
        CHECK(p.mode == (HaloMode)m && !p.hidden && p.animated == (m != HaloModeStatic) && p.reason[0] == 0,
              "plain plan %d", m);
        p = halo_render_plan((HaloMode)m, 1, 0, HaloLowPowerAnimate);
        CHECK(p.mode == HaloModeStatic && !p.animated && !p.hidden, "reduce motion -> static (%d)", m);
        CHECK(m == HaloModeStatic ? p.reason[0] == 0 : strstr(p.reason, "Reduce Motion") != NULL, "reason rm");
        p = halo_render_plan((HaloMode)m, 0, 1, HaloLowPowerStatic);
        CHECK(p.mode == HaloModeStatic && !p.animated && !p.hidden, "low power static (%d)", m);
        p = halo_render_plan((HaloMode)m, 0, 1, HaloLowPowerAnimate);
        CHECK(p.mode == (HaloMode)m && !p.hidden, "low power animate (%d)", m);
        p = halo_render_plan((HaloMode)m, 1, 1, HaloLowPowerHide);
        CHECK(p.hidden && !p.animated, "low power hide (%d)", m);
        p = halo_render_plan((HaloMode)m, 0, 0, HaloLowPowerHide);
        CHECK(!p.hidden, "hide policy only applies in Low Power Mode (%d)", m);
    }
    HaloRenderPlan p = halo_render_plan((HaloMode)77, 0, 0, HaloLowPowerStatic);
    CHECK(p.mode == HaloModeStatic, "invalid mode -> static");
}

static void test_visibility(void) {
    HaloVisibilityInputs v = {1, 1, 1, 1, 1, 1};
    CHECK(halo_visibility_block(&v) == NULL, "all visible");
    int *fields[] = {&v.enabled, &v.attached, &v.screenOn, &v.unlocked, &v.homeInFront, &v.hostVisible};
    for (int i = 0; i < 6; i++) {
        *fields[i] = 0;
        CHECK(halo_visibility_block(&v) != NULL, "field %d blocks", i);
        *fields[i] = 1;
    }
    v.screenOn = 0;
    CHECK(strcmp(halo_visibility_block(&v), "screen off") == 0, "screen off reason");
}

static void test_profiles(void) {
    CHECK(halo_profile_count() > 1, "profiles present");
    const HaloProfile *def = halo_profile_find(halo_default_profile_id());
    CHECK(def && def->implemented, "default profile implemented");
    CHECK(def && strcmp(def->identifier, "iphone-11-pro-max") == 0, "default is iPhone 11 Pro Max");
    CHECK(halo_profile_find(HALO_PROFILE_AUTOMATIC) == NULL, "automatic is never a profile");
    CHECK(halo_profile_find("nope") == NULL && halo_profile_find(NULL) == NULL, "unknown profile");
    CHECK(halo_profile_at(-1) == NULL && halo_profile_at(halo_profile_count()) == NULL, "index bounds");
    int implemented = 0;
    for (int i = 0; i < halo_profile_count(); i++) {
        const HaloProfile *p = halo_profile_at(i);
        CHECK(!p->deviceTested, "no profile may be marked device-tested in this beta (%s)", p->identifier);
        if (!p->implemented) {
            HaloCalibration zero = {0, 0, 0, 0};
            HaloDisplayGeometry g = halo_profile_geometry(p, zero);
            HaloBorderPath path;
            CHECK(halo_build_border(&g, 1, 1, &path) == 0, "planned profile %s must not render", p->identifier);
            continue;
        }
        implemented++;
        CHECK(strlen(p->sources) > 0, "implemented profile %s documents its sources", p->identifier);
        CHECK(halo_profile_matches_screen(p, p->screenWidth, p->screenHeight) &&
                  halo_profile_matches_screen(p, p->screenHeight, p->screenWidth), "matches own screen");
        CHECK(!halo_profile_matches_screen(p, 375, 812), "does not match another screen");
    }
    CHECK(implemented == 1, "exactly one implemented profile in 0.1.0~beta1 (%d)", implemented);

    HaloCalibration cal = {100, -100, ((double)NAN), 3};
    HaloCalibration c = halo_sanitize_calibration(cal);
    CHECK(c.cornerRadius == HALO_CAL_CORNER_MAX && c.notchWidth == HALO_CAL_NOTCH_WIDTH_MIN && c.notchHeight == 0 &&
              c.notchOffsetX == 3, "calibration clamps");
    HaloCalibration zero = {0, 0, 0, 0};
    HaloDisplayGeometry g = halo_profile_geometry(def, zero);
    CHECK(g.width == 414 && g.height == 896 && g.cornerRadius == 39 && g.cutout == HaloCutoutNotch, "profile geometry");
    HaloCalibration adj = {-4, 10, 2, -5};
    HaloDisplayGeometry ga = halo_profile_geometry(def, adj);
    CHECK(NEAR(ga.cornerRadius, 35, 1e-9) && NEAR(ga.notchWidth, 219, 1e-9) && NEAR(ga.notchHeight, 32, 1e-9) &&
              NEAR(ga.notchOffsetX, -5, 1e-9), "calibration applied");
    // Every calibration extreme still renders.
    double corners[] = {HALO_CAL_CORNER_MIN, 0, HALO_CAL_CORNER_MAX};
    double widths[] = {HALO_CAL_NOTCH_WIDTH_MIN, 0, HALO_CAL_NOTCH_WIDTH_MAX};
    double heights[] = {HALO_CAL_NOTCH_HEIGHT_MIN, 0, HALO_CAL_NOTCH_HEIGHT_MAX};
    double offsets[] = {HALO_CAL_NOTCH_OFFSET_MIN, 0, HALO_CAL_NOTCH_OFFSET_MAX};
    for (int a = 0; a < 3; a++)
        for (int b = 0; b < 3; b++)
            for (int h = 0; h < 3; h++)
                for (int o = 0; o < 3; o++)
                    for (double d = 0; d <= 26; d += 6.5) {
                        HaloCalibration k = {corners[a], widths[b], heights[h], offsets[o]};
                        HaloDisplayGeometry kg = halo_profile_geometry(def, k);
                        HaloBorderPath path;
                        CHECK(halo_build_border(&kg, d, 1, &path) == 1, "calibration extreme %d%d%d%d d=%.1f", a, b, h, o, d);
                        check_path_invariants(&path, &kg, d, "calibrated");
                    }
}

static void test_show_on(void) {
    const char *ids[] = {"home", "app", "always", "exceptLock", "exceptScreenOff"};
    for (int i = 0; i < HaloShowOnCount; i++) {
        HaloShowOn v = HaloShowOnCount;
        CHECK(halo_show_on_from_id(ids[i], &v) && v == (HaloShowOn)i, "show-on id %s", ids[i]);
        CHECK(strcmp(halo_show_on_id((HaloShowOn)i), ids[i]) == 0, "show-on round trip %d", i);
        CHECK(halo_show_on_title((HaloShowOn)i)[0], "show-on title %d", i);
    }
    HaloShowOn v = HaloShowOnApp;
    CHECK(!halo_show_on_from_id("lockscreen", &v) && v == HaloShowOnApp, "unknown show-on id rejected");
    CHECK(!halo_show_on_from_id(NULL, &v), "NULL show-on id rejected");
    CHECK(strcmp(halo_show_on_id((HaloShowOn)99), "home") == 0, "invalid show-on -> home");
    CHECK(!halo_show_on_uses_overlay_window(HaloShowOnHome), "home uses the Home Screen window");
    CHECK(halo_show_on_uses_overlay_window(HaloShowOnApp) && halo_show_on_uses_overlay_window(HaloShowOnAlways) &&
              halo_show_on_uses_overlay_window(HaloShowOnExceptLock) &&
              halo_show_on_uses_overlay_window(HaloShowOnExceptScreenOff),
          "other policies use the overlay window");
    CHECK(halo_show_on_includes_lock_screen(HaloShowOnAlways) && halo_show_on_includes_lock_screen(HaloShowOnExceptScreenOff) &&
              !halo_show_on_includes_lock_screen(HaloShowOnExceptLock) && !halo_show_on_includes_lock_screen(HaloShowOnHome) &&
              !halo_show_on_includes_lock_screen(HaloShowOnApp),
          "lock screen inclusion");

    // Every combination of the surface inputs, against the specification.
    for (int policy = 0; policy < HaloShowOnCount; policy++)
        for (int bits = 0; bits < (1 << 9); bits++) {
            HaloSurfaceInputs in;
            memset(&in, 0, sizeof in);
            in.showOn = (HaloShowOn)policy;
            in.base.enabled = bits & 1;
            in.base.attached = (bits >> 1) & 1;
            in.base.screenOn = (bits >> 2) & 1;
            in.base.unlocked = (bits >> 3) & 1;
            in.base.homeInFront = (bits >> 4) & 1;
            in.base.hostVisible = (bits >> 5) & 1;
            in.appChosen = (bits >> 6) & 1;
            in.frontAppKnown = (bits >> 7) & 1;
            in.chosenAppInFront = (bits >> 8) & 1;
            int ready = in.base.enabled && in.base.attached && in.base.screenOn && in.base.hostVisible;
            int expect;
            switch (policy) {
            case HaloShowOnHome: expect = ready && in.base.unlocked && in.base.homeInFront; break;
            case HaloShowOnApp:
                expect = ready && in.base.unlocked && in.appChosen && in.frontAppKnown && in.chosenAppInFront;
                break;
            case HaloShowOnExceptLock: expect = ready && in.base.unlocked; break;
            default: expect = ready; break; // Always, Always Except When Screen Is Off
            }
            const char *block = halo_surface_block(&in);
            CHECK((block == NULL) == expect, "policy %d bits %03x: expected %s, got %s", policy, bits,
                  expect ? "draw" : "hidden", block ? block : "draw");
            if (in.base.enabled && in.base.attached && !in.base.screenOn)
                CHECK(block && strcmp(block, "screen off") == 0, "policy %d: screen off always hides (%03x)", policy, bits);
            if (policy == HaloShowOnHome) {
                const char *legacy = halo_visibility_block(&in.base);
                CHECK((legacy == NULL) == (block == NULL), "home policy == 0.2.0 rules (%03x)", bits);
            }
        }
    // Always and Always Except When Screen Is Off are the same decision.
    HaloSurfaceInputs lit;
    memset(&lit, 0, sizeof lit);
    lit.base = (HaloVisibilityInputs){1, 1, 1, 0, 0, 1}; // lit Lock Screen
    lit.showOn = HaloShowOnAlways;
    CHECK(halo_surface_block(&lit) == NULL, "Always draws on the lit Lock Screen");
    lit.showOn = HaloShowOnExceptScreenOff;
    CHECK(halo_surface_block(&lit) == NULL, "Except Screen Off draws on the lit Lock Screen");
    lit.showOn = HaloShowOnExceptLock;
    CHECK(halo_surface_block(&lit) && strcmp(halo_surface_block(&lit), "locked") == 0, "Except Lock hides when locked");
    lit.showOn = (HaloShowOn)42;
    CHECK(halo_surface_block(&lit) != NULL, "invalid policy behaves as Home Screen Only");
}

static void test_screen_fit(void) {
    const HaloProfile *max = halo_profile_find("iphone-11-pro-max");
    HaloCalibration zero = {0, 0, 0, 0};
    double k = 0;
    HaloScreenMeasure standard = {414, 896, 1242, 2688};
    CHECK(halo_profile_fit(max, standard, &k) == HaloScreenFitMatch && k == 1, "standard 11 Pro Max matches");
    HaloScreenMeasure landscape = {896, 414, 2688, 1242};
    CHECK(halo_profile_fit(max, landscape, &k) == HaloScreenFitMatch, "orientation does not matter");
    HaloScreenMeasure unknownPixels = {414, 896, 0, 0};
    CHECK(halo_profile_fit(max, unknownPixels, &k) == HaloScreenFitMatch, "points alone suffice for a match");

    // iPhone 11 Pro Max with Display Zoom (Larger Text): 375 x 812 pt on the 1242 x 2688 px panel.
    HaloScreenMeasure zoomed = {375, 812, 1242, 2688};
    CHECK(halo_profile_fit(max, zoomed, &k) == HaloScreenFitDisplayZoom, "Display Zoom detected");
    CHECK(NEAR(k, 375.0 / 414.0, 1e-9), "zoom factor %.6f", k);
    HaloScreenFit fit = HaloScreenFitUnknown;
    HaloDisplayGeometry z = halo_profile_geometry_for_screen(max, zero, zoomed, &fit, &k);
    CHECK(fit == HaloScreenFitDisplayZoom, "geometry fit zoom");
    CHECK(z.width == 375 && z.height == 812, "zoomed frame %.1f x %.1f", z.width, z.height);
    CHECK(NEAR(z.cornerRadius, 39 * 375.0 / 414.0, 1e-6), "zoomed corner %.3f", z.cornerRadius);
    CHECK(NEAR(z.notchWidth, 209 * 375.0 / 414.0, 1e-6), "zoomed notch width %.3f", z.notchWidth);
    CHECK(NEAR(z.notchHeight, 30 * 375.0 / 414.0, 1e-6), "zoomed notch depth %.3f", z.notchHeight);
    // Physically the same: corner radius and notch width as a fraction of the screen width are unchanged.
    CHECK(NEAR(z.cornerRadius / z.width, 39.0 / 414.0, 1e-9) && NEAR(z.notchWidth / z.width, 209.0 / 414.0, 1e-9),
          "zoomed geometry is the same physical outline");
    HaloBorderPath zp;
    CHECK(halo_build_border(&z, 1.5, 1, &zp) == 1, "zoomed path builds");
    check_path_invariants(&zp, &z, 1.5, "zoomed");
    // Calibration deltas are screen points, added after scaling.
    HaloCalibration cal = {2, -4, 1, 3};
    HaloDisplayGeometry zc = halo_profile_geometry_for_screen(max, cal, zoomed, NULL, NULL);
    CHECK(NEAR(zc.cornerRadius, z.cornerRadius + 2, 1e-6) && NEAR(zc.notchWidth, z.notchWidth - 4, 1e-6) &&
              NEAR(zc.notchHeight, z.notchHeight + 1, 1e-6) && NEAR(zc.notchOffsetX, 3, 1e-6),
          "calibration after scaling");

    // The 0.2.0 code: real frame, unscaled corners and notch (what a 375 x 812 report used to draw).
    HaloDisplayGeometry old = halo_profile_geometry(max, zero);
    old.width = 375;
    old.height = 812;
    CHECK(NEAR(old.cornerRadius / old.width * 414.0, 43.06, 0.01), "0.2.0 drew the corner ~43 pt (standard pt)");

    // A real iPhone X / XS / 11 Pro (375 x 812 pt on 1125 x 2436 px): a different display.
    HaloScreenMeasure eleven = {375, 812, 1125, 2436};
    CHECK(halo_profile_fit(max, eleven, &k) == HaloScreenFitMismatch && k == 1, "11 Pro is a mismatch, not zoom");
    HaloDisplayGeometry m = halo_profile_geometry_for_screen(max, zero, eleven, &fit, &k);
    CHECK(fit == HaloScreenFitMismatch && m.width == 375 && m.height == 812 && m.cornerRadius == 39,
          "mismatch keeps the frame fitted and the profile lengths unscaled");
    HaloScreenMeasure noPixels = {375, 812, 0, 0};
    CHECK(halo_profile_fit(max, noPixels, &k) == HaloScreenFitMismatch, "unknown pixels cannot prove zoom");
    HaloScreenMeasure odd = {375, 700, 1242, 2688};
    CHECK(halo_profile_fit(max, odd, &k) == HaloScreenFitMismatch, "non-uniform shrink is not zoom");
    HaloScreenMeasure bad = {NAN, 812, 1242, 2688};
    CHECK(halo_profile_fit(max, bad, &k) == HaloScreenFitUnknown, "NaN screen -> unknown");
    CHECK(halo_profile_fit(NULL, zoomed, &k) == HaloScreenFitUnknown, "no profile -> unknown");
    CHECK(halo_profile_fit(halo_profile_find("iphone-11-pro"), zoomed, &k) == HaloScreenFitUnknown, "planned -> unknown");
    HaloDisplayGeometry same = halo_profile_geometry_for_screen(max, cal, standard, NULL, NULL);
    HaloDisplayGeometry ref = halo_profile_geometry(max, cal);
    CHECK(memcmp(&same, &ref, sizeof same) == 0, "standard screen: identical to halo_profile_geometry");
    CHECK(strcmp(halo_screen_fit_id(HaloScreenFitDisplayZoom), "displayZoom") == 0, "fit id");
}

int main(void) {
    test_geometry_no_cutout();
    test_geometry_notch();
    test_geometry_sanitize();
    test_geometry_fuzz();
    test_point_at();
    test_hex();
    test_identifiers();
    test_appearance();
    test_gradient();
    test_patterns();
    test_render_plan();
    test_visibility();
    test_profiles();
    test_show_on();
    test_screen_fit();
    if (gFailures) {
        printf("%ld of %ld checks FAILED\n", gFailures, gChecks);
        return 1;
    }
    printf("All %ld checks passed (geometry, config, patterns, profiles, show-on, screen fit)\n", gChecks);
    return 0;
}
