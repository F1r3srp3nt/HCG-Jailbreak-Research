//
//  PortalView.m
//  HCG Portal — Hakmi Capital Group
//
//  Layer tree (D = diameter):
//
//    stage                      (paused via speed = 0, Apple QA1673)
//    ├─ shadow                  radial black, offset down: depth on the wallpaper
//    ├─ energy                  opacity = brightness
//    │   ├─ glow                radial primary → secondary → clear, 1.6 D
//    │   ├─ rings               (scaled/faded by the unlock flourish)
//    │   │   ├─ outer           conic primary/secondary gradient masked to a 2.5 pt ring, rotates
//    │   │   ├─ middle          dashed secondary ring, rotates the other way
//    │   │   └─ inner           primary arc, rotates faster
//    │   └─ emitter             a few soft motes drifting off the rings
//    └─ core                    dark translucent centre (radial navy → black), glass rim, inner glow
//
//  Rings are rasterised once: rotating a cached bitmap costs only compositing.
//

#import "PortalView.h"

#import <QuartzCore/QuartzCore.h>

static UIColor *PortalColor(PortalRGB c, CGFloat alpha) {
    return [UIColor colorWithRed:c.r green:c.g blue:c.b alpha:alpha];
}

static CGImageRef PortalMoteImage(void) {
    static CGImageRef image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = 2;
        format.opaque = NO;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 8) format:format];
        UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGFloat comps[] = {1, 1, 1, 1, 1, 1, 1, 0};
            CGFloat locs[] = {0, 1};
            CGGradientRef g = CGGradientCreateWithColorComponents(space, comps, locs, 2);
            CGContextDrawRadialGradient(ctx.CGContext, g, CGPointMake(4, 4), 0, CGPointMake(4, 4), 4, 0);
            CGGradientRelease(g);
            CGColorSpaceRelease(space);
        }];
        image = CGImageRetain(img.CGImage);
    });
    return image;
}

@implementation PortalView {
    CALayer *_stage;
    CAGradientLayer *_shadow;
    CALayer *_energy;
    CAGradientLayer *_glow;
    CALayer *_rings;
    CALayer *_outer;
    CAGradientLayer *_outerGradient;
    CAShapeLayer *_outerMask;
    CAShapeLayer *_middle;
    CAShapeLayer *_inner;
    CAEmitterLayer *_emitter;
    CAEmitterCell *_mote;
    CAGradientLayer *_core;
    CAShapeLayer *_rim;
    CAShapeLayer *_highlight;
    CAGradientLayer *_coreGlow;
    PortalAppearance _appearance;
    PortalRenderPlan _plan;
    CGFloat _builtDiameter;
    BOOL _hasAppearance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = NO;
        self.backgroundColor = UIColor.clearColor;
        self.isAccessibilityElement = NO;
        self.accessibilityElementsHidden = YES;
        [self buildLayers];
        portal_appearance_defaults(&_appearance);
        _plan = portal_render_plan(&_appearance, 0, 0, PORTAL_LOWPOWER_STATIC, 1);
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil; // decoration only; PortalOverlayView owns the touch target
}

