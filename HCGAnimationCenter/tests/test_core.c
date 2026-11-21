//
//  test_core.c
//  HCG Animation Center — host unit tests for the pure C core
//  (HCGBackgroundKit's HCGBackgroundCore.c and the tweak's HACPolicy.c).
//  Built with ASan/UBSan by tests/Makefile on Linux (GCC, Clang) and macOS.
//

#include "HACPolicy.h"
#include "HCGBackgroundCore.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int checks = 0, failures = 0;

// math.h DNAN / INFINITY are float; the core works in double.
#define DNAN ((double)NAN)
#define DINF ((double)INFINITY)

#define CHECK(cond, ...)                                                   \
    do {                                                                   \
        checks++;                                                          \
        if (!(cond)) {                                                     \
            failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: %s — ", __FILE__, __LINE__, #cond); \
            fprintf(stderr, __VA_ARGS__);                                  \
            fputc('\n', stderr);                                           \
        }                                                                  \
    } while (0)

static bool near(double a, double b) {
    return fabs(a - b) < 1e-9;
}

static bool covers(HCGBGRect r, HCGBGSize c) {
    return r.x <= 1e-9 && r.y <= 1e-9 && r.x + r.width >= c.width - 1e-9 && r.y + r.height >= c.height - 1e-9;
}

static const HCGBGRect kWhole = {0, 0, 1, 1};

// ---- Scaling identifiers ------------------------------------------------------

static void test_identifiers(void) {
    HCGBGScaling s = HCGBGScalingFit;
    CHECK(strcmp(hcgbg_scaling_id(HCGBGScalingFill), "fill") == 0, "fill id");
    CHECK(strcmp(hcgbg_scaling_id(HCGBGScalingFit), "fit") == 0, "fit id");
    CHECK(strcmp(hcgbg_scaling_id(HCGBGScalingCrop), "crop") == 0, "crop id");
    CHECK(hcgbg_scaling_id((HCGBGScaling)7) == NULL, "out of range id");
    CHECK(hcgbg_scaling_parse("crop", &s) && s == HCGBGScalingCrop, "parse crop");
    CHECK(!hcgbg_scaling_parse("stretch", &s) && s == HCGBGScalingCrop, "unknown leaves value");
    CHECK(!hcgbg_scaling_parse(NULL, &s), "NULL");
    CHECK(!hcgbg_scaling_parse("Fill", &s), "case-sensitive");
}

// ---- Layout -----------------------------------------------------------------

static void test_layout(void) {
    HCGBGSize phone = {414, 896};          // iPhone 11 Pro Max, points
    HCGBGSize landscape = {1920, 1080};
    HCGBGSize portrait = {1080, 1920};
    HCGBGSize square = {500, 500};

    // Fill covers and is centred.
    HCGBGRect r = hcgbg_layout(phone, landscape, HCGBGScalingFill, kWhole);
    CHECK(covers(r, phone), "fill covers (%g %g %g %g)", r.x, r.y, r.width, r.height);
    CHECK(near(r.height, 896) && near(r.x, (414 - r.width) / 2) && near(r.y, 0), "fill centred on width");
    CHECK(near(r.width / r.height, 1920.0 / 1080.0), "fill keeps aspect");

    // Fit is inside and centred.
    r = hcgbg_layout(phone, landscape, HCGBGScalingFit, kWhole);
    CHECK(near(r.width, 414) && r.height < 896 && near(r.y, (896 - r.height) / 2), "fit letterboxes");
    r = hcgbg_layout(phone, square, HCGBGScalingFit, kWhole);
    CHECK(near(r.width, 414) && near(r.height, 414), "fit square");

    // Crop of the whole frame equals fill.
    HCGBGRect f = hcgbg_layout(phone, portrait, HCGBGScalingFill, kWhole);
    HCGBGRect c = hcgbg_layout(phone, portrait, HCGBGScalingCrop, kWhole);
    CHECK(memcmp(&f, &c, sizeof f) == 0, "crop(whole) == fill");

    // A crop of the left quarter shows that region and still covers the screen.
    HCGBGRect left = {0, 0.25, 0.25, 0.5};
    r = hcgbg_layout(phone, landscape, HCGBGScalingCrop, left);
    CHECK(covers(r, phone), "crop covers");
    // The crop is wider than the screen's aspect: its centre is shown at the screen's centre.
    CHECK(near(r.x + 0.125 * r.width, 207) && near(r.y + 0.5 * r.height, 448), "crop centred, got x=%g", r.x);
    double scale = r.width / 1920;
    CHECK(scale * 0.25 * 1920 >= 414 - 1e-9 && scale * 0.5 * 1080 >= 896 - 1e-9, "crop region covers the container");

    // Crop near the bottom-right corner is moved inside, never leaves a gap.
    HCGBGRect corner = {0.9, 0.9, 0.1, 0.1};
    r = hcgbg_layout(phone, square, HCGBGScalingCrop, corner);
    CHECK(covers(r, phone), "corner crop covers");
    // Taller than its crop allows: pinned to the bottom edge, centred horizontally on the crop.
    CHECK(near(r.y + r.height, 896) && near(r.x + 0.95 * r.width, 207), "corner crop pinned to the bottom");

    // Every crop on a grid covers the container.
    int gaps = 0;
    for (int i = 0; i <= 10; i++)
        for (int j = 0; j <= 10; j++)
            for (int k = 1; k <= 10; k++) {
                HCGBGRect g = {i / 10.0, j / 10.0, k / 10.0, k / 10.0};
                if (!covers(hcgbg_layout(phone, landscape, HCGBGScalingCrop, g), phone)) gaps++;
                if (!covers(hcgbg_layout(phone, portrait, HCGBGScalingCrop, g), phone)) gaps++;
            }
    CHECK(gaps == 0, "%d crop rectangles left gaps", gaps);

    // Degenerate input.
    HCGBGSize zero = {0, 0};
    HCGBGSize bad = {DNAN, 100};
    r = hcgbg_layout(phone, zero, HCGBGScalingFill, kWhole);
    CHECK(near(r.width, 414) && near(r.height, 896), "zero media -> container");
    r = hcgbg_layout(phone, bad, HCGBGScalingFit, kWhole);
    CHECK(near(r.width, 414), "NaN media -> container");
    r = hcgbg_layout(zero, landscape, HCGBGScalingFill, kWhole);
    CHECK(near(r.width, 0) && near(r.height, 0), "zero container -> empty");
}

static void test_crop(void) {
    HCGBGRect c = hcgbg_crop_clamp((HCGBGRect){-1, 2, 5, 0.01});
    CHECK(near(c.width, 1) && near(c.height, HCGBG_CROP_MIN) && near(c.x, 0) && near(c.y, 1 - HCGBG_CROP_MIN), "clamp");
    c = hcgbg_crop_clamp((HCGBGRect){DNAN, 0, 1, 1});
    CHECK(memcmp(&c, &kWhole, sizeof c) == 0, "NaN crop -> whole");
    c = hcgbg_crop_clamp((HCGBGRect){0, 0, DINF, 1});
    CHECK(memcmp(&c, &kWhole, sizeof c) == 0, "inf crop -> whole");

    HCGBGSize phone = {414, 896}, landscape = {1920, 1080};
    // Zoom 1 at the centre = the fill region.
    HCGBGRect z1 = hcgbg_crop_from_zoom(phone, landscape, 1, 0.5, 0.5);
    HCGBGRect f = hcgbg_layout(phone, landscape, HCGBGScalingFill, kWhole);
    HCGBGRect zl = hcgbg_layout(phone, landscape, HCGBGScalingCrop, z1);
    CHECK(fabs(f.x - zl.x) < 1e-6 && fabs(f.width - zl.width) < 1e-6, "zoom 1 == fill (%g vs %g)", f.x, zl.x);
    CHECK(near(z1.height, 1), "landscape in portrait: full height");
    // Crop region has the container's aspect in pixels.
    HCGBGRect z2 = hcgbg_crop_from_zoom(phone, landscape, 2, 0.3, 0.6);
    CHECK(fabs((z2.width * 1920) / (z2.height * 1080) - 414.0 / 896.0) < 1e-9, "aspect preserved");
    CHECK(fabs(hcgbg_zoom_for_crop(phone, landscape, z2) - 2) < 1e-9, "zoom round trip");
    // Extreme zoom is limited so no side goes below the minimum.
    HCGBGRect zx = hcgbg_crop_from_zoom(phone, landscape, 1000, 0.5, 0.5);
    CHECK(zx.width >= HCGBG_CROP_MIN - 1e-12 && zx.height >= HCGBG_CROP_MIN - 1e-12, "min crop side");
    // Centre at the edge stays inside.
    HCGBGRect ze = hcgbg_crop_from_zoom(phone, landscape, 3, 1.0, 0.0);
    CHECK(near(ze.x + ze.width, 1) && near(ze.y, 0), "edge centre clamped");
    HCGBGRect zn = hcgbg_crop_from_zoom(phone, landscape, DNAN, DNAN, DNAN);
    CHECK(near(zn.x + zn.width / 2, 0.5), "NaN zoom/centre -> centred fill");
    CHECK(hcgbg_zoom_for_crop(phone, landscape, kWhole) >= 1, "zoom >= 1");
}

// ---- Playback sanitisation --------------------------------------------------

static HCGBGPlayback playback(double duration) {
    HCGBGPlayback p = {duration, 0, 0, 1, 0, 1080, 1920, {0, 0, 1, 1}};
    return p;
}

static void test_playback(void) {
    HCGBGPlayback p = playback(12);
    unsigned issues = hcgbg_playback_sanitize(&p);
    CHECK(issues == 0, "clean preset, got %#x", issues);
    CHECK(near(p.trimEnd, 12) && near(p.trimStart, 0), "trimEnd 0 means the end");
    CHECK(near(hcgbg_clip_seconds(&p), 12), "clip length");

    p = playback(12);
    p.trimStart = 11.9;
    p.trimEnd = 11.95;
    issues = hcgbg_playback_sanitize(&p);
    CHECK(issues & HCGBGIssueTrimClamped, "short trim repaired");
    CHECK(p.trimEnd - p.trimStart >= HCGBG_MIN_CLIP_SECONDS - 1e-9 && p.trimEnd <= 12, "min clip kept (%g..%g)", p.trimStart,
          p.trimEnd);

    p = playback(12);
    p.trimStart = -3;
    p.trimEnd = 99;
    p.speed = 7;
    p.posterTime = 50;
    issues = hcgbg_playback_sanitize(&p);
    CHECK((issues & HCGBGIssueTrimClamped) && (issues & HCGBGIssueSpeedClamped) && (issues & HCGBGIssuePosterClamped),
          "issues %#x", issues);
    CHECK(near(p.trimStart, 0) && near(p.trimEnd, 12) && near(p.speed, HCGBG_SPEED_MAX) && near(p.posterTime, 12),
          "clamped values");
    CHECK(!(issues & HCGBG_FATAL_ISSUES), "repairable only");

    p = playback(12);
    p.speed = DNAN;
    p.posterTime = DNAN;
    p.crop = (HCGBGRect){0.5, 0.5, 0.9, 0.9};
    issues = hcgbg_playback_sanitize(&p);
    CHECK(near(p.speed, 1) && near(p.posterTime, 0) && (issues & HCGBGIssueCropClamped), "NaN repaired");
    CHECK(p.crop.x + p.crop.width <= 1 + 1e-12, "crop inside");

    p = playback(0);
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueDurationInvalid, "zero duration fatal");
    p = playback(DNAN);
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueDurationInvalid, "NaN duration fatal");
    p = playback(HCGBG_MAX_SOURCE_SECONDS + 1);
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueDurationInvalid, "too long fatal");
    p = playback(0.2);
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueClipTooShort, "too short fatal");
    p = playback(5);
    p.width = 8;
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueDimensionsInvalid, "tiny media fatal");
    p = playback(5);
    p.height = 9000;
    CHECK(hcgbg_playback_sanitize(&p) & HCGBGIssueDimensionsInvalid, "huge media fatal");
    CHECK(hcgbg_playback_sanitize(NULL) & HCGBGIssueDurationInvalid, "NULL");

    // Idempotent: a sanitised preset has no further issues.
    int unstable = 0;
    for (int i = 0; i < 400; i++) {
        HCGBGPlayback q = playback(0.5 + (i % 37) * 0.7);
        q.trimStart = (i % 13) - 3.0;
        q.trimEnd = (i % 17) - 2.0;
        q.speed = (i % 9) * 0.4;
        q.posterTime = (i % 11) - 1.0;
        q.crop = (HCGBGRect){(i % 5) / 4.0, (i % 7) / 6.0, (i % 3) / 2.0, (i % 4) / 3.0};
        if (hcgbg_playback_sanitize(&q) & HCGBG_FATAL_ISSUES) continue;
        HCGBGPlayback again = q;
        if (hcgbg_playback_sanitize(&again) != 0 || memcmp(&again, &q, sizeof q) != 0) unstable++;
        if (!(q.trimStart >= 0 && q.trimStart < q.trimEnd && q.trimEnd <= q.duration &&
              q.trimEnd - q.trimStart >= HCGBG_MIN_CLIP_SECONDS - 1e-9 && q.posterTime >= q.trimStart &&
              q.posterTime <= q.trimEnd))
            unstable++;
    }
    CHECK(unstable == 0, "%d sanitised presets were not stable or broke an invariant", unstable);
}

