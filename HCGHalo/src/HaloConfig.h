//
//  HaloConfig.h
//  HCG Halo — Hakmi Capital Group
//
//  Pure C (no Apple frameworks; unit-tested on the build host). The single
//  definition of every appearance value's identifier, default and valid
//  range, and of the decisions that do not need UIKit:
//    * colour stops for the gradient (single / multiple / gradient),
//    * dash patterns for Orbit and Sci-Fi Circuit,
//    * animation periods,
//    * which mode actually renders (Reduce Motion, Low Power Mode),
//    * whether the overlay should be drawing at all (visibility).
//
//  HaloPreferences.m maps these to the preference plist; the Settings bundle
//  and the SpringBoard tweak both compile this file, so they cannot disagree.
//

#ifndef HALO_CONFIG_H
#define HALO_CONFIG_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    HaloModeStatic = 0,
    HaloModeBreathing = 1,
    HaloModeFlow = 2,
    HaloModeOrbit = 3,
    HaloModeCircuit = 4,
    HaloModeCount
} HaloMode;

typedef enum {
    HaloColourSingle = 0,   // one colour
    HaloColourMulti = 1,    // several distinct colours in bands
    HaloColourGradient = 2, // several colours blended smoothly
    HaloColourStyleCount
} HaloColourStyle;

typedef enum {
    HaloLowPowerStatic = 0,  // show the border, without animation (default)
    HaloLowPowerAnimate = 1, // ignore Low Power Mode
    HaloLowPowerHide = 2,    // hide the border while Low Power Mode is on
    HaloLowPowerPolicyCount
} HaloLowPowerPolicy;

typedef enum {
    HaloCutoutTrace = 0,    // light follows the notch outline
    HaloCutoutStraight = 1, // light runs straight along the top edge behind the notch
    HaloCutoutModeCount
} HaloCutoutMode;

/// Where the SCREEN-EDGE border is shown ("Show Halo on"). The HCG Nexus
/// panel border never uses this: it follows the panel's own visibility.
typedef enum {
    HaloShowOnHome = 0,            // Home Screen only (default; the 0.1.0 / 0.2.0 behaviour)
    HaloShowOnApp = 1,             // only while the chosen app is in front
    HaloShowOnAlways = 2,          // every lit surface: Lock Screen, Home Screen, apps
    HaloShowOnExceptLock = 3,      // Home Screen and apps; hidden whenever the phone is locked
    HaloShowOnExceptScreenOff = 4, // like Always, stated explicitly: hidden and paused when the display is off
    HaloShowOnCount
} HaloShowOn;

typedef struct {
    double r, g, b; // 0...1, sRGB
} HaloRGB;

#define HALO_MAX_COLOURS 6

// Valid ranges (inclusive). Settings sliders use the same values.
#define HALO_BRIGHTNESS_MIN 0.10
#define HALO_BRIGHTNESS_MAX 1.00
#define HALO_THICKNESS_MIN 1.0
#define HALO_THICKNESS_MAX 12.0
#define HALO_GLOW_MIN 0.0
#define HALO_GLOW_MAX 1.0
#define HALO_INSET_MIN 0.0
#define HALO_INSET_MAX 20.0
#define HALO_SPEED_MIN 0.25
#define HALO_SPEED_MAX 3.0
#define HALO_REPEAT_MIN 1
#define HALO_REPEAT_MAX 4
#define HALO_SEGMENTS_MIN 1
#define HALO_SEGMENTS_MAX 4
#define HALO_SEGMENT_LENGTH_MIN 0.05
#define HALO_SEGMENT_LENGTH_MAX 0.45
#define HALO_PULSE_MIN 0.0
#define HALO_PULSE_MAX 0.6

/// Everything a preset captures. Device profile, calibration, the master
/// switch and the Low Power policy are deliberately NOT part of a preset.
typedef struct {
    HaloMode mode;
    HaloColourStyle colourStyle;
    int colourCount;
    HaloRGB colours[HALO_MAX_COLOURS];
    double brightness;    // peak opacity of the light
    double thickness;     // stroke width of the core line (pt)
    double glow;          // 0 = none, 1 = strongest halo
    double inset;         // gap between the display edge and the core line (pt)
    double speed;         // animation speed multiplier
    int clockwise;        // movement direction (1 = clockwise on screen)
    int colourRepeat;     // colour spacing: how many times the palette repeats around the perimeter
    int segments;         // Orbit: travelling segments; Circuit: pulse groups
    double segmentLength; // Orbit: lit fraction of each segment's period
    double pulseDepth;    // soft brightness pulse on top of an animated mode (0 = none)
} HaloAppearance;

