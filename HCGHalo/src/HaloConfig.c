//
//  HaloConfig.c
//  HCG Halo — Hakmi Capital Group
//

#include "HaloConfig.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    int value;
    const char *identifier;
    const char *title;
} HaloName;

static const HaloName kModes[] = {
    {HaloModeStatic, "static", "Static"},
    {HaloModeBreathing, "breathing", "Breathing"},
    {HaloModeFlow, "flow", "Colour Flow"},
    {HaloModeOrbit, "orbit", "Orbit"},
    {HaloModeCircuit, "circuit", "Sci-Fi Circuit"},
};
static const HaloName kStyles[] = {
    {HaloColourSingle, "single", "Single Colour"},
    {HaloColourMulti, "multi", "Multiple Colours"},
    {HaloColourGradient, "gradient", "Gradient"},
};
static const HaloName kLowPower[] = {
    {HaloLowPowerStatic, "static", "Static Border"},
    {HaloLowPowerAnimate, "animate", "Keep Animating"},
    {HaloLowPowerHide, "hide", "Hide Border"},
};
static const HaloName kCutout[] = {
    {HaloCutoutTrace, "trace", "Trace Notch"},
    {HaloCutoutStraight, "straight", "Straight Edge"},
};

#define COUNT(a) ((int)(sizeof(a) / sizeof((a)[0])))

static const HaloName *find_value(const HaloName *table, int count, int value) {
    for (int i = 0; i < count; i++)
        if (table[i].value == value) return &table[i];
    return NULL;
}

static int find_id(const HaloName *table, int count, const char *identifier, int *out) {
    if (!identifier) return 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(table[i].identifier, identifier) == 0) {
            *out = table[i].value;
            return 1;
        }
    }
    return 0;
}

const char *halo_mode_id(HaloMode mode) {
    const HaloName *n = find_value(kModes, COUNT(kModes), mode);
    return n ? n->identifier : "static";
}
const char *halo_mode_title(HaloMode mode) {
    const HaloName *n = find_value(kModes, COUNT(kModes), mode);
    return n ? n->title : "Static";
}
int halo_mode_from_id(const char *identifier, HaloMode *out) {
    int v;
    if (!find_id(kModes, COUNT(kModes), identifier, &v)) return 0;
    *out = (HaloMode)v;
    return 1;
}
const char *halo_colour_style_id(HaloColourStyle style) {
    const HaloName *n = find_value(kStyles, COUNT(kStyles), style);
    return n ? n->identifier : "gradient";
}
int halo_colour_style_from_id(const char *identifier, HaloColourStyle *out) {
    int v;
    if (!find_id(kStyles, COUNT(kStyles), identifier, &v)) return 0;
    *out = (HaloColourStyle)v;
    return 1;
}
const char *halo_low_power_id(HaloLowPowerPolicy policy) {
    const HaloName *n = find_value(kLowPower, COUNT(kLowPower), policy);
    return n ? n->identifier : "static";
}
int halo_low_power_from_id(const char *identifier, HaloLowPowerPolicy *out) {
    int v;
    if (!find_id(kLowPower, COUNT(kLowPower), identifier, &v)) return 0;
    *out = (HaloLowPowerPolicy)v;
    return 1;
}
const char *halo_cutout_mode_id(HaloCutoutMode mode) {
    const HaloName *n = find_value(kCutout, COUNT(kCutout), mode);
    return n ? n->identifier : "trace";
}
int halo_cutout_mode_from_id(const char *identifier, HaloCutoutMode *out) {
    int v;
    if (!find_id(kCutout, COUNT(kCutout), identifier, &v)) return 0;
    *out = (HaloCutoutMode)v;
    return 1;
}

// MARK: - Colours

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    c = (char)tolower((unsigned char)c);
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

int halo_parse_hex(const char *text, HaloRGB *out) {
    if (!text) return 0;
    if (*text == '#') text++;
    if (strlen(text) != 6) return 0;
    int v[6];
    for (int i = 0; i < 6; i++) {
        v[i] = hex_digit(text[i]);
        if (v[i] < 0) return 0;
    }
    out->r = (v[0] * 16 + v[1]) / 255.0;
    out->g = (v[2] * 16 + v[3]) / 255.0;
    out->b = (v[4] * 16 + v[5]) / 255.0;
    return 1;
}

static int channel_byte(double c) {
    if (!(c == c)) return 0;
    if (c < 0) c = 0;
    if (c > 1) c = 1;
    return (int)lround(c * 255.0);
}

