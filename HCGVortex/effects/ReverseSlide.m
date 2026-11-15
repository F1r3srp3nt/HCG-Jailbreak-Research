//
//  ReverseSlide.m — Effect A
//  HCG Vortex — Hakmi Capital Group
//
//  The user swipes horizontally; the visual transition moves the opposite
//  way. Swiping left (forward) the next page enters from the LEFT and the
//  current page exits to the RIGHT; swiping right mirrors that.
//
//  Navigation is untouched: the scroll view still pages normally, the engine
//  only applies a compensating sublayer transform (see VortexAnimationEngine).
//  Speed / easing / interruption handling come from the shared parameters and
//  the navigation state machine (tests: test_reverse_slide_mirror,
//  test_continuity_sweep).
//

#import "VortexEffect.h"

@implementation VortexReverseSlideEffect

- (instancetype)init {
    return [super initWithBuiltin:VortexBuiltinEffectReverseSlide];
}

- (NSString *)displayName {
    return @"Reverse Slide";
}

@end
