//
//  PortalRootListController.m
//  HCG Portal — Hakmi Capital Group
//
//  Native Settings pane. Works whether or not the SpringBoard side is loaded:
//  every read and write goes to CFPreferences through the shared validator
//  (PortalPreferences), and SpringBoard is only notified. Status comes from
//  SpringBoard on request, so what this page shows is what SpringBoard last
//  reported, with its time. (Structure follows HCG Halo's root pane.)
//

#import "PortalRootListController.h"

#import "PortalAppsController.h"
#import "PortalCompanions.h"
#import "PortalPlacementController.h"
#import "PortalPreferences.h"
#import "PortalPreviewView.h"
#import "PortalTheme.h"

#import <Preferences/PSControlTableCell.h>
#import <Preferences/PSSpecifier.h>
#include <notify.h>

@implementation PortalRootListController {
    PortalPreviewView *_header;
    UIView *_headerContainer;
    UIColor *_previousNavigationTint;
    BOOL _observingStatus;
}

static void PortalStatusUpdated(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                CFDictionaryRef userInfo) {
    PortalRootListController *controller = (__bridge PortalRootListController *)observer;
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
    if (_specifiers) [self applyDynamicText];
    [super reloadSpecifiers];
    [_header reloadWithSettings:[PortalPreferences loadSettings]];
}

- (void)applyDynamicText {
    NSDictionary *status = [PortalPreferences readStatus];
    NSMutableArray *lines = [NSMutableArray array];
    NSString *detail = status[PortalStatusKeyDetail];
    if ([detail isKindOfClass:[NSString class]] && detail.length) [lines addObject:detail];
    for (NSString *key in @[ PortalStatusKeyAccess, PortalStatusKeyLayout, PortalStatusKeyPlan, PortalStatusKeyLastAction,
                             PortalStatusKeyHost, PortalStatusKeyTouch, PortalStatusKeyPhase, PortalStatusKeyPreviousSession ]) {
        NSString *v = status[key];
        if (![v isKindOfClass:[NSString class]] || !v.length) continue;
        NSString *label = [key isEqualToString:PortalStatusKeyAccess]   ? @"iPhone lock state"
                          : [key isEqualToString:PortalStatusKeyLayout] ? @"Layout"
                          : [key isEqualToString:PortalStatusKeyPlan]   ? @"Rendering"
                          : [key isEqualToString:PortalStatusKeyHost]   ? @"Cover Sheet container"
                          : [key isEqualToString:PortalStatusKeyTouch]  ? @"Touches"
                          : [key isEqualToString:PortalStatusKeyPhase]  ? @"Breadcrumb"
                          : [key isEqualToString:PortalStatusKeyPreviousSession] ? @"Diagnostics"
                                                                        : @"Last action";
        [lines addObject:[NSString stringWithFormat:@"%@: %@", label, v]];
    }
    NSDate *when = status[PortalStatusKeyTimestamp];
    if ([when isKindOfClass:[NSDate class]]) {
        NSString *time = [NSDateFormatter localizedStringFromDate:when
                                                        dateStyle:NSDateFormatterShortStyle
                                                        timeStyle:NSDateFormatterMediumStyle];
        [lines addObject:[NSString stringWithFormat:@"Reported by SpringBoard at %@. Settings is an app, so SpringBoard "
                                                    @"reports the Cover Sheet as hidden while you look at this page.",
                                                    time]];
    } else {
        [lines addObject:@"SpringBoard has not reported yet. If you just installed HCG Portal, respring."];
    }
    NSString *reportedVersion = status[PortalStatusKeyTweakVersion];
    if ([reportedVersion isKindOfClass:[NSString class]] && reportedVersion.length &&
        ![reportedVersion isEqualToString:@PORTAL_VERSION])
        [lines addObject:[NSString stringWithFormat:@"SpringBoard is running %@ but %s is installed: respring.",
                                                    reportedVersion, PORTAL_VERSION]];
    [[self specifierForID:@"statusDetailGroup"] setProperty:[lines componentsJoinedByString:@"\n\n"] forKey:@"footerText"];

    NSMutableArray *dest = [NSMutableArray array];
    [dest addObject:@"Portal works on its own. Companions are optional and found automatically; Portal never changes "
                    @"their settings."];
    [dest addObject:@"Nexus opens the HCG Nexus panel once HCG Nexus offers Portal's open interface (not in HCG Nexus "
                    @"0.3.1~beta1). Backgrounds opens Settings for HCG Animation Center. Devices shows Not connected "
                    @"until Connector and Origin exist. Every destination asks for Face ID, Touch ID or your passcode "
                    @"first; cancelling opens nothing."];
    [[self specifierForID:@"destinationsGroup"] setProperty:[dest componentsJoinedByString:@"\n\n"] forKey:@"footerText"];

    PortalSettings *settings = [PortalPreferences loadSettings];
    PSSpecifier *apps = [self specifierForID:@"openApps"];
    [apps setName:settings.apps.count ? [NSString stringWithFormat:@"HCG Apps (%lu)", (unsigned long)settings.apps.count]
                                      : @"HCG Apps: Choose…"];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    id value = [PortalPreferences valueForKey:key];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }
    [PortalPreferences setValue:value forKey:key];
    // Turning Enable off and on is the explicit "try again" after the launch guard.
    if ([key isEqualToString:PortalKeyEnabled]) {
        [PortalPreferences setConsecutiveUnstableLaunches:0];
        [self requestStatusSoon];
    }
    [_header reloadWithSettings:[PortalPreferences loadSettings]];
}

