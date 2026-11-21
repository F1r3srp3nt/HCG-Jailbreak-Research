//
//  test_runtime.m
//  HCG Animation Center — runtime tests for the Objective-C layer, run in the
//  iOS Simulator by CI (scripts/run-simulator-tests.sh). No SpringBoard: this
//  checks the preset format, preferences, the real importer on generated
//  media (good, damaged and unsupported), the renderer's player lifecycle and
//  the AI interface's rules, and orientation / transformation (aspect ratios,
//  rotation metadata, every rotation, flip and mode, rendered pixels,
//  placements, packs, performance). It does NOT show that anything works inside
//  SpringBoard on a device.
//

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>

#import "HACAIGeneration.h"
#import "HACLibrary.h"
#import "HACMediaImporter.h"
#import "HACPreferences.h"
#import "HACProbe.h"
#import "HACTheme.h"
#import "HACTestMedia.h"
#import "HCGBackgroundCore.h"
#import "HCGBackgroundKit.h"

static long gChecks = 0, gFailures = 0;

#define CHECK(cond, ...)                                                                    \
    do {                                                                                    \
        gChecks++;                                                                          \
        if (!(cond)) {                                                                      \
            gFailures++;                                                                    \
            fprintf(stderr, "FAIL %s:%d: %s — %s\n", __FILE__, __LINE__, #cond,             \
                    [[NSString stringWithFormat:__VA_ARGS__] UTF8String]);                  \
        }                                                                                   \
    } while (0)

static BOOL Spin(NSTimeInterval timeout, BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && [limit timeIntervalSinceNow] > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    return done();
}

static NSURL *gTemp;

#pragma mark - Preset format

static NSDictionary *ValidDocument(void) {
    return @{
        @"format" : @"com.hakmicapitalgroup.background-preset",
        @"formatVersion" : @1,
        @"id" : @"6F0B2C1E-4A55-4C8B-9E1D-2B7F1A3C9D40",
        @"name" : @"Aurora",
        @"media" : @{@"kind" : @"video", @"file" : @"media.mov", @"width" : @1080, @"height" : @1920, @"duration" : @12},
        @"still" : @{@"file" : @"still.jpg", @"time" : @1.5},
        @"playback" : @{@"trimStart" : @1.5, @"trimEnd" : @9.5, @"loop" : @YES, @"speed" : @0.75, @"muted" : @YES},
        @"layout" : @{@"scaling" : @"crop", @"crop" : @{@"x" : @0.1, @"y" : @0.05, @"width" : @0.8, @"height" : @0.8}},
        @"futureKey" : @{@"ignored" : @YES},
    };
}

static NSDictionary *With(NSDictionary *base, NSString *path, id value) {
    NSMutableDictionary *d = [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:base options:0 error:NULL]
                                                             options:NSJSONReadingMutableContainers
                                                               error:NULL];
    NSArray *parts = [path componentsSeparatedByString:@"."];
    NSMutableDictionary *node = d;
    for (NSUInteger i = 0; i + 1 < parts.count; i++) node = node[parts[i]];
    if (value) {
        node[parts.lastObject] = value;
    } else {
        [node removeObjectForKey:parts.lastObject];
    }
    return d;
}

static void TestPresetFormat(void) {
    NSError *error = nil;
    HCGBackgroundPreset *p = [HCGBackgroundPreset presetWithDictionary:ValidDocument() error:&error];
    CHECK(p != nil, @"valid document parses: %@", error);
    CHECK([p.name isEqualToString:@"Aurora"] && p.scaling == HCGBackgroundScalingCrop && p.loops && fabs(p.speed - 0.75) < 1e-9,
          @"fields read");
    CHECK(fabs(p.clipDuration - 8.0) < 1e-6, @"clip duration %f", p.clipDuration);
    CHECK(p.warnings.count == 0, @"no warnings: %@", p.warnings);
    // Round trip: dictionary → preset → dictionary → preset is stable.
    NSDictionary *d1 = [p dictionaryRepresentation];
    HCGBackgroundPreset *p2 = [HCGBackgroundPreset presetWithDictionary:d1 error:&error];
    CHECK([[p2 dictionaryRepresentation] isEqual:d1], @"dictionary round trip");
    NSData *json = [p JSONDataWithError:&error];
    HCGBackgroundPreset *p3 = [HCGBackgroundPreset presetWithJSONData:json error:&error];
    CHECK([[p3 dictionaryRepresentation] isEqual:d1], @"JSON round trip");
    CHECK(!d1[@"futureKey"], @"unknown keys are not carried into the canonical form");
    CHECK([NSPropertyListSerialization propertyList:d1 isValidForFormat:NSPropertyListBinaryFormat_v1_0],
          @"canonical form is property-list safe (stored in preferences)");

    struct {
        NSString *path;
        id value;
        HCGBackgroundError code;
    } refusals[] = {
        {@"formatVersion", @2, HCGBackgroundErrorUnsupportedVersion},
        {@"formatVersion", @1.5, HCGBackgroundErrorUnsupportedVersion},
        {@"format", @"something.else", HCGBackgroundErrorNotAPreset},
        {@"media", nil, HCGBackgroundErrorMissingValue},
        {@"media.file", @"../../../etc/passwd", HCGBackgroundErrorUnsafeFileName},
        {@"media.file", @"/var/mobile/x.mov", HCGBackgroundErrorUnsafeFileName},
        {@"media.file", @".hidden.mov", HCGBackgroundErrorUnsafeFileName},
        {@"still.file", @"a/b.jpg", HCGBackgroundErrorUnsafeFileName},
        {@"media.duration", @0, HCGBackgroundErrorInvalidValue},
        {@"media.duration", @700, HCGBackgroundErrorInvalidValue},
        {@"media.width", @4, HCGBackgroundErrorInvalidValue},
        {@"media.kind", @"image", HCGBackgroundErrorInvalidValue},
        {@"id", @"not-a-uuid", HCGBackgroundErrorInvalidValue},
        {@"media.duration", @"12", HCGBackgroundErrorMissingValue},
    };
    for (size_t i = 0; i < sizeof refusals / sizeof refusals[0]; i++) {
        NSError *e = nil;
        HCGBackgroundPreset *bad = [HCGBackgroundPreset presetWithDictionary:With(ValidDocument(), refusals[i].path, refusals[i].value)
                                                                       error:&e];
        CHECK(bad == nil && e.code == refusals[i].code, @"%@ = %@ refused with %ld (got %ld: %@)", refusals[i].path,
              refusals[i].value, (long)refusals[i].code, (long)e.code, e.localizedDescription);
    }
    // Repairs, reported as warnings.
    HCGBackgroundPreset *repaired = [HCGBackgroundPreset
        presetWithDictionary:With(With(With(ValidDocument(), @"playback.speed", @9), @"playback.muted", @NO), @"layout.scaling", @"stretch")
                       error:&error];
    CHECK(repaired && fabs(repaired.speed - 2.0) < 1e-9 && repaired.scaling == HCGBackgroundScalingFill && repaired.muted,
          @"speed clamped, unknown scaling → fill, always muted");
    CHECK(repaired.warnings.count == 3, @"three warnings: %@", repaired.warnings);
    CHECK([HCGBackgroundPreset presetWithJSONData:[@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding] error:&error] == nil,
          @"non-object JSON refused");
    CHECK([HCGBackgroundPreset presetWithJSONData:[@"{" dataUsingEncoding:NSUTF8StringEncoding] error:&error] == nil,
          @"broken JSON refused");
#ifdef HAC_EXAMPLE_PRESET
    HCGBackgroundPreset *example = [HCGBackgroundPreset presetWithContentsOfURL:[NSURL fileURLWithPath:@HAC_EXAMPLE_PRESET] error:&error];
    CHECK(example != nil, @"Examples/Aurora.hcgbackground loads as a folder: %@", error);
#endif
}

