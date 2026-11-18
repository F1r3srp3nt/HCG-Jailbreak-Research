//
//  HACAIViewController.h
//  HCG Animation Center — Hakmi Capital Group
//
//  AI Backgrounds (later phase): describe a background, generate a PREVIEW
//  through HCG AI, then decide in the preview screen. Generation is available
//  only when HCG's central access controls allow it; in this beta HCG AI is
//  not connected, so the page explains that and Generate stays disabled.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HACAIViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onChange)(void);
/// Starts generation with the current prompt (preview harness / tests).
- (void)generateWithPrompt:(NSString *)prompt;
@end

NS_ASSUME_NONNULL_END
