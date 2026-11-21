//
//  HACLibrary.h
//  HCG Animation Center — Hakmi Capital Group
//
//  The media library (Settings only). Each item is an HCG background preset
//  (format version 1) whose files live in the media folder:
//
//    /var/mobile/Library/HCGAnimationCenter/
//      library.json            {"formatVersion": 2, "items": [preset, …]}
//      Media/<ID>.mov|mp4      the video (video track only; GIFs converted)
//      Media/<ID>-still.jpg    the static fallback (Home Screen placement)
//      Media/<ID>-still-lock.jpg  the Lock Screen placement's own still, if any
//      Media/<ID>-thumb.jpg    the library thumbnail
//      Exports/<name>.hcgbackground/   one placement exported for sharing
//      Exports/<name>.hcgpack/         every placement (HCG animation pack v1)
//
//  Placements. Each item has settings per placement (the screen it is shown
//  on): trim, loop, speed, still, framing and orientation. The Home Screen
//  settings are the item itself. The Lock Screen follows the Home Screen until
//  its own settings are saved; then they are stored with the item as
//  "placements": {"lock-screen": preset} — an extra key that library readers
//  before 0.2 ignore (they keep the Home Screen settings). Media, name and
//  identity are shared by all placements of an item.
//
//  SpringBoard never reads library.json: applying a background copies the
//  placement's preset into the preferences (HACKeyHomePreset / HACKeyLockPreset).
//

#import <Foundation/Foundation.h>

#import "HACPolicy.h"
#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

/// Placement ids, shared with HCG animation packs ("placements.<id>").
FOUNDATION_EXPORT NSString *HACPlacementId(HACSurface placement); // "home-screen" | "lock-screen"

@interface HACLibrary : NSObject

+ (instancetype)shared;

/// Reloads from disk. A corrupt library.json is kept as library.corrupt-<time>.json
/// and the library starts empty; `loadProblem` says so.
- (void)reload;
/// The items (their Home Screen settings).
@property (nonatomic, readonly, copy) NSArray<HCGBackgroundPreset *> *items;
@property (nonatomic, readonly, copy) NSString *loadProblem;

- (nullable HCGBackgroundPreset *)itemWithIdentifier:(NSString *)identifier;
- (BOOL)addItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Saves the Home Screen settings (same as updateItem:placement:HACSurfaceHome).
- (BOOL)updateItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Removes the item and its files, and clears any assignment that uses it.
- (BOOL)removeItem:(HCGBackgroundPreset *)item error:(NSError **)error;

// Placements

/// A copy of the item's settings for a placement (the Lock Screen falls back
/// to the Home Screen settings). Nil if the item is not in the library.
- (nullable HCGBackgroundPreset *)presetForItem:(HCGBackgroundPreset *)item placement:(HACSurface)placement;
/// YES if the placement has its own saved settings (always YES for the Home Screen).
- (BOOL)item:(HCGBackgroundPreset *)item hasOwnSettingsForPlacement:(HACSurface)placement;
/// Saves one placement's settings. Shared fields (name, media) go to every
/// placement. Surfaces showing that placement are updated.
- (BOOL)updateItem:(HCGBackgroundPreset *)preset placement:(HACSurface)placement error:(NSError **)error;
/// The Lock Screen follows the Home Screen settings again (its own still is deleted).
- (BOOL)removeOwnLockSettingsOfItem:(HCGBackgroundPreset *)item error:(NSError **)error;

- (NSURL *)thumbnailURLForItem:(HCGBackgroundPreset *)item;
+ (NSString *)thumbnailFileForIdentifier:(NSString *)identifier;
+ (NSString *)stillFileForIdentifier:(NSString *)identifier;
+ (NSString *)stillFileForIdentifier:(NSString *)identifier placement:(HACSurface)placement;

/// Which surfaces use this item now (by preset identifier in the preferences).
- (BOOL)item:(HCGBackgroundPreset *)item isAssignedTo:(HACSurface)surface;

/// Copies the preset into the preferences for a surface (nil clears it) and
/// tells SpringBoard. The Lock Screen gets its own copy ("own" source). Pass
/// -presetForItem:placement: to apply a library item's placement settings.
+ (void)assignPreset:(nullable HCGBackgroundPreset *)preset toSurface:(HACSurface)surface;

// Sharing

/// Exports one placement as a folder <name>.hcgbackground (preset.json + files).
- (nullable NSURL *)exportItem:(HCGBackgroundPreset *)item placement:(HACSurface)placement error:(NSError **)error;
/// The Home Screen placement.
- (nullable NSURL *)exportItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Exports an HCG animation pack <name>.hcgpack with placements "home-screen",
/// "lock-screen" and "app-background" (the default, = Home Screen, so HCG
/// Animation Center for Mac and other version 1 readers can open it).
- (nullable NSURL *)exportPackForItem:(HCGBackgroundPreset *)item error:(NSError **)error;
/// Imports an exported .hcgbackground or .hcgpack folder (copies its files
/// under a new identifier; checksums are verified). From a pack, "home-screen"
/// (else the default placement) becomes the Home Screen settings and
/// "lock-screen", if present, the Lock Screen's own settings.
- (nullable HCGBackgroundPreset *)importPresetFolder:(NSURL *)folder error:(NSError **)error;

/// Bytes used by the media folder.
- (unsigned long long)mediaBytes;

@end

NS_ASSUME_NONNULL_END
