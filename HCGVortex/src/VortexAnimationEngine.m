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
#import <objc/message.h>
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
@property (nonatomic, weak) UIView *view;              ///< for the label (SBIconView labelHidden)
@property (nonatomic) BOOL hidLabel;                    ///< YES while Vortex has hidden the label
@property (nonatomic) CGFloat originalZPosition;
@property (nonatomic) float originalOpacity;
@property (nonatomic) float lastAppliedOpacity;
@property (nonatomic) NSUInteger frame;   ///< last update frame that set this layer
@end

@implementation VortexIconRecord
@end

/// Circuit Flow traces drawn on one page: added by Vortex, removed by Vortex.
/// Three brightness buckets x (glow, core) shape layers; no shadows (cheap).
#define VORTEX_TRACE_BUCKETS 3
@interface VortexTraceOverlay : NSObject
@property (nonatomic, strong) CALayer *container;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *glow;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *core;
@property (nonatomic) NSUInteger frame;
@end

@implementation VortexTraceOverlay
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
    NSMapTable<CALayer *, VortexTraceOverlay *> *_overlays;  // weak page layer -> Circuit Flow traces
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
        _overlays = [NSMapTable weakToStrongObjectsMapTable];
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
    VortexIconEffectKind kind;
    if ([VortexPreferences iconEffectKind:&kind forIdentifier:identifier]) {
        // Reduce Motion: icons flying around is exactly what it asks to avoid.
        if (UIAccessibilityIsReduceMotionEnabled())
            return [[VortexEffectRegistry sharedRegistry] effectForIdentifier:VortexEffectIdentifierStock];
        return [[VortexGeometricEffect alloc] initWithKind:kind
                                                identifier:identifier
                                               displayName:identifier
                                                  settings:self.configuration.iconEffectSettings];
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
        if (_records.count || _iconRecords.count || _overlays.count) [self restoreAll];
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

- (void)iconListViewDidLayout:(UIView *)listView {
    // SpringBoard laid out an icon page (it may have just added or revealed icon
    // views). During a transition, re-apply in the same frame so nothing renders
    // untransformed. Inert when no transition is active.
    if (_applying || ![self isActive] || !(_records.count || _iconRecords.count)) return;
    UIView *folderView = _folderView;
    if (!folderView || ![listView isDescendantOfView:folderView]) return;
    [self updateAdvancingPresentation:NO deltaTime:0.0];
}

- (void)folderViewDidLayout:(UIView *)folderView {
    if (folderView != _folderView) return;
    if (![self isActive]) {
        if (_records.count || _iconRecords.count || _overlays.count) [self restoreAll];
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
            VortexPageRole role = snapshot.active ? vortex_nav_role(&snapshot, geometry.positions[i]) : VortexPageRoleNone;
            // First-frame guard (0.3.0~beta1 device recording): on the first frame
            // a page joins a pinned icon effect as the incoming page, SpringBoard
            // may add or reveal its icon views AFTER this pass in the same frame,
            // and they rendered untransformed at their grid positions for that
            // frame. Hold the page invisible for that one frame; by the next
            // frame every icon view is transformed (and hidden in the formation).
            if (iconEffect && role == VortexPageRoleIncoming && [iconEffect respondsToSelector:@selector(pinsPages)] &&
                [(id<VortexIconEffect>)iconEffect pinsPages] && ![_records objectForKey:page.layer]) {
                visual.opacity = 0.0;
            }
            BOOL pageFollows = YES;
            if (vortex_visual_is_identity(visual)) {
                [self restoreLayer:page.layer];
            } else {
                pageFollows = [self applyVisual:visual toLayer:page.layer geometry:&geometry];
            }
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
        // Hidden icon views are transformed too: SpringBoard may reveal them later
        // in the frame, and they must already be in the formation when it does.
        if (![view isKindOfClass:iconClass]) continue;
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

    BOOL traces = [effect respondsToSelector:@selector(traceForRole:progress:navigation:slot:pageWidth:pageHeight:parameters:)];
    CGMutablePathRef paths[VORTEX_TRACE_BUCKETS] = { NULL, NULL, NULL };
    for (int i = 0; i < n; i++) {
        if (traces && !fallback[i]) {
            VortexTrace t = [effect traceForRole:role
                                        progress:snapshot->progress
                                      navigation:snapshot->direction
                                            slot:slots[i]
                                       pageWidth:width
                                      pageHeight:height
                                      parameters:params];
            if (t.count >= 2) {
                int bucket = t.alpha > 0.66 ? 2 : (t.alpha > 0.33 ? 1 : 0);
                if (!paths[bucket]) paths[bucket] = CGPathCreateMutable();
                CGPathMoveToPoint(paths[bucket], NULL, midX + t.points[0].x, midY + t.points[0].y);
                for (int q = 1; q < t.count; q++)
                    CGPathAddLineToPoint(paths[bucket], NULL, midX + t.points[q].x, midY + t.points[q].y);
            }
        }
        VortexIconVisual v = fallback[i]
            ? [effect fallbackVisualForRole:role progress:snapshot->progress parameters:params]
            : [effect iconVisualForRole:role
                               progress:snapshot->progress
                             navigation:snapshot->direction
                                   slot:slots[i]
                              pageWidth:width
                             pageHeight:height
                             parameters:params];
        [self applyIconVisual:v toView:views[i]];
    }
    if (traces) {
        [self drawTraces:paths onPage:page]; // keeps the overlay for the whole transition (no churn)
        for (int b = 0; b < VORTEX_TRACE_BUCKETS; b++)
            if (paths[b]) CGPathRelease(paths[b]);
    }
}

- (void)drawTraces:(CGMutablePathRef *)paths onPage:(UIView *)page {
    CALayer *pageLayer = page.layer;
    VortexTraceOverlay *overlay = [_overlays objectForKey:pageLayer];
    if (!overlay) {
        overlay = [[VortexTraceOverlay alloc] init];
        CALayer *container = [CALayer layer];
        container.zPosition = -1.0; // behind the icons
        NSMutableArray *glow = [NSMutableArray array], *core = [NSMutableArray array];
        for (int b = 0; b < VORTEX_TRACE_BUCKETS; b++) {
            for (int g = 0; g < 2; g++) {
                CAShapeLayer *line = [CAShapeLayer layer];
                line.fillColor = nil;
                line.lineCap = kCALineCapRound;
                line.lineJoin = kCALineJoinMiter;
                [container addSublayer:line];
                [(g ? core : glow) addObject:line];
            }
        }
        overlay.container = container;
        overlay.glow = glow;
        overlay.core = core;
        [pageLayer insertSublayer:container atIndex:0];
        [_overlays setObject:overlay forKey:pageLayer];
    }
    overlay.frame = _frame;
    overlay.container.frame = pageLayer.bounds;
    NSArray<NSNumber *> *rgb = self.configuration.accentRGB;
    double glow = self.configuration.iconEffectSettings.circuit.glow;
    UIColor *colour = [UIColor colorWithRed:rgb[0].doubleValue green:rgb[1].doubleValue blue:rgb[2].doubleValue alpha:1.0];
    for (int b = 0; b < VORTEX_TRACE_BUCKETS; b++) {
        float level = (float)(b + 1) / VORTEX_TRACE_BUCKETS;
        CAShapeLayer *g = overlay.glow[b], *c = overlay.core[b];
        g.path = paths[b];
        c.path = paths[b];
        g.strokeColor = colour.CGColor;
        c.strokeColor = [colour colorWithAlphaComponent:0.9].CGColor;
        g.lineWidth = (CGFloat)(2.0 + 8.0 * glow);
        c.lineWidth = 1.5;
        g.opacity = (float)(0.35 * glow) * level;
        c.opacity = level;
    }
}

- (void)removeTraceOverlayForLayer:(CALayer *)pageLayer {
    VortexTraceOverlay *overlay = [_overlays objectForKey:pageLayer];
    [overlay.container removeFromSuperlayer];
    [_overlays removeObjectForKey:pageLayer];
}

/// SBIconView label visibility, only through selectors this SpringBoard has.
static BOOL VortexCanToggleLabel(UIView *view) {
    return [view respondsToSelector:@selector(isLabelHidden)] && [view respondsToSelector:@selector(setLabelHidden:)];
}

- (void)setLabelHiddenForRecord:(VortexIconRecord *)record hidden:(BOOL)hidden {
    UIView *view = record.view;
    if (!view || !VortexCanToggleLabel(view) || hidden == record.hidLabel) return;
    @try {
        id<NSObject> icon = (id<NSObject>)view;
        BOOL current = ((BOOL (*)(id, SEL))objc_msgSend)(icon, @selector(isLabelHidden));
        if (hidden) {
            if (current) return; // already hidden by SpringBoard: not ours to manage
            ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, @selector(setLabelHidden:), YES);
            record.hidLabel = YES;
        } else {
            // Only undo our own change: if SpringBoard re-showed it meanwhile, leave it.
            if (current) ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, @selector(setLabelHidden:), NO);
            record.hidLabel = NO;
        }
    } @catch (NSException *exception) {
        record.hidLabel = NO;
        VortexLogDebug("label toggle failed: %{public}@", exception.reason);
    }
}

