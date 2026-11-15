//
//  VortexTypes.h
//  HCG Vortex — Hakmi Capital Group
//
//  Plain C types shared by the math core, the ObjC engine, the effects and
//  the preference bundle. Deliberately free of Foundation/UIKit so the math
//  core can be unit-tested on any host (see tests/).
//

#ifndef HCG_VORTEX_TYPES_H
#define HCG_VORTEX_TYPES_H

#ifdef __cplusplus
extern "C" {
#endif

/// Screen-space direction. Coordinates follow UIKit: +x right, +y DOWN.
/// "Up" therefore maps to (0,-1). Values are persisted as strings
/// (see vortex_direction_from_string) so the enum can be reordered/extended.
typedef enum {
    VortexDirectionNone = 0,
    VortexDirectionLeft,
    VortexDirectionRight,
    VortexDirectionUp,
    VortexDirectionDown,
    VortexDirectionUpLeft,
    VortexDirectionUpRight,
    VortexDirectionDownLeft,
    VortexDirectionDownRight,
    VortexDirectionCount
} VortexDirection;

/// Which way the user is *navigating*, independent of the visual effect.
/// Forward  = towards the page on the right in screen space (finger swipes LEFT).
/// Backward = towards the page on the left in screen space (finger swipes RIGHT).
/// Defined physically (by geometry), so it is correct for RTL layouts too.
typedef enum {
    VortexNavigationNone = 0,
    VortexNavigationForward = 1,
    VortexNavigationBackward = -1,
} VortexNavigationDirection;

/// Role a page plays in the current transition.
typedef enum {
    VortexPageRoleNone = 0,   ///< Not part of the transition (kept at its presented position).
    VortexPageRoleOutgoing,   ///< The page the transition started from.
    VortexPageRoleIncoming,   ///< The page being navigated to.
} VortexPageRole;

typedef enum {
    VortexEasingLinear = 0,
    VortexEasingEaseIn,
    VortexEasingEaseOut,
    VortexEasingEaseInOut,
    VortexEasingSine,
    VortexEasingCount,
    // Reserved for v0.2+: spring physics. Not selectable in v0.1.0.
    VortexEasingReservedSpring = 100,
} VortexEasing;

/// Built-in effects. Stored as string identifiers in preferences.
typedef enum {
    VortexBuiltinEffectStock = 0,       ///< Natural iOS motion (no visual override).
    VortexBuiltinEffectReverseSlide,
    VortexBuiltinEffectVerticalRise,
    VortexBuiltinEffectVerticalFall,
    VortexBuiltinEffectCount
} VortexBuiltinEffect;

typedef struct {
    double x;
    double y;
} VortexVec2;

/// What an effect wants a page to look like. Translation is expressed in
/// *page units* relative to the screen: x in page pitches, y in page heights.
/// (0,0) means "centred on screen". The engine converts to points and
/// compensates for the page's real (scroll-driven) position.
///
/// scale / rotationY / perspective are part of the interface for future
/// effects (v0.2.0 Cube, Card Flip, ...). The engine already composes them;
/// no v0.1.0 effect sets them to non-neutral values.
typedef struct {
    VortexVec2 translation;
    double opacity;      ///< 0..1 multiplier on the page's own opacity.
    double scale;        ///< 1 = neutral. Reserved.
    double rotationY;    ///< Radians. 0 = neutral. Reserved.
    double perspective;  ///< m34 value, 0 = none. Reserved.
} VortexPageVisual;

/// Parameters shared by all effects.
typedef struct {
    double intensity;     ///< 0.1 .. 1.0  (outgoing page travel; <1 = parallax + fade)
    double speed;         ///< 0.25 .. 4.0 (time-warp exponent on progress)
    VortexEasing easing;
    int fadePages;        ///< Bool: cross-fade incoming/outgoing.
    int reverse;          ///< Bool: invert every direction vector.
} VortexEffectParameters;

#ifdef __cplusplus
}
#endif

#endif /* HCG_VORTEX_TYPES_H */
