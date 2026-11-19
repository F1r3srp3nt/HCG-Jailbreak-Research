//
//  HaloHeaderView.h
//  HCG Halo — Hakmi Capital Group
//
//  Branded table header with a live preview of the current border on a
//  miniature of the selected device profile. The preview uses the same
//  renderer as SpringBoard, pauses when it is off screen, and follows
//  Reduce Motion and Low Power Mode like the real border.
//

#import <UIKit/UIKit.h>

@class HaloSettings;

NS_ASSUME_NONNULL_BEGIN

@interface HaloHeaderView : UIView
- (instancetype)initWithWidth:(CGFloat)width;
- (void)reloadWithSettings:(HaloSettings *)settings;
@end

NS_ASSUME_NONNULL_END
