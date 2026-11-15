//
//  VortexNavigation.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexNavigation.h"
#import "VortexSpringBoard.h"

#import <objc/runtime.h>

@implementation VortexNavigation {
    VortexNavState _state;
}

- (instancetype)init {
    if ((self = [super init])) {
        vortex_nav_reset(&_state);
    }
    return self;
}

- (void)reset {
    vortex_nav_reset(&_state);
}

- (VortexNavSnapshot)stepWithPresentedPosition:(double)presented geometry:(const VortexPageGeometry *)geometry {
    return vortex_nav_step(&_state, presented, geometry->positions, (int)geometry->count);
}

+ (NSArray<UIView *> *)iconListViewsForFolderView:(UIView *)folderView scrollView:(UIScrollView *)scrollView {
    id<VortexFolderViewLike> folder = (id<VortexFolderViewLike>)folderView;
    NSArray *lists = nil;
    if ([folder respondsToSelector:@selector(iconListViews)]) {
        id value = [folder iconListViews];
        if ([value isKindOfClass:[NSArray class]]) lists = value;
    }
    if (lists.count) return lists;

    // Fallback: direct subviews of the scroll view that are icon list views.
    Class listClass = objc_getClass(VORTEX_SB_ICON_LIST_VIEW_CLASS);
    if (!listClass) return @[];
    NSMutableArray *found = [NSMutableArray array];
    for (UIView *view in scrollView.subviews) {
        if ([view isKindOfClass:listClass]) [found addObject:view];
    }
    return found;
}

+ (BOOL)collectGeometryForFolderView:(UIView *)folderView
                          scrollView:(UIScrollView *)scrollView
                            geometry:(VortexPageGeometry *)geometry {
    memset(geometry, 0, sizeof(*geometry));
    CGRect bounds = scrollView.bounds;
    if (CGRectGetWidth(bounds) < 1.0 || CGRectGetHeight(bounds) < 1.0) return NO;

    Class listClass = objc_getClass(VORTEX_SB_ICON_LIST_VIEW_CLASS);
    NSArray<UIView *> *lists = [self iconListViewsForFolderView:folderView scrollView:scrollView];

    // Gather (centre.x, view) pairs in scroll-view coordinates.
    double centres[VORTEX_MAX_PAGES];
    void *views[VORTEX_MAX_PAGES];
    NSInteger n = 0;
    for (UIView *view in lists) {
        if (n >= VORTEX_MAX_PAGES) break;
        if (![view isKindOfClass:[UIView class]]) continue;
        if (listClass && ![view isKindOfClass:listClass]) continue;
        if (view.hidden || !view.superview) continue;
        if (![view isDescendantOfView:scrollView]) continue; // excludes the dock list view
        CGPoint centre = view.superview == scrollView ? view.center
                                                      : [view.superview convertPoint:view.center toView:scrollView];
        if (!isfinite(centre.x)) continue;
        centres[n] = centre.x;
        views[n] = (__bridge void *)view;
        n++;
    }
    if (n == 0) return NO;

    // Insertion sort by x (n is tiny).
    for (NSInteger i = 1; i < n; i++) {
        double c = centres[i];
        void *v = views[i];
        NSInteger j = i - 1;
        while (j >= 0 && centres[j] > c) {
            centres[j + 1] = centres[j];
            views[j + 1] = views[j];
            j--;
        }
        centres[j + 1] = c;
        views[j + 1] = v;
    }

    // Page pitch: smallest gap between neighbouring pages, sanity-checked
    // against the scroll view width (paging is by bounds width).
    double width = CGRectGetWidth(bounds);
    double pitch = width;
    double smallest = INFINITY;
    for (NSInteger i = 1; i < n; i++) {
        double gap = centres[i] - centres[i - 1];
        if (gap > 1.0 && gap < smallest) smallest = gap;
    }
    if (isfinite(smallest) && smallest > width * 0.5 && smallest < width * 2.0) pitch = smallest;

    geometry->count = n;
    for (NSInteger i = 0; i < n; i++) {
        geometry->positions[i] = centres[i] / pitch;
        geometry->views[i] = views[i];
    }
    geometry->pitch = pitch;
    geometry->actual = CGRectGetMidX(bounds) / pitch;
    double windowHeight = scrollView.window ? CGRectGetHeight(scrollView.window.bounds) : 0.0;
    // A vertical "page" must clear the whole screen, not just the scroller.
    geometry->pageHeight = MAX(CGRectGetHeight(bounds), windowHeight);
    return YES;
}

+ (long long)actualPageIndexForFolderView:(UIView *)folderView {
    id<VortexFolderViewLike> folder = (id<VortexFolderViewLike>)folderView;
    if ([folder respondsToSelector:@selector(currentPageIndex)]) return [folder currentPageIndex];
    return -1;
}

@end
