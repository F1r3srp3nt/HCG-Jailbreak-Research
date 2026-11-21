//
//  HCGBackgroundCore.c
//  HCGBackgroundKit — Hakmi Capital Group
//
//  See HCGBackgroundCore.h. Pure C11 + libm; tested on Linux and macOS with
//  ASan/UBSan (tests/test_core.c).
//

#include "HCGBackgroundCore.h"

#include <math.h>
#include <string.h>

static double clampd(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static bool finite_positive(double v) {
    return isfinite(v) && v > 0;
}

static bool size_ok(HCGBGSize s) {
    return finite_positive(s.width) && finite_positive(s.height);
}

// ---- Enumerations ------------------------------------------------------------

static const char *const kScalingIds[] = {"fill", "fit", "crop"};

const char *hcgbg_scaling_id(HCGBGScaling scaling) {
    if ((int)scaling < 0 || (int)scaling > (int)HCGBGScalingCrop) return NULL;
    return kScalingIds[scaling];
}

bool hcgbg_scaling_parse(const char *identifier, HCGBGScaling *out) {
    if (!identifier) return false;
    for (int i = 0; i <= (int)HCGBGScalingCrop; i++) {
        if (strcmp(identifier, kScalingIds[i]) == 0) {
            if (out) *out = (HCGBGScaling)i;
            return true;
        }
    }
    return false;
}

// ---- Geometry ----------------------------------------------------------------

HCGBGRect hcgbg_crop_clamp(HCGBGRect c) {
    if (!isfinite(c.x) || !isfinite(c.y) || !isfinite(c.width) || !isfinite(c.height)) {
        HCGBGRect whole = {0, 0, 1, 1};
        return whole;
    }
    c.width = clampd(c.width, HCGBG_CROP_MIN, 1);
    c.height = clampd(c.height, HCGBG_CROP_MIN, 1);
    c.x = clampd(c.x, 0, 1 - c.width);
    c.y = clampd(c.y, 0, 1 - c.height);
    return c;
}

HCGBGRect hcgbg_layout(HCGBGSize container, HCGBGSize media, HCGBGScaling scaling, HCGBGRect crop) {
    HCGBGRect whole = {0, 0, container.width, container.height};
    if (!size_ok(container) || !size_ok(media)) {
        if (!size_ok(container)) whole.width = whole.height = 0;
        return whole;
    }
    if (scaling == HCGBGScalingFit) {
        double s = fmin(container.width / media.width, container.height / media.height);
        HCGBGRect r = {0, 0, media.width * s, media.height * s};
        r.x = (container.width - r.width) / 2;
        r.y = (container.height - r.height) / 2;
        return r;
    }
    HCGBGRect c = {0, 0, 1, 1};
    if (scaling == HCGBGScalingCrop) c = hcgbg_crop_clamp(crop);
    // Scale so the crop region covers the container.
    double s = fmax(container.width / (c.width * media.width), container.height / (c.height * media.height));
    HCGBGRect r = {0, 0, media.width * s, media.height * s};
    double cropCentreX = (c.x + c.width / 2) * r.width;
    double cropCentreY = (c.y + c.height / 2) * r.height;
    r.x = clampd(container.width / 2 - cropCentreX, container.width - r.width, 0);
    r.y = clampd(container.height / 2 - cropCentreY, container.height - r.height, 0);
    return r;
}

/// The normalised region an aspect-fill shows.
static HCGBGRect fill_region(HCGBGSize container, HCGBGSize media) {
    HCGBGRect r = {0, 0, 1, 1};
    if (!size_ok(container) || !size_ok(media)) return r;
    double containerAspect = container.width / container.height;
    double mediaAspect = media.width / media.height;
    if (mediaAspect > containerAspect) {
        r.width = containerAspect / mediaAspect; // full height, part of the width
    } else {
        r.height = mediaAspect / containerAspect; // full width, part of the height
    }
    r.x = (1 - r.width) / 2;
    r.y = (1 - r.height) / 2;
    return r;
}

HCGBGRect hcgbg_crop_from_zoom(HCGBGSize container, HCGBGSize media, double zoom, double centerX, double centerY) {
    HCGBGRect base = fill_region(container, media);
    if (!isfinite(zoom) || zoom < 1) zoom = 1;
    // Never zoom so far that a side drops below the minimum crop.
    double maxZoom = fmin(base.width, base.height) / HCGBG_CROP_MIN;
    if (maxZoom < 1) maxZoom = 1;
    zoom = fmin(zoom, fmin(maxZoom, HCGBG_ZOOM_MAX));
    HCGBGRect r = {0, 0, base.width / zoom, base.height / zoom};
    if (!isfinite(centerX)) centerX = 0.5;
    if (!isfinite(centerY)) centerY = 0.5;
    r.x = clampd(centerX - r.width / 2, 0, 1 - r.width);
    r.y = clampd(centerY - r.height / 2, 0, 1 - r.height);
    return hcgbg_crop_clamp(r);
}

double hcgbg_zoom_for_crop(HCGBGSize container, HCGBGSize media, HCGBGRect crop) {
    HCGBGRect base = fill_region(container, media);
    HCGBGRect c = hcgbg_crop_clamp(crop);
    double z = fmax(base.width / c.width, base.height / c.height);
    return isfinite(z) && z > 1 ? z : 1;
}

// ---- Playback numbers --------------------------------------------------------

unsigned hcgbg_playback_sanitize(HCGBGPlayback *p) {
    unsigned issues = HCGBGIssueNone;
    if (!p) return HCGBGIssueDurationInvalid;
    if (!finite_positive(p->duration) || p->duration > HCGBG_MAX_SOURCE_SECONDS) issues |= HCGBGIssueDurationInvalid;
    if (!isfinite(p->width) || !isfinite(p->height) || p->width < HCGBG_MIN_DIMENSION ||
        p->height < HCGBG_MIN_DIMENSION || p->width > HCGBG_MAX_DIMENSION || p->height > HCGBG_MAX_DIMENSION)
        issues |= HCGBGIssueDimensionsInvalid;
    if (!(issues & HCGBGIssueDurationInvalid) && p->duration < HCGBG_MIN_CLIP_SECONDS) issues |= HCGBGIssueClipTooShort;

    HCGBGRect crop = hcgbg_crop_clamp(p->crop);
    if (memcmp(&crop, &p->crop, sizeof crop) != 0) issues |= HCGBGIssueCropClamped;
    p->crop = crop;

    double speed = isfinite(p->speed) ? clampd(p->speed, HCGBG_SPEED_MIN, HCGBG_SPEED_MAX) : HCGBG_SPEED_DEFAULT;
    if (speed != p->speed) issues |= HCGBGIssueSpeedClamped;
    p->speed = speed;

    if (issues & (HCGBGIssueDurationInvalid | HCGBGIssueClipTooShort)) return issues;
    double d = p->duration;

    double start = p->trimStart;
    if (!isfinite(start) || start < 0) start = 0;
    if (start > d - HCGBG_MIN_CLIP_SECONDS) start = d - HCGBG_MIN_CLIP_SECONDS;
    double end = p->trimEnd;
    bool toEnd = isfinite(end) && end <= 0;
    if (!isfinite(end) || end <= 0 || end > d) end = d;
    if (end - start < HCGBG_MIN_CLIP_SECONDS) end = fmin(d, start + HCGBG_MIN_CLIP_SECONDS);
    if (end - start < HCGBG_MIN_CLIP_SECONDS) start = end - HCGBG_MIN_CLIP_SECONDS;
    if (start != p->trimStart || (!toEnd && end != p->trimEnd)) issues |= HCGBGIssueTrimClamped;
    p->trimStart = start;
    p->trimEnd = end;

    double poster = isfinite(p->posterTime) ? clampd(p->posterTime, start, end) : start;
    if (poster != p->posterTime) issues |= HCGBGIssuePosterClamped;
    p->posterTime = poster;
    return issues;
}

double hcgbg_clip_seconds(const HCGBGPlayback *p) {
    if (!p || !isfinite(p->trimStart) || !isfinite(p->trimEnd) || p->trimEnd <= p->trimStart) return 0;
    return p->trimEnd - p->trimStart;
}

// ---- GIF timing --------------------------------------------------------------

double hcgbg_gif_frame_delay(double declared) {
    if (!isfinite(declared) || declared <= 0.0105) return 0.1;
    return fmin(declared, 10.0);
}

static double even_floor(double v) {
    double e = floor(v / 2) * 2;
    return e < HCGBG_MIN_DIMENSION ? HCGBG_MIN_DIMENSION : e;
}

HCGBGSize hcgbg_even_fit(HCGBGSize source, double maxLongSide) {
    HCGBGSize out = {HCGBG_MIN_DIMENSION, HCGBG_MIN_DIMENSION};
    if (!size_ok(source)) return out;
    if (!finite_positive(maxLongSide)) maxLongSide = HCGBG_MAX_DIMENSION;
    double longSide = fmax(source.width, source.height);
    double s = longSide > maxLongSide ? maxLongSide / longSide : 1;
    out.width = even_floor(source.width * s);
    out.height = even_floor(source.height * s);
    return out;
}

// ---- Colours -------------------------------------------------------------------

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool hcgbg_parse_hex_colour(const char *text, double *r, double *g, double *b) {
    if (!text || strlen(text) != 7 || text[0] != '#') return false;
    int v[6];
    for (int i = 0; i < 6; i++) {
        v[i] = hex_digit(text[i + 1]);
        if (v[i] < 0) return false;
    }
    if (r) *r = (v[0] * 16 + v[1]) / 255.0;
    if (g) *g = (v[2] * 16 + v[3]) / 255.0;
    if (b) *b = (v[4] * 16 + v[5]) / 255.0;
    return true;
}

// ---- Orientation and transformation (kit 1.1) -------------------------------
// Additions only: nothing above this line changed, so hcgbg_layout() and the
// other functions behave exactly as in kit 1.0 (and in vendored copies).

HCGBGTransform hcgbg_transform_identity(void) {
    HCGBGTransform t = {0, false, false, false, false};
    return t;
}

bool hcgbg_transform_is_identity(HCGBGTransform t) {
    return hcgbg_rotation_normalize((double)t.rotation, NULL) == 0 && !t.flipHorizontal && !t.flipVertical && !t.stretch;
}

int hcgbg_rotation_normalize(double degrees, bool *exact) {
    if (!isfinite(degrees)) {
        if (exact) *exact = false;
        return 0;
    }
    double quarters = round(degrees / 90.0);
    if (exact) *exact = fabs(degrees / 90.0 - quarters) < 1e-9;
    long q = (long)fmod(quarters, 4.0);
    if (q < 0) q += 4;
    return (int)(q * 90);
}

int hcgbg_rotation_from_matrix(double a, double b, double c, double d, bool *mirrored) {
    if (mirrored) *mirrored = false;
    if (!isfinite(a) || !isfinite(b) || !isfinite(c) || !isfinite(d)) return -1;
    double det = a * d - b * c;
    if (fabs(fabs(det) - 1) > 1e-6) return -1; // scaled or skewed
    bool axisAligned = (fabs(a) < 1e-6 && fabs(d) < 1e-6) || (fabs(b) < 1e-6 && fabs(c) < 1e-6);
    if (!axisAligned) return -1; // not a quarter turn
    if (mirrored) *mirrored = det < 0;
    return hcgbg_rotation_normalize(atan2(b, a) * 57.29577951308232, NULL); // degrees
}

HCGBGSize hcgbg_oriented_size(HCGBGSize media, int rotation) {
    int r = hcgbg_rotation_normalize((double)rotation, NULL);
    if (r == 90 || r == 270) {
        HCGBGSize s = {media.height, media.width};
        return s;
    }
    return media;
}

HCGBGPlacement hcgbg_layout_transformed(HCGBGSize container, HCGBGSize media, HCGBGScaling scaling, HCGBGRect crop,
                                        HCGBGTransform t) {
    int rot = hcgbg_rotation_normalize((double)t.rotation, NULL);
    HCGBGSize o = hcgbg_oriented_size(media, rot);
    HCGBGPlacement p;
    memset(&p, 0, sizeof p);
    if (!size_ok(container) || !size_ok(o)) {
        p.frame = hcgbg_layout(container, media, scaling, crop);
        p.bounds.width = p.frame.width;
        p.bounds.height = p.frame.height;
        p.a = p.d = 1;
        return p;
    }
    HCGBGRect whole = {0, 0, 1, 1};
    HCGBGRect c = t.regionAllModes ? hcgbg_crop_clamp(crop) : whole;
    HCGBGRect f;
    if (t.stretch) {
        double sx = container.width / (c.width * o.width), sy = container.height / (c.height * o.height);
        f.width = o.width * sx;
        f.height = o.height * sy;
        f.x = -c.x * f.width;
        f.y = -c.y * f.height;
    } else if (scaling == HCGBGScalingFit && t.regionAllModes) {
        double s = fmin(container.width / (c.width * o.width), container.height / (c.height * o.height));
        f.width = o.width * s;
        f.height = o.height * s;
        f.x = container.width / 2 - (c.x + c.width / 2) * f.width;
        f.y = container.height / 2 - (c.y + c.height / 2) * f.height;
    } else {
        f = hcgbg_layout(container, o, scaling, crop);
    }
    p.frame = f;
    bool swap = rot == 90 || rot == 270;
    p.bounds.width = swap ? f.height : f.width;
    p.bounds.height = swap ? f.width : f.height;
    // Rotation by quarter turns (exact values), then the flips in screen axes.
    static const double kCos[4] = {1, 0, -1, 0}, kSin[4] = {0, 1, 0, -1};
    double cs = kCos[rot / 90], sn = kSin[rot / 90];
    double fx = t.flipHorizontal ? -1 : 1, fy = t.flipVertical ? -1 : 1;
    p.a = cs * fx;
    p.b = sn * fy;
    p.c = -sn * fx;
    p.d = cs * fy;
    return p;
}

HCGBGRect hcgbg_region_from_zoom(HCGBGScaling scaling, bool stretch, HCGBGSize container, HCGBGSize oriented,
                                 double zoom, double centerX, double centerY) {
    if (!stretch && scaling != HCGBGScalingFit) return hcgbg_crop_from_zoom(container, oriented, zoom, centerX, centerY);
    if (!isfinite(zoom) || zoom < 1) zoom = 1;
    zoom = fmin(zoom, HCGBG_ZOOM_MAX);
    if (!isfinite(centerX)) centerX = 0.5;
    if (!isfinite(centerY)) centerY = 0.5;
    HCGBGRect r = {0, 0, 1 / zoom, 1 / zoom};
    r.x = clampd(centerX - r.width / 2, 0, 1 - r.width);
    r.y = clampd(centerY - r.height / 2, 0, 1 - r.height);
    return hcgbg_crop_clamp(r);
}

double hcgbg_zoom_for_region(HCGBGScaling scaling, bool stretch, HCGBGSize container, HCGBGSize oriented,
                             HCGBGRect region) {
    if (!stretch && scaling != HCGBGScalingFit) return hcgbg_zoom_for_crop(container, oriented, region);
    HCGBGRect c = hcgbg_crop_clamp(region);
    double z = fmax(1 / c.width, 1 / c.height);
    return isfinite(z) && z > 1 ? z : 1;
}
