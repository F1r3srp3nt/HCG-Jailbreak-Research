//
//  HACPolicy.c
//  HCG Animation Center — Hakmi Capital Group
//

#include "HACPolicy.h"

#include <string.h>

bool hac_surface_visible(HACSurface surface, const HACSurfaceInputs *in) {
    if (!in || !in->screenOn) return false;
    if (surface == HACSurfaceLock) return in->locked;
    return !in->locked && !in->appInFront;
}

static HACDecision decision(HACShow show, bool visible, const char *reason) {
    HACDecision d = {show, visible, reason};
    return d;
}

HACDecision hac_decide(HACSurface surface, const HACSurfaceInputs *in) {
    if (!in) return decision(HACShowSystem, false, "no input");
    bool visible = hac_surface_visible(surface, in);
    if (!in->enabled) return decision(HACShowSystem, visible, "off");
    if (!in->surfaceEnabled) return decision(HACShowSystem, visible, "off for this surface");
    if (!in->assigned) return decision(HACShowSystem, visible, "no background assigned");
    if (!in->attached) return decision(HACShowSystem, visible, "not attached to SpringBoard");

    // Static fallback when video is not allowed or not possible. With no
    // still either, the system wallpaper shows: never a blank screen.
    const char *stillReason = NULL;
    if (!in->mediaPlayable) {
        stillReason = "video unavailable";
    } else if (in->lowPower && in->lowPowerPolicy == HACLowPowerSystem) {
        return decision(HACShowSystem, visible, "Low Power Mode (system wallpaper)");
    } else if (in->reduceMotion && in->reduceMotionPolicy == HACReduceMotionStill) {
        stillReason = "Reduce Motion";
    } else if (in->lowPower && in->lowPowerPolicy == HACLowPowerStill) {
        stillReason = "Low Power Mode";
    } else if (in->thermalState >= HAC_THERMAL_STILL) {
        stillReason = "device is hot";
    }
    if (stillReason) {
        if (!in->stillAvailable) return decision(HACShowSystem, visible, stillReason);
        return decision(HACShowStill, visible, stillReason);
    }

    if (!visible) {
        const char *why = !in->screenOn ? "screen off"
                          : surface == HACSurfaceLock ? "unlocked"
                          : in->locked ? "locked"
                                       : "app in front";
        return decision(HACShowPaused, false, why);
    }
    return decision(HACShowPlaying, true, "playing");
}

static const char *const kShowIds[] = {"system", "still", "paused", "playing"};
static const char *const kSurfaceIds[] = {"home", "lock"};
static const char *const kReduceMotionIds[] = {"still", "play"};
static const char *const kLowPowerIds[] = {"still", "play", "system"};

#define COUNT(a) ((int)(sizeof(a) / sizeof((a)[0])))

static const char *lookup(const char *const *ids, int count, int value) {
    return value >= 0 && value < count ? ids[value] : NULL;
}

static int parse(const char *const *ids, int count, const char *identifier) {
    if (!identifier) return -1;
    for (int i = 0; i < count; i++)
        if (strcmp(ids[i], identifier) == 0) return i;
    return -1;
}

const char *hac_show_id(HACShow show) {
    return lookup(kShowIds, COUNT(kShowIds), (int)show);
}

const char *hac_surface_id(HACSurface surface) {
    return lookup(kSurfaceIds, COUNT(kSurfaceIds), (int)surface);
}

const char *hac_reduce_motion_id(HACReduceMotionPolicy policy) {
    return lookup(kReduceMotionIds, COUNT(kReduceMotionIds), (int)policy);
}

const char *hac_low_power_id(HACLowPowerPolicy policy) {
    return lookup(kLowPowerIds, COUNT(kLowPowerIds), (int)policy);
}

bool hac_reduce_motion_parse(const char *identifier, HACReduceMotionPolicy *out) {
    int i = parse(kReduceMotionIds, COUNT(kReduceMotionIds), identifier);
    if (i < 0) return false;
    if (out) *out = (HACReduceMotionPolicy)i;
    return true;
}

bool hac_low_power_parse(const char *identifier, HACLowPowerPolicy *out) {
    int i = parse(kLowPowerIds, COUNT(kLowPowerIds), identifier);
    if (i < 0) return false;
    if (out) *out = (HACLowPowerPolicy)i;
    return true;
}
