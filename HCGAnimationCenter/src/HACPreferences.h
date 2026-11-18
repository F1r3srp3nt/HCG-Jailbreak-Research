//
//  HACPreferences.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Preference keys, defaults, validation and engine status. Compiled into
//  BOTH the SpringBoard tweak and the Settings bundle, so the two always agree
//  on what a valid value is.
//
//  Storage:  CFPreferences domain com.hakmicapitalgroup.animationcenter
//            (/var/mobile/Library/Preferences/com.hakmicapitalgroup.animationcenter.plist)
//            The assigned backgrounds are stored there as HCG background
//            preset documents (format version 1, dictionaries).
//  Media:    /var/mobile/Library/HCGAnimationCenter/Media (written by Settings)
//  Status:   domain com.hakmicapitalgroup.animationcenter.status, written by SpringBoard.
//

#import <Foundation/Foundation.h>

#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

#define HAC_BUNDLE_ID "com.hakmicapitalgroup.animationcenter"
#ifndef HAC_VERSION
#error "HAC_VERSION must come from the Makefile (control Version)"
#endif
#ifndef HAC_BUILD_ID
#error "HAC_BUILD_ID must come from the Makefile (source commit)"
#endif

/// Launch guard: this many SpringBoard launches in a row that end within
/// HAC_STABLE_AFTER_SECONDS while enabled => auto-disabled.
#define HAC_MAX_UNSTABLE_LAUNCHES 3
#define HAC_STABLE_AFTER_SECONDS 30.0

extern NSString *const HACPreferencesDomain;
extern NSString *const HACStatusDomain;
extern NSString *const HACPreferencesChangedNotification; // Settings -> SpringBoard
extern NSString *const HACStatusRequestNotification;      // Settings -> SpringBoard: write status now
extern NSString *const HACStatusUpdatedNotification;      // SpringBoard -> Settings
extern NSString *const HACProbeRequestNotification;       // Settings -> SpringBoard: write a hierarchy probe
extern NSString *const HACKillSwitchPath;                 // touch + respring = HCG Animation Center does nothing

// Keys
extern NSString *const HACKeyEnabled;           // BOOL, default NO (master switch)
extern NSString *const HACKeyHomeEnabled;       // BOOL, default YES
extern NSString *const HACKeyLockEnabled;       // BOOL, default NO (Lock Screen is experimental)
extern NSString *const HACKeyHomePreset;        // preset dictionary, or absent
extern NSString *const HACKeyLockPreset;        // preset dictionary, or absent
extern NSString *const HACKeyLockSource;        // "same" (Home's background) | "own"
extern NSString *const HACKeyReduceMotion;      // "still" | "play"
extern NSString *const HACKeyLowPower;          // "still" | "play" | "system"
extern NSString *const HACKeyHomePlacement;     // "automatic" | "homeWindow" | "wallpaper"
extern NSString *const HACKeyLockPlacement;     // "automatic" | "wallpaper" | "coverSheet"
extern NSString *const HACKeyDiagnosticLogging; // BOOL

// Status keys (HACStatusDomain, one dictionary)
extern NSString *const HACStatusKeyState;        // HACEngineState*
extern NSString *const HACStatusKeyDetail;
extern NSString *const HACStatusKeyHome;         // dictionary: rendering, host, placement, preset
extern NSString *const HACStatusKeyLock;         // dictionary: rendering, host, placement, preset
extern NSString *const HACStatusKeyEnvironment;  // interfaces found in this SpringBoard
extern NSString *const HACStatusKeyFrontDetection;
extern NSString *const HACStatusKeyProbePath;    // last hierarchy probe written
extern NSString *const HACStatusKeyTweakVersion;
extern NSString *const HACStatusKeyBuildID;
extern NSString *const HACStatusKeySystemVersion;
extern NSString *const HACStatusKeyTimestamp;
extern NSString *const HACStatusKeyUnstableLaunches;
extern NSString *const HACSurfaceStatusKeyRendering;
extern NSString *const HACSurfaceStatusKeyHost;
extern NSString *const HACSurfaceStatusKeyPlacement;
extern NSString *const HACSurfaceStatusKeyPreset;

// Engine states
extern NSString *const HACEngineStateDisabled;     // "disabled"
extern NSString *const HACEngineStateWaiting;      // "waiting"
extern NSString *const HACEngineStateActive;       // "active"
extern NSString *const HACEngineStateKillSwitch;   // "kill-switch"
extern NSString *const HACEngineStateIncompatible; // "incompatible"
extern NSString *const HACEngineStateAutoDisabled; // "auto-disabled"
extern NSString *const HACEngineStateFault;        // "fault"

/// A validated snapshot of the preferences.
@interface HACSettings : NSObject
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL homeEnabled;
@property (nonatomic, readonly) BOOL lockEnabled;
@property (nonatomic, readonly) BOOL lockSameAsHome;
@property (nonatomic, readonly, nullable) HCGBackgroundPreset *homePreset;
/// The Lock Screen's effective preset (Home's when "same").
@property (nonatomic, readonly, nullable) HCGBackgroundPreset *lockPreset;
/// Why a stored preset was rejected ("" if none / fine).
@property (nonatomic, readonly, copy) NSString *homePresetProblem;
@property (nonatomic, readonly, copy) NSString *lockPresetProblem;
@property (nonatomic, readonly) HACReduceMotionPolicy reduceMotionPolicy;
@property (nonatomic, readonly) HACLowPowerPolicy lowPowerPolicy;
@property (nonatomic, readonly, copy) NSString *homePlacement;
@property (nonatomic, readonly, copy) NSString *lockPlacement;
@property (nonatomic, readonly) BOOL diagnosticLogging;
- (nullable HCGBackgroundPreset *)presetForSurface:(HACSurface)surface;
- (BOOL)surfaceEnabled:(HACSurface)surface;
- (NSString *)placementForSurface:(HACSurface)surface;
@end

@interface HACPreferences : NSObject

+ (HACSettings *)loadSettings;
+ (nullable id)valueForKey:(NSString *)key;
/// Writes, synchronises and posts HACPreferencesChangedNotification.
+ (void)setValue:(nullable id)value forKey:(NSString *)key;
+ (void)postChanged;

+ (NSArray<NSString *> *)validHomePlacements;
+ (NSArray<NSString *> *)validLockPlacements;

/// The media store (Settings writes, SpringBoard reads). Tests may redirect it.
+ (NSString *)storeRoot;
+ (NSURL *)mediaFolder;
+ (NSURL *)diagnosticsFolder;
+ (void)setStoreRootForTesting:(nullable NSString *)root;

+ (NSDictionary<NSString *, id> *)readStatus;
+ (void)writeStatus:(NSDictionary<NSString *, id> *)status;
+ (NSInteger)consecutiveUnstableLaunches;
+ (void)setConsecutiveUnstableLaunches:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
