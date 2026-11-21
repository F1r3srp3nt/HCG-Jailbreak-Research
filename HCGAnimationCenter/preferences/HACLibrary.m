//
//  HACLibrary.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACLibrary.h"
#import "HACPreferences.h"
#import "HCGBackgroundCore.h"

#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>

static NSString *const kLibraryFile = @"library.json";
/// 2 (0.2): entries may carry "placements": {"lock-screen": preset}. Entries
/// are still complete version 1 presets, so 0.1 reads a version 2 library.
static const NSInteger kLibraryFormatVersion = 2;
static NSString *const kPlacementsKey = @"placements";
/// Exported / imported media larger than this is refused.
static const unsigned long long kMaxImportedMediaBytes = 512ull * 1024 * 1024;

static NSString *const kPackFormat = @"com.hakmicapitalgroup.animation-pack";
static const NSInteger kPackFormatVersion = 1;
static NSString *const kPackFile = @"pack.json";
/// Version 1 pack placements, in the order a reader falls back through them.
static NSArray<NSString *> *KnownPackPlacements(void) {
    return @[ @"app-background", @"desktop", @"loading-screen", @"banner" ];
}

NSString *HACPlacementId(HACSurface placement) {
    return placement == HACSurfaceLock ? @"lock-screen" : @"home-screen";
}

