//
//  VortexPreferences.h
//  HCG Vortex — Hakmi Capital Group
//
//  Single source of truth for preference keys, defaults and validation.
//  Compiled into BOTH the SpringBoard tweak and the Settings bundle so the
//  two can never disagree about what a valid value is.
//
//  Storage: CFPreferences, user "mobile", domain com.hakmicapitalgroup.vortex
//  (→ /var/mobile/Library/Preferences/com.hakmicapitalgroup.vortex.plist).
//  Change notification: Darwin notification VortexPreferencesChangedNotification.
//

#import <Foundation/Foundation.h>
#import "VortexTypes.h"

NS_ASSUME_NONNULL_BEGIN

#define VORTEX_BUNDLE_ID "com.hakmicapitalgroup.vortex"
#ifndef VORTEX_VERSION
#error "VORTEX_VERSION must come from the Makefile (control Version)"
#endif

extern NSString *const VortexPreferencesDomain;          // com.hakmicapitalgroup.vortex
extern NSString *const VortexStatusDomain;               // com.hakmicapitalgroup.vortex.status (written by SpringBoard)
extern NSString *const VortexPreferencesChangedNotification;
extern NSString *const VortexKillSwitchPath;             // touch this file + respring = no hooks installed

// Keys
extern NSString *const VortexKeyEnabled;
extern NSString *const VortexKeyPreset;
extern NSString *const VortexKeySwipeLeftEffect;
extern NSString *const VortexKeySwipeRightEffect;
extern NSString *const VortexKeyIncomingDirection;
extern NSString *const VortexKeyOutgoingDirection;
extern NSString *const VortexKeyReverseAnimation;
extern NSString *const VortexKeyDuration;
extern NSString *const VortexKeySpeed;
extern NSString *const VortexKeyIntensity;
extern NSString *const VortexKeyEasing;
extern NSString *const VortexKeyFadePages;
extern NSString *const VortexKeyDiagnosticLogging;

// Status keys (domain VortexStatusDomain)
extern NSString *const VortexStatusKeyState;      // "active" | "disabled" | "incompatible" | "kill-switch" | "auto-disabled" | "fault"
extern NSString *const VortexStatusKeyDetail;
extern NSString *const VortexStatusKeySystemVersion;
extern NSString *const VortexStatusKeyTweakVersion;
extern NSString *const VortexStatusKeyTimestamp;
extern NSString *const VortexStatusKeyUnstableLaunches; // launch guard counter (see VortexCompatibility.h)

// Effect / preset identifiers
extern NSString *const VortexEffectIdentifierStock;
extern NSString *const VortexEffectIdentifierReverseSlide;
extern NSString *const VortexEffectIdentifierVerticalRise;
extern NSString *const VortexEffectIdentifierVerticalFall;
extern NSString *const VortexEffectIdentifierCustom;      // uses incoming/outgoing direction keys
extern NSString *const VortexPresetPerDirection;          // use swipe-left / swipe-right effect keys

/// Immutable, validated snapshot of the user's configuration.
@interface VortexConfiguration : NSObject
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly, copy) NSString *preset;
@property (nonatomic, readonly, copy) NSString *swipeLeftEffect;
@property (nonatomic, readonly, copy) NSString *swipeRightEffect;
@property (nonatomic, readonly) VortexDirection incomingDirection;
@property (nonatomic, readonly) VortexDirection outgoingDirection;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) VortexEffectParameters parameters;
@property (nonatomic, readonly) BOOL diagnosticLogging;

/// True when the configuration would produce stock iOS behaviour: the engine
/// then installs no transforms at all.
@property (nonatomic, readonly, getter=isStock) BOOL stock;

/// Effect identifier to use for a navigation direction, after resolving the
/// preset. Forward == finger swipes left.
- (NSString *)effectIdentifierForNavigation:(VortexNavigationDirection)navigation;
@end

@interface VortexPreferences : NSObject

+ (NSDictionary<NSString *, id> *)defaultValues;
+ (NSArray<NSString *> *)allKeys;

+ (NSArray<NSString *> *)validPresets;
+ (NSArray<NSString *> *)validEffectIdentifiers;
+ (NSArray<NSString *> *)validDirections;
+ (NSArray<NSString *> *)validEasings;
+ (VortexEasing)easingFromString:(NSString *)string;

/// Returns `value` if valid for `key` (numbers are clamped), otherwise the default.
+ (id)sanitizedValue:(nullable id)value forKey:(NSString *)key;

/// Builds a configuration from an arbitrary dictionary (missing / invalid
/// entries fall back to defaults). Pure: no I/O. Used by tests and tooling.
+ (VortexConfiguration *)configurationFromDictionary:(nullable NSDictionary *)dictionary;

/// Reads the persisted configuration (synchronises CFPreferences first).
+ (VortexConfiguration *)loadConfiguration;

+ (id)readValueForKey:(NSString *)key;
+ (void)writeValue:(nullable id)value forKey:(NSString *)key;
+ (void)resetAllValues;
+ (void)postChangeNotification;

/// Engine status as last reported by SpringBoard (may be empty).
+ (NSDictionary<NSString *, id> *)readStatus;
+ (void)writeStatus:(NSDictionary<NSString *, id> *)status;

/// Launch guard counter, stored in the status domain.
+ (NSInteger)consecutiveUnstableLaunches;
+ (void)setConsecutiveUnstableLaunches:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
