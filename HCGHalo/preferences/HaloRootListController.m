//
//  HaloRootListController.m
//  HCG Halo — Hakmi Capital Group
//
//  Native Settings pane. Works whether or not the SpringBoard side is
//  loaded: every read and write goes straight to CFPreferences through the
//  shared HaloPreferences validator, and SpringBoard is only notified.
//  Status comes from SpringBoard on request (HaloStatusRequestNotification),
//  so what this page shows is what SpringBoard last reported, with its time.
//

#import "HaloRootListController.h"
#import "HaloColoursController.h"
#import "HaloHeaderView.h"
#import "HaloNexusBorderController.h"
#import "HaloNexusDefinition.h"
#import "HaloPreferences.h"
#import "HaloPresetsController.h"
#import "HaloProfileController.h"
#import "HaloTheme.h"

#import <Preferences/PSControlTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <notify.h>

@implementation HaloRootListController {
    HaloHeaderView *_header;
    UIColor *_previousNavigationTint;
    BOOL _observingStatus;
}

static void HaloStatusUpdated(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                              CFDictionaryRef userInfo) {
    HaloRootListController *controller = (__bridge HaloRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadSpecifiers];
    });
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
    // Whether or not PSListController re-reads -specifiers, footers are fresh.
    if (_specifiers) [self applyDynamicText];
    [super reloadSpecifiers];
    [_header reloadWithSettings:[HaloPreferences loadSettings]];
}

/// Footers whose text depends on the current status and profile.
- (void)applyDynamicText {
    NSDictionary *status = [HaloPreferences readStatus];
    HaloSettings *settings = [HaloPreferences loadSettings];

    PSSpecifier *detailGroup = [self specifierForID:@"statusDetailGroup"];
    NSMutableArray *lines = [NSMutableArray array];
    NSString *detail = status[HaloStatusKeyDetail];
    if ([detail isKindOfClass:[NSString class]] && detail.length) [lines addObject:detail];
    NSString *match = status[HaloStatusKeyProfileMatch];
    if ([match isKindOfClass:[NSString class]] && match.length) [lines addObject:match];
    NSDate *when = status[HaloStatusKeyTimestamp];
    NSString *reportedVersion = status[HaloStatusKeyTweakVersion];
    if ([when isKindOfClass:[NSDate class]]) {
        NSString *time = [NSDateFormatter localizedStringFromDate:when
                                                        dateStyle:NSDateFormatterShortStyle
                                                        timeStyle:NSDateFormatterMediumStyle];
        [lines addObject:[NSString stringWithFormat:@"Reported by SpringBoard at %@.", time]];
    } else {
        [lines addObject:@"SpringBoard has not reported yet. If you just installed HCG Halo, respring."];
    }
    if ([reportedVersion isKindOfClass:[NSString class]] && reportedVersion.length &&
        ![reportedVersion isEqualToString:@HALO_VERSION]) {
        [lines addObject:[NSString stringWithFormat:@"SpringBoard is running %@ but %s is installed: respring.",
                                                    reportedVersion, HALO_VERSION]];
    }
    [detailGroup setProperty:[lines componentsJoinedByString:@"\n\n"] forKey:@"footerText"];

    PSSpecifier *profileGroup = [self specifierForID:@"profileGroup"];
    const HaloProfile *profile = settings.profile;
    NSString *profileText;
    if (profile) {
        profileText = [NSString stringWithFormat:@"Selected: %s — %s.", profile->name,
                                                 profile->deviceTested ? "implemented and device-tested"
                                                                       : "implemented, not yet device-tested"];
    } else {
        profileText = @"No implemented profile is selected.";
    }
    NSString *screen = status[HaloStatusKeyScreen];
    if ([screen isKindOfClass:[NSString class]] && screen.length)
        profileText = [profileText stringByAppendingFormat:@"\nThis screen: %@.", screen];
    [profileGroup setProperty:profileText forKey:@"footerText"];

    // Border target: whether a compatible HCG Nexus is installed (its own
    // definition file, next to this bundle) and what SpringBoard reports.
    PSSpecifier *targetGroup = [self specifierForID:@"targetGroup"];
    NSString *path = [HaloNexusDefinition installedPathNextToBundle:[NSBundle bundleForClass:[self class]]];
    NSString *error = nil;
    HaloNexusDefinition *definition = path ? [HaloNexusDefinition definitionAtPath:path error:&error] : nil;
    NSMutableArray *targetLines = [NSMutableArray array];
    [targetLines addObject:@"Screen Edge is the default. HCG Nexus Panel draws the border around the HCG Nexus panel "
                           @"while it is shown; Both draws both."];
    if (definition) {
        [targetLines addObject:[NSString stringWithFormat:@"HCG Nexus %@: compatible.", definition.nexusVersion]];
    } else {
        [targetLines addObject:[NSString stringWithFormat:@"Requires compatible HCG Nexus for the panel targets: %@. The "
                                                          @"screen edge is unaffected.",
                                                          error ?: @"not installed"]];
    }
    NSString *nexusDetail = status[HaloStatusKeyNexusDetail];
    if (settings.targetsNexus && [nexusDetail isKindOfClass:[NSString class]] && nexusDetail.length)
        [targetLines addObject:[NSString stringWithFormat:@"Panel border: %@", nexusDetail]];
    [targetGroup setProperty:[targetLines componentsJoinedByString:@"\n\n"] forKey:@"footerText"];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    return [HaloPreferences readValueForKey:key];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }
    [HaloPreferences writeValue:value forKey:key];
    // Changing the master switch is the user's explicit "try again" after the
    // launch guard stopped Halo; it takes effect at the next respring.
    if ([key isEqualToString:HaloKeyEnabled]) [HaloPreferences setConsecutiveUnstableLaunches:0];
    [HaloPreferences postChangeNotification];
    [_header reloadWithSettings:[HaloPreferences loadSettings]];
    if ([key isEqualToString:HaloKeyEnabled]) [self requestStatusSoon];
}