static NSError *LibraryError(NSString *message) {
    return [NSError errorWithDomain:@"com.hakmicapitalgroup.animationcenter.library"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

/// Fields every placement of an item shares (the clip and its identity).
static void CopyShared(HCGBackgroundPreset *from, HCGBackgroundPreset *to) {
    to.identifier = from.identifier;
    to.name = from.name;
    to.created = from.created;
    to.mediaFile = from.mediaFile;
    to.mediaSize = from.mediaSize;
    to.duration = from.duration;
    to.origin = from.origin;
    to.mediaSHA256 = from.mediaSHA256;
    to.sourceRotation = from.sourceRotation;
    to.generator = from.generator;
}

static BOOL SameClip(HCGBackgroundPreset *a, HCGBackgroundPreset *b) {
    return [a.mediaFile isEqualToString:b.mediaFile] && CGSizeEqualToSize(a.mediaSize, b.mediaSize) &&
           fabs(a.duration - b.duration) < 0.001;
}

static NSString *SHA256OfFile(NSURL *url) {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    if (!stream) return nil;
    [stream open];
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    uint8_t buffer[64 * 1024];
    NSInteger n;
    while ((n = [stream read:buffer maxLength:sizeof buffer]) > 0) CC_SHA256_Update(&ctx, buffer, (CC_LONG)n);
    [stream close];
    if (n < 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static unsigned long long SizeOfFile(NSURL *url) {
    return [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL].fileSize;
}

@implementation HACLibrary {
    NSMutableArray<HCGBackgroundPreset *> *_items;
    NSMutableDictionary<NSString *, HCGBackgroundPreset *> *_lockPresets; // identifier → own Lock Screen settings
    NSString *_loadProblem;
}

+ (instancetype)shared {
    static HACLibrary *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        library = [[HACLibrary alloc] init];
        [library reload];
    });
    return library;
}

- (NSArray<HCGBackgroundPreset *> *)items {
    return [_items copy];
}

- (NSString *)loadProblem {
    return _loadProblem ?: @"";
}

- (NSURL *)libraryURL {
    return [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:kLibraryFile]];
}

- (void)reload {
    _items = [NSMutableArray array];
    _lockPresets = [NSMutableDictionary dictionary];
    _loadProblem = @"";
    NSData *data = [NSData dataWithContentsOfURL:[self libraryURL]];
    if (!data) return; // no library yet
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray *items = [root isKindOfClass:[NSDictionary class]] ? root[@"items"] : nil;
    if (![items isKindOfClass:[NSArray class]]) {
        [self quarantineLibraryFile];
        return;
    }
    NSUInteger rejected = 0, rejectedPlacements = 0;
    for (id entry in items) {
        HCGBackgroundPreset *preset = [entry isKindOfClass:[NSDictionary class]]
                                          ? [HCGBackgroundPreset presetWithDictionary:entry error:NULL]
                                          : nil;
        if (!preset || [self itemWithIdentifier:preset.identifier]) {
            rejected++;
            continue;
        }
        [_items addObject:preset];
        NSDictionary *placements = entry[kPlacementsKey];
        id lockDocument = [placements isKindOfClass:[NSDictionary class]] ? placements[HACPlacementId(HACSurfaceLock)] : nil;
        if (!lockDocument) continue;
        HCGBackgroundPreset *lock = [lockDocument isKindOfClass:[NSDictionary class]]
                                        ? [HCGBackgroundPreset presetWithDictionary:lockDocument error:NULL]
                                        : nil;
        if (lock && SameClip(preset, lock)) {
            CopyShared(preset, lock);
            _lockPresets[preset.identifier] = lock;
        } else {
            rejectedPlacements++; // the Lock Screen follows the Home Screen settings
        }
    }
    NSMutableArray *problems = [NSMutableArray array];
    if (rejected)
        [problems addObject:[NSString stringWithFormat:@"%lu library entr%@ could not be read and %@ skipped.",
                                                       (unsigned long)rejected, rejected == 1 ? @"y" : @"ies",
                                                       rejected == 1 ? @"was" : @"were"]];
    if (rejectedPlacements)
        [problems addObject:[NSString stringWithFormat:@"%lu Lock Screen setting%@ could not be read; %@ the Home "
                                                       @"Screen settings.",
                                                       (unsigned long)rejectedPlacements,
                                                       rejectedPlacements == 1 ? @"" : @"s",
                                                       rejectedPlacements == 1 ? @"it uses" : @"they use"]];
    _loadProblem = [problems componentsJoinedByString:@" "];
}

- (void)quarantineLibraryFile {
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"library.corrupt-%@.json", [format stringFromDate:[NSDate date]]];
    NSURL *backup = [[[self libraryURL] URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
    [[NSFileManager defaultManager] moveItemAtURL:[self libraryURL] toURL:backup error:NULL];
    _loadProblem = [NSString stringWithFormat:@"The library file was unreadable. It was kept as %@ and the library "
                                              @"starts empty; your media files were not deleted.",
                                              name];
}

- (BOOL)save:(NSError **)error {
    NSMutableArray *documents = [NSMutableArray array];
    for (HCGBackgroundPreset *item in _items) {
        NSMutableDictionary *document = [[item dictionaryRepresentation] mutableCopy];
        HCGBackgroundPreset *lock = _lockPresets[item.identifier];
        if (lock) document[kPlacementsKey] = @{HACPlacementId(HACSurfaceLock) : [lock dictionaryRepresentation]};
        [documents addObject:document];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"formatVersion" : @(kLibraryFormatVersion), @"items" : documents}
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:error];
    if (!data) return NO;
    NSURL *url = [self libraryURL];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error])
        return NO;
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (HCGBackgroundPreset *)itemWithIdentifier:(NSString *)identifier {
    for (HCGBackgroundPreset *item in _items)
        if ([item.identifier isEqualToString:identifier]) return item;
    return nil;
}

- (NSUInteger)indexOfIdentifier:(NSString *)identifier {
    for (NSUInteger i = 0; i < _items.count; i++)
        if ([_items[i].identifier isEqualToString:identifier]) return i;
    return NSNotFound;
}

- (BOOL)addItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    if ([self itemWithIdentifier:item.identifier]) return [self updateItem:item error:error];
    if (![item sanitizeWithError:error]) return NO;
    [_items insertObject:[item copy] atIndex:0];
    return [self save:error];
}

- (BOOL)updateItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    return [self updateItem:item placement:HACSurfaceHome error:error];
}

#pragma mark Placements

