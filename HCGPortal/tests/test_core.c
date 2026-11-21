//
//  test_core.c
//  HCG Portal — host unit tests for the pure C core (src/PortalCore.c).
//
//  make -C tests test      (ASan + UBSan; GCC or Clang)
//
//  What this proves: the placement solver keeps the portal between the clock and
//  every obstacle in its column, shrinks / collapses / hides it when space runs
//  out, keeps it and its radial menu on screen with non-overlapping 64 pt
//  targets; the render plan honours Reduce Motion and Low Power Mode; the
//  pending protected action performs exactly the selected action once and only
//  after a successful authentication of the same request. What it does not
//  prove: anything about SpringBoard, which needs the Simulator harness and a
//  device.
//

#include "PortalCore.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long gChecks = 0, gFailures = 0;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        gChecks++;                                                             \
        if (!(cond)) {                                                         \
            gFailures++;                                                       \
            if (gFailures <= 40) {                                             \
                fprintf(stderr, "FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond); \
                fprintf(stderr, __VA_ARGS__);                                  \
                fprintf(stderr, "\n");                                         \
            }                                                                  \
        }                                                                      \
    } while (0)

static unsigned long long gSeed = 0x48434750ULL; // "HCGP"
static double rnd(void) {
    gSeed = gSeed * 6364136223846793005ULL + 1442695040888963407ULL;
    return (double)(gSeed >> 11) / (double)(1ULL << 53);
}
static double rrange(double lo, double hi) { return lo + (hi - lo) * rnd(); }

static PortalRect R(double x, double y, double w, double h) {
    PortalRect r = {x, y, w, h};
    return r;
}

// iPhone 11 Pro Max portrait: 414 x 896 pt, safe area top 44, bottom 34.
static PortalLayoutInput phone(void) {
    PortalLayoutInput in;
    memset(&in, 0, sizeof in);
    in.bounds = R(0, 0, 414, 896);
    in.safe = R(0, 44, 414, 896 - 44 - 34);
    in.anchorKnown = 1;
    in.anchorBottom = 300; // clock + date + widget row
    return in;
}

static int rects_intersect(PortalRect a, PortalRect b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

static void test_appearance(void) {
    PortalAppearance a;
    portal_appearance_defaults(&a);
    CHECK(a.palette == PORTAL_PALETTE_SIGNATURE && a.brightness == PORTAL_BRIGHTNESS_DEFAULT, "defaults");
    a.palette = 99; a.brightness = ((double)NAN); a.speed = 50; a.intensity = -1;
    portal_appearance_clamp(&a);
    CHECK(a.palette == PORTAL_PALETTE_SIGNATURE, "palette fallback");
    CHECK(a.brightness == PORTAL_BRIGHTNESS_DEFAULT, "NaN brightness -> default");
    CHECK(a.speed == PORTAL_SPEED_MAX, "speed clamp %f", a.speed);
    CHECK(a.intensity == 0.0, "intensity clamp");
    a.speed = ((double)INFINITY);
    portal_appearance_clamp(&a);
    CHECK(a.speed == PORTAL_SPEED_DEFAULT, "inf speed -> default");

    PortalPlacement p;
    portal_placement_defaults(&p);
    CHECK(p.size == PORTAL_SIZE_DEFAULT && p.offsetX == 0 && p.offsetY == PORTAL_OFFSET_Y_DEFAULT, "placement defaults");
    p.size = 10; p.offsetX = 1e9; p.offsetY = -1e9;
    portal_placement_clamp(&p);
    CHECK(p.size == PORTAL_SIZE_MIN && p.offsetX == PORTAL_OFFSET_X_LIMIT && p.offsetY == PORTAL_OFFSET_Y_MIN, "placement clamp");

    for (int i = 0; i < PORTAL_PALETTE_COUNT; i++) {
        CHECK(portal_palette_from_id(portal_palette_id(i)) == i, "palette round trip %d", i);
        PortalRGB a1, b1;
        portal_palette_colours(i, &a1, &b1);
        CHECK(a1.r >= 0 && a1.r <= 1 && b1.b >= 0 && b1.b <= 1, "palette colour range");
    }
    CHECK(portal_palette_from_id("nope") == PORTAL_PALETTE_SIGNATURE, "unknown palette");
    CHECK(portal_palette_from_id(NULL) == PORTAL_PALETTE_SIGNATURE, "NULL palette");
    PortalRGB c, v;
    portal_palette_colours(PORTAL_PALETTE_SIGNATURE, &c, &v);
    CHECK(c.b > 0.9 && c.g > 0.8 && c.r < 0.4, "signature primary is cyan");
    CHECK(v.b > 0.9 && v.r > 0.4 && v.g < 0.5, "signature secondary is violet");
    for (int i = 0; i < PORTAL_LOWPOWER_COUNT; i++) CHECK(portal_low_power_from_id(portal_low_power_id(i)) == i, "low power ids");
    CHECK(portal_low_power_from_id("x") == PORTAL_LOWPOWER_STATIC, "unknown low power");
}

static void test_render_plan(void) {
    PortalAppearance a;
    portal_appearance_defaults(&a);
    PortalRenderPlan p = portal_render_plan(&a, 0, 0, PORTAL_LOWPOWER_STATIC, 1);
    CHECK(p.draw && p.animate && p.particles && p.unlockAnimation && p.reason == PORTAL_PLAN_FULL, "full plan");
    CHECK(p.ringPeriod >= 12.0 && p.particleRate <= 6.0, "slow rings, restrained particles");
    CHECK(p.glowLayers >= 1 && p.glowLayers <= 3, "glow layers");

    // Every combination: invariants.
    for (int rm = 0; rm < 2; rm++)
        for (int lp = 0; lp < 2; lp++)
            for (int pol = -1; pol <= PORTAL_LOWPOWER_COUNT; pol++)
                for (int un = 0; un < 2; un++)
                    for (int k = 0; k < 20; k++) {
                        a.palette = k % 5 - 1;
                        a.speed = rrange(-1, 3);
                        a.intensity = rrange(-0.5, 1.5);
                        a.brightness = rrange(0, 2);
                        p = portal_render_plan(&a, rm, lp, pol, un);
                        if (rm) CHECK(!p.animate && !p.particles && !p.unlockAnimation, "Reduce Motion is static");
                        if (lp) CHECK(!p.particles && !p.unlockAnimation, "Low Power: no particles, no flourish");
                        if (lp && (pol == PORTAL_LOWPOWER_STATIC || pol < 0 || pol >= PORTAL_LOWPOWER_COUNT))
                            CHECK(!p.animate && p.draw, "Low Power static");
                        if (lp && pol == PORTAL_LOWPOWER_HIDE) CHECK(!p.draw, "Low Power hide");
                        if (lp && pol == PORTAL_LOWPOWER_ECONOMY && !rm) CHECK(p.animate && p.glowLayers == 1, "economy");
                        if (!un) CHECK(!p.unlockAnimation, "flourish only when enabled");
                        if (!lp && !rm) CHECK(p.draw && p.animate, "normal animates");
                        CHECK(isfinite(p.ringPeriod) && p.ringPeriod > 0 && p.particleRate <= 6.0, "finite plan");
                        if (p.particles) CHECK(p.animate, "particles only while animating");
                    }
}

static void test_layout_basic(void) {
    PortalPlacement pl;
    portal_placement_defaults(&pl);
    PortalLayoutInput in = phone();
    PortalLayout l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_FULL, "empty Lock Screen: full (%s)", portal_layout_mode_name(l.mode));
    CHECK(fabs(l.cx - 207) < 1e-9, "centred cx=%f", l.cx);
    CHECK(fabs(l.cy - (300 + PORTAL_GAP + pl.offsetY + pl.size / 2)) < 1e-9, "below the clock cy=%f", l.cy);
    CHECK(l.diameter == pl.size && l.hitRadius >= 22, "size");

    // A notification stack at the bottom (iOS 16+ default) leaves room.
    in.obstacleCount = 1;
    in.obstacles[0] = R(8, 640, 398, 140);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_FULL && l.cy + l.diameter / 2 <= 640 - PORTAL_GAP + 1e-9, "above bottom notifications");

    // Notifications rising to 440: the portal shrinks.
    in.obstacles[0] = R(8, 440, 398, 300);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_REDUCED, "reduced (%s)", portal_layout_mode_name(l.mode));
    CHECK(l.diameter >= PORTAL_SIZE_MIN && l.diameter < pl.size, "reduced size %f", l.diameter);
    CHECK(l.cy - l.diameter / 2 >= 300 + PORTAL_GAP - 1e-9 && l.cy + l.diameter / 2 <= 440 - PORTAL_GAP + 1e-9, "reduced fits");

    // A media platter at 390: compact orb.
    in.obstacles[0] = R(8, 390, 398, 200);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_COMPACT && l.diameter == PORTAL_COMPACT_SIZE, "compact (%s)", portal_layout_mode_name(l.mode));
    CHECK(l.hitRadius >= 28, "compact orb keeps a 56 pt target");

    // Notifications right under the clock: hidden, nothing intercepted.
    in.obstacles[0] = R(8, 320, 398, 500);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_HIDDEN, "hidden (%s)", portal_layout_mode_name(l.mode));

    // An obstacle outside the column is ignored (a narrow widget at the side).
    in.obstacles[0] = R(330, 320, 70, 70);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_FULL, "side obstacle ignored");
    // Obstacles entirely above the anchor are the clock area.
    in.obstacles[0] = R(0, 60, 414, 230);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_FULL, "clock area ignored");

    // Unknown anchor: estimated from the safe area.
    in = phone();
    in.anchorKnown = 0;
    l = portal_layout(&in, &pl);
    CHECK(fabs(l.anchor - portal_estimated_anchor(&in.bounds, &in.safe)) < 1e-9 && l.mode == PORTAL_LAYOUT_FULL, "estimated anchor");

    // Offset beyond the side: the portal stays on screen.
    in = phone();
    pl.offsetX = 120; pl.size = 180;
    l = portal_layout(&in, &pl);
    CHECK(l.cx + l.diameter / 2 <= 414 - PORTAL_EDGE_MARGIN + 1e-9, "stays inside on the right");
    pl.offsetX = -120;
    l = portal_layout(&in, &pl);
    CHECK(l.cx - l.diameter / 2 >= PORTAL_EDGE_MARGIN - 1e-9, "stays inside on the left");
    // Large vertical offset: clipped to the bottom reserve, not into the quick actions.
    portal_placement_defaults(&pl);
    pl.offsetY = 240; pl.size = 180;
    l = portal_layout(&in, &pl);
    CHECK(l.cy + l.diameter / 2 <= 44 + 818 - PORTAL_BOTTOM_RESERVE - PORTAL_GAP + 1e-9, "above the quick actions");
    // Degenerate bounds.
    memset(&in, 0, sizeof in);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_HIDDEN, "empty bounds hidden");
    in = phone();
    in.anchorBottom = ((double)NAN);
    l = portal_layout(&in, &pl);
    CHECK(l.mode != PORTAL_LAYOUT_HIDDEN && isfinite(l.cy), "NaN anchor falls back");
    in = phone();
    in.obstacleCount = 1000;
    for (int i = 0; i < PORTAL_MAX_OBSTACLES; i++) in.obstacles[i] = R(((double)NAN), 0, 1, 1);
    l = portal_layout(&in, &pl);
    CHECK(l.mode == PORTAL_LAYOUT_FULL, "bad obstacles ignored, count capped");
}

