//
//  HaloNexusLink.h
//  HCG Halo — Hakmi Capital Group
//
//  Connects Halo to the HCG Nexus panel running in the same process
//  (SpringBoard), through Nexus's versioned border interface (see
//  docs/NEXUS.md):
//
//    1. NSClassFromString(@"HCGNexusBorderInterface"), +interfaceVersion == 1.
//       No link-time dependency: without Nexus the class simply is not there.
//    2. The border definition INSTALLED by Nexus (+borderDefinitionPath, i.e.
//       <jbroot>/Library/PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist),
//       validated by HaloNexusDefinition. Its nexusVersion must equal the
//       running Nexus's version; otherwise Nexus was updated since the last
//       respring and the border waits for one.
//    3. +activeInterface.borderHostView: the live panel. The border view is
//       added there, so its position always comes from the running panel.
//    4. In-process lifecycle notifications, accepted only from the active
//       interface and only with a well-formed userInfo.
//
//  Anything missing, malformed or incompatible leaves the Nexus border off
//  with a reason ("Requires compatible HCG Nexus: …"); the screen-edge border
//  is unaffected. Main thread only.
//

#import <UIKit/UIKit.h>

#import "HaloConfig.h"

NS_ASSUME_NONNULL_BEGIN

@class HaloSettings, HaloNexusDefinition, HaloPanelBorderView;

extern NSString *const HaloNexusLinkStateOff;          // target excludes the panel, or Halo is disabled
extern NSString *const HaloNexusLinkStateUnavailable;  // Nexus missing / incompatible / outdated definition
extern NSString *const HaloNexusLinkStateWaiting;      // compatible Nexus, panel not built yet
extern NSString *const HaloNexusLinkStateAttached;     // border installed in the live panel

/// Name of Nexus's in-process notification (must match HCGNexusBorderEventNotification).
extern NSString *const HaloNexusBorderEventNotification;

@interface HaloNexusLink : NSObject

@property (nonatomic, readonly, copy) NSString *state;
@property (nonatomic, readonly, copy) NSString *detail;
/// What the panel border is doing right now (Settings diagnostics).
@property (nonatomic, readonly, copy) NSString *rendering;
@property (nonatomic, readonly, nullable) HaloNexusDefinition *definition;
@property (nonatomic, readonly, nullable) HaloPanelBorderView *borderView;

/// Fallback location of the definition derived from where HCG Halo itself
/// was loaded (used only if the running Nexus cannot report it).
@property (nonatomic, copy, nullable) NSString *fallbackDefinitionPath;

/// Called after every state change (to republish status).
@property (nonatomic, copy, nullable) void (^stateDidChange)(HaloNexusLink *link);

/// enabled: Halo is enabled, not faulted, and the target includes the panel.
/// The render plan is derived from the panel's own mode with Reduce Motion,
/// Low Power Mode and the Low Power policy, as for the screen edge.
/// screenOn: false freezes and hides the border.
- (void)applySettings:(HaloSettings *)settings
              enabled:(BOOL)enabled
         reduceMotion:(BOOL)reduceMotion
         lowPowerMode:(BOOL)lowPowerMode
   reduceTransparency:(BOOL)reduceTransparency
             screenOn:(BOOL)screenOn;

/// Screen lit (YES) or off (NO): hides and freezes the border while off.
/// Cheap; does not re-read the definition.
- (void)setScreenOn:(BOOL)screenOn;

/// Removes the border and stops observing. -applySettings: starts again.
- (void)stop;

/// Validates a Nexus event notification. Returns the event name, or nil (and
/// a reason) when it must be ignored. Exposed for tests.
+ (nullable NSString *)validatedEventFromNotification:(NSNotification *)note
                                     expectedInterface:(nullable id)expected
                                                reason:(NSString *_Nullable *_Nullable)reason;

/// Where HCG Halo's own image implies the definition is installed, or nil.
+ (nullable NSString *)definitionPathFromImagePath:(NSString *)imagePath;

@end

NS_ASSUME_NONNULL_END