- (HCGBackgroundPreset *)presetForItem:(HCGBackgroundPreset *)item placement:(HACSurface)placement {
    NSUInteger i = [self indexOfIdentifier:item.identifier];
    if (i == NSNotFound) return nil;
    HCGBackgroundPreset *own = placement == HACSurfaceLock ? _lockPresets[item.identifier] : nil;
    return [own ?: _items[i] copy];
}

- (BOOL)item:(HCGBackgroundPreset *)item hasOwnSettingsForPlacement:(HACSurface)placement {
    if (placement == HACSurfaceHome) return [self indexOfIdentifier:item.identifier] != NSNotFound;
    return _lockPresets[item.identifier] != nil;
}

- (BOOL)updateItem:(HCGBackgroundPreset *)preset placement:(HACSurface)placement error:(NSError **)error {
    if (![preset sanitizeWithError:error]) return NO;
    NSUInteger i = [self indexOfIdentifier:preset.identifier];
    if (i == NSNotFound) {
        if (error) *error = LibraryError(@"That background is no longer in the library.");
        return NO;
    }
    if (!SameClip(_items[i], preset)) {
        if (error) *error = LibraryError(@"These settings are for a different video.");
        return NO;
    }
    HCGBackgroundPreset *edited = [preset copy];
    NSString *identifier = edited.identifier;
    if (placement == HACSurfaceHome) {
        _items[i] = edited;
        if (_lockPresets[identifier]) CopyShared(edited, _lockPresets[identifier]);
    } else {
        // The Lock Screen gets its own still file, so later Home Screen edits
        // never change the Lock Screen's still.
        NSString *lockStill = [HACLibrary stillFileForIdentifier:identifier placement:HACSurfaceLock];
        if (edited.stillFile && ![edited.stillFile isEqualToString:lockStill]) {
            NSURL *media = [HACPreferences mediaFolder];
            NSURL *from = [edited stillURLInFolder:media], *to = [media URLByAppendingPathComponent:lockStill];
            [[NSFileManager defaultManager] removeItemAtURL:to error:NULL];
            if (from && [[NSFileManager defaultManager] copyItemAtURL:from toURL:to error:NULL]) edited.stillFile = lockStill;
        }
        HCGBackgroundPreset *home = [_items[i] copy];
        CopyShared(edited, home);
        _items[i] = home;
        _lockPresets[identifier] = edited;
    }
    if (![self save:error]) return NO;
    [self refreshAssignmentsOfItem:edited];
    return YES;
}

- (BOOL)removeOwnLockSettingsOfItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    HCGBackgroundPreset *lock = _lockPresets[item.identifier];
    if (!lock) return YES;
    [_lockPresets removeObjectForKey:item.identifier];
    if (![self save:error]) {
        _lockPresets[item.identifier] = lock;
        return NO;
    }
    NSString *lockStill = [HACLibrary stillFileForIdentifier:item.identifier placement:HACSurfaceLock];
    [[NSFileManager defaultManager] removeItemAtURL:[[HACPreferences mediaFolder] URLByAppendingPathComponent:lockStill]
                                              error:NULL];
    [self refreshAssignmentsOfItem:item];
    return YES;
}

/// Surfaces that show this item get its current placement settings.
- (void)refreshAssignmentsOfItem:(HCGBackgroundPreset *)item {
    HACSettings *settings = [HACPreferences loadSettings];
    for (int s = 0; s < HAC_SURFACE_COUNT; s++) {
        HACSurface surface = (HACSurface)s;
        // "Same as Home Screen" follows the Home Screen preset by itself; assigning
        // would switch the Lock Screen to its own copy.
        if (surface == HACSurfaceLock && settings.lockSameAsHome) continue;
        if ([self item:item isAssignedTo:surface])
            [HACLibrary assignPreset:[self presetForItem:item placement:surface] toSurface:surface];
    }
}

