//
//  HCGBackgroundPreset.m
//  HCGBackgroundKit — Hakmi Capital Group
//

#import "HCGBackgroundPreset.h"
#import "HCGBackgroundCore.h"

NSString *const HCGBackgroundPresetFormat = @HCGBG_FORMAT_ID;
const NSInteger HCGBackgroundPresetFormatVersion = HCGBG_FORMAT_VERSION;
NSString *const HCGBackgroundPresetFileName = @"preset.json";
NSString *const HCGBackgroundErrorDomain = @"com.hakmicapitalgroup.background-preset";

/// Largest preset document accepted from disk (they are a few hundred bytes).
static const NSUInteger kMaxDocumentBytes = 64 * 1024;

static NSError *HCGError(HCGBackgroundError code, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static NSError *HCGError(HCGBackgroundError code, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:HCGBackgroundErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : message}];
}

static id Typed(NSDictionary *d, NSString *key, Class cls) {
    id v = d[key];
    return [v isKindOfClass:cls] ? v : nil;
}

/// A JSON / plist number that is not a boolean.
static NSNumber *Number(NSDictionary *d, NSString *key) {
    NSNumber *n = Typed(d, key, [NSNumber class]);
    if (!n || CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID()) return nil;
    return n;
}

static NSNumber *BooleanValue(NSDictionary *d, NSString *key) {
    NSNumber *n = Typed(d, key, [NSNumber class]);
    return n && CFGetTypeID((__bridge CFTypeRef)n) == CFBooleanGetTypeID() ? n : nil;
}

static double Round6(double v) {
    return round(v * 1e6) / 1e6;
}

@implementation HCGBackgroundPreset {
    NSMutableArray<NSString *> *_warnings;
}

+ (NSISO8601DateFormatter *)dateFormatter {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return formatter;
}

- (instancetype)init {
    if ((self = [super init])) {
        _identifier = [NSUUID UUID].UUIDString;
        _name = @"Background";
        _mediaFile = @"";
        _origin = @"video";
        _loops = YES;
        _speed = HCGBG_SPEED_DEFAULT;
        _scaling = HCGBackgroundScalingFill;
        _crop = CGRectMake(0, 0, 1, 1);
        _backgroundColor = @"#000000";
        _warnings = [NSMutableArray array];
    }
    return self;
}

- (BOOL)muted {
    return YES;
}

- (NSArray<NSString *> *)warnings {
    return [_warnings copy];
}

- (id)copyWithZone:(NSZone *)zone {
    HCGBackgroundPreset *c = [[[self class] allocWithZone:zone] init];
    c->_identifier = [_identifier copy];
    c->_name = [_name copy];
    c->_created = [_created copy];
    c->_mediaFile = [_mediaFile copy];
    c->_mediaSize = _mediaSize;
    c->_duration = _duration;
    c->_origin = [_origin copy];
    c->_mediaSHA256 = [_mediaSHA256 copy];
    c->_stillFile = [_stillFile copy];
    c->_stillTime = _stillTime;
    c->_trimStart = _trimStart;
    c->_trimEnd = _trimEnd;
    c->_loops = _loops;
    c->_speed = _speed;
    c->_scaling = _scaling;
    c->_crop = _crop;
    c->_backgroundColor = [_backgroundColor copy];
    c->_generator = [_generator copy];
    c->_warnings = [_warnings mutableCopy];
    return c;
}

+ (instancetype)presetWithMediaFile:(NSString *)mediaFile
                          mediaSize:(CGSize)mediaSize
                           duration:(NSTimeInterval)duration
                             origin:(NSString *)origin {
    HCGBackgroundPreset *p = [[self alloc] init];
    p.mediaFile = mediaFile;
    p.mediaSize = mediaSize;
    p.duration = duration;
    p.origin = origin.length ? origin : @"video";
    p.trimEnd = duration;
    p.created = [NSDate date];
    p.name = mediaFile.stringByDeletingPathExtension.length ? mediaFile.stringByDeletingPathExtension : @"Background";
    [p sanitizeWithError:NULL];
    return p;
}

+ (NSString *)identifierForScaling:(HCGBackgroundScaling)scaling {
    const char *s = hcgbg_scaling_id((HCGBGScaling)scaling);
    return s ? @(s) : @"fill";
}

+ (BOOL)isSafeFileName:(NSString *)name {
    if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 255) return NO;
    if ([name hasPrefix:@"."] || [name containsString:@"/"] || [name containsString:@"\\"] || [name containsString:@":"])
        return NO;
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c < 0x20 || c == 0x7F) return NO;
    }
    return YES;
}

#pragma mark - Reading

