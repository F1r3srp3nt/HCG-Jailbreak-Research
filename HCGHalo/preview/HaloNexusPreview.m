//
//  HaloNexusPreview.m
//  HCG Halo — PREVIEW of the HCG Nexus panel border (iOS Simulator only).
//
//  Built by scripts/nexus-preview.sh from two checkouts:
//    * HCG Nexus — its REAL panel code (Sources/Core, Sources/Panel,
//      Sources/Platform/Preview) and its REAL border definition
//      (Prefs/Resources/HaloBorder.plist, copied into this app bundle, where
//      Nexus's own +borderDefinitionPath looks in preview builds);
//    * HCG Halo — HaloNexusLink, HaloNexusDefinition, HaloPanelBorderView and
//      the renderer, exactly as the tweak uses them.
//  Nothing here is mocked on either side of the interface. What is NOT real:
//  SpringBoard, the overlay window, a device and its performance. This is
//  preview evidence, not a device result.
//
//  The app runs a fixed script and prints "HALO-PREVIEW-STATE <name>" when
//  the screen is ready for a screenshot, and "HALO-PREVIEW-CHECK PASS|FAIL
//  <what>" for each structural check. The host script records video and
//  takes the screenshots.
//

#import <UIKit/UIKit.h>

#import "HCGCore.h"
#import "HCGNexusBorderInterface.h"
#import "HCGNexusModel.h"
#import "HCGOverlayController.h"
#import "HCGPreviewPlatform.h"

#import "HaloNexusDefinition.h"
#import "HaloNexusLink.h"
#import "HaloPanelBorderView.h"
#import "HaloPreferences.h"

static int gFailures = 0;

static void Say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void Say(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static void Check(BOOL ok, NSString *what) {
    if (!ok) gFailures++;
    Say(@"HALO-PREVIEW-CHECK %@ %@", ok ? @"PASS" : @"FAIL", what);
}

@interface HaloPreviewViewController : UIViewController
@end

@implementation HaloPreviewViewController {
    HCGUserDefaultsKeyValueStore *_store;
    HCGPreviewLauncher *_launcher;
    HCGNexusModel *_model;
    HCGPreviewEnvironment *_environment;
    HCGOverlayController *_overlay;
    HaloNexusLink *_link;
    UILabel *_caption;
    NSMutableArray<void (^)(void)> *_steps;
    NSString *_presetIdentifier;
    BOOL _haloEnabled;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.06 alpha:1];

    UILabel *banner = [UILabel new];
    banner.numberOfLines = 0;
    banner.textAlignment = NSTextAlignmentCenter;
    banner.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    banner.textColor = UIColor.blackColor;
    banner.backgroundColor = [UIColor colorWithRed:1 green:0.71 blue:0.28 alpha:1];
    banner.text = @"PREVIEW · iOS Simulator · real HCG Nexus panel code + HCG Halo renderer · NOT a device result";
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:banner];

    _caption = [UILabel new];
    _caption.numberOfLines = 0;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    _caption.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    _caption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_caption];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [banner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [banner.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_caption.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_caption.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_caption.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
    ]];

    // HCG Nexus, set up the way its own preview harness does it.
    _store = [[HCGUserDefaultsKeyValueStore alloc] initWithSuiteName:@"com.hakmicapitalgroup.halo.nexus-preview"];
    [_store removeAllValues];
    _launcher = [[HCGPreviewLauncher alloc] init];
    _model = [[HCGNexusModel alloc] initWithStore:_store notifier:nil launcher:_launcher];
    _environment = [[HCGPreviewEnvironment alloc] initWithHostViewController:self];
    _overlay = [[HCGOverlayController alloc] initWithModel:_model environment:_environment];
    HCGSystemSignals signals;
    signals.deviceLocked = HCGTriStateNo;
    signals.coverSheetVisible = HCGTriStateNo;
    signals.screenBlanked = HCGTriStateNo;
    [_overlay updateSystemSignals:signals];

    // HCG Halo, configured for the panel only.
    _link = [[HaloNexusLink alloc] init];
    _presetIdentifier = @"builtin.nexus-signature";
    _haloEnabled = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_steps) return;
    [self buildScript];
    [self next];
}

#pragma mark Halo

- (HaloSettings *)haloSettings {
    NSDictionary *preset = [HaloPreferences presetWithIdentifier:_presetIdentifier][HaloPresetKeyAppearance] ?: @{};
    return [HaloPreferences settingsFromDictionary:@{
        HaloKeyEnabled : @(_haloEnabled),
        HaloKeyTarget : @"nexus",
        HaloKeyNexusAppearance : preset,
    }];
}

