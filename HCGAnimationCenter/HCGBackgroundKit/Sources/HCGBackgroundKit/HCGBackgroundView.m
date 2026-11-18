//
//  HCGBackgroundView.m
//  HCGBackgroundKit — Hakmi Capital Group
//
//  Layer tree (all frames set without implicit animation):
//
//    self.layer                 background colour (shows behind "fit")
//    └─ _clip                   bounds, masksToBounds
//       ├─ _stillLayer          the static fallback, laid out like the video
//       └─ _playerLayer         the video; hidden until its first frame is ready
//

#import "HCGBackgroundView.h"
#import "HCGBackgroundCore.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

static void *const kKVOContext = (void *)&kKVOContext;

@implementation HCGBackgroundView {
    HCGBackgroundPreset *_preset;
    NSURL *_folder;
    NSData *_signature;

    CALayer *_clip;
    CALayer *_stillLayer;
    AVPlayerLayer *_playerLayer;

    AVPlayer *_player;
    AVPlayerLooper *_looper;
    AVPlayerItem *_item; // the non-looping item, or the looper's template
    NSMutableArray<NSArray *> *_observations; // @[object, keyPath]
    NSMutableArray<id> *_notificationTokens;
    NSUInteger _playerGeneration;
    NSUInteger _stillGeneration;
    BOOL _loading;
    BOOL _failReported;
    BOOL _finishedOnce;
    NSString *_failure;
    CGSize _appliedDecodeSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) [self setUp];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self setUp];
    return self;
}

- (void)setUp {
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.backgroundColor = UIColor.clearColor;
    self.hidden = YES;
    _observations = [NSMutableArray array];
    _notificationTokens = [NSMutableArray array];
    _clip = [CALayer layer];
    _clip.masksToBounds = YES;
    _stillLayer = [CALayer layer];
    _stillLayer.contentsGravity = kCAGravityResize;
    _playerLayer = [AVPlayerLayer layer];
    _playerLayer.videoGravity = AVLayerVideoGravityResize; // the frame already has the media's aspect
    _playerLayer.hidden = YES;
    [_clip addSublayer:_stillLayer];
    [_clip addSublayer:_playerLayer];
    [self.layer addSublayer:_clip];
}

- (void)dealloc {
    [self teardownPlayer];
}

#pragma mark Never interactive

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}

#pragma mark Preset

- (HCGBackgroundPreset *)preset {
    return _preset;
}

- (NSURL *)folder {
    return _folder;
}

/// What forces a reload: the files and the clip. Layout (scaling, crop,
/// colour) and speed are applied in place, so editing them never flickers.
static NSData *MediaSignature(HCGBackgroundPreset *preset, NSURL *folder) {
    if (!preset) return nil;
    NSDictionary *d = @{
        @"folder" : folder.path ?: @"",
        @"media" : preset.mediaFile ?: @"",
        @"still" : preset.stillFile ?: @"",
        @"stillTime" : @(preset.stillTime),
        @"trimStart" : @(preset.trimStart),
        @"trimEnd" : @(preset.trimEnd),
        @"loops" : @(preset.loops),
        @"width" : @(preset.mediaSize.width),
        @"height" : @(preset.mediaSize.height),
    };
    return [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:NULL];
}

- (void)applyBackgroundColour {
    double r = 0, g = 0, b = 0;
    hcgbg_parse_hex_colour(_preset.backgroundColor.UTF8String, &r, &g, &b);
    self.layer.backgroundColor = _preset ? [UIColor colorWithRed:r green:g blue:b alpha:1].CGColor : nil;
}

- (void)setPreset:(HCGBackgroundPreset *)preset folder:(NSURL *)folder {
    preset = [preset copy]; // never modify the caller's preset
    [preset sanitizeWithError:NULL];
    NSData *signature = MediaSignature(preset, folder);
    if (signature && [signature isEqualToData:_signature]) {
        // Same media and clip: update layout and speed in place.
        _preset = [preset copy];
        [self applyBackgroundColour];
        [self setNeedsLayout];
        [self layoutIfNeeded];
        if (_player && _display == HCGBackgroundDisplayPlaying) [_player setRate:(float)_preset.speed];
        return;
    }
    if (!signature && !_signature && !_preset) return;
    [self teardownPlayer];
    _preset = [preset copy];
    _folder = [folder copy];
    _signature = signature;
    _mediaFailed = NO;
    _failReported = NO;
    _failure = nil;
    _finishedOnce = NO;
    _stillLoaded = NO;
    _stillLayer.contents = nil;
    [self applyBackgroundColour];
    [self loadStill];
    [self setNeedsLayout];
    [self apply];
}

