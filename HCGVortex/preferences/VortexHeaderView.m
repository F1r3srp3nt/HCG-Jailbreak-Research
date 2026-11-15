//
//  VortexHeaderView.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexHeaderView.h"
#import <QuartzCore/QuartzCore.h>

#ifndef VORTEX_VERSION
#define VORTEX_VERSION "0.1.0-alpha"
#endif

static UIColor *VortexRGB(unsigned int hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

@implementation VortexTheme
+ (UIColor *)background { return VortexRGB(0x05070D, 1.0); }
+ (UIColor *)panel { return VortexRGB(0x0E1424, 1.0); }
+ (UIColor *)cyan { return VortexRGB(0x00E5FF, 1.0); }
+ (UIColor *)purple { return VortexRGB(0x9D4EDD, 1.0); }
+ (UIColor *)textPrimary { return VortexRGB(0xEAF6FF, 1.0); }
+ (UIColor *)textSecondary { return VortexRGB(0x8A9BB8, 1.0); }
@end

@implementation VortexHeaderView {
    CAGradientLayer *_backdrop;
    CAShapeLayer *_rings;
    CAGradientLayer *_titleGradient;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_brandLabel;
}

static const CGFloat kHeaderHeight = 210.0;

- (instancetype)initWithWidth:(CGFloat)width {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, kHeaderHeight)])) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;

        _backdrop = [CAGradientLayer layer];
        _backdrop.type = kCAGradientLayerRadial;
        _backdrop.colors = @[ (id)VortexRGB(0x2A1150, 0.95).CGColor, (id)VortexRGB(0x0A1A2E, 0.6).CGColor,
                              (id)VortexTheme.background.CGColor ];
        _backdrop.locations = @[ @0.0, @0.55, @1.0 ];
        _backdrop.startPoint = CGPointMake(0.5, 0.45);
        _backdrop.endPoint = CGPointMake(1.15, 1.25);
        [self.layer addSublayer:_backdrop];

        _rings = [CAShapeLayer layer];
        _rings.fillColor = UIColor.clearColor.CGColor;
        _rings.strokeColor = VortexRGB(0x00E5FF, 0.22).CGColor;
        _rings.lineWidth = 1.0;
        [self.layer addSublayer:_rings];

        _titleLabel = [[UILabel alloc] init];
        NSDictionary *titleAttributes = @{
            NSFontAttributeName : [UIFont systemFontOfSize:36 weight:UIFontWeightHeavy],
            NSKernAttributeName : @7.0,
            NSForegroundColorAttributeName : UIColor.whiteColor,
        };
        _titleLabel.attributedText = [[NSAttributedString alloc] initWithString:@"HCG VORTEX" attributes:titleAttributes];
        _titleLabel.textAlignment = NSTextAlignmentCenter;

        // Gradient text: cyan → purple, masked by the title glyphs.
        _titleGradient = [CAGradientLayer layer];
        _titleGradient.colors = @[ (id)VortexTheme.cyan.CGColor, (id)VortexRGB(0x7B61FF, 1).CGColor,
                                   (id)VortexTheme.purple.CGColor ];
        _titleGradient.startPoint = CGPointMake(0, 0.5);
        _titleGradient.endPoint = CGPointMake(1, 0.5);
        _titleGradient.mask = _titleLabel.layer;
        [self.layer addSublayer:_titleGradient];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = @"Advanced Home Screen Animation Engine";
        _subtitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _subtitleLabel.textColor = VortexTheme.textPrimary;
        _subtitleLabel.alpha = 0.85;
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.adjustsFontSizeToFitWidth = YES;
        _subtitleLabel.minimumScaleFactor = 0.7;
        [self addSubview:_subtitleLabel];

        _brandLabel = [[UILabel alloc] init];
        NSDictionary *brandAttributes = @{
            NSFontAttributeName : [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold],
            NSKernAttributeName : @2.0,
            NSForegroundColorAttributeName : VortexRGB(0xB47CFF, 1.0),
        };
        _brandLabel.attributedText = [[NSAttributedString alloc]
            initWithString:@"HAKMI CAPITAL GROUP  ·  v" VORTEX_VERSION
                attributes:brandAttributes];
        _brandLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_brandLabel];

        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"HCG Vortex. Advanced Home Screen Animation Engine. Hakmi Capital Group.";
        self.accessibilityTraits = UIAccessibilityTraitHeader;
    }
    return self;
}

- (UIBezierPath *)ringPathInRect:(CGRect)rect {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint centre = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect) - 14);
    // Concentric, progressively offset arcs: a static "vortex".
    for (int i = 0; i < 7; i++) {
        CGFloat radius = 26.0 + i * 17.0;
        CGFloat start = (CGFloat)(i * 0.55);
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:centre
                                                           radius:radius
                                                       startAngle:start
                                                         endAngle:start + (CGFloat)(M_PI * 1.35)
                                                        clockwise:YES];
        [path appendPath:arc];
    }
    return path;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backdrop.frame = b;
    _rings.frame = b;
    _rings.path = [self ringPathInRect:b].CGPath;

    CGFloat inset = 16.0;
    CGRect titleFrame = CGRectMake(inset, 62, CGRectGetWidth(b) - inset * 2, 46);
    _titleGradient.frame = titleFrame;
    _titleLabel.frame = _titleGradient.bounds;
    [_titleLabel setNeedsDisplay]; // the label's layer is a mask, not in the view tree
    [CATransaction commit];

    _subtitleLabel.frame = CGRectMake(inset, CGRectGetMaxY(titleFrame) + 6, CGRectGetWidth(b) - inset * 2, 22);
    _brandLabel.frame = CGRectMake(inset, CGRectGetMaxY(_subtitleLabel.frame) + 14, CGRectGetWidth(b) - inset * 2, 16);
}

@end