- (void)applyIconVisual:(VortexIconVisual)visual toView:(UIView *)view {
    CALayer *layer = view.layer;
    if (!layer) return;
    VortexIconRecord *record = [_iconRecords objectForKey:layer];
    if (vortex_icon_is_identity(visual)) {
        if (record) [self restoreIconLayer:layer];
        return;
    }
    if (!record) {
        if (!CATransform3DIsIdentity(layer.sublayerTransform)) return; // someone else owns it: leave the icon alone
        record = [[VortexIconRecord alloc] init];
        record.view = view;
        record.originalZPosition = layer.zPosition;
        record.originalOpacity = layer.opacity;
        record.lastAppliedOpacity = layer.opacity;
        [_iconRecords setObject:record forKey:layer];
    } else if (fabsf(layer.opacity - record.lastAppliedOpacity) > 0.001f) {
        record.originalOpacity = layer.opacity; // SpringBoard changed it meanwhile: adopt
    }
    record.frame = _frame;

    CATransform3D t = CATransform3DIdentity;
    if (visual.tiltX != 0.0 || visual.tiltY != 0.0) t.m34 = -1.0 / 600.0; // perspective for the 3-D tilt
    t = CATransform3DTranslate(t, (CGFloat)visual.tx, (CGFloat)visual.ty, 0);
    if (visual.tiltY != 0.0) t = CATransform3DRotate(t, (CGFloat)visual.tiltY, 0, 1, 0);
    if (visual.tiltX != 0.0) t = CATransform3DRotate(t, (CGFloat)visual.tiltX, 1, 0, 0);
    if (visual.rotation != 0.0) t = CATransform3DRotate(t, (CGFloat)visual.rotation, 0, 0, 1);
    if (visual.scale != 1.0 && visual.scale > 0.0) t = CATransform3DScale(t, (CGFloat)visual.scale, (CGFloat)visual.scale, 1);
    layer.sublayerTransform = t;
    layer.zPosition = record.originalZPosition + (CGFloat)visual.z;
    float target = (float)(record.originalOpacity * vortex_clamp01(isnan(visual.opacity) ? 1.0 : visual.opacity));
    if (fabsf(layer.opacity - target) > 0.0005f) layer.opacity = target;
    record.lastAppliedOpacity = layer.opacity;
    // Labels hidden while the icon is shrunk into a formation (clutter on device).
    [self setLabelHiddenForRecord:record hidden:vortex_icon_hides_label(visual) ? YES : NO];
}

