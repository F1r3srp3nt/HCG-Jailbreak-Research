//
//  test_runtime.m
//  HCG Animation Center — runtime tests for the Objective-C layer, run in the
//  iOS Simulator by CI (scripts/run-simulator-tests.sh). No SpringBoard: this
//  checks the preset format, preferences, the real importer on generated
//  media (good, damaged and unsupported), the renderer's player lifecycle and
//  the AI interface's rules. It does NOT show that anything works inside
//  SpringBoard on a device.
//

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "HACAIGeneration.h"
#import "HACLibrary.h"
#import "HACMediaImporter.h"
#import "HACPreferences.h"
#import "HACProbe.h"
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
