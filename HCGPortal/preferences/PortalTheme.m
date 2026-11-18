//
//  PortalTheme.m
//  HCG Portal — Hakmi Capital Group
//

#import "PortalTheme.h"

@implementation PortalTheme

+ (UIColor *)colourWithHex:(uint32_t)rgb alpha:(CGFloat)alpha {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

+ (UIColor *)background {
    return [self colourWithHex:0x05070F alpha:1];
}
+ (UIColor *)panel {
    return [self colourWithHex:0x0E1424 alpha:1];
}
+ (UIColor *)cyan {
    return [self colourWithHex:0x00E5FF alpha:1];
}
+ (UIColor *)violet {
    return [self colourWithHex:0xB07CFF alpha:1];
}
+ (UIColor *)deepViolet {
    return [self colourWithHex:0x7B61FF alpha:1];
}
+ (UIColor *)textPrimary {
    return [self colourWithHex:0xE9F1FF alpha:1];
}
+ (UIColor *)textSecondary {
    return [self colourWithHex:0x98A6C4 alpha:1];
}
+ (UIColor *)textDisabled {
    return [self colourWithHex:0x5E6A85 alpha:1];
}
+ (UIColor *)warning {
    return [self colourWithHex:0xFFB547 alpha:1];
}

+ (void)styleTableView:(UITableView *)tableView {
    tableView.backgroundColor = self.background;
    tableView.backgroundView = nil;
    tableView.separatorColor = [self.deepViolet colorWithAlphaComponent:0.28];
    tableView.tintColor = self.cyan;
    tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
}

+ (void)styleCell:(UITableViewCell *)cell {
    cell.backgroundColor = self.panel;
    cell.textLabel.textColor = self.textPrimary;
    cell.detailTextLabel.textColor = self.textSecondary;
    cell.tintColor = self.cyan;
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [self.deepViolet colorWithAlphaComponent:0.30];
    cell.selectedBackgroundView = selected;
}

+ (void)styleHeaderFooterView:(UIView *)view header:(BOOL)header {
    if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
    UILabel *label = ((UITableViewHeaderFooterView *)view).textLabel;
    label.textColor = header ? self.violet : self.textSecondary;
}

@end
