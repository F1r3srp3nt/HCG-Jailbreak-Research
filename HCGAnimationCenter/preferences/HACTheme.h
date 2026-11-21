//
//  HACTheme.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Settings appearance: a dark pane with a violet accent.
//

#import <UIKit/UIKit.h>

#import "HCGBackgroundView.h"

NS_ASSUME_NONNULL_BEGIN

UIColor *HACAccentColor(void);
UIColor *HACSecondaryAccentColor(void);
/// Applies the dark appearance and accent to a controller (and its navigation bar).
void HACApplyTheme(UIViewController *controller);
UIButton *HACMakeButton(NSString *title, NSString *_Nullable systemImage, BOOL prominent);
/// "12.4 s", "1 min 05 s"
NSString *HACFormatSeconds(NSTimeInterval seconds);
/// "1080 × 1920 · 12.4 s · from GIF"
NSString *HACDescribePreset(HCGBackgroundPreset *preset);
/// "Rotated 90° · flipped horizontally · stretch", or "Original orientation".
NSString *HACDescribeTransform(HCGBackgroundPreset *preset);
/// "1920 × 1080 · metadata rotation 90° applied" (what the importer detected).
NSString *HACDescribeSource(HCGBackgroundPreset *preset);
/// The image (a still in the source's display orientation) with the preset's
/// rotation and flips applied: the same matrix the renderer uses. No scaling.
UIImage *HACOrientedImage(UIImage *image, HCGBackgroundPreset *preset);

typedef NS_ENUM(NSInteger, HACStageOverlay) {
    HACStageOverlayNone = 0,
    HACStageOverlayHomeIcons = 1,
    HACStageOverlayLockClock = 2,
};

/// A phone-shaped preview at the screen's aspect ratio. The background is the
/// same HCGBackgroundView class SpringBoard uses, so what you see here is what
/// the Home Screen or Lock Screen shows (scaled).
@interface HACPreviewStage : UIView
@property (nonatomic, readonly) HCGBackgroundView *background;
@property (nonatomic) HACStageOverlay overlay;
/// The screen size the stage represents (points).
@property (nonatomic, readonly) CGSize screenSize;
@end

NS_ASSUME_NONNULL_END
