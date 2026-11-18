//
//  HACMediaImporter.m
//  HCG Animation Center — Hakmi Capital Group
//

#import "HACMediaImporter.h"
#import "HACLibrary.h"
#import "HACPreferences.h"
#import "HCGBackgroundCore.h"

#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

NSString *const HACImportErrorDomain = @"com.hakmicapitalgroup.animationcenter.import";
const unsigned long long HACMaxSourceBytes = 512ull * 1024 * 1024;
const double HACMaxStoredLongSide = 2688;
const double HACGIFMaxLongSide = 1080;
const NSUInteger HACGIFMaxFrames = 3000;

/// GIFs shorter than this are repeated inside the video.
static const double kGIFMinimumSeconds = 1.0;

static NSError *ImportError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *ImportError(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:HACImportErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSURL *StagingFolder(void) {
    return [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:@"Staging"] isDirectory:YES];
}

@implementation HACMediaImporter {
    dispatch_queue_t _queue;
    volatile BOOL _cancelled;
    AVAssetExportSession *_export; // touched on _queue only
    BOOL _busy;                    // main queue only
}

- (instancetype)init {
    if ((self = [super init])) _queue = dispatch_queue_create("com.hakmicapitalgroup.animationcenter.import", DISPATCH_QUEUE_SERIAL);
    return self;
}

#pragma mark Staging and sniffing

+ (NSURL *)stageFileAtURL:(NSURL *)url error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm attributesOfItemAtPath:url.path error:NULL];
    if (![attributes.fileType isEqualToString:NSFileTypeRegular]) {
        if (error) *error = ImportError(@"That item is not a file.");
        return nil;
    }
    if (attributes.fileSize == 0) {
        if (error) *error = ImportError(@"The file is empty.");
        return nil;
    }
    if (attributes.fileSize > HACMaxSourceBytes) {
        if (error) *error = ImportError(@"The file is larger than 512 MB.");
        return nil;
    }
    if (![fm createDirectoryAtURL:StagingFolder() withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"bin";
    NSURL *staged = [StagingFolder() URLByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingPathExtension:ext]];
    if (![fm copyItemAtURL:url toURL:staged error:error]) return nil;
    return staged;
}

+ (HACMediaKind)kindOfFileAtURL:(NSURL *)url {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:NULL];
    NSData *head = [handle readDataOfLength:16];
    [handle closeFile];
    if (head.length < 12) return HACMediaKindUnknown;
    const unsigned char *b = head.bytes;
    if (memcmp(b, "GIF87a", 6) == 0 || memcmp(b, "GIF89a", 6) == 0) return HACMediaKindGIF;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return HACMediaKindStillImage;     // JPEG
    if (memcmp(b, "\x89PNG", 4) == 0) return HACMediaKindStillImage;                      // PNG
    if (memcmp(b + 4, "ftyp", 4) == 0) {
        NSString *brand = [[NSString alloc] initWithBytes:b + 8 length:4 encoding:NSASCIIStringEncoding];
        if ([@[ @"heic", @"heix", @"heim", @"heis", @"mif1", @"msf1", @"avif" ] containsObject:brand])
            return HACMediaKindStillImage;
        return HACMediaKindVideo; // qt, isom, mp41, mp42, M4V, …: AVFoundation decides
    }
    // QuickTime files may start with other atoms (wide, mdat, moov).
    if (memcmp(b + 4, "wide", 4) == 0 || memcmp(b + 4, "mdat", 4) == 0 || memcmp(b + 4, "moov", 4) == 0 ||
        memcmp(b + 4, "free", 4) == 0)
        return HACMediaKindVideo;
    return HACMediaKindUnknown;
}

#pragma mark Import

- (BOOL)isBusy {
    return _busy;
}

- (void)cancel {
    _cancelled = YES;
    dispatch_async(_queue, ^{
        [self->_export cancelExport];
    });
}

