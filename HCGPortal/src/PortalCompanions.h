//
//  PortalCompanions.h
//  HCG Portal — Hakmi Capital Group
//
//  Optional companions, found at run time and never required. HCG Portal has
//  no Depends on any of them, links none of them, and never writes their
//  preferences. See docs/INTEGRATIONS.md for every contract.
//
//  HCG Nexus (com.hakmicapitalgroup.hcgnexus)
//    Installed: its Settings bundle or tweak dylib exists under the jailbreak
//    root. Opening its panel needs the PROPOSED interface HCGNexusPortalInterface
//    version 1, which HCG Nexus 0.3.1~beta1 does NOT have (its only interface,
//    HCGNexusBorderInterface v1, is read-only). Until a Nexus build adds it, the
//    Nexus destination says so and does nothing.
//
//  HCG Animation Center (com.hakmicapitalgroup.animationcenter)
//    Installed: HCGAnimationCenterPrefs.bundle and its PreferenceLoader entry.
//    Its only user interface is that Settings page, so the supported route is
//    the Settings app (com.apple.Preferences). Animation Center defines no
//    deep link; Portal does not guess one.
//
//  HCG Halo (com.hakmicapitalgroup.halo)
//    Coordinated edge lighting is OPTIONAL. Portal posts in-process lighting
//    events (PortalLightingEventNotification, version 1) that a future Halo
//    build may observe. No Halo build observes them yet; nothing depends on it.
//
//  Connector / Origin (Devices)
//    No integration exists. Always "Not connected".
//

#import <Foundation/Foundation.h>

#import "PortalCore.h"

NS_ASSUME_NONNULL_BEGIN

// ---- Proposed HCG Nexus open interface (implemented by Nexus, not by Portal) ----
#define PORTAL_NEXUS_INTERFACE_CLASS "HCGNexusPortalInterface"
#define PORTAL_NEXUS_INTERFACE_VERSION 1

// ---- Portal lighting events (in-process, main thread, version 1) ---------------
// object: nil. userInfo: {"event": NSString, "interfaceVersion": @1,
//                         "palette": NSString, "intensity": NSNumber 0...1}
// Events: "expanded", "collapsed", "opened", "unlock", "hidden".
// Carries no user data (no app names, no destinations beyond the four kinds).
FOUNDATION_EXPORT NSNotificationName const PortalLightingEventNotification; // "com.hakmicapitalgroup.portal.lighting-event"
#define PORTAL_LIGHTING_INTERFACE_VERSION 1

typedef void (^PortalNexusOpenCompletion)(BOOL opened, NSString *_Nullable reason);

@interface PortalCompanions : NSObject

/// The jailbreak root ("/var/jb" on rootless), derived from this image's own
/// path, else /var/jb if it exists, else "" (rootful layout).
+ (NSString *)jailbreakRoot;
+ (void)setJailbreakRootForTesting:(nullable NSString *)root;

+ (BOOL)animationCenterInstalled;
+ (BOOL)nexusInstalled;
/// The running Nexus offers HCGNexusPortalInterface v1 (SpringBoard only).
+ (BOOL)nexusOpenInterfaceAvailable;
/// Asks Nexus to open its panel. Only after authentication succeeded.
+ (void)openNexusPanelWithCompletion:(PortalNexusOpenCompletion)completion;

/// One-line summary for Settings and the status report. With `runtime` NO, only
/// installed files are checked: no companion code is called (used while Portal is
/// inactive, including during SpringBoard's launch).
+ (NSString *)summaryIncludingRuntime:(BOOL)runtime;
+ (NSString *)summary; // = summaryIncludingRuntime:YES

/// User-facing text for an unavailable destination.
+ (NSString *)messageForDestination:(int)destination availability:(PortalAvailability)availability;
+ (NSString *)titleForDestination:(int)destination;

+ (void)postLightingEvent:(NSString *)event palette:(int)palette intensity:(double)intensity;

@end

NS_ASSUME_NONNULL_END
