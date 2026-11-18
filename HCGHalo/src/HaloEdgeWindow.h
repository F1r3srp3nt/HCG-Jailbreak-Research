//
//  HaloEdgeWindow.h
//  HCG Halo — Hakmi Capital Group
//
//  HCG Halo's own overlay window in SpringBoard, used for the "Show Halo on"
//  policies that reach beyond the Home Screen (Selected App Only, Always,
//  Always Except Lock Screen, Always Except When Screen Is Off). Home Screen
//  Only keeps the 0.2.0 host, the Home Screen window, unchanged.
//
//  Never interactive: userInteractionEnabled is NO, -hitTest: returns nil (so
//  UIKit passes every touch to the windows beneath), it never becomes key and
//  never affects the status bar. It is hidden whenever the border is hidden,
//  so a hidden border costs no compositing either.
//
//  To appear above apps and the Lock Screen it uses a high window level and
//  asks UIKit for a secure context (private, optional overrides; if UIKit no
//  longer calls them, the window simply stays under the Lock Screen).
//  Device behaviour is not yet verified.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Above system alerts (2000), so the edge light is not cut off by them.
#define HALO_EDGE_WINDOW_LEVEL 2050.0

@interface HaloEdgeWindow : UIWindow
/// A window on `scene`, sized to its screen, with a non-interactive root view.
- (instancetype)initForScene:(UIWindowScene *)scene;
/// Where to add the overlay (fills the window, declines touches).
@property (nonatomic, readonly) UIView *contentView;
@end

NS_ASSUME_NONNULL_END
