//
//  HaloNexusLink.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloNexusLink.h"
#import "HaloLog.h"
#import "HaloNexusDefinition.h"
#import "HaloPanelBorderView.h"
#import "HaloPreferences.h"

#include <math.h>

NSString *const HaloNexusLinkStateOff = @"off";
NSString *const HaloNexusLinkStateUnavailable = @"unavailable";
NSString *const HaloNexusLinkStateWaiting = @"waiting";
NSString *const HaloNexusLinkStateAttached = @"attached";

NSString *const HaloNexusBorderEventNotification = @"com.hakmicapitalgroup.hcgnexus.border-event";

static NSString *const kEventInstalled = @"installed";
static NSString *const kEventWillOpen = @"will-open";
static NSString *const kEventDidOpen = @"did-open";
static NSString *const kEventWillClose = @"will-close";
static NSString *const kEventDidClose = @"did-close";
static NSString *const kEventGeometry = @"geometry";
static NSString *const kEventWorkspace = @"workspace-changed";
static NSString *const kEventRemoved = @"removed";

static NSString *const kRequires = @"Requires compatible HCG Nexus";

// The subset of HCGNexusBorderInterface (version 1) that Halo uses. Declared
// here only for the compiler; every selector is checked before it is sent.
@protocol HaloNexusBorderInterfaceV1 <NSObject>
+ (NSInteger)interfaceVersion;
+ (nullable id)activeInterface;
+ (nullable NSString *)borderDefinitionPath;
- (NSString *)nexusVersion;
- (nullable UIView *)borderHostView;
- (CGFloat)panelCornerRadius;
- (NSString *)panelState;
- (NSTimeInterval)transitionDuration;
- (BOOL)reducedMotionTransition;
@end

@implementation HaloNexusLink {
    HaloSettings *_settings;
    BOOL _enabled;
    BOOL _reduceMotion;
    BOOL _lowPower;
    BOOL _reduceTransparency;
    BOOL _screenOn;
    BOOL _panelShown;     // Nexus says the panel is opening, open or closing
    BOOL _closing;
    id _observer;
    __weak id _interface;  // the Nexus interface the border is attached to
    HaloNexusDefinition *_definition;
    HaloPanelBorderView *_borderView;
    NSString *_state;
    NSString *_detail;
    NSString *_rendering;
    NSDate *_definitionDate;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = HaloNexusLinkStateOff;
        _detail = @"";
        _rendering = @"Not drawing";
        _screenOn = YES;
    }
    return self;
}

- (void)dealloc {
    if (_observer) [[NSNotificationCenter defaultCenter] removeObserver:_observer];
    [_borderView teardown];
}

- (NSString *)state { return _state; }
- (NSString *)detail { return _detail; }
- (NSString *)rendering { return _rendering; }
- (HaloNexusDefinition *)definition { return _definition; }
- (HaloPanelBorderView *)borderView { return _borderView; }

#pragma mark Public

- (void)applySettings:(HaloSettings *)settings
              enabled:(BOOL)enabled
         reduceMotion:(BOOL)reduceMotion
         lowPowerMode:(BOOL)lowPowerMode
   reduceTransparency:(BOOL)reduceTransparency
             screenOn:(BOOL)screenOn {
    _settings = settings;
    _enabled = enabled;
    _reduceMotion = reduceMotion;
    _lowPower = lowPowerMode;
    _reduceTransparency = reduceTransparency;
    _screenOn = screenOn;
    if (!enabled) {
        [self detach];
        [self stopObserving];
        [self setState:HaloNexusLinkStateOff detail:@""];
        return;
    }
    [self startObserving];
    [self connect];
}

- (void)setScreenOn:(BOOL)screenOn {
    if (_screenOn == screenOn) return;
    _screenOn = screenOn;
    if (!screenOn) [_borderView cancelOpeningTrace];
    [self updateActivity];
}

- (void)stop {
    [self detach];
    [self stopObserving];
    [self setState:HaloNexusLinkStateOff detail:@""];
}

#pragma mark Discovery

- (Class)interfaceClass {
    Class cls = NSClassFromString(HaloNexusInterfaceClassName);
    if (!cls) return Nil;
    for (NSString *name in @[ @"interfaceVersion", @"activeInterface", @"borderDefinitionPath" ]) {
        if (![cls respondsToSelector:NSSelectorFromString(name)]) return Nil;
    }
    return cls;
}

static BOOL HaloInterfaceUsable(id interface) {
    for (NSString *name in @[ @"nexusVersion", @"borderHostView", @"panelCornerRadius", @"panelState", @"transitionDuration",
                              @"reducedMotionTransition" ]) {
        if (![interface respondsToSelector:NSSelectorFromString(name)]) return NO;
    }
    return YES;
}

