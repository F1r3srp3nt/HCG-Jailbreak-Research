//
//  HaloNexusDefinition.h
//  HCG Halo — Hakmi Capital Group
//
//  Loads and validates the border definition that HCG NEXUS installs:
//    <jbroot>/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist
//  (see docs/NEXUS.md). Halo never bundles, copies or downloads this file.
//
//  The file is declarative data only. Schema 1 is strict: every key, type and
//  range must be exactly as specified and unknown keys are rejected — the same
//  rules as HCG Nexus's scripts/check_halo_border.py. Anything else (missing,
//  unreadable, too large, malformed, other version) yields an error and the
//  Nexus border stays off with that explanation. The definition describes the
//  integration; it never says where the panel is: live geometry comes from the
//  running Nexus panel.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define HALO_NEXUS_SCHEMA_VERSION 1
#define HALO_NEXUS_INTERFACE_VERSION 1
#define HALO_NEXUS_MIN_VERSION "0.3.0~beta1"

extern NSString *const HaloNexusSchemaIdentifier;     // com.hakmicapitalgroup.hcgnexus.halo-border
extern NSString *const HaloNexusInterfaceClassName;   // HCGNexusBorderInterface
extern NSString *const HaloNexusPrefsBundleName;      // HCGNexusPrefs.bundle
extern NSString *const HaloNexusDefinitionFileName;   // HaloBorder.plist

@interface HaloNexusDefinition : NSObject

@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *nexusVersion;
@property (nonatomic, readonly) double cornerRadius;
@property (nonatomic, readonly) BOOL continuousCorners;
@property (nonatomic, readonly) double outset;         // gap between the panel edge and the light
@property (nonatomic, readonly) double glowMargin;     // room around the panel for the glow
@property (nonatomic, readonly) BOOL clipInterior;     // never draw over the panel's content
@property (nonatomic, readonly, copy) NSSet<NSString *> *capabilities;
@property (nonatomic, readonly, copy, nullable) NSString *defaultPreset;

- (BOOL)hasCapability:(NSString *)capability;

/// Reads and validates the file at `path`. Returns nil and a user-readable
/// reason in *error when it is missing or not a valid schema-1 definition.
+ (nullable instancetype)definitionAtPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error;

/// Validates already-parsed data (tests). `path` is informational.
+ (nullable instancetype)definitionWithData:(NSData *)data path:(NSString *)path error:(NSString *_Nullable *_Nullable)error;

/// Where an installed Nexus keeps the file, found next to HCG Halo's own
/// Settings bundle (both live in <jbroot>/Library/PreferenceBundles). Use in
/// the Settings app, where the Nexus tweak is not loaded.
+ (nullable NSString *)installedPathNextToBundle:(NSBundle *)bundle;

/// Debian version comparison (enough for X.Y.Z with ~/+/- suffixes): -1, 0, 1.
+ (NSInteger)compareVersion:(NSString *)a to:(NSString *)b;

@end

NS_ASSUME_NONNULL_END