- (void)importStagedFile:(NSURL *)staged
           suggestedName:(NSString *)name
                progress:(HACImportProgress)progress
              completion:(HACImportCompletion)completion {
    if (_busy) {
        completion(nil, ImportError(@"Another import is running."));
        return;
    }
    _busy = YES;
    _cancelled = NO;
    void (^report)(double, NSString *) = ^(double fraction, NSString *phase) {
        if (progress)
            dispatch_async(dispatch_get_main_queue(), ^{
                progress(fraction, phase);
            });
    };
    dispatch_async(_queue, ^{
        NSError *error = nil;
        HCGBackgroundPreset *item = nil;
        @try {
            item = [self importFile:staged name:name report:report error:&error];
        } @catch (NSException *exception) {
            item = nil;
            error = ImportError(@"Import failed: %@", exception.reason);
        }
        [[NSFileManager defaultManager] removeItemAtURL:staged error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            if (item) {
                NSError *saveError = nil;
                [[HACLibrary shared] reload];
                if (![[HACLibrary shared] addItem:item error:&saveError]) {
                    [self removeFilesOfItem:item];
                    completion(nil, saveError);
                    return;
                }
            }
            completion(item, item ? nil : (error ?: ImportError(@"Import failed.")));
        });
    });
}

- (void)removeFilesOfItem:(HCGBackgroundPreset *)item {
    NSURL *folder = [HACPreferences mediaFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in @[ item.mediaFile ?: @"", item.stillFile ?: @"", [HACLibrary thumbnailFileForIdentifier:item.identifier] ])
        if ([HCGBackgroundPreset isSafeFileName:file]) [fm removeItemAtURL:[folder URLByAppendingPathComponent:file] error:NULL];
}

/// Runs on _queue.
- (HCGBackgroundPreset *)importFile:(NSURL *)url
                               name:(NSString *)name
                             report:(void (^)(double, NSString *))report
                              error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm attributesOfItemAtPath:url.path error:NULL];
    if (attributes.fileSize == 0) {
        if (error) *error = ImportError(@"The file is empty.");
        return nil;
    }
    if (attributes.fileSize > HACMaxSourceBytes) {
        if (error) *error = ImportError(@"The file is larger than 512 MB.");
        return nil;
    }
    NSURL *media = [HACPreferences mediaFolder];
    if (![fm createDirectoryAtURL:media withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *identifier = [NSUUID UUID].UUIDString;
    HACMediaKind kind = [HACMediaImporter kindOfFileAtURL:url];
    NSString *origin = nil;
    NSURL *output = nil;
    report(0.02, @"Checking");
    switch (kind) {
        case HACMediaKindStillImage:
            if (error)
                *error = ImportError(@"This is a still image. Live backgrounds need a video or an animated GIF "
                                     @"(Live Photos are not supported yet).");
            return nil;
        case HACMediaKindGIF:
            origin = @"gif";
            output = [media URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"mp4"]];
            if (![self transcodeGIF:url to:output report:report error:error]) {
                [fm removeItemAtURL:output error:NULL];
                return nil;
            }
            break;
        case HACMediaKindVideo:
        case HACMediaKindUnknown:
            origin = @"video";
            output = [self importVideo:url identifier:identifier report:report error:error];
            if (!output) return nil;
            break;
    }
    if (_cancelled) {
        [fm removeItemAtURL:output error:NULL];
        if (error) *error = ImportError(@"Import cancelled.");
        return nil;
    }

    report(0.92, @"Making the still");
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:output options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
    CGSize size = CGSizeZero;
    NSTimeInterval duration = 0;
    if (![HACMediaImporter probe:asset size:&size duration:&duration error:error]) {
        [fm removeItemAtURL:output error:NULL];
        return nil;
    }
    NSString *base = name.stringByDeletingPathExtension;
    HCGBackgroundPreset *item = [HCGBackgroundPreset presetWithMediaFile:output.lastPathComponent
                                                               mediaSize:size
                                                                duration:duration
                                                                  origin:origin];
    item.identifier = identifier;
    item.name = base.length ? base : ([origin isEqualToString:@"gif"] ? @"GIF" : @"Video");
    item.generator = @{@"kind" : @"import", @"source" : origin};
    item.mediaSHA256 = [HACMediaImporter sha256OfFile:output];
    item.stillFile = [HACLibrary stillFileForIdentifier:identifier];
    NSError *presetError = nil;
    if (![item sanitizeWithError:&presetError] || ![HACMediaImporter writeStillAndThumbnailForItem:item error:&presetError]) {
        [self removeFilesOfItem:item];
        if (error) *error = presetError;
        return nil;
    }
    report(1.0, @"Done");
    return item;
}

#pragma mark Video