- (void)applyHalo {
    [_link applySettings:[self haloSettings]
                   enabled:_haloEnabled
              reduceMotion:UIAccessibilityIsReduceMotionEnabled()
              lowPowerMode:NSProcessInfo.processInfo.lowPowerModeEnabled
        reduceTransparency:UIAccessibilityIsReduceTransparencyEnabled()
                  screenOn:YES];
}

#pragma mark Nexus

- (void)setNexusEnabled:(BOOL)enabled {
    HCGSettings *settings = _model.settings;
    settings.enabled = enabled;
    settings.animationsEnabled = YES;
    [_model saveSettings:settings];
}

- (UIView *)borderHost {
    return [HCGNexusBorderInterface activeInterface].borderHostView;
}

- (NSUInteger)haloViewsInHost {
    NSUInteger count = 0;
    for (UIView *v in [self borderHost].subviews) count += [v isKindOfClass:[HaloPanelBorderView class]];
    return count;
}

/// Really on screen: in a window, and neither it nor any ancestor hidden or transparent.
- (BOOL)borderVisible {
    HaloPanelBorderView *border = _link.borderView;
    if (!border || !border.window) return NO;
    for (UIView *v = border; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

- (void)switchWorkspace {
    HCGWorkspaceStore *store = _model.workspaceStore;
    NSArray<HCGWorkspace *> *all = store.workspaces;
    if (all.count < 2) {
        [store createWorkspaceNamed:@"Preview" preset:HCGPresetStudio error:nil];
        all = store.workspaces;
    }
    NSUInteger index = [all indexOfObject:store.activeWorkspace];
    HCGWorkspace *next = all[(index == NSNotFound ? 0 : index + 1) % all.count];
    [store setActiveWorkspace:next.identifier error:nil];
    [_model workspacesDidChange];
}

#pragma mark Script

- (void)state:(NSString *)name caption:(NSString *)caption {
    _caption.text = caption;
    HCGNexusBorderInterface *nexus = [HCGNexusBorderInterface activeInterface];
    Say(@"HALO-PREVIEW-STATE %@ | link=%@ | %@ | nexus panelState=%@ onScreen=%d | border visible=%d",
        name, _link.state, _link.rendering, nexus.panelState ?: @"-", [_overlay isPanelOnScreen], [self borderVisible]);
}

- (void)after:(NSTimeInterval)delay do:(void (^)(void))block {
    [_steps addObject:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
    }];
}

- (void)next {
    if (!_steps.count) return;
    void (^step)(void) = _steps.firstObject;
    [_steps removeObjectAtIndex:0];
    step();
}

- (void)buildScript {
    _steps = [NSMutableArray array];
    __weak HaloPreviewViewController *weakSelf = self;
#define STEP(delay, body)                              \
    [self after:delay do:^{                            \
        HaloPreviewViewController *self = weakSelf;    \
        if (!self) return;                             \
        body;                                          \
        [self next];                                   \
    }]

    STEP(0.5, {
        [self applyHalo];
        Check([self->_link.state isEqualToString:HaloNexusLinkStateWaiting] ||
                  [self->_link.state isEqualToString:HaloNexusLinkStateUnavailable],
              [NSString stringWithFormat:@"before Nexus is enabled: no panel, link %@ (%@)", self->_link.state, self->_link.detail]);
        [self setNexusEnabled:YES];
        Check([self->_link.state isEqualToString:HaloNexusLinkStateAttached],
              [NSString stringWithFormat:@"Nexus enabled: link attached to the live panel via the installed definition (%@)",
                                         self->_link.definition.path.lastPathComponent]);
        Check([self haloViewsInHost] == 1, @"exactly one Halo border view inside Nexus's border host");
        Check(![self borderVisible], @"panel closed: no border visible");
        [self state:@"01-panel-closed" caption:@"Nexus enabled, panel closed: no border"];
    });
    STEP(2.5, {
        [self->_overlay simulateHandleActivation];
        [self state:@"02-opening-trace" caption:@"Opening: light trace travels around the panel"];
    });
    STEP(2.0, {
        Check([self->_overlay isPanelOnScreen] && [self borderVisible], @"panel open: border visible");
        Check(!self->_link.borderView.userInteractionEnabled, @"border never takes touches");
        [self state:@"03-open-nexus-signature" caption:@"Open · Nexus Signature (Colour Flow)"];
    });
    STEP(2.5, {
        [self switchWorkspace];
        [self state:@"04-workspace-pulse" caption:@"Workspace changed: one soft pulse"];
    });
    STEP(2.0, {
        self->_presetIdentifier = @"builtin.reactor";
        [self applyHalo];
        [self state:@"05-reactor" caption:@"Preset: Reactor (travelling segments, soft pulse)"];
    });
    STEP(3.0, {
        self->_presetIdentifier = @"builtin.hologram";
        [self applyHalo];
        [self state:@"06-hologram" caption:@"Preset: Hologram (thin, subtle)"];
    });
    STEP(2.5, {
        self->_presetIdentifier = @"builtin.circuit";
        [self applyHalo];
        [self state:@"07a-sci-fi-circuit" caption:@"Mode: Sci-Fi Circuit (preset Circuit Runner)"];
    });
    STEP(3.0, {
        self->_presetIdentifier = @"builtin.pulse";
        [self applyHalo];
        [self state:@"07b-breathing" caption:@"Mode: Breathing (preset Cyan Pulse)"];
    });
    STEP(2.5, {
        self->_presetIdentifier = @"builtin.nexus-signature";
        [self applyHalo];
        [self->_overlay simulateOutsideTap];
        [self state:@"08-closing-fade" caption:@"Closing: the border fades with the panel"];
    });
    STEP(1.5, {
        Check(![self->_overlay isPanelOnScreen] && ![self borderVisible], @"closed: no orphaned border");
        Check([self haloViewsInHost] == 1, @"still one border view after close");
        [self state:@"09-closed" caption:@"Closed: nothing left on screen"];
    });
    STEP(2.0, {
        HCGOverlayController *overlay = self->_overlay;
        [overlay simulateHandleActivation];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [overlay simulateOutsideTap]; // reverses the opening mid-way
        });
        [self state:@"10-reversed-opening" caption:@"Opening reversed after 0.12 s"];
    });
    STEP(1.5, {
        Check(![self->_overlay isPanelOnScreen] && ![self borderVisible] && !self->_link.borderView.tracing,
              @"reversed opening: border gone, trace cancelled");
        [self->_overlay simulateHandleActivation];
    });
    STEP(1.5, {
        self->_haloEnabled = NO;
        [self applyHalo];
        Check([self->_overlay isPanelOnScreen] && [self haloViewsInHost] == 0 && !self->_link.borderView,
              @"Halo disabled while the panel is open: border removed immediately, panel unaffected");
        [self state:@"11-halo-disabled" caption:@"HCG Halo disabled: plain HCG Nexus panel"];
    });
    STEP(2.5, {
        self->_haloEnabled = YES;
        [self applyHalo];
        Check([self borderVisible], @"Halo re-enabled: border back on the open panel");
        [self state:@"12-halo-reenabled" caption:@"HCG Halo enabled again"];
    });
    STEP(2.5, {
        [self setNexusEnabled:NO];
        Check(![self borderVisible] && ![self->_overlay isPanelOnScreen],
              [NSString stringWithFormat:@"Nexus disabled: panel and border gone (link %@)", self->_link.state]);
        [self state:@"13-nexus-disabled" caption:@"HCG Nexus disabled: no panel, no border"];
    });
    STEP(2.0, {
        [self setNexusEnabled:YES];
        for (int i = 0; i < 30; i++) {
            [self->_overlay simulateHandleActivation];
            if (i % 3 == 0) [self switchWorkspace];
            [self->_overlay simulateOutsideTap];
        }
    });
    STEP(1.5, {
        Check([self haloViewsInHost] == 1 && ![self borderVisible] && ![self->_overlay isPanelOnScreen],
              @"30 rapid open/close cycles (reversed mid-animation): one border view, none left visible");
        [self->_overlay simulateHandleActivation];
    });
    STEP(2.0, {
        Check([self->_overlay isPanelOnScreen] && [self borderVisible], @"opens normally after the cycles");
        [self state:@"14-after-cycles" caption:@"After 30 open/close cycles"];
    });
    STEP(2.5, {
        [self->_overlay simulateOutsideTap];
        Say(@"HALO-PREVIEW-DONE failures=%d", gFailures);
    });
#undef STEP
}

@end

@interface HaloPreviewAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HaloPreviewAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HaloPreviewViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HaloPreviewAppDelegate class]));
    }
}
