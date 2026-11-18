//
//  HaloPanelBorderView.m
//  HCG Halo — Hakmi Capital Group
//
//  Layers:   self.layer (mask: everything except the panel interior)
//            ├─ _base   (opacity animated by the opening trace to "settle")
//            │   └─ renderer.layer   (the selected mode, HaloRenderer)
//            ├─ _traceGlow, _traceCore   (opening trace; idle when not tracing)
//            └─ _pulse                   (workspace pulse; idle otherwise)
//

#import "HaloPanelBorderView.h"
#import "HaloNexusDefinition.h"

#include <math.h>

static NSString *const kTraceKey = @"halo.trace";
static NSString *const kSettleKey = @"halo.settle";
static NSString *const kPulseKey = @"halo.workspace-pulse";

@implementation HaloPanelBorderView {
    HaloNexusDefinition *_definition;
    HaloRenderer *_renderer;
    CALayer *_base;
    CAShapeLayer *_traceGlow;
    CAShapeLayer *_traceCore;
    CAShapeLayer *_pulse;
    CAShapeLayer *_mask;
    HaloAppearance _appearance;
    HaloRenderPlan _plan;
    BOOL _hasAppearance;
    BOOL _reduceTransparency;
    CGRect _laidOutHostBounds;
    CGFloat _laidOutRadius;
    double _laidOutThickness;
    CGPathRef _path;
}

- (instancetype)initWithDefinition:(HaloNexusDefinition *)definition {
    if ((self = [super initWithFrame:CGRectZero])) {
        _definition = definition;
        self.userInteractionEnabled = NO;
        self.isAccessibilityElement = NO;
        self.accessibilityElementsHidden = YES;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.clipsToBounds = NO;
        self.accessibilityIdentifier = @"HCGHaloNexusBorder";
        CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 2;
        _renderer = [[HaloRenderer alloc] initWithContentsScale:scale];
        _base = [CALayer layer];
        _base.contentsScale = scale;
        [_base addSublayer:_renderer.layer];
        [self.layer addSublayer:_base];
        _traceGlow = [self effectLayer:scale];
        _traceCore = [self effectLayer:scale];
        _pulse = [self effectLayer:scale];
        _laidOutHostBounds = CGRectNull;
        _active = YES;
    }
    return self;
}

- (void)dealloc {
    if (_path) CGPathRelease(_path);
}

- (CAShapeLayer *)effectLayer:(CGFloat)scale {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.contentsScale = scale;
    layer.fillColor = nil;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;
    layer.hidden = YES;
    [self.layer addSublayer:layer];
    return layer;
}

- (HaloNexusDefinition *)definition {
    return _definition;
}

- (HaloRenderer *)renderer {
    return _renderer;
}

#pragma mark Never interactive

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}

#pragma mark Layout

- (void)attachToHostView:(UIView *)host {
    if (self.superview != host) [host addSubview:self];
    _laidOutHostBounds = CGRectNull;
    [self relayout];
}

- (void)setPanelCornerRadius:(CGFloat)panelCornerRadius {
    _panelCornerRadius = panelCornerRadius;
    _laidOutHostBounds = CGRectNull;
    [self relayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self relayout];
}

- (CGFloat)effectiveRadius {
    return _panelCornerRadius > 0 ? _panelCornerRadius : (CGFloat)_definition.cornerRadius;
}

