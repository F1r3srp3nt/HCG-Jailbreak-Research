//
//  HACTestMedia.m
//  HCG Animation Center — synthetic media for the Simulator tests and preview.
//

#import "HACTestMedia.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

static NSError *MediaError(NSString *message) {
    return [NSError errorWithDomain:@"HACTestMedia" code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

static void DrawFrame(CGContextRef ctx, CGSize size, double t, double hue) {
    // Diagonal colour waves drifting over time, and a soft orb on a slow orbit.
    int bands = 9;
    for (int b = bands - 1; b >= 0; b--) {
        double h = fmod(hue + b * 0.045 + t * 0.03, 1.0);
        UIColor *c = [UIColor colorWithHue:h saturation:0.75 brightness:0.25 + 0.07 * b alpha:1];
        CGContextSetFillColorWithColor(ctx, c.CGColor);
        CGMutablePathRef path = CGPathCreateMutable();
        double base = size.height * (1.05 - b / (double)bands);
        CGPathMoveToPoint(path, NULL, 0, size.height);
        for (int x = 0; x <= 32; x++) {
            double px = size.width * x / 32.0;
            double py = base + sin(x / 32.0 * M_PI * 2 + t * 1.6 + b * 0.8) * size.height * 0.035;
            CGPathAddLineToPoint(path, NULL, px, py);
        }
        CGPathAddLineToPoint(path, NULL, size.width, size.height);
        CGPathCloseSubpath(path);
        CGContextAddPath(ctx, path);
        CGContextFillPath(ctx);
        CGPathRelease(path);
    }
    double r = size.width * 0.16;
    CGPoint c = CGPointMake(size.width * (0.5 + 0.3 * cos(t * 1.1)), size.height * (0.35 + 0.15 * sin(t * 0.9)));
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:0.22].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(c.x - r, c.y - r, 2 * r, 2 * r));
}

static CMSampleBufferRef SilenceBuffer(CMAudioFormatDescriptionRef format, int64_t frameIndex, int frames) {
    size_t bytes = (size_t)frames * 2; // 16-bit mono
    CMBlockBufferRef block = NULL;
    if (CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, NULL, NULL, 0, bytes, kCMBlockBufferAssureMemoryNowFlag,
                                           &block) != noErr)
        return NULL;
    CMBlockBufferFillDataBytes(0, block, 0, bytes);
    CMSampleBufferRef sample = NULL;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, block, format, frames, CMTimeMake(frameIndex, 44100), NULL,
                                                         &sample);
    CFRelease(block);
    return sample;
}

BOOL HACWriteTestVideo(NSURL *url, CGSize size, double seconds, double hue, BOOL withAudio, NSError **error) {
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:error];
    if (!writer) return NO;
    AVAssetWriterInput *video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                   outputSettings:@{
                                                                       AVVideoCodecKey : AVVideoCodecTypeH264,
                                                                       AVVideoWidthKey : @(size.width),
                                                                       AVVideoHeightKey : @(size.height),
                                                                   }];
    video.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:video
                                   sourcePixelBufferAttributes:@{
                                       (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferWidthKey : @(size.width),
                                       (id)kCVPixelBufferHeightKey : @(size.height),
                                   }];
    [writer addInput:video];
    AVAssetWriterInput *audio = nil;
    CMAudioFormatDescriptionRef format = NULL;
    if (withAudio) {
        audio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                   outputSettings:@{
                                                       AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                       AVSampleRateKey : @44100,
                                                       AVNumberOfChannelsKey : @1,
                                                       AVEncoderBitRateKey : @64000,
                                                   }];
        audio.expectsMediaDataInRealTime = NO;
        [writer addInput:audio];
        AudioStreamBasicDescription asbd = {0};
        asbd.mSampleRate = 44100;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        asbd.mBytesPerPacket = 2;
        asbd.mFramesPerPacket = 1;
        asbd.mBytesPerFrame = 2;
        asbd.mChannelsPerFrame = 1;
        asbd.mBitsPerChannel = 16;
        CMAudioFormatDescriptionCreate(NULL, &asbd, 0, NULL, 0, NULL, NULL, &format);
    }
    if (![writer startWriting]) {
        if (error) *error = writer.error;
        if (format) CFRelease(format);
        return NO;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];
    int fps = 30, frames = (int)lround(seconds * fps);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    BOOL ok = YES;
    for (int i = 0; i < frames && ok; i++) {
        @autoreleasepool {
            while (!video.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.002];
            CVPixelBufferRef buffer = NULL;
            CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
            if (!buffer) {
                ok = NO;
                break;
            }
            CVPixelBufferLockBaseAddress(buffer, 0);
            CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), (size_t)size.width,
                                                     (size_t)size.height, 8, CVPixelBufferGetBytesPerRow(buffer), space,
                                                     kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            DrawFrame(ctx, size, i / (double)fps, hue);
            CGContextRelease(ctx);
            CVPixelBufferUnlockBaseAddress(buffer, 0);
            ok = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, fps)];
            CVPixelBufferRelease(buffer);
        }
    }
    CGColorSpaceRelease(space);
    [video markAsFinished];
    if (audio && ok) {
        int64_t total = (int64_t)lround(seconds * 44100), done = 0;
        while (done < total && ok) {
            while (!audio.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.002];
            int n = (int)MIN((int64_t)4410, total - done);
            CMSampleBufferRef sample = SilenceBuffer(format, done, n);
            ok = sample && [audio appendSampleBuffer:sample];
            if (sample) CFRelease(sample);
            done += n;
        }
        [audio markAsFinished];
    }
    if (format) CFRelease(format);
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (!ok || writer.status != AVAssetWriterStatusCompleted) {
        if (error) *error = writer.error ?: MediaError(@"video writer failed");
        return NO;
    }
    return YES;
}