static void test_layout_fuzz(void) {
    for (int iter = 0; iter < 200000; iter++) {
        PortalLayoutInput in;
        memset(&in, 0, sizeof in);
        double w = rrange(320, 440), h = rrange(568, 960);
        in.bounds = R(0, 0, w, h);
        double top = rrange(20, 59), bottom = rrange(0, 34);
        in.safe = R(0, top, w, h - top - bottom);
        in.anchorKnown = rnd() < 0.8;
        in.anchorBottom = rrange(top + 60, top + 360);
        in.obstacleCount = (int)rrange(0, 8);
        for (int i = 0; i < in.obstacleCount; i++) {
            double ow = rrange(40, w), oh = rrange(30, 260);
            in.obstacles[i] = R(rrange(-20, w - 20), rrange(top, h), ow, oh);
        }
        PortalPlacement pl = {rrange(80, 200), rrange(-150, 150), rrange(-60, 260)};
        PortalLayout l = portal_layout(&in, &pl);
        if (l.mode == PORTAL_LAYOUT_HIDDEN) continue;
        PortalPlacement c = pl;
        portal_placement_clamp(&c);
        double r = l.diameter / 2;
        PortalRect box = R(l.cx - r, l.cy - r, l.diameter, l.diameter);
        CHECK(isfinite(l.cx) && isfinite(l.cy), "finite");
        CHECK(l.diameter <= c.size + 1e-9, "never larger than chosen");
        if (l.mode == PORTAL_LAYOUT_FULL) CHECK(fabs(l.diameter - c.size) < 1e-9, "full = chosen");
        if (l.mode == PORTAL_LAYOUT_REDUCED) CHECK(l.diameter >= PORTAL_SIZE_MIN - 1e-9, "reduced >= min");
        if (l.mode == PORTAL_LAYOUT_COMPACT) CHECK(l.diameter == PORTAL_COMPACT_SIZE, "compact size");
        CHECK(box.x >= in.safe.x + PORTAL_EDGE_MARGIN - 1e-6 && box.x + box.w <= in.safe.x + in.safe.w - PORTAL_EDGE_MARGIN + 1e-6,
              "inside horizontally");
        CHECK(box.y >= l.anchor + PORTAL_GAP - 1e-6, "below the clock/widgets (%f < %f)", box.y, l.anchor + PORTAL_GAP);
        CHECK(box.y + box.h <= in.safe.y + in.safe.h - PORTAL_BOTTOM_RESERVE - PORTAL_GAP + 1e-6, "above the quick actions");
        CHECK(l.hitRadius >= 22, "44 pt target");
        for (int i = 0; i < in.obstacleCount; i++) {
            PortalRect o = in.obstacles[i];
            if (o.y + o.h <= l.anchor) continue;
            CHECK(!rects_intersect(box, o), "never covers an obstacle below the clock (iter %d)", iter);
        }
    }
}

