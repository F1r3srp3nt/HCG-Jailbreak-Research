//
//  PortalOverlayView.h
//  HCG Portal — Hakmi Capital Group
//
//  The interactive layer: the portal orb, its radial menu and a short message
//  line. It covers its host, but only VISIBLE interactive controls take
//  touches:
//
//    collapsed: the orb's circle (>= 44 pt) — everything else passes through
//    expanded:  the orb and each 64 pt item disc — everything else passes
//               through AND collapses the menu ("tap outside")
//
//  Decorative layers (rings, glow, particles, labels, the message) never take
//  touches. Swipes that start outside the controls (unlock, Notification
//  Centre, camera page) are never intercepted.
//

#import <UIKit/UIKit.h>

#import "PortalCore.h"

NS_ASSUME_NONNULL_BEGIN

@class PortalOverlayView, PortalView;

@interface PortalMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbolName;          // SF Symbol, used when there is no image
@property (nonatomic, strong, nullable) UIImage *image;    // app icon
@property (nonatomic) int destination;                     // PortalDestination
@property (nonatomic) int item;                            // app index, or -1
@property (nonatomic) PortalAvailability availability;
@property (nonatomic, copy) NSString *statusText;          // "Not connected", "Update needed", "" …
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol destination:(int)destination item:(int)item;
@end

@protocol PortalOverlayDelegate <NSObject>
- (void)portalOverlay:(PortalOverlayView *)overlay didSelectItem:(PortalMenuItem *)item;
- (void)portalOverlayDidExpand:(PortalOverlayView *)overlay;
- (void)portalOverlayDidCollapse:(PortalOverlayView *)overlay;
@optional
/// Just before the menu opens: the last chance to refresh the destinations' availability.
- (void)portalOverlayWillExpand:(PortalOverlayView *)overlay;
@end

@interface PortalOverlayView : UIView

@property (nonatomic, weak, nullable) id<PortalOverlayDelegate> delegate;
@property (nonatomic, readonly) PortalView *portalView;
@property (nonatomic, readonly) PortalLayout layout;
@property (nonatomic, readonly, getter=isExpanded) BOOL expanded;
@property (nonatomic, readonly, copy) NSString *ringName;  // "main" or "apps"
@property (nonatomic) BOOL animationsAllowed;              // NO with Reduce Motion
@property (nonatomic) int palette;                         // item accents

- (void)applyLayout:(PortalLayout)layout safe:(PortalRect)safe animated:(BOOL)animated;
- (void)setMainItems:(NSArray<PortalMenuItem *> *)items;
- (void)showAppItems:(NSArray<PortalMenuItem *> *)items;
- (void)expand;
- (void)collapseAnimated:(BOOL)animated;
- (void)showMessage:(NSString *)message;
/// Cancels pending callbacks, collapses, hides the message and pauses rendering; called
/// before the overlay is removed from the Lock Screen.
- (void)prepareForDetach;

/// The decision -hitTest:withEvent: makes; `touch` is YES for a real touch
/// event (only those collapse an open menu when they land outside).
- (nullable UIView *)portalHitTest:(CGPoint)point touch:(BOOL)touch timestamp:(NSTimeInterval)timestamp;

// Introspection for tests and the preview.
@property (nonatomic, readonly) CGRect orbFrame;
@property (nonatomic, readonly) NSArray<UIControl *> *itemControls;
@property (nonatomic, readonly, nullable) NSString *visibleMessage;
@property (nonatomic, readonly) NSArray<PortalMenuItem *> *currentItems;

@end

NS_ASSUME_NONNULL_END
