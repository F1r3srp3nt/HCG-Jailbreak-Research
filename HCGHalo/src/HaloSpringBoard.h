//
//  HaloSpringBoard.h
//  HCG Halo — Hakmi Capital Group
//
//  Private SpringBoard interfaces HCG Halo touches. Every use is guarded at
//  runtime (objc_getClass / respondsToSelector / class_getInstanceMethod);
//  when something is missing, Halo degrades as documented in
//  docs/ARCHITECTURE.md and reports it in Settings, instead of guessing.
//
//  Required (at least one):  SBHomeScreenWindow class, or
//                            +[SBIconController sharedInstance] (a view controller in the Home Screen window)
//  Optional:                 -[SpringBoard frontDisplayDidChange:]          (hooked: app in front?)
//                            -[SpringBoard _accessibilityFrontMostApplication] (initial app-in-front state)
//                            -[UIScreen _displayCornerRadius]               (shown for calibration only)
//

#import <UIKit/UIKit.h>

#define HALO_SB_HOME_WINDOW_CLASS "SBHomeScreenWindow"
#define HALO_SB_ICON_CONTROLLER_CLASS "SBIconController"
#define HALO_SB_APPLICATION_CLASS "SBApplication"
#define HALO_SB_SPRINGBOARD_CLASS "SpringBoard"

@interface SpringBoard : UIApplication
- (void)frontDisplayDidChange:(id)display;
- (id)_accessibilityFrontMostApplication;
@end

@interface SBIconController : UIViewController
+ (instancetype)sharedInstance;
@end