/// (Re)establishes the attachment: re-reads and re-validates the installed
/// definition every time, so an updated Nexus is picked up safely.
- (void)connect {
    @try {
        Class cls = [self interfaceClass];
        if (!cls) {
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: HCG Nexus " HALO_NEXUS_MIN_VERSION
                                                      @" or later is not installed or not enabled in SpringBoard. The "
                                                      @"screen-edge border is unaffected.",
                                                      kRequires]];
            return;
        }
        NSInteger version = [(Class<HaloNexusBorderInterfaceV1>)cls interfaceVersion];
        if (version != HALO_NEXUS_INTERFACE_VERSION) {
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: the installed HCG Nexus offers border interface %ld; this HCG "
                                                      @"Halo supports version %d. Update HCG Halo or HCG Nexus.",
                                                      kRequires, (long)version, HALO_NEXUS_INTERFACE_VERSION]];
            return;
        }
        NSString *path = [(Class<HaloNexusBorderInterfaceV1>)cls borderDefinitionPath];
        if (![path isKindOfClass:[NSString class]] || path.length == 0) path = _fallbackDefinitionPath;
        NSString *error = nil;
        HaloNexusDefinition *definition = path ? [HaloNexusDefinition definitionAtPath:path error:&error] : nil;
        if (!definition) {
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: %@.", kRequires,
                                                      error ?: @"HCG Nexus's border definition (HaloBorder.plist) is missing"]];
            return;
        }
        if (![definition.capabilities containsObject:@"live-geometry"] ||
            ![definition.capabilities containsObject:@"open-close-events"]) {
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: the installed HCG Nexus does not offer live panel geometry "
                                                      @"and open/close events.",
                                                      kRequires]];
            return;
        }

        id interface = [(Class<HaloNexusBorderInterfaceV1>)cls activeInterface];
        if (!interface) {
            [self detach];
            _definition = definition;
            [self setState:HaloNexusLinkStateWaiting
                    detail:[NSString stringWithFormat:@"HCG Nexus %@ found; waiting for its panel (is Enable HCG Nexus on?).",
                                                      definition.nexusVersion]];
            return;
        }
        if (![interface isKindOfClass:cls] || !HaloInterfaceUsable(interface)) {
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: the running HCG Nexus panel interface is incomplete.", kRequires]];
            return;
        }
        NSString *running = [interface nexusVersion];
        if (![running isKindOfClass:[NSString class]] || ![running isEqualToString:definition.nexusVersion]) {
            // Nexus was updated (or downgraded) on disk but SpringBoard still
            // runs the previous build: the file does not describe this panel.
            [self detach];
            [self setState:HaloNexusLinkStateUnavailable
                    detail:[NSString stringWithFormat:@"%@: HCG Nexus %@ is installed but %@ is running. Respring to use "
                                                      @"the panel border.",
                                                      kRequires, definition.nexusVersion,
                                                      [running isKindOfClass:[NSString class]] ? running : @"another version"]];
            return;
        }
        UIView *host = [interface borderHostView];
        if (![host isKindOfClass:[UIView class]]) {
            [self detach];
            _definition = definition;
            [self setState:HaloNexusLinkStateWaiting detail:@"HCG Nexus has not built its panel yet."];
            return;
        }

        BOOL sameDefinition = _definition && [_definition.path isEqualToString:definition.path] &&
                              [self definitionUnchangedAtPath:definition.path] && _borderView.superview == host &&
                              _interface == interface;
        if (!sameDefinition) {
            [self detach];
            _definition = definition;
            _definitionDate = [self modificationDateAtPath:definition.path];
            _borderView = [[HaloPanelBorderView alloc] initWithDefinition:definition];
            _interface = interface;
            [_borderView attachToHostView:host];
            HaloLogInfo("Nexus border attached (Nexus %{public}@, definition %{public}@)", definition.nexusVersion,
                        definition.path);
        }
        _borderView.panelCornerRadius = [interface panelCornerRadius];
        NSString *panelState = [interface panelState];
        _panelShown = [panelState isKindOfClass:[NSString class]] && ![panelState isEqualToString:@"closed"];
        _closing = [panelState isKindOfClass:[NSString class]] && [panelState isEqualToString:@"closing"];
        [self configureBorder];
        [self setState:HaloNexusLinkStateAttached
                detail:[NSString stringWithFormat:@"Drawing around the HCG Nexus %@ panel (definition: %@).",
                                                  definition.nexusVersion, definition.path]];
    } @catch (NSException *exception) {
        HaloLogError("Nexus link raised %{public}@", exception.reason);
        [self detach];
        [self setState:HaloNexusLinkStateUnavailable
                detail:[NSString stringWithFormat:@"%@: the panel interface raised an error (%@). The panel border is off.",
                                                  kRequires, exception.reason]];
    }
}