void halo_format_hex(HaloRGB colour, char out[8]) {
    snprintf(out, 8, "#%02X%02X%02X", channel_byte(colour.r), channel_byte(colour.g), channel_byte(colour.b));
}

// MARK: - Appearance

HaloAppearance halo_default_appearance(void) {
    HaloAppearance a;
    memset(&a, 0, sizeof a);
    a.mode = HaloModeStatic;
    a.colourStyle = HaloColourGradient;
    // HCG signature: cyan -> indigo -> violet.
    halo_parse_hex("#00E5FF", &a.colours[0]);
    halo_parse_hex("#7B61FF", &a.colours[1]);
    halo_parse_hex("#C026FF", &a.colours[2]);
    a.colourCount = 3;
    a.brightness = 0.9;
    a.thickness = 3.0;
    a.glow = 0.5;
    a.inset = 0.0;
    a.speed = 1.0;
    a.clockwise = 1;
    a.colourRepeat = 1;
    a.segments = 2;
    a.segmentLength = 0.18;
    a.pulseDepth = 0.0;
    return a;
}

static double clamp(double v, double lo, double hi, double fallback) {
    if (!isfinite(v)) return fallback;
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static double clamp01(double v) {
    return clamp(v, 0, 1, 0);
}

HaloAppearance halo_sanitize_appearance(HaloAppearance a) {
    HaloAppearance d = halo_default_appearance();
    if ((int)a.mode < 0 || a.mode >= HaloModeCount) a.mode = d.mode;
    if ((int)a.colourStyle < 0 || a.colourStyle >= HaloColourStyleCount) a.colourStyle = d.colourStyle;
    if (a.colourCount < 1 || a.colourCount > HALO_MAX_COLOURS) {
        a.colourCount = d.colourCount;
        memcpy(a.colours, d.colours, sizeof a.colours);
    }
    for (int i = 0; i < HALO_MAX_COLOURS; i++) {
        if (i >= a.colourCount) {
            a.colours[i].r = a.colours[i].g = a.colours[i].b = 0;
            continue;
        }
        a.colours[i].r = clamp01(a.colours[i].r);
        a.colours[i].g = clamp01(a.colours[i].g);
        a.colours[i].b = clamp01(a.colours[i].b);
    }
    a.brightness = clamp(a.brightness, HALO_BRIGHTNESS_MIN, HALO_BRIGHTNESS_MAX, d.brightness);
    a.thickness = clamp(a.thickness, HALO_THICKNESS_MIN, HALO_THICKNESS_MAX, d.thickness);
    a.glow = clamp(a.glow, HALO_GLOW_MIN, HALO_GLOW_MAX, d.glow);
    a.inset = clamp(a.inset, HALO_INSET_MIN, HALO_INSET_MAX, d.inset);
    a.speed = clamp(a.speed, HALO_SPEED_MIN, HALO_SPEED_MAX, d.speed);
    a.clockwise = a.clockwise ? 1 : 0;
    a.colourRepeat = clampi(a.colourRepeat, HALO_REPEAT_MIN, HALO_REPEAT_MAX);
    a.segments = clampi(a.segments, HALO_SEGMENTS_MIN, HALO_SEGMENTS_MAX);
    a.segmentLength = clamp(a.segmentLength, HALO_SEGMENT_LENGTH_MIN, HALO_SEGMENT_LENGTH_MAX, d.segmentLength);
    a.pulseDepth = clamp(a.pulseDepth, HALO_PULSE_MIN, HALO_PULSE_MAX, d.pulseDepth);
    return a;
}

int halo_effective_colour_count(const HaloAppearance *a) {
    if (a->colourStyle == HaloColourSingle) return 1;
    return a->colourCount < 1 ? 1 : a->colourCount;
}

static HaloRGB mix(HaloRGB a, HaloRGB b, double t) {
    HaloRGB c = {a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t};
    return c;
}

int halo_gradient_stops(const HaloAppearance *a, HaloStop *out, int capacity) {
    int n = halo_effective_colour_count(a);
    int repeat = clampi(a->colourRepeat, HALO_REPEAT_MIN, HALO_REPEAT_MAX);
    if (n == 1) {
        if (capacity < 2) return 0;
        out[0].colour = out[1].colour = a->colours[0];
        out[0].location = 0;
        out[1].location = 1;
        return 2;
    }
    int bands = n * repeat;
    if (a->colourStyle == HaloColourGradient) {
        if (capacity < bands + 1) return 0;
        for (int i = 0; i <= bands; i++) {
            out[i].colour = a->colours[i % n];
            out[i].location = (double)i / bands;
        }
        return bands + 1;
    }
    // Multiple colours: solid bands with a short blend between neighbours
    // (feather = 12% of a band on each side), closed at 0 / 1.
    int count = 2 * bands + 2;
    if (capacity < count) return 0;
    double band = 1.0 / bands;
    double feather = band * 0.12;
    int k = 0;
    HaloRGB seam = mix(a->colours[(bands - 1) % n], a->colours[0], 0.5);
    out[k].colour = seam;
    out[k++].location = 0;
    for (int i = 0; i < bands; i++) {
        out[k].colour = a->colours[i % n];
        out[k++].location = i * band + feather;
        out[k].colour = a->colours[i % n];
        out[k++].location = (i + 1) * band - feather;
    }
    out[k].colour = seam;
    out[k++].location = 1;
    return k;
}

// MARK: - Timing and patterns

double halo_period(HaloMode mode, double speed) {
    speed = clamp(speed, HALO_SPEED_MIN, HALO_SPEED_MAX, 1.0);
    double base;
    switch (mode) {
    case HaloModeBreathing: base = 4.0; break;   // one inhale + exhale
    case HaloModeFlow: base = 8.0; break;        // palette travels once around
    case HaloModeOrbit: base = 6.0; break;       // a segment travels once around
    case HaloModeCircuit: base = 5.0; break;     // a pulse travels once around
    case HaloModeStatic:
    default: base = 8.0; break;
    }
    return base / speed;
}

void halo_orbit_dash(double perimeter, int segments, double fraction, double *dash, double *gap) {
    segments = clampi(segments, HALO_SEGMENTS_MIN, HALO_SEGMENTS_MAX);
    fraction = clamp(fraction, HALO_SEGMENT_LENGTH_MIN, HALO_SEGMENT_LENGTH_MAX, 0.18);
    double period = perimeter > 0 ? perimeter / segments : 0;
    *dash = period * fraction;
    *gap = period - *dash;
}

int halo_circuit_pattern(double perimeter, double thickness, double *out, int capacity, double *unitLength) {
    // Irregular "trace" rhythm in multiples of the stroke width: long runs,
    // short stubs and via-like dots, like a printed circuit.
    static const double unit[] = {14, 3, 2, 3, 34, 5, 5, 3, 2, 7, 22, 4};
    const int entries = COUNT(unit);
    *unitLength = 0;
    if (capacity < entries || !(perimeter > 0)) return 0;
    double t = clamp(thickness, HALO_THICKNESS_MIN, HALO_THICKNESS_MAX, 3.0);
    double sum = 0;
    for (int i = 0; i < entries; i++) sum += unit[i];
    sum *= t;
    double repeats = floor(perimeter / sum + 0.5);
    if (repeats < 1) repeats = 1;
    double scale = perimeter / (repeats * sum) * t;
    double total = 0;
    for (int i = 0; i < entries; i++) {
        out[i] = unit[i] * scale;
        total += out[i];
    }
    *unitLength = total;
    return entries;
}

// MARK: - Decisions

HaloRenderPlan halo_render_plan(HaloMode requested, int reduceMotion, int lowPowerMode, HaloLowPowerPolicy policy) {
    HaloRenderPlan plan;
    if ((int)requested < 0 || requested >= HaloModeCount) requested = HaloModeStatic;
    plan.mode = requested;
    plan.hidden = 0;
    plan.reason = "";
    if (lowPowerMode && policy == HaloLowPowerHide) {
        plan.hidden = 1;
        plan.animated = 0;
        plan.reason = "Low Power Mode: hidden";
        return plan;
    }
    if (requested != HaloModeStatic) {
        if (reduceMotion) {
            plan.mode = HaloModeStatic;
            plan.reason = "Reduce Motion: static";
        } else if (lowPowerMode && policy == HaloLowPowerStatic) {
            plan.mode = HaloModeStatic;
            plan.reason = "Low Power Mode: static";
        }
    }
    plan.animated = plan.mode != HaloModeStatic;
    return plan;
}

const char *halo_visibility_block(const HaloVisibilityInputs *v) {
    if (!v->enabled) return "disabled";
    if (!v->attached) return "not attached to the Home Screen";
    if (!v->screenOn) return "screen off";
    if (!v->unlocked) return "locked";
    if (!v->homeInFront) return "app in front";
    if (!v->hostVisible) return "Home Screen hidden";
    return NULL;
}
