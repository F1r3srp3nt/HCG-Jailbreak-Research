//
//  PortalCompanions.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalCompanions.h"

#import <objc/message.h>
#import <objc/runtime.h>

#include <dlfcn.h>

NSNotificationName const PortalLightingEventNotification = @"com.hakmicapitalgroup.portal.lighting-event";

static NSString *gRootOverride;

@implementation PortalCompanions

+ (void)setJailbreakRootForTesting:(NSString *)root {
    gRootOverride = [root copy];
}

+ (NSString *)jailbreakRoot {
    if (gRootOverride) return gRootOverride;
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        NSString *image = nil;
        if (dladdr((const void *)&PortalLightingEventNotification, &info) && info.dli_fname)
            image = [NSString stringWithUTF8String:info.dli_fname];
        for (NSString *marker in @[ @"/Library/MobileSubstrate/", @"/usr/lib/TweakInject/", @"/Library/PreferenceBundles/" ]) {
            NSRange r = image ? [image rangeOfString:marker] : NSMakeRange(NSNotFound, 0);
            if (r.location != NSNotFound) {
                root = [image substringToIndex:r.location];
                break;
            }
        }
        if (!root) root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    });
    return root;
}

static BOOL Exists(NSString *relative) {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[PortalCompanions jailbreakRoot] stringByAppendingString:relative]];
}

+ (BOOL)animationCenterInstalled {
    return Exists(@"/Library/PreferenceBundles/HCGAnimationCenterPrefs.bundle/Info.plist") &&
           Exists(@"/Library/PreferenceLoader/Preferences/HCGAnimationCenterPrefs.plist");
}

+ (BOOL)nexusInstalled {
    return Exists(@"/Library/MobileSubstrate/DynamicLibraries/HCGNexus.dylib") ||
           Exists(@"/Library/PreferenceBundles/HCGNexusPrefs.bundle/Info.plist") ||
           NSClassFromString(@"HCGNexusBorderInterface") != nil;
}

static id NexusActiveInterface(void) {
    Class cls = NSClassFromString(@PORTAL_NEXUS_INTERFACE_CLASS);
    if (!cls) return nil;
    SEL versionSel = NSSelectorFromString(@"interfaceVersion");
    SEL activeSel = NSSelectorFromString(@"activeInterface");
    if (![cls respondsToSelector:versionSel] || ![cls respondsToSelector:activeSel]) return nil;
    NSInteger version = ((NSInteger(*)(id, SEL))objc_msgSend)(cls, versionSel);
    if (version != PORTAL_NEXUS_INTERFACE_VERSION) return nil;
    id active = ((id(*)(id, SEL))objc_msgSend)(cls, activeSel);
    if (!active) return nil;
    if (![active respondsToSelector:NSSelectorFromString(@"canOpenPanel")]) return nil;
    if (![active respondsToSelector:NSSelectorFromString(@"openPanelFromSource:completion:")]) return nil;
    return active;
}

+ (BOOL)nexusOpenInterfaceAvailable {
    id active = NexusActiveInterface();
    if (!active) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(active, NSSelectorFromString(@"canOpenPanel"));
}

+ (void)openNexusPanelWithCompletion:(PortalNexusOpenCompletion)completion {
    id active = NexusActiveInterface();
    if (!active) {
        completion(NO, @"HCG Nexus has no Portal open interface.");
        return;
    }
    __block BOOL finished = NO;
    void (^once)(BOOL, NSString *) = ^(BOOL opened, NSString *reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) return;
            finished = YES;
            completion(opened, reason);
        });
    };
    ((void (*)(id, SEL, NSString *, id))objc_msgSend)(active, NSSelectorFromString(@"openPanelFromSource:completion:"),
                                                      @"hcg-portal", ^(BOOL opened, NSString *reason) {
                                                          once(opened, [reason isKindOfClass:[NSString class]] ? reason : nil);
                                                      });
    // Nexus is asked to answer; if it never does, report rather than wait forever.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        once(NO, @"HCG Nexus did not answer.");
    });
}

+ (NSString *)summary {
    NSString *nexus = ![self nexusInstalled]               ? @"not installed"
                      : [self nexusOpenInterfaceAvailable] ? @"installed, open interface v1"
                                                           : @"installed, no open interface";
    return [NSString stringWithFormat:@"Nexus: %@ · Animation Center: %@ · Devices: not connected", nexus,
                                      [self animationCenterInstalled] ? @"installed" : @"not installed"];
}

+ (NSString *)titleForDestination:(int)destination {
    switch (destination) {
        case PORTAL_DEST_NEXUS: return @"Nexus";
        case PORTAL_DEST_BACKGROUNDS: return @"Backgrounds";
        case PORTAL_DEST_DEVICES: return @"Devices";
        case PORTAL_DEST_APPS: return @"HCG Apps";
        default: return @"App";
    }
}

+ (NSString *)messageForDestination:(int)destination availability:(PortalAvailability)availability {
    switch (availability) {
        case PORTAL_AVAIL_AVAILABLE:
            return @"";
        case PORTAL_AVAIL_NOT_INSTALLED:
            if (destination == PORTAL_DEST_NEXUS) return @"HCG Nexus isn't installed.";
            if (destination == PORTAL_DEST_BACKGROUNDS) return @"HCG Animation Center isn't installed.";
            return @"Not installed.";
        case PORTAL_AVAIL_NEEDS_INTERFACE:
            return @"This HCG Nexus can't be opened from Portal yet. It needs a Nexus update.";
        case PORTAL_AVAIL_NOT_CONNECTED:
            return @"Not connected. Connector and Origin aren't available yet.";
        case PORTAL_AVAIL_NO_APPS:
            return @"No apps chosen. Add them in Settings › HCG Portal › HCG Apps.";
        case PORTAL_AVAIL_LAUNCHER_UNAVAILABLE:
            return @"This iOS version doesn't offer the app launcher Portal uses.";
        case PORTAL_AVAIL_AUTH_UNAVAILABLE:
            return @"Unlock your iPhone first: Portal can't request authentication on this iOS version.";
    }
    return @"Unavailable.";
}

+ (void)postLightingEvent:(NSString *)event palette:(int)palette intensity:(double)intensity {
    [[NSNotificationCenter defaultCenter] postNotificationName:PortalLightingEventNotification
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : event,
                                                          @"interfaceVersion" : @(PORTAL_LIGHTING_INTERFACE_VERSION),
                                                          @"palette" : @(portal_palette_id(palette)),
                                                          @"intensity" : @(intensity),
                                                      }];
}

@end
