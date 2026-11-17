//
//  VortexDirectionalEffect.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexEffect.h"
#import "../src/VortexMath.h"

@implementation VortexDirectionalEffect

- (NSString *)identifier {
    return @"directional";
}

- (NSString *)displayName {
    return @"Directional";
}

- (VortexDirection)incomingDirectionForNavigation:(VortexNavigationDirection)navigation {
    VortexDirection in = VortexDirectionNone;
    vortex_builtin_directions(VortexBuiltinEffectStock, navigation, &in, NULL);
    return in;
}

- (VortexDirection)outgoingDirectionForNavigation:(VortexNavigationDirection)navigation {
    VortexDirection out = VortexDirectionNone;
    vortex_builtin_directions(VortexBuiltinEffectStock, navigation, NULL, &out);
    return out;
}

- (VortexPageVisual)visualForRole:(VortexPageRole)role
                         progress:(double)progress
                       navigation:(VortexNavigationDirection)navigation
                       parameters:(const VortexEffectParameters *)parameters {
    return vortex_directional_visual(role, progress, [self incomingDirectionForNavigation:navigation],
                                     [self outgoingDirectionForNavigation:navigation], parameters);
}

@end

@implementation VortexBuiltinDirectionalEffect

- (instancetype)initWithBuiltin:(VortexBuiltinEffect)builtin {
    if ((self = [super init])) {
        _builtin = builtin;
    }
    return self;
}

- (NSString *)identifier {
    return @(vortex_builtin_effect_to_string(self.builtin));
}

- (VortexDirection)incomingDirectionForNavigation:(VortexNavigationDirection)navigation {
    VortexDirection in = VortexDirectionNone;
    vortex_builtin_directions(self.builtin, navigation, &in, NULL);
    return in;
}

- (VortexDirection)outgoingDirectionForNavigation:(VortexNavigationDirection)navigation {
    VortexDirection out = VortexDirectionNone;
    vortex_builtin_directions(self.builtin, navigation, NULL, &out);
    return out;
}

@end

@implementation VortexStockEffect

- (instancetype)init {
    return [super initWithBuiltin:VortexBuiltinEffectStock];
}

- (NSString *)displayName {
    return @"iOS Default";
}

@end

@implementation VortexCustomDirectionalEffect

- (instancetype)initWithIncomingFrom:(VortexDirection)incoming outgoingTo:(VortexDirection)outgoing {
    if ((self = [super init])) {
        // Invalid input degrades to stock directions rather than "no motion",
        // which would leave the incoming page visible at progress 0.
        _incoming = (incoming > VortexDirectionNone && incoming < VortexDirectionCount) ? incoming : VortexDirectionNone;
        _outgoing = (outgoing > VortexDirectionNone && outgoing < VortexDirectionCount) ? outgoing : VortexDirectionNone;
    }
    return self;
}

- (NSString *)identifier {
    return @"custom";
}

- (NSString *)displayName {
    return @"Custom Directions";
}

- (VortexDirection)incomingDirectionForNavigation:(VortexNavigationDirection)navigation {
    return self.incoming != VortexDirectionNone ? self.incoming : [super incomingDirectionForNavigation:navigation];
}

- (VortexDirection)outgoingDirectionForNavigation:(VortexNavigationDirection)navigation {
    return self.outgoing != VortexDirectionNone ? self.outgoing : [super outgoingDirectionForNavigation:navigation];
}

@end