// ---- GIF and colours -----------------------------------------------------------

static void test_gif_and_colour(void) {
    CHECK(near(hcgbg_gif_frame_delay(0), 0.1), "0 -> 100 ms");
    CHECK(near(hcgbg_gif_frame_delay(0.01), 0.1), "10 ms -> 100 ms");
    CHECK(near(hcgbg_gif_frame_delay(0.02), 0.02), "20 ms kept");
    CHECK(near(hcgbg_gif_frame_delay(DNAN), 0.1), "NaN");
    CHECK(near(hcgbg_gif_frame_delay(60), 10), "max 10 s");

    HCGBGSize s = hcgbg_even_fit((HCGBGSize){481, 271}, 1080);
    CHECK(near(s.width, 480) && near(s.height, 270), "even, never upscaled: %g x %g", s.width, s.height);
    s = hcgbg_even_fit((HCGBGSize){3840, 2160}, 1920);
    CHECK(near(s.width, 1920) && near(s.height, 1080), "downscale");
    s = hcgbg_even_fit((HCGBGSize){9, 3}, 1080);
    CHECK(near(s.width, 16) && near(s.height, 16), "minimum 16");
    s = hcgbg_even_fit((HCGBGSize){DNAN, 3}, 1080);
    CHECK(near(s.width, 16), "NaN");

    double r = 0, g = 0, b = 0;
    CHECK(hcgbg_parse_hex_colour("#00E5ff", &r, &g, &b) && near(r, 0) && near(g, 229 / 255.0) && near(b, 1), "hex");
    CHECK(!hcgbg_parse_hex_colour("00E5FF", &r, &g, &b), "no #");
    CHECK(!hcgbg_parse_hex_colour("#00E5F", &r, &g, &b), "short");
    CHECK(!hcgbg_parse_hex_colour("#00E5FG", &r, &g, &b), "bad digit");
    CHECK(!hcgbg_parse_hex_colour(NULL, &r, &g, &b), "NULL");
}

