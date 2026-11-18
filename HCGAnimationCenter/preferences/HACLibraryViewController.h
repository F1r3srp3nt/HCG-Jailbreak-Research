//
//  HACLibraryViewController.h
//  HCG Animation Center — Hakmi Capital Group
//
//  The media library: thumbnails with duration and Home / Lock badges, import
//  from Photos (videos and GIFs), Files (videos, GIFs, exported presets) and
//  an editor per item. In "choose for" mode the first tile is "None", which
//  hands that screen back to the system wallpaper.
//

#import <UIKit/UIKit.h>

#import "HACPolicy.h"

NS_ASSUME_NONNULL_BEGIN

@interface HACLibraryViewController : UIViewController

- (instancetype)initBrowsing;
- (instancetype)initChoosingForSurface:(HACSurface)surface;

@property (nonatomic, copy, nullable) void (^onChange)(void);

/// Imports files as if picked (preview harness and tests).
- (void)importFileURLs:(NSArray<NSURL *> *)urls completion:(nullable void (^)(NSUInteger imported, NSArray<NSString *> *problems))completion;
- (void)reloadLibrary;

@end

NS_ASSUME_NONNULL_END