static void test_menu(void) {
    PortalRect safe = R(0, 44, 414, 818);
    for (int iter = 0; iter < 50000; iter++) {
        PortalLayout l;
        memset(&l, 0, sizeof l);
        l.mode = PORTAL_LAYOUT_FULL;
        l.diameter = rnd() < 0.3 ? PORTAL_COMPACT_SIZE : rrange(PORTAL_SIZE_MIN, PORTAL_SIZE_MAX);
        l.cx = rrange(16 + l.diameter / 2, 414 - 16 - l.diameter / 2);
        l.cy = rrange(200, 640);
        int count = 1 + (int)rrange(0, PORTAL_MENU_MAX_ITEMS);
        PortalMenuLayout m = portal_menu_layout(&l, count, &safe);
        CHECK(m.count == count, "count");
        for (int i = 0; i < count; i++) {
            double h = PORTAL_MENU_ITEM_SIZE / 2;
            CHECK(m.x[i] - h >= safe.x - 1e-6 && m.x[i] + h <= safe.x + safe.w + 1e-6, "item inside x (iter %d)", iter);
            CHECK(m.y[i] - h >= safe.y - 1e-6 && m.y[i] + h <= safe.y + safe.h + 1e-6, "item inside y (iter %d)", iter);
            CHECK(hypot(m.x[i] - l.cx, m.y[i] - l.cy) + h <= m.extentRadius + 1e-6, "extent covers items");
            CHECK(portal_menu_hit(&m, m.x[i], m.y[i]) == i, "hit own centre");
            for (int j = i + 1; j < count; j++)
                CHECK(hypot(m.x[i] - m.x[j], m.y[i] - m.y[j]) >= PORTAL_MENU_ITEM_SIZE + PORTAL_MENU_ITEM_GAP - 1e-6,
                      "items never overlap (%d,%d) iter %d", i, j, iter);
        }
        CHECK(!m.shifted, "a facing fits on a phone (iter %d)", iter);
        for (int i = 0; i < count && !m.shifted; i++)
            CHECK(hypot(m.x[i] - l.cx, m.y[i] - l.cy) >= l.diameter / 2 + PORTAL_MENU_ITEM_SIZE / 2 + 1e-6,
                  "items never cover the portal (iter %d)", iter);
        CHECK(portal_menu_hit(&m, l.cx, l.cy) == -1, "portal centre is not an item");
    }
    PortalLayout l = {PORTAL_LAYOUT_FULL, 207, 400, 132, 66, 300, 700};
    PortalMenuLayout m = portal_menu_layout(&l, 4, &safe);
    CHECK(m.x[0] < l.cx && m.x[3] > l.cx && !m.shifted, "fan runs left to right");
    CHECK(m.y[1] > l.cy && m.y[2] > l.cy, "middle items below the portal (the clock is above)");
    // Near the bottom: the fan turns rather than covering the portal.
    PortalLayout low = l;
    low.cy = 760;
    m = portal_menu_layout(&low, 4, &safe);
    CHECK(!m.shifted && m.y[1] < low.cy, "near the bottom it opens upwards");
    // A tiny safe area: shifted fallback, still inside.
    PortalRect tiny = R(0, 0, 200, 200);
    PortalLayout mid = {PORTAL_LAYOUT_COMPACT, 100, 100, 56, 28, 0, 200};
    m = portal_menu_layout(&mid, 6, &tiny);
    CHECK(m.shifted, "tiny screen falls back to shifting");
    m = portal_menu_layout(&l, 0, &safe);
    CHECK(m.count == 0 && portal_menu_hit(&m, 0, 0) == -1, "empty menu");
    m = portal_menu_layout(&l, 99, &safe);
    CHECK(m.count == PORTAL_MENU_MAX_ITEMS, "capped");
}