BOOL HACWriteTestGIF(NSURL *url, CGSize size, NSArray<NSNumber *> *delays, NSError **error) {
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("com.compuserve.gif"),
                                                                 delays.count, NULL);
    if (!dest) {
        if (error) *error = MediaError(@"GIF destination");
        return NO;
    }
    CGImageDestinationSetProperties(dest, (__bridge CFDictionaryRef) @{
        (__bridge id)kCGImagePropertyGIFDictionary : @{(__bridge id)kCGImagePropertyGIFLoopCount : @0}
    });
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    for (NSUInteger i = 0; i < delays.count; i++) {
        CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, 0, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        DrawFrame(ctx, size, i * 0.4, 0.55 + i * 0.07);
        CGImageRef image = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        CGImageDestinationAddImage(dest, image, (__bridge CFDictionaryRef) @{
            (__bridge id)kCGImagePropertyGIFDictionary : @{(__bridge id)kCGImagePropertyGIFDelayTime : delays[i]}
        });
        CGImageRelease(image);
    }
    CGColorSpaceRelease(space);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    if (!ok && error) *error = MediaError(@"GIF finalize");
    return ok;
}

NSDictionary<NSString *, NSURL *> *HACWriteBadMedia(NSURL *folder, NSURL *validVideo) {
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSMutableData *noise = [NSMutableData dataWithLength:64 * 1024];
    arc4random_buf(noise.mutableBytes, noise.length);
    out[@"random"] = [folder URLByAppendingPathComponent:@"random.mov"];
    [noise writeToURL:out[@"random"] atomically:YES];
    NSData *valid = [NSData dataWithContentsOfURL:validVideo];
    out[@"truncated"] = [folder URLByAppendingPathComponent:@"truncated.mp4"];
    [[valid subdataWithRange:NSMakeRange(0, MIN(valid.length, (NSUInteger)3000))] writeToURL:out[@"truncated"] atomically:YES];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    NSData *png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemTealColor setFill];
        [ctx fillRect:CGRectMake(0, 0, 64, 64)];
    }];
    out[@"still"] = [folder URLByAppendingPathComponent:@"still.png"];
    [png writeToURL:out[@"still"] atomically:YES];
    out[@"oneframe"] = [folder URLByAppendingPathComponent:@"oneframe.gif"];
    HACWriteTestGIF(out[@"oneframe"], CGSizeMake(64, 64), @[ @0.1 ], NULL);
    out[@"empty"] = [folder URLByAppendingPathComponent:@"empty.mov"];
    [[NSData data] writeToURL:out[@"empty"] atomically:YES];
    return out;
}
