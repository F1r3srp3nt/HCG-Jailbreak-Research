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
#import <objc/runtime.h>
#include <math.h>

#pragma mark - Layer record

/// What a layer looked like before Vortex touched it.
@interface VortexLayerRecord : NSObject
@property (nonatomic) float originalOpacity;
@property (nonatomic) float lastAppliedOpacity;
@end

@implementation VortexLayerRecord
@end

/// What an icon layer looked like before a per-icon effect touched it.
@interface VortexIconRecord : NSObject
@property (nonatomic) CGFloat originalZPosition;
@property (nonatomic) float originalOpacity;
@property (nonatomic) float lastAppliedOpacity;
@property (nonatomic) NSUInteger frame;   ///< last update frame that set this layer
@end

@implementation VortexIconRecord
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
    NSMapTable<CALayer *, VortexIconRecord *> *_iconRecords; // weak icon layer -> record
    NSUInteger _frame;                                    // update counter (icon bookkeeping)
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
        _iconRecords = [NSMapTable weakToStrongObjectsMapTable];
        _presented = NAN;
        _configuration = [VortexPreferences configurationFromDictionary:nil];
        [self resolveEffects];
        // Process-lifetime singleton: the observer is never removed.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reduceMotionChanged:)
                                                     name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)reduceMotionChanged:(NSNotification *)note {
    @try {
        [self resetTransitionState];
        [self resolveEffects];
        VortexLogDebug("Reduce Motion is now %d", UIAccessibilityIsReduceMotionEnabled());
    } @catch (NSException *exception) {
        [self tripWithReason:[NSString stringWithFormat:@"reduce motion: %@", exception.reason]];
    }
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
    if ([identifier isEqualToString:VortexEffectIdentifierTornado]) {
        // Reduce Motion: icons flying around is exactly what it asks to avoid.
        if (UIAccessibilityIsReduceMotionEnabled())
            return [[VortexEffectRegistry sharedRegistry] effectForIdentifier:VortexEffectIdentifierStock];
        return [[VortexTornadoEffect alloc] initWithParameters:self.configuration.tornadoParameters];
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
        if (_records.count || _iconRecords.count) [self restoreAll];
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
        if (_records.count || _iconRecords.count) [self restoreAll];
        return;
    }
    if (_records.count || _iconRecords.count || _displayLink) [self updateAdvancingPresentation:NO deltaTime:0.0];
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
    id<VortexEffect> effect = snapshot.direction == VortexNavigationBackward ? _backwardEffect : _forwardEffect;
    id<VortexIconEffect> iconEffect =
        [effect conformsToProtocol:@protocol(VortexIconEffect)] ? (id<VortexIconEffect>)effect : nil;
    _frame++;
    _applying = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        for (NSInteger i = 0; i < geometry.count; i++) {
            UIView *page = (__bridge UIView *)geometry.views[i];
            VortexPageVisual visual = vortex_compose_page(&snapshot, geometry.positions[i], _presented,
                                                          geometry.actual, VortexEffectTrampoline,
                                                          (__bridge void *)self, &params);
            BOOL pageFollows = YES;
            if (vortex_visual_is_identity(visual)) {
                [self restoreLayer:page.layer];
            } else {
                pageFollows = [self applyVisual:visual toLayer:page.layer geometry:&geometry];
            }
            VortexPageRole role = snapshot.active ? vortex_nav_role(&snapshot, geometry.positions[i]) : VortexPageRoleNone;
            // Icons move only if their page is under Vortex's control too.
            if (iconEffect && pageFollows && (role == VortexPageRoleOutgoing || role == VortexPageRoleIncoming)) {
                [self applyIconEffect:iconEffect toPage:page role:role snapshot:&snapshot parameters:&params];
            }
        }
        [self restoreIconsNotUpdatedThisFrame];
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

- (BOOL)applyVisual:(VortexPageVisual)visual toLayer:(CALayer *)layer geometry:(const VortexPageGeometry *)geometry {
    if (!layer) return NO;

    VortexLayerRecord *record = [_records objectForKey:layer];
    if (!record) {
        if (!CATransform3DIsIdentity(layer.sublayerTransform)) {
            // Someone else (SpringBoard or another tweak) currently owns this
            // property. Never fight over it; re-checked every frame, so the
            // page participates again once the other owner lets go.
            VortexLogDebug("skipping a page layer with a pre-existing sublayerTransform");
            return NO;
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
    return YES;
}

#pragma mark Icon state (per-icon effects)

- (void)applyIconEffect:(id<VortexIconEffect>)effect
                 toPage:(UIView *)page
                   role:(VortexPageRole)role
               snapshot:(const VortexNavSnapshot *)snapshot
             parameters:(const VortexEffectParameters *)params {
    Class iconClass = objc_getClass(VORTEX_SB_ICON_VIEW_CLASS);
    if (!iconClass) return;
    CGRect bounds = page.bounds;
    double width = CGRectGetWidth(bounds), height = CGRectGetHeight(bounds);
    if (width < 1.0 || height < 1.0) return;
    double midX = CGRectGetMidX(bounds), midY = CGRectGetMidY(bounds);

    // Stack storage only: no per-frame allocation beyond -subviews itself.
    __unsafe_unretained UIView *views[VORTEX_TORNADO_MAX_ICONS];
    VortexIconSlot slots[VORTEX_TORNADO_MAX_ICONS];
    BOOL fallback[VORTEX_TORNADO_MAX_ICONS];
    VortexIconSlot ranked[VORTEX_TORNADO_MAX_ICONS];
    int rankedIndex[VORTEX_TORNADO_MAX_ICONS];
    int n = 0, m = 0;
    for (UIView *view in page.subviews) {
        if (n >= VORTEX_TORNADO_MAX_ICONS) break;
        if (![view isKindOfClass:iconClass] || view.hidden || view.alpha <= 0.01) continue;
        CGRect b = view.bounds;
        CGPoint c = view.center; // in the page's bounds coordinates
        if (!isfinite(c.x) || !isfinite(c.y)) continue;
        // Widgets and other oversized views get the explicit fallback (fade in
        // place); only ordinary icons join the funnel.
        BOOL big = CGRectGetWidth(b) > 0.3 * width || CGRectGetHeight(b) > 0.3 * width;
        views[n] = view;
        fallback[n] = big;
        slots[n] = (VortexIconSlot){ c.x - midX, c.y - midY, 0.0, 0, 0 };
        if (!big) {
            ranked[m] = slots[n];
            rankedIndex[m] = n;
            m++;
        }
        n++;
    }
    vortex_tornado_rank(ranked, m, 0.08 * width);
    for (int k = 0; k < m; k++) slots[rankedIndex[k]] = ranked[k];

    for (int i = 0; i < n; i++) {
        VortexIconVisual v = fallback[i]
            ? [effect fallbackVisualForRole:role progress:snapshot->progress parameters:params]
            : [effect iconVisualForRole:role
                               progress:snapshot->progress
                             navigation:snapshot->direction
                                   slot:slots[i]
                              pageWidth:width
                             pageHeight:height
                             parameters:params];
        [self applyIconVisual:v toLayer:views[i].layer];
    }
}

- (void)applyIconVisual:(VortexIconVisual)visual toLayer:(CALayer *)layer {
    if (!layer) return;
    VortexIconRecord *record = [_iconRecords objectForKey:layer];
    if (vortex_icon_is_identity(visual)) {
        if (record) [self restoreIconLayer:layer];
        return;
    }
    if (!record) {
        if (!CATransform3DIsIdentity(layer.sublayerTransform)) return; // someone else owns it: leave the icon alone
        record = [[VortexIconRecord alloc] init];
        record.originalZPosition = layer.zPosition;
        record.originalOpacity = layer.opacity;
        record.lastAppliedOpacity = layer.opacity;
        [_iconRecords setObject:record forKey:layer];
    } else if (fabsf(layer.opacity - record.lastAppliedOpacity) > 0.001f) {
        record.originalOpacity = layer.opacity; // SpringBoard changed it meanwhile: adopt
    }
    record.frame = _frame;

    CATransform3D t = CATransform3DMakeTranslation((CGFloat)visual.tx, (CGFloat)visual.ty, 0);
    if (visual.rotation != 0.0) t = CATransform3DRotate(t, (CGFloat)visual.rotation, 0, 0, 1);
    if (visual.scale != 1.0 && visual.scale > 0.0) t = CATransform3DScale(t, (CGFloat)visual.scale, (CGFloat)visual.scale, 1);
    layer.sublayerTransform = t;
    layer.zPosition = record.originalZPosition + (CGFloat)visual.z;
    float target = (float)(record.originalOpacity * vortex_clamp01(isnan(visual.opacity) ? 1.0 : visual.opacity));
    if (fabsf(layer.opacity - target) > 0.0005f) layer.opacity = target;
    record.lastAppliedOpacity = layer.opacity;
}

- (void)restoreIconLayer:(CALayer *)layer {
    VortexIconRecord *record = layer ? [_iconRecords objectForKey:layer] : nil;
    if (!record) return;
    layer.sublayerTransform = CATransform3DIdentity;
    layer.zPosition = record.originalZPosition;
    if (fabsf(layer.opacity - record.lastAppliedOpacity) <= 0.001f) layer.opacity = record.originalOpacity;
    [_iconRecords removeObjectForKey:layer];
}

- (void)restoreIconsNotUpdatedThisFrame {
    if (!_iconRecords.count) return;
    for (CALayer *layer in [[_iconRecords keyEnumerator] allObjects]) {
        if ([_iconRecords objectForKey:layer].frame != _frame) [self restoreIconLayer:layer];
    }
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
    if (!_records.count && !_iconRecords.count) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        for (CALayer *layer in [[_iconRecords keyEnumerator] allObjects]) {
            [self restoreIconLayer:layer];
        }
        for (CALayer *layer in [[_records keyEnumerator] allObjects]) {
            [self restoreLayer:layer];
        }
    } @finally {
        [CATransaction commit];
    }
    [_iconRecords removeAllObjects];
    [_records removeAllObjects];
    VortexLogDebug("restored all page and icon layers");
}

- (NSUInteger)modifiedLayerCount {
    return _records.count + _iconRecords.count;
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