#pragma mark Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HCG Portal";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UITableView *table = self.table;
    [PortalTheme styleTableView:table];
    CGFloat width = CGRectGetWidth(table.bounds) ?: 375.0;
    _headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 250)];
    _header = [[PortalPreviewView alloc] initWithFrame:CGRectZero];
    CGSize s = _header.screenSize;
    CGFloat h = 226, w = h * s.width / s.height;
    _header.frame = CGRectMake((width - w) / 2, 12, w, h);
    _header.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_headerContainer addSubview:_header];
    table.tableHeaderView = _headerContainer;
    self.view.tintColor = PortalTheme.cyan;
    [_header reloadWithSettings:[PortalPreferences loadSettings]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startObservingStatus];
    [self reloadSpecifiers];
    [self requestStatusSoon];
    UINavigationBar *bar = self.navigationController.navigationBar;
    _previousNavigationTint = bar.tintColor;
    bar.tintColor = PortalTheme.cyan;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
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
                                    PortalStatusUpdated, (__bridge CFStringRef)PortalStatusUpdatedNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)stopObservingStatus {
    if (!_observingStatus) return;
    _observingStatus = NO;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       (__bridge CFStringRef)PortalStatusUpdatedNotification, NULL);
}

- (void)requestStatusSoon {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        notify_post(PortalStatusRequestNotification.UTF8String);
    });
}

#pragma mark Styling

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    [PortalTheme styleCell:cell];
    if ([cell isKindOfClass:[PSControlTableCell class]]) {
        UIControl *control = ((PSControlTableCell *)cell).control;
        if ([control isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)control).onTintColor = PortalTheme.cyan;
        } else if ([control isKindOfClass:[UISlider class]]) {
            UISlider *slider = (UISlider *)control;
            slider.minimumTrackTintColor = PortalTheme.cyan;
            slider.maximumTrackTintColor = [PortalTheme.deepViolet colorWithAlphaComponent:0.35];
        }
    }
    NSString *identifier = [self specifierAtIndexPath:indexPath].identifier;
    if ([@[ @"openPlacement", @"openApps" ] containsObject:identifier]) {
        cell.textLabel.textColor = PortalTheme.textPrimary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityTraits |= UIAccessibilityTraitButton;
    } else if ([@[ @"resetAppearance", @"resetAll" ] containsObject:identifier]) {
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else if ([identifier isEqualToString:@"engineStatus"]) {
        cell.detailTextLabel.textColor = [self colourForEngineState];
    } else if ([@[ @"nexusStatus", @"backgroundsStatus", @"devicesStatus", @"visibilityStatus" ] containsObject:identifier]) {
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.minimumScaleFactor = 0.7;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayHeaderView:view forSection:section];
    [PortalTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayFooterView:view forSection:section];
    [PortalTheme styleHeaderFooterView:view header:NO];
}

#pragma mark Information cells

- (NSString *)versionString:(PSSpecifier *)specifier {
    return @PORTAL_VERSION;
}

- (NSString *)buildString:(PSSpecifier *)specifier {
    return @PORTAL_BUILD_ID;
}

- (NSString *)systemVersion:(PSSpecifier *)specifier {
    return [NSString stringWithFormat:@"iOS %@", [UIDevice currentDevice].systemVersion];
}