- (void)restoreIconLayer:(CALayer *)layer {
    VortexIconRecord *record = layer ? [_iconRecords objectForKey:layer] : nil;
    if (!record) return;
    [self setLabelHiddenForRecord:record hidden:NO];
    layer.sublayerTransform = CATransform3DIdentity;
    layer.zPosition = record.originalZPosition;
    if (fabsf(layer.opacity - record.lastAppliedOpacity) <= 0.001f) layer.opacity = record.originalOpacity;
    [_iconRecords removeObjectForKey:layer];
}

- (void)restoreIconsNotUpdatedThisFrame {
    for (CALayer *layer in [[_overlays keyEnumerator] allObjects]) {
        if ([_overlays objectForKey:layer].frame != _frame) [self removeTraceOverlayForLayer:layer];
    }
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
    if (!_records.count && !_iconRecords.count && !_overlays.count) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    @try {
        for (CALayer *layer in [[_overlays keyEnumerator] allObjects]) {
            [self removeTraceOverlayForLayer:layer];
        }
        for (CALayer *layer in [[_iconRecords keyEnumerator] allObjects]) {
            [self restoreIconLayer:layer];
        }
        for (CALayer *layer in [[_records keyEnumerator] allObjects]) {
            [self restoreLayer:layer];
        }
    } @finally {
        [CATransaction commit];
    }
    [_overlays removeAllObjects];
    [_iconRecords removeAllObjects];
    [_records removeAllObjects];
    VortexLogDebug("restored all page and icon layers");
}

- (NSUInteger)modifiedLayerCount {
    return _records.count + _iconRecords.count + _overlays.count;
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
