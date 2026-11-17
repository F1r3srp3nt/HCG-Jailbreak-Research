//
//  VerticalFall.m — Effect C
//  HCG Vortex — Hakmi Capital Group
//
//  The incoming page enters from above while the outgoing page moves down.
//  Left and right swipes are resolved independently (Directional Controls can
//  assign a different effect per swipe direction). Interrupted transitions
//  restore original layer state through -[VortexAnimationEngine restoreAll].
//

#import "VortexEffect.h"

@implementation VortexVerticalFallEffect

- (instancetype)init {
    return [super initWithBuiltin:VortexBuiltinEffectVerticalFall];
}

- (NSString *)displayName {
    return @"Vertical Fall";
}

@end
