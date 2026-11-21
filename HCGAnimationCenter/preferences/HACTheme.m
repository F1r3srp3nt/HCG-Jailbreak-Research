//
//  HACTheme.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACTheme.h"
#import "HCGBackgroundCore.h"

UIColor *HACAccentColor(void) {
    return [UIColor colorWithRed:0.53 green:0.42 blue:1.0 alpha:1]; // #876BFF
}

UIColor *HACSecondaryAccentColor(void) {
    return [UIColor colorWithRed:0.0 green:0.9 blue:1.0 alpha:1]; // HCG cyan
}

void HACApplyTheme(UIViewController *controller) {
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    controller.view.tintColor = HACAccentColor();
    controller.navigationController.navigationBar.tintColor = HACAccentColor();
}

UIButton *HACMakeButton(NSString *title, NSString *systemImage, BOOL prominent) {
    UIButtonConfiguration *config = prominent ? [UIButtonConfiguration filledButtonConfiguration]
                                              : [UIButtonConfiguration tintedButtonConfiguration];
    config.title = title;
    if (systemImage) {
        config.image = [UIImage systemImageNamed:systemImage];
        config.imagePadding = 6;
    }
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.baseBackgroundColor = prominent ? HACAccentColor() : nil;
    config.baseForegroundColor = prominent ? UIColor.whiteColor : HACAccentColor();
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

NSString *HACFormatSeconds(NSTimeInterval seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    if (seconds < 60) return [NSString stringWithFormat:@"%.1f s", seconds];
    long whole = lround(seconds);
    return [NSString stringWithFormat:@"%ld min %02ld s", whole / 60, whole % 60];
}

NSString *HACDescribePreset(HCGBackgroundPreset *preset) {
    NSString *origin = [preset.origin isEqualToString:@"gif"] ? @"from GIF"
                       : [preset.origin isEqualToString:@"ai"] ? @"AI preview"
                                                               : @"video";
    return [NSString stringWithFormat:@"%.0f × %.0f · %@ · %@", preset.mediaSize.width, preset.mediaSize.height,
                                      HACFormatSeconds(preset.duration), origin];
}

NSString *HACDescribeTransform(HCGBackgroundPreset *preset) {
    NSMutableArray *parts = [NSMutableArray array];
    if (preset.rotation) [parts addObject:[NSString stringWithFormat:@"rotated %ld°", (long)preset.rotation]];
    if (preset.flipHorizontal) [parts addObject:@"flipped horizontally"];
    if (preset.flipVertical) [parts addObject:@"flipped vertically"];
    if (preset.stretch) [parts addObject:@"stretch"];
    if (!parts.count) return @"Original orientation";
    NSString *text = [parts componentsJoinedByString:@" · "];
    return [[text substringToIndex:1].uppercaseString stringByAppendingString:[text substringFromIndex:1]];
}

NSString *HACDescribeSource(HCGBackgroundPreset *preset) {
    NSString *size = [NSString stringWithFormat:@"%.0f × %.0f", preset.mediaSize.width, preset.mediaSize.height];
    NSString *metadata = preset.sourceRotation > 0
                             ? [NSString stringWithFormat:@"metadata rotation %ld° applied", (long)preset.sourceRotation]
                         : preset.sourceRotation == 0 ? @"no metadata rotation"
                                                      : @"orientation as recorded";
    BOOL converted = [preset.generator[@"converted"] isEqual:@YES];
    return [NSString stringWithFormat:@"%@ · %@%@", size, metadata, converted ? @" · converted on import" : @""];
}

UIImage *HACOrientedImage(UIImage *image, HCGBackgroundPreset *preset) {
    if (!image || preset.isTransformIdentity || (!preset.rotation && !preset.flipHorizontal && !preset.flipVertical))
        return image;
    CGSize size = image.size;
    HCGBGSize media = {size.width, size.height};
    HCGBGSize oriented = hcgbg_oriented_size(media, (int)preset.rotation);
    HCGBGTransform t = hcgbg_transform_identity();
    t.rotation = (int)preset.rotation;
    t.flipHorizontal = preset.flipHorizontal;
    t.flipVertical = preset.flipVertical;
    HCGBGPlacement p = hcgbg_layout_transformed(oriented, media, HCGBGScalingFill, (HCGBGRect){0, 0, 1, 1}, t);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = image.scale;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(oriented.width, oriented.height) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx = context.CGContext;
        CGContextTranslateCTM(ctx, p.frame.x + p.frame.width / 2, p.frame.y + p.frame.height / 2);
        CGContextConcatCTM(ctx, CGAffineTransformMake(p.a, p.b, p.c, p.d, 0, 0));
        [image drawInRect:CGRectMake(-p.bounds.width / 2, -p.bounds.height / 2, p.bounds.width, p.bounds.height)];
    }];
}

