//
//  HaloOverlayView.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloOverlayView.h"
#import "HaloRenderer.h"

#include <math.h>

@implementation HaloOverlayView {
    HaloRenderer *_renderer;
    HaloDisplayGeometry _geometry;
    BOOL _trace;
    BOOL _hasGeometry;
    CGRect _laidOutBounds;
    CGAffineTransform _laidOutTransform;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = NO;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.clipsToBounds = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.isAccessibilityElement = NO;
        self.accessibilityElementsHidden = YES;
        self.accessibilityIdentifier = @"HCGHaloOverlay";
        // Above any sibling the Home Screen window adds later; rendering order
        // only — hit-testing ignores zPosition and this view declines touches.
        self.layer.zPosition = 10000;
        CGFloat scale = UIScreen.mainScreen.scale;
        _renderer = [[HaloRenderer alloc] initWithContentsScale:scale];
        [self.layer addSublayer:_renderer.layer];
        _laidOutBounds = CGRectNull;
        _laidOutTransform = CGAffineTransformIdentity;
    }
    return self;
}

#pragma mark Never interactive

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}

- (BOOL)canBecomeFocused {
    return NO;
}

- (BOOL)canBecomeFirstResponder {
    return NO;
}

#pragma mark Configuration

- (void)setDisplayGeometry:(HaloDisplayGeometry)geometry traceCutout:(BOOL)traceCutout {
    _geometry = geometry;
    _trace = traceCutout;
    _hasGeometry = YES;
    _laidOutBounds = CGRectNull; // force a new layout
    [self relayout];
}

- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan {
    [_renderer setAppearance:appearance plan:plan];
}

- (void)setVisible:(BOOL)visible animating:(BOOL)animating {
    if (self.hidden == !visible && _renderer.paused == !(visible && animating)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.hidden = !visible;
    [_renderer setPaused:!(visible && animating)];
    [CATransaction commit];
}

- (void)teardown {
    [_renderer teardown];
    _hasGeometry = NO;
}

#pragma mark Layout

- (UIScreen *)hostScreen {
    UIWindow *window = self.window;
    if (@available(iOS 13.0, *)) {
        if (window.windowScene.screen) return window.windowScene.screen;
    }
    return UIScreen.mainScreen;
}

/// Affine transform from the screen's fixed portrait space into this view.
- (BOOL)fixedToViewTransform:(CGAffineTransform *)out fixedSize:(CGSize *)size {
    if (!self.window) return NO;
    UIScreen *screen = [self hostScreen];
    id<UICoordinateSpace> fixed = screen.fixedCoordinateSpace;
    CGPoint o = [self convertPoint:CGPointZero fromCoordinateSpace:fixed];
    CGPoint x = [self convertPoint:CGPointMake(1, 0) fromCoordinateSpace:fixed];
    CGPoint y = [self convertPoint:CGPointMake(0, 1) fromCoordinateSpace:fixed];
    CGAffineTransform t = CGAffineTransformMake(x.x - o.x, x.y - o.y, y.x - o.x, y.y - o.y, o.x, o.y);
    if (!isfinite(t.a) || !isfinite(t.b) || !isfinite(t.c) || !isfinite(t.d) || !isfinite(t.tx) || !isfinite(t.ty))
        return NO;
    *out = t;
    *size = fixed.bounds.size;
    return YES;
}

- (void)relayout {
    if (!_hasGeometry) return;
    CGAffineTransform t;
    CGSize fixedSize;
    if (![self fixedToViewTransform:&t fixedSize:&fixedSize]) return;
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, _laidOutBounds) && CGAffineTransformEqualToTransform(t, _laidOutTransform)) return;
    _laidOutBounds = bounds;
    _laidOutTransform = t;
    HaloDisplayGeometry g = _geometry;
    if (fixedSize.width > 0 && fixedSize.height > 0) {
        g.width = fixedSize.width;
        g.height = fixedSize.height;
    }
    [_renderer setGeometry:g traceCutout:_trace transform:t unitScale:1 bounds:bounds];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self relayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    _laidOutBounds = CGRectNull;
    if (self.window) [self relayout];
    [self.delegate haloOverlayViewDidChangeWindow:self];
}

@end
