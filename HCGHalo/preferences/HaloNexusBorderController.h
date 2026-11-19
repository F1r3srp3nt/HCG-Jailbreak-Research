//
//  HaloNexusBorderController.h
//  HCG Halo — Hakmi Capital Group
//
//  "Nexus Panel Border": the HCG Nexus panel's lighting. Opened from HCG
//  Halo's Settings page, and from HCG Nexus's Appearance section ("Halo
//  border"), which loads HCG Halo's Settings bundle and pushes this class by
//  name, so both apps show the same page and the same settings.
//
//  Contract with HCG Nexus (HCGHaloNexusIntegration = 1 in this bundle's
//  Info.plist): the class name, a UIViewController subclass, created with
//  -init. Nothing else is shared.
//
//  The page reads the border definition INSTALLED by HCG Nexus (next to this
//  bundle) to know whether the panel target is available and which shape to
//  preview; without a compatible Nexus the panel targets are disabled with the
//  reason, and nothing else changes.
//

#import <UIKit/UIKit.h>

@interface HaloNexusBorderController : UITableViewController
@end