@implementation HACPreviewStage {
    UIView *_overlayView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CGRect screen = UIScreen.mainScreen.bounds;
        _screenSize = CGSizeMake(MIN(screen.size.width, screen.size.height), MAX(screen.size.width, screen.size.height));
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        self.layer.cornerRadius = 22;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 3;
        self.layer.borderColor = [UIColor colorWithWhite:0.22 alpha:1].CGColor;
        self.clipsToBounds = YES;
        _background = [[HCGBackgroundView alloc] initWithFrame:self.bounds];
        _background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_background];
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Background preview";
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric);
}

- (void)setOverlay:(HACStageOverlay)overlay {
    _overlay = overlay;
    [_overlayView removeFromSuperview];
    _overlayView = nil;
    if (overlay == HACStageOverlayNone) return;
    _overlayView = [[UIView alloc] initWithFrame:self.bounds];
    _overlayView.userInteractionEnabled = NO;
    _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_overlayView];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_overlayView) return;
    for (UIView *v in [_overlayView.subviews copy]) [v removeFromSuperview];
    CGSize b = self.bounds.size;
    CGFloat k = b.width / _screenSize.width; // stage points per screen point
    if (_overlay == HACStageOverlayHomeIcons) {
        // A 4 × 6 icon grid and a dock, at iPhone proportions, to judge legibility.
        CGFloat icon = 60 * k, gapX = (b.width - 4 * icon) / 5, top = 70 * k, rowStep = 92 * k;
        for (int row = 0; row < 6; row++) {
            for (int col = 0; col < 4; col++) {
                UIView *v = [[UIView alloc] initWithFrame:CGRectMake(gapX + col * (icon + gapX), top + row * rowStep, icon, icon)];
                v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.28];
                v.layer.cornerRadius = icon * 0.225;
                v.layer.cornerCurve = kCACornerCurveContinuous;
                [_overlayView addSubview:v];
            }
        }
        UIView *dock = [[UIView alloc] initWithFrame:CGRectMake(12 * k, b.height - 104 * k, b.width - 24 * k, 92 * k)];
        dock.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
        dock.layer.cornerRadius = 30 * k;
        [_overlayView addSubview:dock];
    } else if (_overlay == HACStageOverlayLockClock) {
        UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(0, 110 * k, b.width, 90 * k)];
        time.text = @"9:41";
        time.textAlignment = NSTextAlignmentCenter;
        time.textColor = UIColor.whiteColor;
        time.font = [UIFont systemFontOfSize:88 * k weight:UIFontWeightSemibold];
        UILabel *date = [[UILabel alloc] initWithFrame:CGRectMake(0, 80 * k, b.width, 30 * k)];
        date.text = @"Wednesday 18 November";
        date.textAlignment = NSTextAlignmentCenter;
        date.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        date.font = [UIFont systemFontOfSize:20 * k weight:UIFontWeightMedium];
        [_overlayView addSubview:time];
        [_overlayView addSubview:date];
    }
}

@end
