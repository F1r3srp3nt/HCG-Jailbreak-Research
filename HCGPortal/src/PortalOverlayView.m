//
//  PortalOverlayView.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalOverlayView.h"

#import "PortalView.h"

@implementation PortalMenuItem

+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol destination:(int)destination item:(int)item {
    PortalMenuItem *i = [[PortalMenuItem alloc] init];
    i.title = title;
    i.symbolName = symbol;
    i.destination = destination;
    i.item = item;
    i.availability = PORTAL_AVAIL_AVAILABLE;
    i.statusText = @"";
    return i;
}

@end

#pragma mark - Controls

/// A circular control: its touch area is the circle, never the square.
@interface PortalCircleControl : UIControl
@property (nonatomic) CGFloat touchRadius;
@end

@implementation PortalCircleControl
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat r = self.touchRadius > 0 ? self.touchRadius : MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    CGPoint c = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    return hypot(point.x - c.x, point.y - c.y) <= r;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.02 || !self.userInteractionEnabled) return nil;
    return [self pointInside:point withEvent:event] ? self : nil;
}
@end

@interface PortalItemControl : PortalCircleControl
@property (nonatomic, strong) PortalMenuItem *item;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UILabel *badge;
@end

@implementation PortalItemControl

- (instancetype)initWithItem:(PortalMenuItem *)item palette:(int)palette {
    CGFloat s = PORTAL_MENU_ITEM_SIZE;
    if ((self = [super initWithFrame:CGRectMake(0, 0, s, s)])) {
        _item = item;
        BOOL available = item.availability == PORTAL_AVAIL_AVAILABLE;
        PortalRGB primary, secondary;
        portal_palette_colours(palette, &primary, &secondary);
        UIColor *accent = [UIColor colorWithRed:primary.r green:primary.g blue:primary.b alpha:1];
        self.layer.cornerRadius = s / 2;
        self.backgroundColor = [UIColor colorWithRed:0.03 green:0.05 blue:0.12 alpha:0.86];
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = (available ? [accent colorWithAlphaComponent:0.9] : [UIColor colorWithWhite:0.6 alpha:0.45]).CGColor;
        self.layer.shadowColor = accent.CGColor;
        self.layer.shadowRadius = available ? 8 : 0;
        self.layer.shadowOpacity = available ? 0.55f : 0;
        self.layer.shadowOffset = CGSizeZero;

        _icon = [[UIImageView alloc] initWithFrame:CGRectInset(self.bounds, 17, 17)];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.userInteractionEnabled = NO;
        if (item.image) {
            _icon.frame = CGRectInset(self.bounds, 12, 12);
            _icon.image = item.image;
            _icon.layer.cornerRadius = 9;
            _icon.clipsToBounds = YES;
            _icon.alpha = available ? 1 : 0.45;
        } else {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22
                                                                                                 weight:UIImageSymbolWeightSemibold];
            _icon.image = [UIImage systemImageNamed:item.symbolName withConfiguration:config];
            _icon.tintColor = available ? UIColor.whiteColor : [UIColor colorWithWhite:0.75 alpha:0.7];
        }
        [self addSubview:_icon];

        _label = [[UILabel alloc] initWithFrame:CGRectMake(-24, s + 4, s + 48, 16)];
        _label.text = item.title;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _label.textColor = available ? UIColor.whiteColor : [UIColor colorWithWhite:0.85 alpha:0.8];
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.75;
        _label.layer.shadowColor = UIColor.blackColor.CGColor;
        _label.layer.shadowRadius = 3;
        _label.layer.shadowOpacity = 0.9f;
        _label.layer.shadowOffset = CGSizeZero;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        if (!available && item.statusText.length) {
            _badge = [[UILabel alloc] initWithFrame:CGRectMake(-24, s + 20, s + 48, 13)];
            _badge.text = item.statusText;
            _badge.textAlignment = NSTextAlignmentCenter;
            _badge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
            _badge.textColor = [UIColor colorWithWhite:0.8 alpha:0.85];
            _badge.adjustsFontSizeToFitWidth = YES;
            _badge.minimumScaleFactor = 0.7;
            _badge.layer.shadowColor = UIColor.blackColor.CGColor;
            _badge.layer.shadowRadius = 3;
            _badge.layer.shadowOpacity = 0.9f;
            _badge.layer.shadowOffset = CGSizeZero;
            _badge.userInteractionEnabled = NO;
            [self addSubview:_badge];
        }

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton | (available ? 0 : UIAccessibilityTraitNotEnabled);
        self.accessibilityLabel = item.title;
        self.accessibilityValue = available ? nil : item.statusText;
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
}

