//
//  HaloRenderer.m
//  HCG Halo — Hakmi Capital Group
//
//  Layer tree (gradient colour styles):
//
//    root (opacity = brightness; Breathing animates it)
//    ├─ colourHost (mask = maskLayer)          ← one offscreen pass
//    │   └─ gradient (conic; Colour Flow rotates it)
//    │   maskLayer: glow strokes + core strokes, white with alpha;
//    │              Orbit / Circuit animate their dash phase
//    └─ highlight strokes (thin white "hot core" of the neon tube)
//
//  Single colour: the strokes are coloured directly and added to root; no
//  mask, no gradient.
//
//  Dash maths: a dash at pattern position [0, L] with phase p covers path
//  positions [-p, L - p]. Decreasing the phase therefore moves light forward
//  along the path, which is clockwise on screen (HaloGeometry.h).
//

#import "HaloRenderer.h"

#include <math.h>

static NSString *const kPhaseKey = @"halo.phase";
static NSString *const kBreatheKey = @"halo.breathe";
static NSString *const kFlowKey = @"halo.flow";
static NSString *const kBlinkKey = @"halo.blink";

@implementation HaloRenderer {
    CGFloat _scale;
    CALayer *_root;

    BOOL _hasGeometry;
    HaloDisplayGeometry _geometry;
    BOOL _trace;
    CGAffineTransform _transform;
    CGFloat _unit;      // fixed points -> layer points for widths (thickness, glow)
    CGFloat _pathScale; // fixed points -> layer points along the path (from the transform)
    CGRect _bounds;

    BOOL _hasAppearance;
    HaloAppearance _appearance;
    HaloRenderPlan _plan;

    HaloBorderPath _border;
    CGPathRef _path;   // transformed centre line
    CALayer *_ink;     // where strokes go: root (solid) or the mask (gradient)
    BOOL _inkIsMask;
    HaloRGB _solid;    // single colour
}

- (instancetype)initWithContentsScale:(CGFloat)scale {
    if ((self = [super init])) {
        _scale = scale > 0 ? scale : 1;
        _root = [CALayer layer];
        _root.contentsScale = _scale;
        _root.masksToBounds = NO;
        _root.allowsGroupOpacity = YES;
        _transform = CGAffineTransformIdentity;
        _unit = 1;
        _pathScale = 1;
    }
    return self;
}

- (void)dealloc {
    if (_path) CGPathRelease(_path);
}

- (CALayer *)layer {
    return _root;
}

#pragma mark - Configuration

- (void)setGeometry:(HaloDisplayGeometry)geometry
         traceCutout:(BOOL)traceCutout
           transform:(CGAffineTransform)transform
           unitScale:(CGFloat)unitScale
              bounds:(CGRect)bounds {
    _geometry = geometry;
    _trace = traceCutout;
    _transform = transform;
    _unit = unitScale > 0 ? unitScale : 1;
    _pathScale = (CGFloat)hypot(transform.a, transform.b);
    if (!(_pathScale > 0)) _pathScale = 1;
    _bounds = bounds;
    _hasGeometry = YES;
    [self rebuild];
}

- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan {
    _appearance = halo_sanitize_appearance(appearance);
    _plan = plan;
    _hasAppearance = YES;
    [self rebuild];
}

- (void)teardown {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self clear];
    [CATransaction commit];
    _hasGeometry = NO;
    _hasAppearance = NO;
}

#pragma mark - Pause / resume (Technical Q&A QA1673)

- (void)setPaused:(BOOL)paused {
    if (paused == _paused) return;
    _paused = paused;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (paused) {
        CFTimeInterval now = [_root convertTime:CACurrentMediaTime() fromLayer:nil];
        _root.speed = 0;
        _root.timeOffset = now;
    } else {
        CFTimeInterval pausedAt = _root.timeOffset;
        _root.speed = 1;
        _root.timeOffset = 0;
        _root.beginTime = 0;
        _root.beginTime = [_root convertTime:CACurrentMediaTime() fromLayer:nil] - pausedAt;
    }
    [CATransaction commit];
}

