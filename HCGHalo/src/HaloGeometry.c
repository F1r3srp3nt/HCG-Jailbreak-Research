//
//  HaloGeometry.c
//  HCG Halo — Hakmi Capital Group
//
//  See HaloGeometry.h. Coordinates: fixed portrait space, origin top-left,
//  y down, points. Angles use atan2(dy, dx) in that space, so an increasing
//  angle turns clockwise on screen.
//
//  Offsetting rules (the centre line is `d` points inside the display edge):
//    * convex corner (screen corners, the notch's top flares) with boundary
//      radius ρ: centre max(ρ, d) from both edges, radius max(ρ, d) − d.
//      Radius 0 is a sharp corner, which the stroke's round join softens.
//    * concave corner (the notch's bottom corners) with radius ρ: same centre,
//      radius ρ + d.
//    * when the inset is deeper than the notch's straight sides, the top edge
//      meets the bottom-corner circle directly (intersection), which is the
//      exact offset of the outline.
//

#include "HaloGeometry.h"

#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static const double kEps = 1e-9;

static double clampd(double v, double lo, double hi) {
    if (!(v == v)) return lo; // NaN
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static double finite_or(double v, double fallback) {
    return isfinite(v) ? v : fallback;
}

HaloDisplayGeometry halo_sanitize_geometry(HaloDisplayGeometry g) {
    g.width = finite_or(g.width, 0);
    g.height = finite_or(g.height, 0);
    if (g.width < 10 || g.height < 10) {
        HaloDisplayGeometry empty;
        memset(&empty, 0, sizeof empty);
        return empty;
    }
    double shortSide = g.width < g.height ? g.width : g.height;
    g.cornerRadius = clampd(finite_or(g.cornerRadius, 0), 0, shortSide / 2 - 1);

    if (g.cutout != HaloCutoutNotch) {
        g.cutout = HaloCutoutNone;
        g.notchWidth = g.notchHeight = g.notchOuterRadius = g.notchInnerRadius = g.notchOffsetX = 0;
        return g;
    }

    double R = g.cornerRadius;
    g.notchHeight = clampd(finite_or(g.notchHeight, 0), 0, g.height / 4);
    g.notchOuterRadius = clampd(finite_or(g.notchOuterRadius, 0), 0, 30);
    g.notchInnerRadius = clampd(finite_or(g.notchInnerRadius, 0), 0, 60);
    // Room along the top edge between the two screen corners, keeping 2 pt of
    // straight edge on each side of the notch's flares.
    double room = g.width - 2 * R - 4;
    g.notchWidth = clampd(finite_or(g.notchWidth, 0), 0, room - 2 * g.notchOuterRadius);
    if (g.notchWidth < 1 || g.notchHeight < 1) {
        g.cutout = HaloCutoutNone;
        g.notchWidth = g.notchHeight = g.notchOuterRadius = g.notchInnerRadius = g.notchOffsetX = 0;
        return g;
    }
    // Bottom corners cannot be wider than half the notch.
    if (g.notchInnerRadius > g.notchWidth / 2) g.notchInnerRadius = g.notchWidth / 2;
    // Flare + bottom corner must fit in the notch's depth.
    double radii = g.notchOuterRadius + g.notchInnerRadius;
    if (radii > g.notchHeight && radii > 0) {
        double k = g.notchHeight / radii;
        g.notchOuterRadius *= k;
        g.notchInnerRadius *= k;
    }
    double slack = (room - 2 * g.notchOuterRadius - g.notchWidth) / 2;
    if (slack < 0) slack = 0;
    g.notchOffsetX = clampd(finite_or(g.notchOffsetX, 0), -slack, slack);
    return g;
}

double halo_max_offset(const HaloDisplayGeometry *g) {
    double shortSide = g->width < g->height ? g->width : g->height;
    double m = shortSide / 2 - 5;
    return m > 0 ? m : 0;
}

// MARK: - Builder

static void add_line(HaloBorderPath *p, double x0, double y0, double x1, double y1) {
    double len = hypot(x1 - x0, y1 - y0);
    if (len < kEps || p->count >= HALO_MAX_SEGMENTS) return;
    HaloSegment *s = &p->segments[p->count++];
    memset(s, 0, sizeof *s);
    s->kind = HaloSegmentLine;
    s->x0 = x0; s->y0 = y0; s->x1 = x1; s->y1 = y1;
    s->length = len;
    p->length += len;
}

static void add_arc(HaloBorderPath *p, double cx, double cy, double r, double a0, double a1) {
    double sweep = a1 - a0;
    if (r < kEps || fabs(sweep) < kEps || p->count >= HALO_MAX_SEGMENTS) return;
    HaloSegment *s = &p->segments[p->count++];
    memset(s, 0, sizeof *s);
    s->kind = HaloSegmentArc;
    s->cx = cx; s->cy = cy; s->radius = r;
    s->startAngle = a0; s->endAngle = a1;
    s->x0 = cx + r * cos(a0); s->y0 = cy + r * sin(a0);
    s->x1 = cx + r * cos(a1); s->y1 = cy + r * sin(a1);
    s->length = r * fabs(sweep);
    p->length += s->length;
}

static void add_landmark(HaloBorderPath *p, double s) {
    if (p->landmarkCount < HALO_MAX_LANDMARKS) p->landmarks[p->landmarkCount++] = s;
}

/// Adds a convex screen corner and records its midpoint as a landmark.
static void add_corner(HaloBorderPath *p, double cx, double cy, double r, double a0, double a1) {
    double before = p->length;
    add_arc(p, cx, cy, r, a0, a1);
    add_landmark(p, before + (p->length - before) / 2);
}

static int build(const HaloDisplayGeometry *g, double d, int trace, HaloBorderPath *out) {
    memset(out, 0, sizeof *out);
    const double W = g->width, H = g->height;
    const double Rc = fmax(g->cornerRadius, d); // corner centre distance from both edges
    const double rc = Rc - d;                   // offset corner radius
    const double halfPi = M_PI / 2;

    // The four screen corners and three edges are the same in both modes.
    // `topRightStartX`: where the top edge reaches the top-right corner.
    double startX, startY;

    if (!trace) {
        startX = W / 2;
        startY = d;
        add_line(out, startX, startY, W - Rc, d);
    } else {
        const double cxN = W / 2 + g->notchOffsetX;
        const double xL = cxN - g->notchWidth / 2, xR = cxN + g->notchWidth / 2;
        const double h = g->notchHeight, ri = g->notchInnerRadius;
        const double F = fmax(g->notchOuterRadius, d), rf = F - d;
        const double yc = h - ri, rr = ri + d;     // bottom-corner circles
        const int direct = (h - ri) < F - kEps;    // side vanished: top edge meets the corner circle
        double dx = 0;                              // half-chord where y = d crosses the corner circle
        if (direct) {
            double dy = d - yc;
            double q = rr * rr - dy * dy;
            dx = q > 0 ? sqrt(q) : 0;
        }
        // The notch must still sit between the screen corners at this offset.
        double leftEnd = direct ? (xL + ri - dx) : (xL - F);
        double rightEnd = direct ? (xR - ri + dx) : (xR + F);
        if (leftEnd < Rc - kEps || rightEnd > W - Rc + kEps) return 0;

        startX = cxN;
        startY = h + d;
        add_line(out, startX, startY, xR - ri, h + d);
        if (direct) {
            double aEnd = atan2(d - yc, dx);              // above-right of the centre, negative
            add_arc(out, xR - ri, yc, rr, halfPi, aEnd);  // decreasing: concave turn
            add_landmark(out, out->length);
        } else {
            double before = out->length;
            add_arc(out, xR - ri, yc, rr, halfPi, 0);
            add_landmark(out, before + (out->length - before) / 2);
            add_line(out, xR + d, yc, xR + d, F);
            add_arc(out, xR + F, F, rf, M_PI, 3 * halfPi);
            add_landmark(out, out->length);
        }
        add_line(out, rightEnd, d, W - Rc, d);
    }

    add_corner(out, W - Rc, Rc, rc, -halfPi, 0);
    {
        double before = out->length;
        add_line(out, W - d, Rc, W - d, H - Rc);
        add_landmark(out, before + (out->length - before) / 2);
    }
    add_corner(out, W - Rc, H - Rc, rc, 0, halfPi);
    {
        double before = out->length;
        add_line(out, W - Rc, H - d, Rc, H - d);
        add_landmark(out, before + (out->length - before) / 2);
    }
    add_corner(out, Rc, H - Rc, rc, halfPi, M_PI);
    {
        double before = out->length;
        add_line(out, d, H - Rc, d, Rc);
        add_landmark(out, before + (out->length - before) / 2);
    }
    add_corner(out, Rc, Rc, rc, M_PI, 3 * halfPi);

    if (!trace) {
        add_line(out, Rc, d, startX, startY);
    } else {
        const double cxN = W / 2 + g->notchOffsetX;
        const double xL = cxN - g->notchWidth / 2;
        const double h = g->notchHeight, ri = g->notchInnerRadius;
        const double F = fmax(g->notchOuterRadius, d), rf = F - d;
        const double yc = h - ri, rr = ri + d;
        const int direct = (h - ri) < F - kEps;
        if (direct) {
            double dy = d - yc;
            double q = rr * rr - dy * dy;
            double dx = q > 0 ? sqrt(q) : 0;
            add_line(out, Rc, d, xL + ri - dx, d);
            add_landmark(out, out->length);
            // Start above-left of the centre (third quadrant, expressed > π so
            // the decreasing sweep passes through π, the leftmost point).
            double aStart = atan2(dy, -dx);
            if (aStart < 0) aStart += 2 * M_PI;
            add_arc(out, xL + ri, yc, rr, aStart, halfPi);
        } else {
            add_line(out, Rc, d, xL - F, d);
            add_landmark(out, out->length);
            add_arc(out, xL - F, F, rf, -halfPi, 0);
            add_line(out, xL - d, F, xL - d, yc);
            double before = out->length;
            add_arc(out, xL + ri, yc, rr, M_PI, halfPi);
            add_landmark(out, before + (out->length - before) / 2);
        }
        add_line(out, xL + ri, h + d, startX, startY);
    }
    out->tracesCutout = trace;
    return out->count > 0 && out->length > 0;
}

int halo_build_border(const HaloDisplayGeometry *input, double offset, int traceCutout, HaloBorderPath *out) {
    HaloDisplayGeometry g = halo_sanitize_geometry(*input);
    memset(out, 0, sizeof *out);
    if (g.width <= 0) return 0;
    double d = clampd(finite_or(offset, 0), 0, halo_max_offset(&g));
    int trace = traceCutout && g.cutout == HaloCutoutNotch;
    if (trace && build(&g, d, 1, out)) return 1;
    // No cutout, tracing switched off, or the notch no longer fits at this
    // offset: run straight along the top edge.
    return build(&g, d, 0, out);
}

// MARK: - Queries

void halo_point_at(const HaloBorderPath *path, double s, double *x, double *y) {
    *x = 0;
    *y = 0;
    if (path->count == 0 || path->length <= 0) return;
    s = fmod(s, path->length);
    if (s < 0) s += path->length;
    for (int i = 0; i < path->count; i++) {
        const HaloSegment *seg = &path->segments[i];
        if (s <= seg->length || i == path->count - 1) {
            double t = seg->length > 0 ? clampd(s / seg->length, 0, 1) : 0;
            if (seg->kind == HaloSegmentLine) {
                *x = seg->x0 + (seg->x1 - seg->x0) * t;
                *y = seg->y0 + (seg->y1 - seg->y0) * t;
            } else {
                double a = seg->startAngle + (seg->endAngle - seg->startAngle) * t;
                *x = seg->cx + seg->radius * cos(a);
                *y = seg->cy + seg->radius * sin(a);
            }
            return;
        }
        s -= seg->length;
    }
}

int halo_border_to_beziers(const HaloBorderPath *path, HaloBezierOp *ops, int capacity) {
    int n = 0;
#define PUSH(op)                         \
    do {                                 \
        if (n >= capacity) return -1;    \
        ops[n++] = (op);                 \
    } while (0)
    if (path->count == 0) return 0;
    HaloBezierOp move = {HaloBezierMove, path->segments[0].x0, path->segments[0].y0, 0, 0, 0, 0};
    PUSH(move);
    for (int i = 0; i < path->count; i++) {
        const HaloSegment *seg = &path->segments[i];
        if (seg->kind == HaloSegmentLine) {
            HaloBezierOp line = {HaloBezierLine, seg->x1, seg->y1, 0, 0, 0, 0};
            PUSH(line);
            continue;
        }
        double sweep = seg->endAngle - seg->startAngle;
        int pieces = (int)ceil(fabs(sweep) / (M_PI / 2) - 1e-9);
        if (pieces < 1) pieces = 1;
        double theta = sweep / pieces;
        double k = 4.0 / 3.0 * tan(theta / 4); // signed: works for both directions
        double r = seg->radius;
        for (int j = 0; j < pieces; j++) {
            double a = seg->startAngle + theta * j;
            double b = a + theta;
            double x0 = seg->cx + r * cos(a), y0 = seg->cy + r * sin(a);
            double x3 = seg->cx + r * cos(b), y3 = seg->cy + r * sin(b);
            if (j == pieces - 1) { // land exactly on the stored end point
                x3 = seg->x1;
                y3 = seg->y1;
            }
            HaloBezierOp curve = {HaloBezierCurve,
                                  x3,
                                  y3,
                                  x0 - k * r * sin(a),
                                  y0 + k * r * cos(a),
                                  x3 + k * r * sin(b),
                                  y3 - k * r * cos(b)};
            PUSH(curve);
        }
    }
    HaloBezierOp close = {HaloBezierClose, 0, 0, 0, 0, 0, 0};
    PUSH(close);
#undef PUSH
    return n;
}
