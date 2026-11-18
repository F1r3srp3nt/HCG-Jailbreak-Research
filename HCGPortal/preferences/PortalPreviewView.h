//
//  PortalPreviewView.h
//  HCG Portal — Hakmi Capital Group
//
//  A miniature Lock Screen for Settings: a stand-in wallpaper, clock, date,
//  widget row, optional sample notifications and media player, the flashlight
//  and camera buttons, and the REAL PortalView placed by the REAL layout solver
//  (PortalCore portal_layout) — so the preview collapses and shrinks exactly
//  where SpringBoard would on a screen of this size.
//
//  All sample content is generic ("Messages", "Calendar"): nothing is read from
//  the phone. The preview pauses when it is off screen.
//

#import <UIKit/UIKit.h>

#import "PortalCore.h"
#import "PortalPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface PortalPreviewView : UIView

@property (nonatomic) BOOL showsNotifications;
@property (nonatomic) BOOL showsMedia;
/// The screen being previewed (the phone's own bounds by default), in points.
@property (nonatomic, readonly) CGSize screenSize;
@property (nonatomic, readonly) PortalLayout layout;
@property (nonatomic, readonly) PortalPlacement placement;

- (void)reloadWithSettings:(PortalSettings *)settings;
/// Live placement while dragging or sliding (not saved).
- (void)setPlacement:(PortalPlacement)placement;
/// Converts a point in this view to the previewed screen's coordinates.
- (CGPoint)screenPointFromPoint:(CGPoint)point;
/// The anchor (bottom of the clock / widgets) in screen coordinates.
@property (nonatomic, readonly) CGFloat anchor;

@end

NS_ASSUME_NONNULL_END