#pragma mark Display

- (void)setDisplay:(HCGBackgroundDisplay)display {
    if (display < HCGBackgroundDisplayNone || display > HCGBackgroundDisplayPlaying) display = HCGBackgroundDisplayNone;
    if (display == _display) return;
    _display = display;
    [self apply];
}

- (void)apply {
    BOOL wantsVideo = (_display == HCGBackgroundDisplayPaused || _display == HCGBackgroundDisplayPlaying);
    self.hidden = (_display == HCGBackgroundDisplayNone || !_preset);
    if (!_preset || !wantsVideo || _mediaFailed) {
        [self teardownPlayer];
        return;
    }
    if (_player) {
        [self applyRate];
    } else {
        [self loadPlayer];
    }
}

- (void)applyRate {
    if (!_player) return;
    if (_display == HCGBackgroundDisplayPlaying) {
        if (!_preset.loops && _finishedOnce) {
            // A clip that plays once starts again each time it is shown.
            _finishedOnce = NO;
            [_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
        [_player playImmediatelyAtRate:(float)_preset.speed];
    } else {
        [_player pause];
    }
}

- (void)restartClip {
    if (!_player) return;
    _finishedOnce = NO;
    [_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self applyRate];
}

- (void)releasePlayer {
    [self teardownPlayer];
}

#pragma mark Still

- (void)loadStill {
    NSUInteger generation = ++_stillGeneration;
    NSURL *url = [_preset stillURLInFolder:_folder];
    if (!url) return;
    CGFloat maxPixel = [self decodeLimit];
    __weak HCGBackgroundView *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageRef image = NULL;
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (source) {
            NSDictionary *options = @{
                (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
                (__bridge id)kCGImageSourceCreateThumbnailWithTransform : @YES,
                (__bridge id)kCGImageSourceShouldCacheImmediately : @YES,
                (__bridge id)kCGImageSourceThumbnailMaxPixelSize : @(maxPixel),
            };
            if (CGImageSourceGetCount(source) > 0)
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
            CFRelease(source);
        }
        id contents = image ? CFBridgingRelease(image) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            HCGBackgroundView *view = weakSelf;
            if (!view || generation != view->_stillGeneration) return;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            view->_stillLayer.contents = contents;
            [CATransaction commit];
            view->_stillLoaded = contents != nil;
        });
    });
}

#pragma mark Player

- (CGFloat)screenScale {
    UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
    return screen.scale > 0 ? screen.scale : 2;
}

/// Longest side, in pixels, worth decoding for the still.
- (CGFloat)decodeLimit {
    CGSize screen = UIScreen.mainScreen.nativeBounds.size;
    CGFloat limit = MAX(screen.width, screen.height);
    if (_maximumDecodeSize.width > 0 && _maximumDecodeSize.height > 0)
        limit = MAX(_maximumDecodeSize.width, _maximumDecodeSize.height);
    return MAX(limit, 256);
}

- (CGSize)decodeSize {
    if (_maximumDecodeSize.width > 0 && _maximumDecodeSize.height > 0) return _maximumDecodeSize;
    CGRect frame = self.mediaFrame;
    CGFloat scale = [self screenScale];
    CGSize media = _preset.mediaSize;
    CGSize size = CGSizeMake(MIN(frame.size.width * scale, media.width), MIN(frame.size.height * scale, media.height));
    if (size.width < 1 || size.height < 1) size = UIScreen.mainScreen.nativeBounds.size;
    return size;
}

- (void)loadPlayer {
    if (_player || _loading || !_preset) return;
    NSURL *url = [_preset mediaURLInFolder:_folder];
    BOOL isDirectory = NO;
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory] || isDirectory) {
        [self failWithReason:@"The video file is missing."];
        return;
    }
    _loading = YES;
    NSUInteger generation = ++_playerGeneration;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
    __weak HCGBackgroundView *weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:@[ @"playable", @"tracks", @"duration" ]
                         completionHandler:^{
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 [weakSelf asset:asset loadedForGeneration:generation];
                             });
                         }];
}

