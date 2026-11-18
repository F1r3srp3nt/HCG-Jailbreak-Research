//
//  PortalPreviewView.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalPreviewView.h"

#import "PortalView.h"

@implementation PortalPreviewView {
    UIView *_screen;           // laid out in screen points, scaled to fit
    CAGradientLayer *_wallpaper;
    UILabel *_clock;
    UILabel *_date;
    NSMutableArray<UIView *> *_widgets;
    NSMutableArray<UIView *> *_notifications;
    UIView *_media;
    UIView *_flashlight;
    UIView *_camera;
    UIView *_homeIndicator;
    PortalView *_portal;
    PortalSettings *_settings;
    PortalPlacement _placement;
    PortalLayout _layout;
    CGSize _screenSize;
    UIEdgeInsets _safe;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 22;
        self.backgroundColor = UIColor.blackColor;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Lock Screen preview";
        CGSize s = UIScreen.mainScreen.bounds.size;
        _screenSize = CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height));
        if (_screenSize.width < 300) _screenSize = CGSizeMake(414, 896);
        // Face ID phones: 44–59 pt top, 34 pt bottom; others 20 / 0.
        BOOL notch = _screenSize.height >= 800;
        _safe = UIEdgeInsetsMake(notch ? 47 : 20, 0, notch ? 34 : 0, 0);
        [self build];
        portal_placement_defaults(&_placement);
    }
    return self;
}

- (PortalLayout)layout {
    return _layout;
}

- (PortalPlacement)placement {
    return _placement;
}

- (CGSize)screenSize {
    return _screenSize;
}

static UIView *Platter(CGRect frame, CGFloat radius) {
    UIView *v = [[UIView alloc] initWithFrame:frame];
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    v.layer.cornerRadius = radius;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    v.userInteractionEnabled = NO;
    return v;
}

static UILabel *Text(NSString *text, CGFloat size, UIFontWeight weight, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    return l;
}

- (void)build {
    CGFloat W = _screenSize.width, H = _screenSize.height;
    _screen = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    _screen.userInteractionEnabled = NO;
    [self addSubview:_screen];

    _wallpaper = [CAGradientLayer layer];
    _wallpaper.frame = _screen.bounds;
    _wallpaper.colors = @[
        (id)[UIColor colorWithRed:0.04 green:0.06 blue:0.16 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.10 green:0.07 blue:0.26 alpha:1].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.13 blue:0.22 alpha:1].CGColor,
    ];
    _wallpaper.startPoint = CGPointMake(0.2, 0);
    _wallpaper.endPoint = CGPointMake(0.8, 1);
    [_screen.layer addSublayer:_wallpaper];

    CGFloat top = _safe.top;
    _date = Text(@"Wednesday 18 November", 20, UIFontWeightSemibold, 0.85);
    _date.textAlignment = NSTextAlignmentCenter;
    _date.frame = CGRectMake(0, top + 18, W, 26);
    [_screen addSubview:_date];
    _clock = Text(@"9:41", 92, UIFontWeightSemibold, 0.95);
    _clock.textAlignment = NSTextAlignmentCenter;
    _clock.frame = CGRectMake(0, top + 40, W, 100);
    [_screen addSubview:_clock];

    _widgets = [NSMutableArray array];
    CGFloat wy = top + 150, ww = (W - 2 * 42 - 2 * 10) / 3;
    for (int i = 0; i < 3; i++) {
        UIView *w = Platter(CGRectMake(42 + i * (ww + 10), wy, ww, 56), 16);
        [_screen addSubview:w];
        [_widgets addObject:w];
    }

    _notifications = [NSMutableArray array];
    NSArray *apps = @[ @"Messages", @"Calendar", @"Reminders" ];
    for (NSUInteger i = 0; i < apps.count; i++) {
        UIView *n = Platter(CGRectZero, 20);
        UILabel *title = Text(apps[i], 14, UIFontWeightSemibold, 0.9);
        title.frame = CGRectMake(56, 12, 220, 18);
        UILabel *body = Text(@"Notification", 14, UIFontWeightRegular, 0.65);
        body.frame = CGRectMake(56, 32, 220, 18);
        UIView *icon = [[UIView alloc] initWithFrame:CGRectMake(12, 14, 34, 34)];
        icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        icon.layer.cornerRadius = 8;
        [n addSubview:icon];
        [n addSubview:title];
        [n addSubview:body];
        [_screen addSubview:n];
        [_notifications addObject:n];
    }

    _media = Platter(CGRectZero, 24);
    UILabel *song = Text(@"Now Playing", 15, UIFontWeightSemibold, 0.9);
    song.frame = CGRectMake(18, 16, 240, 20);
    [_media addSubview:song];
    [_screen addSubview:_media];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    _flashlight = Platter(CGRectMake(46, H - _safe.bottom - 50 - 22, 50, 50), 25);
    _camera = Platter(CGRectMake(W - 46 - 50, H - _safe.bottom - 50 - 22, 50, 50), 25);
    NSArray *symbols = @[ @"flashlight.off.fill", @"camera.fill" ];
    NSArray *buttons = @[ _flashlight, _camera ];
    for (NSUInteger i = 0; i < 2; i++) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[i] withConfiguration:cfg]];
        iv.tintColor = UIColor.whiteColor;
        iv.center = CGPointMake(25, 25);
        [buttons[i] addSubview:iv];
        [_screen addSubview:buttons[i]];
    }
    _homeIndicator = [[UIView alloc] initWithFrame:CGRectMake((W - 134) / 2, H - 13, 134, 5)];
    _homeIndicator.backgroundColor = [UIColor colorWithWhite:1 alpha:0.8];
    _homeIndicator.layer.cornerRadius = 2.5;
    [_screen addSubview:_homeIndicator];

    _portal = [[PortalView alloc] initWithFrame:CGRectMake(0, 0, PORTAL_SIZE_DEFAULT, PORTAL_SIZE_DEFAULT)];
    [_screen addSubview:_portal];
    [self layoutSamples];
}

