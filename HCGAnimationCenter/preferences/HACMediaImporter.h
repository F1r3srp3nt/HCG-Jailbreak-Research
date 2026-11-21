//
//  HACMediaImporter.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Turns a user's file into a library item (docs/LIVE-BACKGROUNDS.md):
//
//    video (MOV / MP4 / M4V, H.264 or HEVC)  →  video track only, passthrough
//        (no transcoding; orientation metadata kept and recorded as
//        media.sourceRotation) when the long side is at most 4096 px and the
//        frame at most 4.19 MP (2048 x 2048). Larger, or not copyable: an
//        upright H.264 copy with the same aspect ratio inside that budget.
//        The audio track is dropped: backgrounds are muted.
//    animated GIF (2+ frames)  →  H.264 MP4, longer side at most 1080 px,
//        browser frame timing, repeated to at least 1 s.
//    still images, Live Photos  →  refused with a reason (not live backgrounds).
//    anything unreadable, corrupt, empty, over 512 MB or over 10 minutes
//        →  refused with a reason; nothing is added and staging is cleaned.
//
//  Every item gets a still (the static fallback) and a thumbnail.
//

#import <Foundation/Foundation.h>

#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HACMediaKind) {
    HACMediaKindUnknown = 0,
    HACMediaKindVideo,
    HACMediaKindGIF,
    HACMediaKindStillImage,
};

FOUNDATION_EXPORT NSString *const HACImportErrorDomain;
FOUNDATION_EXPORT const unsigned long long HACMaxSourceBytes; // 512 MB
FOUNDATION_EXPORT const double HACMaxStoredLongSide;          // 4096 px: longer videos are converted
FOUNDATION_EXPORT const double HACMaxStoredPixels;            // 2048 x 2048: larger frames are converted
/// Whether a video of this display size is stored as is (passthrough).
FOUNDATION_EXPORT BOOL HACVideoFitsWithoutConversion(CGSize size);
/// The size a larger video is converted to (aspect kept, even sides).
FOUNDATION_EXPORT CGSize HACConvertedVideoSize(CGSize size);
FOUNDATION_EXPORT const double HACGIFMaxLongSide;             // 1080 px
FOUNDATION_EXPORT const NSUInteger HACGIFMaxFrames;           // 3000

typedef void (^HACImportProgress)(double fraction, NSString *phase);
typedef void (^HACImportCompletion)(HCGBackgroundPreset *_Nullable item, NSError *_Nullable error);

@interface HACMediaImporter : NSObject

/// Copies a file into the staging folder right away (call it inside a picker's
/// completion, before its temporary file disappears).
+ (nullable NSURL *)stageFileAtURL:(NSURL *)url error:(NSError **)error;

/// What the file's first bytes say it is.
+ (HACMediaKind)kindOfFileAtURL:(NSURL *)url;

/// Imports a staged file into the library (deletes the staged file). Progress
/// and completion arrive on the main queue. One import at a time.
- (void)importStagedFile:(NSURL *)staged
           suggestedName:(nullable NSString *)name
                progress:(nullable HACImportProgress)progress
              completion:(HACImportCompletion)completion;
- (void)cancel;
@property (nonatomic, readonly, getter=isBusy) BOOL busy;

/// (Re)writes the item's still at its stillTime, and the thumbnail. Synchronous.
+ (BOOL)writeStillAndThumbnailForItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// (Re)writes a placement's still (<ID>-still.jpg / <ID>-still-lock.jpg) and
/// sets item.stillFile; the Home Screen also rewrites the thumbnail.
+ (BOOL)writeStillForItem:(HCGBackgroundPreset *)item placement:(HACSurface)placement error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
