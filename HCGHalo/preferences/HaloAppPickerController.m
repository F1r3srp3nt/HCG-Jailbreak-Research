//
//  HaloAppPickerController.m
//  HCG Halo — Hakmi Capital Group
//
//  LaunchServices is private API: every call is guarded and the list is
//  read-only. If neither enumeration works, the page says so and offers the
//  manual entry instead of an empty list.
//

#import "HaloAppPickerController.h"
#import "HaloPreferences.h"
#import "HaloTheme.h"

#import <objc/message.h>

static NSString *const kCellID = @"HaloAppCell";

typedef NS_ENUM(NSInteger, HaloPickerSection) {
    HaloPickerSectionChosen = 0,
    HaloPickerSectionApps,
    HaloPickerSectionManual,
    HaloPickerSectionCount,
};

@interface UIImage (HaloPrivateIcons)
+ (nullable UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@interface HaloAppPickerController () <UISearchResultsUpdating>
@end

@implementation HaloAppPickerController {
    NSArray<NSDictionary<NSString *, NSString *> *> *_apps;
    NSArray<NSDictionary<NSString *, NSString *> *> *_filtered;
    UISearchController *_search;
    NSCache<NSString *, UIImage *> *_icons;
}

#pragma mark Installed apps (LaunchServices, read-only)

static id HaloSend(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)(target, sel);
}

static NSString *HaloString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

/// One LSApplicationProxy / LSApplicationRecord → entry, or nil if it should not be listed.
static NSDictionary<NSString *, NSString *> *HaloEntry(id app) {
    NSString *identifier = HaloString(HaloSend(app, @"bundleIdentifier")) ?: HaloString(HaloSend(app, @"applicationIdentifier"));
    if (!identifier.length || ![[HaloPreferences sanitizedBundleIdentifier:identifier] isEqualToString:identifier]) return nil;
    NSArray *tags = HaloSend(app, @"appTags");
    if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) return nil; // not on the Home Screen
    id prohibited = HaloSend(app, @"isLaunchProhibited");
    if ([prohibited isKindOfClass:[NSNumber class]] && [prohibited boolValue]) return nil;
    NSString *name = HaloString(HaloSend(app, @"localizedName")) ?: HaloString(HaloSend(app, @"itemName"));
    if (!name.length) return nil;
    return @{@"id" : identifier, @"name" : name};
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    NSMutableDictionary<NSString *, NSDictionary *> *found = [NSMutableDictionary dictionary];
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        id workspace = HaloSend(workspaceClass, @"defaultWorkspace");
        NSArray *apps = HaloSend(workspace, @"allInstalledApplications") ?: HaloSend(workspace, @"allApplications");
        if ([apps isKindOfClass:[NSArray class]]) {
            for (id app in apps) {
                NSDictionary *entry = HaloEntry(app);
                if (entry) found[entry[@"id"]] = entry;
            }
        }
        if (!found.count) {
            // iOS 14+: LSApplicationRecord enumeration.
            Class recordClass = NSClassFromString(@"LSApplicationRecord");
            SEL enumerator = NSSelectorFromString(@"enumeratorWithOptions:");
            if ([recordClass respondsToSelector:enumerator]) {
                id records = ((id(*)(id, SEL, NSUInteger))objc_msgSend)(recordClass, enumerator, 0);
                if ([records conformsToProtocol:@protocol(NSFastEnumeration)]) {
                    for (id record in records) {
                        NSDictionary *entry = HaloEntry(record);
                        if (entry) found[entry[@"id"]] = entry;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // Private API changed: the manual entry remains.
    }
    return [found.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        return r != NSOrderedSame ? r : [a[@"id"] compare:b[@"id"]];
    }];
}

+ (NSString *)nameForBundleIdentifier:(NSString *)identifier {
    if (!identifier.length) return nil;
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([proxyClass respondsToSelector:sel]) {
            id proxy = ((id(*)(id, SEL, id))objc_msgSend)(proxyClass, sel, identifier);
            id installed = HaloSend(proxy, @"isInstalled");
            if ([installed isKindOfClass:[NSNumber class]] && ![installed boolValue]) return nil;
            NSString *name = HaloString(HaloSend(proxy, @"localizedName"));
            if (name.length) return name;
        }
    } @catch (NSException *exception) {
    }
    for (NSDictionary *app in [self installedApps])
        if ([app[@"id"] isEqualToString:identifier]) return app[@"name"];
    return nil;
}

#pragma mark Lifecycle

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chosen App";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [HaloTheme styleTableView:self.tableView];
    _icons = [[NSCache alloc] init];
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"Search apps";
    _search.searchBar.tintColor = HaloTheme.cyan;
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    _apps = [HaloAppPickerController installedApps];
    _filtered = _apps;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) {
        _filtered = _apps;
    } else {
        NSPredicate *match = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR id CONTAINS[cd] %@", query, query];
        _filtered = [_apps filteredArrayUsingPredicate:match];
    }
    [self.tableView reloadData];
}

#pragma mark Table

