//
//  PortalCore.c
//  HCG Portal — Hakmi Capital Group
//
//  See PortalCore.h. Pure C11, no allocation; host-tested in tests/test_core.c.
//

#include "PortalCore.h"

#include <math.h>
#include <string.h>

static double clampd(double v, double lo, double hi, double fallback) {
    if (!isfinite(v)) return fallback;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// ---- Appearance and placement ---------------------------------------------

void portal_appearance_defaults(PortalAppearance *a) {
    a->palette = PORTAL_PALETTE_SIGNATURE;
    a->brightness = PORTAL_BRIGHTNESS_DEFAULT;
    a->speed = PORTAL_SPEED_DEFAULT;
    a->intensity = PORTAL_INTENSITY_DEFAULT;
}

void portal_appearance_clamp(PortalAppearance *a) {
    if (a->palette < 0 || a->palette >= PORTAL_PALETTE_COUNT) a->palette = PORTAL_PALETTE_SIGNATURE;
    a->brightness = clampd(a->brightness, PORTAL_BRIGHTNESS_MIN, 1.0, PORTAL_BRIGHTNESS_DEFAULT);
    a->speed = clampd(a->speed, PORTAL_SPEED_MIN, PORTAL_SPEED_MAX, PORTAL_SPEED_DEFAULT);
    a->intensity = clampd(a->intensity, 0.0, 1.0, PORTAL_INTENSITY_DEFAULT);
}

void portal_placement_defaults(PortalPlacement *p) {
    p->size = PORTAL_SIZE_DEFAULT;
    p->offsetX = 0.0;
    p->offsetY = PORTAL_OFFSET_Y_DEFAULT;
}

void portal_placement_clamp(PortalPlacement *p) {
    p->size = clampd(p->size, PORTAL_SIZE_MIN, PORTAL_SIZE_MAX, PORTAL_SIZE_DEFAULT);
    p->offsetX = clampd(p->offsetX, -PORTAL_OFFSET_X_LIMIT, PORTAL_OFFSET_X_LIMIT, 0.0);
    p->offsetY = clampd(p->offsetY, PORTAL_OFFSET_Y_MIN, PORTAL_OFFSET_Y_MAX, PORTAL_OFFSET_Y_DEFAULT);
}

static const char *const kPaletteIds[PORTAL_PALETTE_COUNT] = {"signature", "aurora", "solar", "mono"};

const char *portal_palette_id(int palette) {
    if (palette < 0 || palette >= PORTAL_PALETTE_COUNT) palette = PORTAL_PALETTE_SIGNATURE;
    return kPaletteIds[palette];
}

int portal_palette_from_id(const char *identifier) {
    if (!identifier) return PORTAL_PALETTE_SIGNATURE;
    for (int i = 0; i < PORTAL_PALETTE_COUNT; i++) {
        if (strcmp(identifier, kPaletteIds[i]) == 0) return i;
    }
    return PORTAL_PALETTE_SIGNATURE;
}

void portal_palette_colours(int palette, PortalRGB *primary, PortalRGB *secondary) {
    static const PortalRGB kPrimary[PORTAL_PALETTE_COUNT] = {
        {0.20, 0.90, 1.00}, // cyan
        {0.20, 1.00, 0.80}, // teal
        {1.00, 0.72, 0.25}, // amber
        {0.95, 0.97, 1.00}, // white
    };
    static const PortalRGB kSecondary[PORTAL_PALETTE_COUNT] = {
        {0.58, 0.36, 1.00}, // violet
        {0.35, 0.95, 0.45}, // green
        {1.00, 0.35, 0.55}, // rose
        {0.62, 0.68, 0.78}, // silver
    };
    if (palette < 0 || palette >= PORTAL_PALETTE_COUNT) palette = PORTAL_PALETTE_SIGNATURE;
    if (primary) *primary = kPrimary[palette];
    if (secondary) *secondary = kSecondary[palette];
}

// ---- Render plan -----------------------------------------------------------

static const char *const kLowPowerIds[PORTAL_LOWPOWER_COUNT] = {"static", "economy", "hide"};

const char *portal_low_power_id(int policy) {
    if (policy < 0 || policy >= PORTAL_LOWPOWER_COUNT) policy = PORTAL_LOWPOWER_STATIC;
    return kLowPowerIds[policy];
}

int portal_low_power_from_id(const char *identifier) {
    if (!identifier) return PORTAL_LOWPOWER_STATIC;
    for (int i = 0; i < PORTAL_LOWPOWER_COUNT; i++) {
        if (strcmp(identifier, kLowPowerIds[i]) == 0) return i;
    }
    return PORTAL_LOWPOWER_STATIC;
}

PortalRenderPlan portal_render_plan(const PortalAppearance *appearance, int reduceMotion, int lowPower,
                                    int lowPowerPolicy, int unlockAnimationEnabled) {
    PortalAppearance a = *appearance;
    portal_appearance_clamp(&a);
    PortalRenderPlan plan;
    plan.draw = 1;
    plan.animate = 1;
    plan.particles = a.intensity > 0.05;
    plan.glowLayers = 1 + (int)lround(a.intensity * 2.0); // 1 ... 3
    plan.ringPeriod = 24.0 / a.speed;                        // 12 s ... 96 s per lap: slow
    plan.particleRate = 1.0 + 5.0 * a.intensity;             // 1 ... 6 per second: restrained
    plan.unlockAnimation = unlockAnimationEnabled ? 1 : 0;
    plan.reason = PORTAL_PLAN_FULL;

    if (lowPower) {
        if (lowPowerPolicy < 0 || lowPowerPolicy >= PORTAL_LOWPOWER_COUNT) lowPowerPolicy = PORTAL_LOWPOWER_STATIC;
        if (lowPowerPolicy == PORTAL_LOWPOWER_HIDE) {
            plan.draw = 0;
            plan.animate = 0;
            plan.particles = 0;
            plan.glowLayers = 0;
            plan.unlockAnimation = 0;
            plan.reason = PORTAL_PLAN_LOW_POWER_HIDDEN;
            return plan;
        }
        plan.particles = 0;
        plan.glowLayers = 1;
        plan.unlockAnimation = 0;
        if (lowPowerPolicy == PORTAL_LOWPOWER_ECONOMY) {
            plan.ringPeriod = 2.0 * plan.ringPeriod;
            plan.reason = PORTAL_PLAN_LOW_POWER_ECONOMY;
        } else {
            plan.animate = 0;
            plan.reason = PORTAL_PLAN_LOW_POWER_STATIC;
        }
    }
    // Reduce Motion wins over every policy that still draws: a static appearance.
    if (reduceMotion) {
        plan.animate = 0;
        plan.particles = 0;
        plan.unlockAnimation = 0;
        plan.reason = PORTAL_PLAN_REDUCE_MOTION;
    }
    return plan;
}

// ---- Layout ----------------------------------------------------------------

double portal_estimated_anchor(const PortalRect *bounds, const PortalRect *safe) {
    // Clock + date + one widget row occupy roughly the top 30 % of a phone's
    // safe area in every iOS 15–17 Lock Screen layout.
    (void)bounds;
    return safe->y + 0.30 * safe->h;
}

static int overlaps_x(const PortalRect *r, double left, double right) {
    return r->x < right && r->x + r->w > left;
}

PortalLayout portal_layout(const PortalLayoutInput *in, const PortalPlacement *placementIn) {
    PortalPlacement placement = *placementIn;
    portal_placement_clamp(&placement);
    PortalLayout out;
    memset(&out, 0, sizeof out);
    out.mode = PORTAL_LAYOUT_HIDDEN;

    PortalRect safe = in->safe;
    if (!(safe.w > 0 && safe.h > 0) || !isfinite(safe.x) || !isfinite(safe.y)) safe = in->bounds;
    if (!(safe.w > 2 * PORTAL_EDGE_MARGIN + PORTAL_COMPACT_SIZE) || !(safe.h > 0)) return out;

    double anchor = (in->anchorKnown && isfinite(in->anchorBottom)) ? in->anchorBottom
                                                                    : portal_estimated_anchor(&in->bounds, &safe);
    if (anchor < safe.y) anchor = safe.y;
    out.anchor = anchor;

    double d = placement.size;
    double left = safe.x + PORTAL_EDGE_MARGIN, right = safe.x + safe.w - PORTAL_EDGE_MARGIN;
    double midX = safe.x + safe.w / 2.0;

    // Floor: the highest obstacle edge below the anchor in the portal's column
    // (measured at the chosen size, so a smaller portal is inside it too),
    // otherwise the reserved bottom area (flashlight, camera, home indicator).
    double cx = midX + placement.offsetX;
    {
        double half = d / 2.0;
        if (cx - half < left) cx = left + half;
        if (cx + half > right) cx = right - half;
    }
    double colL = cx - d / 2.0 - PORTAL_GAP, colR = cx + d / 2.0 + PORTAL_GAP;
    double floorY = safe.y + safe.h - PORTAL_BOTTOM_RESERVE;
    int n = in->obstacleCount;
    if (n < 0) n = 0;
    if (n > PORTAL_MAX_OBSTACLES) n = PORTAL_MAX_OBSTACLES;
    for (int i = 0; i < n; i++) {
        const PortalRect *r = &in->obstacles[i];
        if (!(r->w > 0 && r->h > 0) || !isfinite(r->x) || !isfinite(r->y)) continue;
        if (r->y + r->h <= anchor) continue; // entirely above the anchor: part of the clock area
        if (!overlaps_x(r, colL, colR)) continue;
        double top = r->y < anchor ? anchor : r->y;
        if (top < floorY) floorY = top;
    }
    double band = floorY - PORTAL_GAP - (anchor + PORTAL_GAP);
    if (band >= placement.size) {
        d = placement.size;
        out.mode = PORTAL_LAYOUT_FULL;
    } else if (band >= PORTAL_SIZE_MIN) {
        d = band;
        out.mode = PORTAL_LAYOUT_REDUCED;
    } else if (band >= PORTAL_COMPACT_SIZE) {
        d = PORTAL_COMPACT_SIZE;
        out.mode = PORTAL_LAYOUT_COMPACT;
    } else {
        out.mode = PORTAL_LAYOUT_HIDDEN;
        out.floor = floorY;
        return out;
    }

    double half = d / 2.0;
    if (cx - half < left) cx = left + half;
    if (cx + half > right) cx = right - half;
    double top = anchor + PORTAL_GAP;
    double bottom = floorY - PORTAL_GAP;
    double cy;
    if (out.mode == PORTAL_LAYOUT_FULL) {
        cy = top + placement.offsetY + half;
        if (cy - half < top) cy = top + half;
        if (cy + half > bottom) cy = bottom - half;
    } else {
        cy = (top + bottom) / 2.0; // squeezed: centre in the free band
    }
    out.cx = cx;
    out.cy = cy;
    out.diameter = d;
    out.hitRadius = half < 22.0 ? 22.0 : half;
    out.floor = floorY;
    return out;
}

const char *portal_layout_mode_name(int mode) {
    switch (mode) {
        case PORTAL_LAYOUT_FULL: return "full";
        case PORTAL_LAYOUT_REDUCED: return "reduced";
        case PORTAL_LAYOUT_COMPACT: return "compact";
        default: return "hidden";
    }
}

// ---- Radial menu -----------------------------------------------------------

PortalMenuLayout portal_menu_layout(const PortalLayout *portal, int count, const PortalRect *safe) {
    PortalMenuLayout m;
    memset(&m, 0, sizeof m);
    if (count < 0) count = 0;
    if (count > PORTAL_MENU_MAX_ITEMS) count = PORTAL_MENU_MAX_ITEMS;
    m.count = count;
    if (count == 0) return m;

    const double item = PORTAL_MENU_ITEM_SIZE;
    const double minChord = item + PORTAL_MENU_ITEM_GAP;
    const double h = item / 2.0 + 4.0;
    const double baseRadius = portal->diameter / 2.0 + 14.0 + item / 2.0;
    // Fan spans to try: four or fewer items use a half circle; more items
    // prefer a wider fan, then a half circle on a larger orbit.
    double spans[2] = {count <= 4 ? M_PI : 1.25 * M_PI, M_PI};
    int spanCount = count <= 4 ? 1 : 2;
    int placed = 0;
    double r = baseRadius, span = spans[0];
    for (int si = 0; si < spanCount && !placed; si++) {
        span = spans[si];
        r = baseRadius;
        if (count > 1) {
            double step = span / (count - 1);
            double needed = minChord / (2.0 * sin(step / 2.0));
            if (needed > r) r = needed;
        }
        // Facing directions every 15 degrees, nearest to "down" first (y grows
        // downwards and the clock is above the portal); "up" is the last resort.
        for (int k = 0; k <= 12 && !placed; k++) {
            for (int sign = -1; sign <= 1 && !placed; sign += 2) {
                if (k == 0 && sign == 1) continue;
                if (k == 12 && sign == 1) continue;
                double facing = M_PI / 2.0 + sign * k * (M_PI / 12.0);
                double start = facing + span / 2.0;
                int fits = 1;
                for (int i = 0; i < count; i++) {
                    double theta = count == 1 ? facing : start - i * (span / (count - 1));
                    m.x[i] = portal->cx + r * cos(theta);
                    m.y[i] = portal->cy + r * sin(theta);
                    if (m.x[i] - h < safe->x || m.x[i] + h > safe->x + safe->w || m.y[i] - h < safe->y ||
                        m.y[i] + h > safe->y + safe->h)
                        fits = 0;
                }
                placed = fits;
            }
        }
    }
    m.radius = r;
    if (!placed) {
        // Nothing fits as is (a very small screen): the downward fan, shifted
        // (never squeezed) inside the safe area. Items may then cover the portal.
        span = spans[0];
        r = baseRadius;
        if (count > 1) {
            double step = span / (count - 1);
            double needed = minChord / (2.0 * sin(step / 2.0));
            if (needed > r) r = needed;
        }
        m.radius = r;
        double start = M_PI / 2.0 + span / 2.0;
        double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
        for (int i = 0; i < count; i++) {
            double theta = count == 1 ? M_PI / 2.0 : start - i * (span / (count - 1));
            m.x[i] = portal->cx + r * cos(theta);
            m.y[i] = portal->cy + r * sin(theta);
            if (m.x[i] < minX) minX = m.x[i];
            if (m.x[i] > maxX) maxX = m.x[i];
            if (m.y[i] < minY) minY = m.y[i];
            if (m.y[i] > maxY) maxY = m.y[i];
        }
        double dx = 0, dy = 0;
        if (minX - h < safe->x) dx = safe->x - (minX - h);
        else if (maxX + h > safe->x + safe->w) dx = (safe->x + safe->w) - (maxX + h);
        if (maxY + h > safe->y + safe->h) dy = (safe->y + safe->h) - (maxY + h);
        else if (minY - h < safe->y) dy = safe->y - (minY - h);
        for (int i = 0; i < count; i++) {
            m.x[i] += dx;
            m.y[i] += dy;
        }
        m.shifted = 1;
    }
    double extent = 0;
    for (int i = 0; i < count; i++) {
        double e = hypot(m.x[i] - portal->cx, m.y[i] - portal->cy) + item / 2.0;
        if (e > extent) extent = e;
    }
    m.extentRadius = extent;
    return m;
}

int portal_menu_hit(const PortalMenuLayout *menu, double x, double y) {
    double r = PORTAL_MENU_ITEM_SIZE / 2.0;
    for (int i = 0; i < menu->count; i++) {
        if (hypot(x - menu->x[i], y - menu->y[i]) <= r) return i;
    }
    return -1;
}

// ---- Visibility --------------------------------------------------------------

// ---- Access ---------------------------------------------------------------------

PortalAccess portal_access(const PortalAccessInput *in) {
    // Any source that reports "locked" wins, whatever the others say.
    if (in->protectedDataAvailable == PORTAL_SIGNAL_NO || in->lockStateLocked == PORTAL_SIGNAL_YES ||
        in->uiLocked == PORTAL_SIGNAL_YES || in->inSecureApp == PORTAL_SIGNAL_YES)
        return PORTAL_ACCESS_LOCKED;
    // Every required source must have been read, and say "unlocked". Anything else is closed.
    if (in->protectedDataAvailable != PORTAL_SIGNAL_YES || in->lockStateLocked != PORTAL_SIGNAL_NO ||
        in->uiLocked != PORTAL_SIGNAL_NO)
        return PORTAL_ACCESS_UNVERIFIED;
    if (in->screenOn == PORTAL_SIGNAL_NO) return PORTAL_ACCESS_SCREEN_OFF;
    return PORTAL_ACCESS_GRANTED;
}

const char *portal_access_name(int access) {
    switch (access) {
        case PORTAL_ACCESS_GRANTED: return "unlocked";
        case PORTAL_ACCESS_LOCKED: return "locked";
        case PORTAL_ACCESS_UNVERIFIED: return "unverified";
        case PORTAL_ACCESS_SCREEN_OFF: return "screen-off";
        default: return "unknown";
    }
}

void portal_access_session_init(PortalAccessSession *s) {
    s->granted = 0;
    s->epoch = 1;
}

int portal_access_session_apply(PortalAccessSession *s, PortalAccess access) {
    int granted = access == PORTAL_ACCESS_GRANTED;
    int revoked = s->granted && !granted;
    if (granted != s->granted) {
        // Every change starts a new epoch: nothing captured before a relock, and nothing
        // captured while closed, is ever permitted afterwards.
        s->epoch++;
        if (s->epoch == 0) s->epoch = 1;
    }
    s->granted = granted;
    return revoked;
}

int portal_access_permits(const PortalAccessSession *s, unsigned epoch) {
    return s->granted && epoch != 0 && epoch == s->epoch;
}

// ---- Visibility -------------------------------------------------------------------

PortalVisibility portal_visibility(const PortalVisibilityInput *in) {
    if (in->killSwitch) return PORTAL_VIS_KILL_SWITCH;
    if (!in->enabled) return PORTAL_VIS_DISABLED;
    if (in->fault) return PORTAL_VIS_FAULT;
    if (!in->accessGranted) return PORTAL_VIS_LOCKED;
    if (!in->hostAttached) return PORTAL_VIS_NO_HOST;
    if (!in->screenOn) return PORTAL_VIS_SCREEN_OFF;
    if (!in->coverSheetVisible) return PORTAL_VIS_NOT_COVER_SHEET;
    if (in->opening) return PORTAL_VIS_OPENING;
    if (!in->planDraws) return PORTAL_VIS_LOW_POWER_HIDDEN;
    if (in->layoutMode == PORTAL_LAYOUT_HIDDEN) return PORTAL_VIS_NO_ROOM;
    return PORTAL_VIS_VISIBLE;
}

const char *portal_visibility_name(int v) {
    switch (v) {
        case PORTAL_VIS_VISIBLE: return "visible";
        case PORTAL_VIS_DISABLED: return "disabled";
        case PORTAL_VIS_KILL_SWITCH: return "kill-switch";
        case PORTAL_VIS_FAULT: return "fault";
        case PORTAL_VIS_NO_HOST: return "no-host";
        case PORTAL_VIS_SCREEN_OFF: return "screen-off";
        case PORTAL_VIS_NOT_COVER_SHEET: return "not-cover-sheet";
        case PORTAL_VIS_OPENING: return "opening";
        case PORTAL_VIS_NO_ROOM: return "no-room";
        case PORTAL_VIS_LOW_POWER_HIDDEN: return "low-power-hidden";
        case PORTAL_VIS_LOCKED: return "locked";
        default: return "unknown";
    }
}

// ---- Destinations and the pending protected action -----------------------------

PortalAvailability portal_destination_availability(int destination, const PortalDestinationProbe *p) {
    switch (destination) {
        case PORTAL_DEST_DEVICES:
            return PORTAL_AVAIL_NOT_CONNECTED;
        case PORTAL_DEST_NEXUS:
            if (!p->nexusInstalled) return PORTAL_AVAIL_NOT_INSTALLED;
            if (!p->nexusOpenInterface) return PORTAL_AVAIL_NEEDS_INTERFACE;
            break;
        case PORTAL_DEST_BACKGROUNDS:
            if (!p->animationCenterInstalled) return PORTAL_AVAIL_NOT_INSTALLED;
            if (!p->launcherAvailable) return PORTAL_AVAIL_LAUNCHER_UNAVAILABLE;
            break;
        case PORTAL_DEST_APPS:
            if (p->appCount <= 0) return PORTAL_AVAIL_NO_APPS;
            if (!p->launcherAvailable) return PORTAL_AVAIL_LAUNCHER_UNAVAILABLE;
            return PORTAL_AVAIL_AVAILABLE;
        case PORTAL_DEST_APP_ITEM:
            if (!p->launcherAvailable) return PORTAL_AVAIL_LAUNCHER_UNAVAILABLE;
            break;
        default:
            return PORTAL_AVAIL_NOT_INSTALLED;
    }
    return PORTAL_AVAIL_AVAILABLE;
}

int portal_destination_performs_action(int destination) {
    switch (destination) {
        case PORTAL_DEST_NEXUS:
        case PORTAL_DEST_BACKGROUNDS:
        case PORTAL_DEST_APP_ITEM:
            return 1;
        default:
            return 0;
    }
}

const char *portal_destination_id(int destination) {
    switch (destination) {
        case PORTAL_DEST_NEXUS: return "nexus";
        case PORTAL_DEST_BACKGROUNDS: return "backgrounds";
        case PORTAL_DEST_DEVICES: return "devices";
        case PORTAL_DEST_APPS: return "apps";
        case PORTAL_DEST_APP_ITEM: return "app";
        default: return "unknown";
    }
}

void portal_pending_init(PortalPending *p) {
    memset(p, 0, sizeof *p);
}

unsigned portal_pending_begin(PortalPending *p, int destination, int item, double now, unsigned accessEpoch) {
    if (p->awaiting || accessEpoch == 0) return 0;
    p->generation++;
    if (p->generation == 0) p->generation = 1;
    p->awaiting = 1;
    p->destination = destination;
    p->item = item;
    p->startedAt = now;
    p->accessEpoch = accessEpoch;
    return p->generation;
}

PortalPendingOutcome portal_pending_resolve(PortalPending *p, unsigned generation, int success, double now,
                                            const PortalAccessSession *access) {
    PortalPendingOutcome o = {0, -1, -1};
    if (!p->awaiting || generation == 0 || generation != p->generation) return o; // stale or unknown: ignore
    int inTime = isfinite(now) && now >= p->startedAt && now - p->startedAt <= PORTAL_PENDING_TIMEOUT;
    int permitted = access != NULL && portal_access_permits(access, p->accessEpoch);
    if (success && inTime && permitted) {
        o.perform = 1;
        o.destination = p->destination;
        o.item = p->item;
    }
    p->awaiting = 0;
    p->destination = -1;
    p->item = -1;
    return o;
}

void portal_pending_cancel(PortalPending *p) {
    p->awaiting = 0;
    p->accessEpoch = 0;
    p->destination = -1;
    p->item = -1;
}

int portal_pending_expire(PortalPending *p, double now) {
    if (!p->awaiting) return 0;
    if (!isfinite(now) || now < p->startedAt || now - p->startedAt > PORTAL_PENDING_TIMEOUT) {
        portal_pending_cancel(p);
        return 1;
    }
    return 0;
}

int portal_launch_guard_blocks(long consecutiveUnstableLaunches, long maximum) {
    if (maximum < 1) maximum = 1;
    return consecutiveUnstableLaunches >= maximum;
}