#pragma mark - Preferences

static void TestPreferences(void) {
    NSString *domain = HACPreferencesDomain;
    CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        CFPreferencesSetMultiple(NULL, keys, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keys);
    }
    HACSettings *s = [HACPreferences loadSettings];
    CHECK(!s.enabled && s.homeEnabled && !s.lockEnabled && !s.homePreset && !s.lockPreset, @"defaults: off, Home on, Lock off");
    CHECK(s.reduceMotionPolicy == HACReduceMotionStill && s.lowPowerPolicy == HACLowPowerStill, @"policy defaults: still");
    CHECK([s.homePlacement isEqualToString:@"automatic"] && [s.lockPlacement isEqualToString:@"automatic"], @"placement defaults");

    [HACPreferences setValue:ValidDocument() forKey:HACKeyHomePreset];
    [HACPreferences setValue:@"same" forKey:HACKeyLockSource];
    [HACPreferences setValue:@"nowhere" forKey:HACKeyHomePlacement];
    [HACPreferences setValue:@"system" forKey:HACKeyLowPower];
    s = [HACPreferences loadSettings];
    CHECK([s.homePreset.identifier isEqualToString:@"6F0B2C1E-4A55-4C8B-9E1D-2B7F1A3C9D40"], @"home preset stored");
    CHECK(s.lockSameAsHome && [s.lockPreset.identifier isEqualToString:s.homePreset.identifier], @"Lock uses Home's");
    CHECK([s.homePlacement isEqualToString:@"automatic"], @"invalid placement → automatic");
    CHECK(s.lowPowerPolicy == HACLowPowerSystem, @"low power policy read");
    [HACPreferences setValue:With(ValidDocument(), @"media.file", @"../x.mov") forKey:HACKeyHomePreset];
    s = [HACPreferences loadSettings];
    CHECK(!s.homePreset && s.homePresetProblem.length > 0, @"unsafe stored preset rejected with a reason: %@", s.homePresetProblem);
    [HACPreferences setValue:@"not a dictionary" forKey:HACKeyHomePreset];
    CHECK(![HACPreferences loadSettings].homePreset, @"non-dictionary preset rejected");
    for (NSString *key in @[ HACKeyHomePreset, HACKeyLockSource, HACKeyHomePlacement, HACKeyLowPower ])
        [HACPreferences setValue:nil forKey:key];
}

#pragma mark - Import

static HCGBackgroundPreset *Import(HACMediaImporter *importer, NSURL *file, NSError **errorOut) {
    NSError *stageError = nil;
    NSURL *staged = [HACMediaImporter stageFileAtURL:file error:&stageError];
    if (!staged) {
        if (errorOut) *errorOut = stageError;
        return nil;
    }
    __block BOOL finished = NO;
    __block HCGBackgroundPreset *result = nil;
    __block NSError *error = nil;
    [importer importStagedFile:staged
                 suggestedName:file.lastPathComponent
                      progress:nil
                    completion:^(HCGBackgroundPreset *item, NSError *e) {
                        result = item;
                        error = e;
                        finished = YES;
                    }];
    Spin(120, ^BOOL {
        return finished;
    });
    if (errorOut) *errorOut = error;
    return result;
}

static NSUInteger CountFiles(NSURL *folder) {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder.path error:NULL].count;
}

static HCGBackgroundPreset *gVideoItem, *gGIFItem;
static NSDictionary<NSString *, NSURL *> *gBad;

static void TestImport(void) {
    HACMediaImporter *importer = [[HACMediaImporter alloc] init];
    NSURL *source = [gTemp URLByAppendingPathComponent:@"source"];
    [[NSFileManager defaultManager] createDirectoryAtURL:source withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *video = [source URLByAppendingPathComponent:@"Waves.mov"];
    NSError *error = nil;
    CHECK(HACWriteTestVideo(video, CGSizeMake(360, 640), 2.5, 0.7, YES, &error), @"test video written: %@", error);
    AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:video options:nil];
    CHECK([sourceAsset tracksWithMediaType:AVMediaTypeAudio].count == 1, @"the source has an audio track");

    gVideoItem = Import(importer, video, &error);
    CHECK(gVideoItem != nil, @"video imported: %@", error.localizedDescription);
    NSURL *media = [HACPreferences mediaFolder];
    AVURLAsset *stored = [AVURLAsset URLAssetWithURL:[gVideoItem mediaURLInFolder:media] options:nil];
    CHECK([stored tracksWithMediaType:AVMediaTypeVideo].count == 1, @"stored file has the video track");
    CHECK([stored tracksWithMediaType:AVMediaTypeAudio].count == 0, @"stored file has NO audio track (always muted)");
    CHECK(CGSizeEqualToSize(gVideoItem.mediaSize, CGSizeMake(360, 640)), @"size %@", NSStringFromCGSize(gVideoItem.mediaSize));
    CHECK(fabs(gVideoItem.duration - 2.5) < 0.1, @"duration %f", gVideoItem.duration);
    CHECK([gVideoItem.origin isEqualToString:@"video"] && gVideoItem.mediaSHA256.length == 64, @"origin and checksum");
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[gVideoItem stillURLInFolder:media].path], @"still written");
    CHECK([[NSFileManager defaultManager] fileExistsAtPath:[[HACLibrary shared] thumbnailURLForItem:gVideoItem].path], @"thumbnail written");
    CHECK([gVideoItem.name isEqualToString:@"Waves"], @"name from file: %@", gVideoItem.name);

    NSURL *gif = [source URLByAppendingPathComponent:@"Spark.gif"];
    CHECK(HACWriteTestGIF(gif, CGSizeMake(101, 75), @[ @0.0, @0.05, @0.2 ], &error), @"test GIF written");
    gGIFItem = Import(importer, gif, &error);
    CHECK(gGIFItem != nil, @"GIF imported: %@", error.localizedDescription);
    CHECK([gGIFItem.origin isEqualToString:@"gif"], @"GIF origin");
    CHECK(CGSizeEqualToSize(gGIFItem.mediaSize, CGSizeMake(100, 74)), @"GIF transcoded to even size: %@", NSStringFromCGSize(gGIFItem.mediaSize));
    // Delays 0 → 0.1 s (browser rule), 0.05, 0.2 = 0.35 s; repeated 3× to reach at least 1 s.
    CHECK(fabs(gGIFItem.duration - 1.05) < 0.06, @"GIF timing → %f s", gGIFItem.duration);
    CHECK([HACMediaImporter kindOfFileAtURL:gif] == HACMediaKindGIF && [HACMediaImporter kindOfFileAtURL:video] == HACMediaKindVideo,
          @"sniffing");

    NSUInteger before = CountFiles(media);
    gBad = HACWriteBadMedia([gTemp URLByAppendingPathComponent:@"bad"], video);
    NSDictionary<NSString *, NSString *> *expected = @{
        @"random" : @"",
        @"truncated" : @"",
        @"still" : @"still image",
        @"oneframe" : @"only one frame",
        @"empty" : @"empty",
    };
    for (NSString *name in expected) {
        NSError *e = nil;
        HCGBackgroundPreset *item = Import(importer, gBad[name], &e);
        CHECK(item == nil && e.localizedDescription.length > 0, @"%@ refused (%@)", name, e.localizedDescription);
        if (expected[name].length)
            CHECK([e.localizedDescription rangeOfString:expected[name] options:NSCaseInsensitiveSearch].location != NSNotFound,
                  @"%@: reason mentions \"%@\": %@", name, expected[name], e.localizedDescription);
    }
    CHECK(CountFiles(media) == before, @"refused imports leave no files in Media (%lu → %lu)", (unsigned long)before,
          (unsigned long)CountFiles(media));
    NSURL *staging = [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:@"Staging"]];
    CHECK(CountFiles(staging) == 0, @"staging is empty after imports");
    [[HACLibrary shared] reload];
    CHECK([HACLibrary shared].items.count == 2, @"library has the two good items");

    // A corrupt library file is quarantined, never fatal.
    NSURL *libraryFile = [NSURL fileURLWithPath:[[HACPreferences storeRoot] stringByAppendingPathComponent:@"library.json"]];
    NSData *good = [NSData dataWithContentsOfURL:libraryFile];
    [@"{not json" writeToURL:libraryFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[HACLibrary shared] reload];
    CHECK([HACLibrary shared].items.count == 0 && [HACLibrary shared].loadProblem.length > 0, @"corrupt library quarantined");
    [good writeToURL:libraryFile atomically:YES];
    [[HACLibrary shared] reload];
    CHECK([HACLibrary shared].items.count == 2, @"library restored");

    // Export and re-import a preset folder.
    NSURL *exported = [[HACLibrary shared] exportItem:gGIFItem error:&error];
    CHECK(exported && [[NSFileManager defaultManager] fileExistsAtPath:[exported URLByAppendingPathComponent:@"preset.json"].path],
          @"exported %@", error);
    HCGBackgroundPreset *reimported = [[HACLibrary shared] importPresetFolder:exported error:&error];
    CHECK(reimported && ![reimported.identifier isEqualToString:gGIFItem.identifier], @"re-imported under a new id: %@", error);
    if (reimported) [[HACLibrary shared] removeItem:reimported error:NULL];
    // Tampered media is refused by the checksum.
    NSURL *exportedMedia = [exported URLByAppendingPathComponent:@"media.mp4"];
    NSMutableData *tampered = [NSMutableData dataWithContentsOfURL:exportedMedia];
    if (tampered.length > 100) ((uint8_t *)tampered.mutableBytes)[tampered.length - 50] ^= 0xFF;
    [tampered writeToURL:exportedMedia atomically:YES];
    CHECK([[HACLibrary shared] importPresetFolder:exported error:&error] == nil, @"tampered media refused: %@", error.localizedDescription);
}

