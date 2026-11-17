//
//  Tweak.x
//  HCG Halo — Hakmi Capital Group
//
//  The only Logos file and the only hook. HCG Halo draws its border in its
//  own non-interactive view inside the Home Screen window; it does not
//  hook any Home Screen, gesture, touch or accessibility code.
//
//  The one hook tells Halo when an app comes to the front, so the border can
//  stop drawing behind it. It calls %orig FIRST and never changes arguments
//  or return values. It is installed only when Halo is enabled, and only if
//  SpringBoard implements the method (checked in HaloController.m).
//

#import <UIKit/UIKit.h>
#import "HaloController.h"
#import "HaloSpringBoard.h"

%group HaloFrontDisplay

%hook SpringBoard

- (void)frontDisplayDidChange:(id)display {
    %orig;
    HaloControllerFrontDisplayDidChange(display);
}

%end

%end

static void HaloInstallFrontDisplayHook(void) {
    %init(HaloFrontDisplay);
}

%ctor {
    HaloControllerBootstrap(HaloInstallFrontDisplayHook);
}