- (BOOL)removeItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    for (int s = 0; s < HAC_SURFACE_COUNT; s++)
        if ([self item:item isAssignedTo:(HACSurface)s]) [HACLibrary assignPreset:nil toSurface:(HACSurface)s];
    NSURL *folder = [HACPreferences mediaFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    HCGBackgroundPreset *lock = _lockPresets[item.identifier];
    for (NSString *name in @[ item.mediaFile ?: @"", item.stillFile ?: @"", lock.stillFile ?: @"",
                              [HACLibrary thumbnailFileForIdentifier:item.identifier],
                              [HACLibrary stillFileForIdentifier:item.identifier placement:HACSurfaceLock] ]) {
        if ([HCGBackgroundPreset isSafeFileName:name]) [fm removeItemAtURL:[folder URLByAppendingPathComponent:name] error:NULL];
    }
    [_lockPresets removeObjectForKey:item.identifier];
    NSUInteger before = _items.count;
    [_items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HCGBackgroundPreset *p, NSDictionary *bindings) {
                return ![p.identifier isEqualToString:item.identifier];
            }]];
    if (_items.count == before) return YES;
    return [self save:error];
}

+ (NSString *)thumbnailFileForIdentifier:(NSString *)identifier {
    return [identifier stringByAppendingString:@"-thumb.jpg"];
}

+ (NSString *)stillFileForIdentifier:(NSString *)identifier {
    return [self stillFileForIdentifier:identifier placement:HACSurfaceHome];
}

+ (NSString *)stillFileForIdentifier:(NSString *)identifier placement:(HACSurface)placement {
    return [identifier stringByAppendingString:placement == HACSurfaceLock ? @"-still-lock.jpg" : @"-still.jpg"];
}

- (NSURL *)thumbnailURLForItem:(HCGBackgroundPreset *)item {
    NSURL *folder = [HACPreferences mediaFolder];
    NSURL *thumb = [folder URLByAppendingPathComponent:[HACLibrary thumbnailFileForIdentifier:item.identifier]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumb.path]) return thumb;
    return [item stillURLInFolder:folder] ?: thumb;
}

- (BOOL)item:(HCGBackgroundPreset *)item isAssignedTo:(HACSurface)surface {
    HACSettings *settings = [HACPreferences loadSettings];
    if (surface == HACSurfaceLock && !settings.lockEnabled) return NO;
    if (surface == HACSurfaceHome && !settings.homeEnabled) return NO;
    return [[settings presetForSurface:surface].identifier isEqualToString:item.identifier];
}

+ (void)assignPreset:(HCGBackgroundPreset *)preset toSurface:(HACSurface)surface {
    NSString *key = surface == HACSurfaceLock ? HACKeyLockPreset : HACKeyHomePreset;
    if (surface == HACSurfaceLock && preset) {
        CFPreferencesSetAppValue((__bridge CFStringRef)HACKeyLockSource, CFSTR("own"),
                                 (__bridge CFStringRef)HACPreferencesDomain);
    }
    [HACPreferences setValue:preset ? [preset dictionaryRepresentation] : nil forKey:key];
}

#pragma mark Export

- (NSURL *)freshExportFolderForItem:(HCGBackgroundPreset *)item extension:(NSString *)extension error:(NSError **)error {
    NSString *safeName = [[item.name componentsSeparatedByCharactersInSet:
                                         [[NSCharacterSet alphanumericCharacterSet] invertedSet]]
        componentsJoinedByString:@"-"];
    if (safeName.length == 0) safeName = @"Background";
    NSURL *exports = [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:@"Exports"]
                                isDirectory:YES];
    NSURL *folder = [exports URLByAppendingPathComponent:[safeName stringByAppendingPathExtension:extension]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtURL:folder error:NULL];
    if (![fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    return folder;
}

- (NSURL *)exportItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    return [self exportItem:item placement:HACSurfaceHome error:error];
}

