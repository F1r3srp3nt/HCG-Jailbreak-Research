//
//  HACEditorViewController.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Edit and preview one background, then apply it explicitly.
//
//  Library mode: edits a library item (trim, fill / fit / crop, loop, speed,
//  still, name); Apply to Home Screen / Lock Screen, Export, Delete.
//  AI preview mode: the same controls on a generated preview that is NOT in
//  the library. Only Apply or Save to Library adopts it; Discard deletes it.
//

#import <UIKit/UIKit.h>

#import "HACAIGeneration.h"
#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

@interface HACEditorViewController : UIViewController

- (instancetype)initWithItem:(HCGBackgroundPreset *)item preferredSurface:(HACSurface)surface;
- (instancetype)initWithAIResult:(HACAIResult *)result draft:(HCGBackgroundPreset *)draft;

/// The edited preset (tests / preview harness).
@property (nonatomic, readonly) HCGBackgroundPreset *draft;
@property (nonatomic, readonly) BOOL isAIPreview;

/// Called after the library or an assignment changed.
@property (nonatomic, copy, nullable) void (^onChange)(void);

// Exposed for the preview harness and tests: what the buttons do.
- (void)applyToSurface:(HACSurface)surface;
- (void)setScaling:(NSInteger)scaling;
- (void)setZoom:(double)zoom centerX:(double)x centerY:(double)y;

@end

NS_ASSUME_NONNULL_END
