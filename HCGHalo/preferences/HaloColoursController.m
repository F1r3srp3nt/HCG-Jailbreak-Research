//
//  HaloColoursController.m
//  HCG Halo — Hakmi Capital Group
//

#import "HaloColoursController.h"
#import "HaloPreferences.h"
#import "HaloTheme.h"

typedef NS_ENUM(NSInteger, HaloColourSection) {
    HaloColourSectionColours = 0,
    HaloColourSectionAdd,
    HaloColourSectionPalettes,
    HaloColourSectionCount,
};

static NSString *const kCellID = @"HaloColourCell";

@interface HaloColoursController () <UIColorPickerViewControllerDelegate>
@end

@implementation HaloColoursController {
    NSMutableArray<NSString *> *_colours;
    NSInteger _editingIndex;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

+ (NSArray<NSDictionary *> *)palettes {
    return @[
        @{@"name" : @"HCG Cyan & Violet", @"colours" : @[ @"#00E5FF", @"#7B61FF", @"#C026FF" ]},
        @{@"name" : @"Aurora", @"colours" : @[ @"#00FFA3", @"#00E5FF", @"#7B61FF", @"#FF3CAC" ]},
        @{@"name" : @"Solar", @"colours" : @[ @"#FFD60A", @"#FF8A00", @"#FF2E63" ]},
        @{@"name" : @"Ice", @"colours" : @[ @"#E0FBFF", @"#7FDBFF", @"#2F80ED" ]},
        @{@"name" : @"Spectrum", @"colours" : @[ @"#FF2E63", @"#FFD60A", @"#00FFA3", @"#00E5FF", @"#7B61FF", @"#C026FF" ]},
        @{@"name" : @"Pure Cyan", @"colours" : @[ @"#00E5FF" ]},
    ];
}

static UIColor *HaloColourFromHex(NSString *hex) {
    HaloRGB c = {0, 0, 0};
    halo_parse_hex(hex.UTF8String, &c);
    return [UIColor colorWithRed:(CGFloat)c.r green:(CGFloat)c.g blue:(CGFloat)c.b alpha:1];
}

static NSString *HaloHexFromColour(UIColor *colour) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![colour getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([colour getWhite:&white alpha:&a]) r = g = b = white;
    }
    char hex[8];
    halo_format_hex((HaloRGB){r, g, b}, hex); // clamps extended-range values
    return @(hex);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Colours";
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [HaloTheme styleTableView:self.tableView];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self reload];
}

- (void)reload {
    _colours = [[HaloPreferences readValueForKey:HaloKeyColours] mutableCopy];
    [self.tableView reloadData];
}

- (void)save {
    [HaloPreferences writeValue:[_colours copy] forKey:HaloKeyColours];
    [HaloPreferences postChangeNotification];
}

- (NSString *)styleIdentifier {
    return [HaloPreferences readValueForKey:HaloKeyColourStyle];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return HaloColourSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case HaloColourSectionColours: return (NSInteger)_colours.count;
    case HaloColourSectionAdd: return _colours.count < HALO_MAX_COLOURS ? 1 : 0;
    case HaloColourSectionPalettes: return (NSInteger)[HaloColoursController palettes].count;
    default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == HaloColourSectionColours) return @"Palette";
    if (section == HaloColourSectionPalettes) return @"Quick Palettes";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == HaloColourSectionColours) {
        NSString *style = [self styleIdentifier];
        NSString *note = [style isEqualToString:@"single"]
                             ? @"Colour Style is Single Colour: only the first colour is used."
                             : @"All colours are used, in this order, around the edge.";
        return [NSString stringWithFormat:@"%@ Tap a colour to change it; use Edit to reorder. 1–%d colours.", note,
                                          HALO_MAX_COLOURS];
    }
    if (section == HaloColourSectionPalettes) return @"Replaces the palette above. Changes apply immediately.";
    return nil;
}