- (NSURL *)exportItem:(HCGBackgroundPreset *)item placement:(HACSurface)placement error:(NSError **)error {
    HCGBackgroundPreset *copy = [self presetForItem:item placement:placement] ?: [item copy];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *media = [HACPreferences mediaFolder];
    NSURL *folder = [self freshExportFolderForItem:copy extension:@"hcgbackground" error:error];
    if (!folder) return nil;
    NSString *mediaName = [@"media" stringByAppendingPathExtension:copy.mediaFile.pathExtension ?: @"mov"];
    NSURL *mediaSource = [copy mediaURLInFolder:media];
    if (!mediaSource || ![fm copyItemAtURL:mediaSource toURL:[folder URLByAppendingPathComponent:mediaName] error:error])
        return nil;
    copy.mediaFile = mediaName;
    NSURL *still = [copy stillURLInFolder:media];
    NSString *stillName = [@"still" stringByAppendingPathExtension:copy.stillFile.pathExtension ?: @"jpg"];
    if (still && [fm copyItemAtURL:still toURL:[folder URLByAppendingPathComponent:stillName] error:NULL]) {
        copy.stillFile = stillName;
    } else {
        copy.stillFile = nil;
    }
    NSData *json = [copy JSONDataWithError:error];
    if (!json || ![json writeToURL:[folder URLByAppendingPathComponent:HCGBackgroundPresetFileName]
                           options:NSDataWritingAtomic
                             error:error])
        return nil;
    return folder;
}

static NSString *ISO8601(NSDate *date) {
    NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
    f.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [f stringFromDate:date ?: [NSDate date]];
}

