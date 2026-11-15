//
//  VerticalRise.m — Effect B
//  HCG Vortex — Hakmi Capital Group
//
//  The incoming page rises from below while the outgoing page moves upward,
//  for BOTH swipe directions. Horizontal navigation keeps working because the
//  scroll view is never modified; the vertical motion is a pure presentation
//  transform that resolves to identity when the transition completes, so icon
//  hit-testing is exact afterwards (test: test_exactly_one_page_fully_visible…).
//
//  "Configurable duration" is provided by the engine's presentation smoothing
//  (Animation → Duration), which lets the visual transition trail the gesture.
//

#import "VortexEffect.h"

@implementation VortexVerticalRiseEffect

- (instancetype)init {
    return [super initWithBuiltin:VortexBuiltinEffectVerticalRise];
}

- (NSString *)displayName {
    return @"Vertical Rise";
}

@end
