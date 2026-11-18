//
//  VortexAnimationEngine.h
//  HCG Vortex — Hakmi Capital Group
//
//  Presentation layer of HCG Vortex.
//
//  What it touches — and only this:
//    SBIconListView.layer.sublayerTransform   (translation; 3D reserved)
//    SBIconListView.layer.opacity             (only when an effect fades)
//  and, only for per-icon effects (VortexIconEffect, e.g. Tornado), on the
//  SBIconView subviews of the outgoing / incoming pages:
//    SBIconView.layer.sublayerTransform       (offset, scale, rotation)
//    SBIconView.layer.zPosition               (depth ordering among siblings)
//    SBIconView.layer.opacity
//  None of these change frames, centres, subview order, icon order or the
//  persisted layout, and none affect UIKit hit-testing.
//
//  Why sublayerTransform and not view.transform: SpringBoard assigns frames
//  to icon list views during layout, and UIView.frame is undefined while
//  view.transform is non-identity. sublayerTransform is invisible to UIKit
//  layout and hit-testing, so SpringBoard's layout model and touch handling
//  are untouched; only what is drawn moves.
//
//  Every modified layer's original state is recorded and restored when the
//  transition settles, is cancelled, leaves the window, enters edit mode,
//  the configuration changes, the tweak is disabled, or a fault occurs. Icon
//  layers not updated in a frame (their page left the transition, the icon
//  was removed) are restored at the end of that frame.
//
//  Reduce Motion: while it is on, per-icon effects resolve to the stock
//  animation (page effects are unchanged).
//

#import <UIKit/UIKit.h>
#import "VortexPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface VortexAnimationEngine : NSObject

+ (instancetype)sharedEngine;

/// Setting a configuration restores all layers, re-resolves effects and
/// clears a tripped circuit breaker.
@property (nonatomic, strong) VortexConfiguration *configuration;

/// YES after an exception was caught; the engine stays inert (stock
/// behaviour) until the configuration is changed or SpringBoard restarts.
@property (nonatomic, readonly, getter=isTripped) BOOL tripped;
- (void)tripWithReason:(NSString *)reason;

/// Called after SpringBoard's own -scrollViewDidScroll: has run.
- (void)folderView:(UIView *)folderView didScroll:(UIScrollView *)scrollView;
/// Called after SpringBoard's own -layoutSubviews has run.
- (void)folderViewDidLayout:(UIView *)folderView;

/// Put every modified layer back exactly as it was.
- (void)restoreAll;

/// Number of layers currently carrying a Vortex transform (diagnostics).
@property (nonatomic, readonly) NSUInteger modifiedLayerCount;

@end

NS_ASSUME_NONNULL_END