- (NSURL *)exportPackForItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    HCGBackgroundPreset *home = [self presetForItem:item placement:HACSurfaceHome];
    if (!home) {
        if (error) *error = LibraryError(@"That background is no longer in the library.");
        return nil;
    }
    HCGBackgroundPreset *lock = _lockPresets[item.identifier] ? [self presetForItem:item placement:HACSurfaceLock] : nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *mediaFolder = [HACPreferences mediaFolder];
    NSURL *folder = [self freshExportFolderForItem:home extension:@"hcgpack" error:error];
    if (!folder) return nil;

    NSString *mediaName = [@"media" stringByAppendingPathExtension:home.mediaFile.pathExtension.lowercaseString ?: @"mov"];
    NSURL *mediaCopy = [folder URLByAppendingPathComponent:mediaName];
    NSURL *mediaSource = [home mediaURLInFolder:mediaFolder];
    if (!mediaSource || ![fm copyItemAtURL:mediaSource toURL:mediaCopy error:error]) return nil;
    NSString *mediaSHA = SHA256OfFile(mediaCopy);
    if (!mediaSHA) {
        if (error) *error = LibraryError(@"The video could not be read for its checksum.");
        return nil;
    }

    NSMutableArray *files = [NSMutableArray array];
    // Copies a placement's still into the pack under `name` and lists it.
    BOOL (^addStill)(HCGBackgroundPreset *, NSString *, NSString *) = ^BOOL(HCGBackgroundPreset *p, NSString *name, NSString *role) {
        NSURL *source = [p stillURLInFolder:mediaFolder];
        NSURL *target = [folder URLByAppendingPathComponent:name];
        if (!source || ![fm copyItemAtURL:source toURL:target error:NULL]) {
            p.stillFile = nil;
            return NO;
        }
        [files addObject:@{@"file" : name, @"bytes" : @(SizeOfFile(target)), @"sha256" : SHA256OfFile(target) ?: @"",
                           @"role" : role}];
        p.stillFile = name;
        return YES;
    };
    for (HCGBackgroundPreset *p in lock ? @[ home, lock ] : @[ home ]) {
        p.mediaFile = mediaName;
        p.mediaSHA256 = mediaSHA;
    }
    addStill(home, @"poster.jpg", @"poster");
    if (lock) addStill(lock, @"still-lock-screen.jpg", @"still");

    HACSettings *settings = [HACPreferences loadSettings];
    NSString *reduceMotion = settings.reduceMotionPolicy == HACReduceMotionPlay ? @"play" : @"still";
    NSString *lowPower = settings.lowPowerPolicy == HACLowPowerPlay     ? @"play"
                         : settings.lowPowerPolicy == HACLowPowerSystem ? @"system"
                                                                        : @"still";
    CGSize screen = UIScreen.mainScreen.nativeBounds.size; // portrait pixels
    if (screen.width < 1 || screen.height < 1) screen = CGSizeMake(1179, 2556); // no screen (tests): a 6.1" iPhone
    NSDictionary *canvas = @{@"width" : @(round(MIN(screen.width, screen.height))),
                             @"height" : @(round(MAX(screen.width, screen.height)))};
    NSDictionary *homeDocument = [home dictionaryRepresentation];
    NSDictionary * (^placement)(NSDictionary *) = ^NSDictionary *(NSDictionary *preset) {
        return @{@"canvas" : canvas, @"reduceMotion" : reduceMotion, @"lowPower" : lowPower, @"preset" : preset};
    };
    NSString *version = [[NSBundle bundleForClass:[HACLibrary class]] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSDictionary *pack = @{
        @"format" : kPackFormat,
        @"formatVersion" : @(kPackFormatVersion),
        @"id" : home.identifier,
        @"name" : home.name,
        @"created" : ISO8601(home.created),
        @"generator" : @{@"app" : @"HCG Animation Center for iOS", @"version" : version ?: @"0"},
        @"presetFormat" : @{@"format" : HCGBackgroundPresetFormat, @"formatVersion" : @(HCGBackgroundPresetFormatVersion)},
        @"media" : @{
            @"file" : mediaName,
            @"bytes" : @(SizeOfFile(mediaCopy)),
            @"sha256" : mediaSHA,
            @"width" : @(home.mediaSize.width),
            @"height" : @(home.mediaSize.height),
            @"duration" : @(home.duration),
            @"origin" : home.origin ?: @"video",
        },
        @"files" : files,
        // A version 1 placement, so every pack reader (HCG Animation Center for
        // Mac included) has one it knows; home-screen / lock-screen are minor
        // additions that those readers ignore.
        @"defaultPlacement" : @"app-background",
        @"placements" : @{
            @"app-background" : placement(homeDocument),
            HACPlacementId(HACSurfaceHome) : placement(homeDocument),
            HACPlacementId(HACSurfaceLock) : placement(lock ? [lock dictionaryRepresentation] : homeDocument),
        },
    };
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
    NSData *packData = [NSJSONSerialization dataWithJSONObject:pack options:options error:error];
    NSData *presetData = [NSJSONSerialization dataWithJSONObject:homeDocument options:options error:error];
    if (!packData || !presetData ||
        ![packData writeToURL:[folder URLByAppendingPathComponent:kPackFile] options:NSDataWritingAtomic error:error] ||
        ![presetData writeToURL:[folder URLByAppendingPathComponent:HCGBackgroundPresetFileName]
                        options:NSDataWritingAtomic
                          error:error])
        return nil;
    return folder;
}

#pragma mark Import

- (HCGBackgroundPreset *)importPresetFolder:(NSURL *)folder error:(NSError **)error {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[folder URLByAppendingPathComponent:kPackFile].path])
        return [self importPackFolder:folder error:error];
    HCGBackgroundPreset *preset = [HCGBackgroundPreset presetWithContentsOfURL:folder error:error];
    if (!preset) return nil;
    return [self adoptHome:preset lock:nil fromFolder:folder expectedSHA256:preset.mediaSHA256 error:error];
}

/// The listed size and checksum of a file in a pack, or NO.
static BOOL MatchesListing(NSURL *file, NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]]) return NO;
    NSNumber *bytes = entry[@"bytes"];
    NSString *sha = entry[@"sha256"];
    if (![bytes isKindOfClass:[NSNumber class]] || ![sha isKindOfClass:[NSString class]]) return NO;
    return SizeOfFile(file) == bytes.unsignedLongLongValue && [SHA256OfFile(file) isEqualToString:sha.lowercaseString];
}

