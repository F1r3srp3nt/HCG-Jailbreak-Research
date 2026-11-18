//
//  VortexRootListController.h
//  HCG Vortex — Hakmi Capital Group
//

#import <Preferences/PSListController.h>

@interface VortexRootListController : PSListController
/// Shared by the effect panes (VortexEffectPaneController).
- (void)confirmWithTitle:(NSString *)title
                 message:(NSString *)message
             actionTitle:(NSString *)actionTitle
             destructive:(BOOL)destructive
                 handler:(void (^)(void))handler;
@end