- (void)layoutSamples {
    CGFloat W = _screenSize.width, H = _screenSize.height;
    CGFloat bottom = H - _safe.bottom - 50 - 22 - 16; // above the quick actions
    CGFloat y = bottom;
    _media.hidden = !_showsMedia;
    if (_showsMedia) {
        y -= 120;
        _media.frame = CGRectMake(12, y, W - 24, 120);
        y -= 10;
    }
    for (NSUInteger i = 0; i < _notifications.count; i++) {
        UIView *n = _notifications[i];
        n.hidden = !_showsNotifications;
        if (!_showsNotifications) continue;
        y -= 64;
        n.frame = CGRectMake(12, y, W - 24, 64);
        y -= 8;
    }
}

- (void)setShowsNotifications:(BOOL)shows {
    _showsNotifications = shows;
    [self layoutSamples];
    [self relayoutPortal];
}

- (void)setShowsMedia:(BOOL)shows {
    _showsMedia = shows;
    [self layoutSamples];
    [self relayoutPortal];
}

- (CGFloat)anchor {
    return CGRectGetMaxY(_widgets.firstObject.frame);
}

- (void)reloadWithSettings:(PortalSettings *)settings {
    _settings = settings;
    _placement = settings.placement;
    PortalAppearance a = settings.appearance;
    PortalRenderPlan plan = portal_render_plan(&a, UIAccessibilityIsReduceMotionEnabled(),
                                               [NSProcessInfo processInfo].lowPowerModeEnabled, settings.lowPowerPolicy,
                                               settings.unlockAnimation);
    // The preview always draws, so the look can be adjusted even when Low Power hides the portal.
    if (!plan.draw) {
        plan = portal_render_plan(&a, 1, 0, PORTAL_LOWPOWER_STATIC, 0);
    }
    [_portal applyAppearance:a plan:plan];
    [self relayoutPortal];
}

- (void)setPlacement:(PortalPlacement)placement {
    portal_placement_clamp(&placement);
    _placement = placement;
    [self relayoutPortal];
}

- (void)relayoutPortal {
    PortalLayoutInput in;
    memset(&in, 0, sizeof in);
    in.bounds = (PortalRect){0, 0, _screenSize.width, _screenSize.height};
    in.safe = (PortalRect){0, _safe.top, _screenSize.width, _screenSize.height - _safe.top - _safe.bottom};
    in.anchorKnown = 1;
    in.anchorBottom = self.anchor;
    NSMutableArray<UIView *> *obstacles = [NSMutableArray arrayWithObjects:_flashlight, _camera, nil];
    if (_showsMedia) [obstacles addObject:_media];
    if (_showsNotifications) [obstacles addObjectsFromArray:_notifications];
    for (UIView *v in obstacles) {
        CGRect f = v.frame;
        in.obstacles[in.obstacleCount++] = (PortalRect){f.origin.x, f.origin.y, f.size.width, f.size.height};
    }
    _layout = portal_layout(&in, &_placement);
    _portal.hidden = _layout.mode == PORTAL_LAYOUT_HIDDEN;
    _portal.bounds = CGRectMake(0, 0, (CGFloat)_layout.diameter, (CGFloat)_layout.diameter);
    _portal.center = CGPointMake((CGFloat)_layout.cx, (CGFloat)_layout.cy);
    NSString *mode = _layout.mode == PORTAL_LAYOUT_FULL      ? @"full size"
                     : _layout.mode == PORTAL_LAYOUT_REDUCED ? @"reduced to fit"
                     : _layout.mode == PORTAL_LAYOUT_COMPACT ? @"collapsed to a compact orb"
                                                             : @"hidden: no room";
    self.accessibilityValue = [NSString stringWithFormat:@"Portal %@, %.0f points", mode, _layout.diameter];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = MIN(self.bounds.size.width / _screenSize.width, self.bounds.size.height / _screenSize.height);
    _screen.transform = CGAffineTransformMakeScale(scale, scale);
    _screen.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (CGPoint)screenPointFromPoint:(CGPoint)point {
    return [self convertPoint:point toView:_screen];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    _portal.paused = self.window == nil;
}

@end