- (void)relayout {
    UIView *host = self.superview;
    if (!host || !_hasAppearance) return;
    CGRect hostBounds = host.bounds;
    if (CGRectIsEmpty(hostBounds)) return;
    CGFloat radius = [self effectiveRadius];
    double thickness = _appearance.thickness;
    if (CGRectEqualToRect(hostBounds, _laidOutHostBounds) && radius == _laidOutRadius && thickness == _laidOutThickness) return;
    _laidOutHostBounds = hostBounds;
    _laidOutRadius = radius;
    _laidOutThickness = thickness;

    CGFloat margin = (CGFloat)_definition.glowMargin;
    CGFloat width = CGRectGetWidth(hostBounds), height = CGRectGetHeight(hostBounds);
    // The line's outer edge is `outset + thickness` beyond the panel; draw it as
    // a rounded rectangle that large, concentric with the panel's corners.
    double expand = _definition.outset + thickness;
    HaloDisplayGeometry geometry = {width + 2 * expand, height + 2 * expand, radius + expand, HaloCutoutNone, 0, 0, 0, 0, 0};
    CGAffineTransform transform = CGAffineTransformMakeTranslation(margin - (CGFloat)expand, margin - (CGFloat)expand);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.frame = CGRectInset(hostBounds, -margin, -margin);
    CGRect bounds = self.bounds;
    _base.frame = bounds;
    for (CALayer *layer in @[ _traceGlow, _traceCore, _pulse ]) layer.frame = bounds;
    [_renderer setGeometry:geometry traceCutout:NO transform:transform unitScale:1 bounds:bounds];

    if (_path) CGPathRelease(_path);
    _path = [HaloRenderer newPathForGeometry:geometry offset:thickness / 2 traceCutout:NO transform:transform];
    _traceGlow.path = _path;
    _traceCore.path = _path;
    _pulse.path = _path;

    if (_definition.clipInterior) {
        // Everything except the panel itself: the light and glow never cover
        // the panel's content or controls.
        if (!_mask) {
            _mask = [CAShapeLayer layer];
            _mask.fillRule = kCAFillRuleEvenOdd;
            _mask.fillColor = UIColor.blackColor.CGColor;
            _mask.contentsScale = _base.contentsScale;
        }
        UIBezierPath *outside = [UIBezierPath bezierPathWithRect:bounds];
        CGRect panel = CGRectMake(margin, margin, width, height);
        [outside appendPath:_definition.continuousCorners ? [UIBezierPath bezierPathWithRoundedRect:panel cornerRadius:radius]
                                                          : [UIBezierPath bezierPathWithRoundedRect:panel
                                                                                  byRoundingCorners:UIRectCornerAllCorners
                                                                                        cornerRadii:CGSizeMake(radius, radius)]];
        _mask.frame = bounds;
        _mask.path = outside.CGPath;
        self.layer.mask = _mask;
    } else {
        self.layer.mask = nil;
    }
    [CATransaction commit];
}

#pragma mark Appearance and activity

- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan reduceTransparency:(BOOL)reduceTransparency {
    HaloAppearance a = halo_sanitize_appearance(appearance);
    a.inset = 0; // the panel's gap comes from the Nexus definition (anchors.outset)
    if (reduceTransparency) a.glow = 0;
    _appearance = a;
    _plan = plan;
    _reduceTransparency = reduceTransparency;
    _hasAppearance = YES;
    _laidOutHostBounds = CGRectNull;
    [self relayout];
    [_renderer setAppearance:a plan:plan];
    [self updateEffectStyle];
    [self applyActivity];
}

- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    if (!active) [self cancelOpeningTrace];
    [self applyActivity];
}

- (void)applyActivity {
    BOOL visible = _active && !_plan.hidden;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.hidden = !visible;
    [_renderer setPaused:!(visible && _plan.animated)];
    [CATransaction commit];
}

- (UIColor *)traceColour {
    HaloRGB c = _appearance.colours[0];
    return [UIColor colorWithRed:(CGFloat)(c.r + (1 - c.r) * 0.55) green:(CGFloat)(c.g + (1 - c.g) * 0.55)
                            blue:(CGFloat)(c.b + (1 - c.b) * 0.55) alpha:0.95];
}

- (void)updateEffectStyle {
    CGFloat t = (CGFloat)_appearance.thickness;
    HaloRGB c = _appearance.colours[0];
    _traceCore.strokeColor = [self traceColour].CGColor;
    _traceCore.lineWidth = t * 1.5f;
    _traceGlow.strokeColor = [UIColor colorWithRed:(CGFloat)c.r green:(CGFloat)c.g blue:(CGFloat)c.b
                                             alpha:_reduceTransparency ? 0 : 0.35].CGColor;
    _traceGlow.lineWidth = t * 5;
    _pulse.strokeColor = [self traceColour].CGColor;
    _pulse.lineWidth = t;
}

