//
//  VortexTornadoPreviewCell.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexTornadoPreviewCell.h"
#import "VortexHeaderView.h"
#import "VortexMath.h"
#import "VortexPreferences.h"
#import "VortexTornado.h"

#import <QuartzCore/QuartzCore.h>

static const double kPageWidth = 390.0, kPageHeight = 844.0, kIcon = 60.0;
static const int kCols = 4, kRows = 6, kIcons = 24;
static const CFTimeInterval kCycle = 4.0; // swipe forward, hold, reverse, hold

@implementation VortexTornadoPreviewCell {
    UIView *_stage;
    CALayer *_pages[2];
    CALayer *_tiles[2][24];
    UILabel *_caption;
    CADisplayLink *_link;
    CFTimeInterval _start;
    VortexIconSlot _slots[24];
    VortexTornadoParameters _tornado;
    NSUInteger _frames;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier])) {
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
            [_stage.layer addSublayer:_pages[p]]; // outgoing below incoming, as on the Home Screen
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
        [self reloadParameters];
    }
    return self;
}

- (void)reloadParameters {
    _tornado = [VortexPreferences loadConfiguration].tornadoParameters;
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
    _caption.text = still ? @"Reduce Motion is on: Tornado is replaced by the stock animation. Still frame shown."
                          : @"Live preview of the Tornado geometry with your settings (mock icons, not your Home Screen).";
    if (self.window && !still) {
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
    // forward 0..0.4, hold 0.4..0.5, reverse 0.5..0.9, hold
    if (t < 0.4) return t / 0.4;
    if (t < 0.5) return 1.0;
    if (t < 0.9) return 1.0 - (t - 0.5) / 0.4;
    return 0.0;
}

- (void)tick:(CADisplayLink *)link {
    if (++_frames % 15 == 0) [self reloadParameters]; // pick up slider changes within ~0.5 s
    [self renderAtProgress:[self progressNow]];
}

- (void)renderAtProgress:(double)progress {
    CGRect b = _stage.bounds;
    if (CGRectGetWidth(b) < 1.0) return;
    CGFloat k = CGRectGetWidth(b) / kPageWidth;
    VortexEffectParameters ep = vortex_default_parameters();
    VortexTornadoParameters tp = _tornado;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int p = 0; p < 2; p++) {
        VortexPageRole role = p == 0 ? VortexPageRoleOutgoing : VortexPageRoleIncoming;
        VortexPageVisual page = vortex_tornado_page(role, progress, &ep);
        _pages[p].frame = b;
        _pages[p].opacity = (float)page.opacity;
        for (int i = 0; i < kIcons; i++) {
            VortexIconVisual v = vortex_tornado_icon(role, progress, VortexNavigationForward, _slots[i], kPageWidth,
                                                     kPageHeight, &tp, &ep);
            CALayer *tile = _tiles[p][i];
            tile.position = CGPointMake((kPageWidth / 2.0 + _slots[i].homeX + v.tx) * k,
                                        (kPageHeight / 2.0 + _slots[i].homeY + v.ty) * k);
            CATransform3D t = CATransform3DMakeScale((CGFloat)(v.scale * k), (CGFloat)(v.scale * k), 1);
            if (v.rotation != 0.0) t = CATransform3DRotate(t, (CGFloat)v.rotation, 0, 0, 1);
            tile.transform = t;
            tile.zPosition = (CGFloat)v.z;
            tile.opacity = (float)v.opacity;
        }
    }
    [CATransaction commit];
}

@end
