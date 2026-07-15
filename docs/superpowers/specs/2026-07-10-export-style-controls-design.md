# Export Style Controls + Preview Letterbox Fix — Design

Date: 2026-07-10
Status: approved (user: "goot")
Builds on: 2026-07-10-recording-backdrop-and-cursor-design.md (branch feature/recording-backdrop-cursor)

## Goal

OpenScreen-style export configurability for the video preview, plus a fix for
the preview-only black letterbox bars the user reported.

## Bug fix: preview letterboxing

`AVPlayerView` fills the preview pane and paints black bars where the video
doesn't match the pane's aspect, hiding the backdrop preview. Fix: when a
backdrop is selected, constrain the player with
`.aspectRatio(CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight), contentMode: .fit)`
so the backdrop fills the pane and the video floats on it. (`CaptureItem`
already carries `pixelWidth`/`pixelHeight`.) No export change — exports were
already correct.

## New model: `ExportStyle`

```swift
struct ExportStyle: Codable, Equatable, Sendable {
    var paddingFraction: Double = 0.08   // 0...0.30 (today's default)
    var cornerRadius: Double = 16        // 0...40, in points at 1x (scaled to pixels)
    var shadowOpacity: Double = 0.45     // 0...1 (today's default)
    var aspect: CanvasAspect = .auto
}

enum CanvasAspect: String, Codable, CaseIterable, Sendable {
    case auto        // canvas hugs video + padding (today's behavior)
    case widescreen  // 16:9
    case portrait    // 9:16
    case square      // 1:1
    case standard    // 4:3
}
```

Canvas math: compute the padded canvas as today, then for non-auto aspect
expand ONE dimension (never shrink, never crop) until the canvas matches the
target aspect; the video stays centered; the background paints the whole
canvas. Even-pixel rounding as today. Pure function, unit-tested.

Persistence: last-used `ExportStyle` + last backdrop choice stored via
`SniprPreferences` (JSON-encoded, same pattern as `smartFolderRules`).
Custom-image backdrop persists as a file URL; if unreadable at export,
fall back to `.graphite` (same rule as wallpaper).

## `VideoBackdrop` additions

```swift
case color(RGBA)          // solid color; RGBA is a small Codable struct
case customImage(URL)     // user-chosen image file
```

- Color renders as a plain CALayer backgroundColor; picked with the native
  SwiftUI `ColorPicker` (user explicitly wants OpenScreen-style free pick —
  presets-only convention is deliberately relaxed here).
- Custom image via `NSOpenPanel` (public.image types), aspect-filled like
  wallpapers. The chosen URL is remembered in the style preferences.

## Compositor changes

`VideoCompositor.composite` gains `style: ExportStyle` (defaulted so the
bake-at-stop call site is unchanged). Padding fraction, corner radius
(× pixelScale), shadow opacity, and aspect-expanded canvas replace the
current constants. Cursor bake ignores style (nil backdrop ⇒ bare canvas,
as today).

## UI (VideoTrimView)

Bottom bar: the Background picker moves into a new "Style" popover button
(`paintbrush` icon) hosting a compact Form:
- Background: existing grouped picker + "Color" row (ColorPicker) +
  "Custom Image…" row (open panel, shows chosen filename)
- Padding slider (0–30%), Corner radius slider (0–40), Shadow slider (0–100%)
- Canvas: segmented Auto / 16:9 / 9:16 / 1:1 / 4:3
- Recordly attribution caption stays, shown when a bundled wallpaper is active

Preview mirrors padding (proportional inset), radius (clipShape), and aspect
(pane letterboxes with the backdrop, not black) approximately; shadow is
export-only (preview approximation not required).

## Testing

- Pure math: aspect-expansion canvas function (all 5 aspects, expand-only
  invariant, even rounding).
- ExportStyle round-trip through preferences.
- Integration: extend `VideoCompositorIntegrationTests` with one styled
  export (16:9 aspect + color backdrop) pixel-asserting background color in
  the expanded region and video color inside the video rect.
- Preview letterbox fix + popover: visual QA (user).

## Out of scope (deliberate)

- Background blur (user deselected), video backgrounds, spatial crop
  (top/bottom), per-item style memory (one global last-used style).