+ (BOOL)loadAsset:(AVAsset *)asset error:(NSError **)error {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSArray *keys = @[ @"playable", @"tracks", @"duration" ];
    [asset loadValuesAsynchronouslyForKeys:keys
                         completionHandler:^{
                             dispatch_semaphore_signal(done);
                         }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0) {
        [asset cancelLoading];
        if (error) *error = ImportError(@"Reading the video took too long.");
        return NO;
    }
    for (NSString *key in keys) {
        NSError *e = nil;
        if ([asset statusOfValueForKey:key error:&e] != AVKeyValueStatusLoaded) {
            if (error) *error = ImportError(@"The file can't be read as a video (%@).", e.localizedDescription ?: key);
            return NO;
        }
    }
    return YES;
}

+ (BOOL)probe:(AVAsset *)asset size:(CGSize *)size duration:(NSTimeInterval *)duration error:(NSError **)error {
    if (![self loadAsset:asset error:error]) return NO;
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!asset.playable || !track) {
        if (error) *error = ImportError(@"The file has no playable video track.");
        return NO;
    }
    CGRect r = CGRectApplyAffineTransform(CGRectMake(0, 0, track.naturalSize.width, track.naturalSize.height),
                                          track.preferredTransform);
    *size = CGSizeMake(round(fabs(r.size.width)), round(fabs(r.size.height)));
    *duration = CMTimeGetSeconds(asset.duration);
    if (!isfinite(*duration) || *duration < HCGBG_MIN_CLIP_SECONDS) {
        if (error) *error = ImportError(@"The video is shorter than half a second.");
        return NO;
    }
    if (*duration > HCGBG_MAX_SOURCE_SECONDS) {
        if (error) *error = ImportError(@"The video is longer than 10 minutes. Trim it in Photos first.");
        return NO;
    }
    if (size->width < HCGBG_MIN_DIMENSION || size->height < HCGBG_MIN_DIMENSION || size->width > HCGBG_MAX_DIMENSION ||
        size->height > HCGBG_MAX_DIMENSION) {
        if (error) *error = ImportError(@"The video is %.0f × %.0f pixels; supported sizes are %d–%d pixels per side.",
                                        size->width, size->height, HCGBG_MIN_DIMENSION, HCGBG_MAX_DIMENSION);
        return NO;
    }
    return YES;
}

- (NSURL *)importVideo:(NSURL *)url identifier:(NSString *)identifier report:(void (^)(double, NSString *))report error:(NSError **)error {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
    CGSize size = CGSizeZero;
    NSTimeInterval duration = 0;
    if (![HACMediaImporter probe:asset size:&size duration:&duration error:error]) return nil;
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;

    // Video track only: the stored file has no audio at all.
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *video = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *insertError = nil;
    if (!video || ![video insertTimeRange:track.timeRange ofTrack:track atTime:kCMTimeZero error:&insertError]) {
        if (error) *error = ImportError(@"The video track can't be copied (%@).", insertError.localizedDescription ?: @"?");
        return nil;
    }
    video.preferredTransform = track.preferredTransform;

    NSURL *media = [HACPreferences mediaFolder];
    BOOL fits = MAX(size.width, size.height) <= HACMaxStoredLongSide;
    NSMutableArray<NSArray *> *attempts = [NSMutableArray array];
    if (fits) [attempts addObject:@[ AVAssetExportPresetPassthrough, AVFileTypeQuickTimeMovie, @"mov" ]];
    [attempts addObject:@[ AVAssetExportPreset1920x1080, AVFileTypeMPEG4, @"mp4" ]];
    NSError *lastError = nil;
    for (NSArray *attempt in attempts) {
        NSURL *output = [media URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:attempt[2]]];
        [[NSFileManager defaultManager] removeItemAtURL:output error:NULL];
        report(0.05, [attempt[0] isEqualToString:AVAssetExportPresetPassthrough] ? @"Copying the video"
                                                                                 : @"Converting the video");
        if ([self export:composition preset:attempt[0] fileType:attempt[1] to:output report:report error:&lastError])
            return output;
        [[NSFileManager defaultManager] removeItemAtURL:output error:NULL];
        if (_cancelled) break;
    }
    if (error) *error = _cancelled ? ImportError(@"Import cancelled.")
                                   : ImportError(@"The video could not be saved (%@).",
                                                 lastError.localizedDescription ?: @"export failed");
    return nil;
}

