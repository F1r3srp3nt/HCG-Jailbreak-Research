//
//  HACLibrary.h
//  HCG Animation Center — Hakmi Capital Group
//
//  The media library (Settings only). Each item is an HCG background preset
//  (format version 1) whose files live in the media folder:
//
//    /var/mobile/Library/HCGAnimationCenter/
//      library.json            {"formatVersion": 1, "items": [preset, …]}
//      Media/<ID>.mov|mp4      the video (video track only; GIFs converted)
//      Media/<ID>-still.jpg    the static fallback
//      Media/<ID>-thumb.jpg    the library thumbnail
//      Exports/<name>.hcgbackground/   presets exported for sharing
//
//  SpringBoard never reads library.json: applying a background copies its
//  preset into the preferences (HACKeyHomePreset / HACKeyLockPreset).
//

#import <Foundation/Foundation.h>

#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

@interface HACLibrary : NSObject

+ (instancetype)shared;

/// Reloads from disk. A corrupt library.json is kept as library.corrupt-<time>.json
/// and the library starts empty; `loadProblem` says so.
- (void)reload;
@property (nonatomic, readonly, copy) NSArray<HCGBackgroundPreset *> *items;
@property (nonatomic, readonly, copy) NSString *loadProblem;

- (nullable HCGBackgroundPreset *)itemWithIdentifier:(NSString *)identifier;
- (BOOL)addItem:(HCGBackgroundPreset *)item error:(NSError **)error;
- (BOOL)updateItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Removes the item and its files, and clears any assignment that uses it.
- (BOOL)removeItem:(HCGBackgroundPreset *)item error:(NSError **)error;

- (NSURL *)thumbnailURLForItem:(HCGBackgroundPreset *)item;
+ (NSString *)thumbnailFileForIdentifier:(NSString *)identifier;
+ (NSString *)stillFileForIdentifier:(NSString *)identifier;

/// Which surfaces use this item now (by preset identifier in the preferences).
- (BOOL)item:(HCGBackgroundPreset *)item isAssignedTo:(HACSurface)surface;

/// Copies the preset into the preferences for a surface (nil clears it) and
/// tells SpringBoard. The Lock Screen gets its own copy ("own" source).
+ (void)assignPreset:(nullable HCGBackgroundPreset *)preset toSurface:(HACSurface)surface;

/// Exports a shareable folder <name>.hcgbackground (preset.json + files).
- (nullable NSURL *)exportItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Imports an exported folder (copies its files under a new identifier).
- (nullable HCGBackgroundPreset *)importPresetFolder:(NSURL *)folder error:(NSError **)error;

/// Bytes used by the media folder.
- (unsigned long long)mediaBytes;

@end

NS_ASSUME_NONNULL_END