- (void)buildLayers {
    _stage = [CALayer layer];
    [self.layer addSublayer:_stage];

    _shadow = [CAGradientLayer layer];
    _shadow.type = kCAGradientLayerRadial;
    _shadow.startPoint = CGPointMake(0.5, 0.5);
    _shadow.endPoint = CGPointMake(1, 1);
    _shadow.colors = @[ (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor ];
    [_stage addSublayer:_shadow];

    _energy = [CALayer layer];
    [_stage addSublayer:_energy];

    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.startPoint = CGPointMake(0.5, 0.5);
    _glow.endPoint = CGPointMake(1, 1);
    [_energy addSublayer:_glow];

    _rings = [CALayer layer];
    [_energy addSublayer:_rings];

    _outer = [CALayer layer];
    _outerGradient = [CAGradientLayer layer];
    _outerGradient.type = kCAGradientLayerConic;
    _outerGradient.startPoint = CGPointMake(0.5, 0.5);
    _outerGradient.endPoint = CGPointMake(0.5, 0);
    _outerMask = [CAShapeLayer layer];
    _outerMask.fillColor = UIColor.clearColor.CGColor;
    _outerMask.strokeColor = UIColor.whiteColor.CGColor;
    _outerMask.lineCap = kCALineCapRound;
    _outerGradient.mask = _outerMask;
    [_outer addSublayer:_outerGradient];
    [_rings addSublayer:_outer];

    _middle = [CAShapeLayer layer];
    _middle.fillColor = UIColor.clearColor.CGColor;
    _middle.lineCap = kCALineCapRound;
    [_rings addSublayer:_middle];

    _inner = [CAShapeLayer layer];
    _inner.fillColor = UIColor.clearColor.CGColor;
    _inner.lineCap = kCALineCapRound;
    _inner.strokeStart = 0;
    _inner.strokeEnd = 0.72;
    [_rings addSublayer:_inner];

    for (CALayer *l in @[ _outer, _middle, _inner ]) {
        l.shadowOffset = CGSizeZero;
        l.shouldRasterize = YES;
        l.rasterizationScale = UIScreen.mainScreen.scale;
    }

    _emitter = [CAEmitterLayer layer];
    _emitter.emitterShape = kCAEmitterLayerCircle;
    _emitter.emitterMode = kCAEmitterLayerOutline;
    _emitter.renderMode = kCAEmitterLayerAdditive;
    _mote = [CAEmitterCell emitterCell];
    _mote.name = @"mote";
    _mote.contents = (__bridge id)PortalMoteImage();
    _mote.lifetime = 2.4;
    _mote.lifetimeRange = 0.8;
    _mote.velocity = 7;
    _mote.velocityRange = 5;
    _mote.emissionRange = (CGFloat)(2 * M_PI);
    _mote.scale = 0.45;
    _mote.scaleRange = 0.2;
    _mote.scaleSpeed = -0.12;
    _mote.alphaSpeed = -0.38;
    _emitter.emitterCells = @[ _mote ];
    _emitter.birthRate = 0;
    [_energy addSublayer:_emitter];

    _core = [CAGradientLayer layer];
    _core.type = kCAGradientLayerRadial;
    _core.startPoint = CGPointMake(0.5, 0.5);
    _core.endPoint = CGPointMake(1, 1);
    _core.colors = @[
        (id)[UIColor colorWithRed:0.01 green:0.02 blue:0.06 alpha:0.88].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.06 blue:0.14 alpha:0.80].CGColor,
        (id)[UIColor colorWithRed:0.07 green:0.11 blue:0.26 alpha:0.58].CGColor,
    ];
    _core.locations = @[ @0, @0.72, @1 ];
    _core.masksToBounds = YES;
    [_stage addSublayer:_core];

    _coreGlow = [CAGradientLayer layer];
    _coreGlow.type = kCAGradientLayerRadial;
    _coreGlow.startPoint = CGPointMake(0.5, 0.5);
    _coreGlow.endPoint = CGPointMake(1, 1);
    [_core addSublayer:_coreGlow];

    _rim = [CAShapeLayer layer];
    _rim.fillColor = UIColor.clearColor.CGColor;
    _rim.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _rim.lineWidth = 1;
    [_stage addSublayer:_rim];

    _highlight = [CAShapeLayer layer];
    _highlight.fillColor = UIColor.clearColor.CGColor;
    _highlight.strokeColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    _highlight.lineWidth = 1.2;
    _highlight.lineCap = kCALineCapRound;
    [_stage addSublayer:_highlight];
}

- (PortalRenderPlan)plan {
    return _plan;
}

- (void)applyAppearance:(PortalAppearance)appearance plan:(PortalRenderPlan)plan {
    portal_appearance_clamp(&appearance);
    BOOL same = _hasAppearance && memcmp(&appearance, &_appearance, sizeof appearance) == 0 &&
                memcmp(&plan, &_plan, sizeof plan) == 0;
    _appearance = appearance;
    _plan = plan;
    _hasAppearance = YES;
    if (same) return;
    _builtDiameter = 0;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat d = MIN(self.bounds.size.width, self.bounds.size.height);
    if (d < 1) return;
    if (fabs(d - _builtDiameter) < 0.5 && CGRectEqualToRect(_stage.frame, self.bounds)) return;
    _builtDiameter = d;
    [self rebuild:d];
}

static UIBezierPath *Circle(CGPoint c, CGFloat r) {
    // Starts at the top, clockwise, so strokeStart / strokeEnd and dashes begin at 12 o'clock.
    return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:(CGFloat)-M_PI_2 endAngle:(CGFloat)(1.5 * M_PI) clockwise:YES];
}

