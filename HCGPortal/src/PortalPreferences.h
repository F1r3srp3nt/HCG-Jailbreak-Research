//
//  PortalPreferences.h
//  HCG Portal — Hakmi Capital Group
//
//  Preference keys, defaults, validation and engine status. Compiled into BOTH
//  the SpringBoard tweak and the Settings bundle, so the two always agree on
//  what a valid value is (the numeric rules themselves are in PortalCore.c).
//
//  Storage: CFPreferences domain com.hakmicapitalgroup.portal
//           (/var/mobile/Library/Preferences/com.hakmicapitalgroup.portal.plist)
//  Status:  domain com.hakmicapitalgroup.portal.status, written by SpringBoard.
//
//  HCG Portal reads and writes ONLY these two domains. It never writes another
//  product's preferences (HCG Nexus, HCG Animation Center, HCG Halo).
//

#import <Foundation/Foundation.h>

#import "PortalCore.h"

NS_ASSUME_NONNULL_BEGIN

#define PORTAL_BUNDLE_ID "com.hakmicapitalgroup.portal"
#ifndef PORTAL_VERSION
#error "PORTAL_VERSION must come from the Makefile (control Version)"
#endif
#ifndef PORTAL_BUILD_ID
#error "PORTAL_BUILD_ID must come from the Makefile (source commit)"
#endif

/// Launch guard: this many SpringBoard launches in a row that end within
/// PORTAL_STABLE_AFTER_SECONDS while enabled => auto-disabled.
#define PORTAL_MAX_UNSTABLE_LAUNCHES 3
#define PORTAL_STABLE_AFTER_SECONDS 30.0
#define PORTAL_MAX_APPS 6

extern NSString *const PortalPreferencesDomain;
extern NSString *const PortalStatusDomain;
extern NSString *const PortalPreferencesChangedNotification; // Settings -> SpringBoard
extern NSString *const PortalStatusRequestNotification;      // Settings -> SpringBoard: write status now
extern NSString *const PortalStatusUpdatedNotification;      // SpringBoard -> Settings
extern NSString *const PortalKillSwitchPath;                 // touch + respring = HCG Portal does nothing

// Keys
extern NSString *const PortalKeyEnabled;           // BOOL, default NO (master switch)
extern NSString *const PortalKeyPalette;           // "signature" | "aurora" | "solar" | "mono"
extern NSString *const PortalKeyBrightness;        // 0.2 ... 1
extern NSString *const PortalKeySpeed;             // 0.25 ... 2
extern NSString *const PortalKeyIntensity;         // 0 ... 1
extern NSString *const PortalKeySize;              // 96 ... 180 pt
extern NSString *const PortalKeyOffsetX;           // -120 ... 120 pt
extern NSString *const PortalKeyOffsetY;           // -40 ... 240 pt
extern NSString *const PortalKeyUnlockAnimation;   // BOOL, default YES
extern NSString *const PortalKeyLowPower;          // "static" | "economy" | "hide"
extern NSString *const PortalKeyApps;              // array of {id, name} dictionaries, at most 6
extern NSString *const PortalKeyDiagnosticLogging; // BOOL

// Status keys (PortalStatusDomain, one dictionary)
extern NSString *const PortalStatusKeyState;
extern NSString *const PortalStatusKeyDetail;
extern NSString *const PortalStatusKeyVisibility;
extern NSString *const PortalStatusKeyLayout;
extern NSString *const PortalStatusKeyPlan;
extern NSString *const PortalStatusKeyHost;
extern NSString *const PortalStatusKeyScene;
extern NSString *const PortalStatusKeyAccess; // iOS unlock state as Portal last read it, and why
extern NSString *const PortalStatusKeyTouch;  // what happened to touches on Portal's controls
extern NSString *const PortalStatusKeyLauncher;
extern NSString *const PortalStatusKeyCompanions;
extern NSString *const PortalStatusKeyLastAction;
extern NSString *const PortalStatusKeyCounters;
extern NSString *const PortalStatusKeyHooks;
extern NSString *const PortalStatusKeyTweakVersion;
extern NSString *const PortalStatusKeyBuildID;
extern NSString *const PortalStatusKeySystemVersion;
extern NSString *const PortalStatusKeyTimestamp;
extern NSString *const PortalStatusKeyUnstableLaunches;
extern NSString *const PortalStatusKeyPreviousSession; // last step the previous SpringBoard launch recorded
extern NSString *const PortalStatusKeyPhase;           // last step this launch recorded

// Engine states
extern NSString *const PortalEngineStateDisabled;     // "disabled"
extern NSString *const PortalEngineStateWaiting;      // "waiting"
extern NSString *const PortalEngineStateActive;       // "active"
extern NSString *const PortalEngineStateKillSwitch;   // "kill-switch"
extern NSString *const PortalEngineStateIncompatible; // "incompatible"
extern NSString *const PortalEngineStateAutoDisabled; // "auto-disabled"
extern NSString *const PortalEngineStateFault;        // "fault"

/// One chosen app shortcut.
@interface PortalAppShortcut : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *name;
+ (nullable instancetype)shortcutWithDictionary:(id)dictionary;
+ (instancetype)shortcutWithIdentifier:(NSString *)identifier name:(NSString *)name;
- (NSDictionary *)dictionary;
@end

/// A validated snapshot of the preferences.
@interface PortalSettings : NSObject
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) PortalAppearance appearance;
@property (nonatomic, readonly) PortalPlacement placement;
@property (nonatomic, readonly) BOOL unlockAnimation;
@property (nonatomic, readonly) int lowPowerPolicy;
@property (nonatomic, readonly, copy) NSArray<PortalAppShortcut *> *apps;
@property (nonatomic, readonly) BOOL diagnosticLogging;
+ (PortalSettings *)settingsWithDictionary:(NSDictionary *)dictionary;
@end

@interface PortalPreferences : NSObject

+ (PortalSettings *)loadSettings;
+ (nullable id)valueForKey:(NSString *)key;
/// Writes, synchronises and posts PortalPreferencesChangedNotification.
+ (void)setValue:(nullable id)value forKey:(NSString *)key;
/// Removes several keys at once (Reset), then posts one notification.
+ (void)removeKeys:(NSArray<NSString *> *)keys;
+ (void)postChanged;

+ (NSArray<NSString *> *)appearanceKeys;
+ (NSArray<NSString *> *)placementKeys;
+ (NSArray<NSString *> *)validPalettes;
+ (NSArray<NSString *> *)validLowPowerPolicies;

+ (NSDictionary<NSString *, id> *)readStatus;
+ (void)writeStatus:(NSDictionary<NSString *, id> *)status;
/// Crash breadcrumb: the step Portal is about to take or has just taken (bootstrap,
/// installing hooks, attaching to the Lock Screen, …), with the time. Written only on change
/// and synchronised, so it survives a SpringBoard crash (cfprefsd is a separate process).
+ (void)recordPhase:(NSString *)phase;
/// Read once at bootstrap, before the first new breadcrumb: what the previous launch recorded.
+ (NSString *)previousSessionSummary;
+ (NSInteger)consecutiveUnstableLaunches;
+ (void)setConsecutiveUnstableLaunches:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
