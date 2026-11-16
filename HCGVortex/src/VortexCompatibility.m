//
//  VortexCompatibility.m
//  HCG Vortex — Hakmi Capital Group
//
//  Written to compile with or without ARC (only autoreleased factory objects
//  are returned), so the host tests can build it either way.
//

#import "VortexCompatibility.h"

#include <stdlib.h>

const VortexSpringBoardClassNames VortexDefaultSpringBoardClassNames = {
    "SBFolderView",
    "SBRootFolderView",
    "SBIconScrollView",
    "SBIconListView",
};

static NSString *VortexRequireClass(const char *name, Class superclass, Class *out) {
    Class cls = objc_getClass(name);
    if (!cls) return [NSString stringWithFormat:@"class %s not found", name];
    if (superclass && ![cls isSubclassOfClass:superclass])
        return [NSString stringWithFormat:@"class %s is not a %s", name, class_getName(superclass)];
    *out = cls;
    return nil;
}

static BOOL VortexClassOwnsMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    BOOL owns = NO;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count && !owns; i++) {
        if (sel_isEqual(method_getName(methods[i]), sel)) owns = YES;
    }
    free(methods);
    return owns;
}

NSString *VortexCheckCompatibility(const VortexSpringBoardClassNames *names,
                                   Class viewBase,
                                   Class scrollViewBase,
                                   VortexResolvedClasses *resolved) {
    VortexResolvedClasses found = { Nil, Nil, Nil, Nil };
    if (resolved) *resolved = found;

    NSString *failure = nil;
    if ((failure = VortexRequireClass(names->folderView, viewBase, &found.folderView))) return failure;
    if ((failure = VortexRequireClass(names->rootFolderView, found.folderView, &found.rootFolderView))) return failure;
    if ((failure = VortexRequireClass(names->iconScrollView, scrollViewBase, &found.iconScrollView))) return failure;
    if ((failure = VortexRequireClass(names->iconListView, viewBase, &found.iconListView))) return failure;

    // Hooked selectors must be implemented by the folder-view class ITSELF, not
    // merely inherited, so the hook engine replaces a real IMP and %orig always
    // has something to call.
    SEL hooked[2] = { @selector(scrollViewDidScroll:), @selector(layoutSubviews) };
    for (int i = 0; i < 2; i++) {
        if (!class_getInstanceMethod(found.folderView, hooked[i]))
            return [NSString stringWithFormat:@"-[%s %s] not found", names->folderView, sel_getName(hooked[i])];
        if (!VortexClassOwnsMethod(found.folderView, hooked[i]))
            return [NSString stringWithFormat:@"%s does not implement -%s itself", names->folderView, sel_getName(hooked[i])];
    }

    // Read-only accessor the engine depends on.
    if (!class_getInstanceMethod(found.rootFolderView, @selector(scrollView)))
        return [NSString stringWithFormat:@"-[%s scrollView] not found", names->rootFolderView];

    if (resolved) *resolved = found;
    return nil;
}

VortexHookIMPs VortexCurrentHookIMPs(Class folderView) {
    VortexHookIMPs imps = { NULL, NULL };
    if (!folderView) return imps;
    Method scroll = class_getInstanceMethod(folderView, @selector(scrollViewDidScroll:));
    Method layout = class_getInstanceMethod(folderView, @selector(layoutSubviews));
    imps.scrollViewDidScroll = scroll ? method_getImplementation(scroll) : NULL;
    imps.layoutSubviews = layout ? method_getImplementation(layout) : NULL;
    return imps;
}

NSString *VortexVerifyHooksInstalled(VortexHookIMPs before, VortexHookIMPs after) {
    NSMutableArray *missing = [NSMutableArray array];
    if (!after.scrollViewDidScroll || after.scrollViewDidScroll == before.scrollViewDidScroll)
        [missing addObject:@"-scrollViewDidScroll:"];
    if (!after.layoutSubviews || after.layoutSubviews == before.layoutSubviews)
        [missing addObject:@"-layoutSubviews"];
    if (missing.count == 0) return nil;
    return [NSString stringWithFormat:@"hook engine did not replace %@", [missing componentsJoinedByString:@" and "]];
}

BOOL VortexLaunchGuardShouldDisable(NSInteger consecutiveUnstableLaunches) {
    return consecutiveUnstableLaunches >= VORTEX_UNSTABLE_LAUNCH_LIMIT;
}
