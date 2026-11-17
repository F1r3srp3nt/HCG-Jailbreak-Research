//
//  VortexSpringBoard.h
//  HCG Vortex — Hakmi Capital Group
//
//  Minimal declarations of the SpringBoardHome selectors HCG Vortex uses.
//
//  Source: runtime header dump of iOS 17.0.3 SpringBoardHome.framework
//  (see docs/SPRINGBOARD_RESEARCH.md). These are declared on a PROTOCOL, not
//  as @interface SBFolderView, so nothing links against private class
//  symbols. Every call site is guarded with -respondsToSelector:, and the
//  hooked selectors are verified with class_getInstanceMethod at startup
//  (VortexCore) before any hook is installed. iOS 17.4 itself has NOT been
//  verified on a device yet.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Selectors observed on SBFolderView (and inherited by SBRootFolderView).
@protocol VortexFolderViewLike <NSObject>
@optional
- (UIScrollView *)scrollView;                 // property, iOS 17.0.3 header
- (NSArray<UIView *> *)iconListViews;         // property (copy), iOS 17.0.3 header
- (BOOL)isEditing;                            // property getter, iOS 17.0.3 header
- (long long)currentPageIndex;                // property, read-only; diagnostics only
@end

// Class names resolved at runtime via objc_getClass().
#define VORTEX_SB_FOLDER_VIEW_CLASS "SBFolderView"
#define VORTEX_SB_ROOT_FOLDER_VIEW_CLASS "SBRootFolderView"
#define VORTEX_SB_ICON_LIST_VIEW_CLASS "SBIconListView"
#define VORTEX_SB_ICON_SCROLL_VIEW_CLASS "SBIconScrollView"

NS_ASSUME_NONNULL_END