/// Identifiers stored in the preference plist.
const char *halo_mode_id(HaloMode mode);
const char *halo_mode_title(HaloMode mode);
int halo_mode_from_id(const char *identifier, HaloMode *out);
const char *halo_colour_style_id(HaloColourStyle style);
int halo_colour_style_from_id(const char *identifier, HaloColourStyle *out);
const char *halo_low_power_id(HaloLowPowerPolicy policy);
int halo_low_power_from_id(const char *identifier, HaloLowPowerPolicy *out);
const char *halo_cutout_mode_id(HaloCutoutMode mode);
int halo_cutout_mode_from_id(const char *identifier, HaloCutoutMode *out);
const char *halo_show_on_id(HaloShowOn showOn);
const char *halo_show_on_title(HaloShowOn showOn);
int halo_show_on_from_id(const char *identifier, HaloShowOn *out);
/// 1 if the policy can draw over apps or the Lock Screen (so it needs Halo's own
/// overlay window instead of the Home Screen window).
int halo_show_on_uses_overlay_window(HaloShowOn showOn);
/// 1 if the policy can draw on the lit Lock Screen.
int halo_show_on_includes_lock_screen(HaloShowOn showOn);

/// "#RRGGBB" or "RRGGBB" (case-insensitive). Returns 1 on success.
int halo_parse_hex(const char *text, HaloRGB *out);
/// Writes "#RRGGBB" (8 bytes including the terminator).
void halo_format_hex(HaloRGB colour, char out[8]);

HaloAppearance halo_default_appearance(void);
/// Clamps every value into range; replaces invalid enums with defaults.
HaloAppearance halo_sanitize_appearance(HaloAppearance appearance);
/// Number of colours actually used (1 for the single-colour style).
int halo_effective_colour_count(const HaloAppearance *appearance);

/// One colour stop of the conic gradient around the perimeter.
typedef struct {
    HaloRGB colour;
    double location; // 0...1, increasing
} HaloStop;

#define HALO_MAX_STOPS 64

/// Colour stops for the gradient, as a closed loop (the colour at 1.0 equals
/// the colour at 0.0, so a rotating gradient has no seam). Returns the
/// number of stops (>= 2), or 0 if capacity is too small.
int halo_gradient_stops(const HaloAppearance *appearance, HaloStop *out, int capacity);

/// Seconds for one full animation cycle of `mode` at `speed` (> 0 always).
double halo_period(HaloMode mode, double speed);

/// Orbit dash pattern: `segments` lit dashes evenly spaced on a loop of
/// length `perimeter`; dash + gap == perimeter / segments exactly.
void halo_orbit_dash(double perimeter, int segments, double fraction, double *dash, double *gap);

/// Sci-Fi Circuit "trace" pattern: an irregular dash pattern (even count,
/// alternating dash, gap), scaled so a whole number of repeats fits the
/// perimeter exactly. Returns the entry count; *unitLength is the pattern's
/// total length (the distance the phase travels for a seamless loop).
int halo_circuit_pattern(double perimeter, double thickness, double *out, int capacity, double *unitLength);

/// What actually renders after accessibility and power policies.
typedef struct {
    HaloMode mode;      // mode to draw (static when animation is suppressed)
    int animated;       // 1 if the drawn mode has running animations
    int hidden;         // 1 if nothing should be drawn
    const char *reason; // why the plan differs from the request, or "" if it does not
} HaloRenderPlan;

HaloRenderPlan halo_render_plan(HaloMode requested, int reduceMotion, int lowPowerMode, HaloLowPowerPolicy policy);

/// Inputs for the "should the overlay draw now?" decision.
typedef struct {
    int enabled;      // master switch on
    int attached;     // overlay is in its host window
    int screenOn;     // display not blanked
    int unlocked;     // device not locked (Lock Screen / Cover Sheet not up)
    int homeInFront;  // no app (or other full-screen display item) in front of the Home Screen
    int hostVisible;  // the host window is not hidden
} HaloVisibilityInputs;

/// NULL if the overlay should draw; otherwise a short reason it should not.
/// The Home Screen Only policy (the 0.2.0 rules).
const char *halo_visibility_block(const HaloVisibilityInputs *inputs);

/// The same decision for every "Show Halo on" policy.
typedef struct {
    HaloVisibilityInputs base;
    HaloShowOn showOn;
    int appChosen;            // Selected App Only: an app is chosen
    int frontAppKnown;        // the front app can be detected (the SpringBoard hook is installed)
    int chosenAppInFront;     // the chosen app is the app in front
} HaloSurfaceInputs;

/// NULL if the screen-edge border should draw; otherwise a short reason.
/// Every policy hides it while the display is off: a dark display cannot show
/// a border, and a hidden overlay is also paused (no rendering work).
const char *halo_surface_block(const HaloSurfaceInputs *inputs);

#ifdef __cplusplus
}
#endif

#endif /* HALO_CONFIG_H */
