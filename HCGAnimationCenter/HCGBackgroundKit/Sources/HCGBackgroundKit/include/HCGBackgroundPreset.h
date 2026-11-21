//
//  HCGBackgroundPreset.h
//  HCGBackgroundKit — Hakmi Capital Group
//
//  The HCG background preset, format "com.hakmicapitalgroup.background-preset",
//  version 1 (Schema/hcg-background-preset-v1.schema.json, docs/PRESET-FORMAT.md).
//
//  A preset is DATA only: a media file name, how to trim, scale, loop and play
//  it, and a static fallback image. Nothing in a preset is executed, and a
//  preset never names a path outside its own folder.
//
//  Reading is strict about identity and safety (format, major version, file
//  names, required numbers) and tolerant about the rest: unknown keys are
//  ignored, out-of-range numbers are repaired and reported in `warnings`.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const HCGBackgroundPresetFormat;        // "com.hakmicapitalgroup.background-preset"
FOUNDATION_EXPORT const NSInteger HCGBackgroundPresetFormatVersion; // 1
FOUNDATION_EXPORT NSString *const HCGBackgroundPresetFileName;      // "preset.json" inside a .hcgbackground folder
FOUNDATION_EXPORT NSString *const HCGBackgroundErrorDomain;

typedef NS_ERROR_ENUM(HCGBackgroundErrorDomain, HCGBackgroundError) {
    HCGBackgroundErrorNotAPreset = 1,         ///< not a dictionary, or "format" is not the HCG preset format
    HCGBackgroundErrorUnsupportedVersion = 2, ///< formatVersion newer than this code (or not an integer)
    HCGBackgroundErrorMissingValue = 3,       ///< a required key is absent or the wrong type
    HCGBackgroundErrorInvalidValue = 4,       ///< a value can't be used (e.g. zero duration, tiny media)
    HCGBackgroundErrorUnsafeFileName = 5,     ///< a file name with "/", "..", a leading "." or control characters
    HCGBackgroundErrorUnreadable = 6,         ///< the file or JSON could not be read
    HCGBackgroundErrorMediaUnplayable = 7,    ///< (HCGBackgroundView) the media failed to load or play
};

typedef NS_ENUM(NSInteger, HCGBackgroundScaling) {
    HCGBackgroundScalingFill = 0, ///< "fill"
    HCGBackgroundScalingFit = 1,  ///< "fit"
    HCGBackgroundScalingCrop = 2, ///< "crop"
};

@interface HCGBackgroundPreset : NSObject <NSCopying>

// Identity
@property (nonatomic, copy) NSString *identifier; ///< UUID string
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSDate *created;

// Media (one video file; GIFs are converted to video when imported)
@property (nonatomic, copy) NSString *mediaFile;   ///< file name, relative to the preset's folder
@property (nonatomic) CGSize mediaSize;            ///< display size in pixels (after rotation)
@property (nonatomic) NSTimeInterval duration;     ///< source duration, seconds
@property (nonatomic, copy) NSString *origin;      ///< "video" | "gif" | "ai" (informational)
@property (nonatomic, copy, nullable) NSString *mediaSHA256;

// Static fallback
@property (nonatomic, copy, nullable) NSString *stillFile; ///< JPEG/PNG file name, or nil
@property (nonatomic) NSTimeInterval stillTime;            ///< where the still was taken, seconds

// Playback
@property (nonatomic) NSTimeInterval trimStart;
@property (nonatomic) NSTimeInterval trimEnd; ///< <= 0 on input means "to the end"
@property (nonatomic) BOOL loops;
@property (nonatomic) double speed;
/// Always YES in format version 1: backgrounds never play sound.
@property (nonatomic, readonly) BOOL muted;

// Layout
@property (nonatomic) HCGBackgroundScaling scaling;
@property (nonatomic) CGRect crop; ///< normalised to the media frame; used by "crop"
@property (nonatomic, copy) NSString *backgroundColor; ///< "#RRGGBB", behind "fit"

// Orientation and transformation — format v1 minor addition "layout.transform"
// (HCGBackgroundKit 1.1). Non-destructive: the media file is never changed;
// renderers apply these on top of the source's own orientation metadata.
// Readers before 1.1 ignore "layout.transform" and show the clip upright,
// unflipped and unstretched (with "fill" as the stretch fallback).

/// Clockwise quarter turns after the source's metadata: 0, 90, 180 or 270.
@property (nonatomic) NSInteger rotation;
/// Mirror left / right, then top / bottom — in screen axes, after rotating.
@property (nonatomic) BOOL flipHorizontal;
@property (nonatomic) BOOL flipVertical;
/// Fill the container exactly, ignoring the aspect ratio ("Stretch").
@property (nonatomic) BOOL stretch;
/// The preset carries a "layout.transform" object (read from one, or set by an
/// editor). With it, zoom and position (the crop rectangle) apply to "fit" and
/// stretch too. It is written whenever this is YES or the transform is not the
/// identity, so presets that never used a transform stay byte-identical.
@property (nonatomic) BOOL hasTransform;
/// YES if fit / stretch use the crop rectangle (hasTransform, or a non-identity transform).
@property (nonatomic, readonly) BOOL usesRegionInAllModes;
@property (nonatomic, readonly) BOOL isTransformIdentity;
/// The media's display size after `rotation` (sides swapped for 90 / 270).
@property (nonatomic, readonly) CGSize orientedMediaSize;
/// Informational "media.sourceRotation": the quarter turn the source's own
/// orientation metadata applies (0 / 90 / 180 / 270), or -1 if unknown.
@property (nonatomic) NSInteger sourceRotation;

/// Back to the source as recorded: no rotation, flips or stretch, Fill, the
/// whole frame, and no transform object.
- (void)resetTransform;

// Generator (informational: how the media was made)
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *generator;

/// Repairs made while reading or sanitising (human-readable).
@property (nonatomic, readonly, copy) NSArray<NSString *> *warnings;

/// A new preset for a media file with sensible defaults (fill, loop, 1x,
/// whole clip, still at the start).
+ (instancetype)presetWithMediaFile:(NSString *)mediaFile
                          mediaSize:(CGSize)mediaSize
                           duration:(NSTimeInterval)duration
                             origin:(NSString *)origin;

+ (nullable instancetype)presetWithDictionary:(NSDictionary<NSString *, id> *)dictionary error:(NSError **)error;
+ (nullable instancetype)presetWithJSONData:(NSData *)data error:(NSError **)error;
/// A preset.json file, or a folder containing one (e.g. "Aurora.hcgbackground").
+ (nullable instancetype)presetWithContentsOfURL:(NSURL *)url error:(NSError **)error;

/// Clamps every number into range (C core rules) and records warnings.
/// Returns NO, with an error, if the preset cannot be used at all.
- (BOOL)sanitizeWithError:(NSError **)error;

/// The canonical document (property-list and JSON compatible). Sanitises first.
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
- (nullable NSData *)JSONDataWithError:(NSError **)error;

/// mediaFile / stillFile resolved against a folder; nil if unsafe or absent.
- (nullable NSURL *)mediaURLInFolder:(NSURL *)folder;
- (nullable NSURL *)stillURLInFolder:(NSURL *)folder;

/// Trimmed clip length at 1x.
@property (nonatomic, readonly) NSTimeInterval clipDuration;

/// Whether a file name is safe to resolve inside a preset's folder.
+ (BOOL)isSafeFileName:(nullable NSString *)name;

+ (NSString *)identifierForScaling:(HCGBackgroundScaling)scaling;

@end

NS_ASSUME_NONNULL_END
