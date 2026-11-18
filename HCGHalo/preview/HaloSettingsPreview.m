//
//  HaloSettingsPreview.m
//  HCG Halo — PREVIEW of the two Settings entry points (iOS Simulator only).
//
//  Built by scripts/settings-preview.sh. It loads the two REAL Settings bundles,
//  compiled for the simulator from their own sources, from a folder laid out the
//  way a rootless jailbreak installs them:
//
//    <Documents>/PreferenceBundles/HCGNexusPrefs.bundle   HCG Nexus (with its real HaloBorder.plist)
//    <Documents>/PreferenceBundles/HCGHaloPrefs.bundle    HCG Halo
//
//  Preferences.framework (private) is loaded from the simulator runtime.
//
//  The script exercises, in order:
//    A. HCG Nexus alone: Settings › HCG Nexus › Appearance › Halo border explains
//       that Halo is missing.
//    B. Both installed: the same row loads HCG Halo's bundle and pushes its
//       HaloNexusBorderController, which reads the installed Nexus definition.
//    C. HCG Halo's own page › Nexus Panel Border: the same controller, then a
//       target and a preset are chosen and Reset Nexus Lighting is applied.
//    D. Nexus definition malformed, then removed: Halo's page says "Requires
//       compatible HCG Nexus" and disables the panel targets.
//
//  It prints "HALO-SETTINGS-STATE <name>" (stills come from the video) and
//  "HALO-SETTINGS-CHECK PASS|FAIL <what>". Not a device result: there is no
//  Settings app, no PreferenceLoader and no SpringBoard here.
//

#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <dlfcn.h>

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
    Say(@"HALO-SETTINGS-CHECK %@ %@", ok ? @"PASS" : @"FAIL", what);
}

static void Collect(UIView *view, NSMutableArray<NSString *> *out) {
    if ([view isKindOfClass:[UILabel class]] && ((UILabel *)view).text.length && !view.hidden) [out addObject:((UILabel *)view).text];
    for (UIView *sub in view.subviews) Collect(sub, out);
}

static NSString *AllText(UIViewController *controller) {
    NSMutableArray *texts = [NSMutableArray array];
    Collect(controller.view, texts);
    return [texts componentsJoinedByString:@" | "];
}

static id PrefValue(NSString *key) {
    CFPreferencesAppSynchronize(CFSTR("com.hakmicapitalgroup.halo"));
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.hakmicapitalgroup.halo")));
}

