//
//  HACRootListController.m
//  HCG Animation Center — Hakmi Capital Group
//
//  Settings › HCG Animation Center. Values are read and written through
//  CFPreferences (HACPreferences), never by PSListController's plist writer,
//  so SpringBoard sees every change at once. Status comes from SpringBoard
//  (HACStatusDomain), refreshed on request.
//

#import "HACRootListController.h"
#import "HACAIViewController.h"
#import "HACLibraryViewController.h"
#import "HACPreferences.h"
#import "HACTheme.h"

#import <Preferences/PSSpecifier.h>
#import <Preferences/PSControlTableCell.h>
#include <notify.h>

static void HACStatusUpdated(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                             CFDictionaryRef userInfo);

@implementation HACRootListController {
    BOOL _observingStatus;
    UIColor *_previousNavigationTint;
}

- (void)dealloc {
    [self stopObservingStatus];
}

#pragma mark Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self applyDynamicText];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    if (_specifiers) [self applyDynamicText];
    [super reloadSpecifiers];
}

- (NSDictionary *)status {
    return [HACPreferences readStatus];
}

- (void)applyDynamicText {
    NSDictionary *status = [self status];
    NSMutableArray *lines = [NSMutableArray array];
    NSString *detail = status[HACStatusKeyDetail];
    if ([detail isKindOfClass:[NSString class]] && detail.length) [lines addObject:detail];
    for (NSString *key in @[ HACStatusKeyHome, HACStatusKeyLock ]) {
        NSDictionary *surface = status[key];
        if (![surface isKindOfClass:[NSDictionary class]]) continue;
        NSString *host = surface[HACSurfaceStatusKeyHost];
        if ([host isKindOfClass:[NSString class]] && host.length)
            [lines addObject:[NSString stringWithFormat:@"%@ placement: %@.",
                                                        [key isEqualToString:HACStatusKeyHome] ? @"Home Screen" : @"Lock Screen",
                                                        host]];
    }
    NSString *probe = status[HACStatusKeyProbePath];
    if ([probe isKindOfClass:[NSString class]] && probe.length)
        [lines addObject:[NSString stringWithFormat:@"Last hierarchy probe: %@", probe]];
    NSDate *when = status[HACStatusKeyTimestamp];
    if ([when isKindOfClass:[NSDate class]]) {
        [lines addObject:[NSString stringWithFormat:@"Reported by SpringBoard at %@.",
                                                    [NSDateFormatter localizedStringFromDate:when
                                                                                   dateStyle:NSDateFormatterShortStyle
                                                                                   timeStyle:NSDateFormatterMediumStyle]]];
    } else {
        [lines addObject:@"SpringBoard has not reported yet. If you just installed HCG Animation Center, respring."];
    }
    NSString *version = status[HACStatusKeyTweakVersion];
    if ([version isKindOfClass:[NSString class]] && version.length && ![version isEqualToString:@HAC_VERSION])
        [lines addObject:[NSString stringWithFormat:@"SpringBoard is running %@ but %s is installed: respring.", version,
                                                    HAC_VERSION]];
    [[self specifierForID:@"statusDetail"] setProperty:[lines componentsJoinedByString:@"\n\n"] forKey:@"footerText"];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    id value = [HACPreferences valueForKey:key];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }
    // Turning the master switch is the user's explicit "try again" after the launch guard stopped it.
    if ([key isEqualToString:HACKeyEnabled]) [HACPreferences setConsecutiveUnstableLaunches:0];
    [HACPreferences setValue:value forKey:key];
    [self requestStatusSoon];
}

#pragma mark Getters

- (NSString *)engineStatus:(PSSpecifier *)specifier {
    NSString *state = [self status][HACStatusKeyState];
    NSDictionary *titles = @{
        HACEngineStateDisabled : @"Off",
        HACEngineStateWaiting : @"Starting",
        HACEngineStateActive : @"Active",
        HACEngineStateKillSwitch : @"Disabled by kill switch",
        HACEngineStateIncompatible : @"Incompatible",
        HACEngineStateAutoDisabled : @"Auto-disabled",
        HACEngineStateFault : @"Fault: system wallpaper shown",
    };
    if (![state isKindOfClass:[NSString class]]) return [HACPreferences loadSettings].enabled ? @"Respring needed" : @"Off";
    return titles[state] ?: state;
}

- (NSString *)surfaceStatus:(NSString *)key field:(NSString *)field {
    NSDictionary *surface = [self status][key];
    id value = [surface isKindOfClass:[NSDictionary class]] ? surface[field] : nil;
    return [value isKindOfClass:[NSString class]] && [value length] ? value : @"—";
}

- (NSString *)homeRendering:(PSSpecifier *)specifier {
    return [self surfaceStatus:HACStatusKeyHome field:HACSurfaceStatusKeyRendering];
}

- (NSString *)lockRendering:(PSSpecifier *)specifier {
    return [self surfaceStatus:HACStatusKeyLock field:HACSurfaceStatusKeyRendering];
}