// ---- Policy ------------------------------------------------------------------

static HACSurfaceInputs inputs_from_bits(unsigned bits) {
    HACSurfaceInputs in;
    memset(&in, 0, sizeof in);
    in.enabled = bits & 1;
    in.surfaceEnabled = bits & 2;
    in.assigned = bits & 4;
    in.mediaPlayable = bits & 8;
    in.stillAvailable = bits & 16;
    in.attached = bits & 32;
    in.screenOn = bits & 64;
    in.locked = bits & 128;
    in.appInFront = bits & 256;
    in.reduceMotion = bits & 512;
    in.lowPower = bits & 1024;
    in.thermalState = (bits >> 11) & 3;
    in.reduceMotionPolicy = (bits >> 13) & 1 ? HACReduceMotionPlay : HACReduceMotionStill;
    in.lowPowerPolicy = (HACLowPowerPolicy)((bits >> 14) % 3);
    return in;
}

static void test_policy_examples(void) {
    HACSurfaceInputs in = inputs_from_bits(1 | 2 | 4 | 8 | 16 | 32 | 64);
    HACDecision home = hac_decide(HACSurfaceHome, &in), lock = hac_decide(HACSurfaceLock, &in);
    CHECK(home.show == HACShowPlaying && home.visible, "home plays when unlocked and lit");
    CHECK(lock.show == HACShowPaused && !lock.visible && strcmp(lock.reason, "unlocked") == 0, "lock paused: %s", lock.reason);

    in.locked = true;
    home = hac_decide(HACSurfaceHome, &in);
    lock = hac_decide(HACSurfaceLock, &in);
    CHECK(home.show == HACShowPaused && strcmp(home.reason, "locked") == 0, "home paused when locked");
    CHECK(lock.show == HACShowPlaying, "lock plays when locked");

    in.screenOn = false;
    CHECK(hac_decide(HACSurfaceLock, &in).show == HACShowPaused, "screen off pauses");
    CHECK(strcmp(hac_decide(HACSurfaceLock, &in).reason, "screen off") == 0, "reason");

    in = inputs_from_bits(1 | 2 | 4 | 8 | 16 | 32 | 64 | 256);
    CHECK(strcmp(hac_decide(HACSurfaceHome, &in).reason, "app in front") == 0, "app in front");

    in = inputs_from_bits(1 | 2 | 4 | 8 | 16 | 32 | 64 | 512);
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowStill, "Reduce Motion -> still");
    in.reduceMotionPolicy = HACReduceMotionPlay;
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowPlaying, "Reduce Motion override plays");

    in = inputs_from_bits(1 | 2 | 4 | 8 | 16 | 32 | 64 | 1024);
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowStill, "Low Power -> still");
    in.lowPowerPolicy = HACLowPowerSystem;
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowSystem, "Low Power -> system");
    in.lowPowerPolicy = HACLowPowerPlay;
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowPlaying, "Low Power play");

    in = inputs_from_bits(1 | 2 | 4 | 16 | 32 | 64); // media not playable
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowStill, "broken media -> still");
    in.stillAvailable = false;
    HACDecision d = hac_decide(HACSurfaceHome, &in);
    CHECK(d.show == HACShowSystem && strcmp(d.reason, "video unavailable") == 0, "no still -> system");

    in = inputs_from_bits(1 | 2 | 4 | 8 | 16 | 32 | 64);
    in.thermalState = 2;
    CHECK(hac_decide(HACSurfaceHome, &in).show == HACShowStill, "serious thermal -> still");
    CHECK(hac_decide(HACSurfaceHome, NULL).show == HACShowSystem, "NULL input");
}