- (void)asset:(AVURLAsset *)asset loadedForGeneration:(NSUInteger)generation {
    if (generation != _playerGeneration) return; // released or replaced meanwhile
    _loading = NO;
    for (NSString *key in @[ @"playable", @"tracks", @"duration" ]) {
        NSError *error = nil;
        if ([asset statusOfValueForKey:key error:&error] != AVKeyValueStatusLoaded) {
            [self failWithReason:[NSString stringWithFormat:@"The video could not be read (%@).",
                                                            error.localizedDescription ?: key]];
            return;
        }
    }
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!asset.playable || !track) {
        [self failWithReason:@"The file has no playable video track."];
        return;
    }
    CMTimeRange available = track.timeRange;
    CMTime start = CMTimeMakeWithSeconds(_preset.trimStart, 600);
    CMTime end = CMTimeMakeWithSeconds(_preset.trimEnd, 600);
    CMTimeRange range = CMTimeRangeGetIntersection(CMTimeRangeFromTimeToTime(start, end), available);
    if (CMTIMERANGE_IS_INVALID(range) || CMTIMERANGE_IS_EMPTY(range) ||
        CMTimeGetSeconds(range.duration) < HCGBG_MIN_CLIP_SECONDS / 2) {
        [self failWithReason:@"The trimmed range is outside the video."];
        return;
    }
    // Video track only: a background never plays sound and never takes the audio session.
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *video = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    if (!video || ![video insertTimeRange:range ofTrack:track atTime:kCMTimeZero error:&error]) {
        [self failWithReason:[NSString stringWithFormat:@"The video could not be prepared (%@).",
                                                        error.localizedDescription ?: @"composition"]];
        return;
    }
    video.preferredTransform = track.preferredTransform;

    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:composition];
    item.preferredForwardBufferDuration = 1.0;
    _appliedDecodeSize = [self decodeSize];
    item.preferredMaximumResolution = _appliedDecodeSize;
    _item = item;

    if (_preset.loops) {
        AVQueuePlayer *queue = [AVQueuePlayer queuePlayerWithItems:@[]];
        _looper = [AVPlayerLooper playerLooperWithPlayer:queue templateItem:item];
        _player = queue;
        [self observe:_looper keyPath:@"status"];
    } else {
        _player = [AVPlayer playerWithPlayerItem:item];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        __weak HCGBackgroundView *weakSelf = self;
        [_notificationTokens addObject:[[NSNotificationCenter defaultCenter]
                                           addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                       object:item
                                                        queue:[NSOperationQueue mainQueue]
                                                   usingBlock:^(NSNotification *note) {
                                                       [weakSelf finishedOnce];
                                                   }]];
    }
    _player.muted = YES;
    _player.allowsExternalPlayback = NO;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    _player.automaticallyWaitsToMinimizeStalling = NO;
    if (@available(iOS 15.0, *))
        _player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyPauses;
    [self observe:_player keyPath:@"status"];
    [self observe:_player keyPath:@"currentItem.status"];
    __weak HCGBackgroundView *weakSelf = self;
    [_notificationTokens addObject:[[NSNotificationCenter defaultCenter]
                                       addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                                                   object:nil
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:^(NSNotification *note) {
                                                   HCGBackgroundView *view = weakSelf;
                                                   if (view && note.object && note.object == view->_player.currentItem) {
                                                       NSError *e = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
                                                       [view failWithReason:[NSString stringWithFormat:
                                                                                          @"Playback failed (%@).",
                                                                                          e.localizedDescription
                                                                                              ?: @"decoder"]];
                                                   }
                                               }]];
    _playerLayer.player = _player;
    [self observe:_playerLayer keyPath:@"readyForDisplay"];
    [self applyRate];
}

- (void)observe:(id)object keyPath:(NSString *)keyPath {
    [object addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionInitial context:kKVOContext];
    [_observations addObject:@[ object, keyPath ]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != kKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (![NSThread isMainThread]) {
        __weak HCGBackgroundView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf checkPlayback];
        });
        return;
    }
    [self checkPlayback];
}

