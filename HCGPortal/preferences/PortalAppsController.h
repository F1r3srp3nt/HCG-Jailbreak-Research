//
//  PortalAppsController.h
//  HCG Portal — Hakmi Capital Group
//
//  HCG Apps: up to six installed apps you choose for the portal's app ring.
//  Installed HCG apps (com.hakmicapitalgroup.*) are suggested first. The list
//  of installed apps is read-only, through guarded LaunchServices calls (the
//  same approach as HCG Halo's app picker); if they are missing, the page says
//  so and offers manual entry.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PortalAppsController : UITableViewController
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps;
@end

NS_ASSUME_NONNULL_END
