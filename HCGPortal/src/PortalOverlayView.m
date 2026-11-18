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
        dispatch_async(dispatch_get_main_queue(), ^{
            [self collapseAnimated:YES];
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

- (void)setMainItems:(NSArray<PortalMenuItem *> *)items {
    _mainItems = [items copy];
    if ([_ringName isEqualToString:@"main"]) [self installItems:_mainItems];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == self->_idleGeneration) [self collapseAnimated:YES];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->_messageGeneration) return;
        void (^hide)(void) = ^{
            self->_message.alpha = 0;
        };
        if (self->_animationsAllowed) [UIView animateWithDuration:0.3 animations:hide];
        else hide();
    });
}

@end