static void test_visibility(void) {
    PortalVisibilityInput v = {1, 0, 0, 1, 1, 1, 1, 0, PORTAL_LAYOUT_FULL, 1};
    CHECK(portal_visibility(&v) == PORTAL_VIS_VISIBLE, "visible");
    // Exhaustive: visible iff all conditions hold.
    for (int mask = 0; mask < (1 << 9); mask++) {
        PortalVisibilityInput t;
        t.enabled = mask & 1;
        t.killSwitch = (mask >> 1) & 1;
        t.fault = (mask >> 2) & 1;
        t.hostAttached = (mask >> 3) & 1;
        t.coverSheetVisible = (mask >> 4) & 1;
        t.screenOn = (mask >> 5) & 1;
        t.lockScreenSession = (mask >> 6) & 1;
        t.authenticationVisible = (mask >> 7) & 1;
        t.planDraws = (mask >> 8) & 1;
        for (int mode = PORTAL_LAYOUT_HIDDEN; mode <= PORTAL_LAYOUT_COMPACT; mode++) {
            t.layoutMode = mode;
            int expect = t.enabled && !t.killSwitch && !t.fault && t.hostAttached && t.coverSheetVisible && t.screenOn &&
                         t.lockScreenSession && !t.authenticationVisible && t.planDraws && mode != PORTAL_LAYOUT_HIDDEN;
            PortalVisibility got = portal_visibility(&t);
            CHECK((got == PORTAL_VIS_VISIBLE) == expect, "visibility mask %d mode %d -> %s", mask, mode,
                  portal_visibility_name(got));
            if (t.killSwitch) CHECK(got == PORTAL_VIS_KILL_SWITCH, "kill switch first");
            if (!t.killSwitch && !t.enabled) CHECK(got == PORTAL_VIS_DISABLED, "disabled next");
            CHECK(strcmp(portal_visibility_name(got), "unknown") != 0, "named");
        }
    }
}

