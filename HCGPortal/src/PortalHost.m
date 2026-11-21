//
//  PortalHost.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalHost.h"

@interface NSObject (PortalCoverSheet)
- (id)mainPageContentViewController;
- (id)dateView;
- (id)dateViewController;
- (id)complicationContainerViewController;
@end

@implementation PortalHostMeasurement
@end

static const NSUInteger kMaxViewsVisited = 2500;
static const NSUInteger kMaxDepth = 18;

static BOOL PortalViewIsShown(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.02) return NO;
        if ([v isKindOfClass:[UIWindow class]]) break;
    }
    return view.window != nil && view.bounds.size.width > 1 && view.bounds.size.height > 1;
}

@implementation PortalHost

+ (UIView *)hostViewForCoverSheet:(UIViewController *)coverSheet reason:(NSString **)reason {
    // Only the Lock Screen's main page is an acceptable container. There is deliberately
    // no fallback (0.1.0~beta1/2 fell back to the Cover Sheet's own root view): if the
    // expected container is unavailable, Portal stays hidden and the Lock Screen is untouched.
    if (!coverSheet) {
        if (reason) *reason = @"Lock Screen container unavailable: no Cover Sheet view controller";
        return nil;
    }
    if (![coverSheet respondsToSelector:@selector(mainPageContentViewController)]) {
        if (reason) *reason = @"Lock Screen container unavailable: no mainPageContentViewController on this iOS";
        return nil;
    }
    id main = [coverSheet mainPageContentViewController];
    if (![main isKindOfClass:[UIViewController class]]) {
        if (reason) *reason = @"Lock Screen container unavailable: no main page controller";
        return nil;
    }
    Class expected = NSClassFromString(@"CSMainPageContentViewController");
    if (expected && ![main isKindOfClass:expected]) {
        if (reason) *reason = [NSString stringWithFormat:@"Lock Screen container unavailable: unexpected %@", NSStringFromClass([main class])];
        return nil;
    }
    if (![main isViewLoaded]) {
        if (reason) *reason = @"Lock Screen container unavailable: main page not loaded";
        return nil;
    }
    UIView *view = [main view];
    if (!view.window || view.window.hidden || view.bounds.size.width < 1 || view.bounds.size.height < 1) {
        if (reason) *reason = @"Lock Screen container unavailable: main page not on screen";
        return nil;
    }
    if (reason) *reason = [NSString stringWithFormat:@"%@.view", NSStringFromClass([main class])];
    return view;
}

static BOOL NameHas(NSString *name, NSArray<NSString *> *tokens) {
    for (NSString *t in tokens)
        if ([name rangeOfString:t].location != NSNotFound) return YES;
    return NO;
}

static UIView *ViewOf(id object) {
    if ([object isKindOfClass:[UIView class]]) return object;
    if ([object isKindOfClass:[UIViewController class]] && [object isViewLoaded]) return [object view];
    return nil;
}