+ (instancetype)presetWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
    NSURL *file = isDirectory.boolValue ? [url URLByAppendingPathComponent:HCGBackgroundPresetFileName] : url;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:NULL];
    if (!attributes || ![attributes.fileType isEqualToString:NSFileTypeRegular]) {
        if (error) *error = HCGError(HCGBackgroundErrorUnreadable, @"No preset file at %@.", file.lastPathComponent);
        return nil;
    }
    if (attributes.fileSize > kMaxDocumentBytes) {
        if (error) *error = HCGError(HCGBackgroundErrorUnreadable, @"%@ is larger than 64 KB.", file.lastPathComponent);
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:file options:0 error:NULL];
    if (!data) {
        if (error) *error = HCGError(HCGBackgroundErrorUnreadable, @"%@ could not be read.", file.lastPathComponent);
        return nil;
    }
    return [self presetWithJSONData:data error:error];
}

+ (instancetype)presetWithJSONData:(NSData *)data error:(NSError **)error {
    if (data.length > kMaxDocumentBytes) {
        if (error) *error = HCGError(HCGBackgroundErrorUnreadable, @"The preset is larger than 64 KB.");
        return nil;
    }
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = HCGError(HCGBackgroundErrorUnreadable, @"The preset is not a JSON object.");
        return nil;
    }
    return [self presetWithDictionary:object error:error];
}

+ (instancetype)presetWithDictionary:(NSDictionary *)d error:(NSError **)error {
#define FAIL(code, ...)                                   \
    do {                                                  \
        if (error) *error = HCGError(code, __VA_ARGS__);  \
        return nil;                                       \
    } while (0)
    if (![d isKindOfClass:[NSDictionary class]]) FAIL(HCGBackgroundErrorNotAPreset, @"Not a preset.");
    if (![Typed(d, @"format", [NSString class]) isEqualToString:HCGBackgroundPresetFormat])
        FAIL(HCGBackgroundErrorNotAPreset, @"Not an HCG background preset (format must be %@).", HCGBackgroundPresetFormat);
    NSNumber *version = Number(d, @"formatVersion");
    if (!version || version.doubleValue != (double)version.integerValue || version.integerValue < 1)
        FAIL(HCGBackgroundErrorUnsupportedVersion, @"formatVersion must be a whole number.");
    if (version.integerValue > HCGBackgroundPresetFormatVersion)
        FAIL(HCGBackgroundErrorUnsupportedVersion,
             @"This preset uses format version %ld; this version of HCGBackgroundKit reads version %ld. Update to use it.",
             (long)version.integerValue, (long)HCGBackgroundPresetFormatVersion);

    HCGBackgroundPreset *p = [[self alloc] init];
    NSString *identifier = Typed(d, @"id", [NSString class]);
    if (identifier.length) {
        if (![[NSUUID alloc] initWithUUIDString:identifier]) FAIL(HCGBackgroundErrorInvalidValue, @"id must be a UUID.");
        p.identifier = identifier.uppercaseString;
    }
    NSString *name = Typed(d, @"name", [NSString class]);
    if (name.length) p.name = name.length > 120 ? [name substringToIndex:120] : name;
    NSString *created = Typed(d, @"created", [NSString class]);
    if (created) p.created = [[self dateFormatter] dateFromString:created];

    NSDictionary *media = Typed(d, @"media", [NSDictionary class]);
    if (!media) FAIL(HCGBackgroundErrorMissingValue, @"media is missing.");
    NSString *kind = Typed(media, @"kind", [NSString class]) ?: @"video";
    if (![kind isEqualToString:@"video"])
        FAIL(HCGBackgroundErrorInvalidValue, @"media.kind \"%@\" is not supported (version 1 plays video only).", kind);
    NSString *file = Typed(media, @"file", [NSString class]);
    if (!file) FAIL(HCGBackgroundErrorMissingValue, @"media.file is missing.");
    if (![self isSafeFileName:file]) FAIL(HCGBackgroundErrorUnsafeFileName, @"media.file must be a plain file name.");
    p.mediaFile = file;
    NSNumber *width = Number(media, @"width"), *height = Number(media, @"height"), *duration = Number(media, @"duration");
    if (!width || !height || !duration) FAIL(HCGBackgroundErrorMissingValue, @"media needs width, height and duration.");
    p.mediaSize = CGSizeMake(width.doubleValue, height.doubleValue);
    p.duration = duration.doubleValue;
    NSString *origin = Typed(media, @"origin", [NSString class]);
    if (origin.length) p.origin = origin;
    NSString *sha = Typed(media, @"sha256", [NSString class]);
    if (sha.length == 64) p.mediaSHA256 = sha.lowercaseString;

    NSDictionary *still = Typed(d, @"still", [NSDictionary class]);
    NSString *stillFile = Typed(still, @"file", [NSString class]);
    if (stillFile) {
        if (![self isSafeFileName:stillFile]) FAIL(HCGBackgroundErrorUnsafeFileName, @"still.file must be a plain file name.");
        p.stillFile = stillFile;
    }
    p.stillTime = Number(still, @"time").doubleValue;

    NSDictionary *playback = Typed(d, @"playback", [NSDictionary class]) ?: @{};
    p.trimStart = Number(playback, @"trimStart").doubleValue;
    p.trimEnd = Number(playback, @"trimEnd") ? Number(playback, @"trimEnd").doubleValue : 0;
    p.loops = BooleanValue(playback, @"loop") ? BooleanValue(playback, @"loop").boolValue : YES;
    p.speed = Number(playback, @"speed") ? Number(playback, @"speed").doubleValue : HCGBG_SPEED_DEFAULT;
    NSNumber *muted = BooleanValue(playback, @"muted");
    if (muted && !muted.boolValue) [p->_warnings addObject:@"Sound is not supported: the background plays muted."];

    NSDictionary *layout = Typed(d, @"layout", [NSDictionary class]) ?: @{};
    NSString *scaling = Typed(layout, @"scaling", [NSString class]);
    HCGBGScaling s = HCGBGScalingFill;
    if (scaling && !hcgbg_scaling_parse(scaling.UTF8String, &s))
        [p->_warnings addObject:[NSString stringWithFormat:@"Unknown scaling \"%@\": using fill.", scaling]];
    p.scaling = (HCGBackgroundScaling)s;
    NSDictionary *crop = Typed(layout, @"crop", [NSDictionary class]);
    if (crop) {
        p.crop = CGRectMake(Number(crop, @"x") ? Number(crop, @"x").doubleValue : 0,
                            Number(crop, @"y") ? Number(crop, @"y").doubleValue : 0,
                            Number(crop, @"width") ? Number(crop, @"width").doubleValue : 1,
                            Number(crop, @"height") ? Number(crop, @"height").doubleValue : 1);
    }
    NSString *colour = Typed(layout, @"backgroundColor", [NSString class]);
    if (colour) {
        if (hcgbg_parse_hex_colour(colour.UTF8String, NULL, NULL, NULL)) {
            p.backgroundColor = colour.uppercaseString;
        } else {
            [p->_warnings addObject:@"backgroundColor must be #RRGGBB: using black."];
        }
    }
    NSDictionary *generator = Typed(d, @"generator", [NSDictionary class]);
    if (generator && [NSJSONSerialization isValidJSONObject:generator]) p.generator = generator;

    if (![p sanitizeWithError:error]) return nil;
    return p;
#undef FAIL
}

