//
//  VortexEffectPreviewCell.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexEffectPreviewCell.h"
#import "VortexHeaderView.h"
#import "VortexIconEffects.h"
#import "VortexMath.h"
#import "VortexPreferences.h"

#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>

static const double kPageWidth = 390.0, kPageHeight = 844.0, kIcon = 60.0;
static const int kCols = 4, kRows = 6, kIcons = 24;
static const CFTimeInterval kCycle = 4.0; // swipe forward, hold, reverse, hold

@implementation VortexEffectPreviewCell {
    VortexIconEffectKind _kind;
    BOOL _valid;
    UIView *_stage;
    CALayer *_pages[2];
    CAShapeLayer *_traceGlow[2], *_traceCore[2];
    CALayer *_tiles[2][24];
    UILabel *_caption;
    CADisplayLink *_link;
    CFTimeInterval _start;
    VortexIconSlot _slots[24];
    VortexConfiguration *_config;
    NSUInteger _frames;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
        _valid = [VortexPreferences iconEffectKind:&_kind forIdentifier:[specifier propertyForKey:@"effect"]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = VortexTheme.panel;

        _stage = [[UIView alloc] init];
        _stage.backgroundColor = VortexTheme.background;
        _stage.layer.cornerRadius = 14.0;
        _stage.clipsToBounds = YES;
        [self.contentView addSubview:_stage];

        NSArray<UIColor *> *cool = @[ VortexTheme.cyan, VortexTheme.purple, [UIColor systemBlueColor], [UIColor systemTealColor] ];
        NSArray<UIColor *> *warm = @[ [UIColor systemOrangeColor], [UIColor systemPinkColor], [UIColor systemYellowColor], [UIColor systemRedColor] ];
        for (int p = 0; p < 2; p++) {
            _pages[p] = [CALayer layer];
            CATransform3D perspective = CATransform3DIdentity;
            perspective.m34 = -1.0 / 600.0;
            _pages[p].sublayerTransform = perspective;
            [_stage.layer addSublayer:_pages[p]]; // outgoing below incoming, as on the Home Screen
            _traceGlow[p] = [CAShapeLayer layer];
            _traceCore[p] = [CAShapeLayer layer];
            for (CAShapeLayer *line in @[ _traceGlow[p], _traceCore[p] ]) {
                line.fillColor = nil;
                line.lineCap = kCALineCapRound;
                line.zPosition = -1000.0;
                [_pages[p] addSublayer:line];
            }
            for (int i = 0; i < kIcons; i++) {
                CALayer *tile = [CALayer layer];
                tile.backgroundColor = (p == 0 ? cool : warm)[i % 4].CGColor;
                tile.cornerRadius = kIcon * 0.23;
                tile.bounds = CGRectMake(0, 0, kIcon, kIcon);
                [_pages[p] addSublayer:tile];
                _tiles[p][i] = tile;
            }
        }
        for (int i = 0; i < kIcons; i++) {
            _slots[i].homeX = (i % kCols - (kCols - 1) / 2.0) * 97.5;
            _slots[i].homeY = (i / kCols - (kRows - 1) / 2.0) * 110.0;
        }
        vortex_tornado_rank(_slots, kIcons, 8.0);

        _caption = [[UILabel alloc] init];
        _caption.font = [UIFont systemFontOfSize:11.0];
        _caption.textColor = VortexTheme.textSecondary;
        _caption.numberOfLines = 2;
        _caption.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_caption];
        _config = [VortexPreferences loadConfiguration];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat captionHeight = 30.0;
    CGFloat h = MAX(CGRectGetHeight(b) - captionHeight - 16.0, 40.0);
    CGFloat w = h * kPageWidth / kPageHeight;
    _stage.frame = CGRectMake((CGRectGetWidth(b) - w) / 2.0, 8.0, w, h);
    _caption.frame = CGRectMake(12.0, CGRectGetMaxY(_stage.frame) + 2.0, CGRectGetWidth(b) - 24.0, captionHeight);
    [self renderAtProgress:[self progressNow]];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_link invalidate];
    _link = nil;
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    _caption.text = still ? @"Reduce Motion is on: this effect is replaced by the stock animation. Still frame shown."
                          : @"Live preview of this effect's geometry with your settings (mock icons, not your Home Screen).";
    if (self.window && !still && _valid) {
        _start = CACurrentMediaTime();
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 30);
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    [self renderAtProgress:[self progressNow]];
}