static void test_policy_exhaustive(void) {
    int bad = 0;
    unsigned total = 3u << 14;
    for (unsigned bits = 0; bits < total; bits++) {
        HACSurfaceInputs in = inputs_from_bits(bits);
        HACDecision home = hac_decide(HACSurfaceHome, &in);
        HACDecision lock = hac_decide(HACSurfaceLock, &in);
        HACDecision ds[2] = {home, lock};
        for (int s = 0; s < 2; s++) {
            HACDecision d = ds[s];
            if (!d.reason || !hac_show_id(d.show)) bad++;
            if (d.visible != hac_surface_visible((HACSurface)s, &in)) bad++;
            if (!in.enabled && d.show != HACShowSystem) bad++;
            if ((!in.surfaceEnabled || !in.assigned || !in.attached) && d.show != HACShowSystem) bad++;
            if (d.show == HACShowStill && !in.stillAvailable) bad++;
            if (d.show == HACShowPlaying) {
                if (!d.visible || !in.screenOn || !in.mediaPlayable) bad++;
                if (in.reduceMotion && in.reduceMotionPolicy == HACReduceMotionStill) bad++;
                if (in.lowPower && in.lowPowerPolicy != HACLowPowerPlay) bad++;
                if (in.thermalState >= HAC_THERMAL_STILL) bad++;
            }
            if (d.show == HACShowPaused && d.visible) bad++;
            // Video work happens only when every precondition holds.
            if ((d.show == HACShowPaused || d.show == HACShowPlaying) && !in.mediaPlayable) bad++;
        }
        // The two surfaces are never on screen, or playing, at the same time.
        if (home.visible && lock.visible) bad++;
        if (home.show == HACShowPlaying && lock.show == HACShowPlaying) bad++;
    }
    CHECK(bad == 0, "%d invariant violations over %u input combinations", bad, total);
    checks += (int)total - 1;
}

