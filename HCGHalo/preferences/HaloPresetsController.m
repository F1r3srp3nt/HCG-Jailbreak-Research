//
//  HaloPresetsController.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloPresetsController.h"
#import "HaloPreferences.h"
#import "HaloTheme.h"

typedef NS_ENUM(NSInteger, HaloPresetSection) {
    HaloPresetSectionUser = 0,
    HaloPresetSectionBuiltIn,
    HaloPresetSectionCount,
};

static NSString *const kCellID = @"HaloPresetCell";

@implementation HaloPresetsController {
    NSArray<NSDictionary *> *_user;
    NSArray<NSDictionary *> *_builtIn;
    NSString *_matching;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Presets";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [HaloTheme styleTableView:self.tableView];
    UIBarButtonItem *save = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                          target:self
                                                                          action:@selector(saveCurrent)];
    save.accessibilityLabel = @"Save current appearance as a preset";
    self.navigationItem.rightBarButtonItem = save;
    [self reload];
}

- (void)reload {
    _user = [HaloPreferences userPresets];
    _builtIn = [HaloPreferences builtInPresets];
    _matching = [HaloPreferences matchingPresetIdentifier];
    self.navigationItem.rightBarButtonItem.enabled = _user.count < HALO_MAX_PRESETS;
    [self.tableView reloadData];
}

- (NSDictionary *)presetAt:(NSIndexPath *)indexPath {
    if (indexPath.section == HaloPresetSectionUser) return indexPath.row < (NSInteger)_user.count ? _user[indexPath.row] : nil;
    return indexPath.row < (NSInteger)_builtIn.count ? _builtIn[indexPath.row] : nil;
}

- (NSString *)summaryOf:(NSDictionary *)preset {
    HaloAppearance a = [HaloPreferences appearanceFromDictionary:preset[HaloPresetKeyAppearance]];
    return [NSString stringWithFormat:@"%s · %d colour%s · %.0f%% brightness", halo_mode_title(a.mode),
                                      halo_effective_colour_count(&a), halo_effective_colour_count(&a) == 1 ? "" : "s",
                                      a.brightness * 100];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return HaloPresetSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == HaloPresetSectionUser) return MAX((NSInteger)_user.count, 1); // placeholder row when empty
    return (NSInteger)_builtIn.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == HaloPresetSectionUser ? @"Your Presets" : @"Built-in";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == HaloPresetSectionUser)
        return @"Tap to apply. Swipe left to rename, duplicate or delete. + saves the current appearance.";
    return @"Presets store mode, colours, brightness, thickness, glow, inset and animation. Applying one never changes "
           @"your device profile, calibration, Low Power behaviour or the Enable switch. Built-in presets can be "
           @"duplicated, then edited.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
    [HaloTheme styleCell:cell];
    NSDictionary *preset = [self presetAt:indexPath];
    if (!preset) {
        cell.textLabel.text = @"No saved presets yet";
        cell.textLabel.textColor = HaloTheme.textSecondary;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.text = preset[HaloPresetKeyName];
    cell.detailTextLabel.text = [self summaryOf:preset];
    BOOL current = [preset[HaloPresetKeyID] isEqualToString:_matching];
    cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityValue = current ? @"Current appearance" : nil;
    cell.accessibilityHint = @"Applies this preset.";
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:NO];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self presetAt:indexPath] ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *preset = [self presetAt:indexPath];
    if (!preset) return;
    NSString *identifier = preset[HaloPresetKeyID];
    if ([identifier isEqualToString:_matching]) return;
    NSString *message = _matching ? @"Your current appearance is saved as a preset, so nothing is lost."
                                  : @"Your current appearance is not saved as a preset. Save it first (+) if you want "
                                    @"to keep it.";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Apply “%@”?", preset[HaloPresetKeyName]]
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                [HaloPreferences applyPreset:identifier];
                                                [HaloPreferences postChangeNotification];
                                                [self reload];
                                            }]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *preset = [self presetAt:indexPath];
    if (!preset) return nil;
    NSString *identifier = preset[HaloPresetKeyID];
    NSMutableArray *actions = [NSMutableArray array];
    __weak HaloPresetsController *weakSelf = self;
    if (indexPath.section == HaloPresetSectionUser) {
        UIContextualAction *delete =
            [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                    title:@"Delete"
                                                  handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
                                                      [weakSelf confirmDelete:preset completion:done];
                                                  }];
        UIContextualAction *rename =
            [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                    title:@"Rename"
                                                  handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
                                                      [weakSelf promptRename:preset];
                                                      done(YES);
                                                  }];
        rename.backgroundColor = HaloTheme.deepViolet;
        [actions addObjectsFromArray:@[ delete, rename ]];
    }
    UIContextualAction *duplicate =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                title:@"Duplicate"
                                              handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
                                                  BOOL ok = [HaloPreferences duplicatePreset:identifier] != nil;
                                                  if (!ok) [weakSelf showLimit];
                                                  [weakSelf reload];
                                                  done(ok);
                                              }];
    duplicate.backgroundColor = [HaloTheme colourWithHex:0x00A3B8 alpha:1];
    [actions addObject:duplicate];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO; // never delete by accident
    return configuration;
}

#pragma mark Actions

- (void)showLimit {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Preset Limit"
                                            message:[NSString stringWithFormat:@"You can keep up to %d presets. Delete one first.",
                                                                               HALO_MAX_PRESETS]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForName:(NSString *)title
              initial:(NSString *)initial
               action:(NSString *)actionTitle
              handler:(void (^)(NSString *name))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:[NSString stringWithFormat:@"Up to %d characters.",
                                                                                                      HALO_PRESET_NAME_MAX]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = initial;
        field.placeholder = @"Preset name";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                handler(weakAlert.textFields.firstObject.text ?: @"");
                                            }]];
    alert.view.tintColor = HaloTheme.cyan;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCurrent {
    if (_user.count >= HALO_MAX_PRESETS) {
        [self showLimit];
        return;
    }
    __weak HaloPresetsController *weakSelf = self;
    [self promptForName:@"Save Current Appearance"
                initial:@""
                 action:@"Save"
                handler:^(NSString *name) {
                    if (![HaloPreferences saveCurrentAppearanceAsPresetNamed:name]) {
                        [weakSelf showInvalidName];
                        return;
                    }
                    [weakSelf reload];
                }];
}

- (void)promptRename:(NSDictionary *)preset {
    NSString *identifier = preset[HaloPresetKeyID];
    __weak HaloPresetsController *weakSelf = self;
    [self promptForName:@"Rename Preset"
                initial:preset[HaloPresetKeyName]
                 action:@"Rename"
                handler:^(NSString *name) {
                    if (![HaloPreferences renamePreset:identifier to:name]) [weakSelf showInvalidName];
                    [weakSelf reload];
                }];
}

- (void)showInvalidName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Name Required"
                                                                   message:@"Enter a name with at least one character."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(NSDictionary *)preset completion:(void (^)(BOOL))done {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"Delete “%@”?", preset[HaloPresetKeyName]]
                         message:@"This removes the preset only. The border keeps its current appearance."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
                                                done(NO);
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [HaloPreferences deletePreset:preset[HaloPresetKeyID]];
                                                done(YES);
                                                [self reload];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
