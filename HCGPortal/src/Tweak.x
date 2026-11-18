//
//  Tweak.x
//  HCG Portal — Hakmi Capital Group
//
//  The only Logos file. Three hooks on CSCoverSheetViewController tell Portal
//  when the Lock Screen appears, disappears and lays out. Each calls %orig
//  FIRST and never changes arguments or return values; Portal never hooks a
//  gesture, touch, authentication, notification or wallpaper method.
//
//  They are installed only when Portal is first enabled, and only if the class
//  exists (checked in PortalControllerBootstrap and below). When Portal is
//  disabled they return right after %orig: the Lock Screen behaves exactly as
//  without HCG Portal.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "PortalController.h"

%group PortalCoverSheet

%hook CSCoverSheetViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    PortalControllerCoverSheetWillAppear(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    PortalControllerCoverSheetDidDisappear(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    PortalControllerCoverSheetDidLayout(self);
}

%end

%end

static void PortalInstallHooks(void) {
    Class cls = objc_getClass("CSCoverSheetViewController");
    if (!cls) {
        PortalControllerNoteHooks(@"none: CSCoverSheetViewController missing");
        return;
    }
    %init(PortalCoverSheet);
    PortalControllerNoteHooks(@"CSCoverSheetViewController viewWillAppear:, viewDidDisappear:, viewDidLayoutSubviews");
}

%ctor {
    PortalControllerBootstrap(PortalInstallHooks);
}