#pragma mark - Building

- (void)clear {
    for (CALayer *sub in [_root.sublayers copy]) [sub removeFromSuperlayer];
    [_root removeAllAnimations];
    _root.mask = nil;
    _root.opacity = 1;
    _layerCount = 0;
    _perimeter = 0;
    _ink = nil;
    if (_path) {
        CGPathRelease(_path);
        _path = NULL;
    }
}

- (void)rebuild {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        [self clear];
        _root.frame = _bounds;
        if (_hasGeometry && _hasAppearance && !_plan.hidden && !CGRectIsEmpty(_bounds)) [self build];
    } @finally {
        [CATransaction commit];
    }
}

- (void)build {
    HaloAppearance a = _appearance;
    double offset = a.inset + a.thickness / 2; // centre line, fixed points
    if (!halo_build_border(&_geometry, offset, _trace, &_border)) return;
    _perimeter = _border.length;
    _path = [self newTransformedPath];
    if (!_path) return;

    HaloMode mode = _plan.mode;
    // Colour Flow needs something to move: a single colour flows as a
    // bright-to-dim band of that colour.
    if (mode == HaloModeFlow && halo_effective_colour_count(&a) == 1) {
        HaloRGB c = a.colours[0];
        a.colourStyle = HaloColourGradient;
        a.colourCount = 2;
        a.colours[0] = c;
        a.colours[1] = (HaloRGB){c.r * 0.22, c.g * 0.22, c.b * 0.22};
    }

    _root.opacity = (float)a.brightness;
    CALayer *colourHost = nil;
    CAGradientLayer *gradient = nil;
    if (halo_effective_colour_count(&a) == 1) {
        _ink = _root;
        _inkIsMask = NO;
        _solid = a.colours[0];
    } else {
        colourHost = [self addLayer:[CALayer layer] to:_root];
        gradient = [self gradientFor:a];
        [colourHost addSublayer:gradient];
        _layerCount++;
        CALayer *mask = [CALayer layer];
        mask.frame = colourHost.bounds;
        mask.contentsScale = _scale;
        colourHost.mask = mask;
        _layerCount++;
        _ink = mask;
        _inkIsMask = YES;
    }

    CGFloat t = (CGFloat)(a.thickness * _unit);
    switch (mode) {
    case HaloModeStatic:
        [self trackWidth:t glow:a.glow alpha:1];
        break;
    case HaloModeBreathing:
        [self trackWidth:t glow:a.glow alpha:1];
        [self addBreathingTo:_root brightness:a.brightness speed:a.speed];
        break;
    case HaloModeFlow:
        [self trackWidth:t glow:a.glow alpha:1];
        [self addFlowTo:gradient appearance:a];
        break;
    case HaloModeOrbit:
        [self buildOrbit:a width:t];
        break;
    case HaloModeCircuit:
        [self buildCircuit:a width:t];
        break;
    default:
        [self trackWidth:t glow:a.glow alpha:1];
        break;
    }

    // Nothing in the masked subtree changes per frame in Static / Breathing:
    // rasterise it once, so each frame only composites a cached bitmap.
    if (colourHost && (mode == HaloModeStatic || mode == HaloModeBreathing)) {
        colourHost.shouldRasterize = YES;
        colourHost.rasterizationScale = _scale;
    }
}

- (CGPathRef)newTransformedPath {
    enum { kCapacity = 256 };
    HaloBezierOp ops[kCapacity];
    int n = halo_border_to_beziers(&_border, ops, kCapacity);
    if (n <= 0) return NULL;
    CGMutablePathRef path = CGPathCreateMutable();
    CGAffineTransform t = _transform;
    for (int i = 0; i < n; i++) {
        const HaloBezierOp *op = &ops[i];
        switch (op->kind) {
        case HaloBezierMove: CGPathMoveToPoint(path, &t, (CGFloat)op->x, (CGFloat)op->y); break;
        case HaloBezierLine: CGPathAddLineToPoint(path, &t, (CGFloat)op->x, (CGFloat)op->y); break;
        case HaloBezierCurve:
            CGPathAddCurveToPoint(path, &t, (CGFloat)op->c1x, (CGFloat)op->c1y, (CGFloat)op->c2x, (CGFloat)op->c2y,
                                  (CGFloat)op->x, (CGFloat)op->y);
            break;
        case HaloBezierClose: CGPathCloseSubpath(path); break;
        }
    }
    return path;
}

