//
//  HaloPreferences.h
//  HCG Halo — Hakmi Capital Group
//
//  Preference keys, defaults, validation, presets and engine status.
//  Compiled into BOTH the SpringBoard tweak and the Settings bundle, so the
//  two always agree on what a valid value is.
//
//  Storage: CFPreferences, domain com.hakmicapitalgroup.halo
//    (/var/mobile/Library/Preferences/com.hakmicapitalgroup.halo.plist).
//  Status:  domain com.hakmicapitalgroup.halo.status, written by SpringBoard.
//  Change notification: Darwin notification HaloPreferencesChangedNotification.
//

#import <Foundation/Foundation.h>

#import "HaloConfig.h"
#import "HaloProfiles.h"

NS_ASSUME_NONNULL_BEGIN

#define HALO_BUNDLE_ID "com.hakmicapitalgroup.halo"
#ifndef HALO_VERSION
#error "HALO_VERSION must come from the Makefile (control Version)"
#endif
#ifndef HALO_BUILD_ID
#error "HALO_BUILD_ID must come from the Makefile (source commit)"
#endif

extern NSString *const HaloPreferencesDomain;
extern NSString *const HaloStatusDomain;
extern NSString *const HaloPreferencesChangedNotification; // Settings -> SpringBoard
extern NSString *const HaloStatusRequestNotification;      // Settings -> SpringBoard: please write status now
extern NSString *const HaloStatusUpdatedNotification;      // SpringBoard -> Settings: status written
extern NSString *const HaloKillSwitchPath;                 // touch + respring = HCG Halo does nothing

// Keys
extern NSString *const HaloKeyEnabled;
extern NSString *const HaloKeyMode;
extern NSString *const HaloKeyColourStyle;
extern NSString *const HaloKeyColours;
extern NSString *const HaloKeyBrightness;
extern NSString *const HaloKeyThickness;
extern NSString *const HaloKeyGlow;
extern NSString *const HaloKeyInset;
extern NSString *const HaloKeySpeed;
extern NSString *const HaloKeyDirection;
extern NSString *const HaloKeyColourRepeat;
extern NSString *const HaloKeySegments;
extern NSString *const HaloKeySegmentLength;
extern NSString *const HaloKeyLowPower;
extern NSString *const HaloKeyProfile;
extern NSString *const HaloKeyCutoutMode;
extern NSString *const HaloKeyCalCornerRadius;
extern NSString *const HaloKeyCalNotchWidth;
extern NSString *const HaloKeyCalNotchHeight;
extern NSString *const HaloKeyCalNotchOffset;
extern NSString *const HaloKeyPresets;
extern NSString *const HaloKeyPulse;                 // soft pulse depth (appearance)
extern NSString *const HaloKeyTarget;                // "screen" | "nexus" | "both"
extern NSString *const HaloKeyNexusMatchScreen;      // Nexus border uses the screen-edge appearance
extern NSString *const HaloKeyNexusAppearance;       // dictionary of appearance keys for the Nexus border
extern NSString *const HaloKeyNexusOpenTrace;        // light trace when the panel opens
extern NSString *const HaloKeyNexusCloseFade;        // fade with the panel (off: disappear at once)
extern NSString *const HaloKeyNexusWorkspacePulse;   // small pulse on workspace changes
extern NSString *const HaloKeyDiagnosticLogging;
extern NSString *const HaloKeyShowOn;                // screen edge: "home" | "app" | "always" | "exceptLock" | "exceptScreenOff"
extern NSString *const HaloKeyShowOnApp;             // Selected App Only: bundle identifier ("" = none chosen)
extern NSString *const HaloKeyShowOnAppName;         // its display name when chosen (shown if the app is removed)

