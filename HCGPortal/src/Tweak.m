//
//  Tweak.m
//  HCG Portal — Hakmi Capital Group
//
//  Plain Objective-C (no Logos), so the dylib has NO load-time dependency on
//  CydiaSubstrate: loading HCGPortal.dylib into SpringBoard and running its
//  disabled path needs nothing from the injector. validate.sh fails the build
//  if either slice gains a Substrate load command again.
//
//  The injector's hook API (MSHookMessageEx, provided by ElleKit/Substrate) is
//  looked up with dlsym ONLY when Portal is enabled. If it is missing, Portal
//  stays inactive and Settings shows why; turning Enable off and on retries.
//
//  Three hooks on CSCoverSheetViewController tell Portal when the Lock Screen
//  appears, disappears and lays out. Each calls the ORIGINAL method first and
//  never changes arguments or return values; Portal never hooks a gesture,
//  touch, authentication, notification or wallpaper method. When Portal is
//  disabled they return right after the original method.
//
//  The constructor only queues the bootstrap on the main queue. The bootstrap
//  itself never touches SpringBoard's Lock Screen objects until Portal is
//  enabled and SpringBoard has finished launching (PortalController.m).
//

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#import "PortalController.h"

#ifndef PORTAL_PREVIEW_HOST
typedef void (*PortalHookMessageFunction)(Class, SEL, IMP, IMP *);
#endif

static Class gCoverSheetClass;
static IMP originalWillAppear;
static IMP originalDidDisappear;
static IMP originalDidLayout;

/// The original implementation, or — should the injector ever report none —
/// the superclass's, so the Lock Screen's own behaviour is never skipped.
static IMP PortalOriginal(IMP original, SEL selector) {
    if (original) return original;
    return class_getMethodImplementation(class_getSuperclass(gCoverSheetClass), selector);
}

static void PortalWillAppear(id controller, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))PortalOriginal(originalWillAppear, selector))(controller, selector, animated);
    PortalControllerCoverSheetWillAppear(controller);
}

static void PortalDidDisappear(id controller, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))PortalOriginal(originalDidDisappear, selector))(controller, selector, animated);
    PortalControllerCoverSheetDidDisappear(controller);
}

static void PortalDidLayout(id controller, SEL selector) {
    ((void (*)(id, SEL))PortalOriginal(originalDidLayout, selector))(controller, selector);
    PortalControllerCoverSheetDidLayout(controller);
}

#ifdef PORTAL_PREVIEW_HOST
static PortalHookMessageFunction gPreviewHookAPI;
void PortalPreviewSetHookAPI(PortalHookMessageFunction function) {
    gPreviewHookAPI = function;
}
#endif

static PortalHookMessageFunction PortalResolveHookAPI(void) {
#ifdef PORTAL_PREVIEW_HOST
    return gPreviewHookAPI;
#else
    return (PortalHookMessageFunction)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
#endif
}

static NSString *PortalInstallHooks(void) {
    Class coverSheet = objc_getClass("CSCoverSheetViewController");
    SEL willAppear = @selector(viewWillAppear:);
    SEL didDisappear = @selector(viewDidDisappear:);
    SEL didLayout = @selector(viewDidLayoutSubviews);
    if (!coverSheet || !class_getInstanceMethod(coverSheet, willAppear) ||
        !class_getInstanceMethod(coverSheet, didDisappear) || !class_getInstanceMethod(coverSheet, didLayout)) {
        return @"The Lock Screen lifecycle methods are unavailable on this build of iOS.";
    }

    // Resolve the injector's hook API at enable time. Loading this dylib and
    // running its disabled path must work without a Substrate load command.
    PortalHookMessageFunction hook = PortalResolveHookAPI();
    if (!hook) return @"The injector's Substrate hook API (MSHookMessageEx) is unavailable in SpringBoard.";

    gCoverSheetClass = coverSheet;
    hook(coverSheet, willAppear, (IMP)PortalWillAppear, &originalWillAppear);
    hook(coverSheet, didDisappear, (IMP)PortalDidDisappear, &originalDidDisappear);
    hook(coverSheet, didLayout, (IMP)PortalDidLayout, &originalDidLayout);
    PortalControllerNoteHooks(@"CSCoverSheetViewController viewWillAppear:, viewDidDisappear:, viewDidLayoutSubviews");
    return nil;
}

__attribute__((constructor)) static void PortalStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PortalControllerBootstrap(PortalInstallHooks);
    });
}