- (NSDate *)modificationDateAtPath:(NSString *)path {
    return [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate;
}

- (BOOL)definitionUnchangedAtPath:(NSString *)path {
    NSDate *now = [self modificationDateAtPath:path];
    return (now == nil && _definitionDate == nil) || [now isEqualToDate:_definitionDate];
}

- (void)detach {
    if (_borderView) {
        [_borderView teardown];
        _borderView = nil;
        HaloLogInfo("Nexus border detached");
    }
    _interface = nil;
    _panelShown = NO;
    _closing = NO;
    _rendering = @"Not drawing";
}

#pragma mark Rendering

- (HaloRenderPlan)plan {
    HaloAppearance appearance = _settings.effectiveNexusAppearance;
    return halo_render_plan(appearance.mode, _reduceMotion, _lowPower, _settings.lowPowerPolicy);
}

- (void)configureBorder {
    if (!_borderView) return;
    HaloRenderPlan plan = [self plan];
    [_borderView setAppearance:_settings.effectiveNexusAppearance plan:plan reduceTransparency:_reduceTransparency];
    [self updateActivity];
}

- (void)updateActivity {
    if (!_borderView) return;
    HaloRenderPlan plan = [self plan];
    BOOL closingHidden = _closing && !_settings.nexusCloseFade;
    BOOL active = _panelShown && _screenOn && !closingHidden;
    _borderView.active = active;
    if (!_panelShown) {
        _rendering = @"Hidden: HCG Nexus panel closed";
    } else if (!_screenOn) {
        _rendering = @"Hidden: screen off";
    } else if (closingHidden) {
        _rendering = @"Hidden: panel closing";
    } else if (plan.hidden) {
        _rendering = @"Hidden: Low Power Mode";
    } else if (plan.animated) {
        _rendering = [NSString stringWithFormat:@"Animating around the panel: %s", halo_mode_title(plan.mode)];
    } else {
        _rendering = plan.reason[0] ? [NSString stringWithFormat:@"Static around the panel (%s)", plan.reason]
                                    : @"Static around the panel";
    }
}

#pragma mark Events

- (void)startObserving {
    if (_observer) return;
    __weak HaloNexusLink *weakSelf = self;
    // Delivered synchronously on the posting thread (Nexus posts on the main
    // thread, just before it starts each animation), so the border reacts in
    // the same Core Animation transaction as the panel. Anything posted from
    // another thread is moved to the main thread.
    _observer = [[NSNotificationCenter defaultCenter] addObserverForName:HaloNexusBorderEventNotification
                                                                  object:nil
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *note) {
                                                                  if (NSThread.isMainThread) {
                                                                      [weakSelf handleNotification:note];
                                                                  } else {
                                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                                          [weakSelf handleNotification:note];
                                                                      });
                                                                  }
                                                              }];
}

- (void)stopObserving {
    if (!_observer) return;
    [[NSNotificationCenter defaultCenter] removeObserver:_observer];
    _observer = nil;
}

+ (NSString *)validatedEventFromNotification:(NSNotification *)note expectedInterface:(id)expected reason:(NSString **)reason {
#define HALO_REJECT(text)            \
    do {                             \
        if (reason) *reason = text;  \
        return nil;                  \
    } while (0)
    if (![note.name isEqualToString:HaloNexusBorderEventNotification]) HALO_REJECT(@"wrong name");
    Class cls = NSClassFromString(HaloNexusInterfaceClassName);
    id object = note.object;
    if (!cls || ![object isKindOfClass:cls]) HALO_REJECT(@"sender is not the HCG Nexus border interface");
    NSDictionary *info = note.userInfo;
    if (![info isKindOfClass:[NSDictionary class]] || info.count > 8) HALO_REJECT(@"malformed userInfo");
    NSString *event = info[@"event"];
    static NSSet *events;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        events = [NSSet setWithArray:@[ kEventInstalled, kEventWillOpen, kEventDidOpen, kEventWillClose, kEventDidClose,
                                        kEventGeometry, kEventWorkspace, kEventRemoved ]];
    });
    if (![event isKindOfClass:[NSString class]] || ![events containsObject:event]) HALO_REJECT(@"unknown event");
    NSNumber *version = info[@"interfaceVersion"];
    if (![version isKindOfClass:[NSNumber class]] || version.integerValue != HALO_NEXUS_INTERFACE_VERSION)
        HALO_REJECT(@"wrong interface version");
    NSNumber *generation = info[@"generation"];
    if (![generation isKindOfClass:[NSNumber class]]) HALO_REJECT(@"missing generation");
    NSNumber *duration = info[@"duration"];
    if (![duration isKindOfClass:[NSNumber class]] || !isfinite(duration.doubleValue) || duration.doubleValue < 0 ||
        duration.doubleValue > 5)
        HALO_REJECT(@"invalid duration");
    // Only the interface Halo is attached to (or, for "installed", the one
    // Nexus has just made active) may drive the border.
    if ([event isEqualToString:kEventInstalled]) {
        id active = [cls respondsToSelector:@selector(activeInterface)] ? [(Class<HaloNexusBorderInterfaceV1>)cls activeInterface] : nil;
        if (object != active) HALO_REJECT(@"not the active interface");
    } else if (object != expected) {
        HALO_REJECT(@"not the attached interface");
    }
    return event;
