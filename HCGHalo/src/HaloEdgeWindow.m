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

/// Root controller: only so UIKit sizes the window properly. It never asks
/// for an orientation or a status bar change; the overlay maps the border
/// from the screen's fixed coordinate space whatever the window does.
@interface HaloEdgeRootController : UIViewController
@end

@implementation HaloEdgeRootController
- (void)loadView {
    HaloPassthroughView *view = [[HaloPassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    view.userInteractionEnabled = NO;
    view.isAccessibilityElement = NO;
    view.accessibilityElementsHidden = YES;
    self.view = view;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
- (BOOL)prefersStatusBarHidden {
    return NO;
}
- (UIViewController *)childViewControllerForStatusBarStyle {
    return nil;
}
@end

@implementation HaloEdgeWindow

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
        self.rootViewController = [[HaloEdgeRootController alloc] init];
        self.hidden = YES; // shown only while the border is visible
    }
    return self;
}

- (UIView *)contentView {
    return self.rootViewController.view;
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