+ (PortalHostMeasurement *)measureHost:(UIView *)host coverSheet:(UIViewController *)coverSheet exclude:(UIView *)exclude {
    PortalLayoutInput in;
    memset(&in, 0, sizeof in);
    CGRect b = host.bounds;
    in.bounds = (PortalRect){b.origin.x, b.origin.y, b.size.width, b.size.height};
    UIEdgeInsets insets = host.window ? host.window.safeAreaInsets : host.safeAreaInsets;
    CGRect safe = UIEdgeInsetsInsetRect(b, insets);
    // The host may be offset inside the window: express the window's safe area in host coordinates.
    if (host.window) {
        CGRect windowSafe = UIEdgeInsetsInsetRect(host.window.bounds, host.window.safeAreaInsets);
        safe = CGRectIntersection([host convertRect:windowSafe fromView:host.window], b);
        if (CGRectIsNull(safe)) safe = b;
    }
    in.safe = (PortalRect){safe.origin.x, safe.origin.y, safe.size.width, safe.size.height};

    NSString *anchorSource = @"estimated";
    __block double anchor = -1;
    void (^considerAnchor)(UIView *, NSString *) = ^(UIView *v, NSString *label) {
        if (!v || !PortalViewIsShown(v)) return;
        CGRect r = [host convertRect:v.bounds fromView:v];
        if (CGRectGetMinY(r) > CGRectGetMidY(b)) return; // the clock area is in the upper half
        double bottom = CGRectGetMaxY(r);
        if (bottom > anchor && bottom < CGRectGetMaxY(b)) {
            anchor = bottom;
        }
    };
    NSMutableArray<NSString *> *anchorClasses = [NSMutableArray array];
    if ([coverSheet respondsToSelector:@selector(dateView)]) {
        UIView *v = ViewOf([coverSheet dateView]);
        double before = anchor;
        considerAnchor(v, @"dateView");
        if (anchor != before) [anchorClasses addObject:NSStringFromClass([v class])];
    }
    if ([coverSheet respondsToSelector:@selector(complicationContainerViewController)]) {
        UIView *v = ViewOf([coverSheet complicationContainerViewController]);
        // The container can span the page; only its visible content matters.
        UIView *content = nil;
        for (UIView *sub in v.subviews)
            if (PortalViewIsShown(sub)) content = content ? v : sub;
        double before = anchor;
        considerAnchor(content ?: v, @"widgets");
        if (anchor != before) [anchorClasses addObject:NSStringFromClass([(content ?: v) class])];
    }

    NSArray *anchorTokens = @[ @"DateView", @"ProminentDisplay", @"ProminentTime", @"ComplicationContainer" ];
    NSArray *obstacleTokens = @[
        @"NotificationListCell", @"NotificationShortLook", @"AdjunctItemView", @"MediaControls", @"PlatterView",
        @"QuickActionsButton", @"QuickActionsView", @"ActivityItem", @"CallToActionLabel", @"PageControl",
        @"TeachableMoments"
    ];
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:host];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@0];
    // Walk from the host's window if it has one, so siblings of the page (quick actions) count too.
    UIView *root = host.window ?: host;
    if (root != host) {
        [stack removeAllObjects];
        [depths removeAllObjects];
        [stack addObject:root];
        [depths addObject:@0];
    }
    NSUInteger visited = 0;
    while (stack.count && visited < kMaxViewsVisited) {
        UIView *v = stack.lastObject;
        NSUInteger depth = depths.lastObject.unsignedIntegerValue;
        [stack removeLastObject];
        [depths removeLastObject];
        visited++;
        if (v == exclude || v.hidden || v.alpha < 0.02) continue;
        NSString *name = NSStringFromClass([v class]);
        BOOL matched = NO;
        if (v != host && v != root && NameHas(name, obstacleTokens) && PortalViewIsShown(v)) {
            CGRect r = CGRectIntersection([host convertRect:v.bounds fromView:v], b);
            if (!CGRectIsNull(r) && r.size.width > 1 && r.size.height > 1 && in.obstacleCount < PORTAL_MAX_OBSTACLES) {
                in.obstacles[in.obstacleCount++] = (PortalRect){r.origin.x, r.origin.y, r.size.width, r.size.height};
                counts[name] = @(counts[name].integerValue + 1);
                matched = YES; // its subviews are inside it
            }
        } else if (v != host && v != root && NameHas(name, anchorTokens)) {
            double before = anchor;
            considerAnchor(v, name);
            if (anchor != before && ![anchorClasses containsObject:name]) [anchorClasses addObject:name];
            matched = YES;
        }
        if (matched || depth >= kMaxDepth) continue;
        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
            [depths addObject:@(depth + 1)];
        }
    }
    if (anchor > 0) {
        in.anchorKnown = 1;
        in.anchorBottom = anchor;
        anchorSource = [anchorClasses componentsJoinedByString:@" + "];
    }

    PortalHostMeasurement *m = [[PortalHostMeasurement alloc] init];
    m.input = in;
    m.anchorSource = anchorSource.length ? anchorSource : @"estimated";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *name in [counts.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@×%@", name, counts[name]]];
    m.obstacleSummary = parts.count ? [parts componentsJoinedByString:@", "] : @"none";
    return m;
}

@end
