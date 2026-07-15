# Export Style Controls + Preview Letterbox Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenScreen-style export controls (padding, corner radius, shadow, canvas aspect, solid-color and custom-image backgrounds) for video exports, plus a fix for black letterbox bars in the backdrop preview.

**Architecture:** A new `ExportStyle` value type owns the style knobs, the pure canvas math (aspect expansion), and UserDefaults persistence. `VideoBackdrop` gains `.color`/`.customImage` cases and becomes Codable. `VideoCompositor.composite` takes a defaulted `style:` parameter so the cursor-bake call site is untouched. `VideoTrimView` constrains the player to the video's aspect (letterbox fix) and hosts a Style popover.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, AVFoundation, XCTest. macOS 14 floor. CI builds warnings-as-errors.

**Spec:** `docs/superpowers/specs/2026-07-10-export-style-controls-design.md`

## Global Constraints

- Defaults keep today's look: paddingFraction 0.08, cornerRadius 16, shadowOpacity 0.45, aspect `.auto` (canvas hugs video + padding). Two deliberate default-output changes, both in Task 3: the hidden 48px padding minimum is removed (padding is honestly proportional now), and the corner radius becomes a flat `style.cornerRadius × 2` pixels (16pt at Retina) instead of the old width-scaled formula. Screenshot Beautify (`BeautifyRenderer`) is untouched.
- Aspect expansion is expand-only: one dimension grows to hit the target ratio; never shrink, never crop; video stays centered; background paints the whole canvas; even-pixel rounding stays.
- Unreadable custom image or wallpaper at export → `.graphite` gradient fallback.
- Cursor bake-at-stop call site unchanged (style parameter defaulted).
- Persistence adaptation from spec: `ExportStyle.load()/save()` + `VideoBackdrop` persistence use `UserDefaults.standard` directly (PreviewPresenter has no `SniprPreferences` to plumb through).
- Recordly attribution caption stays, shown when a bundled wallpaper is active.
- `git add` only the files each task names. Run tests with `swift test` from repo root.

---

### Task 1: `ExportStyle` model — knobs, canvas math, persistence

**Files:**
- Create: `Sources/Snipr/Models/ExportStyle.swift`
- Test: `Tests/SniprTests/ExportStyleTests.swift`

**Interfaces:**
- Produces:

```swift
struct RGBA: Codable, Hashable, Sendable {
    var red: Double, green: Double, blue: Double, alpha: Double
    var cgColor: CGColor
    init(red: Double, green: Double, blue: Double, alpha: Double)
    init(color: Color)          // SwiftUI bridge (resolve in sRGB)
    var color: Color
}

enum CanvasAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, widescreen, portrait, square, standard
    var id: String { rawValue }
    var title: String       // "Auto", "16:9", "9:16", "1:1", "4:3"
    var ratio: Double?      // nil for auto; 16.0/9, 9.0/16, 1, 4.0/3
}

struct ExportStyle: Codable, Equatable, Sendable {
    var paddingFraction: Double = 0.08
    var cornerRadius: Double = 16
    var shadowOpacity: Double = 0.45
    var aspect: CanvasAspect = .auto

    /// Padded canvas, then expanded (one dimension only) to the target
    /// aspect. Pure math; even-rounding stays the compositor's job.
    func canvas(for videoSize: CGSize) -> (canvas: CGSize, padding: CGFloat)

    static func load(from defaults: UserDefaults = .standard) -> ExportStyle
    func save(to defaults: UserDefaults = .standard)
}
```

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SniprTests/ExportStyleTests.swift
import XCTest
@testable import Snipr

final class ExportStyleTests: XCTestCase {
    func testAutoCanvasMatchesPaddedSize() {
        let style = ExportStyle()   // defaults: 0.08, auto
        let (canvas, padding) = style.canvas(for: CGSize(width: 640, height: 360))
        XCTAssertEqual(padding, 29)                    // round(360 * 0.08)
        XCTAssertEqual(canvas, CGSize(width: 698, height: 418))
    }

    func testZeroPaddingMeansNoPadding() {
        var style = ExportStyle()
        style.paddingFraction = 0
        let (canvas, padding) = style.canvas(for: CGSize(width: 640, height: 360))
        XCTAssertEqual(padding, 0)
        XCTAssertEqual(canvas, CGSize(width: 640, height: 360))
    }

