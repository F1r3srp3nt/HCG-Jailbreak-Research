//
//  HaloEdgeWindow.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloEdgeWindow.h"

/// Fills the window; never takes a touch.
@interface HaloPassthroughView : UIView
@end

@implementation HaloPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}
@end

@implementation HaloEdgeWindow {
    HaloPassthroughView *_content;
}

- (instancetype)initForScene:(UIWindowScene *)scene {
    if ((self = [super initWithWindowScene:scene])) {
        self.frame = scene.screen.bounds;
        self.windowLevel = HALO_EDGE_WINDOW_LEVEL;
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.isAccessibilityElement = NO;
        self.accessibilityElementsHidden = YES;
        self.accessibilityIdentifier = @"HCGHaloEdgeWindow";
        // The content view is a direct subview, so the overlay is in this window (view.window
        // is set) even while the window is hidden. A root view controller's view would only be
        // installed when the window is first shown, and the window is shown only once the border
        // is attached: the overlay would never count as attached. Without a root view
        // controller the window also never takes part in rotation or status-bar decisions; the
        // overlay maps the border from the screen's fixed coordinate space itself.
        _content = [[HaloPassthroughView alloc] initWithFrame:self.bounds];
        _content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _content.backgroundColor = UIColor.clearColor;
        _content.opaque = NO;
        _content.userInteractionEnabled = NO;
        _content.isAccessibilityElement = NO;
        _content.accessibilityElementsHidden = YES;
        [self addSubview:_content];
        self.hidden = YES; // shown only while the border is visible
    }
    return self;
}

- (UIView *)contentView {
    return _content;
}

#pragma mark Never interactive, never key

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (void)makeKeyWindow {
    // Never key: the overlay must not take focus or keyboard input.
}

#pragma mark Private UIKit hooks (overrides only; harmless if UIKit stops calling them)

- (BOOL)_canBecomeKeyWindow {
    return NO;
}

- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}

- (BOOL)_ignoresHitTest {
    return YES;
}

// Shown above the Lock Screen (a SpringBoard window must be secure to be
// rendered while the device is locked).
- (BOOL)_shouldCreateContextAsSecure {
    return YES;
}

+ (BOOL)_isSecure {
    return YES;
}

- (BOOL)_isSecure {
    return YES;
}

@end