- (void)checkPlayback {
    if (!_player) return;
    if (_player.status == AVPlayerStatusFailed) {
        [self failWithReason:[NSString stringWithFormat:@"The player failed (%@).",
                                                        _player.error.localizedDescription ?: @"unknown"]];
        return;
    }
    if (_player.currentItem.status == AVPlayerItemStatusFailed) {
        [self failWithReason:[NSString stringWithFormat:@"The video failed to play (%@).",
                                                        _player.currentItem.error.localizedDescription ?: @"decoder"]];
        return;
    }
    if (_looper && _looper.status == AVPlayerLooperStatusFailed) {
        [self failWithReason:[NSString stringWithFormat:@"Looping failed (%@).",
                                                        _looper.error.localizedDescription ?: @"unknown"]];
        return;
    }
    BOOL ready = _playerLayer.readyForDisplay;
    if (ready != _videoVisible) {
        _videoVisible = ready;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _playerLayer.hidden = !ready;
        [CATransaction commit];
        if (ready && [_delegate respondsToSelector:@selector(backgroundViewDidBecomeReady:)])
            [_delegate backgroundViewDidBecomeReady:self];
    }
}

- (void)finishedOnce {
    _finishedOnce = YES;
    if ([_delegate respondsToSelector:@selector(backgroundViewDidFinishPlayingOnce:)])
        [_delegate backgroundViewDidFinishPlayingOnce:self];
}

- (void)failWithReason:(NSString *)reason {
    _loading = NO;
    _mediaFailed = YES;
    _failure = reason;
    [self teardownPlayer];
    if (_failReported) return;
    _failReported = YES;
    if ([_delegate respondsToSelector:@selector(backgroundView:didFailWithError:)]) {
        NSError *error = [NSError errorWithDomain:HCGBackgroundErrorDomain
                                             code:HCGBackgroundErrorMediaUnplayable
                                         userInfo:@{NSLocalizedDescriptionKey : reason ?: @"The video can't be played."}];
        [_delegate backgroundView:self didFailWithError:error];
    }
}

- (void)teardownPlayer {
    _playerGeneration++; // cancels an asset load in flight
    _loading = NO;
    for (NSArray *pair in _observations) {
        @try {
            [pair[0] removeObserver:self forKeyPath:pair[1] context:kKVOContext];
        } @catch (NSException *exception) {
            // Already removed; nothing to do.
        }
    }
    [_observations removeAllObjects];
    for (id token in _notificationTokens) [[NSNotificationCenter defaultCenter] removeObserver:token];
    [_notificationTokens removeAllObjects];
    [_looper disableLooping];
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    _looper = nil;
    _player = nil;
    _item = nil;
    _playerLayer.player = nil;
    _playerLayer.hidden = YES;
    _videoVisible = NO;
}

- (BOOL)playerActive {
    return _player != nil || _loading;
}

#pragma mark Layout

- (CGRect)mediaFrame {
    if (!_preset) return self.bounds;
    CGSize b = self.bounds.size;
    CGSize m = _preset.mediaSize;
    CGRect c = _preset.crop;
    HCGBGRect r = hcgbg_layout((HCGBGSize){b.width, b.height}, (HCGBGSize){m.width, m.height},
                               (HCGBGScaling)_preset.scaling,
                               (HCGBGRect){c.origin.x, c.origin.y, c.size.width, c.size.height});
    return CGRectMake(r.x, r.y, r.width, r.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _clip.frame = self.bounds;
    CGRect frame = self.mediaFrame;
    _stillLayer.frame = frame;
    _playerLayer.frame = frame;
    [CATransaction commit];
    CGSize decode = [self decodeSize];
    if (_item && !CGSizeEqualToSize(decode, _appliedDecodeSize)) {
        _appliedDecodeSize = decode;
        _player.currentItem.preferredMaximumResolution = decode;
    }
}

#pragma mark Description

- (NSString *)stateDescription {
    if (!_preset) return @"No preset";
    if (_display == HCGBackgroundDisplayNone) return @"Hidden";
    NSString *still = _stillLoaded ? @"still" : @"no still";
    if (_mediaFailed) return [NSString stringWithFormat:@"Video unavailable (%@): %@", still, _failure ?: @""];
    switch (_display) {
        case HCGBackgroundDisplayStill:
            return [NSString stringWithFormat:@"Still (%@)", still];
        case HCGBackgroundDisplayPaused:
            return _player ? @"Paused" : (_loading ? @"Loading" : @"Paused (no decoder)");
        case HCGBackgroundDisplayPlaying:
            if (_loading || !_player) return @"Loading";
            return [NSString stringWithFormat:@"Playing %.2g× %@%@", _preset.speed, _preset.loops ? @"looping" : @"once",
                                              _videoVisible ? @"" : @" (waiting for first frame)"];
        default:
            return @"Hidden";
    }
}

@end