    func testAspectExpansionOnlyGrows() {
        var style = ExportStyle()
        style.paddingFraction = 0

        // 640×360 is already 16:9 → widescreen changes nothing
        style.aspect = .widescreen
        XCTAssertEqual(style.canvas(for: CGSize(width: 640, height: 360)).canvas,
                       CGSize(width: 640, height: 360))

        // Square canvas for a wide video grows height, keeps width
        style.aspect = .square
        XCTAssertEqual(style.canvas(for: CGSize(width: 640, height: 360)).canvas,
                       CGSize(width: 640, height: 640))

        // Portrait 9:16 for a wide video grows height
        style.aspect = .portrait
        let portrait = style.canvas(for: CGSize(width: 640, height: 360)).canvas
        XCTAssertEqual(portrait.width, 640)
        XCTAssertEqual(portrait.height, (640.0 / (9.0 / 16.0)).rounded(), accuracy: 1)

        // Widescreen for a tall video grows width
        let tall = style.canvas(for: CGSize(width: 360, height: 640)).canvas
        style.aspect = .widescreen
        let wide = style.canvas(for: CGSize(width: 360, height: 640)).canvas
        XCTAssertEqual(wide.height, tall.height)
        XCTAssertEqual(wide.width, (640.0 * (16.0 / 9.0)).rounded(), accuracy: 1)
        XCTAssertGreaterThan(wide.width, 360)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "ExportStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ExportStyle.load(from: defaults), ExportStyle())  // defaults when unset

        var style = ExportStyle()
        style.paddingFraction = 0.2
        style.cornerRadius = 30
        style.shadowOpacity = 0.8
        style.aspect = .square
        style.save(to: defaults)
        XCTAssertEqual(ExportStyle.load(from: defaults), style)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExportStyleTests`
Expected: FAIL — `cannot find 'ExportStyle' in scope`

- [ ] **Step 3: Implement**

```swift
// Sources/Snipr/Models/ExportStyle.swift
import CoreGraphics
import Foundation
import SwiftUI

/// Codable sRGB color for persisted style choices.
struct RGBA: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        alpha = Double(resolved.alphaComponent)
    }
}

/// Output canvas shape. Non-auto aspects expand the padded canvas so the
/// background — never black bars — fills platform-standard frames.
enum CanvasAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case widescreen
    case portrait
    case square
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .widescreen: "16:9"
        case .portrait: "9:16"
        case .square: "1:1"
        case .standard: "4:3"
        }
    }

    var ratio: Double? {
        switch self {
        case .auto: nil
        case .widescreen: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .square: 1
        case .standard: 4.0 / 3.0
        }
    }
}

/// User-adjustable export framing. Defaults reproduce the pre-style export
/// exactly (8% padding, radius 16, 45% shadow, canvas hugging the video).
struct ExportStyle: Codable, Equatable, Sendable {
    var paddingFraction: Double = 0.08
    var cornerRadius: Double = 16
    var shadowOpacity: Double = 0.45
    var aspect: CanvasAspect = .auto