// Status keys (HaloStatusDomain)
extern NSString *const HaloStatusKeyState;       // see HaloEngineState* below
extern NSString *const HaloStatusKeyDetail;
extern NSString *const HaloStatusKeyRendering;   // human-readable rendering state
extern NSString *const HaloStatusKeyHost;        // how the Home Screen window was found
extern NSString *const HaloStatusKeyFrontDetection;
extern NSString *const HaloStatusKeyScreen;      // e.g. "414 × 896 pt @3x"
extern NSString *const HaloStatusKeyProfileMatch;
extern NSString *const HaloStatusKeyTweakVersion;
extern NSString *const HaloStatusKeyBuildID;
extern NSString *const HaloStatusKeySystemVersion;
extern NSString *const HaloStatusKeyTimestamp;
extern NSString *const HaloStatusKeyUnstableLaunches;
extern NSString *const HaloStatusKeyNexusState;      // "attached" | "waiting" | "off" | "unavailable"
extern NSString *const HaloStatusKeyNexusDetail;     // human-readable reason
extern NSString *const HaloStatusKeyNexusRendering;  // what the panel border is doing now
extern NSString *const HaloStatusKeyShowOn;          // the policy SpringBoard applied
extern NSString *const HaloStatusKeyFrontApp;        // bundle identifier of the app in front ("" = none / unknown)
extern NSString *const HaloStatusKeySurfaceHost;     // "Home Screen window" | "HCG Halo overlay window"
extern NSString *const HaloStatusKeyScreenFit;       // halo_screen_fit_id()

extern NSString *const HaloEngineStateActive;        // overlay attached and managed
extern NSString *const HaloEngineStateDisabled;      // loaded, master switch off
extern NSString *const HaloEngineStateWaiting;       // enabled, looking for the Home Screen window
extern NSString *const HaloEngineStateIncompatible;  // required SpringBoard interface missing; nothing changed
extern NSString *const HaloEngineStateKillSwitch;
extern NSString *const HaloEngineStateAutoDisabled;  // launch guard tripped
extern NSString *const HaloEngineStateFault;         // exception caught; overlay removed

extern NSString *const HaloPresetKeyID;
extern NSString *const HaloPresetKeyName;
extern NSString *const HaloPresetKeyAppearance;
extern NSString *const HaloBuiltInPresetPrefix; // "builtin."

#define HALO_MAX_PRESETS 50
#define HALO_PRESET_NAME_MAX 40

typedef NS_ENUM(NSInteger, HaloTarget) {
    HaloTargetScreen = 0, // screen edge only (default; the 0.1.0~beta1 behaviour)
    HaloTargetNexus = 1,  // HCG Nexus panel only
    HaloTargetBoth = 2,
};

/// Immutable, validated snapshot of every setting.
@interface HaloSettings : NSObject
@property (nonatomic, readonly) HaloTarget target;
@property (nonatomic, readonly) BOOL targetsScreen;
@property (nonatomic, readonly) BOOL targetsNexus;
@property (nonatomic, readonly) BOOL nexusMatchScreen;
/// The Nexus border's own appearance (ignored while nexusMatchScreen is on).
@property (nonatomic, readonly) HaloAppearance nexusAppearance;
/// What the Nexus border actually uses.
@property (nonatomic, readonly) HaloAppearance effectiveNexusAppearance;
@property (nonatomic, readonly) BOOL nexusOpenTrace;
@property (nonatomic, readonly) BOOL nexusCloseFade;
@property (nonatomic, readonly) BOOL nexusWorkspacePulse;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) HaloAppearance appearance;
@property (nonatomic, readonly) HaloLowPowerPolicy lowPowerPolicy;
@property (nonatomic, readonly, copy) NSString *profileIdentifier;
@property (nonatomic, readonly) HaloCalibration calibration;
@property (nonatomic, readonly) HaloCutoutMode cutoutMode;
@property (nonatomic, readonly) BOOL diagnosticLogging;
/// Where the screen-edge border is shown. Never affects the HCG Nexus panel border.
@property (nonatomic, readonly) HaloShowOn showOn;
/// Selected App Only: the chosen bundle identifier, or "" if none.
@property (nonatomic, readonly, copy) NSString *showOnApp;
@property (nonatomic, readonly, copy) NSString *showOnAppName;
@property (nonatomic, readonly, nullable) const HaloProfile *profile;
/// Profile geometry plus calibration; width 0 if no implemented profile.
@property (nonatomic, readonly) HaloDisplayGeometry geometry;
@end

@interface HaloPreferences : NSObject

