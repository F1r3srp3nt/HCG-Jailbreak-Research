//
//  Tweak.x
//  HCG Animation Center — Hakmi Capital Group
//
//  The only Logos file and the only hook. Backgrounds are drawn in HCG
//  Animation Center's own non-interactive views, added to existing
//  SpringBoard views (src/HACHosts.m); no wallpaper, gesture, touch, icon or
//  accessibility code is hooked, and the system wallpaper is never changed.
//
//  The one hook tells the Home Screen surface when an app comes to the front,
//  so playback pauses behind it. It calls %orig FIRST and never changes
//  arguments or return values. It is installed only when the tweak is enabled,
//  and only if SpringBoard implements the method (checked in HACController.m).
//  The same hook and pattern as HCG Halo: hook chains are designed for this.
//

#import <UIKit/UIKit.h>
#import "HACController.h"
#import "HACSpringBoard.h"

%group HACFrontDisplay

%hook SpringBoard

- (void)frontDisplayDidChange:(id)display {
    %orig;
    HACControllerFrontDisplayDidChange(display);
}

%end

%end

static void HACInstallFrontDisplayHook(void) {
    %init(HACFrontDisplay);
}

%ctor {
    HACControllerBootstrap(HACInstallFrontDisplayHook);
}
