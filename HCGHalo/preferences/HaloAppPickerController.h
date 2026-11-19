//
//  HaloAppPickerController.h
//  HCG Halo — Hakmi Capital Group
//
//  Settings › HCG Halo › Chosen App: the installed-app picker for
//  "Show Halo on: Selected App Only". Lists the visible installed apps
//  (LaunchServices, read-only), searchable, with their icons. Tapping one
//  stores its bundle identifier and name and selects Selected App Only; the
//  change applies immediately. "Enter Bundle ID" is a manual fallback if
//  LaunchServices returns nothing on this iOS version.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HaloAppPickerController : UITableViewController
/// Visible installed apps as @{ @"id": bundle identifier, @"name": display name }, sorted by name.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps;
/// Display name of an installed app, or nil if it is not installed.
+ (nullable NSString *)nameForBundleIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