static void test_destinations(void) {
    PortalDestinationProbe none = {0};
    PortalDestinationProbe all = {1, 1, 1, 1, 1, 3};
    CHECK(portal_destination_availability(PORTAL_DEST_DEVICES, &all) == PORTAL_AVAIL_NOT_CONNECTED, "devices never connected");
    CHECK(portal_destination_availability(PORTAL_DEST_NEXUS, &none) == PORTAL_AVAIL_NOT_INSTALLED, "nexus absent");
    PortalDestinationProbe nx = all;
    nx.nexusOpenInterface = 0;
    CHECK(portal_destination_availability(PORTAL_DEST_NEXUS, &nx) == PORTAL_AVAIL_NEEDS_INTERFACE, "nexus without interface");
    CHECK(portal_destination_availability(PORTAL_DEST_NEXUS, &all) == PORTAL_AVAIL_AVAILABLE, "nexus with interface");
    CHECK(portal_destination_availability(PORTAL_DEST_BACKGROUNDS, &none) == PORTAL_AVAIL_NOT_INSTALLED, "AC absent");
    CHECK(portal_destination_availability(PORTAL_DEST_BACKGROUNDS, &all) == PORTAL_AVAIL_AVAILABLE, "AC present");
    PortalDestinationProbe noauth = all;
    noauth.authAvailable = 0;
    CHECK(portal_destination_availability(PORTAL_DEST_BACKGROUNDS, &noauth) == PORTAL_AVAIL_AUTH_UNAVAILABLE, "fail closed without auth");
    CHECK(portal_destination_availability(PORTAL_DEST_APP_ITEM, &noauth) == PORTAL_AVAIL_AUTH_UNAVAILABLE, "app fails closed");
    CHECK(portal_destination_availability(PORTAL_DEST_APPS, &none) == PORTAL_AVAIL_NO_APPS, "no apps");
    CHECK(portal_destination_availability(PORTAL_DEST_APPS, &all) == PORTAL_AVAIL_AVAILABLE, "apps ring");
    PortalDestinationProbe nolaunch = all;
    nolaunch.launcherAvailable = 0;
    CHECK(portal_destination_availability(PORTAL_DEST_APP_ITEM, &nolaunch) == PORTAL_AVAIL_LAUNCHER_UNAVAILABLE, "no launcher");
    CHECK(portal_destination_requires_auth(PORTAL_DEST_NEXUS) && portal_destination_requires_auth(PORTAL_DEST_BACKGROUNDS) &&
              portal_destination_requires_auth(PORTAL_DEST_APP_ITEM),
          "every launching destination needs authentication");
    CHECK(!portal_destination_requires_auth(PORTAL_DEST_DEVICES) && !portal_destination_requires_auth(PORTAL_DEST_APPS),
          "showing a ring or a status needs none");
    CHECK(portal_destination_availability(42, &all) == PORTAL_AVAIL_NOT_INSTALLED, "unknown destination");
    CHECK(strcmp(portal_destination_id(PORTAL_DEST_BACKGROUNDS), "backgrounds") == 0, "ids");
}