#undef HALO_REJECT
}

- (void)handleNotification:(NSNotification *)note {
    if (!_enabled) return;
    @try {
        NSString *reason = nil;
        NSString *event = [HaloNexusLink validatedEventFromNotification:note expectedInterface:_interface reason:&reason];
        if (!event) {
            HaloLogDebug("ignored Nexus event: %{public}@", reason);
            return;
        }
        HaloLogDebug("Nexus event %{public}@", event);
        if ([event isEqualToString:kEventInstalled]) {
            [self connect];
        } else if ([event isEqualToString:kEventRemoved]) {
            [self detach];
            [self setState:HaloNexusLinkStateWaiting detail:@"The HCG Nexus panel was removed."];
        } else if ([event isEqualToString:kEventWillOpen]) {
            _panelShown = YES;
            _closing = NO;
            [self updateActivity];
            NSTimeInterval duration = [note.userInfo[@"duration"] doubleValue];
            BOOL crossfade = [note.object reducedMotionTransition];
            if (_settings.nexusOpenTrace && !_reduceMotion && !crossfade && duration > 0 && _borderView.active)
                [_borderView playOpeningTraceWithDuration:duration];
            else
                [_borderView cancelOpeningTrace];
        } else if ([event isEqualToString:kEventDidOpen]) {
            _panelShown = YES;
            _closing = NO;
            [self updateActivity];
        } else if ([event isEqualToString:kEventWillClose]) {
            // Also reverses an opening in progress: the trace stops at once and
            // the border fades with the panel (it is inside it).
            [_borderView cancelOpeningTrace];
            _closing = YES;
            [self updateActivity];
        } else if ([event isEqualToString:kEventDidClose]) {
            [_borderView cancelOpeningTrace];
            _panelShown = NO;
            _closing = NO;
            [self updateActivity];
        } else if ([event isEqualToString:kEventGeometry]) {
            _borderView.panelCornerRadius = [note.object panelCornerRadius];
            [_borderView relayout];
        } else if ([event isEqualToString:kEventWorkspace]) {
            if (_settings.nexusWorkspacePulse && _borderView.active && !_closing)
                [_borderView playWorkspacePulseReducedMotion:_reduceMotion];
        }
    } @catch (NSException *exception) {
        HaloLogError("Nexus event raised %{public}@", exception.reason);
        [self detach];
        [self setState:HaloNexusLinkStateUnavailable
                detail:[NSString stringWithFormat:@"%@: an HCG Nexus event raised an error (%@). The panel border is off.",
                                                  kRequires, exception.reason]];
    }
}

#pragma mark State

- (void)setState:(NSString *)state detail:(NSString *)detail {
    BOOL changed = ![_state isEqualToString:state] || ![_detail isEqualToString:detail ?: @""];
    _state = [state copy];
    _detail = [detail copy] ?: @"";
    if (!changed) return;
    HaloLogInfo("Nexus border %{public}@: %{public}@", state, _detail);
    if (_stateDidChange) _stateDidChange(self);
}

+ (NSString *)definitionPathFromImagePath:(NSString *)imagePath {
    for (NSString *suffix in @[ @"/Library/MobileSubstrate/DynamicLibraries/HCGHalo.dylib", @"/usr/lib/TweakInject/HCGHalo.dylib",
                                @"/Library/PreferenceBundles/HCGHaloPrefs.bundle/HCGHaloPrefs" ]) {
        if (![imagePath hasSuffix:suffix]) continue;
        NSString *root = [imagePath substringToIndex:imagePath.length - suffix.length];
        return [[[root stringByAppendingPathComponent:@"Library/PreferenceBundles"]
            stringByAppendingPathComponent:HaloNexusPrefsBundleName] stringByAppendingPathComponent:HaloNexusDefinitionFileName];
    }
    return nil;
}

@end
