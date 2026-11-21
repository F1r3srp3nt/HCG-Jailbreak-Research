//
//  HACTestMedia.h
//  HCG Animation Center — synthetic media for the Simulator tests and preview.
//
//  Everything is generated on the fly (original, no third-party content):
//    a video with moving colour waves and an AAC silence track (to prove the
//    importer drops audio), an animated GIF with browser-style frame delays,
//    and the damaged / unsupported files the importer must refuse.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// H.264 + AAC (silence) QuickTime movie; `hue` shifts the palette.
BOOL HACWriteTestVideo(NSURL *url, CGSize size, double seconds, double hue, BOOL withAudio, NSError **error);
/// The same, with orientation metadata (`transform`, as a camera writes it)
/// and, if `marker`, a red square in the stored frame's top-left corner.
BOOL HACWriteTestVideoWithOrientation(NSURL *url, CGSize size, double seconds, double hue, BOOL withAudio,
                                      CGAffineTransform transform, BOOL marker, NSError **error);
/// A camera-style preferred transform that turns a `natural` frame clockwise
/// by 90 / 180 / 270 degrees.
CGAffineTransform HACTestRotationTransform(CGSize natural, NSInteger degrees);
/// Animated GIF, one frame per delay (seconds; 0 = "unspecified").
BOOL HACWriteTestGIF(NSURL *url, CGSize size, NSArray<NSNumber *> *delays, NSError **error);
/// Writes random.mov (noise), truncated.mp4 (cut from `validVideo`), still.png,
/// oneframe.gif and empty.mov into `folder`; returns their URLs by name.
NSDictionary<NSString *, NSURL *> *HACWriteBadMedia(NSURL *folder, NSURL *validVideo);

NS_ASSUME_NONNULL_END
