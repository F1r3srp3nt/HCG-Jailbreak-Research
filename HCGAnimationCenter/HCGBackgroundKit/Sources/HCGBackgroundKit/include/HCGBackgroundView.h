//
//  HCGBackgroundView.h
//  HCGBackgroundKit — Hakmi Capital Group
//
//  Renders one HCG background preset: the static fallback image, and above it
//  the trimmed, looped, muted video at the preset's speed and scaling. The
//  same class draws the background in SpringBoard (HCG Animation Center), in
//  the Settings preview, and in any HCG app that opts in.
//
//  Behaviour that callers can rely on:
//    - never interactive (no hit-testing) and hidden from accessibility;
//    - never plays sound: only the video track is played, and muted;
//    - one video decoder at most, created only for Paused / Playing and freed
//      by -releasePlayer, Display None or a nil preset;
//    - if the media is missing, corrupt or fails while playing, the view keeps
//      showing the still (or nothing) and reports it once to the delegate.
//  All methods must be called on the main thread.
//

#import <UIKit/UIKit.h>

#import "HCGBackgroundPreset.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HCGBackgroundDisplay) {
    HCGBackgroundDisplayNone = 0,    ///< draw nothing (what's behind shows through)
    HCGBackgroundDisplayStill = 1,   ///< the still only; no decoder
    HCGBackgroundDisplayPaused = 2,  ///< the video's current frame, not advancing
    HCGBackgroundDisplayPlaying = 3, ///< the video plays
};

@class HCGBackgroundView;

@protocol HCGBackgroundViewDelegate <NSObject>
@optional
/// The video can't be played (HCGBackgroundErrorMediaUnplayable). Called once
/// per preset; the view falls back to the still.
- (void)backgroundView:(HCGBackgroundView *)view didFailWithError:(NSError *)error;
/// The first video frame is on screen.
- (void)backgroundViewDidBecomeReady:(HCGBackgroundView *)view;
/// A clip that does not loop reached its end and holds its last frame.
- (void)backgroundViewDidFinishPlayingOnce:(HCGBackgroundView *)view;
@end

@interface HCGBackgroundView : UIView

@property (nonatomic, weak, nullable) id<HCGBackgroundViewDelegate> delegate;
@property (nonatomic, readonly, nullable) HCGBackgroundPreset *preset;
@property (nonatomic, readonly, nullable) NSURL *folder;

/// What to draw. Changing it never blocks; video loads asynchronously.
@property (nonatomic) HCGBackgroundDisplay display;

/// Largest decode size in pixels (0 = what the layout needs at the screen's
/// scale, capped at the media size). Limits decoder memory.
@property (nonatomic) CGSize maximumDecodeSize;

@property (nonatomic, readonly) BOOL mediaFailed;     ///< the video failed for this preset
@property (nonatomic, readonly) BOOL stillLoaded;     ///< the still image is decoded and shown below the video
@property (nonatomic, readonly) BOOL playerActive;    ///< a decoder exists
@property (nonatomic, readonly) BOOL videoVisible;    ///< a video frame is on screen
@property (nonatomic, readonly, copy) NSString *stateDescription;

/// Sets (or clears) the preset. Files are resolved inside `folder`. A
/// different preset, or the same one with different numbers, reloads.
- (void)setPreset:(nullable HCGBackgroundPreset *)preset folder:(nullable NSURL *)folder;

/// Frees the video decoder; the still stays. The next Paused / Playing
/// restarts the clip from its start.
- (void)releasePlayer;

/// Restarts the trimmed clip from its start (keeps the current display).
- (void)restartClip;

/// For tests: the frame the media is laid out in (view coordinates).
@property (nonatomic, readonly) CGRect mediaFrame;

@end

NS_ASSUME_NONNULL_END