- (__kindof CALayer *)addLayer:(CALayer *)layer to:(CALayer *)parent {
    layer.frame = parent.bounds;
    layer.contentsScale = _scale;
    [parent addSublayer:layer];
    _layerCount++;
    return layer;
}

- (CGColorRef)inkWithAlpha:(CGFloat)alpha {
    if (_inkIsMask) return [UIColor colorWithWhite:1 alpha:alpha].CGColor;
    return [UIColor colorWithRed:(CGFloat)_solid.r green:(CGFloat)_solid.g blue:(CGFloat)_solid.b alpha:alpha].CGColor;
}

- (CAShapeLayer *)strokeIn:(CALayer *)parent width:(CGFloat)width colour:(CGColorRef)colour {
    CAShapeLayer *s = [self addLayer:[CAShapeLayer layer] to:parent];
    s.path = _path;
    s.fillColor = nil;
    s.strokeColor = colour;
    s.lineWidth = width;
    s.lineJoin = kCALineJoinRound;
    s.lineCap = kCALineCapRound;
    return s;
}

/// Glow (widest first), core line, and the white "hot core" highlight.
/// Returns every layer so callers can apply a dash pattern to the whole set.
- (NSArray<CAShapeLayer *> *)trackWidth:(CGFloat)t glow:(double)glow alpha:(CGFloat)alpha {
    NSMutableArray *layers = [NSMutableArray array];
    if (glow > 0.01) {
        CGFloat reach = (CGFloat)(20.0 * glow) * _unit;
        const CGFloat widths[] = {t + reach * 1.8f, t + reach, t + reach * 0.45f};
        const CGFloat alphas[] = {0.06f, 0.14f, 0.30f};
        CGFloat strength = (CGFloat)(0.5 + 0.5 * glow);
        for (int i = 0; i < 3; i++)
            [layers addObject:[self strokeIn:_ink width:widths[i] colour:[self inkWithAlpha:alphas[i] * strength * alpha]]];
    }
    [layers addObject:[self strokeIn:_ink width:t colour:[self inkWithAlpha:alpha]]];
    if (t >= 2 * _unit) {
        CGColorRef hot;
        if (_inkIsMask) {
            hot = [UIColor colorWithWhite:1 alpha:0.42 * alpha].CGColor;
        } else {
            HaloRGB c = _solid;
            hot = [UIColor colorWithRed:(CGFloat)(c.r + (1 - c.r) * 0.65) green:(CGFloat)(c.g + (1 - c.g) * 0.65)
                                   blue:(CGFloat)(c.b + (1 - c.b) * 0.65) alpha:0.8 * alpha].CGColor;
        }
        [layers addObject:[self strokeIn:_root width:t * 0.32f colour:hot]];
    }
    return layers;
}

