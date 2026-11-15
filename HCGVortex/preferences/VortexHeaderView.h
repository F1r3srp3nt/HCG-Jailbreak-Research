//
//  VortexHeaderView.h
//  HCG Vortex — Hakmi Capital Group
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Palette shared by the Settings UI.
@interface VortexTheme : NSObject
@property (class, nonatomic, readonly) UIColor *background;   // near-black navy
@property (class, nonatomic, readonly) UIColor *panel;        // grouped cell background
@property (class, nonatomic, readonly) UIColor *cyan;         // primary accent
@property (class, nonatomic, readonly) UIColor *purple;       // highlight
@property (class, nonatomic, readonly) UIColor *textPrimary;
@property (class, nonatomic, readonly) UIColor *textSecondary;
@end

/// "HCG VORTEX" branded table header with a static vortex ring motif.
@interface VortexHeaderView : UIView
- (instancetype)initWithWidth:(CGFloat)width;
@end

NS_ASSUME_NONNULL_END