@end

#pragma mark - Overlay

@implementation PortalOverlayView {
    PortalView *_portalView;
    PortalCircleControl *_orb;
    NSMutableArray<PortalItemControl *> *_controls;
    NSArray<PortalMenuItem *> *_mainItems;
    NSArray<PortalMenuItem *> *_items;
    UILabel *_message;
    PortalLayout _layout;
    PortalRect _safe;
    NSTimeInterval _lastOutsideEvent;
    NSUInteger _messageGeneration;
    NSUInteger _idleGeneration;
    NSUInteger _detachGeneration; // bumped by -prepareForDetach: cancels a pending tap-outside collapse
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.isAccessibilityElement = NO;
        _animationsAllowed = YES;
        _ringName = @"main";
        _controls = [NSMutableArray array];
        _mainItems = @[];
        _items = @[];

        _orb = [[PortalCircleControl alloc] initWithFrame:CGRectMake(0, 0, PORTAL_SIZE_DEFAULT, PORTAL_SIZE_DEFAULT)];
        _orb.backgroundColor = UIColor.clearColor;
        _orb.isAccessibilityElement = YES;
        _orb.accessibilityLabel = @"HCG Portal";
        _orb.accessibilityHint = @"Shows Portal destinations.";
        _orb.accessibilityTraits = UIAccessibilityTraitButton;
        [_orb addTarget:self action:@selector(orbTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_orb];

        _portalView = [[PortalView alloc] initWithFrame:_orb.bounds];
        _portalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_orb addSubview:_portalView];

        _message = [[UILabel alloc] initWithFrame:CGRectZero];
        _message.numberOfLines = 2;
        _message.textAlignment = NSTextAlignmentCenter;
        _message.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _message.textColor = UIColor.whiteColor;
        _message.backgroundColor = [UIColor colorWithRed:0.03 green:0.05 blue:0.12 alpha:0.88];
        _message.layer.cornerRadius = 12;
        _message.layer.masksToBounds = YES;
        _message.alpha = 0;
        _message.userInteractionEnabled = NO;
        _message.isAccessibilityElement = NO;
        [self addSubview:_message];
    }
    return self;
}

- (PortalView *)portalView {
    return _portalView;
}

- (PortalLayout)layout {
    return _layout;
}

- (CGRect)orbFrame {
    return _orb.frame;
}

- (NSArray<UIControl *> *)itemControls {
    return [_controls copy];
}

- (NSArray<PortalMenuItem *> *)currentItems {
    return _items;
}

- (NSString *)visibleMessage {
    return _message.alpha > 0.01 ? _message.text : nil;
}

#pragma mark Touches

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL touch = event != nil && event.type == UIEventTypeTouches;
    return [self portalHitTest:point touch:touch timestamp:touch ? event.timestamp : 0];
}

- (UIView *)portalHitTest:(CGPoint)point touch:(BOOL)touch timestamp:(NSTimeInterval)timestamp {
    if (self.hidden || self.alpha < 0.02 || !self.userInteractionEnabled || _layout.mode == PORTAL_LAYOUT_HIDDEN) return nil;
    if (_expanded) {
        for (PortalItemControl *c in _controls) {
            UIView *hit = [c hitTest:[self convertPoint:point toView:c] withEvent:nil];
            if (hit) return hit;
        }
    }
    UIView *orbHit = [_orb hitTest:[self convertPoint:point toView:_orb] withEvent:nil];
    if (orbHit) return orbHit;
    if (_expanded && touch && timestamp != _lastOutsideEvent) {
        // Tap outside: collapse, and let the touch reach what is underneath.
        _lastOutsideEvent = timestamp;
        __weak PortalOverlayView *weakSelf = self;
        NSUInteger detachGeneration = _detachGeneration;
        dispatch_async(dispatch_get_main_queue(), ^{
            PortalOverlayView *strongSelf = weakSelf;
            // Never acts on an overlay that has left the Lock Screen since the tap.
            if (strongSelf && detachGeneration == strongSelf->_detachGeneration) [strongSelf collapseAnimated:YES];
        });
    }
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [self portalHitTest:point touch:NO timestamp:0] != nil;
}

- (NSArray *)accessibilityElements {
    if (self.hidden || _layout.mode == PORTAL_LAYOUT_HIDDEN) return @[];
    NSMutableArray *elements = [NSMutableArray arrayWithObject:_orb];
    if (_expanded) [elements addObjectsFromArray:_controls];
    return elements;
}

#pragma mark Layout

