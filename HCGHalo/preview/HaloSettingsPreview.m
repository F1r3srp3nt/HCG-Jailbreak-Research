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
    NSMutableArray<void (^)(void)> *_steps;
    UIViewController *_nexusRoot;
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
        Check([footer containsString:@"HCG Halo is not installed."], [NSString stringWithFormat:@"Nexus alone: Appearance footer says Halo is not installed"]);
        [self state:@"A1-nexus-settings-alone" caption:@"Settings › HCG Nexus (Halo not installed)"];
    });
    STEP(2.0, {
        // PSListController exposes its table as -table (not -tableView).
        UITableView *table = ((id (*)(id, SEL))objc_msgSend)(self->_nexusRoot, NSSelectorFromString(@"table"));
        NSIndexPath *row = nil;
        for (NSInteger s = 0; s < table.numberOfSections && !row; s++)
            for (NSInteger r = 0; r < [table numberOfRowsInSection:s]; r++) {
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
                if ([cell.textLabel.text isEqualToString:@"Halo border"]) { row = [NSIndexPath indexPathForRow:r inSection:s]; break; }
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
        Check([footer containsString:@"HCG Halo is installed"], @"both: Appearance footer says Halo is installed");
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
        Check([version isEqualToString:@"0.3.1~beta1"], [NSString stringWithFormat:@"definition nexusVersion %@", version]);
        NSString *text = AllText(top);
        Check([text containsString:@"0.3.1~beta1 · compatible"], @"status row: HCG Nexus 0.3.1~beta1 · compatible");
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
    // C. HCG Halo's own entry point, and its controls.
    STEP(2.0, {
        UIViewController *haloRoot = [self principalOf:@"HCGHaloPrefs.bundle"];
        Check([NSStringFromClass([haloRoot class]) isEqualToString:@"HaloRootListController"], @"HCG Halo principal class loads");
        [self show:haloRoot];
        NSString *footer = FooterText((UITableViewController *)haloRoot);
        Check([footer containsString:@"HCG Nexus 0.3.1~beta1: compatible."], @"Halo › Border Target footer: HCG Nexus 0.3.1~beta1 compatible");
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