- (HCGBackgroundPreset *)importPackFolder:(NSURL *)folder error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:[folder URLByAppendingPathComponent:kPackFile]];
    NSDictionary *pack = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![pack isKindOfClass:[NSDictionary class]] || ![pack[@"format"] isEqual:kPackFormat]) {
        if (error) *error = LibraryError(@"This is not an HCG animation pack.");
        return nil;
    }
    NSNumber *version = pack[@"formatVersion"];
    if (![version isKindOfClass:[NSNumber class]] || version.doubleValue != floor(version.doubleValue)) {
        if (error) *error = LibraryError(@"The pack has no valid format version.");
        return nil;
    }
    if (version.integerValue > kPackFormatVersion) {
        if (error) *error = LibraryError(@"This pack was made by a newer version. Update HCG Animation Center to use it.");
        return nil;
    }
    NSDictionary *media = pack[@"media"];
    NSString *mediaName = [media isKindOfClass:[NSDictionary class]] ? media[@"file"] : nil;
    if (![HCGBackgroundPreset isSafeFileName:mediaName] || ![media[@"sha256"] isKindOfClass:[NSString class]]) {
        if (error) *error = LibraryError(@"The pack does not name its video correctly.");
        return nil;
    }
    NSURL *mediaURL = [folder URLByAppendingPathComponent:mediaName];
    NSNumber *mediaBytes = media[@"bytes"];
    if (![mediaBytes isKindOfClass:[NSNumber class]] || SizeOfFile(mediaURL) != mediaBytes.unsignedLongLongValue) {
        if (error) *error = LibraryError(@"The pack's video is missing or not the size the pack lists; it may be damaged.");
        return nil;
    }
    NSMutableDictionary<NSString *, NSDictionary *> *listed = [NSMutableDictionary dictionary];
    NSArray *files = [pack[@"files"] isKindOfClass:[NSArray class]] ? pack[@"files"] : @[];
    for (NSDictionary *entry in files)
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"file"] isKindOfClass:[NSString class]])
            listed[entry[@"file"]] = entry;

    NSDictionary *placements = [pack[@"placements"] isKindOfClass:[NSDictionary class]] ? pack[@"placements"] : @{};
    NSDictionary * (^presetDocument)(NSString *) = ^NSDictionary *(NSString *placementId) {
        NSDictionary *p = placementId ? placements[placementId] : nil;
        return [p isKindOfClass:[NSDictionary class]] && [p[@"preset"] isKindOfClass:[NSDictionary class]] ? p[@"preset"] : nil;
    };
    NSDictionary *homeDocument = presetDocument(HACPlacementId(HACSurfaceHome));
    NSString *defaultPlacement = [pack[@"defaultPlacement"] isKindOfClass:[NSString class]] ? pack[@"defaultPlacement"] : nil;
    if (!homeDocument) homeDocument = presetDocument(defaultPlacement);
    for (NSString *known in KnownPackPlacements())
        if (!homeDocument) homeDocument = presetDocument(known);
    if (!homeDocument) {
        if (error) *error = LibraryError(@"The pack has no placement this version can show.");
        return nil;
    }
    NSDictionary *lockDocument = presetDocument(HACPlacementId(HACSurfaceLock));

    NSMutableArray<HCGBackgroundPreset *> *presets = [NSMutableArray array];
    for (NSDictionary *document in lockDocument ? @[ homeDocument, lockDocument ] : @[ homeDocument ]) {
        NSError *presetError = nil;
        HCGBackgroundPreset *p = [HCGBackgroundPreset presetWithDictionary:document error:&presetError];
        if (!p) {
            if (error)
                *error = LibraryError([NSString stringWithFormat:@"A placement in the pack can't be read: %@",
                                                                 presetError.localizedDescription]);
            return nil;
        }
        if (![p.mediaFile isEqualToString:mediaName]) {
            if (error) *error = LibraryError(@"A placement in the pack uses a different video.");
            return nil;
        }
        if (p.stillFile) {
            NSURL *still = [p stillURLInFolder:folder];
            if (!still || !MatchesListing(still, listed[p.stillFile])) {
                if (error) *error = LibraryError(@"A still image in the pack is missing or damaged.");
                return nil;
            }
        }
        [presets addObject:p];
    }
    HCGBackgroundPreset *home = presets[0], *lock = presets.count > 1 ? presets[1] : nil;
    if (lock && !SameClip(home, lock)) {
        if (error) *error = LibraryError(@"The pack's placements describe different videos.");
        return nil;
    }
    if ([pack[@"name"] isKindOfClass:[NSString class]] && [pack[@"name"] length]) home.name = pack[@"name"];
    return [self adoptHome:home lock:lock fromFolder:folder expectedSHA256:[media[@"sha256"] lowercaseString] error:error];
}