#pragma mark - Sanitising

- (HCGBGPlayback)corePlayback {
    HCGBGPlayback c = {
        .duration = _duration,
        .trimStart = _trimStart,
        .trimEnd = _trimEnd,
        .speed = _speed,
        .posterTime = _stillTime,
        .width = _mediaSize.width,
        .height = _mediaSize.height,
        .crop = {_crop.origin.x, _crop.origin.y, _crop.size.width, _crop.size.height},
    };
    return c;
}

- (BOOL)sanitizeWithError:(NSError **)error {
    if (![HCGBackgroundPreset isSafeFileName:_mediaFile]) {
        if (error) *error = HCGError(HCGBackgroundErrorUnsafeFileName, @"media.file must be a plain file name.");
        return NO;
    }
    if (_stillFile && ![HCGBackgroundPreset isSafeFileName:_stillFile]) {
        if (error) *error = HCGError(HCGBackgroundErrorUnsafeFileName, @"still.file must be a plain file name.");
        return NO;
    }
    if (!hcgbg_scaling_id((HCGBGScaling)_scaling)) _scaling = HCGBackgroundScalingFill;
    if (!hcgbg_parse_hex_colour(_backgroundColor.UTF8String, NULL, NULL, NULL)) _backgroundColor = @"#000000";

    HCGBGPlayback c = [self corePlayback];
    unsigned issues = hcgbg_playback_sanitize(&c);
    if (issues & HCGBGIssueDurationInvalid) {
        if (error)
            *error = HCGError(HCGBackgroundErrorInvalidValue, @"media.duration must be between 0 and %.0f seconds.",
                              HCGBG_MAX_SOURCE_SECONDS);
        return NO;
    }
    if (issues & HCGBGIssueDimensionsInvalid) {
        if (error)
            *error = HCGError(HCGBackgroundErrorInvalidValue, @"media width and height must be %d–%d pixels.",
                              HCGBG_MIN_DIMENSION, HCGBG_MAX_DIMENSION);
        return NO;
    }
    if (issues & HCGBGIssueClipTooShort) {
        if (error)
            *error = HCGError(HCGBackgroundErrorInvalidValue, @"The media is shorter than %.1f s.", HCGBG_MIN_CLIP_SECONDS);
        return NO;
    }
    void (^note)(unsigned, NSString *) = ^(unsigned flag, NSString *text) {
        if ((issues & flag) && ![self->_warnings containsObject:text]) [self->_warnings addObject:text];
    };
    note(HCGBGIssueTrimClamped, @"The trim range was adjusted to fit the clip.");
    note(HCGBGIssueSpeedClamped, @"The speed was limited to 0.25×–2×.");
    note(HCGBGIssuePosterClamped, @"The still was moved inside the trimmed clip.");
    note(HCGBGIssueCropClamped, @"The crop was adjusted to fit the frame.");
    _trimStart = Round6(c.trimStart);
    _trimEnd = Round6(c.trimEnd);
    _speed = Round6(c.speed);
    _stillTime = Round6(c.posterTime);
    _crop = CGRectMake(Round6(c.crop.x), Round6(c.crop.y), Round6(c.crop.width), Round6(c.crop.height));
    return YES;
}

