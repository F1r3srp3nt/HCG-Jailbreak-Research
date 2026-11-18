//
//  Tornado.m — icons form a travelling tornado funnel
//  HCG Vortex — Hakmi Capital Group
//
//  All geometry is the tested C in src/VortexTornado.c; this class only binds
//  it to the effect interface. The page visual pins both pages to the screen
//  centre (the icons do the moving); per-icon visuals come from
//  vortex_tornado_icon(). See docs/EFFECTS.md.
//

#import "VortexEffect.h"
#import "../src/VortexMath.h"

@implementation VortexTornadoEffect

- (instancetype)initWithParameters:(VortexTornadoParameters)parameters {
    if ((self = [super init])) {
        _tornadoParameters = vortex_tornado_sanitize(parameters);
    }
    return self;
}

- (NSString *)identifier {
    return @"tornado";
}

- (NSString *)displayName {
    return @"Tornado";
}

- (VortexPageVisual)visualForRole:(VortexPageRole)role
                         progress:(double)progress
                       navigation:(VortexNavigationDirection)navigation
                       parameters:(const VortexEffectParameters *)parameters {
    return vortex_tornado_page(role, progress, parameters);
}

- (VortexIconVisual)iconVisualForRole:(VortexPageRole)role
                             progress:(double)progress
                           navigation:(VortexNavigationDirection)navigation
                                 slot:(VortexIconSlot)slot
                            pageWidth:(double)pageWidth
                           pageHeight:(double)pageHeight
                           parameters:(const VortexEffectParameters *)parameters {
    VortexTornadoParameters tp = _tornadoParameters;
    return vortex_tornado_icon(role, progress, navigation, slot, pageWidth, pageHeight, &tp, parameters);
}

- (VortexIconVisual)fallbackVisualForRole:(VortexPageRole)role
                                 progress:(double)progress
                               parameters:(const VortexEffectParameters *)parameters {
    return vortex_tornado_fallback_icon(role, progress, parameters);
}

@end