#pragma mark Lifecycle and styling

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HCG Halo";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UITableView *table = self.table;
    [HaloTheme styleTableView:table];
    _header = [[HaloHeaderView alloc] initWithWidth:CGRectGetWidth(table.bounds) ?: 375.0];
    table.tableHeaderView = _header;
    self.view.tintColor = HaloTheme.cyan;
    [_header reloadWithSettings:[HaloPreferences loadSettings]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startObservingStatus];
    [self reloadSpecifiers];
    [self requestStatusSoon];
    UINavigationBar *bar = self.navigationController.navigationBar;
    _previousNavigationTint = bar.tintColor;
    bar.tintColor = HaloTheme.cyan;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Never leave HCG colours on Settings' shared navigation bar.
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
                                    HaloStatusUpdated, (__bridge CFStringRef)HaloStatusUpdatedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)stopObservingStatus {
    if (!_observingStatus) return;
    _observingStatus = NO;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       (__bridge CFStringRef)HaloStatusUpdatedNotification, NULL);
}

/// Asks SpringBoard to report; it answers with HaloStatusUpdatedNotification.
- (void)requestStatusSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post(HaloStatusRequestNotification.UTF8String);
    });
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    [HaloTheme styleCell:cell];
    if ([cell isKindOfClass:[PSControlTableCell class]]) {
        UIControl *control = ((PSControlTableCell *)cell).control;
        if ([control isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)control).onTintColor = HaloTheme.cyan;
        } else if ([control isKindOfClass:[UISlider class]]) {
            UISlider *slider = (UISlider *)control;
            slider.minimumTrackTintColor = HaloTheme.cyan;
            slider.maximumTrackTintColor = [HaloTheme.deepViolet colorWithAlphaComponent:0.35];
        }
    }
    NSString *identifier = [self specifierAtIndexPath:indexPath].identifier;
    if ([@[ @"openPresets", @"openColours", @"openProfiles", @"openNexusBorder" ] containsObject:identifier]) {
        cell.textLabel.textColor = HaloTheme.textPrimary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
    } else if ([identifier isEqualToString:@"resetAppearance"] || [identifier isEqualToString:@"resetCalibration"]) {
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else if ([identifier isEqualToString:@"engineStatus"]) {
        cell.detailTextLabel.textColor = [self colourForEngineState];
    } else if ([identifier isEqualToString:@"renderingStatus"] || [identifier isEqualToString:@"displayContext"]) {
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.6;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayHeaderView:view forSection:section];
    [HaloTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayFooterView:view forSection:section];
    [HaloTheme styleHeaderFooterView:view header:NO];
}