- (CAGradientLayer *)gradientFor:(HaloAppearance)a {
    HaloStop stops[HALO_MAX_STOPS];
    int count = halo_gradient_stops(&a, stops, HALO_MAX_STOPS);
    NSMutableArray *colours = [NSMutableArray array];
    NSMutableArray *locations = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        HaloRGB c = stops[i].colour;
        [colours addObject:(__bridge id)[UIColor colorWithRed:(CGFloat)c.r green:(CGFloat)c.g blue:(CGFloat)c.b alpha:1].CGColor];
        [locations addObject:@(stops[i].location)];
    }
    CAGradientLayer *g = [CAGradientLayer layer];
    g.type = kCAGradientLayerConic;
    g.startPoint = CGPointMake(0.5, 0.5);
    g.endPoint = CGPointMake(0.5, 0);
    g.colors = colours;
    g.locations = locations;
    g.contentsScale = _scale;
    // Square around the screen centre, large enough to cover the screen at
    // any rotation; rotated with the display so the palette starts at its top.
    CGPoint centre = CGPointApplyAffineTransform(CGPointMake((CGFloat)(_geometry.width / 2), (CGFloat)(_geometry.height / 2)),
                                                 _transform);
    CGFloat side = (CGFloat)hypot(CGRectGetWidth(_bounds), CGRectGetHeight(_bounds)) * 1.02f;
    g.bounds = CGRectMake(0, 0, side, side);
    g.position = centre;
    g.affineTransform = CGAffineTransformMakeRotation((CGFloat)atan2(_transform.b, _transform.a));
    return g;
}

#pragma mark - Animations

- (void)prepare:(CAAnimation *)animation duration:(CFTimeInterval)duration {
    animation.duration = duration;
    animation.repeatCount = HUGE_VALF;
    animation.removedOnCompletion = NO;
}

- (void)addBreathingTo:(CALayer *)layer brightness:(double)brightness speed:(double)speed {
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @(brightness);
    breathe.toValue = @(brightness * 0.2);
    breathe.autoreverses = YES;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self prepare:breathe duration:halo_period(HaloModeBreathing, speed) / 2];
    [layer addAnimation:breathe forKey:kBreatheKey];
}

- (void)addFlowTo:(CAGradientLayer *)gradient appearance:(HaloAppearance)a {
    if (!gradient) return;
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0;
    spin.toValue = @(a.clockwise ? 2 * M_PI : -2 * M_PI);
    spin.additive = YES; // on top of the display-orientation rotation
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self prepare:spin duration:halo_period(HaloModeFlow, a.speed)];
    [gradient addAnimation:spin forKey:kFlowKey];
}

/// Dashes of `length` repeating every `period` (layer points), travelling one
/// period per `duration`. `trailing` dashes keep their head aligned with a
/// head of length `headLength` (comet tails).
- (void)dash:(NSArray<CAShapeLayer *> *)layers
        length:(CGFloat)length
        period:(CGFloat)period
    headLength:(CGFloat)headLength
     clockwise:(BOOL)clockwise
      duration:(CFTimeInterval)duration {
    if (period <= 0 || length <= 0 || duration <= 0) return;
    length = MIN(length, period * 0.96f);
    CGFloat phase = clockwise ? (length - headLength) : 0;
    CGFloat delta = clockwise ? -period : period;
    for (CAShapeLayer *layer in layers) {
        layer.lineDashPattern = @[ @(length), @(period - length) ];
        layer.lineDashPhase = phase;
        CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        move.fromValue = @(phase);
        move.toValue = @(phase + delta);
        move.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self prepare:move duration:duration];
        [layer addAnimation:move forKey:kPhaseKey];
    }
}

- (void)buildOrbit:(HaloAppearance)a width:(CGFloat)t {
    CGFloat perimeter = (CGFloat)(_border.length * _pathScale); // dash lengths are measured along the path
    double dash, gap;
    halo_orbit_dash(perimeter, a.segments, a.segmentLength, &dash, &gap);
    CGFloat period = (CGFloat)(dash + gap);
    CGFloat head = (CGFloat)dash;
    CFTimeInterval duration = halo_period(HaloModeOrbit, a.speed) / a.segments; // one lap per period per segment
    BOOL cw = a.clockwise;

    // A faint full track so the border's shape stays legible between segments.
    [self strokeIn:_ink width:MAX(t * 0.5f, 0.75f * _unit) colour:[self inkWithAlpha:0.10]];
    // Comet: two fading tail stages under a bright head with glow.
    [self dash:[self trackWidth:t * 0.8f glow:0 alpha:0.16f] length:head * 3.2f period:period headLength:head
        clockwise:cw duration:duration];
    [self dash:[self trackWidth:t * 0.9f glow:0 alpha:0.42f] length:head * 1.9f period:period headLength:head
        clockwise:cw duration:duration];
    [self dash:[self trackWidth:t glow:a.glow alpha:1] length:head period:period headLength:head clockwise:cw
        duration:duration];
}

