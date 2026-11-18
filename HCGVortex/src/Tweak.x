//
//  Tweak.x
//  HCG Vortex — Hakmi Capital Group
//
//  The only Logos file. Two required hooks, both on methods SBFolderView
//  implements itself (verified at runtime by VortexCoreCompatibilityFailure
//  before %init runs), plus one optional hook on SBIconListView (below). Each hook calls %orig FIRST, so SpringBoard's own scrolling,
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

// Optional (0.3.1): re-apply icon visuals right after SpringBoard lays out an
// icon page, so icon views it adds or reveals mid-frame are never drawn
// untransformed. Installed only if SBIconListView implements -layoutSubviews
// itself; calls %orig first and changes nothing when no transition is active.
%group VortexListHooks

%hook SBIconListView

- (void)layoutSubviews {
    %orig;
    VortexCoreHandleListLayout((UIView *)self);
}

%end

%end

static void VortexInstallHooks(void) {
    %init(VortexHooks);
    BOOL list = VortexCoreListLayoutHookAvailable();
    if (list) %init(VortexListHooks);
    VortexCoreNoteListLayoutHookInstalled(list);
}

%ctor {
    VortexCoreBootstrap(VortexInstallHooks);
}