- (NSString *)backgroundName:(HACSurface)surface {
    HACSettings *settings = [HACPreferences loadSettings];
    HCGBackgroundPreset *preset = [settings presetForSurface:surface];
    NSString *problem = surface == HACSurfaceLock ? settings.lockPresetProblem : settings.homePresetProblem;
    if (problem.length) return @"Invalid (choose again)";
    if (!preset) return @"None (system wallpaper)";
    if (surface == HACSurfaceLock && settings.lockSameAsHome) return [NSString stringWithFormat:@"%@ (same as Home)", preset.name];
    return preset.name;
}

- (NSString *)homeBackground:(PSSpecifier *)specifier {
    return [self backgroundName:HACSurfaceHome];
}

- (NSString *)lockBackground:(PSSpecifier *)specifier {
    return [self backgroundName:HACSurfaceLock];
}

- (NSString *)environmentStatus:(PSSpecifier *)specifier {
    id value = [self status][HACStatusKeyEnvironment];
    return [value isKindOfClass:[NSString class]] ? value : @"Not reported yet";
}

- (NSString *)versionString:(PSSpecifier *)specifier {
    return [NSString stringWithFormat:@"%s (%s)", HAC_VERSION, HAC_BUILD_ID];
}

#pragma mark Actions

- (void)hac_pushPage:(UIViewController *)controller {
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openLibrary:(PSSpecifier *)specifier {
    HACLibraryViewController *library = [[HACLibraryViewController alloc] initBrowsing];
    __weak HACRootListController *weakSelf = self;
    library.onChange = ^{
        [weakSelf reloadSpecifiers];
        [weakSelf requestStatusSoon];
    };
    [self hac_pushPage:library];
}

- (void)chooseSurface:(HACSurface)surface {
    HACLibraryViewController *library = [[HACLibraryViewController alloc] initChoosingForSurface:surface];
    __weak HACRootListController *weakSelf = self;
    library.onChange = ^{
        [weakSelf reloadSpecifiers];
        [weakSelf requestStatusSoon];
    };
    [self hac_pushPage:library];
}

- (void)chooseHome:(PSSpecifier *)specifier {
    [self chooseSurface:HACSurfaceHome];
}

- (void)chooseLock:(PSSpecifier *)specifier {
    [self chooseSurface:HACSurfaceLock];
}

- (void)openAI:(PSSpecifier *)specifier {
    HACAIViewController *ai = [[HACAIViewController alloc] init];
    __weak HACRootListController *weakSelf = self;
    ai.onChange = ^{
        [weakSelf reloadSpecifiers];
    };
    [self hac_pushPage:ai];
}

- (void)restoreSystemWallpaper:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Restore System Wallpaper?"
                         message:@"HCG Animation Center turns off and your normal Home Screen and Lock Screen wallpaper "
                                 @"shows at once. Your library and choices are kept; turn it on again any time."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [HACPreferences setValue:@NO forKey:HACKeyEnabled];
                                                [self reloadSpecifiers];
                                                [self requestStatusSoon];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)writeProbe:(PSSpecifier *)specifier {
    notify_post(HACProbeRequestNotification.UTF8String);
    [self requestStatusSoon];
}

#pragma mark Lifecycle and styling

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HCG Animation Center";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.tintColor = HACAccentColor();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startObservingStatus];
    [self reloadSpecifiers];
    [self requestStatusSoon];
    UINavigationBar *bar = self.navigationController.navigationBar;
    _previousNavigationTint = bar.tintColor;
    bar.tintColor = HACAccentColor();
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Pushed pages keep the accent; leaving HCG Animation Center restores Settings' own tint.
    if (!self.navigationController || ![self.navigationController.viewControllers containsObject:self])
        self.navigationController.navigationBar.tintColor = _previousNavigationTint;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.navigationController || ![self.navigationController.viewControllers containsObject:self])
        [self stopObservingStatus];
}

- (void)startObservingStatus {
    if (_observingStatus) return;
    _observingStatus = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                    HACStatusUpdated, (__bridge CFStringRef)HACStatusUpdatedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)stopObservingStatus {
    if (!_observingStatus) return;
    _observingStatus = NO;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       (__bridge CFStringRef)HACStatusUpdatedNotification, NULL);
}

/// Asks SpringBoard to report; it answers with HACStatusUpdatedNotification.
- (void)requestStatusSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post(HACStatusRequestNotification.UTF8String);
    });
}

- (void)statusUpdated {
    [self reloadSpecifiers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:[PSControlTableCell class]]) {
        UIControl *control = ((PSControlTableCell *)cell).control;
        if ([control isKindOfClass:[UISwitch class]]) ((UISwitch *)control).onTintColor = HACAccentColor();
    }
    NSString *identifier = [self specifierAtIndexPath:indexPath].identifier;
    if ([@[ @"chooseHome", @"chooseLock", @"openLibrary", @"openAI" ] containsObject:identifier]) {
        cell.textLabel.textColor = UIColor.labelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
    } else if ([identifier isEqualToString:@"restoreSystemWallpaper"]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else if ([@[ @"homeRendering", @"lockRendering", @"environment", @"engineStatus" ] containsObject:identifier]) {
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.55;
    }
    return cell;
}

@end

static void HACStatusUpdated(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                             CFDictionaryRef userInfo) {
    HACRootListController *controller = (__bridge HACRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller statusUpdated];
    });
}
