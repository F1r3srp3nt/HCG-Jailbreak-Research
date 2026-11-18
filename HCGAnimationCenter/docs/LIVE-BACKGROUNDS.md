# What counts as a “live background” (0.1.0~beta1)

A **live background** in HCG Animation Center is: **one muted video clip, looped (or played once), drawn behind the
Home Screen icons or the Lock Screen clock, with a still image as its fallback.** It is stored as an HCG background
preset (format version 1, `PRESET-FORMAT.md`).

## Supported

| Input | What happens at import | Limits |
|---|---|---|
| Video: `.mov`, `.mp4`, `.m4v` with H.264 or HEVC video (any codec AVFoundation can decode on the phone) | The **video track only** is copied (passthrough, no quality loss). Rotation metadata is kept. If a side is larger than 2688 px, or passthrough fails, it is converted to H.264 at 1920 × 1080 (aspect kept) | ≤ 512 MB, ≥ 0.5 s, ≤ 10 min, 16–8192 px per side |
| Animated GIF (2 or more frames) | Converted once to an H.264 `.mp4`: frames drawn on black (GIF transparency becomes black), longer side ≤ 1080 px, even dimensions, browser frame timing (a delay of 10 ms or less, or none, plays as 100 ms), repeated until it lasts at least 1 s | ≤ 3000 frames, ≤ 10 min |

Every item also gets a **still** (JPEG frame at the chosen time; the static fallback) and a **thumbnail**.

Why convert GIFs: a GIF decoded frame by frame in SpringBoard holds every frame as a bitmap (a 100-frame 1080 × 1920
GIF is about 800 MB). As video it uses the hardware decoder and a few buffers.

Why drop audio: a background must never play sound, take the audio session, or interrupt music. The stored file has
no audio track, and the player is also muted and plays a video-only composition (`HCGBackgroundView`).

## Not supported in this beta (refused at import, with the reason shown)

| Input | Reason shown | Note |
|---|---|---|
| Still images (JPEG, PNG, HEIC, single-frame GIF) | “Live backgrounds need a video or an animated GIF” | A still is only used as the fallback of a video |
| **Live Photos** | “Live Photos aren't supported as live backgrounds yet … save it as a video in Photos first” | See the investigation below |
| Damaged, truncated, empty or unreadable files | the AVFoundation / ImageIO reason | Nothing is added; staging is cleaned |
| Files over the limits above | the limit | |
| Streams, URLs, DRM-protected video | never offered (local files only) | |

Not features of 0.1.0~beta1: sound, interaction (tap to play), parallax / perspective zoom, per-page or
time-of-day backgrounds, landscape-specific layout (the background is laid out for the portrait screen), HDR tone
mapping control (iOS decides).

## Live Photos: investigated separately, not assumed to be video

A Live Photo is **not** a video file. It is a pair: a still (HEIC/JPEG) and a short `.mov` (≈ 3 s), linked by a
content identifier, plus metadata saying which frame is the “key photo”. iOS treats it differently from video
everywhere:

| Question | What we know | Status |
|---|---|---|
| What does the photo picker hand over? | `PHPickerViewController` can return the pair as a `PHLivePhoto` object, or (with the images filter) only the still. Extracting the `.mov` needs `PHAssetResource` APIs on the `PHLivePhoto`; whether that works **without** full Photos library access from the Settings app is not established | Open — needs a device test |
| How does iOS play them as wallpaper? | Historically (iOS ≤ 15) a Live Photo wallpaper played on long-press on the Lock Screen, not continuously; iOS 16's PosterBoard changed Lock Screen wallpapers; iOS 17 brought back a Live Photo wallpaper motion that plays briefly when waking | Behaviour differs by iOS version; not continuous looping |
| Would looping the `.mov` look right? | The clip is short and starts / ends on arbitrary frames; looping it shows a visible jump. The key photo is usually mid-clip | Likely needs a “play once on wake, settle on the key photo” mode, not a loop |
| Rotation, HDR, frame rate | Same as video (handled) | — |

**Decision for 0.1.0~beta1:** Live Photos are detected (the `com.apple.live-photo` type) and refused with an
explanation and a workaround (Photos › Share › Save as Video, then import the video — a normal, supported path).
Nothing is extracted silently.

**Investigation plan (for 0.2):**
1. On the test device, from Settings: pick a Live Photo with `PHPickerFilter.livePhotosFilter`, load `PHLivePhoto`,
   call `+[PHAssetResource assetResourcesForLivePhoto:]` and `-[PHAssetResourceManager writeDataForAssetResource:…]`,
   record whether it succeeds without a Photos permission prompt.
2. Read the key-photo time from the `.mov` metadata (`com.apple.quicktime.still-image-time`).
3. Prototype a mode `playback.liveOnce` (play once when the surface appears, end on the key frame) behind a new
   **minor** format field (version 1 readers ignore it and loop as usual).
4. Decide from a device recording whether it reads as a Live Photo or as a short glitchy loop.

## How playback adapts (all surfaces)

| Situation | Shown |
|---|---|
| Surface on screen | the video plays |
| Hidden (app open, phone locked for Home, unlocked for Lock, screen off) | paused on its frame; after 8 s hidden the decoder is freed (the still stays) |
| Reduce Motion on | the still (setting: or keep playing) |
| Low Power Mode on | the still (settings: keep playing, or your system wallpaper) |
| Device hot (thermal state serious or critical) | the still |
| Video missing or fails to play | the still; with no still, your system wallpaper |
| Off, faulted, auto-disabled, kill switch, uninstalled | your system wallpaper |
