//
//  VortexAnimationEngine.m
//  HCG Vortex — Hakmi Capital Group
//

#import "VortexAnimationEngine.h"
#import "VortexLog.h"
#import "VortexMath.h"
#import "VortexNavigation.h"
#import "VortexSpringBoard.h"
#import "../effects/VortexEffect.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>

#pragma mark - Layer record

/// What a layer looked like before Vortex touched it.
@interface VortexLayerRecord : NSObject
@property (nonatomic) float originalOpacity;
@property (nonatomic) float lastAppliedOpacity;
@end

@implementation VortexLayerRecord
@end

#pragma mark - Engine

@interface VortexAnimationEngine ()
@property (nonatomic, readwrite, getter=isTripped) BOOL tripped;
@end

@implementation VortexAnimationEngine {
    __weak UIView *_folderView;
    __weak UIScrollView *_scrollView;
    VortexNavigation *_navigation;
    NSMapTable<CALayer *, VortexLayerRecord *> *_records; // weak layer -> record
    id<VortexEffect> _forwardEffect;                      // finger swipes left
    id<VortexEffect> _backwardEffect;                     // finger swipes right
    double _presented;                                    // presented scroll position (page units)
    CADisplayLink *_displayLink;
    CFTimeInterval _lastTimestamp;
    BOOL _applying;
}

+ (instancetype)sharedEngine {
    // SpringBoard main thread only.
    static VortexAnimationEngine *engine = nil;
    if (!engine) engine = [[VortexAnimationEngine alloc] init];
    return engine;
}

- (instancetype)init {
    if ((self = [super init])) {
        _navigation = [[VortexNavigation alloc] init];
        _records = [NSMapTable weakToStrongObjectsMapTable];
        _presented = NAN;
        _configuration = [VortexPreferences configurationFromDictionary:nil];
        [self resolveEffects];
    }
    return self;
}

#pragma mark Configuration

- (void)setConfiguration:(VortexConfiguration *)configuration {
    [self restoreAll];
    _configuration = configuration ?: [VortexPreferences configurationFromDictionary:nil];
    self.tripped = NO;
    [self resolveEffects];
    VortexLogDebug("configuration applied: %{public}@", _configuration.description);
}

- (id<VortexEffect>)effectForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:VortexEffectIdentifierCustom]) {
        return [[VortexCustomDirectionalEffect alloc] initWithIncomingFrom:self.configuration.incomingDirection
                                                                outgoingTo:self.configuration.outgoingDirection];
    }
    id<VortexEffect> effect = [[VortexEffectRegistry sharedRegistry] effectForIdentifier:identifier];
    return effect ?: [[VortexEffectRegistry sharedRegistry] effectForIdentifier:VortexEffectIdentifierStock];
}

- (void)resolveEffects {
    _forwardEffect = [self effectForIdentifier:[self.configuration effectIdentifierForNavigation:VortexNavigationForward]];
    _backwardEffect = [self effectForIdentifier:[self.configuration effectIdentifierForNavigation:VortexNavigationBackward]];
}

- (void)tripWithReason:(NSString *)reason {
    self.tripped = YES;
    VortexLogError("engine tripped, falling back to stock behaviour: %{public}@", reason);
    @try {
        [self restoreAll];
    } @catch (NSException *exception) {
        VortexLogError("restore after trip failed: %{public}@", exception.reason);
    }
}

#pragma mark Entry points

- (BOOL)isActive {
    return self.configuration.enabled && !self.configuration.isStock && !self.tripped;
}

- (void)folderView:(UIView *)folderView didScroll:(UIScrollView *)scrollView {
    if (![self isActive]) {
        if (_records.count) [self restoreAll];
        return;
    }
    UIView *current = _folderView;
    if (current && current != folderView) {
        [self restoreAll]; // a different root folder view (e.g. after a respring of the UI)
    }
    _folderView = folderView;
    _scrollView = scrollView;
    [self updateAdvancingPresentation:NO deltaTime:0.0];
}

- (void)folderViewDidLayout:(UIView *)folderView {
    if (folderView != _folderView) return;
    if (![self isActive]) {
        if (_records.count) [self restoreAll];
        return;
    }
    if (_records.count || _displayLink) [self updateAdvancingPresentation:NO deltaTime:0.0];
}

- (void)tick:(CADisplayLink *)link {
    @try {
        CFTimeInterval now = link.timestamp;
        CFTimeInterval dt = _lastTimestamp > 0 ? now - _lastTimestamp : link.duration;
        _lastTimestamp = now;
        if (![self isActive]) {
            [self restoreAll];
            return;
        }
        [self updateAdvancingPresentation:YES deltaTime:dt];
    } @catch (NSException *exception) {
        [self tripWithReason:[NSString stringWithFormat:@"display link: %@", exception.reason]];
    }
}

#pragma mark Core update

static VortexPageVisual VortexEffectTrampoline(void *context, VortexPageRole role, double progress,
                                               VortexNavigationDirection direction,
                                               const VortexEffectParameters *params) {
    VortexAnimationEngine *engine = (__bridge VortexAnimationEngine *)context;
    id<VortexEffect> effect = direction == VortexNavigationBackward ? engine->_backwardEffect : engine->_forwardEffect;
    if (!effect) return vortex_identity_visual();
    return [effect visualForRole:role progress:progress navigation:direction parameters:params];
}

- (BOOL)folderViewIsEditing:(UIView *)folderView {
    id<VortexFolderViewLike> folder = (id<VortexFolderViewLike>)folderView;
    return [folder respondsToSelector:@selector(isEditing)] && [folder isEditing];
}