#pragma mark Effects

- (BOOL)isTracing {
    return [_traceCore animationForKey:kTraceKey] != nil;
}

- (void)playOpeningTraceWithDuration:(NSTimeInterval)transitionDuration {
    [self cancelOpeningTrace];
    if (!_path || _plan.hidden) return;
    // Long enough to read as one sweep, short enough never to linger: the panel
    // is usable throughout (purely visual, nothing waits for it).
    CFTimeInterval duration = MIN(MAX(transitionDuration * 2.0, 0.6), 0.9);
    for (CAShapeLayer *layer in @[ _traceGlow, _traceCore ]) {
        layer.hidden = NO;
        CABasicAnimation *head = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        head.fromValue = @0;
        head.toValue = @1;
        head.duration = duration;
        head.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        CABasicAnimation *tail = [CABasicAnimation animationWithKeyPath:@"strokeStart"];
        tail.fromValue = @0;
        tail.toValue = @1;
        tail.beginTime = duration * 0.35;
        tail.duration = duration * 0.65;
        tail.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[ @1, @1, @0 ];
        fade.keyTimes = @[ @0, @0.8, @1 ];
        fade.duration = duration;
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[ head, tail, fade ];
        group.duration = duration;
        group.fillMode = kCAFillModeForwards;
        group.removedOnCompletion = NO;
        [layer addAnimation:group forKey:kTraceKey];
    }
    // The selected mode settles in behind the trace.
    CAKeyframeAnimation *settle = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    settle.values = @[ @0, @0, @1 ];
    settle.keyTimes = @[ @0, @0.35, @1 ];
    settle.duration = duration;
    [_base addAnimation:settle forKey:kSettleKey];
    __weak HaloPanelBorderView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HaloPanelBorderView *strong = weakSelf;
        if (!strong) return;
        CAAnimation *running = [strong->_traceCore animationForKey:kTraceKey];
        if (running && running.duration == duration) [strong cancelOpeningTrace];
    });
}

- (void)cancelOpeningTrace {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CAShapeLayer *layer in @[ _traceGlow, _traceCore ]) {
        [layer removeAnimationForKey:kTraceKey];
        layer.hidden = YES;
    }
    [_base removeAnimationForKey:kSettleKey];
    [CATransaction commit];
}

- (void)playWorkspacePulseReducedMotion:(BOOL)reduceMotion {
    if (!_path || self.hidden) return;
    [_pulse removeAnimationForKey:kPulseKey];
    _pulse.hidden = NO;
    CAKeyframeAnimation *glow = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    glow.values = @[ @0, @0.5, @0 ]; // soft: never a full-brightness flash
    glow.keyTimes = @[ @0, @0.35, @1 ];
    NSMutableArray *animations = [NSMutableArray arrayWithObject:glow];
    if (!reduceMotion) {
        CABasicAnimation *swell = [CABasicAnimation animationWithKeyPath:@"lineWidth"];
        swell.fromValue = @(_appearance.thickness);
        swell.toValue = @(_appearance.thickness * 2.4);
        [animations addObject:swell];
    }
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = animations;
    group.duration = 0.5;
    for (CAAnimation *a in animations) a.duration = 0.5;
    group.fillMode = kCAFillModeForwards;
    group.removedOnCompletion = NO;
    [_pulse addAnimation:group forKey:kPulseKey];
    __weak HaloPanelBorderView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        HaloPanelBorderView *strong = weakSelf;
        if (!strong || [strong->_pulse animationForKey:kPulseKey] != group) return;
        [strong->_pulse removeAnimationForKey:kPulseKey];
        strong->_pulse.hidden = YES;
    });
}

- (void)teardown {
    [self cancelOpeningTrace];
    [_pulse removeAllAnimations];
    [_renderer teardown];
    self.layer.mask = nil;
    [self removeFromSuperview];
}

@end