static void test_policy_ids(void) {
    HACReduceMotionPolicy rm = HACReduceMotionStill;
    HACLowPowerPolicy lp = HACLowPowerStill;
    CHECK(hac_reduce_motion_parse("play", &rm) && rm == HACReduceMotionPlay, "rm parse");
    CHECK(!hac_reduce_motion_parse("system", &rm), "rm has no system");
    CHECK(hac_low_power_parse("system", &lp) && lp == HACLowPowerSystem, "lp parse");
    CHECK(!hac_low_power_parse(NULL, &lp), "lp NULL");
    CHECK(strcmp(hac_low_power_id(HACLowPowerPlay), "play") == 0, "lp id");
    CHECK(hac_low_power_id((HACLowPowerPolicy)9) == NULL, "lp out of range");
    CHECK(strcmp(hac_reduce_motion_id(HACReduceMotionStill), "still") == 0, "rm id");
    CHECK(strcmp(hac_surface_id(HACSurfaceLock), "lock") == 0, "surface id");
    CHECK(strcmp(hac_show_id(HACShowPaused), "paused") == 0, "show id");
}


// ---- Orientation and transformation ---------------------------------------------

static bool near_eps(double a, double b, double eps) {
    return fabs(a - b) <= eps * fmax(1.0, fmax(fabs(a), fabs(b)));
}

/// Maps a point of the untransformed layer (relative to its centre) through the placement.
static void map_point(HCGBGPlacement p, double x, double y, double *ox, double *oy) {
    *ox = p.frame.x + p.frame.width / 2 + x * p.a + y * p.c;
    *oy = p.frame.y + p.frame.height / 2 + x * p.b + y * p.d;
}

