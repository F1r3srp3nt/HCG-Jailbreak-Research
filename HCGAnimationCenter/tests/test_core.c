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

int main(void) {
    test_identifiers();
    test_layout();
    test_crop();
    test_playback();
    test_gif_and_colour();
    test_policy_examples();
    test_policy_exhaustive();
    test_policy_ids();
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("core tests: %d checks passed\n", checks);
    return 0;
}