- (void)rebuild:(CGFloat)d {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    PortalRGB primary, secondary;
    portal_palette_colours(_appearance.palette, &primary, &secondary);
    double intensity = _appearance.intensity;
    CGRect bounds = self.bounds;
    CGPoint c = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    BOOL compact = d < PORTAL_SIZE_MIN;

    _stage.frame = bounds;

    CGFloat shadowD = d * 1.25;
    _shadow.frame = CGRectMake(c.x - shadowD / 2, c.y - shadowD / 2 + d * 0.08, shadowD, shadowD);

    _energy.frame = bounds;
    _energy.opacity = (float)_appearance.brightness;

    CGFloat glowD = d * (compact ? 1.45 : 1.6);
    _glow.frame = CGRectMake(c.x - glowD / 2, c.y - glowD / 2, glowD, glowD);
    CGFloat g = (CGFloat)(0.10 + 0.30 * intensity) * (_plan.glowLayers > 0 ? 1 : 0);
    _glow.colors = @[
        (id)PortalColor(primary, g).CGColor, (id)PortalColor(secondary, g * 0.55).CGColor,
        (id)PortalColor(secondary, 0).CGColor
    ];
    _glow.locations = @[ @0.42, @0.62, @1 ];
    _glow.opacity = _expanded ? 1.0f : 0.8f;

    _rings.frame = bounds;
    CGFloat glowRadius = (CGFloat)(_plan.glowLayers <= 0 ? 0 : 2.0 + 2.5 * _plan.glowLayers);

    CGFloat outerR = d * 0.46;
    _outer.frame = bounds;
    _outerGradient.frame = bounds;
    _outerGradient.colors = @[
        (id)PortalColor(primary, 1).CGColor, (id)PortalColor(secondary, 1).CGColor,
        (id)PortalColor(primary, 0.25).CGColor, (id)PortalColor(secondary, 0.9).CGColor,
        (id)PortalColor(primary, 1).CGColor
    ];
    _outerMask.frame = bounds;
    _outerMask.path = Circle(c, outerR).CGPath;
    _outerMask.lineWidth = compact ? 2.0 : 2.6;
    _outer.shadowColor = PortalColor(primary, 1).CGColor;
    _outer.shadowRadius = glowRadius;
    _outer.shadowOpacity = glowRadius > 0 ? 0.9f : 0;

    CGFloat middleR = d * 0.415;
    _middle.frame = bounds;
    _middle.path = Circle(c, middleR).CGPath;
    _middle.lineWidth = compact ? 1.0 : 1.5;
    _middle.strokeColor = PortalColor(secondary, 0.9).CGColor;
    CGFloat circumference = (CGFloat)(2 * M_PI * middleR);
    _middle.lineDashPattern = @[ @(circumference / 9 * 0.68), @(circumference / 9 * 0.32) ];
    _middle.shadowColor = PortalColor(secondary, 1).CGColor;
    _middle.shadowRadius = glowRadius * 0.8;
    _middle.shadowOpacity = glowRadius > 0 ? 0.85f : 0;

    CGFloat innerR = d * 0.365;
    _inner.frame = bounds;
    _inner.path = Circle(c, innerR).CGPath;
    _inner.lineWidth = compact ? 0.8 : 1.1;
    _inner.strokeColor = PortalColor(primary, 0.7).CGColor;
    _inner.shadowColor = PortalColor(primary, 1).CGColor;
    _inner.shadowRadius = glowRadius * 0.6;
    _inner.shadowOpacity = glowRadius > 0 ? 0.7f : 0;

    CGFloat coreD = d * 0.70;
    _core.frame = CGRectMake(c.x - coreD / 2, c.y - coreD / 2, coreD, coreD);
    _core.cornerRadius = coreD / 2;
    _coreGlow.frame = _core.bounds;
    _coreGlow.colors = @[
        (id)PortalColor(primary, 0.10 + 0.14 * intensity).CGColor, (id)PortalColor(secondary, 0.05).CGColor,
        (id)PortalColor(secondary, 0).CGColor
    ];
    _coreGlow.locations = @[ @0, @0.55, @1 ];
    _rim.frame = bounds;
    _rim.path = Circle(c, coreD / 2).CGPath;
    _highlight.frame = bounds;
    _highlight.path = [UIBezierPath bezierPathWithArcCenter:c
                                                     radius:coreD / 2 - 2
                                                 startAngle:(CGFloat)(-M_PI * 0.85)
                                                   endAngle:(CGFloat)(-M_PI * 0.45)
                                                  clockwise:YES]
                          .CGPath;

    _emitter.frame = bounds;
    _emitter.emitterPosition = c;
    _emitter.emitterSize = CGSizeMake(outerR * 2, outerR * 2);
    _mote.color = PortalColor(primary, 0.85).CGColor;
    _mote.birthRate = (float)_plan.particleRate;

    for (CALayer *l in @[ _outer, _middle, _inner ]) l.rasterizationScale = self.window.screen.scale ?: UIScreen.mainScreen.scale;

    [self installAnimations];
    [CATransaction commit];
}