- (void)updateAdvancingPresentation:(BOOL)advance deltaTime:(double)dt {
    if (_applying) return; // never re-enter (layout triggered by our own changes)
    UIView *folderView = _folderView;
    UIScrollView *scrollView = _scrollView;

    // Bail-outs that must leave the Home Screen exactly stock.
    if (!folderView || !scrollView || !folderView.window || folderView.hidden ||
        [self folderViewIsEditing:folderView]) {
        [self resetTransitionState];
        return;
    }

    VortexPageGeometry geometry;
    if (![VortexNavigation collectGeometryForFolderView:folderView scrollView:scrollView geometry:&geometry]) {
        [self resetTransitionState];
        return;
    }

    // Presentation vs. gesture: the presented position chases the real one.
    NSTimeInterval duration = self.configuration.duration;
    if (isnan(_presented) || duration <= 0.0) {
        _presented = geometry.actual;
    } else if (advance) {
        _presented = vortex_smooth_step(_presented, geometry.actual, dt, duration);
    }

    VortexNavSnapshot snapshot = [_navigation stepWithPresentedPosition:_presented geometry:&geometry];
    if (!snapshot.inRange) {
        // Today View / App Library / rubber-banding: pure stock.
        [self resetTransitionState];
        return;
    }

    VortexEffectParameters params = self.configuration.parameters;
    _applying = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        for (NSInteger i = 0; i < geometry.count; i++) {
            UIView *page = (__bridge UIView *)geometry.views[i];
            VortexPageVisual visual = vortex_compose_page(&snapshot, geometry.positions[i], _presented,
                                                          geometry.actual, VortexEffectTrampoline,
                                                          (__bridge void *)self, &params);
            if (vortex_visual_is_identity(visual)) {
                [self restoreLayer:page.layer];
            } else {
                [self applyVisual:visual toLayer:page.layer geometry:&geometry];
            }
        }
    } @finally {
        [CATransaction commit];
        _applying = NO;
    }

    BOOL converged = fabs(_presented - geometry.actual) < 1e-9;
    if (converged) {
        [self stopDisplayLink];
    } else {
        [self startDisplayLink];
    }
}

- (void)resetTransitionState {
    _presented = NAN;
    [_navigation reset];
    [self stopDisplayLink];
    [self restoreAll];
}

#pragma mark Layer state

- (void)applyVisual:(VortexPageVisual)visual toLayer:(CALayer *)layer geometry:(const VortexPageGeometry *)geometry {
    if (!layer) return;

    VortexLayerRecord *record = [_records objectForKey:layer];
    if (!record) {
        if (!CATransform3DIsIdentity(layer.sublayerTransform)) {
            // Someone else (SpringBoard or another tweak) currently owns this
            // property. Never fight over it; re-checked every frame, so the
            // page participates again once the other owner lets go.
            VortexLogDebug("skipping a page layer with a pre-existing sublayerTransform");
            return;
        }
        record = [[VortexLayerRecord alloc] init];
        record.originalOpacity = layer.opacity;
        record.lastAppliedOpacity = layer.opacity;
        [_records setObject:record forKey:layer];
    } else if (fabsf(layer.opacity - record.lastAppliedOpacity) > 0.001f) {
        // SpringBoard changed the opacity while we were active: adopt it.
        record.originalOpacity = layer.opacity;
    }

    CATransform3D t = CATransform3DIdentity;
    if (visual.perspective != 0.0) t.m34 = (CGFloat)visual.perspective;
    t = CATransform3DTranslate(t, (CGFloat)(visual.translation.x * geometry->pitch),
                               (CGFloat)(visual.translation.y * geometry->pageHeight), 0);
    if (visual.rotationY != 0.0) t = CATransform3DRotate(t, (CGFloat)visual.rotationY, 0, 1, 0);
    if (visual.scale != 1.0 && visual.scale > 0.0) t = CATransform3DScale(t, (CGFloat)visual.scale, (CGFloat)visual.scale, 1);
    layer.sublayerTransform = t;

    double opacity = vortex_clamp01(isnan(visual.opacity) ? 1.0 : visual.opacity);
    float target = (float)(record.originalOpacity * opacity);
    if (fabsf(layer.opacity - target) > 0.0005f) layer.opacity = target;
    record.lastAppliedOpacity = layer.opacity;
}

- (void)restoreLayer:(CALayer *)layer {
    VortexLayerRecord *record = layer ? [_records objectForKey:layer] : nil;
    if (!record) return;
    layer.sublayerTransform = CATransform3DIdentity;
    // Only put opacity back if nobody else changed it in the meantime.
    if (fabsf(layer.opacity - record.lastAppliedOpacity) <= 0.001f) layer.opacity = record.originalOpacity;
    [_records removeObjectForKey:layer];
}

- (void)restoreAll {
    if (!_records.count) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        for (CALayer *layer in [[_records keyEnumerator] allObjects]) {
            [self restoreLayer:layer];
        }
    } @finally {
        [CATransaction commit];
    }
    [_records removeAllObjects];
    VortexLogDebug("restored all page layers");
}

- (NSUInteger)modifiedLayerCount {
    return _records.count;
}

#pragma mark Display link (presentation smoothing only)

- (void)startDisplayLink {
    if (_displayLink) return;
    _lastTimestamp = 0;
    // The engine is a process-lifetime singleton, so the link's strong
    // reference to it is not a leak; the link is invalidated on stop.
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [_displayLink invalidate];
    _displayLink = nil;
    _lastTimestamp = 0;
}

@end