/// Copies an imported placement set's files into the library under a new identifier.
- (HCGBackgroundPreset *)adoptHome:(HCGBackgroundPreset *)home
                              lock:(HCGBackgroundPreset *)lock
                        fromFolder:(NSURL *)folder
                    expectedSHA256:(NSString *)expected
                             error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *source = [home mediaURLInFolder:folder];
    NSDictionary *attributes = source ? [fm attributesOfItemAtPath:source.path error:NULL] : nil;
    if (![attributes.fileType isEqualToString:NSFileTypeRegular]) {
        if (error) *error = LibraryError(@"The preset's video file is missing from the folder.");
        return nil;
    }
    if (attributes.fileSize > kMaxImportedMediaBytes) {
        if (error) *error = LibraryError(@"The preset's video is larger than 512 MB.");
        return nil;
    }
    if (expected && ![SHA256OfFile(source) isEqualToString:expected]) {
        if (error) *error = LibraryError(@"The video does not match the preset's checksum; it may be damaged.");
        return nil;
    }
    NSString *identifier = [NSUUID UUID].UUIDString;
    NSURL *media = [HACPreferences mediaFolder];
    if (![fm createDirectoryAtURL:media withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *ext = source.pathExtension.length ? source.pathExtension.lowercaseString : @"mov";
    if (![@[ @"mov", @"mp4", @"m4v" ] containsObject:ext]) ext = @"mov";
    NSString *mediaName = [identifier stringByAppendingPathExtension:ext];
    NSURL *mediaTarget = [media URLByAppendingPathComponent:mediaName];
    if (![fm copyItemAtURL:source toURL:mediaTarget error:error]) return nil;

    NSArray *pairs = lock ? @[ @[ home, @(HACSurfaceHome) ], @[ lock, @(HACSurfaceLock) ] ] : @[ @[ home, @(HACSurfaceHome) ] ];
    for (NSArray *pair in pairs) {
        HCGBackgroundPreset *p = pair[0];
        NSURL *still = [p stillURLInFolder:folder];
        NSString *stillName = [HACLibrary stillFileForIdentifier:identifier placement:(HACSurface)[pair[1] integerValue]];
        [fm removeItemAtURL:[media URLByAppendingPathComponent:stillName] error:NULL];
        p.stillFile = still && [fm copyItemAtURL:still toURL:[media URLByAppendingPathComponent:stillName] error:NULL]
                          ? stillName
                          : nil;
    }
    home.identifier = identifier;
    home.mediaFile = mediaName;
    home.mediaSHA256 = SHA256OfFile(mediaTarget);
    if (lock) CopyShared(home, lock);
    if (![self addItem:home error:error]) {
        [fm removeItemAtURL:mediaTarget error:NULL];
        return nil;
    }
    if (lock && ![lock sanitizeWithError:NULL]) lock = nil;
    if (lock) {
        _lockPresets[identifier] = [lock copy];
        if (![self save:error]) return nil;
    }
    return [home copy];
}

- (unsigned long long)mediaBytes {
    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtURL:[HACPreferences mediaFolder]
                                                    includingPropertiesForKeys:@[ NSURLFileSizeKey ]
                                                                       options:0
                                                                  errorHandler:nil];
    for (NSURL *url in e) {
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        total += size.unsignedLongLongValue;
    }
    return total;
}

@end