- (void)dealloc {
    [_link invalidate];
}

- (double)progressNow {
    if (!_link) return 0.5;
    double t = fmod(CACurrentMediaTime() - _start, kCycle) / kCycle;
    if (t < 0.4) return t / 0.4;
    if (t < 0.5) return 1.0;
    if (t < 0.9) return 1.0 - (t - 0.5) / 0.4;
    return 0.0;
}

- (void)tick:(CADisplayLink *)link {
    if (++_frames % 15 == 0) _config = [VortexPreferences loadConfiguration]; // pick up changes within ~0.5 s
    [self renderAtProgress:[self progressNow]];
}

- (void)renderAtProgress:(double)progress {
    CGRect b = _stage.bounds;
    if (!_valid || CGRectGetWidth(b) < 1.0) return;
    CGFloat k = CGRectGetWidth(b) / kPageWidth;
    VortexEffectParameters ep = vortex_default_parameters();
    VortexIconEffectSettings s = _config.iconEffectSettings;
    NSArray<NSNumber *> *rgb = _config.accentRGB;
    UIColor *accent = [UIColor colorWithRed:rgb[0].doubleValue green:rgb[1].doubleValue blue:rgb[2].doubleValue alpha:1.0];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int p = 0; p < 2; p++) {
        VortexPageRole role = p == 0 ? VortexPageRoleOutgoing : VortexPageRoleIncoming;
        VortexPageVisual page = vortex_icon_effect_page(_kind, role, progress, VortexNavigationForward, &ep);
        _pages[p].frame = CGRectOffset(b, page.translation.x * CGRectGetWidth(b), page.translation.y * CGRectGetHeight(b));
        _pages[p].opacity = (float)(isnan(page.opacity) ? 1.0 : page.opacity);
        CGMutablePathRef path = CGPathCreateMutable();
        double alpha = 0.0;
        for (int i = 0; i < kIcons; i++) {
            VortexIconVisual v = vortex_icon_effect_visual(_kind, role, progress, VortexNavigationForward, _slots[i],
                                                           kPageWidth, kPageHeight, &s, &ep);
            CALayer *tile = _tiles[p][i];
            tile.position = CGPointMake((kPageWidth / 2.0 + _slots[i].homeX + v.tx) * k,
                                        (kPageHeight / 2.0 + _slots[i].homeY + v.ty) * k);
            CATransform3D t = CATransform3DMakeScale((CGFloat)(v.scale * k), (CGFloat)(v.scale * k), 1);
            if (v.tiltY != 0.0) t = CATransform3DRotate(t, (CGFloat)v.tiltY, 0, 1, 0);
            if (v.tiltX != 0.0) t = CATransform3DRotate(t, (CGFloat)v.tiltX, 1, 0, 0);
            if (v.rotation != 0.0) t = CATransform3DRotate(t, (CGFloat)v.rotation, 0, 0, 1);
            tile.transform = t;
            tile.zPosition = (CGFloat)v.z;
            tile.opacity = (float)v.opacity;
            VortexTrace tr = vortex_icon_effect_trace(_kind, role, progress, VortexNavigationForward, _slots[i],
                                                      kPageWidth, kPageHeight, &s, &ep);
            if (tr.count >= 2) {
                CGPathMoveToPoint(path, NULL, (kPageWidth / 2.0 + tr.points[0].x) * k, (kPageHeight / 2.0 + tr.points[0].y) * k);
                for (int q = 1; q < tr.count; q++)
                    CGPathAddLineToPoint(path, NULL, (kPageWidth / 2.0 + tr.points[q].x) * k,
                                         (kPageHeight / 2.0 + tr.points[q].y) * k);
                alpha = MAX(alpha, tr.alpha);
            }
        }
        _traceGlow[p].path = path;
        _traceCore[p].path = path;
        _traceGlow[p].strokeColor = accent.CGColor;
        _traceCore[p].strokeColor = accent.CGColor;
        _traceGlow[p].lineWidth = (CGFloat)((2.0 + 8.0 * s.circuit.glow) * k);
        _traceCore[p].lineWidth = MAX(1.0, 1.5 * k);
        _traceGlow[p].opacity = (float)(0.35 * s.circuit.glow * alpha);
        _traceCore[p].opacity = (float)alpha;
        CGPathRelease(path);
    }
    [CATransaction commit];
}

@end