- (NSString *)engineStatus:(PSSpecifier *)specifier {
    NSString *state = [PortalPreferences readStatus][PortalStatusKeyState];
    if (![state isKindOfClass:[NSString class]] || !state.length) return @"Not reported (respring)";
    NSDictionary *labels = @{
        PortalEngineStateActive : @"Active",
        PortalEngineStateDisabled : @"Off",
        PortalEngineStateWaiting : @"Starting…",
        PortalEngineStateIncompatible : @"Incompatible: inactive",
        PortalEngineStateKillSwitch : @"Kill switch on",
        PortalEngineStateFault : @"Fault: removed",
        PortalEngineStateAutoDisabled : @"Auto-disabled",
    };
    return labels[state] ?: state;
}

- (NSString *)visibilityStatus:(PSSpecifier *)specifier {
    NSString *state = [PortalPreferences readStatus][PortalStatusKeyState];
    // Enabled but not running (hook API missing, incompatible, kill switch, auto-disabled, fault):
    // say so rather than "Off", which would contradict the Enable switch.
    if ([state isKindOfClass:[NSString class]] && state.length && ![state isEqualToString:PortalEngineStateActive] &&
        ![state isEqualToString:PortalEngineStateDisabled] && ![state isEqualToString:PortalEngineStateWaiting])
        return @"Not shown (inactive)";
    NSString *v = [PortalPreferences readStatus][PortalStatusKeyVisibility];
    if (![v isKindOfClass:[NSString class]] || !v.length) return @"—";
    NSDictionary *labels = @{
        @"visible" : @"Shown",
        @"disabled" : @"Off",
        @"kill-switch" : @"Kill switch",
        @"fault" : @"Removed after a fault",
        @"locked" : @"Hidden: iPhone locked",
        @"no-host" : @"Cover Sheet not found",
        @"screen-off" : @"Paused: screen off",
        @"not-cover-sheet" : @"Hidden: Cover Sheet closed",
        @"opening" : @"Hidden: opening",
        @"no-room" : @"Hidden: no room",
        @"low-power-hidden" : @"Hidden: Low Power Mode",
    };
    return labels[v] ?: v;
}

- (NSString *)nexusStatus:(PSSpecifier *)specifier {
    if (![PortalCompanions nexusInstalled]) return @"HCG Nexus not installed";
    return @"Installed: needs Nexus update";
}

- (NSString *)backgroundsStatus:(PSSpecifier *)specifier {
    return [PortalCompanions animationCenterInstalled] ? @"HCG Animation Center (via Settings)" : @"Animation Center not installed";
}

- (NSString *)devicesStatus:(PSSpecifier *)specifier {
    return @"Not connected";
}

- (UIColor *)colourForEngineState {
    NSString *state = [PortalPreferences readStatus][PortalStatusKeyState];
    if ([state isEqualToString:PortalEngineStateActive]) return PortalTheme.cyan;
    if (![state isKindOfClass:[NSString class]] || !state.length || [state isEqualToString:PortalEngineStateDisabled] ||
        [state isEqualToString:PortalEngineStateWaiting])
        return PortalTheme.textSecondary;
    return PortalTheme.warning;
}

#pragma mark Navigation and actions

- (void)openPlacement:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[[PortalPlacementController alloc] init] animated:YES];
}

- (void)openApps:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[[PortalAppsController alloc] init] animated:YES];
}

- (void)confirmWithTitle:(NSString *)title message:(NSString *)message handler:(void (^)(void))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                handler();
                                            }]];
    alert.view.tintColor = PortalTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetAppearance:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Reset Appearance"
                   message:@"Return colour, brightness, animation speed and intensity to the defaults? Position, size "
                           @"and your apps are kept."
                   handler:^{
                       [PortalPreferences removeKeys:[PortalPreferences appearanceKeys]];
                       [self reloadSpecifiers];
                   }];
}

- (void)resetAll:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Reset All HCG Portal Settings"
                   message:@"Turn HCG Portal off and return every HCG Portal setting, including your chosen apps, to "
                           @"the defaults? Other apps and tweaks are not affected."
                   handler:^{
                       NSMutableArray *keys = [NSMutableArray arrayWithArray:[PortalPreferences appearanceKeys]];
                       [keys addObjectsFromArray:[PortalPreferences placementKeys]];
                       [keys addObjectsFromArray:@[
                           PortalKeyEnabled, PortalKeyUnlockAnimation, PortalKeyLowPower, PortalKeyApps,
                           PortalKeyDiagnosticLogging
                       ]];
                       [PortalPreferences removeKeys:keys];
                       [PortalPreferences setConsecutiveUnstableLaunches:0];
                       [self reloadSpecifiers];
                       [self requestStatusSoon];
                   }];
}

@end