#pragma mark - Renderer

@interface FailRecorder : NSObject <HCGBackgroundViewDelegate>
@property (nonatomic) NSInteger failures;
@property (nonatomic) NSInteger ready;
@end

@implementation FailRecorder
- (void)backgroundView:(HCGBackgroundView *)view didFailWithError:(NSError *)error {
    self.failures++;
}
- (void)backgroundViewDidBecomeReady:(HCGBackgroundView *)view {
    self.ready++;
}
@end

static AVPlayer *PlayerOf(HCGBackgroundView *view) {
    return [view valueForKey:@"player"];
}

static void TestRenderer(void) {
    if (!gVideoItem) return;
    NSURL *media = [HACPreferences mediaFolder];
    HCGBackgroundView *view = [[HCGBackgroundView alloc] initWithFrame:CGRectMake(0, 0, 207, 448)];
    FailRecorder *recorder = [[FailRecorder alloc] init];
    view.delegate = recorder;
    CHECK(view.hidden && !view.userInteractionEnabled && [view hitTest:CGPointMake(10, 10) withEvent:nil] == nil &&
              view.accessibilityElementsHidden,
          @"never interactive, hidden from accessibility, hidden until shown");
    [view setPreset:gVideoItem folder:media];
    view.display = HCGBackgroundDisplayPlaying;
    [view layoutIfNeeded];
    BOOL ready = Spin(20, ^BOOL {
        return PlayerOf(view).currentItem.status == AVPlayerItemStatusReadyToPlay;
    });
    CHECK(ready, @"player ready: %@", view.stateDescription);
    AVPlayer *player = PlayerOf(view);
    CHECK(player.muted && !player.allowsExternalPlayback && player.rate > 0.9, @"muted, local only, playing at 1×");
    CHECK([player.currentItem.asset tracksWithMediaType:AVMediaTypeAudio].count == 0, @"no audio track is played");
    CHECK([player isKindOfClass:[AVQueuePlayer class]], @"looping uses AVQueuePlayer + AVPlayerLooper");
    CHECK(!view.hidden && view.playerActive, @"visible with a decoder");
    Spin(3, ^BOOL {
        return view.stillLoaded;
    });
    CHECK(view.stillLoaded, @"still loaded under the video");

    // Layout: the C core decides.
    HCGBGRect expect = hcgbg_layout((HCGBGSize){207, 448}, (HCGBGSize){360, 640}, HCGBGScalingFill, (HCGBGRect){0, 0, 1, 1});
    CHECK(CGRectEqualToRect(view.mediaFrame, CGRectMake(expect.x, expect.y, expect.width, expect.height)), @"fill layout");
    HCGBackgroundPreset *fit = [gVideoItem copy];
    fit.scaling = HCGBackgroundScalingFit;
    fit.speed = 2.0;
    [view setPreset:fit folder:media];
    CHECK(PlayerOf(view) == player, @"scaling and speed changes keep the same decoder (no reload, no flicker)");
    CHECK(fabs(PlayerOf(view).rate - 2.0) < 0.01, @"speed 2× applied: %f", PlayerOf(view).rate);
    CHECK(view.mediaFrame.size.width <= 207.001 && view.mediaFrame.size.height < 448, @"fit letterboxes");

    HCGBackgroundPreset *trimmed = [fit copy];
    trimmed.trimStart = 0.5;
    trimmed.trimEnd = 1.5;
    [view setPreset:trimmed folder:media];
    Spin(20, ^BOOL {
        return PlayerOf(view).currentItem.status == AVPlayerItemStatusReadyToPlay;
    });
    CHECK(PlayerOf(view) != player, @"a trim change reloads the clip");
    CMTime d = PlayerOf(view).currentItem.asset.duration;
    CHECK(fabs(CMTimeGetSeconds(d) - 1.0) < 0.1, @"trimmed clip is 1.0 s: %f", CMTimeGetSeconds(d));

    view.display = HCGBackgroundDisplayPaused;
    CHECK(PlayerOf(view).rate == 0, @"paused: rate 0");
    view.display = HCGBackgroundDisplayStill;
    CHECK(!view.playerActive && PlayerOf(view) == nil, @"still: decoder freed");
    view.display = HCGBackgroundDisplayPlaying;
    CHECK(view.playerActive, @"playing again: decoder recreated");
    [view releasePlayer];
    CHECK(!view.playerActive, @"releasePlayer frees the decoder");
    view.display = HCGBackgroundDisplayNone;
    CHECK(view.hidden && !view.playerActive, @"none: hidden, no decoder");

    // Play once: no looper, pauses at the end.
    HCGBackgroundPreset *once = [gVideoItem copy];
    once.loops = NO;
    [view setPreset:once folder:media];
    view.display = HCGBackgroundDisplayPlaying;
    Spin(20, ^BOOL {
        return PlayerOf(view).currentItem.status == AVPlayerItemStatusReadyToPlay;
    });
    CHECK(PlayerOf(view) && ![PlayerOf(view) isKindOfClass:[AVQueuePlayer class]] &&
              PlayerOf(view).actionAtItemEnd == AVPlayerActionAtItemEndPause,
          @"no loop: plays once and holds the last frame");

    // Damaged media: the view reports once and falls back to the still.
    NSURL *damaged = [media URLByAppendingPathComponent:@"damaged.mov"];
    [[NSFileManager defaultManager] copyItemAtURL:gBad[@"random"] toURL:damaged error:NULL];
    HCGBackgroundPreset *broken = [gVideoItem copy];
    broken.mediaFile = @"damaged.mov";
    recorder.failures = 0;
    [view setPreset:broken folder:media];
    view.display = HCGBackgroundDisplayPlaying;
    Spin(20, ^BOOL {
        return recorder.failures > 0;
    });
    CHECK(recorder.failures == 1 && view.mediaFailed && !view.playerActive, @"damaged media: one failure report, decoder gone");
    CHECK([view.stateDescription hasPrefix:@"Video unavailable"], @"state: %@", view.stateDescription);
    view.display = HCGBackgroundDisplayPaused;
    view.display = HCGBackgroundDisplayPlaying;
    CHECK(recorder.failures == 1 && !view.playerActive, @"no retry loop on the same broken preset");
    HCGBackgroundPreset *missing = [gVideoItem copy];
    missing.mediaFile = @"missing.mov";
    [view setPreset:missing folder:media];
    CHECK(view.mediaFailed && recorder.failures == 2, @"missing file fails at once");
    [view setPreset:nil folder:nil];
    CHECK(view.hidden && !view.playerActive, @"nil preset clears everything");
    [[NSFileManager defaultManager] removeItemAtURL:damaged error:NULL];
}