#pragma mark Information cells

- (NSString *)versionString:(PSSpecifier *)specifier {
    return @HALO_VERSION;
}

- (NSString *)buildString:(PSSpecifier *)specifier {
    return @HALO_BUILD_ID;
}

- (NSString *)systemVersion:(PSSpecifier *)specifier {
    return [NSString stringWithFormat:@"iOS %@", [UIDevice currentDevice].systemVersion];
}

- (NSString *)displayContext:(PSSpecifier *)specifier {
    HaloSettings *settings = [HaloPreferences loadSettings];
    if (settings.target == HaloTargetNexus) return @"HCG Nexus panel only";
    if (settings.target == HaloTargetBoth) return @"Home Screen + HCG Nexus panel";
    return @"Home Screen only";
}

- (NSString *)engineStatus:(PSSpecifier *)specifier {
    NSString *state = [HaloPreferences readStatus][HaloStatusKeyState];
    if (![state isKindOfClass:[NSString class]] || !state.length) return @"Not reported (respring)";
    NSDictionary *labels = @{
        HaloEngineStateActive : @"Active",
        HaloEngineStateDisabled : @"Off",
        HaloEngineStateWaiting : @"Starting…",
        HaloEngineStateIncompatible : @"Incompatible: inactive",
        HaloEngineStateKillSwitch : @"Kill switch on",
        HaloEngineStateFault : @"Fault: removed",
        HaloEngineStateAutoDisabled : @"Auto-disabled",
    };
    return labels[state] ?: state;
}

- (NSString *)renderingStatus:(PSSpecifier *)specifier {
    NSString *rendering = [HaloPreferences readStatus][HaloStatusKeyRendering];
    return [rendering isKindOfClass:[NSString class]] && rendering.length ? rendering : @"—";
}

- (UIColor *)colourForEngineState {
    NSString *state = [HaloPreferences readStatus][HaloStatusKeyState];
    if ([state isEqualToString:HaloEngineStateActive]) return HaloTheme.cyan;
    if (![state isKindOfClass:[NSString class]] || !state.length || [state isEqualToString:HaloEngineStateDisabled] ||
        [state isEqualToString:HaloEngineStateWaiting])
        return HaloTheme.textSecondary;
    return HaloTheme.warning;
}

#pragma mark Navigation

- (void)push:(UIViewController *)controller {
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)openPresets:(PSSpecifier *)specifier {
    [self push:[[HaloPresetsController alloc] init]];
}

- (void)openColours:(PSSpecifier *)specifier {
    [self push:[[HaloColoursController alloc] init]];
}

- (void)openProfiles:(PSSpecifier *)specifier {
    [self push:[[HaloProfileController alloc] init]];
}

- (void)openNexusBorder:(PSSpecifier *)specifier {
    [self push:[[HaloNexusBorderController alloc] init]];
}

#pragma mark Actions

- (void)confirmWithTitle:(NSString *)title
                 message:(NSString *)message
             actionTitle:(NSString *)actionTitle
                 handler:(void (^)(void))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                handler();
                                            }]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetAppearance:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Reset Appearance"
                   message:@"Return mode, colours, brightness, thickness, glow, inset and animation to the defaults? Your "
                           @"presets, device profile, calibration and the Enable switch are kept."
               actionTitle:@"Reset"
                   handler:^{
                       [HaloPreferences resetAppearance];
                       [HaloPreferences postChangeNotification];
                       [self reloadSpecifiers];
                   }];
}

- (void)resetCalibration:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Reset Calibration"
                   message:@"Set the four calibration values back to 0? Nothing else changes."
               actionTitle:@"Reset"
                   handler:^{
                       [HaloPreferences resetCalibration];
                       [HaloPreferences postChangeNotification];
                       [self reloadSpecifiers];
                   }];
}

@end