- (BOOL)export:(AVAsset *)asset
        preset:(NSString *)preset
      fileType:(AVFileType)fileType
            to:(NSURL *)output
        report:(void (^)(double, NSString *))report
         error:(NSError **)error {
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
    if (!session || ![session.supportedFileTypes containsObject:fileType]) {
        if (error) *error = ImportError(@"%@ export is not available for this video.", preset);
        return NO;
    }
    session.outputURL = output;
    session.outputFileType = fileType;
    session.shouldOptimizeForNetworkUse = NO;
    _export = session;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(done);
    }];
    while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) != 0) {
        if (_cancelled) [session cancelExport];
        report(0.05 + 0.85 * session.progress, @"Saving the video");
    }
    _export = nil;
    if (session.status != AVAssetExportSessionStatusCompleted) {
        if (error) *error = session.error ?: ImportError(@"The export did not complete.");
        return NO;
    }
    return YES;
}

#pragma mark GIF

- (BOOL)transcodeGIF:(NSURL *)url to:(NSURL *)output report:(void (^)(double, NSString *))report error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source || CGImageSourceGetStatus(source) != kCGImageStatusComplete) {
        if (source) CFRelease(source);
        if (error) *error = ImportError(@"The GIF is damaged or incomplete.");
        return NO;
    }
    size_t count = CGImageSourceGetCount(source);
    if (count < 2) {
        CFRelease(source);
        if (error) *error = ImportError(@"This GIF has only one frame. Live backgrounds need an animated GIF or a video.");
        return NO;
    }
    if (count > HACGIFMaxFrames) {
        CFRelease(source);
        if (error) *error = ImportError(@"This GIF has %zu frames; the limit is %lu.", count, (unsigned long)HACGIFMaxFrames);
        return NO;
    }
    // Frame size and timing.
    NSDictionary *first = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    double width = [first[(__bridge id)kCGImagePropertyPixelWidth] doubleValue];
    double height = [first[(__bridge id)kCGImagePropertyPixelHeight] doubleValue];
    if (width < 1 || height < 1) {
        CFRelease(source);
        if (error) *error = ImportError(@"The GIF has no readable frame size.");
        return NO;
    }
    NSMutableArray<NSNumber *> *delays = [NSMutableArray arrayWithCapacity:count];
    double total = 0;
    for (size_t i = 0; i < count; i++) {
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, i, NULL));
        NSDictionary *gif = props[(__bridge id)kCGImagePropertyGIFDictionary];
        NSNumber *declared = gif[(__bridge id)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(__bridge id)kCGImagePropertyGIFDelayTime];
        double delay = hcgbg_gif_frame_delay(declared ? declared.doubleValue : 0);
        [delays addObject:@(delay)];
        total += delay;
    }
    NSUInteger repeats = total < kGIFMinimumSeconds ? (NSUInteger)ceil(kGIFMinimumSeconds / total) : 1;
    if (total * repeats > HCGBG_MAX_SOURCE_SECONDS) {
        CFRelease(source);
        if (error) *error = ImportError(@"The GIF plays for longer than 10 minutes.");
        return NO;
    }
    HCGBGSize out = hcgbg_even_fit((HCGBGSize){width, height}, HACGIFMaxLongSide);

    NSError *writerError = nil;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:output fileType:AVFileTypeMPEG4 error:&writerError];
    if (!writer) {
        CFRelease(source);
        if (error) *error = ImportError(@"The video writer could not start (%@).", writerError.localizedDescription ?: @"?");
        return NO;
    }
    NSDictionary *settings = @{
        AVVideoCodecKey : AVVideoCodecTypeH264,
        AVVideoWidthKey : @(out.width),
        AVVideoHeightKey : @(out.height),
        AVVideoCompressionPropertiesKey : @{
            AVVideoAverageBitRateKey : @(MAX(1000000.0, out.width * out.height * 6)),
            AVVideoProfileLevelKey : AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey : @30,
        },
    };
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    input.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                   sourcePixelBufferAttributes:@{
                                       (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferWidthKey : @(out.width),
                                       (id)kCVPixelBufferHeightKey : @(out.height),
                                   }];
    if (![writer canAddInput:input]) {
        CFRelease(source);
        if (error) *error = ImportError(@"The video writer rejected the GIF's size.");
        return NO;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
        CFRelease(source);
        if (error) *error = ImportError(@"The video writer could not start (%@).", writer.error.localizedDescription ?: @"?");
        return NO;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    double t = 0;
    BOOL ok = YES;
    NSString *failure = nil;
    NSUInteger written = 0, totalFrames = count * repeats;
    for (NSUInteger r = 0; r < repeats && ok; r++) {
        for (size_t i = 0; i < count && ok; i++) {
            @autoreleasepool {
                while (!input.readyForMoreMediaData && !_cancelled && writer.status == AVAssetWriterStatusWriting)
                    usleep(2000);
                if (_cancelled) {
                    ok = NO;
                    failure = @"Import cancelled.";
                    break;
                }
                CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
                CVPixelBufferRef buffer = NULL;
                if (adaptor.pixelBufferPool)
                    CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
                if (!image || !buffer) {
                    if (image) CGImageRelease(image);
                    if (buffer) CVPixelBufferRelease(buffer);
                    ok = NO;
                    failure = [NSString stringWithFormat:@"Frame %zu of the GIF can't be decoded.", i + 1];
                    break;
                }
                CVPixelBufferLockBaseAddress(buffer, 0);
                CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), (size_t)out.width,
                                                         (size_t)out.height, 8, CVPixelBufferGetBytesPerRow(buffer), space,
                                                         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
                if (ctx) {
                    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
                    CGContextFillRect(ctx, CGRectMake(0, 0, out.width, out.height));
                    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
                    CGContextDrawImage(ctx, CGRectMake(0, 0, out.width, out.height), image);
                    CGContextRelease(ctx);
                }
                CVPixelBufferUnlockBaseAddress(buffer, 0);
                CGImageRelease(image);
                if (!ctx || ![adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMakeWithSeconds(t, 1000)]) {
                    ok = NO;
                    failure = [NSString stringWithFormat:@"The video writer stopped (%@).",
                                                         writer.error.localizedDescription ?: @"?"];
                }
                CVPixelBufferRelease(buffer);
                t += delays[i].doubleValue;
                written++;
                if (written % 8 == 0) report(0.05 + 0.85 * (double)written / (double)totalFrames, @"Converting the GIF");
            }
        }
    }
    CGColorSpaceRelease(space);
    CFRelease(source);
    if (!ok) {
        [writer cancelWriting];
        if (error) *error = ImportError(@"%@", failure ?: @"The GIF could not be converted.");
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMakeWithSeconds(t, 1000)];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) {
        if (error) *error = ImportError(@"The GIF could not be converted (%@).", writer.error.localizedDescription ?: @"?");
        return NO;
    }
    return YES;
}