#pragma mark - Orientation and transformation (0.2)

static double FootprintMB(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.phys_footprint / 1048576.0;
}

/// Corners as normalised points, y down: 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left.
static CGPoint CornerPoint(int corner) {
    static const CGPoint points[4] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
    return points[corner & 3];
}

static int CornerOfPoint(CGPoint p) {
    for (int i = 0; i < 4; i++)
        if (fabs(CornerPoint(i).x - p.x) < 1e-9 && fabs(CornerPoint(i).y - p.y) < 1e-9) return i;
    return -1;
}

/// Where a corner of the (display-oriented) picture ends up on screen: rotated
/// clockwise, then flipped in screen axes. Written independently of the editor.
static int ExpectedCorner(int corner, NSInteger rotation, BOOL flipH, BOOL flipV) {
    CGPoint p = CornerPoint(corner);
    for (NSInteger r = 0; r < hcgbg_rotation_normalize((double)rotation, NULL); r += 90) p = CGPointMake(1 - p.y, p.x);
    if (flipH) p.x = 1 - p.x;
    if (flipV) p.y = 1 - p.y;
    return CornerOfPoint(p);
}

/// The corner whose pixels are the red marker (-1: none or several).
static int MarkedCorner(CGImageRef image) {
    size_t w = 200, h = 200;
    uint8_t *px = calloc(w * h, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image); // row 0 = the image's top
    CGContextRelease(ctx);
    int found = -1, count = 0;
    for (int c = 0; c < 4; c++) {
        CGPoint p = CornerPoint(c);
        size_t x = (size_t)lround(p.x ? w - 1 - w * 0.025 : w * 0.025), y = (size_t)lround(p.y ? h - 1 - h * 0.025 : h * 0.025);
        const uint8_t *q = px + (y * w + x) * 4; // B G R A
        if (q[2] > 170 && q[1] < 90 && q[0] < 90) {
            found = c;
            count++;
        }
    }
    free(px);
    return count == 1 ? found : -1;
}

static CGImageRef CopyRenderedLayer(UIView *view) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.blackColor setFill];
            UIRectFill(view.bounds);
            [view.layer renderInContext:context.CGContext];
        }];
    return CGImageRetain(image.CGImage);
}

static CGSize ImageSizeOfFile(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return CGSizeZero;
    NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return CGSizeMake([p[(id)kCGImagePropertyPixelWidth] doubleValue], [p[(id)kCGImagePropertyPixelHeight] doubleValue]);
}

static BOOL NearRect(CGRect a, HCGBGRect b) {
    return fabs(a.origin.x - b.x) < 0.01 && fabs(a.origin.y - b.y) < 0.01 && fabs(a.size.width - b.width) < 0.01 &&
           fabs(a.size.height - b.height) < 0.01;
}

/// The C core's placement for a preset in a container (what every renderer must show).
static HCGBGPlacement CorePlacement(HCGBackgroundPreset *p, CGSize container) {
    HCGBGTransform t = hcgbg_transform_identity();
    t.rotation = (int)p.rotation;
    t.flipHorizontal = p.flipHorizontal;
    t.flipVertical = p.flipVertical;
    t.stretch = p.stretch;
    t.regionAllModes = p.usesRegionInAllModes;
    return hcgbg_layout_transformed((HCGBGSize){container.width, container.height},
                                    (HCGBGSize){p.mediaSize.width, p.mediaSize.height}, (HCGBGScaling)p.scaling,
                                    (HCGBGRect){p.crop.origin.x, p.crop.origin.y, p.crop.size.width, p.crop.size.height}, t);
}

typedef struct {
    NSString *name;
    CGSize natural;      ///< the stored frame
    NSInteger metadata;  ///< orientation metadata, clockwise degrees
    CGSize display;      ///< expected display size
} OrientedClip;

static HCGBackgroundPreset *gRotatedItem, *gUltrawideItem;

