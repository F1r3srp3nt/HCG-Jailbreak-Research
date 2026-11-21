//
//  PortalTouchSynth.h
//  HCG Portal — synthesised touches for the PREVIEW only (iOS Simulator).
//
//  Real UITouch / UIEvent objects carrying an IOHIDEvent, delivered through
//  -[UIApplication sendEvent:], so hit-testing, gesture recognizers (and their
//  arbitration), UIScrollView touch delays and UIControl tracking all run as
//  they do for a finger. The technique is the one KIF uses
//  (github.com/kif-framework/KIF: UITouch-KIFAdditions, IOHIDEvent+KIF).
//
//  It uses private UIKit and IOKit interfaces, checked at run time, and is
//  NEVER compiled into the package. It is still a simulation: the device's
//  touch hardware, SpringBoard's real gesture configuration and system
//  gestures are device rows.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// YES if every private interface the synthesiser needs is present; otherwise NO and `why`.
BOOL PTSAvailable(NSString *_Nullable *_Nullable why);

/// A tap at `point` (window coordinates): touch down, held for `hold` seconds, touch up. The
/// run loop runs between the phases and for 0.35 s afterwards. Returns NO if unavailable.
BOOL PTSTap(UIWindow *window, CGPoint point, NSTimeInterval hold);

/// A drag from `from` to `to` (window coordinates) in `steps` moves. Returns NO if unavailable.
BOOL PTSDrag(UIWindow *window, CGPoint from, CGPoint to, NSUInteger steps);

NS_ASSUME_NONNULL_END