static NSString *FooterText(UITableViewController *controller) {
    NSMutableArray *texts = [NSMutableArray array];
    // PSListController: footers live in its group specifiers' "footerText".
    if ([controller respondsToSelector:NSSelectorFromString(@"specifiers")]) {
        NSArray *specifiers = ((id (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"specifiers"));
        for (id spec in specifiers) {
            id text = ((id (*)(id, SEL, id))objc_msgSend)(spec, NSSelectorFromString(@"propertyForKey:"), @"footerText");
            if ([text isKindOfClass:[NSString class]] && [text length]) [texts addObject:text];
        }
        return [texts componentsJoinedByString:@" | "];
    }
    UITableView *table = controller.tableView;
    for (NSInteger s = 0; s < table.numberOfSections; s++) {
        if ([table.dataSource respondsToSelector:@selector(tableView:titleForFooterInSection:)]) {
            NSString *t = [table.dataSource tableView:table titleForFooterInSection:s];
            if (t.length) [texts addObject:t];
        }
    }
    return [texts componentsJoinedByString:@" | "];
}

@interface HaloSettingsViewController : UIViewController
@end

@implementation HaloSettingsViewController {
    UINavigationController *_nav;
    UILabel *_caption;
    NSString *_bundles;
    NSString *_stage;
    UIViewController *_haloRoot;
    NSString *_chosenApp;
    NSString *_chosenName;
    NSMutableArray<void (^)(void)> *_steps;
    UIViewController *_nexusRoot;
    NSString *_nexusVersion; // read from the installed definition (step B)
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UILabel *banner = [UILabel new];
    banner.numberOfLines = 0;
    banner.textAlignment = NSTextAlignmentCenter;
    banner.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    banner.backgroundColor = [UIColor colorWithRed:1 green:0.71 blue:0.28 alpha:1];
    banner.textColor = UIColor.blackColor;
    banner.text = @"PREVIEW · iOS Simulator · real HCG Nexus + HCG Halo Settings bundles · NOT a device result";
    _caption = [UILabel new];
    _caption.numberOfLines = 0;
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    _caption.textColor = UIColor.whiteColor;
    _caption.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    _nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    _nav.navigationBar.prefersLargeTitles = NO;
    [self addChildViewController:_nav];
    for (UIView *v in @[ banner, _nav.view, _caption ]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:v];
    }
    [_nav didMoveToParentViewController:self];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [banner.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [banner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [banner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_nav.view.topAnchor constraintEqualToAnchor:banner.bottomAnchor],
        [_nav.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_nav.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_nav.view.bottomAnchor constraintEqualToAnchor:_caption.topAnchor],
        [_caption.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_caption.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_caption.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_caption.heightAnchor constraintEqualToConstant:44],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_steps) return;
    [self buildScript];
    [self next];
}

#pragma mark Helpers

- (void)state:(NSString *)name caption:(NSString *)caption {
    _caption.text = caption;
    Say(@"HALO-SETTINGS-STATE %@ | top=%@", name, NSStringFromClass([_nav.topViewController class]));
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
    @try {
        step();
    } @catch (NSException *exception) {
        Check(NO, [NSString stringWithFormat:@"exception: %@ — %@", exception.name, exception.reason]);
        [self next];
    }
}

- (BOOL)install:(NSString *)name {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *to = [_bundles stringByAppendingPathComponent:name];
    [fm removeItemAtPath:to error:nil];
    NSError *error = nil;
    BOOL ok = [fm copyItemAtPath:[_stage stringByAppendingPathComponent:name] toPath:to error:&error];
    if (!ok) Say(@"copy %@ failed: %@", name, error);
    return ok;
}

- (UIViewController *)principalOf:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleWithPath:[_bundles stringByAppendingPathComponent:name]];
    NSError *error = nil;
    if (![bundle isLoaded] && ![bundle loadAndReturnError:&error]) {
        Check(NO, [NSString stringWithFormat:@"load %@: %@", name, error.localizedDescription]);
        return nil;
    }
    Class cls = bundle.principalClass;
    return cls ? [[cls alloc] init] : nil;
}

- (void)show:(UIViewController *)root {
    [_nav setViewControllers:@[ root ] animated:NO];
    [root loadViewIfNeeded];
    [root.view layoutIfNeeded];
}

- (void)send:(NSString *)selectorName to:(id)target {
    SEL selector = NSSelectorFromString(selectorName);
    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, nil);
}

#pragma mark Script