static void TestOrientation(void) {
    NSURL *media = [HACPreferences mediaFolder];
    HACMediaImporter *importer = [[HACMediaImporter alloc] init];
    NSError *error = nil;
    OrientedClip clips[] = {
        {@"Portrait", {360, 640}, 0, {360, 640}},
        {@"Landscape", {640, 360}, 0, {640, 360}},
        {@"Square", {480, 480}, 0, {480, 480}},
        {@"Ultrawide", {1280, 360}, 0, {1280, 360}},
        {@"Rotated90", {640, 360}, 90, {360, 640}},
        {@"Rotated180", {640, 360}, 180, {640, 360}},
        {@"Rotated270", {640, 360}, 270, {360, 640}},
    };
    const int clipCount = (int)(sizeof clips / sizeof clips[0]);
    HCGBackgroundPreset *items[sizeof clips / sizeof clips[0]] = {nil};
    for (int i = 0; i < clipCount; i++) {
        OrientedClip c = clips[i];
        NSURL *file = [gTemp URLByAppendingPathComponent:[c.name stringByAppendingPathExtension:@"mov"]];
        CHECK(HACWriteTestVideoWithOrientation(file, c.natural, 1.6, 0.58, NO, HACTestRotationTransform(c.natural, c.metadata),
                                               YES, &error),
              @"%@ test video written: %@", c.name, error);
        HCGBackgroundPreset *item = Import(importer, file, &error);
        items[i] = item;
        CHECK(item != nil, @"%@ imported: %@", c.name, error.localizedDescription);
        if (!item) continue;
        CHECK(CGSizeEqualToSize(item.mediaSize, c.display), @"%@: display size %@", c.name, NSStringFromCGSize(item.mediaSize));
        CHECK(item.sourceRotation == c.metadata, @"%@: metadata rotation %ld detected (expected %ld)", c.name,
              (long)item.sourceRotation, (long)c.metadata);
        CHECK([item.mediaFile.pathExtension isEqualToString:@"mov"] && !item.generator[@"converted"],
              @"%@: passthrough, no transcoding (%@)", c.name, item.mediaFile);
        AVURLAsset *stored = [AVURLAsset URLAssetWithURL:[item mediaURLInFolder:media] options:nil];
        AVAssetTrack *track = [stored tracksWithMediaType:AVMediaTypeVideo].firstObject;
        CGAffineTransform t = track.preferredTransform;
        CHECK(track && CGSizeEqualToSize(track.naturalSize, c.natural) &&
                  hcgbg_rotation_from_matrix(t.a, t.b, t.c, t.d, NULL) == c.metadata,
              @"%@: stored file keeps the source frame and its orientation metadata", c.name);
        // Poster frame: the source as displayed (metadata applied), never the editor's transform.
        NSURL *still = [item stillURLInFolder:media];
        CHECK(CGSizeEqualToSize(ImageSizeOfFile(still), c.display), @"%@: still is %@", c.name,
              NSStringFromCGSize(ImageSizeOfFile(still)));
        UIImage *stillImage = [UIImage imageWithContentsOfFile:still.path];
        int expected = ExpectedCorner(0, c.metadata, NO, NO);
        CHECK(MarkedCorner(stillImage.CGImage) == expected, @"%@: marker at corner %d of the still (expected %d)", c.name,
              MarkedCorner(stillImage.CGImage), expected);
        // The library thumbnail helper turns the still exactly like the renderer.
        HCGBackgroundPreset *turned = [item copy];
        turned.rotation = 90;
        turned.flipHorizontal = YES;
        UIImage *oriented = HACOrientedImage(stillImage, turned);
        CHECK(fabs(oriented.size.width - stillImage.size.height) < 0.5 && fabs(oriented.size.height - stillImage.size.width) < 0.5,
              @"%@: oriented thumbnail swaps sides", c.name);
        CHECK(MarkedCorner(oriented.CGImage) == ExpectedCorner(expected, 90, YES, NO), @"%@: oriented thumbnail marker", c.name);
    }
    HCGBackgroundPreset *rotated = items[4];
    gRotatedItem = rotated;
    CHECK([HACDescribeSource(rotated) containsString:@"metadata rotation 90° applied"], @"source row: %@", HACDescribeSource(rotated));

    // High resolution: an ultrawide 3840 x 1080 clip is within the decoder budget
    // and is stored as is; a 3840 x 2160 clip is converted upright, aspect kept.
    CHECK(HACVideoFitsWithoutConversion(CGSizeMake(3840, 1080)) && !HACVideoFitsWithoutConversion(CGSizeMake(3840, 2160)),
          @"passthrough budget");
    CGSize converted = HACConvertedVideoSize(CGSizeMake(3840, 2160));
    CHECK(converted.width * converted.height <= HACMaxStoredPixels && fabs(converted.width / converted.height - 16.0 / 9) < 0.01 &&
              (long)converted.width % 2 == 0 && (long)converted.height % 2 == 0,
          @"conversion size %@", NSStringFromCGSize(converted));
    NSURL *wide = [gTemp URLByAppendingPathComponent:@"Ultrawide4K.mov"];
    CHECK(HACWriteTestVideoWithOrientation(wide, CGSizeMake(3840, 1080), 1.0, 0.58, NO, CGAffineTransformIdentity, YES, &error),
          @"3840 x 1080 video written: %@", error);
    NSDate *start = [NSDate date];
    gUltrawideItem = Import(importer, wide, &error);
    double wideSeconds = -[start timeIntervalSinceNow];
    CHECK(gUltrawideItem && CGSizeEqualToSize(gUltrawideItem.mediaSize, CGSizeMake(3840, 1080)) &&
              !gUltrawideItem.generator[@"converted"],
          @"3840 x 1080 stored without transcoding: %@ %@", NSStringFromCGSize(gUltrawideItem.mediaSize), error);
    printf("perf: import 3840x1080 passthrough %.2f s\n", wideSeconds);
    NSURL *uhd = [gTemp URLByAppendingPathComponent:@"Rotated4K.mov"];
    CGSize uhdNatural = CGSizeMake(3840, 2160);
    CHECK(HACWriteTestVideoWithOrientation(uhd, uhdNatural, 1.0, 0.58, NO, HACTestRotationTransform(uhdNatural, 90), YES, &error),
          @"3840 x 2160 rotated video written: %@", error);
    start = [NSDate date];
    HCGBackgroundPreset *uhdItem = Import(importer, uhd, &error);
    printf("perf: import 3840x2160 (rotated) with conversion %.2f s\n", -[start timeIntervalSinceNow]);
    CGSize uhdExpected = HACConvertedVideoSize(CGSizeMake(2160, 3840));
    CHECK(uhdItem && CGSizeEqualToSize(uhdItem.mediaSize, uhdExpected) && [uhdItem.generator[@"converted"] isEqual:@YES] &&
              uhdItem.sourceRotation == 90,
          @"oversized rotated clip converted upright to %@ (expected %@): %@", NSStringFromCGSize(uhdItem.mediaSize),
          NSStringFromCGSize(uhdExpected), error.localizedDescription);
    if (uhdItem) {
        UIImage *uhdStill = [UIImage imageWithContentsOfFile:[uhdItem stillURLInFolder:media].path];
        CHECK(MarkedCorner(uhdStill.CGImage) == 1, @"converted clip keeps its orientation (marker top-right)");
        [[HACLibrary shared] removeItem:uhdItem error:NULL];
    }

    // Renderer: every rotation, flip and mode, at zoom 1 and zoomed + moved,
    // lays out exactly as the C core says, still and video alike.
    CGSize container = CGSizeMake(207, 448);
    HCGBackgroundView *view = [[HCGBackgroundView alloc] initWithFrame:CGRectMake(0, 0, container.width, container.height)];
    long layoutChecks = 0, layoutFailures = 0, pixelChecks = 0, pixelFailures = 0;
    for (int i = 0; i < clipCount; i++) {
        HCGBackgroundPreset *item = items[i];
        if (!item) continue;
        [view setPreset:item folder:media];
        view.display = HCGBackgroundDisplayStill;
        Spin(5, ^BOOL {
            return view.stillLoaded;
        });
        CHECK(view.stillLoaded, @"%@: still shown", clips[i].name);
        CALayer *stillLayer = [view valueForKey:@"stillLayer"];
        CALayer *playerLayer = [view valueForKey:@"playerLayer"];
        int marker = ExpectedCorner(0, clips[i].metadata, NO, NO);
        for (NSInteger rotation = 0; rotation < 360; rotation += 90) {
            for (int flips = 0; flips < 4; flips++) {
                for (int mode = 0; mode < 3; mode++) {
                    for (int zoomed = 0; zoomed < 2; zoomed++) {
                        HCGBackgroundPreset *p = [item copy];
                        p.rotation = rotation;
                        p.flipHorizontal = flips & 1;
                        p.flipVertical = (flips & 2) != 0;
                        p.stretch = mode == 2;
                        p.scaling = mode == 0 ? HCGBackgroundScalingFit
                                    : mode == 1 ? HCGBackgroundScalingCrop
                                                : HCGBackgroundScalingFill;
                        p.hasTransform = YES;
                        CGSize o = p.orientedMediaSize;
                        HCGBGRect r = hcgbg_region_from_zoom((HCGBGScaling)p.scaling, p.stretch,
                                                             (HCGBGSize){container.width, container.height},
                                                             (HCGBGSize){o.width, o.height}, zoomed ? 1.6 : 1.0,
                                                             zoomed ? 0.3 : 0.5, zoomed ? 0.7 : 0.5);
                        p.crop = CGRectMake(r.x, r.y, r.width, r.height);
                        [view setPreset:p folder:media];
                        [view setNeedsLayout];
                        [view layoutIfNeeded];
                        HCGBGPlacement core = CorePlacement(p, container);
                        CGAffineTransform m = CGAffineTransformMake(core.a, core.b, core.c, core.d, 0, 0);
                        BOOL ok = NearRect(view.mediaFrame, core.frame) && fabs(view.mediaBounds.width - core.bounds.width) < 0.01 &&
                                  fabs(view.mediaBounds.height - core.bounds.height) < 0.01 &&
                                  CGAffineTransformEqualToTransform(view.mediaTransform, m) &&
                                  CGAffineTransformEqualToTransform(stillLayer.affineTransform, m) &&
                                  CGAffineTransformEqualToTransform(playerLayer.affineTransform, m) &&
                                  CGRectEqualToRect(stillLayer.frame, playerLayer.frame) &&
                                  NearRect(stillLayer.frame, core.frame);
                        layoutChecks++;
                        if (!ok) {
                            layoutFailures++;
                            if (layoutFailures <= 5)
                                fprintf(stderr, "FAIL layout %s rot %ld flips %d mode %d zoom %d: frame %s\n",
                                        clips[i].name.UTF8String, (long)rotation, flips, mode, zoomed,
                                        NSStringFromCGRect(view.mediaFrame).UTF8String);
                        }
                        // Pixels: with Stretch at zoom 1 the picture's corners are the
                        // screen's corners, so the marker must be where the turn and flips put it.
                        if (mode == 2 && !zoomed) {
                            CGImageRef shot = CopyRenderedLayer(view);
                            int got = MarkedCorner(shot), want = ExpectedCorner(marker, rotation, p.flipHorizontal, p.flipVertical);
                            CGImageRelease(shot);
                            pixelChecks++;
                            if (got != want) {
                                pixelFailures++;
                                fprintf(stderr, "FAIL pixels %s rot %ld flips %d: marker at %d, expected %d\n",
                                        clips[i].name.UTF8String, (long)rotation, flips, got, want);
                            }
                        }
                    }
                }
            }
        }
    }
    CHECK(layoutChecks > 0 && layoutFailures == 0, @"renderer layout = C core: %ld of %ld cases failed", layoutFailures, layoutChecks);
    CHECK(pixelChecks > 0 && pixelFailures == 0, @"rendered pixels: %ld of %ld rotation / flip cases wrong", pixelFailures, pixelChecks);
    printf("orientation: %ld renderer layouts and %ld rendered rotation / flip cases checked\n", layoutChecks, pixelChecks);

    // Playback with a transform: trim, loop and speed still apply, and layout
    // edits never reload the decoder.
    if (rotated) {
        HCGBackgroundPreset *p = [rotated copy];
        p.rotation = 90;
        p.flipHorizontal = YES;
        p.hasTransform = YES;
        p.scaling = HCGBackgroundScalingCrop;
        p.crop = CGRectMake(0.1, 0.2, 0.7, 0.6);
        p.trimStart = 0.3;
        p.trimEnd = 1.3;
        p.speed = 1.5;
        p.loops = YES;
        [view setPreset:p folder:media];
        view.display = HCGBackgroundDisplayPlaying;
        [view layoutIfNeeded];
        BOOL ready = Spin(20, ^BOOL {
            return PlayerOf(view).currentItem.status == AVPlayerItemStatusReadyToPlay;
        });
        AVPlayer *player = PlayerOf(view);
        CHECK(ready && [player isKindOfClass:[AVQueuePlayer class]] && fabs(player.rate - 1.5) < 0.01,
              @"transformed clip plays looped at 1.5×: %@", view.stateDescription);
        CHECK(fabs(CMTimeGetSeconds(player.currentItem.asset.duration) - 1.0) < 0.1, @"trim 0.3–1.3 s kept with a transform");
        HCGBGPlacement core = CorePlacement(p, container);
        CHECK(CGAffineTransformEqualToTransform([[view valueForKey:@"playerLayer"] affineTransform],
                                                CGAffineTransformMake(core.a, core.b, core.c, core.d, 0, 0)),
              @"the playing video layer carries the transform");
        HCGBackgroundPreset *turned = [p copy];
        turned.rotation = 270;
        turned.stretch = YES;
        [view setPreset:turned folder:media];
        CHECK(PlayerOf(view) == player, @"rotation / stretch edits keep the same decoder (no reload)");
        HCGBackgroundPreset *once = [turned copy];
        once.loops = NO;
        [view setPreset:once folder:media];
        Spin(20, ^BOOL {
            return PlayerOf(view).currentItem.status == AVPlayerItemStatusReadyToPlay;
        });
        CHECK(PlayerOf(view).actionAtItemEnd == AVPlayerActionAtItemEndPause, @"play-once works with a transform");
        [view releasePlayer];
    }

    // Performance: layout is pure arithmetic; a layout-only edit is a layer
    // property change. Memory: turning the video adds no decoder memory.
    double t0 = CACurrentMediaTime();
    volatile double sink = 0;
    for (int i = 0; i < 100000; i++) {
        HCGBGTransform t = hcgbg_transform_identity();
        t.rotation = (i % 4) * 90;
        t.flipHorizontal = i & 1;
        t.regionAllModes = true;
        HCGBGPlacement pl = hcgbg_layout_transformed((HCGBGSize){207, 448}, (HCGBGSize){3840, 1080}, (HCGBGScaling)(i % 3),
                                                     (HCGBGRect){0.1, 0.1, 0.5, 0.5}, t);
        sink += pl.frame.width;
    }
    double perLayoutMicros = (CACurrentMediaTime() - t0) * 1e6 / 100000;
    printf("perf: hcgbg_layout_transformed %.3f µs per call\n", perLayoutMicros);
    CHECK(perLayoutMicros < 20, @"layout arithmetic %.3f µs", perLayoutMicros);
    if (gUltrawideItem) {
        HCGBackgroundView *big = [[HCGBackgroundView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
        double base = FootprintMB();
        [big setPreset:gUltrawideItem folder:media];
        big.display = HCGBackgroundDisplayPlaying;
        [big layoutIfNeeded];
        Spin(20, ^BOOL {
            return PlayerOf(big).currentItem.status == AVPlayerItemStatusReadyToPlay;
        });
        Spin(1.5, ^BOOL {
            return NO;
        });
        double plain = FootprintMB() - base;
        AVPlayer *player = PlayerOf(big);
        HCGBackgroundPreset *p = [gUltrawideItem copy];
        p.rotation = 90;
        p.hasTransform = YES;
        p.scaling = HCGBackgroundScalingCrop;
        t0 = CACurrentMediaTime();
        const int edits = 2000;
        for (int i = 0; i < edits; i++) {
            p.rotation = (i % 4) * 90;
            p.flipHorizontal = i & 1;
            p.crop = CGRectMake(0.001 * (i % 100), 0, 0.5, 0.5);
            [big setPreset:p folder:media];
            [big layoutIfNeeded];
        }
        double perEditMs = (CACurrentMediaTime() - t0) * 1000 / edits;
        Spin(1.5, ^BOOL {
            return NO;
        });
        double turned = FootprintMB() - base;
        printf("perf: layout-only edit on a playing 3840x1080 clip %.3f ms; footprint +%.1f MB upright, +%.1f MB after "
               "turning (%.1f MB base)\n",
               perEditMs, plain, turned, base);
        CHECK(PlayerOf(big) == player, @"2000 layout edits, one decoder");
        CHECK(perEditMs < 5, @"layout-only edit %.3f ms", perEditMs);
        CHECK(turned - plain < 25, @"turning the video adds no decoder memory (%.1f → %.1f MB)", plain, turned);
        [big releasePlayer];
    }
    (void)sink;
}

static void TestPlacementsAndPacks(void) {
    HCGBackgroundPreset *item = gRotatedItem;
    if (!item) return;
    HACLibrary *library = [HACLibrary shared];
    NSURL *media = [HACPreferences mediaFolder];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    CHECK(![library item:item hasOwnSettingsForPlacement:HACSurfaceLock], @"a new item's Lock Screen follows the Home Screen");
    HCGBackgroundPreset *home = [library presetForItem:item placement:HACSurfaceHome];
    home.rotation = 90;
    home.scaling = HCGBackgroundScalingFit;
    home.hasTransform = YES;
    CHECK([library updateItem:home placement:HACSurfaceHome error:&error], @"Home settings saved: %@", error);
    CHECK([library presetForItem:item placement:HACSurfaceLock].rotation == 90, @"Lock follows Home until edited");

    HCGBackgroundPreset *lock = [library presetForItem:item placement:HACSurfaceLock];
    lock.rotation = 180;
    lock.flipVertical = YES;
    lock.stretch = YES;
    lock.scaling = HCGBackgroundScalingFill;
    lock.hasTransform = YES;
    lock.trimStart = 0.2;
    lock.speed = 0.75;
    lock.stillTime = 1.0;
    CHECK([HACMediaImporter writeStillForItem:lock placement:HACSurfaceLock error:&error], @"Lock still written: %@", error);
    CHECK([lock.stillFile isEqualToString:[HACLibrary stillFileForIdentifier:item.identifier placement:HACSurfaceLock]],
          @"Lock still has its own file: %@", lock.stillFile);
    CHECK([library updateItem:lock placement:HACSurfaceLock error:&error], @"Lock settings saved: %@", error);
    HCGBackgroundPreset *savedLock = [library presetForItem:item placement:HACSurfaceLock];
    HCGBackgroundPreset *savedHome = [library presetForItem:item placement:HACSurfaceHome];
    CHECK(savedLock.rotation == 180 && savedLock.stretch && savedLock.flipVertical && fabs(savedLock.speed - 0.75) < 1e-9,
          @"Lock keeps its own settings");
    CHECK(savedHome.rotation == 90 && !savedHome.stretch && fabs(savedHome.speed - 1.0) < 1e-9 &&
              ![savedHome.stillFile isEqualToString:savedLock.stillFile],
          @"Home keeps its own settings and still");
    CHECK(CGSizeEqualToSize(ImageSizeOfFile([savedLock stillURLInFolder:media]), item.mediaSize),
          @"the Lock still is the displayed frame (orientation metadata applied)");

    // Persisted, and readable by a 0.1 library reader (entries are v1 presets).
    [library reload];
    CHECK([library presetForItem:item placement:HACSurfaceLock].rotation == 180 &&
              [library presetForItem:item placement:HACSurfaceHome].rotation == 90,
          @"placements survive a reload");
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
                                                                     [[HACPreferences storeRoot] stringByAppendingPathComponent:@"library.json"]]
                                                         options:0
                                                           error:NULL];
    CHECK([root[@"formatVersion"] integerValue] == 2, @"library.json version 2");
    NSDictionary *entry = nil;
    for (NSDictionary *e in root[@"items"])
        if ([e[@"id"] isEqualToString:item.identifier]) entry = e;
    HCGBackgroundPreset *asOld = entry ? [HCGBackgroundPreset presetWithDictionary:entry error:NULL] : nil;
    CHECK(asOld && asOld.rotation == 90 && asOld.warnings.count == 0, @"a 0.1 reader sees the Home settings without warnings");
    CHECK([entry[@"placements"][@"lock-screen"][@"layout"][@"transform"][@"rotation"] integerValue] == 180,
          @"Lock settings stored under placements.lock-screen");

    // Assignments follow the placement.
    [HACPreferences setValue:@YES forKey:HACKeyLockEnabled];
    [HACPreferences setValue:@YES forKey:HACKeyHomeEnabled];
    [HACLibrary assignPreset:[library presetForItem:item placement:HACSurfaceHome] toSurface:HACSurfaceHome];
    [HACLibrary assignPreset:[library presetForItem:item placement:HACSurfaceLock] toSurface:HACSurfaceLock];
    HCGBackgroundPreset *edit = [library presetForItem:item placement:HACSurfaceLock];
    edit.rotation = 270;
    edit.name = @"Turned";
    CHECK([library updateItem:edit placement:HACSurfaceLock error:&error], @"Lock edit saved");
    HACSettings *s = [HACPreferences loadSettings];
    CHECK(s.lockPreset.rotation == 270 && s.homePreset.rotation == 90, @"each screen shows its own placement (%ld / %ld)",
          (long)s.lockPreset.rotation, (long)s.homePreset.rotation);
    CHECK([[library presetForItem:item placement:HACSurfaceHome].name isEqualToString:@"Turned"], @"the name is shared");

    // Export: one placement, and a pack with every placement.
    NSURL *exported = [library exportItem:item placement:HACSurfaceLock error:&error];
    HCGBackgroundPreset *lockExport = exported ? [HCGBackgroundPreset presetWithContentsOfURL:exported error:NULL] : nil;
    CHECK(lockExport.rotation == 270 && lockExport.stretch && lockExport.stillFile &&
              [fm fileExistsAtPath:[lockExport stillURLInFolder:exported].path],
          @"Lock Screen placement exported as .hcgbackground: %@", error);
    NSURL *pack = [library exportPackForItem:item error:&error];
    CHECK(pack != nil, @"pack exported: %@", error);
    NSDictionary *manifest = pack ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:
                                                                                  [pack URLByAppendingPathComponent:@"pack.json"]]
                                                                    options:0
                                                                      error:NULL]
                                  : nil;
    NSDictionary *placements = manifest[@"placements"];
    CHECK([manifest[@"format"] isEqual:@"com.hakmicapitalgroup.animation-pack"] && [manifest[@"formatVersion"] isEqual:@1] &&
              [manifest[@"defaultPlacement"] isEqual:@"app-background"] && placements[@"app-background"] &&
              placements[@"home-screen"] && placements[@"lock-screen"],
          @"pack manifest: %@", placements.allKeys);
    NSDictionary *presetJSON = pack ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:
                                                                                    [pack URLByAppendingPathComponent:@"preset.json"]]
                                                                      options:0
                                                                        error:NULL]
                                    : nil;
    CHECK([presetJSON isEqual:placements[@"app-background"][@"preset"]], @"preset.json = the default placement");
    CHECK([placements[@"lock-screen"][@"preset"][@"layout"][@"transform"][@"rotation"] isEqual:@270],
          @"the Lock Screen placement carries its transform");
    for (NSDictionary *f in [manifest[@"files"] arrayByAddingObject:manifest[@"media"] ?: @{}]) {
        NSURL *u = [pack URLByAppendingPathComponent:f[@"file"] ?: @"?"];
        NSDictionary *a = [fm attributesOfItemAtPath:u.path error:NULL];
        CHECK(a && a.fileSize == [f[@"bytes"] unsignedLongLongValue], @"pack file %@ listed with its size", f[@"file"]);
    }