- (void)applyLayout:(PortalLayout)layout safe:(PortalRect)safe animated:(BOOL)animated {
    BOOL changed = layout.mode != _layout.mode || fabs(layout.cx - _layout.cx) > 0.5 || fabs(layout.cy - _layout.cy) > 0.5 ||
                   fabs(layout.diameter - _layout.diameter) > 0.5;
    _layout = layout;
    _safe = safe;
    if (layout.mode == PORTAL_LAYOUT_HIDDEN) {
        if (_expanded) [self collapseAnimated:NO];
        _orb.hidden = YES;
        return;
    }
    _orb.hidden = NO;
    if (!changed && !CGRectIsEmpty(_orb.frame)) return;
    void (^apply)(void) = ^{
        CGFloat d = (CGFloat)layout.diameter;
        self->_orb.bounds = CGRectMake(0, 0, d, d);
        self->_orb.center = CGPointMake((CGFloat)layout.cx, (CGFloat)layout.cy);
        self->_orb.touchRadius = (CGFloat)layout.hitRadius;
        [self layoutItems];
        [self layoutMessage];
    };
    if (animated && _animationsAllowed && !CGRectIsEmpty(_orb.frame)) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:apply completion:nil];
    } else {
        apply();
    }
    _orb.accessibilityHint = layout.mode == PORTAL_LAYOUT_COMPACT ? @"Compact. Shows Portal destinations." : @"Shows Portal destinations.";
}

- (void)layoutItems {
    PortalMenuLayout m = portal_menu_layout(&_layout, (int)_controls.count, &_safe);
    for (NSUInteger i = 0; i < _controls.count; i++) {
        PortalItemControl *c = _controls[i];
        c.center = _expanded ? CGPointMake((CGFloat)m.x[i], (CGFloat)m.y[i]) : _orb.center;
    }
}

- (void)layoutMessage {
    CGFloat width = MIN((CGFloat)_safe.w - 48, 300);
    CGSize fit = [_message sizeThatFits:CGSizeMake(width - 24, 60)];
    CGFloat w = MIN(width, fit.width + 28), h = MAX(30, fit.height + 14);
    CGFloat y = CGRectGetMaxY(_orb.frame) + 10;
    if (_expanded) {
        PortalMenuLayout m = portal_menu_layout(&_layout, (int)_controls.count, &_safe);
        y = (CGFloat)(_layout.cy + m.extentRadius + 22);
    }
    if (y + h > _safe.y + _safe.h - 8) y = CGRectGetMinY(_orb.frame) - h - 10;
    _message.frame = CGRectMake((CGFloat)_layout.cx - w / 2, y, w, h);
    CGRect f = _message.frame;
    if (f.origin.x < _safe.x + 8) f.origin.x = (CGFloat)_safe.x + 8;
    if (CGRectGetMaxX(f) > _safe.x + _safe.w - 8) f.origin.x = (CGFloat)(_safe.x + _safe.w - 8) - f.size.width;
    _message.frame = f;
}

#pragma mark Items

static NSString *PortalItemsSignature(NSArray<PortalMenuItem *> *items) {
    NSMutableString *sig = [NSMutableString string];
    for (PortalMenuItem *i in items)
        [sig appendFormat:@"%d/%d/%d/%@/%@|", i.destination, i.item, (int)i.availability, i.title, i.statusText];
    return sig;
}

- (void)setMainItems:(NSArray<PortalMenuItem *> *)items {
    // Rebuild the controls only when something a user can see changed (0.1.0~beta2
    // rebuilt all four on every update, i.e. after every Lock Screen layout pass).
    if (_mainItems.count && [PortalItemsSignature(items) isEqualToString:PortalItemsSignature(_mainItems)]) return;
    _mainItems = [items copy];
    if ([_ringName isEqualToString:@"main"]) [self installItems:_mainItems];
}

- (void)prepareForDetach {
    // Every pending callback (idle collapse, message fade, tap-outside collapse) checks a
    // generation, so nothing acts on this view after it leaves the Lock Screen.
    _detachGeneration++;
    _idleGeneration++;
    _messageGeneration++;
    if (_expanded) [self collapseAnimated:NO];
    _message.alpha = 0;
    _portalView.paused = YES;
    [self.layer removeAllAnimations];
    for (UIView *v in self.subviews) [v.layer removeAllAnimations];
}

- (void)showAppItems:(NSArray<PortalMenuItem *> *)items {
    _ringName = @"apps";
    [self installItems:items];
    [self expandControlsAnimated:YES];
    _orb.accessibilityHint = @"Back to Portal destinations.";
}

