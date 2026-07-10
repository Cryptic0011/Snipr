# Recording Backdrops + Custom Cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export recordings composited over gradient/wallpaper backdrops, and optionally record with a hidden system cursor replaced by a smoothed, resizable, recolorable synthetic cursor baked in right after stop.

**Architecture:** One AVFoundation compositor (`VideoCompositor`, using `AVMutableVideoComposition` + `AVVideoCompositionCoreAnimationTool`) serves both features: backdrop+trim exports from the video preview, and the automatic cursor bake that runs in `RecordingPresenter.stop()`. Cursor positions are sampled at 60 Hz in memory by `CursorSampler` while ScreenCaptureKit records with `showsCursor = false`.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, AVFoundation, ScreenCaptureKit, XCTest. macOS 14 floor (existing).

**Spec:** `docs/superpowers/specs/2026-07-10-recording-backdrop-and-cursor-design.md`

## Global Constraints

- All UI code is `@MainActor`; engines/presenters follow existing actor annotations.
- New preferences default to today's behavior (custom cursor **off**).
- Cursor color/size are preset-driven (`CursorColor` enum + bounded slider), matching the codebase's presets-not-pickers convention (`BeautifyStyle`, `WebcamBorderColor`).
- Bundled wallpapers: exactly the 11 JPEGs already committed in `Sources/Snipr/Resources/Wallpapers/` (sequoia-blue-orange, sequoia-blue, sonoma-clouds, sonoma-dark, sonoma-evening, sonoma-horizon, sonoma-light, tahoe-dark, tahoe-light, ventura-dark, ventura). Recordly attribution required in the picker UI and README.
- `nil` backdrop + no trim-needed export must keep using the lossless passthrough `TrimExporter`.
- A failed cursor bake must never lose the raw recording.
- Run tests with `swift test` from the repo root. Full app check: `./script/build_and_run.sh run`.

---

### Task 1: `VideoBackdrop` model, JPEG asset loading, build-script resources

**Files:**
- Create: `Sources/Snipr/Models/VideoBackdrop.swift`
- Modify: `Sources/Snipr/Support/SniprAssets.swift`
- Modify: `script/build_and_run.sh:89` (resource copying)
- Test: `Tests/SniprTests/VideoBackdropTests.swift`

**Interfaces:**
- Consumes: `BeautifyStyle` (existing, `Sources/Snipr/Support/BeautifyRenderer.swift`), `SniprAssets`.
- Produces: `enum VideoBackdrop: Hashable, Identifiable` with cases `.gradient(BeautifyStyle)`, `.bundled(String)`, `.wallpaper`; `static let bundledWallpaperNames: [String]`; `var title: String`; `func resolveImage(for screen: NSScreen?) -> NSImage?` (nil for `.gradient`); `SniprAssets.wallpaper(named:) -> NSImage?`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SniprTests/VideoBackdropTests.swift
import AppKit
import XCTest
@testable import Snipr

final class VideoBackdropTests: XCTestCase {
    func testBundledWallpaperNamesAllResolveToImages() {
        XCTAssertEqual(VideoBackdrop.bundledWallpaperNames.count, 11)
        for name in VideoBackdrop.bundledWallpaperNames {
            XCTAssertNotNil(
                SniprAssets.wallpaper(named: name),
                "Missing bundled wallpaper resource: \(name)"
            )
        }
    }

    func testTitles() {
        XCTAssertEqual(VideoBackdrop.gradient(.ocean).title, "Ocean")
        XCTAssertEqual(VideoBackdrop.bundled("sonoma-horizon").title, "Sonoma Horizon")
        XCTAssertEqual(VideoBackdrop.wallpaper.title, "Desktop Wallpaper")
    }

