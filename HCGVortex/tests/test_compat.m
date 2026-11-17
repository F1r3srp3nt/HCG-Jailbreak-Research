//
//  test_compat.m — tests for the SpringBoard compatibility gate, the
//  hook-installation check and the launch guard (src/VortexCompatibility.m).
//
//  Builds fake class hierarchies with the Objective-C runtime that stand in
//  for SBFolderView / SBRootFolderView / SBIconScrollView / SBIconListView
//  (with NSObject subclasses standing in for UIView / UIScrollView), then
//  checks that every unsupported shape is REFUSED, so no hooks would be
//  installed and SpringBoard would stay stock.
//
//  Needs an Objective-C runtime with Foundation: runs on macOS (CI) via
//  `make -C tests compat`. Written without ARC so it also builds with GNUstep.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import "../src/VortexCompatibility.h"

static int g_checks = 0, g_failures = 0;

#define CHECK(cond, ...)                                                       \
    do {                                                                       \
        g_checks++;                                                            \
        if (!(cond)) {                                                         \
            g_failures++;                                                      \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);               \
            fprintf(stderr, __VA_ARGS__);                                      \
            fprintf(stderr, "\n");                                             \
        }                                                                      \
    } while (0)

static void noopIMP(id self, SEL _cmd) {}
static void noopIMP1(id self, SEL _cmd, id arg) {}
static id nilIMP(id self, SEL _cmd) { return nil; }
static void replacementIMP(id self, SEL _cmd) {}
static void replacementIMP1(id self, SEL _cmd, id arg) {}

static Class makeClass(const char *name, Class superclass) {
    Class cls = objc_allocateClassPair(superclass, name, 0);
    if (!cls) {
        fprintf(stderr, "could not create class %s\n", name);
        exit(2);
    }
    objc_registerClassPair(cls);
    return cls;
}

static void addScroll(Class cls) { class_addMethod(cls, @selector(scrollViewDidScroll:), (IMP)noopIMP1, "v@:@"); }
static void addLayout(Class cls) { class_addMethod(cls, @selector(layoutSubviews), (IMP)noopIMP, "v@:"); }
static void addScrollViewAccessor(Class cls) { class_addMethod(cls, @selector(scrollView), (IMP)nilIMP, "@@:"); }

/// Shapes a scenario can break.
typedef struct {
    int omitRootClass;          // SBRootFolderView missing
    int rootNotFolderSubclass;  // SBRootFolderView not a SBFolderView
    int scrollNotScrollView;    // SBIconScrollView not a UIScrollView
    int omitListClass;          // SBIconListView missing
    int omitScroll;             // no -scrollViewDidScroll: anywhere
    int inheritScroll;          // -scrollViewDidScroll: only on the superclass
    int omitLayout;             // no -layoutSubviews on SBFolderView itself
    int omitScrollViewAccessor; // no -scrollView
} Shape;

static Class gFakeView, gFakeScrollView;
static int gScenario = 0;

/// Builds a fresh, uniquely named hierarchy and fills `names`.
static void buildScenario(Shape shape, VortexSpringBoardClassNames *names, char storage[4][64]) {
    gScenario++;
    snprintf(storage[0], 64, "T%d_SBFolderView", gScenario);
    snprintf(storage[1], 64, "T%d_SBRootFolderView", gScenario);
    snprintf(storage[2], 64, "T%d_SBIconScrollView", gScenario);
    snprintf(storage[3], 64, "T%d_SBIconListView", gScenario);
    names->folderView = storage[0];
    names->rootFolderView = storage[1];
    names->iconScrollView = storage[2];
    names->iconListView = storage[3];

    Class viewBase = gFakeView;
    if (shape.inheritScroll) {
        char base[64];
        snprintf(base, sizeof base, "T%d_ViewWithScroll", gScenario);
        viewBase = makeClass(base, gFakeView);
        addScroll(viewBase);
    }
    Class folder = makeClass(storage[0], viewBase);
    if (!shape.omitScroll && !shape.inheritScroll) addScroll(folder);
    if (!shape.omitLayout) addLayout(folder);

    if (!shape.omitRootClass) {
        Class root = makeClass(storage[1], shape.rootNotFolderSubclass ? gFakeView : folder);
        if (!shape.omitScrollViewAccessor) addScrollViewAccessor(root);
    }
    makeClass(storage[2], shape.scrollNotScrollView ? gFakeView : gFakeScrollView);
    if (!shape.omitListClass) makeClass(storage[3], gFakeView);
}

static NSString *run(Shape shape, VortexResolvedClasses *resolved) {
    VortexSpringBoardClassNames names;
    char storage[4][64];
    buildScenario(shape, &names, storage);
    return VortexCheckCompatibility(&names, gFakeView, gFakeScrollView, resolved);
}

static BOOL contains(NSString *s, NSString *needle) {
    return s && [s rangeOfString:needle].location != NSNotFound;
}

