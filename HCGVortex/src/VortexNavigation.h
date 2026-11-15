//
//  VortexNavigation.h
//  HCG Vortex — Hakmi Capital Group
//
//  Observes Home Screen paging WITHOUT modifying it.
//
//  - Reads icon-page geometry from the root folder view / scroll view.
//  - Converts it to normalised page positions (page units).
//  - Runs the tested C state machine (vortex_nav_step) to determine the
//    navigation direction, transition progress and page roles.
//
//  It never writes contentOffset, currentPageIndex or any SpringBoard state;
//  the real page index is therefore always SpringBoard's own.
//

#import <UIKit/UIKit.h>
#import "VortexMath.h"

NS_ASSUME_NONNULL_BEGIN

#define VORTEX_MAX_PAGES 64

/// One frame's worth of Home Screen geometry.
typedef struct {
    NSInteger count;                       ///< number of icon pages collected
    double positions[VORTEX_MAX_PAGES];    ///< page centres, page units, sorted ascending
    void *_Nullable views[VORTEX_MAX_PAGES]; ///< unretained UIView* (valid for this frame only)
    double actual;                         ///< real scroll position, page units
    double pitch;                          ///< points per page horizontally
    double pageHeight;                     ///< points used for one vertical "page"
} VortexPageGeometry;

@interface VortexNavigation : NSObject

/// Collects geometry. Returns NO (and leaves the struct zeroed) if the
/// hierarchy doesn't look like an icon page scroller.
+ (BOOL)collectGeometryForFolderView:(UIView *)folderView
                          scrollView:(UIScrollView *)scrollView
                            geometry:(VortexPageGeometry *)geometry;

/// SpringBoard's own page index (read-only, for diagnostics). -1 if unknown.
+ (long long)actualPageIndexForFolderView:(UIView *)folderView;

- (void)reset;
- (VortexNavSnapshot)stepWithPresentedPosition:(double)presented geometry:(const VortexPageGeometry *)geometry;

@end

NS_ASSUME_NONNULL_END