    /// Padded canvas, then expanded — one dimension only, never shrunk —
    /// to the target aspect. Even-pixel rounding stays the compositor's job.
    func canvas(for videoSize: CGSize) -> (canvas: CGSize, padding: CGFloat) {
        let padding = (min(videoSize.width, videoSize.height) * paddingFraction).rounded()
        var canvas = CGSize(
            width: videoSize.width + padding * 2,
            height: videoSize.height + padding * 2
        )
        if let ratio = aspect.ratio {
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        return (canvas, padding)
    }

    private static let defaultsKey = "videoExportStyle"

    static func load(from defaults: UserDefaults = .standard) -> ExportStyle {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(ExportStyle.self, from: data) else {
            return ExportStyle()
        }
        return stored
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExportStyleTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Models/ExportStyle.swift Tests/SniprTests/ExportStyleTests.swift
git commit -m "feat(export): ExportStyle model with aspect-expanding canvas math"
```

---

### Task 2: `VideoBackdrop` — color + custom image cases, Codable

**Files:**
- Modify: `Sources/Snipr/Models/VideoBackdrop.swift`
- Test: `Tests/SniprTests/VideoBackdropTests.swift` (append)

**Interfaces:**
- Consumes: `RGBA` (Task 1).
- Produces: `VideoBackdrop` gains `case color(RGBA)` and `case customImage(URL)`; conforms to `Codable` (synthesized — `BeautifyStyle` is `String`-raw so add `Codable` to it if not already conformed); `title`, `id`, `resolveImage(for:)` handle the new cases; `pickerGroups` UNCHANGED (color/custom get dedicated UI rows, not picker entries); persistence helpers:

```swift
extension VideoBackdrop {
    static let defaultsKey = "videoExportBackdrop"
    static func loadSelection(from defaults: UserDefaults = .standard) -> VideoBackdrop?
    static func saveSelection(_ backdrop: VideoBackdrop?, to defaults: UserDefaults = .standard)
}
```

- [ ] **Step 1: Write the failing test** (append to `VideoBackdropTests.swift`)

```swift
    func testColorAndCustomImageCases() throws {
        let color = VideoBackdrop.color(RGBA(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(color.title, "Color")
        XCTAssertNil(color.resolveImage(for: nil))   // rendered as a fill, not an image

        // Custom image resolves from disk; a bundled wallpaper on disk works
        // as the fixture without adding test resources.
        let bundledURL = try XCTUnwrap(
            Bundle.module.url(forResource: "sequoia-blue", withExtension: "jpg")
        )
        let custom = VideoBackdrop.customImage(bundledURL)
        XCTAssertEqual(custom.title, "Custom Image")
        XCTAssertNotNil(custom.resolveImage(for: nil))
        XCTAssertNil(VideoBackdrop.customImage(URL(fileURLWithPath: "/nonexistent.png")).resolveImage(for: nil))
    }

    func testBackdropSelectionPersistenceRoundTrip() throws {
        let suite = "VideoBackdropTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(VideoBackdrop.loadSelection(from: defaults))

        for backdrop: VideoBackdrop in [
            .gradient(.ocean),
            .bundled("sonoma-dark"),
            .wallpaper,
            .color(RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .customImage(URL(fileURLWithPath: "/tmp/x.png"))
        ] {
            VideoBackdrop.saveSelection(backdrop, to: defaults)
            XCTAssertEqual(VideoBackdrop.loadSelection(from: defaults), backdrop)
        }

        VideoBackdrop.saveSelection(nil, to: defaults)
        XCTAssertNil(VideoBackdrop.loadSelection(from: defaults))
    }

    func testPickerGroupsUnchangedByNewCases() {
        // Color/custom image live in dedicated UI rows, not the picker.
        XCTAssertEqual(VideoBackdrop.pickerGroups.flatMap(\.options).count,
                       BeautifyStyle.allCases.count + VideoBackdrop.bundledWallpaperNames.count + 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VideoBackdropTests`
Expected: FAIL — `type 'VideoBackdrop' has no member 'color'`

- [ ] **Step 3: Implement**

In `Sources/Snipr/Models/VideoBackdrop.swift`:

1. Declaration becomes `enum VideoBackdrop: Hashable, Identifiable, Codable {` and add the cases:

```swift
    case color(RGBA)         // solid fill, rendered as a plain layer color
    case customImage(URL)    // user-chosen image file, aspect-filled
```

2. Add `Codable` to `BeautifyStyle`'s conformance list in `Sources/Snipr/Support/BeautifyRenderer.swift` if not present (it is `String, CaseIterable, Identifiable, Sendable` today — append `Codable`).

3. Extend `id` / `title` / `resolveImage(for:)`:

```swift
        case .color: "color"                                   // in id
        case .customImage(let url): "custom-\(url.path)"       // in id

        case .color: "Color"                                   // in title
        case .customImage: "Custom Image"                      // in title

        case .color:                                           // in resolveImage
            nil
        case .customImage(let url):
            NSImage(contentsOf: url)
```

4. Persistence extension (JSON of the enum itself — synthesized Codable):

```swift
extension VideoBackdrop {
    static let defaultsKey = "videoExportBackdrop"

    static func loadSelection(from defaults: UserDefaults = .standard) -> VideoBackdrop? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(VideoBackdrop.self, from: data)
    }

    static func saveSelection(_ backdrop: VideoBackdrop?, to defaults: UserDefaults = .standard) {
        guard let backdrop, let data = try? JSONEncoder().encode(backdrop) else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set(data, forKey: defaultsKey)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VideoBackdropTests`
Expected: PASS (all, including the 3 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Models/VideoBackdrop.swift Sources/Snipr/Support/BeautifyRenderer.swift Tests/SniprTests/VideoBackdropTests.swift
git commit -m "feat(export): solid-color and custom-image backdrops, Codable persistence"
```

---

### Task 3: Compositor style support + integration test

**Files:**
- Modify: `Sources/Snipr/Support/VideoCompositor.swift`
- Test: `Tests/SniprTests/VideoCompositorIntegrationTests.swift` (append)

**Interfaces:**
- Consumes: `ExportStyle.canvas(for:)` (Task 1), `VideoBackdrop.color/.customImage` (Task 2).
- Produces: `composite(sourceURL:outputURL:backdrop:backdropScreen:cursor:trimStart:trimEnd:style:)` with `style: ExportStyle = ExportStyle()` as the LAST parameter (bake-at-stop call site in `RecordingPresenter` compiles unchanged).

- [ ] **Step 1: Write the failing test** (append to `VideoCompositorIntegrationTests.swift`; reuse the existing `makeSourceVideo`, `videoInfo`, `frameImage`, and pixel-sampling helpers)

```swift
    func testStyledExportExpandsCanvasToAspectAndFillsWithColor() async throws {
        let source = try await makeSourceVideo()   // 640×360, 16:9
        let out = tempDir.appending(path: "styled-square.mov")
        var style = ExportStyle()
        style.paddingFraction = 0.10                // padding = 36
        style.aspect = .square
        style.cornerRadius = 0                      // corners square: video color reaches its edges
        _ = try await VideoCompositor.composite(
            sourceURL: source, outputURL: out,
            backdrop: .color(RGBA(red: 0, green: 1, blue: 0, alpha: 1)),
            backdropScreen: nil,
            cursor: nil, trimStart: nil, trimEnd: nil,
            style: style
        )
        let info = try await videoInfo(out)
        // padded 712×432 → square expands height to 712 (even-rounded)
        XCTAssertEqual(info.size.width, 712)
        XCTAssertEqual(info.size.height, 712)

        let frame = try await frameImage(out, at: 1.0)
        // Expanded region (well above the centered video) is the fill color…
        assertPixel(frame, x: 356, y: 40, isNear: (0, 1, 0))
        // …and the video's color sits at the frame center.
        assertPixel(frame, x: 356, y: 356, isNear: (0.5, 0.3, 0.6))
    }
```

(If the existing pixel-assert helper has a different name/signature, use that one — the assertions above are the required behavior. Note the source video's frame color at t=1.0 is ~(0.5, 0.3, 0.6) per `makeSourceVideo`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VideoCompositorIntegrationTests`
Expected: FAIL — `extra argument 'style' in call` (compile) — that is the RED state.

- [ ] **Step 3: Implement**

In `VideoCompositor.swift`:

1. Signature: add `style: ExportStyle = ExportStyle()` as the final parameter of `composite`.
2. Canvas block: replace the `BeautifyRenderer.canvasGeometry(for:)` call with `style.canvas(for: videoSize)`; keep `evenSize` on the result; `padding` comes from the same call. Bare-canvas (nil backdrop) branch unchanged.
3. Corner radius: replace the current formula with `let cornerRadius = style.cornerRadius * 2` — style value is in points, exports are 2× (Retina captures); keep the existing `max(cornerRadius, 0)` semantics but drop the old `max(..., 8)` floor so radius 0 means square corners. Guard `masksToBounds`/`shadowPath` still use this radius.
4. Shadow: `shadowContainer.shadowOpacity = Float(style.shadowOpacity)`.
5. `backdropLayer(for:screen:canvas:)`: add the new cases:

```swift
        case .color(let rgba):
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = rgba.cgColor
            return layer
        case .customImage:
            // falls through to the image path below — resolveImage reads the URL
```

   (Structure it as: `.bundled, .wallpaper, .customImage` share the image path with the existing graphite fallback.)

- [ ] **Step 4: Run tests**

Run: `swift test --filter VideoCompositorIntegrationTests && swift test && swift build 2>&1 | tail -3`
Expected: new test PASS, full suite PASS, zero-warning build. The pre-existing integration tests still pass because `ExportStyle()` defaults reproduce the old constants (padding 0.08 → 48-floor difference: NOTE — the old code had `minPadding: 48`; 640×360 at 0.08 gives 29 < 48, so `testBackdropExportProducesPaddedEvenCanvas` expectations CHANGE from 736×456 to 698×418. Update that test's expected numbers accordingly and say so in the commit message — this is a deliberate behavior change: padding is now honestly proportional, no hidden 48px floor.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Support/VideoCompositor.swift Tests/SniprTests/VideoCompositorIntegrationTests.swift
git commit -m "feat(export): style-driven canvas, radius, shadow, color/custom backdrops

Padding is now honestly proportional (old hidden 48px minimum removed);
integration expectations updated."
```

---

### Task 4: VideoTrimView — letterbox fix, Style popover, persistence

**Files:**
- Modify: `Sources/Snipr/Views/VideoTrimView.swift`

**Interfaces:**
- Consumes: `ExportStyle` (Task 1), `VideoBackdrop` additions (Task 2), `composite(..., style:)` (Task 3), `CaptureItem.pixelWidth/pixelHeight` (existing).

- [ ] **Step 1: Implement the letterbox fix**

In `body`, replace the player branch with:

```swift
            if let player {
                AVPlayerViewWrapper(player: player)
                    // Constrain to the video's own aspect so the backdrop —
                    // not AVPlayerView's black letterboxing — fills the pane.
                    .aspectRatio(videoAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: backdrop == nil ? 0 : style.cornerRadius))
                    .padding(backdrop == nil ? 0 : previewPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { backdropPreview }
            } else { ... unchanged ... }
```

with helpers on the view:

```swift
    private var videoAspect: CGFloat {
        CGFloat(max(1, item.pixelWidth)) / CGFloat(max(1, item.pixelHeight))
    }

    /// Preview-scale approximation of the export padding.
    private var previewPadding: CGFloat {
        24 * style.paddingFraction / 0.08
    }
```

- [ ] **Step 2: Add style state + persistence**

```swift
    @State private var style = ExportStyle.load()
```

Initialize `backdrop` from persistence and save both on change (in `body`'s container):

```swift
        .onAppear { backdrop = VideoBackdrop.loadSelection() }
        .onChange(of: style) { _, newValue in newValue.save() }
        .onChange(of: backdrop) { _, newValue in VideoBackdrop.saveSelection(newValue) }
```

(Keep the existing `.onAppear` player creation — merge into the same closure.)

- [ ] **Step 3: Replace the header picker with the Style popover**

Replace the `Picker("Background", ...)` + `.help(...)` in the header `HStack` (and the attribution caption block below it) with:

```swift
                Button {
                    showStylePopover.toggle()
                } label: {
                    Label("Style", systemImage: "paintbrush")
                }
                .popover(isPresented: $showStylePopover, arrowEdge: .bottom) {
                    stylePopover
                }
```

Add `@State private var showStylePopover = false` and:

```swift
    @State private var customImageName: String?

    private var stylePopover: some View {
        Form {
            Section("Background") {
                Picker("Preset", selection: $backdrop) {
                    Text("None").tag(VideoBackdrop?.none)
                    ForEach(VideoBackdrop.pickerGroups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.options) { option in
                                Text(option.title).tag(VideoBackdrop?.some(option))
                            }
                        }
                    }
                }

                ColorPicker("Color", selection: Binding(
                    get: {
                        if case .color(let rgba) = backdrop { return rgba.color }
                        return Color.black
                    },
                    set: { backdrop = .color(RGBA(color: $0)) }
                ), supportsOpacity: false)

                LabeledContent("Custom Image") {
                    Button(customImageName ?? "Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            backdrop = .customImage(url)
                            customImageName = url.lastPathComponent
                        }
                    }
                }

                if case .bundled = backdrop {
                    Text("Bundled wallpapers courtesy of the Recordly project.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Frame") {
                LabeledContent("Padding") {
                    Slider(value: $style.paddingFraction, in: 0...0.30)
                    Text(style.paddingFraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Corner radius") {
                    Slider(value: $style.cornerRadius, in: 0...40)
                    Text("\(Int(style.cornerRadius))")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Shadow") {
                    Slider(value: $style.shadowOpacity, in: 0...1)
                    Text(style.shadowOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }

            Section("Canvas") {
                Picker("Aspect", selection: $style.aspect) {
                    ForEach(CanvasAspect.allCases) { aspect in
                        Text(aspect.title).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding(8)
    }
```

Set `customImageName` from a persisted `.customImage` in `.onAppear` (`if case .customImage(let url) = backdrop { customImageName = url.lastPathComponent }` — after loading the selection).

- [ ] **Step 4: Pass style to export**

In `exportTrimmed()`, add `style: style` to the `VideoCompositor.composite` call. The `TrimExporter` branch (backdrop == nil) is unchanged.

- [ ] **Step 5: Build, run the full suite**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | grep -E "Executed .* tests" | tail -1`
Expected: zero-warning build, all tests pass (no unit tests for this view — visual QA is Step 7).

- [ ] **Step 6: Commit**

```bash
git add Sources/Snipr/Views/VideoTrimView.swift
git commit -m "feat(export): style popover, aspect-fit preview (letterbox fix), persisted style"
```

- [ ] **Step 7: E2E visual verification (controller/user)**

1. `./script/build_and_run.sh run`; open a recording from history.
2. Pick a wallpaper backdrop → the preview must show the backdrop all around the video (no black bars) — this is the bug fix.
3. Open Style: drag padding/radius/shadow; switch Canvas to 16:9 and 1:1; pick a solid color; choose a custom image.
4. Export with 1:1 + color; verify in QuickTime: square canvas, color fill, video centered, no black.
5. Reopen the preview window: style and backdrop choices survived.
