//
//  HACSpringBoard.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Private SpringBoard interfaces HCG Animation Center touches. Every use is
//  guarded at runtime (objc_getClass / respondsToSelector /
//  class_getInstanceMethod); when something is missing the surface reports it
//  in Settings and draws nothing, instead of guessing. docs/SPRINGBOARD_RESEARCH.md
//  lists where each name comes from (iOS 17.0.3 and 14.5 runtime header dumps)
//  and what is still unconfirmed on the test device.
//
//  Home Screen host (automatic):  SBHomeScreenWindow (the window HCG Halo already
//                                 draws in on the test device), our view at index 0,
//                                 below the icons
//  Wallpaper host (optional):     +[SBWallpaperController sharedInstance]
//                                 -_wallpaperViewForVariant: (0 = Lock, 1 = Home)
//  Cover Sheet host (fallback):   SBCoverSheetWindow, our view at index 0
//  App in front:                  -[SpringBoard frontDisplayDidChange:] (hooked, %orig first)
//                                 -[SpringBoard _accessibilityFrontMostApplication]
//  Screen / lock state:           Darwin notifications (public names, read-only)
//

#import <UIKit/UIKit.h>

#define HAC_SB_SPRINGBOARD_CLASS "SpringBoard"
#define HAC_SB_HOME_WINDOW_CLASS "SBHomeScreenWindow"
#define HAC_SB_ICON_CONTROLLER_CLASS "SBIconController"
#define HAC_SB_APPLICATION_CLASS "SBApplication"
#define HAC_SB_WALLPAPER_CONTROLLER_CLASS "SBWallpaperController"
#define HAC_SB_COVER_SHEET_WINDOW_CLASS "SBCoverSheetWindow"
#define HAC_SB_WALLPAPER_WINDOW_CLASS "_SBWallpaperWindow"
#define HAC_PB_POSTER_CONTROLLER_CLASS "PBUIPosterWallpaperViewController"
#define HAC_PB_WALLPAPER_CONTROLLER_CLASS "PBUIWallpaperViewController"

/// SBWallpaperController variants.
#define HAC_WALLPAPER_VARIANT_LOCK 0
#define HAC_WALLPAPER_VARIANT_HOME 1

@interface SpringBoard : UIApplication
- (void)frontDisplayDidChange:(id)display;
- (id)_accessibilityFrontMostApplication;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
@end

@interface SBWallpaperController : NSObject
+ (instancetype)sharedInstance;
- (id)_wallpaperViewForVariant:(long long)variant;
@end