#pragma mark Still, thumbnail, checksum

+ (BOOL)writeJPEG:(CGImageRef)image to:(NSURL *)url quality:(double)quality error:(NSError **)error {
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (!dest) {
        if (error) *error = ImportError(@"The image file could not be created.");
        return NO;
    }
    CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef) @{(__bridge id)kCGImageDestinationLossyCompressionQuality : @(quality)});
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    if (!ok && error) *error = ImportError(@"The image file could not be written.");
    return ok;
}

+ (BOOL)writeStillAndThumbnailForItem:(HCGBackgroundPreset *)item error:(NSError **)error {
    NSURL *folder = [HACPreferences mediaFolder];
    NSURL *mediaURL = [item mediaURLInFolder:folder];
    if (!mediaURL) {
        if (error) *error = ImportError(@"The background has no video file.");
        return NO;
    }
    if (!item.stillFile) item.stillFile = [HACLibrary stillFileForIdentifier:item.identifier];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaURL options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.05, 600);
    generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.05, 600);
    NSError *e = nil;
    CGImageRef still = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(item.stillTime, 600) actualTime:NULL error:&e];
    if (!still) still = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&e];
    if (!still) {
        if (error) *error = ImportError(@"No frame could be read from the video (%@). It may be damaged.",
                                        e.localizedDescription ?: @"?");
        return NO;
    }
    BOOL ok = [self writeJPEG:still to:[item stillURLInFolder:folder] quality:0.9 error:error];
    if (ok) {
        // Thumbnail: at most 360 px on the longer side.
        CGFloat w = CGImageGetWidth(still), h = CGImageGetHeight(still);
        CGFloat s = MIN(1.0, 360.0 / MAX(w, h));
        size_t tw = MAX((size_t)1, (size_t)round(w * s)), th = MAX((size_t)1, (size_t)round(h * s));
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, tw, th, 8, 0, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(space);
        if (ctx) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            CGContextDrawImage(ctx, CGRectMake(0, 0, tw, th), still);
            CGImageRef thumb = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            if (thumb) {
                [self writeJPEG:thumb
                             to:[folder URLByAppendingPathComponent:[HACLibrary thumbnailFileForIdentifier:item.identifier]]
                        quality:0.8
                          error:NULL];
                CGImageRelease(thumb);
            }
        }
    }
    CGImageRelease(still);
    return ok;
}

+ (NSString *)sha256OfFile:(NSURL *)url {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
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

@end
