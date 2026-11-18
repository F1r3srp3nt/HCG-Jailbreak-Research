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
| `media.width`, `media.height` | yes | display size in pixels **after rotation**, 16–8192, else refused |
| `media.duration` | yes | seconds, > 0 and ≤ 600, at least 0.5, else refused |
| `media.origin` | no | `video`, `gif` or `ai` (informational) |
| `media.sha256` | no | lowercase hex of the file; importers verify it when present |
| `still.file` / `still.time` | no | safe file name; time is moved inside the trim range |
| `playback.trimStart` / `trimEnd` | no | seconds; `trimEnd` ≤ 0 means "to the end"; repaired to `0 ≤ start < end ≤ duration`, at least 0.5 s |
| `playback.loop` | no | default `true`; `false` = play once each time shown, hold the last frame |
| `playback.speed` | no | 0.25–2.0, default 1 (clamped) |
| `playback.muted` | no | always `true` in version 1 (`false` is read as `true` with a warning) |
| `layout.scaling` | no | `fill` (default), `fit`, `crop`; unknown → `fill` with a warning |
| `layout.crop` | no | normalised to the media frame, top-left origin; each side 0.1–1, kept inside the frame |
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

## A preset folder (`.hcgbackground`)

The exchange format: a folder named `<name>.hcgbackground` containing `preset.json`, the media file and the still.
Settings exports one (*Export Preset…*) and imports one (*Import › HCG Preset*); `+[HCGBackgroundPreset
presetWithContentsOfURL:]` reads a folder or a `preset.json`. Import checks the checksum, copies the files under a new
identifier and never reads outside the folder.

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
| Web renderer for HCG Store | **Separate integration, not built here.** Mapping for whoever builds it: fill → `object-fit: cover`; fit → `object-fit: contain` + background colour; crop → scale/translate from `hcgbg_layout` (or `object-view-box` where supported); `muted playsinline loop` (or `ended` → hold); `playbackRate`; trim with `currentTime` and a `timeupdate` guard (or a media fragment `#t=start,end`); `poster` = the still; `prefers-reduced-motion` → show the still. It must refuse a higher `formatVersion` the same way. |
