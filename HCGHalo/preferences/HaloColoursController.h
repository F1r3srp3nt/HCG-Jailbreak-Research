//
//  HaloColoursController.h
//  HCG Halo — Hakmi Capital Group
//
//  Edit the palette: 1–6 colours, add / remove / reorder, edit with the
//  system colour picker, or start from a quick palette. Applies immediately.
//

#import <UIKit/UIKit.h>

@interface HaloColoursController : UITableViewController
/// Edits the HCG Nexus panel border's own palette instead of the screen edge's.
- (instancetype)initForNexusBorder;
/// Called after every saved change (the Nexus page refreshes its preview).
@property (nonatomic, copy) void (^didChange)(void);
@end