- (void)buildCircuit:(HaloAppearance)a width:(CGFloat)t {
    CGFloat perimeter = (CGFloat)(_border.length * _pathScale); // dash lengths are measured along the path
    CFTimeInterval lap = halo_period(HaloModeCircuit, a.speed);
    BOOL cw = a.clockwise;

    // 1. Dim continuous trace.
    [self strokeIn:_ink width:MAX(t * 0.55f, 0.75f * _unit) colour:[self inkWithAlpha:0.18]];

    // 2. Irregular circuit segments drifting slowly.
    double pattern[16], unit = 0;
    int entries = halo_circuit_pattern(perimeter, a.thickness * _unit, pattern, 16, &unit);
    if (entries > 0 && unit > 0) {
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i < entries; i++) [values addObject:@(pattern[i])];
        CAShapeLayer *trace = [self strokeIn:_ink width:t colour:[self inkWithAlpha:0.55]];
        trace.lineCap = kCALineCapButt;
        trace.lineDashPattern = values;
        CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        drift.fromValue = @0;
        drift.toValue = @(cw ? -unit : unit);
        drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        // The pattern drifts at a sixth of the pulse speed.
        [self prepare:drift duration:6 * lap * unit / perimeter];
        [trace addAnimation:drift forKey:kPhaseKey];
    }

    // 3. Fast data pulses with a short tail and glow.
    int groups = a.segments * 2;
    CGFloat period = perimeter / groups;
    CGFloat pulse = MIN(MAX(t * 5, perimeter * 0.02f), period * 0.45f);
    CFTimeInterval duration = lap / groups;
    [self dash:[self trackWidth:t glow:0 alpha:0.35f] length:pulse * 2.2f period:period headLength:pulse clockwise:cw
        duration:duration];
    [self dash:[self trackWidth:t * 1.15f glow:a.glow alpha:1] length:pulse period:period headLength:pulse clockwise:cw
        duration:duration];

    // 4. Nodes at corners and notch points, blinking out of step.
    CGFloat radius = MAX(1.6f * _unit, t * 0.9f);
    for (int i = 0; i < _border.landmarkCount; i++) {
        double fx, fy;
        halo_point_at(&_border, _border.landmarks[i], &fx, &fy);
        CGPoint p = CGPointApplyAffineTransform(CGPointMake((CGFloat)fx, (CGFloat)fy), _transform);
        CAShapeLayer *node = [self addLayer:[CAShapeLayer layer] to:_ink];
        CGMutablePathRef dot = CGPathCreateMutable();
        CGPathAddEllipseInRect(dot, NULL, CGRectMake(p.x - radius, p.y - radius, radius * 2, radius * 2));
        CGFloat ring = radius * 2.3f, inner = ring - MAX(0.8f * _unit, t * 0.35f);
        CGPathAddEllipseInRect(dot, NULL, CGRectMake(p.x - inner, p.y - inner, inner * 2, inner * 2));
        CGPathAddEllipseInRect(dot, NULL, CGRectMake(p.x - ring, p.y - ring, ring * 2, ring * 2));
        node.path = dot;
        CGPathRelease(dot);
        node.fillRule = kCAFillRuleEvenOdd; // filled dot inside a thin ring: a circuit "via"
        node.fillColor = [self inkWithAlpha:0.9];
        CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        blink.values = @[ @0.25, @1.0, @0.25, @0.25 ];
        blink.keyTimes = @[ @0, @0.12, @0.4, @1 ];
        [self prepare:blink duration:lap * 0.9];
        blink.timeOffset = fmod(i * 0.61 * lap, lap * 0.9);
        [node addAnimation:blink forKey:kBlinkKey];
    }
}

@end
