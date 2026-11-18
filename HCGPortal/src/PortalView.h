//
//  PortalView.h
//  HCG Portal — Hakmi Capital Group
//
//  The portal itself: a dark translucent centre, cyan-and-violet energy rings,
//  a soft outer glow, restrained particles and a shadow for depth. Core
//  Animation only: every animation runs in the render server, so SpringBoard
//  does no per-frame work (no timers, no display link, no drawRect:).
//
//  Shared by SpringBoard, the Settings preview and the Simulator harnesses.
//  Never interactive by itself (PortalOverlayView decides about touches).
//

#import <UIKit/UIKit.h>

#import "PortalCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface PortalView : UIView

- (void)applyAppearance:(PortalAppearance)appearance plan:(PortalRenderPlan)plan;
/// Freezes every animation (layer speed 0, phase kept) and stops the emitter.
@property (nonatomic, getter=isPaused) BOOL paused;
/// Brighter, slightly larger while the radial menu is open.
@property (nonatomic, getter=isExpanded) BOOL expanded;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
/// A short dim pulse while waiting for authentication.
@property (nonatomic, getter=isWaiting) BOOL waiting;
/// The brief opening flourish (about 0.5 s). Never blocks: purely visual, and
/// skipped by plans without unlockAnimation.
- (void)playUnlockFlourish;

// Introspection for tests and the status report.
@property (nonatomic, readonly) PortalRenderPlan plan;
@property (nonatomic, readonly) NSUInteger runningAnimationCount;
@property (nonatomic, readonly) BOOL emitterActive;
@property (nonatomic, readonly) BOOL flourishPlayed;

@end

NS_ASSUME_NONNULL_END
