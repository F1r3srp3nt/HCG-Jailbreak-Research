//
//  HaloHeaderView.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloHeaderView.h"
#import "HaloPreferences.h"
#import "HaloRenderer.h"
#import "HaloTheme.h"

static const CGFloat kHeaderHeight = 236.0;
static const CGFloat kPreviewHeight = 184.0;

@implementation HaloHeaderView {
    UIView *_bezel;
    UIView *_screen;
    CAShapeLayer *_homeGrid;
    CAShapeLayer *_notch;
    HaloRenderer *_renderer;
    CAGradientLayer *_backdrop;
    CAGradientLayer *_titleGradient;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_brandLabel;
    UILabel *_captionLabel;
    HaloSettings *_settings;
    id _reduceMotionToken;
    id _powerToken;
}

- (instancetype)initWithWidth:(CGFloat)width {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, kHeaderHeight)])) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;

        _backdrop = [CAGradientLayer layer];
        _backdrop.type = kCAGradientLayerRadial;
        _backdrop.colors = @[
            (id)[HaloTheme colourWithHex:0x1B1048 alpha:0.95].CGColor, (id)[HaloTheme colourWithHex:0x06213A alpha:0.55].CGColor,
            (id)HaloTheme.background.CGColor
        ];
        _backdrop.locations = @[ @0, @0.5, @1 ];
        _backdrop.startPoint = CGPointMake(0.25, 0.5);
        _backdrop.endPoint = CGPointMake(1.1, 1.2);
        [self.layer addSublayer:_backdrop];

        _bezel = [[UIView alloc] init];
        _bezel.backgroundColor = [HaloTheme colourWithHex:0x1A2238 alpha:1];
        _bezel.layer.borderColor = [HaloTheme colourWithHex:0x2E3A5C alpha:1].CGColor;
        _bezel.layer.borderWidth = 1;
        [self addSubview:_bezel];

        _screen = [[UIView alloc] init];
        _screen.backgroundColor = [HaloTheme colourWithHex:0x090D1A alpha:1];
        _screen.clipsToBounds = YES; // the glow stops at the glass, as on the phone
        [_bezel addSubview:_screen];

        _homeGrid = [CAShapeLayer layer];
        _homeGrid.fillColor = [UIColor colorWithWhite:1 alpha:0.07].CGColor;
        [_screen.layer addSublayer:_homeGrid];

        _renderer = [[HaloRenderer alloc] initWithContentsScale:UIScreen.mainScreen.scale];
        [_screen.layer addSublayer:_renderer.layer];

        _notch = [CAShapeLayer layer];
        _notch.fillColor = UIColor.blackColor.CGColor;
        [_screen.layer addSublayer:_notch];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.attributedText = [[NSAttributedString alloc]
            initWithString:@"HCG HALO"
                attributes:@{
                    NSFontAttributeName : [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy],
                    NSKernAttributeName : @5.0,
                    NSForegroundColorAttributeName : UIColor.whiteColor,
                }];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.6;
        _titleGradient = [CAGradientLayer layer];
        _titleGradient.colors = @[ (id)HaloTheme.cyan.CGColor, (id)HaloTheme.deepViolet.CGColor,
                                   (id)[HaloTheme colourWithHex:0xC026FF alpha:1].CGColor ];
        _titleGradient.startPoint = CGPointMake(0, 0.5);
        _titleGradient.endPoint = CGPointMake(1, 0.5);
        _titleGradient.mask = _titleLabel.layer;
        [self.layer addSublayer:_titleGradient];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = @"Animated edge lighting";
        _subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = HaloTheme.textPrimary;
        _subtitleLabel.adjustsFontSizeToFitWidth = YES;
        _subtitleLabel.minimumScaleFactor = 0.7;
        [self addSubview:_subtitleLabel];

        _brandLabel = [[UILabel alloc] init];
        _brandLabel.numberOfLines = 2;
        _brandLabel.attributedText = [[NSAttributedString alloc]
            initWithString:@"HAKMI CAPITAL GROUP\nv" HALO_VERSION " · build " HALO_BUILD_ID
                attributes:@{
                    NSFontAttributeName : [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightSemibold],
                    NSKernAttributeName : @1.4,
                    NSForegroundColorAttributeName : HaloTheme.violet,
                }];
        _brandLabel.adjustsFontSizeToFitWidth = YES;
        _brandLabel.minimumScaleFactor = 0.7;
        [self addSubview:_brandLabel];

        _captionLabel = [[UILabel alloc] init];
        _captionLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightSemibold];
        _captionLabel.textColor = HaloTheme.textSecondary;
        _captionLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_captionLabel];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitHeader;

        __weak HaloHeaderView *weakSelf = self;
        void (^refresh)(NSNotification *) = ^(NSNotification *note) {
            HaloHeaderView *strong = weakSelf;
            if (strong && strong->_settings) [strong reloadWithSettings:strong->_settings];
        };
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        _reduceMotionToken = [center addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification
                                                 object:nil
                                                  queue:[NSOperationQueue mainQueue]
                                             usingBlock:refresh];
        _powerToken = [center addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                          object:nil
                                           queue:[NSOperationQueue mainQueue]
                                      usingBlock:refresh];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:_reduceMotionToken];
    [[NSNotificationCenter defaultCenter] removeObserver:_powerToken];
    [_renderer teardown];
}

#pragma mark Preview

- (HaloDisplayGeometry)previewGeometry {
    HaloDisplayGeometry g = _settings.geometry;
    if (g.width <= 0) {
        // No implemented profile: show a plain rounded screen.
        g = (HaloDisplayGeometry){414, 896, 39, HaloCutoutNone, 0, 0, 0, 0, 0};
    }
    return g;
}

