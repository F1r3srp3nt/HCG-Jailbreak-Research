//
//  HACEditorViewController.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Edit and preview one background, then apply it explicitly.
//
//  Library mode: edits a library item per placement (Home Screen / Lock
//  Screen): trim, loop, speed, still, and framing — rotation, flips, Fit /
//  Fill-Crop / Stretch, zoom and position — all live in the preview, which is
//  the same HCGBackgroundView SpringBoard uses. Nothing touches the media file
//  (non-destructive). Apply to Home Screen / Lock Screen, Export, Delete.
//  AI preview mode: the same controls on a generated preview that is NOT in
//  the library. Only Apply or Save to Library adopts it; Discard deletes it.
//

#import <UIKit/UIKit.h>

#import "HACAIGeneration.h"
#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"
#import "HCGBackgroundView.h"

NS_ASSUME_NONNULL_BEGIN

/// The editor's scaling choices (a preset stores them as scaling + stretch).
typedef NS_ENUM(NSInteger, HACFramingMode) {
    HACFramingModeFit = 0,      ///< scaling "fit": the whole region visible, bars in the background colour
    HACFramingModeFillCrop = 1, ///< scaling "crop" ("fill" when the whole frame): covers the screen
    HACFramingModeStretch = 2,  ///< transform.stretch (scaling "fill" for older readers): exact, aspect ignored
};

@interface HACEditorViewController : UIViewController

- (instancetype)initWithItem:(HCGBackgroundPreset *)item preferredSurface:(HACSurface)surface;
- (instancetype)initWithAIResult:(HACAIResult *)result draft:(HCGBackgroundPreset *)draft;

/// The edited preset of the current placement (tests / preview harness).
@property (nonatomic, readonly) HCGBackgroundPreset *draft;
@property (nonatomic, readonly) BOOL isAIPreview;
/// The placement being edited (library mode). Each keeps its own draft.
@property (nonatomic) HACSurface placement;
/// YES once the Lock Screen has its own settings (else it follows the Home Screen).
@property (nonatomic, readonly) BOOL lockHasOwnSettings;
/// The live preview (the renderer SpringBoard uses).
@property (nonatomic, readonly) HCGBackgroundView *previewView;
/// The current framing mode, zoom and normalised position of the current placement.
@property (nonatomic, readonly) HACFramingMode framingMode;
@property (nonatomic, readonly) double zoom;
@property (nonatomic, readonly) CGPoint position;

/// Called after the library or an assignment changed.
@property (nonatomic, copy, nullable) void (^onChange)(void);

// Exposed for the preview harness and tests: what the controls do.
- (void)applyToSurface:(HACSurface)surface;
/// Preset scaling: 0 fill, 1 fit, 2 crop (no stretch).
- (void)setScaling:(NSInteger)scaling;
- (void)setFramingMode:(HACFramingMode)mode;
- (void)setZoom:(double)zoom centerX:(double)x centerY:(double)y;
/// 0, 90, 180 or 270 (other values are normalised to a quarter turn).
- (void)setRotation:(NSInteger)degrees;
- (void)rotateClockwise;
- (void)setFlipHorizontal:(BOOL)horizontal vertical:(BOOL)vertical;
/// Back to the source as recorded (orientation metadata still applied).
- (void)resetTransformations;
/// The Lock Screen follows the Home Screen settings again.
- (void)useHomeSettingsForLock;
/// Saves every changed placement (library mode).
- (BOOL)save:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