- (void)buildScript {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    _bundles = [documents stringByAppendingPathComponent:@"PreferenceBundles"];
    // Start from HCG Halo's defaults, whatever an earlier (retried) launch left behind.
    CFStringRef domain = CFSTR("com.hakmicapitalgroup.halo");
    CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    CFPreferencesAppSynchronize(domain);
    _stage = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Stage"];
    [NSFileManager.defaultManager removeItemAtPath:_bundles error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:_bundles withIntermediateDirectories:YES attributes:nil error:nil];
    _steps = [NSMutableArray array];
    __weak HaloSettingsViewController *weakSelf = self;
#define STEP(delay, ...)                               \
    [self after:delay do:^{                            \
        HaloSettingsViewController *self = weakSelf;   \
        if (!self) return;                             \
        @try {                                         \
            __VA_ARGS__;                               \
        } @catch (NSException *e) {                    \
            Check(NO, [NSString stringWithFormat:@"exception: %@ — %@", e.name, e.reason]); \
        }                                              \
        [self next];                                   \
    }]

    // A. HCG Nexus alone.
    STEP(1.0, {
        void *prefs = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_NOW | RTLD_GLOBAL);
        Check(prefs != NULL, @"Preferences.framework loaded from the simulator runtime");
        Check([self install:@"HCGNexusPrefs.bundle"], @"HCG Nexus Settings bundle installed (alone)");
        self->_nexusRoot = [self principalOf:@"HCGNexusPrefs.bundle"];
        Check([NSStringFromClass([self->_nexusRoot class]) isEqualToString:@"HCGNexusRootListController"], @"HCG Nexus principal class loads");
        [self show:self->_nexusRoot];
        NSString *footer = FooterText((UITableViewController *)self->_nexusRoot);
        Check([footer containsString:@"HCG Halo is not installed"], [NSString stringWithFormat:@"Nexus alone: Appearance footer says Halo is not installed"]);
        // HCG Nexus 0.3.2~beta1+: "Use HCG Halo border" (absent in older Nexus builds: then nothing to check here).
        id useSpec = ((id (*)(id, SEL, id))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"specifierForID:"), @"useHaloBorder");
        if (useSpec) {
            id statusSpec = ((id (*)(id, SEL, id))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"specifierForID:"), @"haloBorderStatus");
            NSString *state = ((id (*)(id, SEL, id))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"haloBorderStatusValue:"), statusSpec);
            id enabled = ((id (*)(id, SEL, id))objc_msgSend)(useSpec, NSSelectorFromString(@"propertyForKey:"), @"enabled");
            Check([state isEqualToString:@"Not installed"] && enabled && ![enabled boolValue],
                  [NSString stringWithFormat:@"Nexus alone: Use HCG Halo border = %@, switch disabled", state]);
        }
        [self state:@"A1-nexus-settings-alone" caption:@"Settings › HCG Nexus (Halo not installed)"];
    });
    STEP(2.0, {
        // PSListController exposes its table as -table (not -tableView).
        UITableView *table = ((id (*)(id, SEL))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"table"));
        // Find the row through its specifier (id "haloBorder" in Nexus's Root.plist).
        NSIndexPath *row = nil;
        NSArray *specifiers = ((id (*)(id, SEL))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"specifiers"));
        for (id spec in specifiers) {
            NSString *identifier = ((id (*)(id, SEL))objc_msgSend)(spec, NSSelectorFromString(@"identifier"));
            if (![identifier isEqualToString:@"haloBorder"]) continue;
            row = ((id (*)(id, SEL, id))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"indexPathForSpecifier:"), spec);
            break;
        }
        Check(row != nil, @"Appearance › Halo border row is shown");
        if (row) [table scrollToRowAtIndexPath:row atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [self send:@"openHaloBorder:" to:self->_nexusRoot];
        UIViewController *presented = self->_nexusRoot.presentedViewController;
        Check([presented isKindOfClass:[UIAlertController class]] &&
                  [((UIAlertController *)presented).message containsString:@"Install HCG Halo"],
              @"Nexus alone: Halo border explains HCG Halo is needed (alert), nothing loaded");
        [self state:@"A2-halo-border-without-halo" caption:@"Appearance › Halo border without HCG Halo"];
    });
    // B. Both installed: the Nexus entry point.
    STEP(2.5, {
        [self->_nexusRoot dismissViewControllerAnimated:NO completion:nil];
        Check([self install:@"HCGHaloPrefs.bundle"], @"HCG Halo Settings bundle installed next to HCG Nexus");
        [self send:@"reloadSpecifiers" to:self->_nexusRoot];
        NSString *footer = FooterText((UITableViewController *)self->_nexusRoot);
        // Nexus 0.3.1 says "HCG Halo is installed"; 0.3.2+ states the switch's real state. Either way, not "missing".
        Check(footer.length && ![footer containsString:@"HCG Halo is not installed"], @"both: Appearance footer no longer says Halo is missing");
        [self send:@"openHaloBorder:" to:self->_nexusRoot];
    });
    STEP(1.5, {
        UIViewController *top = self->_nav.topViewController;
        Check([NSStringFromClass([top class]) isEqualToString:@"HaloNexusBorderController"],
              [NSString stringWithFormat:@"Nexus › Appearance › Halo border pushes HCG Halo's page (%@)", NSStringFromClass([top class])]);
        id definition = [top valueForKey:@"definition"];
        NSString *version = [definition valueForKey:@"nexusVersion"];
        NSString *path = [definition valueForKey:@"path"];
        Check(definition && [path hasSuffix:@"PreferenceBundles/HCGNexusPrefs.bundle/HaloBorder.plist"],
              [NSString stringWithFormat:@"Halo page read the INSTALLED Nexus definition (%@)", path]);
        Check(version.length > 0, [NSString stringWithFormat:@"definition nexusVersion %@", version]);
        self->_nexusVersion = version;
        NSString *text = AllText(top);
        Check([text containsString:[version stringByAppendingString:@" · compatible"]],
              [NSString stringWithFormat:@"status row: HCG Nexus %@ · compatible", version]);
        Check([text containsString:@"HCG Nexus"] && [text containsString:@"PREVIEW"], @"panel outline preview shown");
        [self state:@"B1-halo-page-from-nexus" caption:@"Nexus › Appearance › Halo border → HCG Halo page"];
        [self send:@"replayOpening" to:top];
    });
    STEP(0.35, {
        [self state:@"B2-replay-opening" caption:@"Replay Opening (preview trace)"];
    });
    STEP(2.0, {
        UITableViewController *top = (UITableViewController *)self->_nav.topViewController;
        [top.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2] atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self state:@"B3-halo-page-target-look" caption:@"Border Target and Panel Look"];
    });
    // B4. Nexus › Appearance › Use HCG Halo border (HCG Nexus 0.3.2~beta1+): Nexus's real Settings bundle calls
    // HCG Halo's own HaloNexusControl; the screen edge must never be turned on or off by it.
    STEP(1.5, {
        [self->_nav popToRootViewControllerAnimated:NO];
        id root = self->_nexusRoot;
        [self send:@"reloadSpecifiers" to:root];
        id useSpec = ((id (*)(id, SEL, id))objc_msgSend)(root, NSSelectorFromString(@"specifierForID:"), @"useHaloBorder");
        if (!useSpec) {
            Say(@"HALO-SETTINGS-INFO this HCG Nexus build has no Use HCG Halo border switch (before 0.3.2~beta1); B4 skipped");
            return;
        }
        id statusSpec = ((id (*)(id, SEL, id))objc_msgSend)(root, NSSelectorFromString(@"specifierForID:"), @"haloBorderStatus");
        NSString *(^state)(void) = ^NSString * {
            return ((id (*)(id, SEL, id))objc_msgSend)(root, NSSelectorFromString(@"haloBorderStatusValue:"), statusSpec);
        };
        void (^flip)(BOOL) = ^(BOOL on) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(root, NSSelectorFromString(@"setHaloBorderSwitchValue:specifier:"), @(on), useSpec);
        };
        Class prefsClass = NSClassFromString(@"HaloPreferences");
        void (^write)(NSDictionary *) = ^(NSDictionary *values) {
            ((void (*)(id, SEL, id))objc_msgSend)(prefsClass, NSSelectorFromString(@"writeValues:"), values);
        };
        id enabled = ((id (*)(id, SEL, id))objc_msgSend)(useSpec, NSSelectorFromString(@"propertyForKey:"), @"enabled");
        Check(enabled && [enabled boolValue], @"both installed: Use HCG Halo border can be switched (HCGHaloNexusControl 1)");
        write(@{ @"enabled" : @NO, @"target" : @"screen" });
        Check([state() isEqualToString:@"Disabled"], [NSString stringWithFormat:@"Halo off: state %@ (Disabled)", state()]);
        flip(YES);
        Check([PrefValue(@"enabled") boolValue] && [PrefValue(@"target") isEqualToString:@"nexus"],
              [NSString stringWithFormat:@"switch on with Halo off: panel only (enabled %@, target %@)", PrefValue(@"enabled"), PrefValue(@"target")]);
        Check([state() isEqualToString:@"Ready"], [NSString stringWithFormat:@"switched on: state %@ (Ready)", state()]);
        [self state:@"B4-nexus-use-halo-border-on" caption:@"Nexus › Appearance › Use HCG Halo border: on (Ready)"];
        flip(NO);
        Check(![PrefValue(@"enabled") boolValue], @"switch off: HCG Halo off again (screen edge never turned on)");
        write(@{ @"enabled" : @YES, @"target" : @"screen" });
        flip(YES);
        Check([PrefValue(@"enabled") boolValue] && [PrefValue(@"target") isEqualToString:@"both"], @"screen edge on + switch on: Both (screen edge kept)");
        flip(NO);
        Check([PrefValue(@"enabled") boolValue] && [PrefValue(@"target") isEqualToString:@"screen"], @"switch off: screen edge only, unchanged");
        write(@{ @"enabled" : [NSNull null], @"target" : [NSNull null] });
    });
    // C. HCG Halo's own entry point, and its controls.
    STEP(2.0, {
        UIViewController *haloRoot = [self principalOf:@"HCGHaloPrefs.bundle"];
        Check([NSStringFromClass([haloRoot class]) isEqualToString:@"HaloRootListController"], @"HCG Halo principal class loads");
        [self show:haloRoot];
        NSString *footer = FooterText((UITableViewController *)haloRoot);
        NSString *compatible = [NSString stringWithFormat:@"HCG Nexus %@: compatible.", self->_nexusVersion ?: @"?"];
        Check([footer containsString:compatible], [NSString stringWithFormat:@"Halo › Border Target footer: %@", compatible]);
        [self state:@"C1-halo-settings-root" caption:@"Settings › HCG Halo"];
        [self send:@"openNexusBorder:" to:haloRoot];
    });
    STEP(1.5, {
        UITableViewController *top = (UITableViewController *)self->_nav.topViewController;
        Check([NSStringFromClass([top class]) isEqualToString:@"HaloNexusBorderController"], @"Halo › Nexus Panel Border pushes the same page");
        // Choose the target "Nexus Panel" (section 1, row 1) and the preset Reactor.
        [top.tableView.delegate tableView:top.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
        Check([PrefValue(@"target") isEqualToString:@"nexus"], [NSString stringWithFormat:@"target written: %@", PrefValue(@"target")]);
        UITableView *table = top.tableView;
        NSInteger lookSection = 2, reactor = -1;
        for (NSInteger r = 0; r < [table numberOfRowsInSection:lookSection]; r++) {
            UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:lookSection]];
            if ([cell.textLabel.text isEqualToString:@"Reactor"]) reactor = r;
        }
        Check(reactor >= 0, @"Panel Look lists Reactor");
        if (reactor >= 0) [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:reactor inSection:lookSection]];
        Check([PrefValue(@"nexusAppearance")[@"mode"] isEqualToString:@"orbit"] && PrefValue(@"mode") == nil,
              @"Reactor applied to the panel border only (screen-edge mode untouched)");
        [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3] atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self state:@"C2-target-nexus-reactor" caption:@"Target: Nexus Panel · preset Reactor"];
    });
    STEP(2.5, {
        UITableViewController *top = (UITableViewController *)self->_nav.topViewController;
        UITableView *table = top.tableView;
        NSInteger last = table.numberOfSections - 1;
        [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:last] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:last]];
        UIAlertController *alert = (UIAlertController *)top.presentedViewController;
        Check([alert isKindOfClass:[UIAlertController class]] && [alert.title isEqualToString:@"Reset Nexus Lighting"],
              @"Reset Nexus Lighting asks for confirmation");
        [self state:@"C3-reset-nexus-lighting" caption:@"Reset Nexus Lighting (confirmation)"];
    });
    STEP(2.0, {
        UITableViewController *top = (UITableViewController *)self->_nav.topViewController;
        [top dismissViewControllerAnimated:NO completion:nil];
        Class prefsClass = NSClassFromString(@"HaloPreferences");
        ((void (*)(id, SEL))objc_msgSend)(prefsClass, NSSelectorFromString(@"resetNexusLighting"));
        Check(PrefValue(@"nexusAppearance") == nil && [PrefValue(@"target") isEqualToString:@"nexus"],
              @"reset clears the panel look only (target kept)");
    });
    // D. Nexus definition malformed, then missing.
    STEP(0.5, {
        NSString *definition = [self->_bundles stringByAppendingPathComponent:@"HCGNexusPrefs.bundle/HaloBorder.plist"];
        [@"<plist><dict><key>schema</key><string>other</string></dict></plist>" writeToFile:definition atomically:YES encoding:NSUTF8StringEncoding error:nil];
        UIViewController *page = [[NSClassFromString(@"HaloNexusBorderController") alloc] init];
        [self->_nav pushViewController:page animated:NO];
        [page.view layoutIfNeeded];
        Check([page valueForKey:@"definition"] == nil && [FooterText((UITableViewController *)page) containsString:@"Requires compatible HCG Nexus"],
              @"malformed definition: Requires compatible HCG Nexus, panel targets disabled");
        UITableView *pageTable = ((UITableViewController *)page).tableView;
        UITableViewCell *status = [pageTable.dataSource tableView:pageTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Check([status.detailTextLabel.text isEqualToString:@"Not compatible"], [NSString stringWithFormat:@"status row: %@", status.detailTextLabel.text]);
        // "Both" (section 1, row 2) is not selected, so without a compatible Nexus it must be disabled.
        UITableViewCell *both = [pageTable.dataSource tableView:pageTable cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
        Check((both.accessibilityTraits & UIAccessibilityTraitNotEnabled) != 0, @"target \"Both\" is disabled without a compatible Nexus");
        [self state:@"D1-malformed-definition" caption:@"Nexus definition malformed → Requires compatible HCG Nexus"];
    });
    STEP(2.5, {
        [NSFileManager.defaultManager removeItemAtPath:[self->_bundles stringByAppendingPathComponent:@"HCGNexusPrefs.bundle"] error:nil];
        UIViewController *page = [[NSClassFromString(@"HaloNexusBorderController") alloc] init];
        [self->_nav pushViewController:page animated:NO];
        [page.view layoutIfNeeded];
        Check([page valueForKey:@"definition"] == nil && [FooterText((UITableViewController *)page) containsString:@"Requires compatible HCG Nexus"],
              @"Nexus removed: Requires compatible HCG Nexus; screen edge unaffected");
        [self state:@"D2-nexus-absent" caption:@"HCG Nexus not installed → Requires compatible HCG Nexus"];
    });
    // E. Show Halo on (screen edge) and the installed-app picker.
    STEP(1.0, {
        UIViewController *haloRoot = [self principalOf:@"HCGHaloPrefs.bundle"];
        [self show:haloRoot];
        self->_haloRoot = haloRoot;
        id spec = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"specifierForID:"), @"showOn");
        id value = spec ? ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"readPreferenceValue:"), spec) : nil;
        Check(spec && [value isEqualToString:@"home"], [NSString stringWithFormat:@"Show Halo on row, default %@", value]);
        Check(((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"specifierForID:"), @"displayContext") == nil,
              @"the read-only Display Context row is replaced");
        NSString *footer = FooterText((UITableViewController *)haloRoot);
        Check([footer containsString:@"Home Screen Only (default)"] && [footer containsString:@"fully off can't show a border"] &&
                  [footer containsString:@"Always and Always Except When Screen Is Off"],
              @"Show Halo on footer: current choice, dark display, Always vs Except Screen Off");
        Check([footer containsString:@"HCG Nexus panel border follows the panel"], @"footer: Nexus panel lighting not affected");
        id picker = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"specifierForID:"), @"openAppPicker");
        NSString *pickerName = picker ? ((id (*)(id, SEL))objc_msgSend)(picker, NSSelectorFromString(@"name")) : nil;
        Check([pickerName isEqualToString:@"Choose App…"], [NSString stringWithFormat:@"app row: %@", pickerName]);
        UITableView *table = ((id (*)(id, SEL))objc_msgSend)(haloRoot, NSSelectorFromString(@"table")); // PSListController: -table
        id indexPath = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"indexPathForSpecifier:"), spec);
        if (indexPath) [table scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self state:@"E1-show-halo-on-default" caption:@"Settings › HCG Halo › Show Halo on (default)"];
        [self send:@"openAppPicker:" to:haloRoot];
    });
    STEP(2.5, {
        UITableViewController *top = (UITableViewController *)self->_nav.topViewController;
        Check([NSStringFromClass([top class]) isEqualToString:@"HaloAppPickerController"], @"Choose App opens the app picker");
        NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"HaloAppPickerController"), NSSelectorFromString(@"installedApps"));
        Say(@"HALO-SETTINGS-INFO installed apps listed: %lu", (unsigned long)apps.count);
        NSInteger safari = -1;
        for (NSUInteger i = 0; i < apps.count; i++)
            if ([apps[i][@"id"] isEqualToString:@"com.apple.mobilesafari"]) safari = (NSInteger)i;
        Check(apps.count > 0 || [FooterText(top) containsString:@"Enter Bundle ID"],
              [NSString stringWithFormat:@"picker lists the installed apps (%lu) or offers manual entry", (unsigned long)apps.count]);
        if (apps.count) {
            NSInteger row = safari >= 0 ? safari : 0;
            [top.tableView.delegate tableView:top.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
            self->_chosenApp = apps[row][@"id"];
            self->_chosenName = apps[row][@"name"];
        } else {
            // Manual fallback, as a user would type it.
            ((void (*)(id, SEL, id, id))objc_msgSend)(top, NSSelectorFromString(@"choose:name:"), @"com.apple.mobilesafari", @"Safari");
            self->_chosenApp = @"com.apple.mobilesafari";
            self->_chosenName = @"Safari";
        }
        Check([PrefValue(@"showOn") isEqualToString:@"app"] && [PrefValue(@"showOnApp") isEqualToString:self->_chosenApp],
              [NSString stringWithFormat:@"choosing %@ stores it and selects Selected App Only", self->_chosenApp]);
        [top.tableView reloadData];
        [self state:@"E2-app-picker" caption:[NSString stringWithFormat:@"Chosen App: %@", self->_chosenName]];
    });
    STEP(2.5, {
        [self->_nav popToRootViewControllerAnimated:NO];
        UIViewController *haloRoot = self->_haloRoot;
        ((void (*)(id, SEL))objc_msgSend)(haloRoot, NSSelectorFromString(@"reloadSpecifiers"));
        id picker = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"specifierForID:"), @"openAppPicker");
        NSString *pickerName = picker ? ((id (*)(id, SEL))objc_msgSend)(picker, NSSelectorFromString(@"name")) : nil;
        Check([pickerName hasPrefix:@"Chosen App: "], [NSString stringWithFormat:@"app row now: %@", pickerName]);
        Check([FooterText((UITableViewController *)haloRoot) containsString:@"Selected App Only: the border shows only while"],
              @"footer explains Selected App Only with the chosen app");
        id spec = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"specifierForID:"), @"showOn");
        ((void (*)(id, SEL, id, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"setPreferenceValue:specifier:"), @"always", spec);
        Check([PrefValue(@"showOn") isEqualToString:@"always"] &&
                  [FooterText((UITableViewController *)haloRoot) containsString:@"Always: the border shows on every lit screen"],
              @"Always written, footer updated at once");
        ((void (*)(id, SEL, id, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"setPreferenceValue:specifier:"), @"lockscreen", spec);
        Check([PrefValue(@"showOn") isEqualToString:@"home"], @"an unknown Show Halo on value is stored as Home Screen Only");
        ((void (*)(id, SEL, id, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"setPreferenceValue:specifier:"), @"exceptLock", spec);
        UITableView *table = ((id (*)(id, SEL))objc_msgSend)(haloRoot, NSSelectorFromString(@"table")); // PSListController: -table
        id indexPath = ((id (*)(id, SEL, id))objc_msgSend)(haloRoot, NSSelectorFromString(@"indexPathForSpecifier:"), spec);
        if (indexPath) [table scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
        [self state:@"E3-show-halo-on-except-lock" caption:@"Show Halo on: Always Except Lock Screen"];
    });
    STEP(2.5, {
        Say(@"HALO-SETTINGS-DONE failures=%d", gFailures);
    });
#undef STEP
}

@end

@interface HaloSettingsAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation HaloSettingsAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HaloSettingsViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HaloSettingsAppDelegate class]));
    }
}
