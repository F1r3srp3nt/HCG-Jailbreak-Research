//
//  VortexEffect.h
//  HCG Vortex — Hakmi Capital Group
//
//  Effect interface + built-in effect classes + registry.
//
//  Adding an effect (v0.2.0+): create a class conforming to <VortexEffect>,
//  return a VortexPageVisual for (role, progress, navigation), and register
//  it in VortexEffectRegistry -registerBuiltins. The engine, navigation and
//  preferences need no changes beyond adding the identifier to
//  +[VortexPreferences validEffectIdentifiers] and the Settings list.
//

#import <Foundation/Foundation.h>
#import "../src/VortexTypes.h"
#import "../src/VortexTornado.h"

NS_ASSUME_NONNULL_BEGIN

@protocol VortexEffect <NSObject>

/// Persisted identifier, e.g. "vertical-rise".
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *displayName;

/// Visual state for a page.
///  role:       outgoing / incoming (never None — the engine handles those)
///  progress:   RAW transition progress 0..1 (gesture-derived, not eased)
///  navigation: actual navigation direction (forward == finger swipes left)
///
/// Contract (enforced by tests for the built-ins): at progress 0 the outgoing
/// page must be identity and the incoming page invisible; at progress 1 the
/// incoming page must be identity and the outgoing page invisible. This is
/// what makes interrupted gestures and multi-page flicks seamless.
- (VortexPageVisual)visualForRole:(VortexPageRole)role
                         progress:(double)progress
                       navigation:(VortexNavigationDirection)navigation
                       parameters:(const VortexEffectParameters *)parameters;

@end

/// Optional: effects that move individual ICONS, not just whole pages
/// (v0.2.0+, Tornado). The engine still applies the page visual from
/// -visualForRole:..., then asks for one visual per icon view of each
/// outgoing / incoming page. Same contract as pages: at progress 0 the
/// outgoing icons are identity and the incoming icons invisible; at progress 1
/// the reverse. Pure functions of progress, so pausing, reversing and
/// cancelling need no extra state.
@protocol VortexIconEffect <VortexEffect>
/// slot: the icon's grid position relative to its page centre, and its rank.
/// pageWidth / pageHeight: the icon list view's bounds, points.
- (VortexIconVisual)iconVisualForRole:(VortexPageRole)role
                             progress:(double)progress
                           navigation:(VortexNavigationDirection)navigation
                                 slot:(VortexIconSlot)slot
                            pageWidth:(double)pageWidth
                           pageHeight:(double)pageHeight
                           parameters:(const VortexEffectParameters *)parameters;
/// Explicit fallback for icon views that are not ordinary app icons
/// (widgets and other oversized views): they must not be thrown around.
- (VortexIconVisual)fallbackVisualForRole:(VortexPageRole)role
                                 progress:(double)progress
                               parameters:(const VortexEffectParameters *)parameters;
@end

/// Tornado: the icons lift out of the grid into a tapered helical funnel that
/// travels with the swipe; the incoming icons unwind out of it into place.
/// Built per configuration (it carries the user's Tornado settings).
@interface VortexTornadoEffect : NSObject <VortexIconEffect>
- (instancetype)initWithParameters:(VortexTornadoParameters)parameters NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) VortexTornadoParameters tornadoParameters;
@end

/// Base for every effect that is a pair of directions (incoming-from /
/// outgoing-to). Subclasses override the two direction methods.
@interface VortexDirectionalEffect : NSObject <VortexEffect>
- (VortexDirection)incomingDirectionForNavigation:(VortexNavigationDirection)navigation;
- (VortexDirection)outgoingDirectionForNavigation:(VortexNavigationDirection)navigation;
@end

/// Built-in effects backed by the tested C direction table.
@interface VortexBuiltinDirectionalEffect : VortexDirectionalEffect
@property (nonatomic, readonly) VortexBuiltinEffect builtin;
- (instancetype)initWithBuiltin:(VortexBuiltinEffect)builtin NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface VortexStockEffect : VortexBuiltinDirectionalEffect
- (instancetype)init;
@end

/// Effect A — visual motion opposite to the swipe; navigation unchanged.
@interface VortexReverseSlideEffect : VortexBuiltinDirectionalEffect
- (instancetype)init;
@end

/// Effect B — incoming rises from below, outgoing moves up.
@interface VortexVerticalRiseEffect : VortexBuiltinDirectionalEffect
- (instancetype)init;
@end

/// Effect C — incoming enters from above, outgoing moves down.
@interface VortexVerticalFallEffect : VortexBuiltinDirectionalEffect
- (instancetype)init;
@end

/// User-defined directions from the Direction Matrix (8 directions each).
@interface VortexCustomDirectionalEffect : VortexDirectionalEffect
- (instancetype)initWithIncomingFrom:(VortexDirection)incoming outgoingTo:(VortexDirection)outgoing;
@property (nonatomic, readonly) VortexDirection incoming;
@property (nonatomic, readonly) VortexDirection outgoing;
@end

@interface VortexEffectRegistry : NSObject
+ (instancetype)sharedRegistry;
- (void)registerEffect:(id<VortexEffect>)effect;
- (nullable id<VortexEffect>)effectForIdentifier:(NSString *)identifier;
- (NSArray<NSString *> *)registeredIdentifiers;
@end

NS_ASSUME_NONNULL_END
