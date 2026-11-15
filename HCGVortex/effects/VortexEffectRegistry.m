//
//  VortexEffectRegistry.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexEffect.h"

@implementation VortexEffectRegistry {
    NSMutableDictionary<NSString *, id<VortexEffect>> *_effects;
}

+ (instancetype)sharedRegistry {
    // Main-thread only (SpringBoard UI + Settings UI). Plain lazy static, no
    // dispatch_once block, by design.
    static VortexEffectRegistry *shared = nil;
    if (!shared) {
        shared = [[VortexEffectRegistry alloc] init];
    }
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _effects = [NSMutableDictionary dictionary];
        [self registerBuiltins];
    }
    return self;
}

- (void)registerBuiltins {
    [self registerEffect:[[VortexStockEffect alloc] init]];
    [self registerEffect:[[VortexReverseSlideEffect alloc] init]];
    [self registerEffect:[[VortexVerticalRiseEffect alloc] init]];
    [self registerEffect:[[VortexVerticalFallEffect alloc] init]];
    // v0.2.0 roadmap: Cube Rotation, Card Flip, Carousel, Elastic Bounce,
    // Wave Motion register here. "custom" is built per-configuration by the
    // engine because it carries user-chosen directions.
}

- (void)registerEffect:(id<VortexEffect>)effect {
    if (effect.identifier.length) _effects[effect.identifier] = effect;
}

- (id<VortexEffect>)effectForIdentifier:(NSString *)identifier {
    return identifier ? _effects[identifier] : nil;
}

- (NSArray<NSString *> *)registeredIdentifiers {
    return [_effects.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

@end
