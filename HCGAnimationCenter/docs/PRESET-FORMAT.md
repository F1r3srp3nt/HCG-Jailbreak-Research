# HCG background preset format — version 1

Identifier `com.hakmicapitalgroup.background-preset`, `formatVersion` **1**. Machine-readable schema:
`HCGBackgroundKit/Schema/hcg-background-preset-v1.schema.json`. Reference implementation: `HCGBackgroundKit`
(`HCGBackgroundPreset`, `HCGBackgroundView`, C rules in `HCGBackgroundCore.c`). Example:
`HCGBackgroundKit/Examples/Aurora.hcgbackground/preset.json`.

`tests/test_schema.py` checks that the schema, the examples and the C constants agree; `tests/test_runtime.m` checks
the Objective-C reader against the same rules.

## A preset is data

It names one video file and says how to trim, scale, loop and play it, plus a still for when video can't play.
Nothing in it is executed. File names are **plain names inside the preset's own folder** — no `/`, `\`, `:`, no
leading `.` — so a preset can never point at another file on the device. `generator` is informational and is never
used for access decisions.

## Document

```json
{
  "format": "com.hakmicapitalgroup.background-preset",
  "formatVersion": 1,
  "id": "6F0B2C1E-4A55-4C8B-9E1D-2B7F1A3C9D40",
  "name": "Aurora",
  "created": "2026-11-18T12:00:00Z",
  "media":    { "kind": "video", "file": "media.mov", "width": 1080, "height": 1920, "duration": 12.0,
                "origin": "video", "sha256": "…64 hex…" },
  "still":    { "file": "still.jpg", "time": 1.5 },
  "playback": { "trimStart": 1.5, "trimEnd": 9.5, "loop": true, "speed": 0.75, "muted": true },
  "layout":   { "scaling": "crop", "crop": { "x": 0.1, "y": 0.05, "width": 0.8, "height": 0.8 },
                "backgroundColor": "#000000" },
  "generator": { "kind": "import", "source": "video" }
}
```

| Field | Required | Rules (reader behaviour) |
|---|---|---|
| `format` | yes | exactly the identifier, else **refused** |
| `formatVersion` | yes | whole number; **higher than the reader's → refused** with "update to use it"; never guessed |
| `id` | no | UUID; generated if absent; invalid → refused |
| `name` | no | ≤ 120 characters (longer is cut) |
| `media.kind` | no | `"video"` (the only kind in version 1) |
| `media.file` | yes | safe plain file name, else refused |
| `media.width`, `media.height` | yes | display size in pixels **after the file's orientation metadata**, 16–8192, else refused |
| `media.duration` | yes | seconds, > 0 and ≤ 600, at least 0.5, else refused |
| `media.origin` | no | `video`, `gif` or `ai` (informational) |
| `media.sha256` | no | lowercase hex of the file; importers verify it when present |
| `still.file` / `still.time` | no | safe file name; time is moved inside the trim range |
| `playback.trimStart` / `trimEnd` | no | seconds; `trimEnd` ≤ 0 means "to the end"; repaired to `0 ≤ start < end ≤ duration`, at least 0.5 s |
| `playback.loop` | no | default `true`; `false` = play once each time shown, hold the last frame |
| `playback.speed` | no | 0.25–2.0, default 1 (clamped) |
| `playback.muted` | no | always `true` in version 1 (`false` is read as `true` with a warning) |
| `layout.scaling` | no | `fill` (default), `fit`, `crop`; unknown → `fill` with a warning |
| `layout.crop` | no | normalised to the media frame (with `transform`: the transformed picture), top-left origin; each side 0.1–1, kept inside the frame |
| `layout.transform`, `media.sourceRotation` | no | kit 1.1 — see *Orientation and transformation* below |
| `layout.backgroundColor` | no | `#RRGGBB` behind `fit` |
| anything else | — | **ignored** (minor additions stay compatible) |

Readers **repair** what can be repaired and list each repair in `warnings`; they **refuse** (with an error code) what
can't be used: wrong format, newer major version, unsafe file names, missing or impossible media numbers.

### Layout (the same numbers on every renderer)

`hcgbg_layout(container, media, scaling, crop)` returns the rectangle the **whole** media frame is drawn in:

- **fill** – aspect-fill: covers the container, centred.
- **fit** – aspect-fit: inside the container, centred, background colour around it.
- **crop** – scaled so the crop rectangle covers the container, centred on the crop's centre, then moved the least
  distance needed so the frame still covers the container (never a gap at an edge).

The editor's zoom/centre ↔ crop conversions are `hcgbg_crop_from_zoom` / `hcgbg_zoom_for_crop`.

## Orientation and transformation (HCGBackgroundKit 1.1, a version 1 minor addition)

```json
"media":  { …, "width": 3840, "height": 1080, "sourceRotation": 0 },
"layout": { "scaling": "crop", "crop": { "x": 0.2, "y": 0.1, "width": 0.6, "height": 0.8 },
            "backgroundColor": "#000000",
            "transform": { "rotation": 90, "flipHorizontal": true, "flipVertical": false, "stretch": false } }
```

| Field | Rules |
|---|---|
| `layout.transform` | optional object. Present = the preset uses transformation; a non-object is ignored with a warning |
| `transform.rotation` | clockwise quarter turns **after** the source's orientation metadata: `0`, `90`, `180`, `270` (schema). Readers normalise anything else to the nearest quarter turn with a warning (450 → 90, −90 → 270) |
| `transform.flipHorizontal` / `flipVertical` | mirror left/right, top/bottom — in **screen** axes, after rotating |
| `transform.stretch` | fill the container exactly, ignoring the aspect ratio. Writers keep `scaling: "fill"` with it, so older readers show a fill |
| `media.sourceRotation` | informational: the quarter turn the file's own orientation metadata applies (recorded at import). `width`/`height` are already the size after it |

