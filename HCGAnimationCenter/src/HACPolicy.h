//
//  HACPolicy.h
//  HCG Animation Center — Hakmi Capital Group
//
//  What each surface (Home Screen, Lock Screen) shows, decided from plain
//  inputs. Pure C: the SpringBoard controller gathers the inputs, this file
//  decides, and tests/test_core.c checks every combination on Linux.
//
//  Outcomes, from least to most work:
//    system  — HCG Animation Center draws nothing; the normal wallpaper shows
//    still   — the preset's static fallback image (no video decoder)
//    paused  — the video's current frame, rate 0 (surface hidden)
//    playing — the video plays
//

#ifndef HAC_POLICY_H
#define HAC_POLICY_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    HACSurfaceHome = 0,
    HACSurfaceLock = 1,
} HACSurface;
#define HAC_SURFACE_COUNT 2

typedef enum {
    HACShowSystem = 0,
    HACShowStill = 1,
    HACShowPaused = 2,
    HACShowPlaying = 3,
} HACShow;

/// Reduce Motion: show the still (default) or keep playing.
typedef enum {
    HACReduceMotionStill = 0,
    HACReduceMotionPlay = 1,
} HACReduceMotionPolicy;

/// Low Power Mode: show the still (default), keep playing, or hand back to
/// the system wallpaper.
typedef enum {
    HACLowPowerStill = 0,
    HACLowPowerPlay = 1,
    HACLowPowerSystem = 2,
} HACLowPowerPolicy;

typedef struct {
    bool enabled;         ///< master switch on, not faulted, not blocked
    bool surfaceEnabled;  ///< this surface is switched on (Lock Screen has its own switch)
    bool assigned;        ///< a valid preset is assigned to this surface
    bool mediaPlayable;   ///< the media file exists and has not failed to play
    bool stillAvailable;  ///< the static fallback image loaded
    bool attached;        ///< the surface's view is in SpringBoard's hierarchy
    bool screenOn;
    bool locked;
    bool appInFront;      ///< an app covers the Home Screen (Home only)
    bool reduceMotion;
    bool lowPower;
    int thermalState;     ///< 0 nominal, 1 fair, 2 serious, 3 critical
    HACReduceMotionPolicy reduceMotionPolicy;
    HACLowPowerPolicy lowPowerPolicy;
} HACSurfaceInputs;

typedef struct {
    HACShow show;
    bool visible;        ///< the surface is on screen now
    const char *reason;  ///< short English phrase for Settings, never NULL
} HACDecision;

/// Thermal state at or above which video stops (serious).
#define HAC_THERMAL_STILL 2
/// Seconds a surface may stay hidden before its video player is released
/// (the still and the preset stay; playback resumes from the clip start).
#define HAC_RELEASE_HIDDEN_AFTER_SECONDS 8.0

/// Whether the surface is on screen: Home — lit, unlocked, no app in front;
/// Lock — lit and locked.
bool hac_surface_visible(HACSurface surface, const HACSurfaceInputs *in);

HACDecision hac_decide(HACSurface surface, const HACSurfaceInputs *in);

const char *hac_show_id(HACShow show);
const char *hac_surface_id(HACSurface surface);

/// "still" | "play"  and  "still" | "play" | "system"; NULL if out of range.
const char *hac_reduce_motion_id(HACReduceMotionPolicy policy);
const char *hac_low_power_id(HACLowPowerPolicy policy);
bool hac_reduce_motion_parse(const char *identifier, HACReduceMotionPolicy *out);
bool hac_low_power_parse(const char *identifier, HACLowPowerPolicy *out);

#ifdef __cplusplus
}
#endif

#endif