- (void)installItems:(NSArray<PortalMenuItem *> *)items {
    for (PortalItemControl *c in _controls) [c removeFromSuperview];
    [_controls removeAllObjects];
    _items = [items copy];
    int palette = self.palette;
    for (PortalMenuItem *item in _items) {
        PortalItemControl *c = [[PortalItemControl alloc] initWithItem:item palette:palette];
        c.alpha = _expanded ? 1 : 0;
        c.hidden = !_expanded;
        c.center = _orb.center;
        [c addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self insertSubview:c belowSubview:_message];
        [_controls addObject:c];
    }
    [self layoutItems];
}

#pragma mark Expand / collapse

- (void)orbTapped {
    if (!_expanded) {
        [self expand];
    } else if ([_ringName isEqualToString:@"apps"]) {
        _ringName = @"main";
        [self installItems:_mainItems];
        [self expandControlsAnimated:YES];
        _orb.accessibilityHint = @"Hides Portal destinations.";
    } else {
        [self collapseAnimated:YES];
    }
}

- (void)expand {
    if (_expanded || _layout.mode == PORTAL_LAYOUT_HIDDEN) return;
    if ([self.delegate respondsToSelector:@selector(portalOverlayWillExpand:)]) [self.delegate portalOverlayWillExpand:self];
    _expanded = YES;
    _ringName = @"main";
    [self installItems:_mainItems];
    [_portalView setExpanded:YES animated:_animationsAllowed];
    [self expandControlsAnimated:YES];
    _orb.accessibilityHint = @"Hides Portal destinations.";
    [self armIdleCollapse];
    [self.delegate portalOverlayDidExpand:self];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, _controls.firstObject);
}

- (void)expandControlsAnimated:(BOOL)animated {
    PortalMenuLayout m = portal_menu_layout(&_layout, (int)_controls.count, &_safe);
    void (^apply)(void) = ^{
        for (NSUInteger i = 0; i < self->_controls.count; i++) {
            PortalItemControl *c = self->_controls[i];
            c.hidden = NO;
            c.alpha = 1;
            c.center = CGPointMake((CGFloat)m.x[i], (CGFloat)m.y[i]);
        }
    };
    if (animated && _animationsAllowed) {
        for (PortalItemControl *c in _controls) {
            c.hidden = NO;
            c.center = _orb.center;
            c.alpha = 0;
        }
        [UIView animateWithDuration:0.32
                              delay:0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.4
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:apply
                         completion:nil];
    } else {
        apply();
    }
    [self layoutMessage];
}

- (void)collapseAnimated:(BOOL)animated {
    if (!_expanded) return;
    _expanded = NO;
    _ringName = @"main";
    _idleGeneration++;
    [_portalView setExpanded:NO animated:animated && _animationsAllowed];
    NSArray *controls = [_controls copy];
    void (^apply)(void) = ^{
        for (PortalItemControl *c in controls) {
            c.alpha = 0;
            c.center = self->_orb.center;
        }
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (self->_expanded) return;
        for (PortalItemControl *c in controls) c.hidden = YES;
        [self installItems:self->_mainItems];
    };
    if (animated && _animationsAllowed) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:apply completion:done];
    } else {
        apply();
        done(YES);
    }
    _orb.accessibilityHint = @"Shows Portal destinations.";
    [self layoutMessage];
    [self.delegate portalOverlayDidCollapse:self];
}

- (void)armIdleCollapse {
    NSUInteger generation = ++_idleGeneration;
    __weak PortalOverlayView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PortalOverlayView *strongSelf = weakSelf;
        if (strongSelf && generation == strongSelf->_idleGeneration) [strongSelf collapseAnimated:YES];
    });
}

- (void)itemTapped:(PortalItemControl *)control {
    [self armIdleCollapse];
    [self.delegate portalOverlay:self didSelectItem:control.item];
}

#pragma mark Message

- (void)showMessage:(NSString *)message {
    NSUInteger generation = ++_messageGeneration;
    _message.text = message;
    [self layoutMessage];
    [self bringSubviewToFront:_message];
    void (^show)(void) = ^{
        self->_message.alpha = message.length ? 1 : 0;
    };
    if (_animationsAllowed) [UIView animateWithDuration:0.18 animations:show];
    else show();
    if (message.length) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    __weak PortalOverlayView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PortalOverlayView *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf->_messageGeneration) return;
        UILabel *message = strongSelf->_message;
        void (^hide)(void) = ^{
            message.alpha = 0;
        };
        if (strongSelf->_animationsAllowed && strongSelf.superview) [UIView animateWithDuration:0.3 animations:hide];
        else hide();
    });
}

@end