- (UIImage *)swatch:(NSArray<NSString *> *)hexes size:(CGFloat)size {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size * hexes.count * 0.7f + size * 0.3f, size)
                                                                               format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        for (NSUInteger i = 0; i < hexes.count; i++) {
            CGRect r = CGRectMake(i * size * 0.7f, 0, size, size);
            UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(r, 1, 1)];
            [HaloColourFromHex(hexes[i]) setFill];
            [circle fill];
            [[UIColor colorWithWhite:1 alpha:0.35] setStroke];
            circle.lineWidth = 1;
            [circle stroke];
        }
    }];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID forIndexPath:indexPath];
    [HaloTheme styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    switch (indexPath.section) {
    case HaloColourSectionColours: {
        NSString *hex = _colours[indexPath.row];
        BOOL unused = [[self styleIdentifier] isEqualToString:@"single"] && indexPath.row > 0;
        cell.imageView.image = [self swatch:@[ hex ] size:26];
        cell.textLabel.text = [NSString stringWithFormat:@"Colour %ld   %@%@", (long)indexPath.row + 1, hex,
                                                         unused ? @"   (unused)" : @""];
        cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
        cell.textLabel.textColor = unused ? HaloTheme.textDisabled : HaloTheme.textPrimary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessibilityLabel = [NSString stringWithFormat:@"Colour %ld, %@%@", (long)indexPath.row + 1, hex,
                                                             unused ? @", unused with Single Colour" : @""];
        cell.accessibilityHint = @"Opens the colour picker.";
        break;
    }
    case HaloColourSectionAdd:
        cell.textLabel.text = @"Add Colour";
        cell.textLabel.textColor = HaloTheme.cyan;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        break;
    case HaloColourSectionPalettes: {
        NSDictionary *palette = [HaloColoursController palettes][indexPath.row];
        cell.imageView.image = [self swatch:palette[@"colours"] size:20];
        cell.textLabel.text = palette[@"name"];
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        BOOL current = [palette[@"colours"] isEqualToArray:_colours];
        cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
    case HaloColourSectionColours: [self editColourAtIndex:indexPath.row]; break;
    case HaloColourSectionAdd: {
        if (_colours.count >= HALO_MAX_COLOURS) return;
        NSArray *suggestions = @[ @"#00E5FF", @"#7B61FF", @"#C026FF", @"#00FFA3", @"#FF3CAC", @"#FFD60A" ];
        NSString *next = suggestions[_colours.count % suggestions.count];
        [_colours addObject:next];
        [self save];
        [tableView reloadData];
        [self editColourAtIndex:(NSInteger)_colours.count - 1];
        break;
    }
    case HaloColourSectionPalettes:
        _colours = [[HaloColoursController palettes][indexPath.row][@"colours"] mutableCopy];
        [self save];
        [tableView reloadData];
        break;
    }
}

- (void)editColourAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_colours.count) return;
    _editingIndex = index;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.selectedColor = HaloColourFromHex(_colours[index]);
    picker.title = [NSString stringWithFormat:@"Colour %ld", (long)index + 1];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously {
    if (continuously) return; // write once per pick, not on every drag step
    if (_editingIndex < 0 || _editingIndex >= (NSInteger)_colours.count) return;
    _colours[_editingIndex] = HaloHexFromColour(color);
    [self save];
    [self.tableView reloadData];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (_editingIndex >= 0 && _editingIndex < (NSInteger)_colours.count) {
        NSString *hex = HaloHexFromColour(viewController.selectedColor);
        if (![hex isEqualToString:_colours[_editingIndex]]) {
            _colours[_editingIndex] = hex;
            [self save];
        }
    }
    [self.tableView reloadData];
}

#pragma mark Editing

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == HaloColourSectionColours;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != HaloColourSectionColours) return UITableViewCellEditingStyleNone;
    return _colours.count > 1 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || _colours.count <= 1) return;
    [_colours removeObjectAtIndex:indexPath.row];
    [self save];
    [tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == HaloColourSectionColours && _colours.count > 1;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
                         toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section != HaloColourSectionColours) {
        NSInteger row = proposed.section < HaloColourSectionColours ? 0 : (NSInteger)_colours.count - 1;
        return [NSIndexPath indexPathForRow:row inSection:HaloColourSectionColours];
    }
    return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *hex = _colours[from.row];
    [_colours removeObjectAtIndex:from.row];
    [_colours insertObject:hex atIndex:to.row];
    [self save];
    dispatch_async(dispatch_get_main_queue(), ^{
        [tableView reloadData]; // renumber "Colour n"
    });
}

@end
