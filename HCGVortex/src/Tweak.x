//
//  Tweak.x
//  HCG Vortex — Hakmi Capital Group
//
//  The only Logos file. Two hooks, both on methods SBFolderView implements
//  itself (verified at runtime by VortexCoreCompatibilityFailure before
//  %init runs). Each hook calls %orig FIRST, so SpringBoard's own scrolling,
//  page-index bookkeeping and layout always complete before Vortex looks at
//  the result. Vortex never changes arguments or return values.
//
//  Note: the spec suggested Tweak.xm. This file is .x (Objective-C) rather
//  than .xm (Objective-C++) on purpose: no C++ runtime in SpringBoard, and
//  fewer arm64e ABI surfaces for non-Xcode toolchains (see docs/BUILD.md).
//

#import <UIKit/UIKit.h>
#import "VortexCore.h"

%group VortexHooks

%hook SBFolderView

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    %orig;
    VortexCoreHandleScroll((UIView *)self, scrollView);
}

- (void)layoutSubviews {
    %orig;
    VortexCoreHandleLayout((UIView *)self);
}

%end

%end

static void VortexInstallHooks(void) {
    %init(VortexHooks);
}

%ctor {
    VortexCoreBootstrap(VortexInstallHooks);
}
