# Recording Backdrops + Custom Cursor — Design

Date: 2026-07-10
Status: approved pending user review

## Goal

Two OpenScreen-style upgrades for screen recordings:

1. **Backdrop export** — export a recording composited over a background
   (gradient preset or the user's macOS desktop wallpaper) with padding,
   rounded corners, and drop shadow, matching the screenshot Beautify look.
2. **Custom cursor** — optional recording mode that hides the real cursor and
   redraws a synthetic one with a smoothed path, user-chosen size (1×–3×),
   and color.

## Decisions (user-confirmed)

- Backdrop is applied **at export time** from the video preview window, never
  baked into the original recording. `nil` backdrop keeps today's lossless
  passthrough trim export.
- Backdrop choices: the 5 existing `BeautifyStyle` gradients + **11 bundled
  macOS-style wallpapers** + **Desktop Wallpaper** (current wallpaper via
  `NSWorkspace.desktopImageURL`, aspect-filled).
- Bundled wallpapers are curated from the Recordly repo
  (github.com/webadderallorg/Recordly, AGPLv3): sequoia-blue-orange,
  sequoia-blue, sonoma-clouds, sonoma-dark, sonoma-evening, sonoma-horizon,
  sonoma-light, tahoe-dark, tahoe-light, ventura-dark, ventura — 1600×900
  JPEGs, ~1 MB total, in `Sources/Snipr/Resources/Wallpapers/`. **User
  accepted the licensing gray area** (AGPL repo → MIT app; several images
  are Apple's own wallpapers) after it was flagged. Recordly attribution
  goes in the backdrop picker's footer and README credits.
- Custom cursor is **baked right after recording stops** (one automatic
  re-encode) so every file in the stack/history is complete and shareable.
  GIF export, trim, and backdrop export operate on the baked file unchanged.

## Components

### 1. `VideoBackdrop` (Models)

```swift
enum VideoBackdrop: Equatable {
    case gradient(BeautifyStyle)
    case bundled(String)   // resource name, e.g. "sonoma-horizon"
    case wallpaper         // user's desktop wallpaper, resolved at export
}
```

Bundled images load through the `SniprAssets` pattern (Bundle.main → 
Bundle.module), extended for `.jpg`. The app-bundle build script
(`script/build_and_run.sh`) currently copies only `Resources/*.png`; it
must also copy `Resources/Wallpapers/*.jpg`.

### 2. `VideoCompositor` (Support)

One AVFoundation compositor used by both features, built on
`AVMutableVideoComposition` + `AVVideoCompositionCoreAnimationTool`
(GPU-side, no per-frame CPU rendering):

- **Canvas**: `BeautifyRenderer.canvasGeometry` (existing pure math), rounded
  to even pixel dimensions for H.264.
- **Layer stack**: background layer (CAGradientLayer or aspect-filled
  wallpaper CALayer) → video layer inset by the padding with `cornerRadius`
  + shadow (mirrors `BeautifyRenderer.render` visuals) → optional cursor
  layer on top.
- **Cursor layer**: vector arrow `CGPath` (crisp at any scale), fill = user
  color, white/black outline for contrast; position driven by a
  `CAKeyframeAnimation` over the sampled path. Smoothing on = thinned
  samples + `.cubic` calculation mode; smoothing off = raw samples,
  `.linear`.
- **Export**: single `AVAssetExportSession` (high-quality preset) that takes
  the trim `timeRange` and the composition together. Audio passes through.
- Cursor-only bake (post-stop) is the same compositor with no padding/canvas
  growth and no backdrop.

### 3. Cursor sampling (Engines/RecordingEngine path)

- New preferences (see §4). When custom cursor is enabled and the recording
  mode is **region or full screen**, `SCStreamConfiguration.showsCursor =
  false` and a `CursorSampler` polls `NSEvent.mouseLocation` at 60 Hz on a
  main-actor timer, storing `(time, point)` in memory. No permissions, no
  sidecar files.
- Coordinate mapping: global screen points → recorded region rect → video
  pixel coordinates, using the recording's known region and scale factor.
  Samples outside the region simply render outside the frame (clipped).
- **Window recordings keep the system cursor** (v1 limitation — a moving
  window makes the mapping unreliable).
- On stop: recording finishes to a temp URL → compositor bakes the cursor →
  baked file becomes the stored capture item. If the bake fails, fall back
  to storing the raw recording and surface the error via toast.

### 4. Preferences (`SniprPreferences`)

```
recordingCustomCursor: Bool        (default false)
recordingCursorSmoothing: Bool     (default true)
recordingCursorScale: Double       (1.0–3.0, default 1.5)
recordingCursorColor: RGBA         (default white arrow, dark outline)
```

Settings → Recording tab gets a "Custom Cursor" group: toggle, smoothing
toggle, size slider, color well. Size/color rows disabled while the main
toggle is off, with a footnote that it applies to region/screen recordings.

### 5. UI — video preview (`VideoTrimView`)

- Background `Menu` + `Picker` identical in style to the screenshot editor's,
  grouped: None / Gradients (5) / Wallpapers (11 bundled) / Desktop
  Wallpaper. Footer line credits Recordly for the bundled set.
- Choosing a backdrop shows it behind the player as a live approximation
  (same trick as `PreviewWindowView`).
- Export button: backdrop selected → `VideoCompositor` export (`.mp4`-capable,
  default `.mov` as today); None → existing `TrimExporter` passthrough.

## Error handling

- Wallpaper unreadable at export → fall back to `.graphite` gradient, show a
  toast.
- Post-stop bake failure → keep raw recording, toast the error (recording is
  never lost).
- Export failures surface in the existing `exportError` label in the trim UI.

## Testing

- Pure-math unit tests: even-pixel canvas rounding; cursor coordinate mapping
  (screen → region → video pixels); sample thinning for smoothing.
- Existing `TrimExporter`/geometry tests unchanged.
- End-to-end: record region with custom cursor on → verify baked file plays
  with synthetic cursor; export with wallpaper backdrop → verify canvas,
  corners, audio, in the running app.

## Out of scope (deliberate)

- Padding/corner/shadow knobs (screenshot Beautify has none either).
- Custom cursor for window-mode recordings.
- Click-highlight rings on the synthetic cursor (the live ripple overlay
  feature already exists; can composite later if wanted).
- Cursor zoom/auto-pan effects (Screen Studio territory — separate feature).