- (void)reloadWithSettings:(HaloSettings *)settings {
    _settings = settings;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self configurePreview];
}

- (void)configurePreview {
    if (!_settings || CGRectIsEmpty(_screen.bounds)) return;
    HaloDisplayGeometry g = [self previewGeometry];
    CGFloat s = CGRectGetHeight(_screen.bounds) / (CGFloat)g.height;
    CGAffineTransform t = CGAffineTransformMakeScale(s, s);
    // Exaggerate widths so a 1–3 pt line is still visible at ~20% scale.
    CGFloat unit = MIN(1.0f, s * 2.4f);
    [_renderer setGeometry:g
               traceCutout:_settings.cutoutMode == HaloCutoutTrace
                 transform:t
                 unitScale:unit
                    bounds:_screen.bounds];
    HaloRenderPlan plan = halo_render_plan(_settings.appearance.mode, UIAccessibilityIsReduceMotionEnabled(),
                                           [NSProcessInfo processInfo].lowPowerModeEnabled, _settings.lowPowerPolicy);
    [_renderer setAppearance:_settings.appearance plan:plan];
    [_renderer setPaused:!(self.window && plan.animated)];

    // Notch silhouette and a faint Home Screen grid, in the same scaled space.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _screen.layer.cornerRadius = (CGFloat)g.cornerRadius * s;
    _bezel.layer.cornerRadius = _screen.layer.cornerRadius + 4;
    if (g.cutout == HaloCutoutNotch) {
        CGFloat w = (CGFloat)g.notchWidth * s, h = (CGFloat)g.notchHeight * s;
        CGFloat x = ((CGFloat)g.width / 2 + (CGFloat)g.notchOffsetX) * s - w / 2;
        CGFloat r = MIN((CGFloat)g.notchInnerRadius * s, h);
        _notch.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, -1, w, h + 1)
                                            byRoundingCorners:UIRectCornerBottomLeft | UIRectCornerBottomRight
                                                  cornerRadii:CGSizeMake(r, r)]
                          .CGPath;
    } else {
        _notch.path = nil;
    }
    UIBezierPath *grid = [UIBezierPath bezierPath];
    CGFloat icon = 60 * s, gapX = ((CGFloat)g.width * s - 4 * icon) / 5, top = 70 * s;
    for (int row = 0; row < 5; row++)
        for (int col = 0; col < 4; col++)
            [grid appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(gapX + col * (icon + gapX),
                                                                                top + row * (icon + 30 * s), icon, icon)
                                                        cornerRadius:icon * 0.22f]];
    CGFloat dockH = 92 * s;
    [grid appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(12 * s, CGRectGetHeight(_screen.bounds) - dockH - 12 * s,
                                                                        CGRectGetWidth(_screen.bounds) - 24 * s, dockH)
                                                cornerRadius:26 * s]];
    _homeGrid.path = grid.CGPath;
    [CATransaction commit];

    NSString *state = _settings.enabled ? @"PREVIEW" : @"PREVIEW · HALO IS OFF";
    if (plan.reason[0]) state = [state stringByAppendingFormat:@"\n%s", plan.reason];
    _captionLabel.numberOfLines = 2;
    _captionLabel.text = state.uppercaseString;
    self.accessibilityLabel =
        [NSString stringWithFormat:@"HCG Halo, version %s. Preview of the %@ border. %@", HALO_VERSION,
                                   @(halo_mode_title(plan.mode)), _settings.enabled ? @"Halo is on." : @"Halo is off."];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!_settings) return;
    HaloRenderPlan plan = halo_render_plan(_settings.appearance.mode, UIAccessibilityIsReduceMotionEnabled(),
                                           [NSProcessInfo processInfo].lowPowerModeEnabled, _settings.lowPowerPolicy);
    [_renderer setPaused:!(self.window && plan.animated)];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    HaloDisplayGeometry g = [self previewGeometry];
    CGFloat previewW = kPreviewHeight * (CGFloat)(g.width / g.height);
    CGFloat inset = 20;
    CGRect bezel = CGRectMake(inset, 18, previewW + 8, kPreviewHeight + 8);
    CGRect screen = CGRectMake(4, 4, previewW, kPreviewHeight);
    BOOL changed = !CGRectEqualToRect(_screen.frame, screen);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backdrop.frame = b;
    _bezel.frame = bezel;
    _screen.frame = screen;
    _homeGrid.frame = _screen.bounds;
    _notch.frame = _screen.bounds;
    CGFloat textX = CGRectGetMaxX(bezel) + 18, textW = CGRectGetWidth(b) - textX - inset;
    CGRect titleFrame = CGRectMake(textX, 66, textW, 38);
    _titleGradient.frame = titleFrame;
    _titleLabel.frame = _titleGradient.bounds;
    [_titleLabel setNeedsDisplay]; // the label's layer is a mask, not in the view tree
    [CATransaction commit];

    _subtitleLabel.frame = CGRectMake(textX, CGRectGetMaxY(titleFrame) + 2, textW, 20);
    _brandLabel.frame = CGRectMake(textX, CGRectGetMaxY(_subtitleLabel.frame) + 12, textW, 30);
    _captionLabel.frame = CGRectMake(CGRectGetMinX(bezel) - 10, CGRectGetMaxY(bezel) + 2, CGRectGetWidth(bezel) + 20, 24);
    if (changed) [self configurePreview];
}

@end
