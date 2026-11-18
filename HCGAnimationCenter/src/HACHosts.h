//
//  HACHosts.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Where each surface's background view goes. Nothing here hooks or changes
//  SpringBoard: it only FINDS an existing view to add a non-interactive
//  subview to, and says why when it can't.
//
//  Placements (Settings › Advanced › Placement; "automatic" tries in order):
//    Home Screen  automatic = homeWindow, then wallpaper
//      homeWindow  SBHomeScreenWindow, index 0: above the system wallpaper,
//                  below the icons, dock, widgets and every other window
//      wallpaper   SBWallpaperController's Home wallpaper view, on top of it
//    Lock Screen  automatic = wallpaper, then coverSheet
//      wallpaper   SBWallpaperController's Lock wallpaper view, on top of it
//      coverSheet  SBCoverSheetWindow, index 0: below the clock and
//                  notifications
//

#import <UIKit/UIKit.h>

#import "HACPolicy.h"

NS_ASSUME_NONNULL_BEGIN

@interface HACHost : NSObject
@property (nonatomic, weak, nullable) UIView *container;
@property (nonatomic) BOOL atBottom;              ///< insert at index 0 (else on top)
@property (nonatomic, copy) NSString *placement;  ///< "homeWindow" | "wallpaper" | "coverSheet"
@property (nonatomic, copy) NSString *summary;    ///< how it was found, for Settings
@end

/// The placements "automatic" tries for a surface, in order.
NSArray<NSString *> *HACPlacementLadder(HACSurface surface, NSString *requested);

/// Finds a host, trying the ladder in order. On failure returns nil and sets
/// *whyNot to every reason, one per placement tried.
HACHost *_Nullable HACFindHost(HACSurface surface, NSString *requested, NSString *_Nullable *_Nullable whyNot);

/// Every window of the app (scene windows first).
NSArray<UIWindow *> *HACAllWindows(void);

/// Which of the interfaces above exist in this process (read-only checks).
NSDictionary<NSString *, NSString *> *HACEnvironmentReport(void);
/// One line for Settings.
NSString *HACEnvironmentSummary(NSDictionary<NSString *, NSString *> *report);

NS_ASSUME_NONNULL_END