- (void)installAnimations {
    for (CALayer *l in @[ _outer, _middle, _inner, _coreGlow ]) [l removeAllAnimations];
    // Static angles, so the static appearance still looks composed.
    _outer.transform = CATransform3DMakeRotation((CGFloat)(M_PI * 0.15), 0, 0, 1);
    _middle.transform = CATransform3DMakeRotation((CGFloat)(-M_PI * 0.08), 0, 0, 1);
    _inner.transform = CATransform3DMakeRotation((CGFloat)(M_PI * 0.6), 0, 0, 1);
    _coreGlow.opacity = 0.8f;

    BOOL emit = _plan.draw && _plan.particles && _plan.animate && !_paused;
    _emitter.birthRate = emit ? 1 : 0;
    if (!_plan.draw || !_plan.animate) return;

    double period = _plan.ringPeriod;
    struct { CALayer *layer; double factor; } spins[] = {{_outer, 1.0}, {_middle, -1.6}, {_inner, 0.65}};
    for (size_t i = 0; i < 3; i++) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.byValue = @(spins[i].factor > 0 ? 2 * M_PI : -2 * M_PI);
        spin.duration = period * fabs(spins[i].factor);
        spin.repeatCount = HUGE_VALF;
        spin.additive = YES;
        spin.removedOnCompletion = NO;
        [spins[i].layer addAnimation:spin forKey:@"portal.spin"];
    }
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @0.55;
    breathe.toValue = @1.0;
    breathe.duration = (_waiting ? 0.9 : 3.2) / _appearance.speed;
    breathe.autoreverses = YES;
    breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    breathe.removedOnCompletion = NO;
    [_coreGlow addAnimation:breathe forKey:@"portal.breathe"];
}

- (void)setPaused:(BOOL)paused {
    if (paused == _paused) return;
    _paused = paused;
    if (paused) {
        CFTimeInterval t = [_stage convertTime:CACurrentMediaTime() fromLayer:nil];
        _stage.speed = 0;
        _stage.timeOffset = t;
        _emitter.birthRate = 0;
    } else {
        CFTimeInterval paused_t = _stage.timeOffset;
        _stage.speed = 1;
        _stage.timeOffset = 0;
        _stage.beginTime = 0;
        _stage.beginTime = [_stage convertTime:CACurrentMediaTime() fromLayer:nil] - paused_t;
        _emitter.birthRate = (_plan.draw && _plan.particles && _plan.animate) ? 1 : 0;
    }
}

- (void)setExpanded:(BOOL)expanded {
    [self setExpanded:expanded animated:NO];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _expanded = expanded;
    CGFloat scale = expanded ? 1.06 : 1.0;
    void (^apply)(void) = ^{
        self->_stage.transform = CATransform3DMakeScale(scale, scale, 1);
        self->_glow.opacity = expanded ? 1.0f : 0.8f;
    };
    if (animated && _plan.animate) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.22];
        apply();
        [CATransaction commit];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        apply();
        [CATransaction commit];
    }
}

- (void)setWaiting:(BOOL)waiting {
    if (waiting == _waiting) return;
    _waiting = waiting;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self installAnimations];
    [CATransaction commit];
}

- (void)playUnlockFlourish {
    if (!_plan.unlockAnimation || !_plan.draw || _paused) return;
    _flourishPlayed = YES;
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    grow.fromValue = @1.0;
    grow.toValue = @1.45;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @1.0;
    fade.toValue = @0.0;
    CAAnimationGroup *open = [CAAnimationGroup animation];
    open.animations = @[ grow, fade ];
    open.duration = 0.5;
    open.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_rings addAnimation:open forKey:@"portal.flourish"];

    CABasicAnimation *flash = [CABasicAnimation animationWithKeyPath:@"opacity"];
    flash.fromValue = @1.0;
    flash.toValue = @0.0;
    flash.duration = 0.5;
    [_glow addAnimation:flash forKey:@"portal.flourish"];
    CABasicAnimation *iris = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    iris.fromValue = @1.0;
    iris.toValue = @1.25;
    iris.duration = 0.5;
    iris.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_core addAnimation:iris forKey:@"portal.flourish"];
}

- (NSUInteger)runningAnimationCount {
    NSUInteger n = 0;
    for (CALayer *l in @[ _outer, _middle, _inner, _coreGlow, _rings, _glow, _core ]) n += l.animationKeys.count;
    return n;
}

- (BOOL)emitterActive {
    return _emitter.birthRate > 0 && _mote.birthRate > 0;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        _builtDiameter = 0;
        [self setNeedsLayout];
    }
}

@end