+ (NSDictionary<NSString *, id> *)defaultValues;
+ (NSArray<NSString *> *)allKeys;
/// The keys a preset captures and "Reset Appearance" resets.
+ (NSArray<NSString *> *)appearanceKeys;
/// The keys "Reset Calibration" resets.
+ (NSArray<NSString *> *)calibrationKeys;
/// The keys "Reset Nexus Lighting" resets (not the target, not the screen edge).
+ (NSArray<NSString *> *)nexusLightingKeys;
+ (NSArray<NSString *> *)validTargets;
+ (NSArray<NSString *> *)validShowOn;
/// A bundle identifier as stored for Selected App Only ("" if not one).
+ (NSString *)sanitizedBundleIdentifier:(nullable id)value;
/// Default look of the Nexus border: the "Nexus Signature" preset.
+ (HaloAppearance)nexusSignatureAppearance;

+ (NSArray<NSString *> *)validModes;
+ (NSArray<NSString *> *)validColourStyles;
+ (NSArray<NSString *> *)validDirections;
+ (NSArray<NSString *> *)validLowPowerPolicies;
+ (NSArray<NSString *> *)validCutoutModes;
/// Implemented (selectable) profile identifiers. Never contains "automatic".
+ (NSArray<NSString *> *)validProfiles;

/// `value` if valid for `key` (numbers clamped, colours normalised), else the default.
+ (id)sanitizedValue:(nullable id)value forKey:(NSString *)key;

+ (HaloSettings *)settingsFromDictionary:(nullable NSDictionary *)dictionary;
+ (HaloSettings *)loadSettings;

+ (HaloAppearance)appearanceFromDictionary:(nullable NSDictionary *)dictionary;
+ (NSDictionary<NSString *, id> *)dictionaryFromAppearance:(HaloAppearance)appearance;

+ (id)readValueForKey:(NSString *)key;
+ (void)writeValue:(nullable id)value forKey:(NSString *)key;
/// Writes several keys with one synchronise; NSNull removes a key.
+ (void)writeValues:(NSDictionary<NSString *, id> *)values;
+ (void)postChangeNotification;

+ (void)resetAppearance;
+ (void)resetCalibration;
+ (void)resetNexusLighting;

// Presets ---------------------------------------------------------------
+ (NSArray<NSDictionary *> *)builtInPresets;
+ (NSArray<NSDictionary *> *)userPresets;
+ (nullable NSDictionary *)presetWithIdentifier:(NSString *)identifier;
+ (BOOL)isBuiltInPreset:(NSString *)identifier;
/// Trimmed, length-limited, unique (case-insensitive) among user presets; nil if empty.
+ (nullable NSString *)uniquePresetName:(NSString *)proposed excluding:(nullable NSString *)identifier;
/// Saves the current appearance as a new user preset. Returns its identifier, or nil (empty name / full).
+ (nullable NSString *)saveCurrentAppearanceAsPresetNamed:(NSString *)name;
+ (BOOL)renamePreset:(NSString *)identifier to:(NSString *)name;
+ (nullable NSString *)duplicatePreset:(NSString *)identifier;
+ (BOOL)deletePreset:(NSString *)identifier;
/// Writes the preset's appearance keys. Nothing else changes.
+ (BOOL)applyPreset:(NSString *)identifier;
/// Applies a preset to the Nexus border only (and stops matching the screen edge).
+ (BOOL)applyPresetToNexus:(NSString *)identifier;
/// Identifier of the preset equal to the Nexus border's own appearance, or nil.
+ (nullable NSString *)matchingNexusPresetIdentifier;
/// Writes one appearance key of the Nexus border (validated like the screen-edge key).
+ (void)writeNexusAppearanceValue:(nullable id)value forKey:(NSString *)key;
/// Identifier of the preset whose appearance equals the current one, or nil.
+ (nullable NSString *)matchingPresetIdentifier;

// Status ----------------------------------------------------------------
+ (NSDictionary<NSString *, id> *)readStatus;
+ (void)writeStatus:(NSDictionary<NSString *, id> *)status;
+ (NSInteger)consecutiveUnstableLaunches;
+ (void)setConsecutiveUnstableLaunches:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
