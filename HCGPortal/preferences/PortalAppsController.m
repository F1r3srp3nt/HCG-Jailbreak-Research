//
//  PortalAppsController.m
//  HCG Portal — Hakmi Capital Group
//
//  LaunchServices is private API: every call is guarded and read-only
//  (adapted from HCG Halo's HaloAppPickerController, which was fixed for
//  BOOL-returning selectors).
//

#import "PortalAppsController.h"

#import "PortalPreferences.h"
#import "PortalTheme.h"

#import <objc/message.h>

static NSString *const kCellID = @"PortalAppCell";

typedef NS_ENUM(NSInteger, PortalAppsSection) {
    PortalAppsSectionChosen = 0,
    PortalAppsSectionHCG,
    PortalAppsSectionAll,
    PortalAppsSectionManual,
    PortalAppsSectionCount,
};

@interface UIImage (PortalPrivateIcons)
+ (nullable UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

@interface PortalAppsController () <UISearchResultsUpdating>
@end

@implementation PortalAppsController {
    NSArray<NSDictionary<NSString *, NSString *> *> *_apps;
    NSArray<NSDictionary<NSString *, NSString *> *> *_hcg;
    NSArray<NSDictionary<NSString *, NSString *> *> *_filtered;
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *_chosen;
    UISearchController *_search;
    NSCache<NSString *, UIImage *> *_icons;
}

#pragma mark Installed apps

static id PortalSend(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return nil;
    const char *type = [target methodSignatureForSelector:sel].methodReturnType;
    if (!type || type[0] != '@') return nil;
    return ((id(*)(id, SEL))objc_msgSend)(target, sel);
}

static BOOL PortalSendBool(id target, NSString *selector, BOOL *value) {
    SEL sel = NSSelectorFromString(selector);
    if (!target || ![target respondsToSelector:sel]) return NO;
    const char *type = [target methodSignatureForSelector:sel].methodReturnType;
    if (!type || (strcmp(type, @encode(BOOL)) != 0 && strcmp(type, @encode(bool)) != 0)) return NO;
    *value = ((BOOL(*)(id, SEL))objc_msgSend)(target, sel);
    return YES;
}

static NSString *PortalStringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary<NSString *, NSString *> *PortalEntry(id app) {
    NSString *identifier = PortalStringValue(PortalSend(app, @"bundleIdentifier")) ?: PortalStringValue(PortalSend(app, @"applicationIdentifier"));
    NSString *name = PortalStringValue(PortalSend(app, @"localizedName")) ?: PortalStringValue(PortalSend(app, @"itemName"));
    if (!identifier.length || !name.length) return nil;
    if (![PortalAppShortcut shortcutWithDictionary:@{@"id" : identifier, @"name" : name}]) return nil;
    NSArray *tags = PortalSend(app, @"appTags");
    if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) return nil;
    BOOL prohibited = NO;
    if (PortalSendBool(app, @"isLaunchProhibited", &prohibited) && prohibited) return nil;
    return @{@"id" : identifier, @"name" : name};
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    NSMutableDictionary<NSString *, NSDictionary *> *found = [NSMutableDictionary dictionary];
    @try {
        id workspace = PortalSend(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
        NSArray *apps = PortalSend(workspace, @"allInstalledApplications") ?: PortalSend(workspace, @"allApplications");
        if ([apps isKindOfClass:[NSArray class]]) {
            for (id app in apps) {
                NSDictionary *entry = PortalEntry(app);
                if (entry) found[entry[@"id"]] = entry;
            }
        }
        if (!found.count) {
            Class recordClass = NSClassFromString(@"LSApplicationRecord");
            SEL enumerator = NSSelectorFromString(@"enumeratorWithOptions:");
            if ([recordClass respondsToSelector:enumerator]) {
                id records = ((id(*)(id, SEL, NSUInteger))objc_msgSend)(recordClass, enumerator, 0);
                if ([records conformsToProtocol:@protocol(NSFastEnumeration)]) {
                    for (id record in records) {
                        NSDictionary *entry = PortalEntry(record);
                        if (entry) found[entry[@"id"]] = entry;
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // Private API changed: manual entry remains.
    }
    return [found.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        return r != NSOrderedSame ? r : [a[@"id"] compare:b[@"id"]];
    }];
}

#pragma mark Lifecycle

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HCG Apps";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [PortalTheme styleTableView:self.tableView];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    _icons = [[NSCache alloc] init];
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"Search apps";
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    _chosen = [NSMutableArray array];
    for (PortalAppShortcut *app in [PortalPreferences loadSettings].apps) [_chosen addObject:app.dictionary];
    _apps = [[self class] installedApps];
    NSMutableArray *hcg = [NSMutableArray array];
    for (NSDictionary *app in _apps)
        if ([app[@"id"] hasPrefix:@"com.hakmicapitalgroup."]) [hcg addObject:app];
    _hcg = hcg;
    _filtered = _apps;
}

- (void)save {
    [PortalPreferences setValue:[_chosen copy] forKey:PortalKeyApps];
}

- (BOOL)isChosen:(NSString *)identifier {
    for (NSDictionary *app in _chosen)
        if ([app[@"id"] isEqualToString:identifier]) return YES;
    return NO;
}

- (void)toggle:(NSDictionary *)app {
    NSString *identifier = app[@"id"];
    if ([self isChosen:identifier]) {
        NSIndexSet *found = [_chosen indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            return [obj[@"id"] isEqualToString:identifier];
        }];
        [_chosen removeObjectsAtIndexes:found];
    } else {
        if (_chosen.count >= PORTAL_MAX_APPS) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Six Apps at Most"
                                 message:@"The app ring holds six apps. Remove one from Chosen first."
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        [_chosen addObject:app];
    }
    [self save];
    [self.tableView reloadData];
}

#pragma mark Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text;
    if (!q.length) {
        _filtered = _apps;
    } else {
        NSPredicate *p = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR id CONTAINS[cd] %@", q, q];
        _filtered = [_apps filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return PortalAppsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case PortalAppsSectionChosen: return MAX(1, (NSInteger)_chosen.count);
        case PortalAppsSectionHCG: return (NSInteger)_hcg.count;
        case PortalAppsSectionAll: return _apps.count ? (NSInteger)_filtered.count : 1;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case PortalAppsSectionChosen: return [NSString stringWithFormat:@"Chosen (%lu of %d)", (unsigned long)_chosen.count, PORTAL_MAX_APPS];
        case PortalAppsSectionHCG: return _hcg.count ? @"Installed HCG Apps" : nil;
        case PortalAppsSectionAll: return @"All Apps";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == PortalAppsSectionChosen)
        return @"These apps appear in Portal's HCG Apps ring. Their icons and names are visible on the Lock Screen when you "
               @"open the ring. Opening one always asks for Face ID, Touch ID or your passcode first; if you cancel, "
               @"nothing opens.";
    if (section == PortalAppsSectionAll && !_apps.count)
        return @"The installed-apps list isn't available on this iOS version. Enter a bundle identifier instead.";
    return nil;
}

- (UIImage *)iconFor:(NSString *)identifier {
    UIImage *icon = [_icons objectForKey:identifier];
    if (!icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:identifier format:0 scale:UIScreen.mainScreen.scale];
        if (icon) [_icons setObject:icon forKey:identifier];
    }
    return icon;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
    [PortalTheme styleCell:cell];
    NSDictionary *app = nil;
    switch (indexPath.section) {
        case PortalAppsSectionChosen:
            if (!_chosen.count) {
                cell.textLabel.text = @"No apps chosen";
                cell.textLabel.textColor = PortalTheme.textSecondary;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            app = _chosen[indexPath.row];
            break;
        case PortalAppsSectionHCG: app = _hcg[indexPath.row]; break;
        case PortalAppsSectionAll:
            if (!_apps.count) {
                cell.textLabel.text = @"No apps listed";
                cell.textLabel.textColor = PortalTheme.textSecondary;
                return cell;
            }
            app = _filtered[indexPath.row];
            break;
        default:
            cell.textLabel.text = @"Enter Bundle ID…";
            cell.textLabel.textColor = PortalTheme.cyan;
            cell.accessibilityTraits |= UIAccessibilityTraitButton;
            return cell;
    }
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = app[@"id"];
    cell.imageView.image = [self iconFor:app[@"id"]];
    BOOL chosen = [self isChosen:app[@"id"]];
    cell.accessoryType = chosen && indexPath.section != PortalAppsSectionChosen ? UITableViewCellAccessoryCheckmark
                                                                               : UITableViewCellAccessoryNone;
    if (indexPath.section == PortalAppsSectionChosen) cell.showsReorderControl = YES;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case PortalAppsSectionChosen:
            if (_chosen.count) [self toggle:_chosen[indexPath.row]];
            break;
        case PortalAppsSectionHCG: [self toggle:_hcg[indexPath.row]]; break;
        case PortalAppsSectionAll:
            if (_apps.count) [self toggle:_filtered[indexPath.row]];
            break;
        default: [self enterManually]; break;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PortalAppsSectionChosen && _chosen.count;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == PortalAppsSectionChosen && _chosen.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
                         toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section != PortalAppsSectionChosen)
        return [NSIndexPath indexPathForRow:proposed.section < PortalAppsSectionChosen ? 0 : (NSInteger)_chosen.count - 1
                                  inSection:PortalAppsSectionChosen];
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSDictionary *app = _chosen[from.row];
    [_chosen removeObjectAtIndex:from.row];
    [_chosen insertObject:app atIndex:to.row];
    [self save];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == PortalAppsSectionChosen && _chosen.count) {
        [_chosen removeObjectAtIndex:indexPath.row];
        [self save];
        [tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    [PortalTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [PortalTheme styleHeaderFooterView:view header:NO];
}

- (void)enterManually {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Bundle ID"
                                                                   message:@"For example com.hakmicapitalgroup.hcgterminal"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = UIKeyboardTypeURL;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Add"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                NSString *text = [weakAlert.textFields.firstObject.text
                                                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                                                PortalAppShortcut *s = [PortalAppShortcut shortcutWithDictionary:@{@"id" : text ?: @""}];
                                                if (!s) return;
                                                if (![self isChosen:s.bundleIdentifier]) [self toggle:s.dictionary];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