- (NSTimeInterval)clipDuration {
    HCGBGPlayback c = [self corePlayback];
    hcgbg_playback_sanitize(&c);
    return hcgbg_clip_seconds(&c);
}

#pragma mark - Writing

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    [self sanitizeWithError:NULL];
    NSMutableDictionary *media = [@{
        @"kind" : @"video",
        @"file" : _mediaFile ?: @"",
        @"width" : @(round(_mediaSize.width)),
        @"height" : @(round(_mediaSize.height)),
        @"duration" : @(Round6(_duration)),
        @"origin" : _origin ?: @"video",
    } mutableCopy];
    if (_mediaSHA256) media[@"sha256"] = _mediaSHA256;
    NSMutableDictionary *still = [@{@"time" : @(_stillTime)} mutableCopy];
    if (_stillFile) still[@"file"] = _stillFile;
    NSMutableDictionary *d = [@{
        @"format" : HCGBackgroundPresetFormat,
        @"formatVersion" : @(HCGBackgroundPresetFormatVersion),
        @"id" : _identifier ?: [NSUUID UUID].UUIDString,
        @"name" : _name ?: @"Background",
        @"media" : media,
        @"still" : still,
        @"playback" : @{
            @"trimStart" : @(_trimStart),
            @"trimEnd" : @(_trimEnd),
            @"loop" : @(_loops),
            @"speed" : @(_speed),
            @"muted" : @YES,
        },
        @"layout" : @{
            @"scaling" : [HCGBackgroundPreset identifierForScaling:_scaling],
            @"crop" : @{
                @"x" : @(_crop.origin.x),
                @"y" : @(_crop.origin.y),
                @"width" : @(_crop.size.width),
                @"height" : @(_crop.size.height),
            },
            @"backgroundColor" : _backgroundColor ?: @"#000000",
        },
    } mutableCopy];
    if (_created) d[@"created"] = [[HCGBackgroundPreset dateFormatter] stringFromDate:_created];
    if (_generator) d[@"generator"] = _generator;
    return d;
}

- (NSData *)JSONDataWithError:(NSError **)error {
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
    if (@available(iOS 11.0, macOS 10.13, *)) options |= NSJSONWritingSortedKeys;
    return [NSJSONSerialization dataWithJSONObject:[self dictionaryRepresentation] options:options error:error];
}

- (NSURL *)mediaURLInFolder:(NSURL *)folder {
    if (!folder || ![HCGBackgroundPreset isSafeFileName:_mediaFile]) return nil;
    return [folder URLByAppendingPathComponent:_mediaFile isDirectory:NO];
}

- (NSURL *)stillURLInFolder:(NSURL *)folder {
    if (!folder || ![HCGBackgroundPreset isSafeFileName:_stillFile]) return nil;
    return [folder URLByAppendingPathComponent:_stillFile isDirectory:NO];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<HCGBackgroundPreset %@ \"%@\" %@ %.0fx%.0f %.2fs trim %.2f–%.2f %@ %.2gx %@>",
                                      _identifier, _name, _mediaFile, _mediaSize.width, _mediaSize.height, _duration,
                                      _trimStart, _trimEnd, _loops ? @"loop" : @"once", _speed,
                                      [HCGBackgroundPreset identifierForScaling:_scaling]];
}

@end
