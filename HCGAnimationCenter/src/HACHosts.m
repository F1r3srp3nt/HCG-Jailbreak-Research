//
//  HACHosts.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACHosts.h"
#import "HACSpringBoard.h"

#import <objc/runtime.h>

@implementation HACHost
@end

NSArray<NSString *> *HACPlacementLadder(HACSurface surface, NSString *requested) {
    if (surface == HACSurfaceHome) {
        if ([requested isEqualToString:@"homeWindow"] || [requested isEqualToString:@"wallpaper"]) return @[ requested ];
        return @[ @"homeWindow", @"wallpaper" ];
    }
    if ([requested isEqualToString:@"wallpaper"] || [requested isEqualToString:@"coverSheet"]) return @[ requested ];
    return @[ @"wallpaper", @"coverSheet" ];
}

NSArray<UIWindow *> *HACAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in app.windows) {
        if (![windows containsObject:window]) [windows addObject:window];
    }
#pragma clang diagnostic pop
    return windows;
}

static UIWindow *FirstWindowOfClass(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) return nil;
    for (UIWindow *window in HACAllWindows())
        if ([window isKindOfClass:cls]) return window;
    return nil;
}

static UIWindow *HomeScreenWindow(NSString **how) {
    UIWindow *window = FirstWindowOfClass(HAC_SB_HOME_WINDOW_CLASS);
    if (window) {
        *how = @"SBHomeScreenWindow";
        return window;
    }
    Class iconControllerClass = objc_getClass(HAC_SB_ICON_CONTROLLER_CLASS);
    if ([iconControllerClass respondsToSelector:@selector(sharedInstance)]) {
        id controller = [(id)iconControllerClass sharedInstance];
        if ([controller isKindOfClass:[UIViewController class]]) {
            window = ((UIViewController *)controller).viewIfLoaded.window;
            if (window) {
                *how = [NSString stringWithFormat:@"SBIconController's window (%@)", NSStringFromClass([window class])];
                return window;
            }
        }
    }
    return nil;
}

static id WallpaperController(void) {
    Class cls = objc_getClass(HAC_SB_WALLPAPER_CONTROLLER_CLASS);
    if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return nil;
    return [(id)cls sharedInstance];
}

/// The wallpaper view for a variant: -_wallpaperViewForVariant:, then the
/// legacy PBUIWallpaperViewController properties (read through KVC, guarded).
static UIView *WallpaperView(long long variant, NSString **how, NSString **whyNot) {
    id controller = WallpaperController();
    if (!controller) {
        *whyNot = @"wallpaper: +[SBWallpaperController sharedInstance] is not available";
        return nil;
    }
    UIView *view = nil;
    if ([controller respondsToSelector:@selector(_wallpaperViewForVariant:)]) {
        id candidate = [(SBWallpaperController *)controller _wallpaperViewForVariant:variant];
        if ([candidate isKindOfClass:[UIView class]]) {
            view = candidate;
            *how = [NSString stringWithFormat:@"-_wallpaperViewForVariant:%lld (%@)", variant, NSStringFromClass([view class])];
        }
    }
    if (!view) {
        @try {
            id viewController = [controller valueForKey:@"wallpaperViewController"];
            NSString *key = variant == HAC_WALLPAPER_VARIANT_LOCK ? @"lockscreenWallpaperView" : @"homescreenWallpaperView";
            for (NSString *k in @[ key, @"sharedWallpaperView" ]) {
                if (![viewController respondsToSelector:NSSelectorFromString(k)]) continue;
                id candidate = [viewController valueForKey:k];
                if ([candidate isKindOfClass:[UIView class]]) {
                    view = candidate;
                    *how = [NSString stringWithFormat:@"%@.%@ (%@)", NSStringFromClass([viewController class]), k,
                                                      NSStringFromClass([view class])];
                    break;
                }
            }
        } @catch (NSException *exception) {
            view = nil;
        }
    }
    if (!view) {
        *whyNot = [NSString stringWithFormat:@"wallpaper: no %@ wallpaper view (PosterBoard wallpapers may not expose one)",
                                             variant == HAC_WALLPAPER_VARIANT_LOCK ? @"Lock Screen" : @"Home Screen"];
        return nil;
    }
    if (!view.window) {
        *whyNot = [NSString stringWithFormat:@"wallpaper: %@ is not in a window", *how];
        return nil;
    }
    return view;
}

