//
//  HaloTheme.h
//  HCG Halo — Hakmi Capital Group
//
//  Dark HCG palette for the Settings pane. Text colours keep at least 4.5:1
//  contrast on the panel colour (see docs/ARCHITECTURE.md, "Settings").
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HaloTheme : NSObject
@property (class, nonatomic, readonly) UIColor *background;    // #05070F
@property (class, nonatomic, readonly) UIColor *panel;         // #0E1424
@property (class, nonatomic, readonly) UIColor *cyan;          // #00E5FF
@property (class, nonatomic, readonly) UIColor *violet;        // #B07CFF (readable violet for text)
@property (class, nonatomic, readonly) UIColor *deepViolet;    // #7B61FF
@property (class, nonatomic, readonly) UIColor *textPrimary;   // #E9F1FF
@property (class, nonatomic, readonly) UIColor *textSecondary; // #98A6C4
@property (class, nonatomic, readonly) UIColor *textDisabled;  // #5E6A85
@property (class, nonatomic, readonly) UIColor *warning;       // #FFB547

+ (UIColor *)colourWithHex:(uint32_t)rgb alpha:(CGFloat)alpha;
/// Dark grouped table styling for any UITableView owned by HCG Halo.
+ (void)styleTableView:(UITableView *)tableView;
/// Cell colours and selection highlight.
+ (void)styleCell:(UITableViewCell *)cell;
+ (void)styleHeaderFooterView:(UIView *)view header:(BOOL)header;
@end

NS_ASSUME_NONNULL_END