static void test_rotation_helpers(void) {
    bool exact = false;
    CHECK(hcgbg_rotation_normalize(0, &exact) == 0 && exact, "0");
    CHECK(hcgbg_rotation_normalize(90, &exact) == 90 && exact, "90");
    CHECK(hcgbg_rotation_normalize(450, &exact) == 90 && exact, "450 -> 90");
    CHECK(hcgbg_rotation_normalize(-90, &exact) == 270 && exact, "-90 -> 270");
    CHECK(hcgbg_rotation_normalize(-360, &exact) == 0 && exact, "-360 -> 0");
    CHECK(hcgbg_rotation_normalize(100, &exact) == 90 && !exact, "100 -> 90, not exact");
    CHECK(hcgbg_rotation_normalize(135.1, &exact) == 180 && !exact, "135.1 -> 180");
    CHECK(hcgbg_rotation_normalize(DNAN, &exact) == 0 && !exact, "NaN -> 0");
    CHECK(hcgbg_rotation_normalize(DINF, NULL) == 0, "inf -> 0");

    // Video track preferred transforms (a, b, c, d) as cameras write them.
    bool mirrored = true;
    CHECK(hcgbg_rotation_from_matrix(1, 0, 0, 1, &mirrored) == 0 && !mirrored, "identity");
    CHECK(hcgbg_rotation_from_matrix(0, 1, -1, 0, &mirrored) == 90 && !mirrored, "portrait recording (90)");
    CHECK(hcgbg_rotation_from_matrix(-1, 0, 0, -1, &mirrored) == 180 && !mirrored, "upside down (180)");
    CHECK(hcgbg_rotation_from_matrix(0, -1, 1, 0, &mirrored) == 270 && !mirrored, "270");
    CHECK(hcgbg_rotation_from_matrix(-1, 0, 0, 1, &mirrored) >= 0 && mirrored, "front camera mirror reported");
    CHECK(hcgbg_rotation_from_matrix(0.7071, 0.7071, -0.7071, 0.7071, NULL) == -1, "45° is not a quarter turn");
    CHECK(hcgbg_rotation_from_matrix(2, 0, 0, 2, NULL) == -1, "scaled refused");
    CHECK(hcgbg_rotation_from_matrix(DNAN, 0, 0, 1, NULL) == -1, "NaN refused");

    HCGBGSize land = {1920, 1080};
    HCGBGSize o = hcgbg_oriented_size(land, 90);
    CHECK(near(o.width, 1080) && near(o.height, 1920), "90 swaps");
    o = hcgbg_oriented_size(land, 180);
    CHECK(near(o.width, 1920), "180 keeps");
    o = hcgbg_oriented_size(land, -90);
    CHECK(near(o.width, 1080), "-90 swaps");
    CHECK(hcgbg_transform_is_identity(hcgbg_transform_identity()), "identity is identity");
    HCGBGTransform t = hcgbg_transform_identity();
    t.rotation = 360;
    CHECK(hcgbg_transform_is_identity(t), "360 is identity");
    t.flipVertical = true;
    CHECK(!hcgbg_transform_is_identity(t), "flip is not identity");
}

static void test_transform_direction(void) {
    // A 1920×1080 landscape picture rotated 90° clockwise into a portrait screen
    // fills it exactly: its top-left corner goes to the top-RIGHT.
    HCGBGSize screen = {1080, 1920}, land = {1920, 1080};
    HCGBGTransform t = hcgbg_transform_identity();
    t.rotation = 90;
    HCGBGPlacement p = hcgbg_layout_transformed(screen, land, HCGBGScalingFill, kWhole, t);
    CHECK(near(p.frame.x, 0) && near(p.frame.y, 0) && near(p.frame.width, 1080) && near(p.frame.height, 1920),
          "90° landscape fills portrait exactly (%g %g %g %g)", p.frame.x, p.frame.y, p.frame.width, p.frame.height);
    CHECK(near(p.bounds.width, 1920) && near(p.bounds.height, 1080), "layer keeps the source shape");
    double x, y;
    map_point(p, -p.bounds.width / 2, -p.bounds.height / 2, &x, &y);
    CHECK(near(x, 1080) && near(y, 0), "top-left -> top-right (%g, %g)", x, y);
    t.rotation = 270;
    p = hcgbg_layout_transformed(screen, land, HCGBGScalingFill, kWhole, t);
    map_point(p, -p.bounds.width / 2, -p.bounds.height / 2, &x, &y);
    CHECK(near(x, 0) && near(y, 1920), "270: top-left -> bottom-left (%g, %g)", x, y);
    t.rotation = 180;
    p = hcgbg_layout_transformed(land, land, HCGBGScalingFill, kWhole, t);
    map_point(p, -960, -540, &x, &y);
    CHECK(near(x, 1920) && near(y, 1080), "180: top-left -> bottom-right");
    t.rotation = 0;
    t.flipHorizontal = true;
    p = hcgbg_layout_transformed(land, land, HCGBGScalingFill, kWhole, t);
    map_point(p, -960, -540, &x, &y);
    CHECK(near(x, 1920) && near(y, 0), "flip H: top-left -> top-right");
    t.flipHorizontal = false;
    t.flipVertical = true;
    p = hcgbg_layout_transformed(land, land, HCGBGScalingFill, kWhole, t);
    map_point(p, -960, -540, &x, &y);
    CHECK(near(x, 0) && near(y, 1080), "flip V: top-left -> bottom-left");
    // Flips act in screen axes AFTER rotation: 90° + flip H moves top-left to top-left.
    t.rotation = 90;
    t.flipVertical = false;
    t.flipHorizontal = true;
    p = hcgbg_layout_transformed(screen, land, HCGBGScalingFill, kWhole, t);
    map_point(p, -p.bounds.width / 2, -p.bounds.height / 2, &x, &y);
    CHECK(near(x, 0) && near(y, 0), "90° then flip H: top-left stays top-left (%g, %g)", x, y);

    // Stretch: exactly the container, whatever the aspect.
    t = hcgbg_transform_identity();
    t.stretch = true;
    HCGBGSize ultra = {3840, 1080};
    p = hcgbg_layout_transformed(screen, ultra, HCGBGScalingFill, kWhole, t);
    CHECK(near(p.frame.x, 0) && near(p.frame.y, 0) && near(p.frame.width, 1080) && near(p.frame.height, 1920), "stretch");
    // Stretch with a region: the region maps exactly onto the container.
    t.regionAllModes = true;
    HCGBGRect region = {0.25, 0.1, 0.5, 0.8};
    p = hcgbg_layout_transformed(screen, ultra, HCGBGScalingFill, region, t);
    CHECK(near(p.frame.x + 0.25 * p.frame.width, 0) && near(p.frame.x + 0.75 * p.frame.width, 1080) &&
              near(p.frame.y + 0.1 * p.frame.height, 0) && near(p.frame.y + 0.9 * p.frame.height, 1920),
          "stretch region -> container");
    // Fit with a region: the region is inside, touching one axis, centred.
    t.stretch = false;
    p = hcgbg_layout_transformed(screen, ultra, HCGBGScalingFit, region, t);
    double rx0 = p.frame.x + 0.25 * p.frame.width, rx1 = p.frame.x + 0.75 * p.frame.width;
    double ry0 = p.frame.y + 0.1 * p.frame.height, ry1 = p.frame.y + 0.9 * p.frame.height;
    CHECK(rx0 >= -1e-6 && rx1 <= 1080 + 1e-6 && ry0 >= -1e-6 && ry1 <= 1920 + 1e-6, "fit region inside");
    CHECK(near(rx1 - rx0, 1080) || near(ry1 - ry0, 1920), "fit region touches an edge");
    CHECK(near((rx0 + rx1) / 2, 540) && near((ry0 + ry1) / 2, 960), "fit region centred");
}

