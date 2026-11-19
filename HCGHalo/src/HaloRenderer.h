//
//  HaloRenderer.h
//  HCG Halo — Hakmi Capital Group
//
//  Builds the Core Animation layer tree for one border. Used by the
//  SpringBoard overlay and by the live preview in Settings.
//
//  Efficiency:
//    * Every animation is a Core Animation animation, run by the render
//      server: this process does no per-frame work and no drawRect:.
//    * The tree is rebuilt only when the appearance, geometry or plan changes.
//    * Single-colour borders stroke shape layers directly (no mask). Gradient
//      borders use one conic gradient behind one mask; Static and Breathing
//      rasterise it once, so only opacity changes per frame.
//    * -setPaused: freezes the layer clock (speed 0), so a hidden or paused
//      border costs no animation work at all.
//

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#import "HaloConfig.h"
#import "HaloGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@interface HaloRenderer : NSObject

/// Root layer. The owner adds it to its view's layer and keeps its frame equal
/// to the view's bounds.
@property (nonatomic, readonly) CALayer *layer;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;
/// Number of layers in the current tree (diagnostics / tests).
@property (nonatomic, readonly) NSUInteger layerCount;
/// Perimeter of the current centre line in fixed points (0 if no path).
@property (nonatomic, readonly) double perimeter;

- (instancetype)initWithContentsScale:(CGFloat)scale NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Display geometry in fixed portrait points, and the mapping from fixed
/// points into the root layer's coordinate space. `unitScale` converts
/// fixed-point widths (thickness, glow) into layer points: 1 on the device;
/// the Settings preview uses a larger value than its path scale so thin
/// lines stay visible. Dash lengths always follow the transform's scale.
- (void)setGeometry:(HaloDisplayGeometry)geometry
         traceCutout:(BOOL)traceCutout
           transform:(CGAffineTransform)transform
           unitScale:(CGFloat)unitScale
              bounds:(CGRect)bounds;

- (void)setAppearance:(HaloAppearance)appearance plan:(HaloRenderPlan)plan;

/// Freezes (YES) or resumes (NO) every animation, keeping their phase.
- (void)setPaused:(BOOL)paused;

/// Removes every layer and animation. The renderer can be configured again.
- (void)teardown;

/// The centre line the renderer draws for `geometry` at `offset` (fixed
/// points), mapped by `transform`. +1 retained; NULL if the geometry is unusable.
/// Used by effects that must follow exactly the same path.
+ (nullable CGPathRef)newPathForGeometry:(HaloDisplayGeometry)geometry
                                  offset:(double)offset
                             traceCutout:(BOOL)traceCutout
                               transform:(CGAffineTransform)transform CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
