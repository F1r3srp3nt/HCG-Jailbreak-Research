//
//  HaloPanelBorderView.h
//  HCG Halo — Hakmi Capital Group
//
//  The border Halo draws around the HCG Nexus panel. It is added to the
//  border host view that the RUNNING Nexus panel provides
//  (HCGNexusBorderInterface.borderHostView), so it inherits the panel's real
//  position, transform, alpha, rotation and size at no cost and can never
//  outlive it.
//
//  Geometry: the light runs `outset` points outside the live panel edge (both
//  from the installed Nexus definition), concentric with its corners. The view
//  extends `glowMargin` beyond the panel so the glow is not clipped, and (when
//  the definition asks, clipInterior) masks out the panel's interior so it can
//  never cover the panel's controls. Never interactive, hidden from
//  accessibility.
//
//  Effects (all optional, brief, never delaying interaction):
//    * opening trace: a light travels once around the panel while the panel
//      opens, then the selected mode fades in;
//    * workspace pulse: one soft swell, about half a second;
//    * closing: the border simply fades with the panel (it is inside it).
//

#import <UIKit/UIKit.h>

#import "HaloConfig.h"
#import "HaloRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@class HaloNexusDefinition;

@interface HaloPanelBorderView : UIView

- (instancetype)initWithDefinition:(HaloNexusDefinition *)definition NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) HaloNexusDefinition *definition;
@property (nonatomic, readonly) HaloRenderer *renderer;
/// Live corner radius of the panel (from Nexus); <= 0 uses the definition's.
@property (nonatomic) CGFloat panelCornerRadius;

/// Adds the view to `host` (the Nexus border host) and sizes it from the host's bounds.
- (void)attachToHostView:(UIView *)host;
/// Re-reads the host's bounds (call on Nexus geometry events; layout also does it).
- (void)relayout;

/// reduceTransparency removes the glow (translucent bloom) and keeps a solid line.
- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan reduceTransparency:(BOOL)reduceTransparency;

/// Visible and animating (YES) or hidden with a frozen layer clock (NO).
@property (nonatomic, getter=isActive) BOOL active;

- (void)playOpeningTraceWithDuration:(NSTimeInterval)transitionDuration;
- (void)cancelOpeningTrace;
@property (nonatomic, readonly, getter=isTracing) BOOL tracing;
- (void)playWorkspacePulseReducedMotion:(BOOL)reduceMotion;

/// Removes every layer, animation and the view itself.
- (void)teardown;

@end

NS_ASSUME_NONNULL_END