static void testGate(void) {
    Shape ok = { 0 };
    VortexResolvedClasses r;
    NSString *f = run(ok, &r);
    CHECK(f == nil, "complete hierarchy should be compatible, got: %s", f.UTF8String);
    CHECK(r.folderView && r.rootFolderView && r.iconScrollView && r.iconListView, "resolved classes filled");

    struct {
        const char *label;
        Shape shape;
        NSString *expect;
    } refuse[] = {
        { "missing SBRootFolderView", { .omitRootClass = 1 }, @"not found" },
        { "SBRootFolderView not a SBFolderView", { .rootNotFolderSubclass = 1 }, @"is not a" },
        { "SBIconScrollView not a UIScrollView", { .scrollNotScrollView = 1 }, @"is not a" },
        { "missing SBIconListView", { .omitListClass = 1 }, @"not found" },
        { "no -scrollViewDidScroll:", { .omitScroll = 1 }, @"scrollViewDidScroll:] not found" },
        { "inherited-only -scrollViewDidScroll:", { .inheritScroll = 1 }, @"does not implement -scrollViewDidScroll: itself" },
        { "no -layoutSubviews on SBFolderView", { .omitLayout = 1 }, @"layoutSubviews" },
        { "no -scrollView accessor", { .omitScrollViewAccessor = 1 }, @"scrollView] not found" },
    };
    for (size_t i = 0; i < sizeof refuse / sizeof refuse[0]; i++) {
        VortexResolvedClasses rr;
        NSString *reason = run(refuse[i].shape, &rr);
        CHECK(reason != nil, "%s: must be refused", refuse[i].label);
        CHECK(contains(reason, refuse[i].expect), "%s: reason '%s' should mention '%s'", refuse[i].label,
              reason.UTF8String, refuse[i].expect.UTF8String);
        CHECK(!rr.folderView && !rr.rootFolderView, "%s: nothing resolved on refusal", refuse[i].label);
    }

    // Missing SBFolderView entirely (class name that was never created).
    VortexSpringBoardClassNames missing = { "T_Nonexistent_SBFolderView", "x", "y", "z" };
    NSString *reason = VortexCheckCompatibility(&missing, gFakeView, gFakeScrollView, &r);
    CHECK(contains(reason, @"not found"), "missing SBFolderView refused (%s)", reason.UTF8String);
}

static void testHookVerification(void) {
    Shape ok = { 0 };
    VortexResolvedClasses r;
    CHECK(run(ok, &r) == nil, "setup");
    VortexHookIMPs before = VortexCurrentHookIMPs(r.folderView);
    CHECK(before.scrollViewDidScroll && before.layoutSubviews, "IMPs read before install");

    CHECK(VortexVerifyHooksInstalled(before, VortexCurrentHookIMPs(r.folderView)) != nil,
          "no replacement must be reported as not installed");

    // Simulate the hook engine replacing only one method.
    method_setImplementation(class_getInstanceMethod(r.folderView, @selector(scrollViewDidScroll:)),
                             (IMP)replacementIMP1);
    NSString *partial = VortexVerifyHooksInstalled(before, VortexCurrentHookIMPs(r.folderView));
    CHECK(contains(partial, @"layoutSubviews") && !contains(partial, @"scrollViewDidScroll"),
          "partial install names the missing hook (%s)", partial.UTF8String);

    method_setImplementation(class_getInstanceMethod(r.folderView, @selector(layoutSubviews)), (IMP)replacementIMP);
    CHECK(VortexVerifyHooksInstalled(before, VortexCurrentHookIMPs(r.folderView)) == nil, "full install verified");

    VortexHookIMPs none = VortexCurrentHookIMPs(Nil);
    CHECK(!none.scrollViewDidScroll && !none.layoutSubviews, "Nil class yields no IMPs");
}

static void testLaunchGuard(void) {
    for (NSInteger n = -1; n < VORTEX_UNSTABLE_LAUNCH_LIMIT; n++)
        CHECK(!VortexLaunchGuardShouldDisable(n), "%ld unstable launches must not disable", (long)n);
    CHECK(VortexLaunchGuardShouldDisable(VORTEX_UNSTABLE_LAUNCH_LIMIT), "limit reached disables");
    CHECK(VortexLaunchGuardShouldDisable(VORTEX_UNSTABLE_LAUNCH_LIMIT + 5), "above limit disables");
}

static void testDefaultNames(void) {
    CHECK(strcmp(VortexDefaultSpringBoardClassNames.folderView, "SBFolderView") == 0, "default folder class");
    CHECK(strcmp(VortexDefaultSpringBoardClassNames.rootFolderView, "SBRootFolderView") == 0, "default root class");
    CHECK(strcmp(VortexDefaultSpringBoardClassNames.iconScrollView, "SBIconScrollView") == 0, "default scroll class");
    CHECK(strcmp(VortexDefaultSpringBoardClassNames.iconListView, "SBIconListView") == 0, "default list class");
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    gFakeView = makeClass("TFakeUIView", [NSObject class]);
    gFakeScrollView = makeClass("TFakeUIScrollView", gFakeView);
    testGate();
    testHookVerification();
    testLaunchGuard();
    testDefaultNames();
    printf("%d checks, %d failures\n", g_checks, g_failures);
    [pool drain];
    return g_failures ? 1 : 0;
}