    func testBundledResolvesImageAndGradientDoesNot() {
        XCTAssertNotNil(VideoBackdrop.bundled("sequoia-blue").resolveImage(for: nil))
        XCTAssertNil(VideoBackdrop.gradient(.brass).resolveImage(for: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VideoBackdropTests`
Expected: FAIL — `cannot find 'VideoBackdrop' in scope`

- [ ] **Step 3: Implement**

```swift
// Sources/Snipr/Models/VideoBackdrop.swift
import AppKit

/// Backdrop a recording is composited over at export time. Mirrors the
/// screenshot Beautify feature: presets, not a free-form picker.
enum VideoBackdrop: Hashable, Identifiable {
    case gradient(BeautifyStyle)
    case bundled(String)   // resource name, e.g. "sonoma-horizon"
    case wallpaper         // the user's current desktop wallpaper

    /// Curated macOS-style set shipped in Resources/Wallpapers (from the
    /// Recordly project — attribution required in UI + README).
    static let bundledWallpaperNames: [String] = [
        "sequoia-blue-orange", "sequoia-blue",
        "sonoma-clouds", "sonoma-dark", "sonoma-evening",
        "sonoma-horizon", "sonoma-light",
        "tahoe-dark", "tahoe-light",
        "ventura-dark", "ventura"
    ]

    var id: String {
        switch self {
        case .gradient(let style): "gradient-\(style.rawValue)"
        case .bundled(let name): "bundled-\(name)"
        case .wallpaper: "wallpaper"
        }
    }

    var title: String {
        switch self {
        case .gradient(let style): style.title
        case .bundled(let name):
            name.split(separator: "-").map(\.capitalized).joined(separator: " ")
        case .wallpaper: "Desktop Wallpaper"
        }
    }

    /// The image drawn behind the video; nil for gradients (drawn as a
    /// CAGradientLayer instead) and when the wallpaper can't be read.
    func resolveImage(for screen: NSScreen?) -> NSImage? {
        switch self {
        case .gradient:
            nil
        case .bundled(let name):
            SniprAssets.wallpaper(named: name)
        case .wallpaper:
            (screen ?? NSScreen.main)
                .flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                .flatMap { NSImage(contentsOf: $0) }
        }
    }
}
```

Add to `Sources/Snipr/Support/SniprAssets.swift` (inside `enum SniprAssets`):

```swift
    static func wallpaper(named name: String) -> NSImage? {
        for bundle in [Bundle.main, Bundle.module] {
            if let url = bundle.url(forResource: name, withExtension: "jpg"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
```

In `script/build_and_run.sh`, directly below the existing line
`cp "$ROOT_DIR"/Sources/Snipr/Resources/*.png "$APP_RESOURCES"/` add:

```bash
cp "$ROOT_DIR"/Sources/Snipr/Resources/Wallpapers/*.jpg "$APP_RESOURCES"/
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VideoBackdropTests`
Expected: PASS (3 tests). SPM `.process("Resources")` flattens `Wallpapers/*.jpg` into `Bundle.module`, so name-only lookup works.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Models/VideoBackdrop.swift Sources/Snipr/Support/SniprAssets.swift script/build_and_run.sh Tests/SniprTests/VideoBackdropTests.swift
git commit -m "feat(recording): VideoBackdrop model with bundled macOS-style wallpapers"
```

---

### Task 2: Cursor preferences + Recording settings UI

**Files:**
- Create: `Sources/Snipr/Models/CursorColor.swift`
- Modify: `Sources/Snipr/Models/SniprPreferences.swift`
- Modify: `Sources/Snipr/Views/Settings/RecordingTab.swift`
- Test: `Tests/SniprTests/SniprPreferencesTests.swift` (append)

**Interfaces:**
- Produces: `enum CursorColor: String, CaseIterable, Identifiable, Codable, Sendable` (cases `white, black, brass, blue, red`; `var fill: CGColor`, `var outline: CGColor`, `var title: String`). Preferences: `recordingCustomCursor: Bool` (false), `recordingCursorSmoothing: Bool` (true), `recordingCursorScale: Double` (1.5), `recordingCursorColor: CursorColor` (.white).

- [ ] **Step 1: Write the failing test** (append to `SniprPreferencesTests.swift`; it already has a `makeDefaults()` helper returning `(defaults, suiteName)`)

```swift
    @MainActor
    func testCursorPreferencesDefaultsAndPersistence() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = SniprPreferences(defaults: defaults)
        XCTAssertFalse(prefs.recordingCustomCursor)
        XCTAssertTrue(prefs.recordingCursorSmoothing)
        XCTAssertEqual(prefs.recordingCursorScale, 1.5)
        XCTAssertEqual(prefs.recordingCursorColor, .white)

        prefs.recordingCustomCursor = true
        prefs.recordingCursorScale = 2.0
        prefs.recordingCursorColor = .brass

        let reloaded = SniprPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.recordingCustomCursor)
        XCTAssertEqual(reloaded.recordingCursorScale, 2.0)
        XCTAssertEqual(reloaded.recordingCursorColor, .brass)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SniprPreferencesTests`
Expected: FAIL — `value of type 'SniprPreferences' has no member 'recordingCustomCursor'`

- [ ] **Step 3: Implement**

```swift
// Sources/Snipr/Models/CursorColor.swift
import CoreGraphics

/// Preset tints for the synthetic recording cursor. Presets, not a color
/// picker — same philosophy as BeautifyStyle / WebcamBorderColor.
enum CursorColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case white
    case black
    case brass
    case blue
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Arrow body fill.
    var fill: CGColor {
        switch self {
        case .white: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        case .brass: CGColor(red: 0.80, green: 0.67, blue: 0.33, alpha: 1)
        case .blue: CGColor(red: 0.25, green: 0.51, blue: 0.96, alpha: 1)
        case .red: CGColor(red: 0.91, green: 0.28, blue: 0.24, alpha: 1)
        }
    }

    /// Contrasting outline so the arrow reads on any content.
    var outline: CGColor {
        switch self {
        case .white: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
        default: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        }
    }
}
```

In `SniprPreferences.swift` add to `Keys`:

```swift
        static let recordingCustomCursor = "recordingCustomCursor"
        static let recordingCursorSmoothing = "recordingCursorSmoothing"
        static let recordingCursorScale = "recordingCursorScale"
        static let recordingCursorColor = "recordingCursorColor"
```

Add properties (below `webcamBubbleBorderColor`):

```swift
    /// Record with the system cursor hidden and bake a synthetic smoothed
    /// cursor into the file right after the recording stops.
    var recordingCustomCursor: Bool {
        didSet { defaults.set(recordingCustomCursor, forKey: Keys.recordingCustomCursor) }
    }

    /// Smooth the synthetic cursor's path (cubic interpolation over a
    /// thinned sample set). Off = raw 60 Hz path.
    var recordingCursorSmoothing: Bool {
        didSet { defaults.set(recordingCursorSmoothing, forKey: Keys.recordingCursorSmoothing) }
    }

    /// Synthetic cursor size multiplier (1.0–3.0).
    var recordingCursorScale: Double {
        didSet { defaults.set(recordingCursorScale, forKey: Keys.recordingCursorScale) }
    }

    /// Synthetic cursor tint preset.
    var recordingCursorColor: CursorColor {
        didSet { defaults.set(recordingCursorColor.rawValue, forKey: Keys.recordingCursorColor) }
    }
```

Add to `init` (after `webcamBubbleBorderColor` loading):

```swift
        recordingCustomCursor = defaults.object(forKey: Keys.recordingCustomCursor) as? Bool ?? false
        recordingCursorSmoothing = defaults.object(forKey: Keys.recordingCursorSmoothing) as? Bool ?? true
        recordingCursorScale = defaults.object(forKey: Keys.recordingCursorScale) as? Double ?? 1.5
        recordingCursorColor = CursorColor(
            rawValue: defaults.string(forKey: Keys.recordingCursorColor) ?? ""
        ) ?? .white
```

In `RecordingTab.swift`, add a new section between `Section("Recording")` and `Section("While recording")`:

```swift
            Section("Custom cursor") {
                Toggle("Replace cursor in recordings", isOn: Binding(
                    get: { model.preferences.recordingCustomCursor },
                    set: { model.preferences.recordingCustomCursor = $0 }
                ))
                Text("Records with the real cursor hidden, then bakes in a redrawn cursor when the recording stops. Applies to region, window, and full-screen recordings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Smooth cursor movement", isOn: Binding(
                    get: { model.preferences.recordingCursorSmoothing },
                    set: { model.preferences.recordingCursorSmoothing = $0 }
                ))
                .disabled(!model.preferences.recordingCustomCursor)

                LabeledContent("Cursor size") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.preferences.recordingCursorScale },
                            set: { model.preferences.recordingCursorScale = $0 }
                        ), in: 1.0...3.0, step: 0.25)
                        .frame(width: 180)
                        Text(String(format: "%.2f×", model.preferences.recordingCursorScale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!model.preferences.recordingCustomCursor)

                LabeledContent("Cursor color") {
                    Picker("Cursor color", selection: Binding(
                        get: { model.preferences.recordingCursorColor },
                        set: { model.preferences.recordingCursorColor = $0 }
                    )) {
                        ForEach(CursorColor.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .disabled(!model.preferences.recordingCustomCursor)
            }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SniprPreferencesTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Models/CursorColor.swift Sources/Snipr/Models/SniprPreferences.swift Sources/Snipr/Views/Settings/RecordingTab.swift Tests/SniprTests/SniprPreferencesTests.swift
git commit -m "feat(recording): custom cursor preferences and settings UI"
```

---

### Task 3: `CursorSampler` + coordinate mapping + thinning

**Files:**
- Create: `Sources/Snipr/Support/CursorSampler.swift`
- Test: `Tests/SniprTests/CursorSamplerTests.swift`

**Interfaces:**
- Produces:

```swift
struct CursorSample: Equatable, Sendable {
    let time: TimeInterval    // seconds since sampling started
    let location: CGPoint     // global Cocoa coords (bottom-left origin, points)
}

@MainActor final class CursorSampler {
    private(set) var samples: [CursorSample] = []
    var isSampling: Bool { get }
    func start()                       // 60 Hz timer, resets samples
    func stop() -> [CursorSample]      // stops timer, returns samples
    func discard()                     // stops timer, drops samples
}

enum CursorPath {
    /// Global Cocoa point → video pixel coords (top-left origin).
    static func mapToVideoPixels(_ point: CGPoint, region: CGRect, scale: CGFloat) -> CGPoint
    /// Keep every `stride`-th sample, always retaining first and last.
    static func thinned(_ samples: [CursorSample], stride: Int) -> [CursorSample]
}
```

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SniprTests/CursorSamplerTests.swift
import XCTest
@testable import Snipr

final class CursorSamplerTests: XCTestCase {
    func testMapToVideoPixelsFlipsYAndScales() {
        // Region: 100pt-wide, 50pt-tall region whose bottom-left global
        // corner is (10, 20). 2x display → video pixels are 200×100.
        let region = CGRect(x: 10, y: 20, width: 100, height: 50)
        // Bottom-left corner of the region → (0, maxYPixels)
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 10, y: 20), region: region, scale: 2),
            CGPoint(x: 0, y: 100)
        )
        // Top-left corner → origin in top-left video space
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 10, y: 70), region: region, scale: 2),
            CGPoint(x: 0, y: 0)
        )
        // Center maps to center
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 60, y: 45), region: region, scale: 2),
            CGPoint(x: 100, y: 50)
        )
    }

    func testThinnedKeepsFirstAndLastAndStride() {
        let samples = (0..<10).map { CursorSample(time: Double($0), location: CGPoint(x: Double($0), y: 0)) }
        let thinned = CursorPath.thinned(samples, stride: 4)
        XCTAssertEqual(thinned.map(\.time), [0, 4, 8, 9])   // every 4th + last
        XCTAssertEqual(CursorPath.thinned(samples, stride: 1), samples)
        XCTAssertEqual(CursorPath.thinned([], stride: 4), [])
    }

    @MainActor
    func testSamplerCollectsSamplesWhileRunning() async throws {
        let sampler = CursorSampler()
        sampler.start()
        XCTAssertTrue(sampler.isSampling)
        try await Task.sleep(nanoseconds: 200_000_000)   // ~12 ticks at 60 Hz
        let samples = sampler.stop()
        XCTAssertFalse(sampler.isSampling)
        XCTAssertGreaterThan(samples.count, 3)
        // Times are monotonically nondecreasing and start near zero.
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
        XCTAssertLessThan(samples[0].time, 0.1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CursorSamplerTests`
Expected: FAIL — `cannot find 'CursorPath' in scope`

- [ ] **Step 3: Implement**

```swift
// Sources/Snipr/Support/CursorSampler.swift
import AppKit

/// One sampled cursor position, relative to sampling start.
struct CursorSample: Equatable, Sendable {
    let time: TimeInterval
    let location: CGPoint   // global Cocoa coordinates (bottom-left origin)
}

/// Polls the global mouse location at 60 Hz while a recording runs. Polling
/// `NSEvent.mouseLocation` needs no permissions, unlike event taps.
@MainActor
final class CursorSampler {
    private(set) var samples: [CursorSample] = []
    private var timer: Timer?
    private var startedAt: TimeInterval = 0

    var isSampling: Bool { timer != nil }

    func start() {
        discard()
        samples.reserveCapacity(60 * 60 * 5)   // 5 minutes without realloc
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.samples.append(CursorSample(
                    time: ProcessInfo.processInfo.systemUptime - self.startedAt,
                    location: NSEvent.mouseLocation
                ))
            }
        }
        // .common so sampling continues while menus/drags run their tracking loops.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() -> [CursorSample] {
        timer?.invalidate()
        timer = nil
        return samples
    }

    func discard() {
        timer?.invalidate()
        timer = nil
        samples = []
    }
}

/// Pure math for turning sampled global points into video-pixel keyframes.
enum CursorPath {
    /// Global Cocoa point (bottom-left origin) → video pixels (top-left
    /// origin, matching the flipped compositing layer space).
    static func mapToVideoPixels(_ point: CGPoint, region: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x - region.minX) * scale,
            y: (region.maxY - point.y) * scale
        )
    }

    /// Every `stride`-th sample plus the final one, so cubic interpolation
    /// has anchors at both ends. `stride <= 1` returns the input unchanged.
    static func thinned(_ samples: [CursorSample], stride strideLength: Int) -> [CursorSample] {
        guard strideLength > 1, samples.count > 2 else { return samples }
        var kept = Swift.stride(from: 0, to: samples.count, by: strideLength).map { samples[$0] }
        if let last = samples.last, kept.last != last {
            kept.append(last)
        }
        return kept
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CursorSamplerTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Support/CursorSampler.swift Tests/SniprTests/CursorSamplerTests.swift
git commit -m "feat(recording): 60Hz cursor sampler with pixel mapping and thinning"
```

---

### Task 4: `VideoCompositor` — backdrop, cursor overlay, trim, export

**Files:**
- Create: `Sources/Snipr/Support/VideoCompositor.swift`
- Test: `Tests/SniprTests/VideoCompositorTests.swift`

**Interfaces:**
- Consumes: `VideoBackdrop` (Task 1), `CursorSample`/`CursorPath` (Task 3), `CursorColor` (Task 2), `BeautifyRenderer.canvasGeometry` (existing).
- Produces:

```swift
struct CursorOverlaySpec: Sendable {
    let samples: [CursorSample]     // global Cocoa points
    let regionInScreen: CGRect      // recorded region, global Cocoa coords
    let scale: Double               // cursor size multiplier (pref)
    let color: CursorColor
    let smoothed: Bool
}

enum VideoCompositorError: LocalizedError { case exportFailed(any Error), sessionUnavailable, noVideoTrack }

enum VideoCompositor {
    static func evenSize(_ size: CGSize) -> CGSize   // rounds each dimension UP to even
    static func composite(
        sourceURL: URL, outputURL: URL,
        backdrop: VideoBackdrop?, backdropScreen: NSScreen?,
        cursor: CursorOverlaySpec?,
        trimStart: TimeInterval?, trimEnd: TimeInterval?
    ) async throws -> URL
    static func cursorArrowPath(height: CGFloat) -> CGPath   // top-left-origin arrow, tip at (0,0)
}
```

- [ ] **Step 1: Write the failing test** (pure geometry + arrow path; the AVFoundation pipeline is verified in Task 5's integration test and the E2E check)

```swift
// Tests/SniprTests/VideoCompositorTests.swift
import CoreGraphics
import XCTest
@testable import Snipr

final class VideoCompositorTests: XCTestCase {
    func testEvenSizeRoundsUpToEven() {
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 641, height: 480)), CGSize(width: 642, height: 480))
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 640.4, height: 479.5)), CGSize(width: 642, height: 480))
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 2, height: 2)), CGSize(width: 2, height: 2))
    }

    func testCursorArrowPathIsNonEmptyAndAnchoredAtTip() {
        let path = VideoCompositor.cursorArrowPath(height: 24)
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingBox
        // Tip at origin, arrow extends right/down in top-left-origin space.
        XCTAssertEqual(box.minX, 0, accuracy: 0.001)
        XCTAssertEqual(box.minY, 0, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 24, accuracy: 0.5)
        XCTAssertGreaterThan(box.maxX, 10)
        // Scales linearly.
        XCTAssertEqual(VideoCompositor.cursorArrowPath(height: 48).boundingBox.maxY, 48, accuracy: 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VideoCompositorTests`
Expected: FAIL — `cannot find 'VideoCompositor' in scope`

- [ ] **Step 3: Implement**

```swift
// Sources/Snipr/Support/VideoCompositor.swift
@preconcurrency import AVFoundation
import AppKit
import QuartzCore

/// Everything the compositor needs to draw the synthetic cursor.
struct CursorOverlaySpec: Sendable {
    let samples: [CursorSample]
    let regionInScreen: CGRect
    let scale: Double
    let color: CursorColor
    let smoothed: Bool
}

enum VideoCompositorError: LocalizedError {
    case exportFailed(any Error)
    case sessionUnavailable
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .exportFailed(let error): error.localizedDescription
        case .sessionUnavailable: "Snipr could not start the video export session."
        case .noVideoTrack: "The recording has no video track."
        }
    }
}

/// One AVFoundation compositor for both share-ready features: backdrop
/// exports from the video preview, and the automatic cursor bake after a
/// recording stops. Rendering happens on the GPU via the Core Animation
/// tool — layers are declarative, no per-frame CPU work.
enum VideoCompositor {
    /// H.264 wants even dimensions; round up so content is never cropped.
    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: 2 * ((size.width / 2).rounded(.up)),
            height: 2 * ((size.height / 2).rounded(.up))
        )
    }

    /// Classic macOS arrow, drawn in top-left-origin (y-down) coordinates
    /// with the hotspot/tip at (0,0). Proportions follow the system arrow's
    /// 17:24 box at `height` = 24.
    static func cursorArrowPath(height: CGFloat) -> CGPath {
        let s = height / 24.0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))                       // tip
        path.addLine(to: CGPoint(x: 0, y: 20.5 * s))             // left edge down
        path.addLine(to: CGPoint(x: 4.6 * s, y: 16.2 * s))       // notch in
        path.addLine(to: CGPoint(x: 7.6 * s, y: 23.1 * s))       // down to click-heel
        path.addLine(to: CGPoint(x: 10.5 * s, y: 21.9 * s))      // heel across
        path.addLine(to: CGPoint(x: 7.5 * s, y: 15.0 * s))       // back up
        path.addLine(to: CGPoint(x: 13.9 * s, y: 14.7 * s))      // out to right barb
        path.closeSubpath()
        return path
    }

    static func composite(
        sourceURL: URL,
        outputURL: URL,
        backdrop: VideoBackdrop?,
        backdropScreen: NSScreen?,
        cursor: CursorOverlaySpec?,
        trimStart: TimeInterval?,
        trimEnd: TimeInterval?
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoCompositorError.noVideoTrack
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Canvas: padded per BeautifyRenderer's math when there's a backdrop,
        // bare video size for a cursor-only bake. Even either way.
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        let padding: CGFloat
        let canvas: CGSize
        if backdrop != nil {
            let geometry = BeautifyRenderer.canvasGeometry(for: videoSize)
            padding = geometry.padding
            canvas = evenSize(geometry.canvas)
        } else {
            padding = 0
            canvas = evenSize(videoSize)
        }

        // ---- Layer tree (all frames in top-left-origin space via
        // isGeometryFlipped; CoreAnimation renders it upright). ----
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: canvas)
        parentLayer.isGeometryFlipped = true

        let videoLayer = CALayer()
        let videoRect = CGRect(
            x: (canvas.width - videoSize.width) / 2,
            y: (canvas.height - videoSize.height) / 2,
            width: videoSize.width,
            height: videoSize.height
        )

        if let backdrop {
            parentLayer.addSublayer(backdropLayer(for: backdrop, screen: backdropScreen, canvas: canvas))

            // Shadow lives on a container so the video layer itself can clip
            // to rounded corners (shadow + masksToBounds are exclusive).
            let cornerRadius = 16 * (videoSize.width / max(videoSize.width, 1200))
            let shadowContainer = CALayer()
            shadowContainer.frame = videoRect
            shadowContainer.shadowColor = CGColor(gray: 0, alpha: 1)
            shadowContainer.shadowOpacity = 0.45
            shadowContainer.shadowRadius = padding * 0.5
            shadowContainer.shadowOffset = CGSize(width: 0, height: padding * 0.16)
            shadowContainer.shadowPath = CGPath(
                roundedRect: CGRect(origin: .zero, size: videoRect.size),
                cornerWidth: max(cornerRadius, 8),
                cornerHeight: max(cornerRadius, 8),
                transform: nil
            )

            videoLayer.frame = CGRect(origin: .zero, size: videoRect.size)
            videoLayer.cornerRadius = max(cornerRadius, 8)
            videoLayer.masksToBounds = true
            shadowContainer.addSublayer(videoLayer)
            parentLayer.addSublayer(shadowContainer)
        } else {
            videoLayer.frame = videoRect
            parentLayer.addSublayer(videoLayer)
        }

        if let cursor, !cursor.samples.isEmpty {
            // Cursor coordinates are relative to the video, so parent the
            // arrow to the layer that contains the video content.
            let host = backdrop != nil ? videoLayer : parentLayer
            let offset = backdrop != nil ? CGPoint.zero : videoRect.origin
            host.addSublayer(cursorLayer(
                for: cursor,
                videoSize: videoSize,
                offset: offset,
                videoDuration: durationSeconds
            ))
        }

        // ---- Composition ----
        let composition = AVMutableVideoComposition(propertiesOf: asset)
        composition.renderSize = canvas
        composition.instructions = passthroughInstruction(for: videoTrack, duration: duration)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoCompositorError.sessionUnavailable
        }
        session.videoComposition = composition
        session.outputURL = outputURL
        let fileType: AVFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.outputFileType = fileType
        if let trimStart, let trimEnd, trimEnd > trimStart {
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: max(0, trimStart), preferredTimescale: 600),
                end: CMTime(seconds: min(durationSeconds, trimEnd), preferredTimescale: 600)
            )
        }

        do {
            try await session.export(to: outputURL, as: fileType)
        } catch {
            throw VideoCompositorError.exportFailed(error)
        }
        return outputURL
    }

    // MARK: - Layer builders

    private static func backdropLayer(for backdrop: VideoBackdrop, screen: NSScreen?, canvas: CGSize) -> CALayer {
        let frame = CGRect(origin: .zero, size: canvas)
        switch backdrop {
        case .gradient(let style):
            let layer = CAGradientLayer()
            layer.frame = frame
            let (top, bottom) = style.colors
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            layer.colors = [
                CGColor(colorSpace: space, components: top),
                CGColor(colorSpace: space, components: bottom)
            ].compactMap { $0 }
            layer.startPoint = CGPoint(x: 0, y: 0)
            layer.endPoint = CGPoint(x: 1, y: 1)
            return layer
        case .bundled, .wallpaper:
            let layer = CALayer()
            layer.frame = frame
            if let image = backdrop.resolveImage(for: screen) {
                var rect = CGRect(origin: .zero, size: image.size)
                layer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                layer.contentsGravity = .resizeAspectFill
                layer.masksToBounds = true
            } else {
                // Wallpaper unreadable — graphite gradient fallback (spec).
                return backdropLayer(for: .gradient(.graphite), screen: nil, canvas: canvas)
            }
            return layer
        }
    }

    private static func cursorLayer(
        for cursor: CursorOverlaySpec,
        videoSize: CGSize,
        offset: CGPoint,
        videoDuration: TimeInterval
    ) -> CALayer {
        // Pixels-per-point of the recording; sized so the arrow matches how
        // big the real cursor would have appeared, times the user multiplier.
        let pixelScale = videoSize.width / max(cursor.regionInScreen.width, 1)
        let arrowHeight = 24 * pixelScale * cursor.scale

        let shape = CAShapeLayer()
        shape.path = cursorArrowPath(height: arrowHeight)
        shape.fillColor = cursor.color.fill
        shape.strokeColor = cursor.color.outline
        shape.lineWidth = max(1, arrowHeight / 16)
        shape.lineJoin = .round
        let box = shape.path?.boundingBox ?? .zero
        shape.bounds = CGRect(x: 0, y: 0, width: box.maxX, height: box.maxY)
        shape.anchorPoint = .zero   // position == the arrow tip

        let used = cursor.smoothed
            ? CursorPath.thinned(cursor.samples, stride: 6)   // ~10 Hz anchors
            : cursor.samples
        let points = used.map {
            let p = CursorPath.mapToVideoPixels($0.location, region: cursor.regionInScreen, scale: pixelScale)
            return CGPoint(x: p.x + offset.x, y: p.y + offset.y)
        }

        guard videoDuration > 0, points.count > 1 else {
            shape.position = points.first ?? .zero
            return shape
        }

        shape.position = points[0]
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.values = points.map { NSValue(point: $0) }
        animation.keyTimes = used.map { NSNumber(value: min(1, $0.time / videoDuration)) }
        animation.calculationMode = cursor.smoothed ? .cubic : .linear
        animation.duration = videoDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        shape.add(animation, forKey: "cursorPath")
        return shape
    }

    /// The CA tool stretches video content to fill `videoLayer`; the
    /// composition instruction only needs to pass the track through
    /// untransformed at its natural size.
    private static func passthroughInstruction(
        for track: AVAssetTrack,
        duration: CMTime
    ) -> [AVMutableVideoCompositionInstruction] {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instruction.layerInstructions = [layerInstruction]
        return [instruction]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VideoCompositorTests`
Expected: PASS (2 tests). Also run `swift build` — the whole target must compile.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Support/VideoCompositor.swift Tests/SniprTests/VideoCompositorTests.swift
git commit -m "feat(recording): AVFoundation compositor for backdrops and cursor overlay"
```

---

### Task 5: Recording pipeline — hide cursor, sample, bake at stop

**Files:**
- Modify: `Sources/Snipr/Engines/RecordingEngine.swift` (RecordingOptions)
- Modify: `Sources/Snipr/Engines/SCKRecordingEngine.swift:83`
- Modify: `Sources/Snipr/Presenters/RecordingPresenter.swift`
- Modify: `Tests/SniprTests/FakeEngines.swift` (record options)
- Test: `Tests/SniprTests/RecordingPresenterTests.swift` (append)

**Interfaces:**
- Consumes: `CursorSampler`, `CursorOverlaySpec`, `VideoCompositor.composite` (Tasks 3–4); preferences from Task 2.
- Produces: `RecordingOptions.hidesSystemCursor: Bool = false`; `FakeRecordingEngine.lastOptions: RecordingOptions?`.

- [ ] **Step 1: Write the failing tests** (append to `RecordingPresenterTests.swift`; reuse the file's existing `waitFor` helper and store/engine setup pattern)

```swift
    /// Custom-cursor pref on → the engine is asked to hide the system
    /// cursor; off → it isn't.
    func testCustomCursorPrefHidesSystemCursor() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        // Isolated defaults, same pattern as SniprPreferencesTests.makeDefaults():
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        prefs.recordingCustomCursor = true
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }
        XCTAssertEqual(engine.lastOptions?.hidesSystemCursor, true)

        presenter.cancel()
    }

    /// With the pref off, options say so and no bake runs — the stored file
    /// is byte-identical to what the engine produced.
    func testNoCursorPrefLeavesRecordingUntouched() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let finished = expectation(description: "finished")
        presenter.onRecordingFinished = { finished.fulfill() }

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }
        XCTAssertEqual(engine.lastOptions?.hidesSystemCursor, false)

        presenter.stop()
        await fulfillment(of: [finished], timeout: 2)
        // FakeRecordingEngine writes Data([0x00]); an accidental bake attempt
        // on a bogus file would fail and surface an error instead.
        let url = try XCTUnwrap(store.items.first?.fileURL)
        XCTAssertEqual(try Data(contentsOf: url), Data([0x00]))
    }

    /// Bake failure (the fake's file isn't a real video) falls back to the
    /// raw recording: item still lands in the store, error is surfaced.
    func testFailedCursorBakeKeepsRawRecording() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        prefs.recordingCustomCursor = true
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let finished = expectation(description: "finished")
        presenter.onRecordingFinished = { finished.fulfill() }
        var surfacedError: Error?
        presenter.onError = { surfacedError = $0 }

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }

        presenter.stop()
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertEqual(store.items.count, 1, "raw recording must survive a failed bake")
        XCTAssertNotNil(surfacedError, "bake failure should be reported")
    }
```

In `FakeEngines.swift`, add to `FakeRecordingEngine`:

```swift
    var lastOptions: RecordingOptions?

    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL,
        options: RecordingOptions
    ) async throws {
        lastOptions = options
        try await start(displayID: displayID, rectInDisplayPoints: rectInDisplayPoints, screen: screen, destinationURL: destinationURL)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RecordingPresenterTests`
Expected: FAIL — `'RecordingOptions' has no member 'hidesSystemCursor'`

- [ ] **Step 3: Implement**

`RecordingEngine.swift` — add to `RecordingOptions`:

```swift
    /// Record without the system cursor (a synthetic one is baked in later).
    var hidesSystemCursor: Bool = false
```

`SCKRecordingEngine.swift:83` — replace `configuration.showsCursor = true` with:

```swift
        configuration.showsCursor = !options.hidesSystemCursor
```

`RecordingPresenter.swift` changes:

```swift
    // New stored properties next to `activeRecordingDisplayID`:
    private let cursorSampler = CursorSampler()
    private var activeRecordingRegion: NSRect?   // global Cocoa coords
```

In `start(...)`, build options with the new flag and start sampling (inside the existing `do` block, after `recordingEngine.start` succeeds — placement matters so a failed start never leaves a dangling timer):

```swift
                let customCursor = preferences?.recordingCustomCursor ?? false
                try await recordingEngine.start(
                    displayID: displayID,
                    rectInDisplayPoints: rect,
                    screen: screen,
                    destinationURL: destinationURL,
                    options: RecordingOptions(
                        capturesSystemAudio: preferences?.recordSystemAudio ?? false,
                        capturesMicrophone: preferences?.recordMicrophone ?? false,
                        fileFormat: format,
                        hidesSystemCursor: customCursor
                    )
                )
                activeRecordingDisplayID = displayID
                if customCursor {
                    // Same rect math as the companions: top-left display
                    // points → global Cocoa coordinates.
                    activeRecordingRegion = NSRect(
                        x: screen.frame.minX + rect.minX,
                        y: screen.frame.maxY - rect.maxY,
                        width: rect.width,
                        height: rect.height
                    )
                    cursorSampler.start()
                }
```

In `stop()`, replace the body of the `do` block:

```swift
                let recordedVideo = try await self.recordingEngine.stop()
                let samples = self.cursorSampler.stop()
                self.closeRecordingHUD()

                var finalVideo = recordedVideo
                if let region = self.activeRecordingRegion, !samples.isEmpty, let preferences = self.preferences {
                    ToastPresenter.show("Finishing recording…", systemImage: "cursorarrow.motionlines")
                    do {
                        finalVideo = try await self.bakeCursor(
                            into: recordedVideo,
                            samples: samples,
                            region: region,
                            preferences: preferences
                        )
                    } catch {
                        // Never lose the recording — store the raw file and say why.
                        self.onError?(error)
                    }
                }
                self.activeRecordingRegion = nil

                _ = try self.captureStore.addRecording(
                    fileURL: finalVideo.fileURL,
                    pixelSize: finalVideo.pixelSize,
                    displayID: self.activeRecordingDisplayID,
                    duration: finalVideo.duration
                )
                self.activeRecordingDisplayID = nil
                self.onRecordingFinished?()
```

…and in the `catch` of `stop()` add `self.cursorSampler.discard()` and `self.activeRecordingRegion = nil`. In `cancel()` add the same two lines.

New private method on `RecordingPresenter`:

```swift
    /// Re-encode once to draw the synthetic cursor over the recording, then
    /// atomically swap the baked file into the original URL so downstream
    /// (store, GIF export, trim) never knows the difference.
    private func bakeCursor(
        into video: RecordedVideo,
        samples: [CursorSample],
        region: NSRect,
        preferences: SniprPreferences
    ) async throws -> RecordedVideo {
        let bakedURL = video.fileURL.deletingPathExtension()
            .appendingPathExtension("baked." + video.fileURL.pathExtension)
        _ = try await VideoCompositor.composite(
            sourceURL: video.fileURL,
            outputURL: bakedURL,
            backdrop: nil,
            backdropScreen: nil,
            cursor: CursorOverlaySpec(
                samples: samples,
                regionInScreen: region,
                scale: preferences.recordingCursorScale,
                color: preferences.recordingCursorColor,
                smoothed: preferences.recordingCursorSmoothing
            ),
            trimStart: nil,
            trimEnd: nil
        )
        _ = try FileManager.default.replaceItemAt(video.fileURL, withItemAt: bakedURL)
        return RecordedVideo(fileURL: video.fileURL, pixelSize: video.pixelSize, duration: video.duration)
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter RecordingPresenterTests`
Expected: PASS (all, including the three new ones — the bake-failure test passes because `Data([0x00])` is not a readable AVAsset, so `composite` throws `noVideoTrack`/load error and the fallback stores the raw file).

Run: `swift test`
Expected: PASS (full suite; no other test touches `showsCursor`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Engines/RecordingEngine.swift Sources/Snipr/Engines/SCKRecordingEngine.swift Sources/Snipr/Presenters/RecordingPresenter.swift Tests/SniprTests/FakeEngines.swift Tests/SniprTests/RecordingPresenterTests.swift
git commit -m "feat(recording): hide system cursor and bake smoothed synthetic cursor at stop"
```

---

### Task 6: Backdrop picker + export in the video preview, attribution

**Files:**
- Modify: `Sources/Snipr/Views/VideoTrimView.swift`
- Modify: `README.md` (credits)
- Test: `Tests/SniprTests/VideoBackdropTests.swift` (append picker-grouping test)

**Interfaces:**
- Consumes: `VideoBackdrop` (Task 1), `VideoCompositor.composite` (Task 4), existing `TrimExporter`.
- Produces: `VideoBackdrop.pickerGroups: [(label: String, options: [VideoBackdrop])]` (static, for the menu).

- [ ] **Step 1: Write the failing test** (append to `VideoBackdropTests.swift`)

```swift
    func testPickerGroupsCoverAllOptions() {
        let groups = VideoBackdrop.pickerGroups
        XCTAssertEqual(groups.map(\.label), ["Gradients", "Wallpapers", "Desktop"])
        XCTAssertEqual(groups[0].options.count, BeautifyStyle.allCases.count)
        XCTAssertEqual(groups[1].options.count, VideoBackdrop.bundledWallpaperNames.count)
        XCTAssertEqual(groups[2].options, [.wallpaper])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VideoBackdropTests`
Expected: FAIL — `type 'VideoBackdrop' has no member 'pickerGroups'`

- [ ] **Step 3: Implement**

Add to `VideoBackdrop`:

```swift
    /// Menu layout for the export pickers: gradients, bundled wallpapers,
    /// then the live desktop wallpaper.
    static let pickerGroups: [(label: String, options: [VideoBackdrop])] = [
        ("Gradients", BeautifyStyle.allCases.map { .gradient($0) }),
        ("Wallpapers", bundledWallpaperNames.map { .bundled($0) }),
        ("Desktop", [.wallpaper])
    ]
```

`VideoTrimView.swift` changes — add state:

```swift
    @State private var backdrop: VideoBackdrop?
```

Give the player pane a live preview of the chosen backdrop. Replace the current `.background(Color.black)` on `AVPlayerViewWrapper` with:

```swift
                AVPlayerViewWrapper(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(backdrop == nil ? 0 : 24)
                    .background { backdropPreview }
```

And add to the view:

```swift
    @ViewBuilder
    private var backdropPreview: some View {
        switch backdrop {
        case .gradient(let style):
            style.previewGradient
        case .bundled, .wallpaper:
            if let image = backdrop?.resolveImage(for: nil) {
                Image(nsImage: image).resizable().scaledToFill().clipped()
            } else {
                Color.black
            }
        case nil:
            Color.black
        }
    }
```

In `controls`, replace the `Text("Trim").font(.headline)` header row with a header that also hosts the backdrop menu:

```swift
            HStack {
                Text("Trim")
                    .font(.headline)
                Spacer()
                Picker("Background", selection: $backdrop) {
                    Text("None").tag(VideoBackdrop?.none)
                    ForEach(VideoBackdrop.pickerGroups, id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.options) { option in
                                Text(option.title).tag(VideoBackdrop?.some(option))
                            }
                        }
                    }
                }
                .fixedSize()
                .help("Composite the export over a backdrop, like screenshot Beautify")
            }
            if backdrop != nil, case .bundled = backdrop {
                Text("Bundled wallpapers courtesy of the Recordly project.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
```

In `exportTrimmed()`, route by backdrop (replace the `TrimExporter.export` call):

```swift
        do {
            if let backdrop {
                _ = try await VideoCompositor.composite(
                    sourceURL: item.fileURL,
                    outputURL: outURL,
                    backdrop: backdrop,
                    backdropScreen: NSScreen.main,
                    cursor: nil,
                    trimStart: trimStart,
                    trimEnd: trimEnd
                )
            } else {
                _ = try await TrimExporter.export(
                    sourceURL: item.fileURL,
                    outputURL: outURL,
                    start: trimStart,
                    end: trimEnd
                )
            }
        } catch {
            exportError = error.localizedDescription
        }
```

Also change the save-panel filename suffix from `"-trimmed.mov"` to `backdrop == nil ? "-trimmed.mov" : "-styled.mov"` and allow `.mpeg4Movie` in `allowedContentTypes` alongside `.quickTimeMovie`.

`README.md` — add under the existing credits/acknowledgments section (or create `## Credits` if absent):

```markdown
- Bundled recording-backdrop wallpapers are curated from the
  [Recordly](https://github.com/webadderallorg/Recordly) project (AGPLv3).
```

- [ ] **Step 4: Run tests + build**

Run: `swift test && swift build`
Expected: full suite PASS, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snipr/Models/VideoBackdrop.swift Sources/Snipr/Views/VideoTrimView.swift README.md Tests/SniprTests/VideoBackdropTests.swift
git commit -m "feat(recording): backdrop picker and styled export in video preview"
```

---

### Task 7: End-to-end verification in the running app

**Files:** none (verification only; fix-forward anything found, committing per fix)

- [ ] **Step 1: Build and launch**

Run: `./script/build_and_run.sh run`
Expected: app launches (check `pgrep -x Snipr`).

- [ ] **Step 2: Verify cursor bake**

1. Enable Settings → Recording → "Replace cursor in recordings", size 2×, color Brass.
2. Record a small region (`snipr://record` or ⌘⇧6), move the mouse through the region, stop after ~5s.
3. Open the recording from the stack; confirm the video shows a brass arrow following a smooth path and the real cursor is absent. Confirm the "Finishing recording…" toast appeared.

- [ ] **Step 3: Verify backdrop export**

1. In the same video preview, pick Background → Wallpapers → Sonoma Horizon.
2. Confirm the live preview shows the wallpaper behind the player.
3. Export; open the result in QuickTime: wallpaper backdrop, padding, rounded corners, shadow, audio intact, trim range honored.
4. Repeat once with Background → Desktop and Background → None (None must produce the fast passthrough file).

- [ ] **Step 4: Verify the disabled path is untouched**

Toggle "Replace cursor in recordings" off, record again, confirm the real system cursor is in the file (no bake toast, instant stop-to-file).
