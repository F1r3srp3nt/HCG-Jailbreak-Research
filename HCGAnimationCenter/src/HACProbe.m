//
//  HACProbe.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACProbe.h"
#import "HACHosts.h"
#import "HACPreferences.h"
#import "HACSpringBoard.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <sys/utsname.h>

static const NSUInteger kMaxNodes = 2500;
static const NSUInteger kKeepProbes = 5;

static NSString *Frame(CGRect r) {
    return [NSString stringWithFormat:@"(%.0f %.0f; %.0f × %.0f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *ClassChain(UIView *view) {
    NSMutableArray *names = [NSMutableArray array];
    for (Class c = [view class]; c && c != [UIView class] && names.count < 4; c = class_getSuperclass(c))
        [names addObject:NSStringFromClass(c)];
    return [names componentsJoinedByString:@" : "];
}

static void Dump(UIView *view, NSUInteger depth, NSUInteger maxDepth, NSUInteger *nodes, NSMutableString *out) {
    if (*nodes >= kMaxNodes) return;
    (*nodes)++;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    BOOL ours = [view.accessibilityIdentifier hasPrefix:@"HCGAnimationCenter"];
    [out appendFormat:@"%@%@ %@%@%@%@%@\n", indent, ClassChain(view), Frame(view.frame), view.hidden ? @" hidden" : @"",
                      view.alpha < 0.999 ? [NSString stringWithFormat:@" alpha=%.2f", view.alpha] : @"",
                      CATransform3DIsIdentity(view.layer.transform) ? @"" : @" transformed",
                      ours ? @"   <== HCG Animation Center" : @""];
    if (depth >= maxDepth) {
        if (view.subviews.count) [out appendFormat:@"%@  … %lu subviews\n", indent, (unsigned long)view.subviews.count];
        return;
    }
    for (UIView *sub in view.subviews) Dump(sub, depth + 1, maxDepth, nodes, out);
}

NSString *HACHierarchyProbeText(NSDictionary<NSString *, id> *status) {
    NSMutableString *out = [NSMutableString string];
    struct utsname u;
    uname(&u);
    [out appendFormat:@"HCG Animation Center hierarchy probe (read-only)\n"];
    [out appendFormat:@"version %s, build %s\n", HAC_VERSION, HAC_BUILD_ID];
    [out appendFormat:@"device %s, %@\n", u.machine, [NSProcessInfo processInfo].operatingSystemVersionString];
    [out appendFormat:@"screen %@ @%.0fx, native %@\n", Frame(UIScreen.mainScreen.bounds), UIScreen.mainScreen.scale,
                      Frame(UIScreen.mainScreen.nativeBounds)];
    [out appendFormat:@"time %@\n\n", [NSDate date]];

    [out appendString:@"== Interfaces\n"];
    NSDictionary *report = HACEnvironmentReport();
    for (NSString *key in [report.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [out appendFormat:@"%@: %@\n", key, report[key]];

    [out appendString:@"\n== Placement ladder results\n"];
    for (int s = 0; s < HAC_SURFACE_COUNT; s++) {
        for (NSString *placement in HACPlacementLadder((HACSurface)s, @"automatic")) {
            NSString *why = nil;
            HACHost *host = HACFindHost((HACSurface)s, placement, &why);
            [out appendFormat:@"%s / %@: %@\n", hac_surface_id((HACSurface)s), placement,
                              host ? [NSString stringWithFormat:@"%@ in %@", host.summary,
                                                                Frame(host.container.frame)]
                                   : why];
        }
    }

    [out appendString:@"\n== Engine status\n"];
    for (NSString *key in [status.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [out appendFormat:@"%@: %@\n", key, status[key]];

    [out appendString:@"\n== Windows (front to back)\n"];
    NSArray *windows = [HACAllWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel > b.windowLevel ? NSOrderedAscending : (a.windowLevel < b.windowLevel ? NSOrderedDescending : NSOrderedSame);
    }];
    for (UIWindow *w in windows)
        [out appendFormat:@"level %8.1f  %@ %@%@ subviews=%lu\n", w.windowLevel, ClassChain(w), Frame(w.frame),
                          w.hidden ? @" hidden" : @"", (unsigned long)w.subviews.count];

    NSUInteger nodes = 0;
    Class home = objc_getClass(HAC_SB_HOME_WINDOW_CLASS), cover = objc_getClass(HAC_SB_COVER_SHEET_WINDOW_CLASS),
          wallpaperWindow = objc_getClass(HAC_SB_WALLPAPER_WINDOW_CLASS);
    for (UIWindow *w in windows) {
        NSUInteger depth = 0;
        if (home && [w isKindOfClass:home]) depth = 3;
        else if (cover && [w isKindOfClass:cover]) depth = 7;
        else if (wallpaperWindow && [w isKindOfClass:wallpaperWindow]) depth = 9;
        else if ([NSStringFromClass([w class]) containsString:@"Wallpaper"] ||
                 [NSStringFromClass([w class]) containsString:@"Poster"]) depth = 9;
        if (!depth) continue;
        [out appendFormat:@"\n== %@ (depth %lu)\n", NSStringFromClass([w class]), (unsigned long)depth];
        Dump(w, 0, depth, &nodes, out);
    }
    if (nodes >= kMaxNodes) [out appendFormat:@"\n(stopped after %lu views)\n", (unsigned long)kMaxNodes];
    return out;
}

NSString *HACWriteHierarchyProbe(NSDictionary<NSString *, id> *status, NSError **error) {
    NSURL *folder = [HACPreferences diagnosticsFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    format.dateFormat = @"yyyyMMdd'T'HHmmss'Z'";
    NSURL *file = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"hierarchy-%@.txt",
                                                                                 [format stringFromDate:[NSDate date]]]];
    NSString *text = HACHierarchyProbeText(status);
    if (![text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
    // Keep only the newest few.
    NSArray *existing = [[fm contentsOfDirectoryAtPath:folder.path error:NULL]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'hierarchy-'"]];
    NSArray *sorted = [existing sortedArrayUsingSelector:@selector(compare:)];
    for (NSUInteger i = 0; i + kKeepProbes < sorted.count; i++)
        [fm removeItemAtURL:[folder URLByAppendingPathComponent:sorted[i]] error:NULL];
    return file.path;
}
