//
//  HACLibrary.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACLibrary.h"
#import "HACPreferences.h"
#import "HCGBackgroundCore.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const kLibraryFile = @"library.json";
static const NSInteger kLibraryFormatVersion = 1;
/// Exported / imported media larger than this is refused.
static const unsigned long long kMaxImportedMediaBytes = 512ull * 1024 * 1024;

static NSError *LibraryError(NSString *message) {
    return [NSError errorWithDomain:@"com.hakmicapitalgroup.animationcenter.library"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation HACLibrary {
    NSMutableArray<HCGBackgroundPreset *> *_items;
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
    _loadProblem = @"";
    NSData *data = [NSData dataWithContentsOfURL:[self libraryURL]];
    if (!data) return; // no library yet
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray *items = [root isKindOfClass:[NSDictionary class]] ? root[@"items"] : nil;
    if (![items isKindOfClass:[NSArray class]]) {
        [self quarantineLibraryFile];
        return;
    }
    NSUInteger rejected = 0;
    for (id entry in items) {
        HCGBackgroundPreset *preset = [entry isKindOfClass:[NSDictionary class]]
                                          ? [HCGBackgroundPreset presetWithDictionary:entry error:NULL]
                                          : nil;
        if (preset && ![self itemWithIdentifier:preset.identifier]) {
            [_items addObject:preset];
        } else {
            rejected++;
        }
    }
    if (rejected)
        _loadProblem = [NSString stringWithFormat:@"%lu library entr%@ could not be read and %@ skipped.",
                                                  (unsigned long)rejected, rejected == 1 ? @"y" : @"ies",
                                                  rejected == 1 ? @"was" : @"were"];
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
    for (HCGBackgroundPreset *item in _items) [documents addObject:[item dictionaryRepresentation]];
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

- (BOOL)addItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    if ([self itemWithIdentifier:item.identifier]) return [self updateItem:item error:error];
    if (![item sanitizeWithError:error]) return NO;
    [_items insertObject:[item copy] atIndex:0];
    return [self save:error];
}

- (BOOL)updateItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    if (![item sanitizeWithError:error]) return NO;
    for (NSUInteger i = 0; i < _items.count; i++) {
        if ([_items[i].identifier isEqualToString:item.identifier]) {
            _items[i] = [item copy];
            if (![self save:error]) return NO;
            // Keep any assignment of this item in step with the edit.
            for (int s = 0; s < HAC_SURFACE_COUNT; s++)
                if ([self item:item isAssignedTo:(HACSurface)s]) [HACLibrary assignPreset:item toSurface:(HACSurface)s];
            return YES;
        }
    }
    if (error) *error = LibraryError(@"That background is no longer in the library.");
    return NO;
}

- (BOOL)removeItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    for (int s = 0; s < HAC_SURFACE_COUNT; s++)
        if ([self item:item isAssignedTo:(HACSurface)s]) [HACLibrary assignPreset:nil toSurface:(HACSurface)s];
    NSURL *folder = [HACPreferences mediaFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in @[ item.mediaFile ?: @"", item.stillFile ?: @"",
                              [HACLibrary thumbnailFileForIdentifier:item.identifier] ]) {
        if ([HCGBackgroundPreset isSafeFileName:name]) [fm removeItemAtURL:[folder URLByAppendingPathComponent:name] error:NULL];
    }
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
    return [identifier stringByAppendingString:@"-still.jpg"];
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

#pragma mark Export / import

- (NSURL *)exportItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *media = [HACPreferences mediaFolder];
    NSString *safeName = [[item.name componentsSeparatedByCharactersInSet:
                                         [[NSCharacterSet alphanumericCharacterSet] invertedSet]]
        componentsJoinedByString:@"-"];
    if (safeName.length == 0) safeName = @"Background";
    NSURL *exports = [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:@"Exports"]
                                isDirectory:YES];
    NSURL *folder = [exports URLByAppendingPathComponent:[safeName stringByAppendingPathExtension:@"hcgbackground"]];
    [fm removeItemAtURL:folder error:NULL];
    if (![fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    HCGBackgroundPreset *copy = [item copy];
    NSString *mediaName = [@"media" stringByAppendingPathExtension:item.mediaFile.pathExtension ?: @"mov"];
    if (![fm copyItemAtURL:[item mediaURLInFolder:media] toURL:[folder URLByAppendingPathComponent:mediaName] error:error])
        return nil;
    copy.mediaFile = mediaName;
    NSURL *still = [item stillURLInFolder:media];
    if (still && [fm fileExistsAtPath:still.path]) {
        NSString *stillName = [@"still" stringByAppendingPathExtension:item.stillFile.pathExtension ?: @"jpg"];
        if ([fm copyItemAtURL:still toURL:[folder URLByAppendingPathComponent:stillName] error:NULL]) copy.stillFile = stillName;
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

- (HCGBackgroundPreset *)importPresetFolder:(NSURL *)folder error:(NSError **)error {
    HCGBackgroundPreset *preset = [HCGBackgroundPreset presetWithContentsOfURL:folder error:error];
    if (!preset) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *source = [preset mediaURLInFolder:folder];
    NSDictionary *attributes = source ? [fm attributesOfItemAtPath:source.path error:NULL] : nil;
    if (![attributes.fileType isEqualToString:NSFileTypeRegular]) {
        if (error) *error = LibraryError(@"The preset's video file is missing from the folder.");
        return nil;
    }
    if (attributes.fileSize > kMaxImportedMediaBytes) {
        if (error) *error = LibraryError(@"The preset's video is larger than 512 MB.");
        return nil;
    }
    if (preset.mediaSHA256 && ![SHA256OfFile(source) isEqualToString:preset.mediaSHA256]) {
        if (error) *error = LibraryError(@"The video does not match the preset's checksum; it may be damaged.");
        return nil;
    }
    NSString *identifier = [NSUUID UUID].UUIDString;
    NSURL *media = [HACPreferences mediaFolder];
    if (![fm createDirectoryAtURL:media withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *ext = source.pathExtension.length ? source.pathExtension.lowercaseString : @"mov";
    if (![@[ @"mov", @"mp4", @"m4v" ] containsObject:ext]) ext = @"mov";
    NSString *mediaName = [identifier stringByAppendingPathExtension:ext];
    if (![fm copyItemAtURL:source toURL:[media URLByAppendingPathComponent:mediaName] error:error]) return nil;
    preset.identifier = identifier;
    preset.mediaFile = mediaName;
    NSURL *still = [preset stillURLInFolder:folder];
    NSString *stillName = [HACLibrary stillFileForIdentifier:identifier];
    if (still && [fm copyItemAtURL:still toURL:[media URLByAppendingPathComponent:stillName] error:NULL]) {
        preset.stillFile = stillName;
    } else {
        preset.stillFile = nil;
    }
    preset.mediaSHA256 = SHA256OfFile([media URLByAppendingPathComponent:mediaName]);
    if (![self addItem:preset error:error]) return nil;
    return preset;
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