**Non-destructive.** The media file is never changed. Orientation metadata in the file (the video track's preferred
transform) is applied by AVFoundation for video and by the still generator for the still, so `media.width/height` and
the still are always the picture *as the source shows it*. The transform is applied on top, by the renderer, to the
still and the video alike (one Core Animation affine transform; no decoding or encoding).

**Region.** With a `transform` object, `crop` is the zoom / position **region in every mode**, normalised to the
*transformed* picture (top-left origin): *fit* shows the region inside the container (bars in `backgroundColor`),
*stretch* maps the region exactly onto the container, *crop* / *fill* are as in 1.0 on the transformed size. Without
the object, 1.0 rules apply unchanged (fit and fill ignore `crop`).

**Layout** is `hcgbg_layout_transformed(container, media, scaling, crop, transform)` → the transformed picture's
frame, the layer's untransformed bounds (sides swapped for 90° / 270°) and a 2×2 matrix applied about the frame's
centre: rotate clockwise (UIKit axes, y down), then flip. With an identity transform and no region it equals
`hcgbg_layout()` exactly. Editor conversions: `hcgbg_region_from_zoom` / `hcgbg_zoom_for_region`.

**Written only when used.** Writers emit `transform` only when the preset has one (read from a document, or set by an
editor) or it is not the identity, and `sourceRotation` only when known — a preset that never used them is
byte-identical to 1.0 output. Example: `Examples/Skyline-Rotated.hcgbackground` (ultrawide turned for portrait).

| Reader | What it shows for a preset with `transform` |
|---|---|
| HCGBackgroundKit ≥ 1.1 (HCG Animation Center ≥ 0.2) | the transformation |
| HCGBackgroundKit 1.0, HCG Animation Center 0.1, HCG Animation Center for Mac (vendored 1.0 core) | the clip upright, unflipped; `stretch` as fill; region ignored for fit. Never refused, never a crash |

Because the change is a minor addition, `formatVersion` stays **1**; the 1.0 schema still accepts every 1.1 preset
(`tests/fixtures/hcg-background-preset-v1.0.schema.json`, checked by `tests/test_schema.py`).

## A preset folder (`.hcgbackground`)

The exchange format: a folder named `<name>.hcgbackground` containing `preset.json`, the media file and the still.
Settings exports one placement (*Export… › Home Screen / Lock Screen Preset*) and imports one (*Import › HCG Preset or
Pack*); `+[HCGBackgroundPreset
presetWithContentsOfURL:]` reads a folder or a `preset.json`. Import checks the checksum, copies the files under a new
identifier and never reads outside the folder.

## Placements and animation packs (`.hcgpack`)

HCG Animation Center keeps settings **per placement**: `home-screen` and `lock-screen`. Each placement is a complete
preset of the same clip (its own trim, loop, speed, still, framing and transformation; name and media shared). The Lock
Screen follows the Home Screen until it is edited. In `library.json` (version 2) each entry is still a plain version 1
preset (the Home Screen) with `"placements": {"lock-screen": preset}` added — 0.1 reads it and keeps the Home settings.

*Export… › Animation Pack* writes an **HCG animation pack v1** (the format of HCG Animation Center for Mac,
`com.hakmicapitalgroup.animation-pack`): `pack.json`, `preset.json`, `media.*`, `poster.jpg` and, if the Lock Screen
has its own settings, `still-lock-screen.jpg`, every file with its size and SHA-256. Placements: `app-background`
(the default, = Home Screen; a placement every version 1 reader knows), `home-screen` and `lock-screen` (minor
additions: version 1 readers ignore them with a note). `preset.json` equals the default placement. Importing a pack
verifies sizes and checksums, refuses a newer `formatVersion`, and maps `home-screen` (else the default placement,
else the first known one) to the Home Screen and `lock-screen` to the Lock Screen.

## Versioning rules

- **Minor additions** (new optional keys) keep `formatVersion: 1`. Old readers ignore them; the new keys must have a
  safe default.
- **Breaking changes** (a required key, a changed meaning) increase `formatVersion`. Old readers refuse such a preset
  and say an update is needed; they never play it wrongly.
- Writers emit the canonical form (`-dictionaryRepresentation`): property-list safe, so it can live in preferences.

## Renderers

| Renderer | Status |
|---|---|
| `HCGBackgroundView` (UIKit, AVFoundation) | Implemented: SpringBoard (this tweak), Settings preview, HCG apps via HCGBackgroundKit |
| Web renderer for HCG Store | **Separate integration, not built here.** Mapping for whoever builds it: fill → `object-fit: cover`; fit → `object-fit: contain` + background colour; crop → scale/translate from `hcgbg_layout` (or `object-view-box` where supported); `muted playsinline loop` (or `ended` → hold); `playbackRate`; trim with `currentTime` and a `timeupdate` guard (or a media fragment `#t=start,end`); `poster` = the still; `prefers-reduced-motion` → show the still. Transform (1.1): size the element to the layout's `bounds`, centre it on the frame's centre and apply `transform: matrix(a, b, c, d, 0, 0)` from `hcgbg_layout_transformed`; browsers already honour a file's rotation metadata, like AVFoundation. It must refuse a higher `formatVersion` the same way. |