#ifdef HAC_EXPORT_DIR
    // For the Mac compatibility check (validate_pack.py / hcgpack) after the run.
    NSURL *out = [NSURL fileURLWithPath:@HAC_EXPORT_DIR isDirectory:YES];
    [fm removeItemAtURL:out error:NULL];
    [fm createDirectoryAtURL:out withIntermediateDirectories:YES attributes:nil error:NULL];
    if (pack) [fm copyItemAtURL:pack toURL:[out URLByAppendingPathComponent:pack.lastPathComponent] error:NULL];
    if (exported) [fm copyItemAtURL:exported toURL:[out URLByAppendingPathComponent:exported.lastPathComponent] error:NULL];
#endif

    // Import: placements come back; damage and newer versions are refused.
    HCGBackgroundPreset *back = pack ? [library importPresetFolder:pack error:&error] : nil;
    CHECK(back && ![back.identifier isEqualToString:item.identifier], @"pack re-imported under a new id: %@", error);
    if (back) {
        CHECK([library item:back hasOwnSettingsForPlacement:HACSurfaceLock] &&
                  [library presetForItem:back placement:HACSurfaceLock].rotation == 270 &&
                  [library presetForItem:back placement:HACSurfaceHome].rotation == 90,
              @"both placements imported");
        NSString *lockStill = [HACLibrary stillFileForIdentifier:back.identifier placement:HACSurfaceLock];
        CHECK([fm fileExistsAtPath:[media URLByAppendingPathComponent:lockStill].path], @"Lock still imported");
        CHECK([library removeItem:back error:&error] && ![fm fileExistsAtPath:[media URLByAppendingPathComponent:lockStill].path],
              @"removing an item removes both stills");
    }
    if (pack) {
        NSURL *damaged = [gTemp URLByAppendingPathComponent:@"Damaged.hcgpack"];
        [fm removeItemAtURL:damaged error:NULL];
        [fm copyItemAtURL:pack toURL:damaged error:NULL];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:[damaged URLByAppendingPathComponent:@"still-lock-screen.jpg"].path];
        [h seekToEndOfFile];
        [h writeData:[@"x" dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
        CHECK([library importPresetFolder:damaged error:&error] == nil, @"damaged pack still refused: %@", error.localizedDescription);
        NSMutableDictionary *newer = [manifest mutableCopy];
        newer[@"formatVersion"] = @2;
        [[NSJSONSerialization dataWithJSONObject:newer options:0 error:NULL] writeToURL:[damaged URLByAppendingPathComponent:@"pack.json"]
                                                                              atomically:YES];
        CHECK([library importPresetFolder:damaged error:&error] == nil &&
                  [error.localizedDescription rangeOfString:@"newer"].location != NSNotFound,
              @"newer pack version refused: %@", error.localizedDescription);
    }

    // Back to following the Home Screen.
    CHECK([library removeOwnLockSettingsOfItem:item error:&error] && ![library item:item hasOwnSettingsForPlacement:HACSurfaceLock] &&
              [library presetForItem:item placement:HACSurfaceLock].rotation == 90,
          @"Use Home Screen Settings");
    CHECK(![fm fileExistsAtPath:[media URLByAppendingPathComponent:[HACLibrary stillFileForIdentifier:item.identifier
                                                                                            placement:HACSurfaceLock]]
                                    .path],
          @"the Lock still is deleted with its settings");
    CHECK([HACPreferences loadSettings].lockPreset.rotation == 90, @"the Lock Screen now shows the Home settings");

    // Backward compatibility: a 0.1 library.json (version 1, plain presets) loads.
    NSString *libraryPath = [[HACPreferences storeRoot] stringByAppendingPathComponent:@"library.json"];
    NSData *current = [NSData dataWithContentsOfFile:libraryPath];
    NSDictionary *legacy = @{@"formatVersion" : @1, @"items" : @[ [[library presetForItem:item placement:HACSurfaceHome] dictionaryRepresentation] ]};
    [[NSJSONSerialization dataWithJSONObject:legacy options:0 error:NULL] writeToFile:libraryPath atomically:YES];
    [library reload];
    CHECK(library.items.count == 1 && library.loadProblem.length == 0 &&
              ![library item:item hasOwnSettingsForPlacement:HACSurfaceLock],
          @"a 0.1 library loads; Lock follows Home");
    [current writeToFile:libraryPath atomically:YES];
    [library reload];

    // Presets that never used a transform are written exactly as before.
#ifdef HAC_EXAMPLE_PRESET
    NSURL *aurora = [NSURL fileURLWithPath:@HAC_EXAMPLE_PRESET];
    HCGBackgroundPreset *plain = [HCGBackgroundPreset presetWithContentsOfURL:aurora error:NULL];
    CHECK(plain && !plain.hasTransform && !plain.usesRegionInAllModes && !plain.dictionaryRepresentation[@"layout"][@"transform"] &&
              !plain.dictionaryRepresentation[@"media"][@"sourceRotation"],
          @"no transform key for presets that never used one");
    NSURL *skyline = [[aurora URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Skyline-Rotated.hcgbackground"];
    HCGBackgroundPreset *turned = [HCGBackgroundPreset presetWithContentsOfURL:skyline error:&error];
    CHECK(turned && turned.rotation == 90 && turned.flipHorizontal && !turned.flipVertical && turned.sourceRotation == 0 &&
              turned.warnings.count == 0 && CGSizeEqualToSize(turned.orientedMediaSize, CGSizeMake(1080, 3840)),
          @"Examples/Skyline-Rotated reads: %@ %@", error, turned.warnings);
    CHECK([[HCGBackgroundPreset presetWithDictionary:turned.dictionaryRepresentation error:NULL].dictionaryRepresentation
              isEqual:turned.dictionaryRepresentation],
          @"transform round trip");
#endif
}

#pragma mark - AI interface

static void TestAI(void) {
    id<HACAIGenerationProvider> provider = [HACAIGeneration provider];
    CHECK([provider isKindOfClass:[HACAIUnavailableProvider class]], @"this beta ships the unavailable provider");
    CHECK([provider currentAccess].state == HACAIAccessUnavailable && [provider currentAccess].explanation.length,
          @"access: not connected, explained");
    __block NSError *error = nil;
    __block BOOL called = NO;
    [provider generate:[[HACAIRequest alloc] init]
              progress:^(double f, NSString *p) {
              }
            completion:^(HACAIResult *result, NSError *e) {
                called = YES;
                error = e;
                CHECK(result == nil, @"no result without access");
            }];
    CHECK(called && error, @"generation refused");
    HACAIRequest *request = [[HACAIRequest alloc] init];
    CHECK([request validationProblem] != nil, @"empty prompt refused");
    request.prompt = @"slow aurora";
    request.pixelSize = CGSizeMake(1242, 2688);
    CHECK([request validationProblem] == nil, @"valid request");
    request.durationSeconds = 30;
    CHECK([request validationProblem] != nil, @"too long refused");
}

#pragma mark - Probe

static void TestProbe(void) {
    NSString *text = HACHierarchyProbeText(@{@"state" : @"active"});
    CHECK([text containsString:@"== Interfaces"] && [text containsString:@"== Placement ladder results"], @"probe sections");
    CHECK([text containsString:@"home / homeWindow:"] && [text containsString:@"lock / coverSheet:"], @"probe tries every placement");
    NSError *error = nil;
    NSString *path = HACWriteHierarchyProbe(@{}, &error);
    CHECK(path && [[NSFileManager defaultManager] fileExistsAtPath:path], @"probe written: %@", error);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        gTemp = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSString stringWithFormat:@"hac-runtime-%@", [NSUUID UUID].UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtURL:gTemp withIntermediateDirectories:YES attributes:nil error:NULL];
        [HACPreferences setStoreRootForTesting:[gTemp URLByAppendingPathComponent:@"store"].path];
        printf("HCG Animation Center %s runtime tests (store %s)\n", HAC_VERSION, [HACPreferences storeRoot].UTF8String);
        TestPresetFormat();
        TestPreferences();
        TestImport();
        TestRenderer();
        TestOrientation();
        TestPlacementsAndPacks();
        TestAI();
        TestProbe();
        [[NSFileManager defaultManager] removeItemAtURL:gTemp error:NULL];
        if (gFailures) {
            printf("%ld of %ld runtime checks FAILED\n", gFailures, gChecks);
            return 1;
        }
        printf("runtime tests: %ld checks passed\n", gChecks);
        return 0;
    }
}
