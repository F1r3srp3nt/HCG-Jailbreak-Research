//
//  HACMediaImporter.h
//  HCG Animation Center — Hakmi Capital Group
//
//  Turns a user's file into a library item (docs/LIVE-BACKGROUNDS.md):
//
//    video (MOV / MP4 / M4V, H.264 or HEVC)  →  video track only, passthrough;
//        downscaled to 1920 × 1080 (H.264) if a side exceeds 2688 px or
//        passthrough fails. The audio track is dropped: backgrounds are muted.
//    animated GIF (2+ frames)  →  H.264 MP4, longer side at most 1080 px,
//        browser frame timing, repeated to at least 1 s.
//    still images, Live Photos  →  refused with a reason (not live backgrounds).
//    anything unreadable, corrupt, empty, over 512 MB or over 10 minutes
//        →  refused with a reason; nothing is added and staging is cleaned.
//
//  Every item gets a still (the static fallback) and a thumbnail.
//

#import <Foundation/Foundation.h>

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
FOUNDATION_EXPORT const double HACMaxStoredLongSide;          // 2688 px: larger videos are downscaled
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

@end

NS_ASSUME_NONNULL_END
