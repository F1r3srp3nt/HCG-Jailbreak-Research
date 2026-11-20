#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#import "PortalController.h"

typedef void (*PortalHookMessage)(Class, SEL, IMP, IMP *);
static IMP originalWillAppear;
static IMP originalDidDisappear;
static IMP originalDidLayout;

static void PortalWillAppear(id controller, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))originalWillAppear)(controller, selector, animated);
    PortalControllerCoverSheetWillAppear(controller);
}

static void PortalDidDisappear(id controller, SEL selector, BOOL animated) {
    ((void (*)(id, SEL, BOOL))originalDidDisappear)(controller, selector, animated);
    PortalControllerCoverSheetDidDisappear(controller);
}

static void PortalDidLayout(id controller, SEL selector) {
    ((void (*)(id, SEL))originalDidLayout)(controller, selector);
    PortalControllerCoverSheetDidLayout(controller);
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
    PortalHookMessage hook = (PortalHookMessage)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) return @"The injector's Substrate hook API is unavailable in SpringBoard.";

    hook(coverSheet, willAppear, (IMP)PortalWillAppear, &originalWillAppear);
    hook(coverSheet, didDisappear, (IMP)PortalDidDisappear, &originalDidDisappear);
    hook(coverSheet, didLayout, (IMP)PortalDidLayout, &originalDidLayout);
    PortalControllerNoteHooks(@"CSCoverSheetViewController viewWillAppear:, viewDidDisappear:, viewDidLayoutSubviews");
    return nil;
}

__attribute__((constructor))
static void PortalStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PortalControllerBootstrap(PortalInstallHooks);
    });
}
