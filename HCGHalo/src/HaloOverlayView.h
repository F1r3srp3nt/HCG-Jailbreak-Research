//
//  HaloOverlayView.h
//  HCG Halo — Hakmi Capital Group
//
//  Full-window, non-interactive view that hosts a HaloRenderer.
//
//  Never intercepts touches: userInteractionEnabled is NO, and -hitTest: and
//  -pointInside: always decline, so UIKit hit-testing skips the view and its
//  layers entirely and every touch reaches the Home Screen beneath. It has no
//  gesture recognisers. It is hidden from accessibility (VoiceOver, Switch
//  Control and Full Keyboard Access never see it).
//
//  Orientation: the border is built in the screen's FIXED portrait space and
//  mapped into this view with UIScreen.fixedCoordinateSpace, so the notch stays
//  on the physical top edge whatever the interface orientation.
//

#import <UIKit/UIKit.h>

#import "HaloConfig.h"
#import "HaloGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class HaloOverlayView;

@protocol HaloOverlayViewDelegate <NSObject>
/// Called when the view joins or leaves a window, or its window's visibility may have changed.
- (void)haloOverlayViewDidChangeWindow:(HaloOverlayView *)view;
@end

@interface HaloOverlayView : UIView

@property (nonatomic, weak, nullable) id<HaloOverlayViewDelegate> delegate;

/// Geometry in fixed portrait points. If the real screen differs in size, the
/// width/height are replaced by the real screen's so the border always fits.
- (void)setDisplayGeometry:(HaloDisplayGeometry)geometry traceCutout:(BOOL)traceCutout;
- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan;
/// Hidden overlays are also paused; visible overlays animate only if `animating`.
- (void)setVisible:(BOOL)visible animating:(BOOL)animating;
/// Releases every layer and animation (before removal).
- (void)teardown;

@end

NS_ASSUME_NONNULL_END