HACHost *HACFindHost(HACSurface surface, NSString *requested, NSString **whyNot) {
    NSMutableArray<NSString *> *reasons = [NSMutableArray array];
    for (NSString *placement in HACPlacementLadder(surface, requested)) {
        NSString *how = nil, *why = nil;
        UIView *container = nil;
        BOOL atBottom = YES;
        if ([placement isEqualToString:@"homeWindow"]) {
            container = HomeScreenWindow(&how);
            if (!container) why = @"homeWindow: neither SBHomeScreenWindow nor SBIconController's window was found";
        } else if ([placement isEqualToString:@"wallpaper"]) {
            container = WallpaperView(surface == HACSurfaceLock ? HAC_WALLPAPER_VARIANT_LOCK : HAC_WALLPAPER_VARIANT_HOME,
                                      &how, &why);
            atBottom = NO;
        } else if ([placement isEqualToString:@"coverSheet"]) {
            container = FirstWindowOfClass(HAC_SB_COVER_SHEET_WINDOW_CLASS);
            how = @"SBCoverSheetWindow";
            if (!container) why = @"coverSheet: no SBCoverSheetWindow";
        }
        if (container) {
            HACHost *host = [[HACHost alloc] init];
            host.container = container;
            host.atBottom = atBottom;
            host.placement = placement;
            host.summary = [NSString stringWithFormat:@"%@ — %@", placement, how ?: NSStringFromClass([container class])];
            return host;
        }
        if (why) [reasons addObject:why];
    }
    if (whyNot) *whyNot = [reasons componentsJoinedByString:@"; "];
    return nil;
}

NSDictionary<NSString *, NSString *> *HACEnvironmentReport(void) {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    NSString *(^yesno)(BOOL) = ^NSString *(BOOL b) {
        return b ? @"yes" : @"no";
    };
    r[@"SBHomeScreenWindow"] = yesno(objc_getClass(HAC_SB_HOME_WINDOW_CLASS) != Nil);
    r[@"SBCoverSheetWindow"] = yesno(objc_getClass(HAC_SB_COVER_SHEET_WINDOW_CLASS) != Nil);
    r[@"_SBWallpaperWindow"] = yesno(objc_getClass(HAC_SB_WALLPAPER_WINDOW_CLASS) != Nil);
    Class wallpaper = objc_getClass(HAC_SB_WALLPAPER_CONTROLLER_CLASS);
    r[@"SBWallpaperController.sharedInstance"] = yesno(wallpaper && [wallpaper respondsToSelector:@selector(sharedInstance)]);
    r[@"SBWallpaperController._wallpaperViewForVariant:"] =
        yesno(wallpaper && class_getInstanceMethod(wallpaper, @selector(_wallpaperViewForVariant:)) != NULL);
    r[@"PBUIPosterWallpaperViewController"] = yesno(objc_getClass(HAC_PB_POSTER_CONTROLLER_CLASS) != Nil);
    r[@"PBUIWallpaperViewController"] = yesno(objc_getClass(HAC_PB_WALLPAPER_CONTROLLER_CLASS) != Nil);
    Class springBoard = objc_getClass(HAC_SB_SPRINGBOARD_CLASS);
    r[@"SpringBoard.frontDisplayDidChange:"] =
        yesno(springBoard && class_getInstanceMethod(springBoard, @selector(frontDisplayDidChange:)) != NULL);
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    r[@"iOS"] = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
    return r;
}

NSString *HACEnvironmentSummary(NSDictionary<NSString *, NSString *> *r) {
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"iOS %@", r[@"iOS"] ?: @"?"]];
    [parts addObject:[r[@"PBUIPosterWallpaperViewController"] isEqualToString:@"yes"] ? @"PosterBoard wallpapers"
                                                                                       : @"classic wallpapers"];
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *key in @[ @"SBHomeScreenWindow", @"SBWallpaperController._wallpaperViewForVariant:", @"SBCoverSheetWindow",
                             @"SpringBoard.frontDisplayDidChange:" ]) {
        if (![r[key] isEqualToString:@"yes"]) [missing addObject:key];
    }
    [parts addObject:missing.count ? [NSString stringWithFormat:@"missing: %@", [missing componentsJoinedByString:@", "]]
                                   : @"all expected interfaces present"];
    return [parts componentsJoinedByString:@" · "];
}
