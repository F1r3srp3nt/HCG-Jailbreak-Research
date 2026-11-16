//
//  VortexRootListController.m
//  HCG Vortex — Hakmi Capital Group
//
//  Native Settings pane. Works whether or not the SpringBoard side is
//  loaded: every read/write goes straight to CFPreferences through the shared
//  VortexPreferences validator, and SpringBoard is only *notified*.
//

#import "VortexRootListController.h"
#import "VortexHeaderView.h"
#import "VortexPreferences.h"

#import <Preferences/PSControlTableCell.h>
#import <Preferences/PSSpecifier.h>

#ifndef VORTEX_VERSION
#define VORTEX_VERSION "0.1.0-alpha"
#endif

@implementation VortexRootListController {
    UIColor *_previousNavigationTint;
}

#pragma mark Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [super readPreferenceValue:specifier];
    return [VortexPreferences readValueForKey:key];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) {
        [super setPreferenceValue:value specifier:specifier];
        return;
    }
    [VortexPreferences writeValue:value forKey:key];
    // Changing the master switch is the user's explicit "try again" after the
    // launch guard auto-disabled Vortex; it takes effect at the next respring.
    if ([key isEqualToString:VortexKeyEnabled]) [VortexPreferences setConsecutiveUnstableLaunches:0];
    [VortexPreferences postChangeNotification];
}

#pragma mark Lifecycle / styling

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UITableView *table = self.table;
    table.backgroundColor = VortexTheme.background;
    table.separatorColor = [VortexTheme.purple colorWithAlphaComponent:0.25];
    table.tintColor = VortexTheme.cyan;
    table.tableHeaderView = [[VortexHeaderView alloc] initWithWidth:CGRectGetWidth(table.bounds) ?: 375.0];
    self.view.tintColor = VortexTheme.cyan;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh status cells (SpringBoard may have respringed meanwhile).
    [self reloadSpecifiers];
    UINavigationBar *bar = self.navigationController.navigationBar;
    _previousNavigationTint = bar.tintColor;
    bar.tintColor = VortexTheme.cyan;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Never leave our colours on Settings' shared navigation bar.
    self.navigationController.navigationBar.tintColor = _previousNavigationTint;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.backgroundColor = VortexTheme.panel;
    cell.textLabel.textColor = VortexTheme.textPrimary;
    cell.detailTextLabel.textColor = VortexTheme.textSecondary;
    cell.tintColor = VortexTheme.cyan;

    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [VortexTheme.purple colorWithAlphaComponent:0.28];
    cell.selectedBackgroundView = selected;

    if ([cell isKindOfClass:[PSControlTableCell class]]) {
        UIControl *control = ((PSControlTableCell *)cell).control;
        if ([control isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)control).onTintColor = VortexTheme.cyan;
        } else if ([control isKindOfClass:[UISlider class]]) {
            UISlider *slider = (UISlider *)control;
            slider.minimumTrackTintColor = VortexTheme.cyan;
            slider.maximumTrackTintColor = [VortexTheme.purple colorWithAlphaComponent:0.35];
        }
    }

    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *identifier = specifier.identifier;
    if ([identifier isEqualToString:@"resetPreferences"]) {
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else if ([identifier isEqualToString:@"restoreDefault"]) {
        cell.textLabel.textColor = VortexTheme.cyan;
    } else if ([identifier isEqualToString:@"engineStatus"]) {
        cell.detailTextLabel.textColor = [self colorForEngineState];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayHeaderView:view forSection:section];
    }
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        ((UITableViewHeaderFooterView *)view).textLabel.textColor = [UIColor colorWithRed:0.71 green:0.49 blue:1.0 alpha:1.0];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayFooterView:view forSection:section];
    }
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        ((UITableViewHeaderFooterView *)view).textLabel.textColor = VortexTheme.textSecondary;
    }
}

#pragma mark Information cells

- (NSString *)versionString:(PSSpecifier *)specifier {
    return @VORTEX_VERSION;
}

- (NSString *)engineStatus:(PSSpecifier *)specifier {
    NSDictionary *status = [VortexPreferences readStatus];
    NSString *state = status[VortexStatusKeyState];
    if (!state.length) return @"Not reported (respring)";
    NSDictionary *labels = @{
        @"active" : @"Active",
        @"disabled" : @"Loaded, disabled",
        @"incompatible" : @"Incompatible — stock",
        @"kill-switch" : @"Kill switch on",
        @"fault" : @"Fault — stock",
        @"auto-disabled" : @"Auto-disabled — stock",
    };
    return labels[state] ?: state;
}

- (NSString *)engineDetail:(PSSpecifier *)specifier {
    NSString *detail = [VortexPreferences readStatus][VortexStatusKeyDetail];
    return detail.length ? detail : @"—";
}

- (UIColor *)colorForEngineState {
    NSString *state = [VortexPreferences readStatus][VortexStatusKeyState];
    if ([state isEqualToString:@"active"]) return VortexTheme.cyan;
    if ([state isEqualToString:@"disabled"]) return VortexTheme.textSecondary;
    if (!state.length) return VortexTheme.textSecondary;
    return [UIColor systemOrangeColor];
}

- (NSString *)systemVersion:(PSSpecifier *)specifier {
    return [NSString stringWithFormat:@"iOS %@", [UIDevice currentDevice].systemVersion];
}

- (NSString *)compatibilityTarget:(PSSpecifier *)specifier {
    return @"iOS 17.4 · A13 · rootless";
}

#pragma mark Actions

- (void)confirmWithTitle:(NSString *)title
                 message:(NSString *)message
             actionTitle:(NSString *)actionTitle
             destructive:(BOOL)destructive
                 handler:(void (^)(void))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                handler();
                                            }]];
    alert.view.tintColor = VortexTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreDefaultBehavior:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Restore Default Behavior"
                   message:@"Switch to the stock iOS page animation? Your other HCG Vortex settings are kept."
               actionTitle:@"Restore"
               destructive:NO
                   handler:^{
                       [VortexPreferences writeValue:VortexEffectIdentifierStock forKey:VortexKeyPreset];
                       [VortexPreferences postChangeNotification];
                       [self reloadSpecifiers];
                   }];
}

- (void)resetPreferences:(PSSpecifier *)specifier {
    [self confirmWithTitle:@"Reset Preferences"
                   message:@"Erase every HCG Vortex setting and return to the defaults?"
               actionTitle:@"Reset"
               destructive:YES
                   handler:^{
                       [VortexPreferences resetAllValues];
                       [VortexPreferences setConsecutiveUnstableLaunches:0];
                       [VortexPreferences postChangeNotification];
                       [self reloadSpecifiers];
                   }];
}

@end
