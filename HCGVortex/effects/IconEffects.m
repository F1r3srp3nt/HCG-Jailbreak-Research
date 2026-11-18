//
//  IconEffects.m — Tornado, Orbital, Warp, Holographic Layers, Circuit Flow, Magnetic Grid
//  HCG Vortex — Hakmi Capital Group
//
//  All geometry is the tested C in src/VortexIconEffects.c (and
//  src/VortexTornado.c); this class only binds it to the effect interface.
//  See docs/EFFECTS.md.
//

#import "VortexEffect.h"
#import "../src/VortexMath.h"

@implementation VortexGeometricEffect {
    NSString *_identifier;
    NSString *_displayName;
}

- (instancetype)initWithKind:(VortexIconEffectKind)kind
                  identifier:(NSString *)identifier
                 displayName:(NSString *)displayName
                    settings:(VortexIconEffectSettings)settings {
    if ((self = [super init])) {
        _kind = kind;
        _identifier = [identifier copy];
        _displayName = [displayName copy];
        _settings = vortex_icon_settings_sanitize(settings);
    }
    return self;
}

- (NSString *)identifier {
    return _identifier;
}

- (NSString *)displayName {
    return _displayName;
}

- (VortexPageVisual)visualForRole:(VortexPageRole)role
                         progress:(double)progress
                       navigation:(VortexNavigationDirection)navigation
                       parameters:(const VortexEffectParameters *)parameters {
    return vortex_icon_effect_page(_kind, role, progress, navigation, parameters);
}

- (VortexIconVisual)iconVisualForRole:(VortexPageRole)role
                             progress:(double)progress
                           navigation:(VortexNavigationDirection)navigation
                                 slot:(VortexIconSlot)slot
                            pageWidth:(double)pageWidth
                           pageHeight:(double)pageHeight
                           parameters:(const VortexEffectParameters *)parameters {
    VortexIconEffectSettings s = _settings;
    return vortex_icon_effect_visual(_kind, role, progress, navigation, slot, pageWidth, pageHeight, &s, parameters);
}

- (VortexIconVisual)fallbackVisualForRole:(VortexPageRole)role
                                 progress:(double)progress
                               parameters:(const VortexEffectParameters *)parameters {
    return vortex_icon_effect_fallback(_kind, role, progress, parameters);
}

- (BOOL)pinsPages {
    return vortex_icon_effect_pins_pages(_kind) ? YES : NO;
}

- (VortexTrace)traceForRole:(VortexPageRole)role
                   progress:(double)progress
                 navigation:(VortexNavigationDirection)navigation
                       slot:(VortexIconSlot)slot
                  pageWidth:(double)pageWidth
                 pageHeight:(double)pageHeight
                 parameters:(const VortexEffectParameters *)parameters {
    VortexIconEffectSettings s = _settings;
    return vortex_icon_effect_trace(_kind, role, progress, navigation, slot, pageWidth, pageHeight, &s, parameters);
}

@end