- (NSString *)chosen {
    return [HaloPreferences loadSettings].showOnApp;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return HaloPickerSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case HaloPickerSectionChosen: return 1;
    case HaloPickerSectionApps: return MAX((NSInteger)_filtered.count, 1);
    default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case HaloPickerSectionChosen: return @"Selected App Only";
    case HaloPickerSectionApps: return @"Installed Apps";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case HaloPickerSectionChosen:
        return @"The screen-edge border shows only while this app is in front and the phone is unlocked and lit. "
               @"Choosing an app also selects Selected App Only. It applies immediately.";
    case HaloPickerSectionApps:
        return _apps.count ? nil
                           : @"This iOS version did not return the installed apps. Use Enter Bundle ID below.";
    default:
        return @"For an app that is not listed: its bundle identifier, e.g. com.apple.mobilesafari.";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
    [HaloTheme styleCell:cell];
    cell.textLabel.textColor = HaloTheme.textPrimary;
    cell.detailTextLabel.textColor = HaloTheme.textSecondary;
    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    NSString *chosen = [self chosen];
    switch (indexPath.section) {
    case HaloPickerSectionChosen: {
        HaloSettings *settings = [HaloPreferences loadSettings];
        if (chosen.length) {
            NSString *name = [HaloAppPickerController nameForBundleIdentifier:chosen];
            cell.textLabel.text = name ?: (settings.showOnAppName.length ? settings.showOnAppName : chosen);
            cell.detailTextLabel.text = name ? chosen : [NSString stringWithFormat:@"%@ · not installed", chosen];
            cell.imageView.image = [self iconFor:chosen];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessibilityTraits = UIAccessibilityTraitStaticText;
        } else {
            cell.textLabel.text = @"No app chosen";
            cell.textLabel.textColor = HaloTheme.textSecondary;
            cell.detailTextLabel.text = @"Choose one below.";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessibilityTraits = UIAccessibilityTraitStaticText;
        }
        break;
    }
    case HaloPickerSectionApps: {
        if (!_filtered.count) {
            cell.textLabel.text = _apps.count ? @"No matching apps" : @"No apps returned";
            cell.textLabel.textColor = HaloTheme.textSecondary;
            cell.detailTextLabel.text = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessibilityTraits = UIAccessibilityTraitStaticText;
            break;
        }
        NSDictionary *app = _filtered[indexPath.row];
        cell.textLabel.text = app[@"name"];
        cell.detailTextLabel.text = app[@"id"];
        cell.imageView.image = [self iconFor:app[@"id"]];
        BOOL selected = [app[@"id"] isEqualToString:chosen];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        if (selected) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
        break;
    }
    default:
        cell.textLabel.text = @"Enter Bundle ID…";
        cell.textLabel.textColor = HaloTheme.cyan;
        cell.detailTextLabel.text = nil;
        break;
    }
    return cell;
}

- (UIImage *)iconFor:(NSString *)identifier {
    UIImage *cached = [_icons objectForKey:identifier];
    if (cached) return cached;
    UIImage *icon = nil;
    @try {
        if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
            icon = [UIImage _applicationIconImageForBundleIdentifier:identifier format:0 scale:UIScreen.mainScreen.scale];
    } @catch (NSException *exception) {
        icon = nil;
    }
    if (icon) [_icons setObject:icon forKey:identifier];
    return icon;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:NO];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == HaloPickerSectionChosen) return nil;
    if (indexPath.section == HaloPickerSectionApps && !_filtered.count) return nil;
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == HaloPickerSectionApps && indexPath.row < (NSInteger)_filtered.count) {
        NSDictionary *app = _filtered[indexPath.row];
        [self choose:app[@"id"] name:app[@"name"]];
    } else if (indexPath.section == HaloPickerSectionManual) {
        [self enterBundleIdentifier];
    }
}

- (void)choose:(NSString *)identifier name:(NSString *)name {
    [HaloPreferences writeValues:@{
        HaloKeyShowOnApp : identifier,
        HaloKeyShowOnAppName : name ?: @"",
        HaloKeyShowOn : @"app",
    }];
    [HaloPreferences postChangeNotification];
    [self.tableView reloadData];
}

- (void)enterBundleIdentifier {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Bundle ID"
                                                                   message:@"The app's bundle identifier."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"com.example.app";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = UIKeyboardTypeASCIICapable;
        field.text = [self chosen];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak HaloAppPickerController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Choose"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                NSString *text = [weakAlert.textFields.firstObject.text
                                                    stringByTrimmingCharactersInSet:[NSCharacterSet
                                                                                        whitespaceAndNewlineCharacterSet]];
                                                NSString *identifier = [HaloPreferences sanitizedBundleIdentifier:text];
                                                if (!identifier.length) {
                                                    [weakSelf showInvalid:text];
                                                    return;
                                                }
                                                [weakSelf choose:identifier
                                                            name:[HaloAppPickerController nameForBundleIdentifier:identifier]];
                                            }]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showInvalid:(NSString *)text {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Not a Bundle ID"
                                             message:@"Use letters, digits, dots, hyphens and underscores, e.g. "
                                                     @"com.apple.mobilesafari. Nothing was changed."
                                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

@end