static void test_pending(void) {
    PortalPending p;
    portal_pending_init(&p);
    unsigned g = portal_pending_begin(&p, PORTAL_DEST_APP_ITEM, 2, 100.0);
    CHECK(g != 0 && p.awaiting, "begin");
    CHECK(portal_pending_begin(&p, PORTAL_DEST_BACKGROUNDS, -1, 101.0) == 0, "second request ignored while waiting");
    PortalPendingOutcome o = portal_pending_resolve(&p, g + 7, 1, 102.0);
    CHECK(!o.perform && p.awaiting, "stale generation ignored, still waiting");
    o = portal_pending_resolve(&p, g, 1, 103.0);
    CHECK(o.perform && o.destination == PORTAL_DEST_APP_ITEM && o.item == 2 && !p.awaiting, "success performs the selected action");
    o = portal_pending_resolve(&p, g, 1, 104.0);
    CHECK(!o.perform, "performs only once");

    g = portal_pending_begin(&p, PORTAL_DEST_BACKGROUNDS, -1, 200.0);
    o = portal_pending_resolve(&p, g, 0, 201.0);
    CHECK(!o.perform && !p.awaiting, "cancellation discards");
    o = portal_pending_resolve(&p, g, 1, 202.0);
    CHECK(!o.perform, "late success after cancellation discarded");

    g = portal_pending_begin(&p, PORTAL_DEST_NEXUS, -1, 300.0);
    portal_pending_cancel(&p); // screen off / disabled
    o = portal_pending_resolve(&p, g, 1, 301.0);
    CHECK(!o.perform, "success after screen-off discarded");

    g = portal_pending_begin(&p, PORTAL_DEST_NEXUS, -1, 400.0);
    o = portal_pending_resolve(&p, g, 1, 400.0 + PORTAL_PENDING_TIMEOUT + 1);
    CHECK(!o.perform && !p.awaiting, "too late discarded");
    g = portal_pending_begin(&p, PORTAL_DEST_NEXUS, -1, 500.0);
    CHECK(!portal_pending_expire(&p, 510.0) && p.awaiting, "not yet expired");
    CHECK(portal_pending_expire(&p, 500.0 + PORTAL_PENDING_TIMEOUT + 0.5) && !p.awaiting, "expired");
    o = portal_pending_resolve(&p, g, 1, 520.0);
    CHECK(!o.perform, "expired request never performs");
    g = portal_pending_begin(&p, PORTAL_DEST_NEXUS, -1, 600.0);
    o = portal_pending_resolve(&p, g, 1, ((double)NAN));
    CHECK(!o.perform, "NaN clock never performs");
    o = portal_pending_resolve(&p, 0, 1, 600.0);
    CHECK(!o.perform, "generation 0 never performs");

    // Random sequences: at most one perform per begin, and only for that begin's action.
    portal_pending_init(&p);
    for (int iter = 0; iter < 200000; iter++) {
        double now = iter;
        int dest = (int)rrange(0, 4), item = (int)rrange(-1, 6);
        unsigned gen = portal_pending_begin(&p, dest, item, now);
        if (!gen) { portal_pending_cancel(&p); continue; }
        int performed = 0;
        int steps = 1 + (int)rrange(0, 4);
        for (int s = 0; s < steps; s++) {
            double r = rnd();
            unsigned which = r < 0.15 ? gen + 1 : gen;
            int success = rnd() < 0.6;
            double t = now + rrange(0, PORTAL_PENDING_TIMEOUT * 1.2);
            if (r > 0.9) portal_pending_cancel(&p);
            PortalPendingOutcome x = portal_pending_resolve(&p, which, success, t);
            if (x.perform) {
                performed++;
                CHECK(which == gen && success && t - now <= PORTAL_PENDING_TIMEOUT, "performs only on own success in time");
                CHECK(x.destination == dest && x.item == item, "exact action");
            }
        }
        CHECK(performed <= 1, "at most once");
        portal_pending_cancel(&p);
    }
}

static void test_launch_guard(void) {
    CHECK(!portal_launch_guard_blocks(0, 3), "first launch runs");
    CHECK(!portal_launch_guard_blocks(2, 3), "two quick exits: still runs");
    CHECK(portal_launch_guard_blocks(3, 3), "three quick exits in a row: blocked");
    CHECK(portal_launch_guard_blocks(99, 3), "more: blocked");
    CHECK(!portal_launch_guard_blocks(-5, 3), "corrupt negative count never blocks");
    CHECK(portal_launch_guard_blocks(1, 0), "a maximum below one is treated as one");
}

int main(void) {
    test_appearance();
    test_render_plan();
    test_layout_basic();
    test_layout_fuzz();
    test_menu();
    test_visibility();
    test_destinations();
    test_pending();
    test_launch_guard();
    if (gFailures) {
        printf("%ld of %ld checks FAILED\n", gFailures, gChecks);
        return 1;
    }
    printf("all %ld checks passed\n", gChecks);
    return 0;
}
