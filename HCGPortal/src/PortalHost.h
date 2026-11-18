//
//  PortalHost.h
//  HCG Portal — Hakmi Capital Group
//
//  Where the portal lives on the Lock Screen, and what it must not cover.
//  Nothing is hooked here: views are found and measured read-only.
//
//  Host (first that exists, checked every time):
//    1. CSCoverSheetViewController.mainPageContentViewController.view
//       (the Lock Screen's main page: scrolls away with the camera / Today
//       pages and slides up with the unlock gesture)
//    2. CSCoverSheetViewController.view
//
//  Anchor (the portal goes below it): the lowest visible edge of
//    -dateView (SBFLockScreenDateView), -dateViewController.view,
//    -complicationContainerViewController.view (Lock Screen widgets), and any
//    visible view whose class name contains "DateView", "ProminentDisplay",
//    "ProminentTime" or "ComplicationContainer" in the upper half.
//
//  Obstacles (the portal never covers them; it moves, shrinks, collapses to a
//  compact orb or hides): visible views whose class name contains
//    "NotificationListCell", "NotificationShortLook", "AdjunctItemView",
//    "MediaControls", "PlatterView", "QuickActionsButton", "QuickActionsView",
//    "ActivityItem", "CallToActionLabel", "PageControl", "TeachableMoments".
//
//  The class names are iOS 15–17 header evidence; which ones the phone really
//  has is recorded in the status report (device row L2).
//

#import <UIKit/UIKit.h>

#import "PortalCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface PortalHostMeasurement : NSObject
@property (nonatomic) PortalLayoutInput input;
@property (nonatomic, copy) NSString *anchorSource;       // class that set the anchor, or "estimated"
@property (nonatomic, copy) NSString *obstacleSummary;    // "NCNotificationListCell×2, CSQuickActionsButton×2"
@end

@interface PortalHost : NSObject

/// The view the overlay is added to, or nil (with a reason).
+ (nullable UIView *)hostViewForCoverSheet:(nullable UIViewController *)coverSheet reason:(NSString *_Nullable *_Nullable)reason;
/// Measures the clock / widgets and the obstacles in `host` coordinates,
/// skipping `exclude` (the portal's own overlay).
+ (PortalHostMeasurement *)measureHost:(UIView *)host
                            coverSheet:(nullable UIViewController *)coverSheet
                               exclude:(nullable UIView *)exclude;

@end

NS_ASSUME_NONNULL_END