static void test_transform_exhaustive(void) {
    const HCGBGSize media[] = {
        {1080, 1920}, {1920, 1080}, {1080, 1080}, {2560, 1080}, {3840, 1080}, {1080, 3840},
        {4096, 2160}, {7680, 4320}, {16, 8192}, {8192, 16}, {641, 359},
    };
    const HCGBGSize containers[] = {{414, 896}, {896, 414}, {375, 812}, {1024, 1366}, {1179, 2556}, {1500, 500}};
    const HCGBGRect crops[] = {{0, 0, 1, 1}, {0.2, 0.3, 0.5, 0.4}, {0.9, 0.9, 0.1, 0.1}, {0, 0.6, 0.3, 0.4}};
    int bad = 0, cases = 0;
    for (size_t m = 0; m < sizeof media / sizeof media[0]; m++)
        for (size_t k = 0; k < sizeof containers / sizeof containers[0]; k++)
            for (int rot = -90; rot <= 450; rot += 90)
                for (int flips = 0; flips < 4; flips++)
                    for (int sc = 0; sc < 3; sc++)
                        for (int stretch = 0; stretch < 2; stretch++)
                            for (int region = 0; region < 2; region++)
                                for (size_t q = 0; q < sizeof crops / sizeof crops[0]; q++) {
                                    cases++;
                                    HCGBGSize md = media[m], ct = containers[k];
                                    HCGBGTransform t = {rot, flips & 1, (flips & 2) != 0, stretch, region};
                                    HCGBGPlacement p = hcgbg_layout_transformed(ct, md, (HCGBGScaling)sc, crops[q], t);
                                    int r = hcgbg_rotation_normalize(rot, NULL);
                                    HCGBGSize o = hcgbg_oriented_size(md, r);
                                    // Matrix: a signed permutation, determinant = product of the flips.
                                    double det = p.a * p.d - p.b * p.c;
                                    double fdet = ((flips & 1) ? -1 : 1) * ((flips & 2) ? -1 : 1);
                                    if (!near(det, fdet)) bad++;
                                    // Bounds = frame, swapped for quarter turns; mapped corners give the frame back.
                                    bool swap = r == 90 || r == 270;
                                    if (!near(p.bounds.width, swap ? p.frame.height : p.frame.width)) bad++;
                                    double minx = DINF, maxx = -DINF, miny = DINF, maxy = -DINF;
                                    for (int c = 0; c < 4; c++) {
                                        double x, y;
                                        map_point(p, (c & 1 ? 0.5 : -0.5) * p.bounds.width, (c & 2 ? 0.5 : -0.5) * p.bounds.height,
                                                  &x, &y);
                                        minx = fmin(minx, x), maxx = fmax(maxx, x), miny = fmin(miny, y), maxy = fmax(maxy, y);
                                    }
                                    if (!near_eps(minx, p.frame.x, 1e-9) || !near_eps(maxx, p.frame.x + p.frame.width, 1e-9) ||
                                        !near_eps(miny, p.frame.y, 1e-9) || !near_eps(maxy, p.frame.y + p.frame.height, 1e-9))
                                        bad++;
                                    if (stretch) {
                                        HCGBGRect c = region ? hcgbg_crop_clamp(crops[q]) : kWhole;
                                        if (!near_eps(p.frame.x + c.x * p.frame.width, 0, 1e-9) ||
                                            !near_eps(p.frame.x + (c.x + c.width) * p.frame.width, ct.width, 1e-9) ||
                                            !near_eps(p.frame.y + (c.y + c.height) * p.frame.height, ct.height, 1e-9))
                                            bad++;
                                        continue;
                                    }
                                    // Not stretched: the oriented aspect is kept.
                                    if (!near_eps(p.frame.width / p.frame.height, o.width / o.height, 1e-9)) bad++;
                                    if (sc != HCGBGScalingFit && !covers(p.frame, ct)) bad++;
                                    if (sc == HCGBGScalingFit && !region &&
                                        (p.frame.x < -1e-6 || p.frame.y < -1e-6 || p.frame.x + p.frame.width > ct.width + 1e-6 ||
                                         p.frame.y + p.frame.height > ct.height + 1e-6))
                                        bad++;
                                    // No transform → exactly the 1.0 layout and an identity matrix.
                                    if (r == 0 && flips == 0 && !region) {
                                        HCGBGRect old = hcgbg_layout(ct, md, (HCGBGScaling)sc, crops[q]);
                                        if (memcmp(&old, &p.frame, sizeof old) != 0 || p.a != 1 || p.d != 1 || p.b != 0 || p.c != 0) bad++;
                                    }
                                }
    CHECK(bad == 0, "%d transform invariant violations over %d layouts", bad, cases);
    checks += cases - 1;

    // Zoom / position round trips in every mode, on the oriented frame.
    int rt = 0;
    for (size_t m = 0; m < sizeof media / sizeof media[0]; m++)
        for (int sc = 0; sc < 3; sc++)
            for (int stretch = 0; stretch < 2; stretch++)
                for (int zi = 0; zi < 5; zi++) {
                    double zoom = 1 + zi * 0.75;
                    HCGBGSize o = hcgbg_oriented_size(media[m], 90);
                    HCGBGRect r = hcgbg_region_from_zoom((HCGBGScaling)sc, stretch, containers[0], o, zoom, 0.3, 0.7);
                    if (r.x < -1e-12 || r.y < -1e-12 || r.x + r.width > 1 + 1e-12 || r.y + r.height > 1 + 1e-12) rt++;
                    // Beyond ~10:1 against the screen, the 1.0 minimum crop side (HCGBG_CROP_MIN)
                    // makes the region wider than a fill would show; the region is still valid
                    // (checked above) but zoom is not recoverable from it, as in 1.0.
                    double oa = o.width / o.height, ca = containers[0].width / containers[0].height;
                    if (!stretch && sc != HCGBGScalingFit && fmin(oa / ca, ca / oa) < HCGBG_CROP_MIN) continue;
                    double back = hcgbg_zoom_for_region((HCGBGScaling)sc, stretch, containers[0], o, r);
                    HCGBGRect again = hcgbg_region_from_zoom((HCGBGScaling)sc, stretch, containers[0], o, back,
                                                             r.x + r.width / 2, r.y + r.height / 2);
                    if (fabs(again.x - r.x) > 1e-9 || fabs(again.width - r.width) > 1e-9) rt++;
                }
    CHECK(rt == 0, "%d zoom/region round-trip failures", rt);
    HCGBGRect deg = hcgbg_region_from_zoom(HCGBGScalingFit, false, containers[0], media[0], DNAN, DNAN, DNAN);
    CHECK(near(deg.width, 1) && near(deg.x, 0), "NaN zoom -> whole frame");
    HCGBGSize zero = {0, 0};
    HCGBGPlacement z = hcgbg_layout_transformed(containers[0], zero, HCGBGScalingFill, kWhole, hcgbg_transform_identity());
    CHECK(near(z.frame.width, 414) && z.a == 1 && z.d == 1, "degenerate media -> container, identity");
}

int main(void) {
    test_identifiers();
    test_layout();
    test_crop();
    test_playback();
    test_gif_and_colour();
    test_policy_examples();
    test_policy_exhaustive();
    test_policy_ids();
    test_rotation_helpers();
    test_transform_direction();
    test_transform_exhaustive();
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("core tests: %d checks passed\n", checks);
    return 0;
}
