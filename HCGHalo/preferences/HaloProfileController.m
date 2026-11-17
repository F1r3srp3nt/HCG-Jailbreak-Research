//
//  HaloProfileController.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloProfileController.h"
#import "HaloPreferences.h"
#import "HaloTheme.h"

#include <sys/utsname.h>

typedef NS_ENUM(NSInteger, HaloProfileSection) {
    HaloProfileSectionAutomatic = 0,
    HaloProfileSectionImplemented,
    HaloProfileSectionPlanned,
    HaloProfileSectionThisDevice,
    HaloProfileSectionCount,
};

static NSString *const kCellID = @"HaloProfileCell";

@implementation HaloProfileController {
    NSArray<NSValue *> *_implemented; // const HaloProfile *
    NSArray<NSValue *> *_planned;
    NSString *_selected;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Device Profile";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [HaloTheme styleTableView:self.tableView];
    NSMutableArray *implemented = [NSMutableArray array], *planned = [NSMutableArray array];
    for (int i = 0; i < halo_profile_count(); i++) {
        const HaloProfile *p = halo_profile_at(i);
        [(p->implemented ? implemented : planned) addObject:[NSValue valueWithPointer:p]];
    }
    _implemented = implemented;
    _planned = planned;
    [self reload];
}

- (void)reload {
    _selected = [HaloPreferences readValueForKey:HaloKeyProfile];
    [self.tableView reloadData];
}

static NSString *HaloMachine(void) {
    struct utsname info;
    if (uname(&info) != 0) return @"unknown";
    return @(info.machine);
}

- (const HaloProfile *)profileForMachine:(NSString *)machine {
    for (int i = 0; i < halo_profile_count(); i++) {
        const HaloProfile *p = halo_profile_at(i);
        for (NSString *m in [@(p->machines) componentsSeparatedByString:@","])
            if ([m isEqualToString:machine]) return p;
    }
    return NULL;
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return HaloProfileSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case HaloProfileSectionAutomatic: return 1;
    case HaloProfileSectionImplemented: return (NSInteger)_implemented.count;
    case HaloProfileSectionPlanned: return (NSInteger)_planned.count;
    case HaloProfileSectionThisDevice: return 2;
    default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case HaloProfileSectionAutomatic: return @"Detection";
    case HaloProfileSectionImplemented: return @"Implemented Profiles";
    case HaloProfileSectionPlanned: return @"Planned — Not Available Yet";
    case HaloProfileSectionThisDevice: return @"This Device (Information Only)";
    default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
    case HaloProfileSectionAutomatic: return @"Automatic detection is not implemented yet. Choose a profile manually.";
    case HaloProfileSectionImplemented:
        return @"Implemented: the screen outline is entered and the profile can be used. Device-tested: someone has "
               @"checked it on that iPhone. A profile can be implemented without being device-tested. Fine-tune the "
               @"outline under Calibration.";
    case HaloProfileSectionPlanned:
        return @"Listed for planning only. These models have no profile yet and cannot be selected. HCG Halo does not "
               @"claim to support them.";
    case HaloProfileSectionThisDevice: return @"Shown to help you choose. Nothing is selected automatically.";
    default: return nil;
    }
}

- (UITableViewCell *)cell:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
    [HaloTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.userInteractionEnabled = YES;
    cell.accessibilityTraits = UIAccessibilityTraitNone;
    cell.accessibilityHint = nil;
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

- (void)disable:(UITableViewCell *)cell hint:(NSString *)hint {
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = NO;
    cell.textLabel.textColor = HaloTheme.textDisabled;
    cell.detailTextLabel.textColor = HaloTheme.textDisabled;
    cell.accessibilityTraits = UIAccessibilityTraitNotEnabled;
    cell.accessibilityHint = hint;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self cell:tableView];
    switch (indexPath.section) {
    case HaloProfileSectionAutomatic:
        cell.textLabel.text = @"Automatic";
        cell.detailTextLabel.text = @"Coming soon";
        [self disable:cell hint:@"Not available yet."];
        break;
    case HaloProfileSectionImplemented: {
        const HaloProfile *p = [_implemented[indexPath.row] pointerValue];
        cell.textLabel.text = @(p->name);
        cell.detailTextLabel.text = p->deviceTested ? @"Implemented · device-tested" : @"Implemented · not yet device-tested";
        BOOL selected = [_selected isEqualToString:@(p->identifier)];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        if (selected) cell.accessibilityTraits = UIAccessibilityTraitSelected;
        break;
    }
    case HaloProfileSectionPlanned: {
        const HaloProfile *p = [_planned[indexPath.row] pointerValue];
        cell.textLabel.text = @(p->name);
        cell.detailTextLabel.text = @"Planned · not available";
        [self disable:cell hint:@"No profile yet. Cannot be selected."];
        break;
    }
    case HaloProfileSectionThisDevice: {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            NSString *machine = HaloMachine();
            const HaloProfile *match = [self profileForMachine:machine];
            cell.textLabel.text = [NSString stringWithFormat:@"Model identifier %@", machine];
            if (match && match->implemented)
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Listed under %s (implemented).", match->name];
            else if (match)
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Listed under %s (planned: no profile yet).", match->name];
            else
                cell.detailTextLabel.text = @"Not in the profile list.";
        } else {
            UIScreen *screen = UIScreen.mainScreen;
            CGSize size = screen.fixedCoordinateSpace.bounds.size;
            cell.textLabel.text = [NSString stringWithFormat:@"Screen %.0f × %.0f pt @%.0fx", size.width, size.height, screen.scale];
            const HaloProfile *selected = halo_profile_find(_selected.UTF8String);
            if (selected && halo_profile_matches_screen(selected, size.width, size.height))
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Same size as %s.", selected->name];
            else if (selected)
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Different size from %s: the border will not line up.",
                                                                       selected->name];
            else
                cell.detailTextLabel.text = @"";
        }
        break;
    }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    [HaloTheme styleHeaderFooterView:view header:NO];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == HaloProfileSectionImplemented;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Only implemented profiles are selectable; "Automatic" and planned rows never are.
    return indexPath.section == HaloProfileSectionImplemented ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != HaloProfileSectionImplemented) return;
    const HaloProfile *p = [_implemented[indexPath.row] pointerValue];
    [HaloPreferences writeValue:@(p->identifier) forKey:HaloKeyProfile];
    [HaloPreferences postChangeNotification];
    [self reload];
}

@end
