# Snipr — Implementation Plan

> **Goal:** ship the best lightweight macOS screenshot tool. Sub-200ms hotkey-to-pixels, Raycast-grade UI, 6 features power users actually use, single notarized binary < 30 MB, zero accounts, zero cloud, zero telemetry.
>
> **Anti-goals:** cloud upload, sharing service, accounts, iCloud sync, team workspaces. Those are CleanShot's moat — fighting for them is a losing trade.

This plan is structured for **subagent-driven phased execution**. Each phase is a self-contained brief with:
- a clear scope a single agent can hold,
- explicit non-goals so phases don't bleed,
- acceptance criteria the agent must satisfy,
- handoff notes for the next phase.

Treat phases as **gates**: do not start phase N+1 until phase N's acceptance criteria are green and committed to `main`.

---

## Operating rules for executing agents

Every dispatched subagent must follow these rules. Bake them into the dispatch prompt.

1. **Read first, write second.** Read every file you'll touch in full before editing. Skim `Prompt.md` and this `plan.md` for context.
2. **Verify the build is green at the start of your phase.** `swift build && swift test` must pass on `main` before you make any edit. If it doesn't, stop and report.
3. **Verify before claiming done.** End your work with `swift build && swift test`. Both must pass. Paste the tail of the output into your final report.
4. **Stay inside the phase scope.** Do not refactor unrelated code, do not add features outside the phase brief, do not delete features unless explicitly listed under "Cut".
5. **Minimal diffs.** Prefer edits over rewrites. Do not reformat untouched files.
6. **Commit per logical unit.** One commit per task in the phase, conventional-commit style: `feat(capture): migrate stills to ScreenCaptureKit`. Use `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
7. **Surface decisions, don't bury them.** Any non-obvious tradeoff goes in the commit body.
8. **No deprecated APIs.** From Phase 0 onward, every PR must be free of deprecated symbol warnings. Run `swift build -Xswiftc -warnings-as-errors` for capture/recording-touching changes.
9. **Strict concurrency clean.** Swift 6 strict concurrency is on. No `@unchecked Sendable` shortcuts unless documented with a `// reason:` comment.
10. **Keep this plan honest.** When a phase ships, update its status in the [Status board](#status-board) and move handoff notes to the next phase.

---

## Status board

| Phase | Title | Status | Owner | Branch |
|------:|-------|--------|-------|--------|
| 0 | Foundation reset | ⬜ not started | — | — |
| 1 | Perfect the capture moment | ⬜ blocked on 0 | — | — |
| 2 | Stack & post-capture UX | ⬜ blocked on 1 | — | — |
| 3 | Differentiator features | ⬜ blocked on 2 | — | — |
| 4 | Power features | ⬜ blocked on 3 | — | — |
| 5 | Distribution | ⬜ blocked on 4 | — | — |

Legend: ⬜ not started · 🟡 in progress · 🟢 done · 🔴 blocked

---

## Architecture target (post-refactor)

This is the shape the codebase should converge to by end of Phase 0. Phases 1–4 add files inside this skeleton.

```
SniprApp
├── SniprAppModel               (DI root, owns engines + stores + coordinator)
├── Engines/
│   ├── CaptureEngine.swift     (protocol)
│   ├── SCKCaptureEngine.swift  (ScreenCaptureKit stills)
│   ├── RecordingEngine.swift   (protocol)
│   ├── SCKRecordingEngine.swift(SCStream + audio)
│   ├── OCREngine.swift         (Vision, Phase 3)
│   └── StitchEngine.swift      (vImage row-correlation, Phase 4)
├── Stores/
│   ├── CaptureStore.swift
│   ├── OCRHistoryStore.swift   (Phase 3)
│   └── SniprPreferences.swift
├── Coordinators/
│   └── WindowCoordinator.swift (router only, target ≤ 150 lines)
├── Presenters/
│   ├── OverlayPresenter.swift  (selection + magnifier loupe)
│   ├── StackPresenter.swift
│   ├── RecordingPresenter.swift(HUD + region frame)
│   ├── PreviewPresenter.swift  (annotation editor)
│   └── PinPresenter.swift      (Phase 3)
├── Annotation/
│   ├── AnnotationTool.swift    (protocol)
│   ├── Tools/{Arrow,Rect,Ellipse,Text,Step,Highlight,Blur,Pixelate,Crop}.swift
│   └── AnnotationRenderer.swift
├── Views/                      (SwiftUI views, one per pane)
└── Support/
    ├── DisplayGeometry.swift   (NSScreen ↔ CGDirectDisplayID ↔ pixel-rect math)
    ├── HotKeyService.swift
    └── ClipboardSink.swift
```

---

## Phase 0 — Foundation reset

**Length:** ~3–4 agent-days. **Branch:** `phase-0-foundation`.

### Why this is first
Every later phase touches capture, recording, or window orchestration. Doing them on top of deprecated APIs and a 614-line god object multiplies cost. Burn the foundation down once.

### Scope (in)
1. **Migrate stills to ScreenCaptureKit.**
   - Replace `CGDisplayCreateImage` in `Sources/Snipr/Services/ScreenCaptureService.swift` with `SCScreenshotManager.captureImage(contentFilter:configuration:)`.
   - Use `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` to build the filter.
   - Preserve current `CapturedImage(pngData:pixelSize:)` return shape — encoding stays via `CGImageDestination`.
2. **Migrate recording to SCStream.**
   - Replace `AVCaptureScreenInput` in `Sources/Snipr/Services/ScreenRecordingService.swift` with `SCStream` + `SCStreamConfiguration`.
   - Single video output for now (audio added in Phase 3); preserve the `RecordedVideo(fileURL:pixelSize:duration:)` return shape.
   - Continue writing to `.mov` via `AVAssetWriter` fed by SCStream sample buffers.
3. **Extract `Support/DisplayGeometry.swift`.**
   - One place for `NSScreen ↔ CGDirectDisplayID` conversion and `displayPoints → pixelRect` scaling. Use it from both engines.
4. **Define engine protocols.**
   - `protocol CaptureEngine { func capture(displayID:rectInDisplayPoints:screen:) async throws -> CapturedImage }`
   - `protocol RecordingEngine { var isRecording: Bool { get } ; func start(...) async throws ; func stop() async throws -> RecordedVideo ; func cancel() }`
   - Inject through `SniprAppModel.init(captureEngine:recordingEngine:)`. Default to SCK implementations; tests inject fakes.
5. **Split `WindowCoordinator` into presenters.**
   - `OverlayPresenter` — owns selection overlay windows (`showCaptureOverlays`, `closeCaptureOverlays`, `completeSelection`).
   - `StackPresenter` — owns thumbnail panel, hover/pin state, auto-hide task.
   - `RecordingPresenter` — owns recording HUD + region frame panels, recording lifecycle wiring.
   - `PreviewPresenter` — owns preview/annotation windows.
   - `WindowCoordinator` retains only routing (`startCaptureArea`, `execute(_:)`) and holds the four presenters. Target ≤ 150 lines.
6. **Fix the FourCharCode endian double-swap.**
   - `Sources/Snipr/Services/HotKeyService.swift:89` — drop `UInt32(bigEndian:)`. `OSType(signature: "SNPR".fourCharCode)` is sufficient.
7. **Replace permission polling.**
   - `Sources/Snipr/Views/ContentView.swift:36` 1-second `Task` loop → observe `NSApplication.didBecomeActiveNotification` and recheck permissions.
8. **Tests.**
   - New `Tests/SniprTests/` files: `OverlayPresenterTests`, `StackPresenterTests`, `RecordingPresenterTests`, `PreviewPresenterTests`. Use fake engines.
   - Keep existing `CaptureStoreTests`, `SniprPreferencesTests`, `SniprCommandTests`, `AnnotationRendererTests` green.

### Scope (out, deferred)
- Audio capture (Phase 3).
- Window picker UI (Phase 1).
- Magnifier loupe (Phase 1).
- Stack visual redesign (Phase 2).
- Any new annotation tools (Phase 3).
- Removing the "Settings" tab inside `ContentView` (Phase 1).

### Acceptance criteria
- [ ] `swift build -Xswiftc -warnings-as-errors` produces zero deprecation warnings.
- [ ] No references to `CGDisplayCreateImage` or `AVCaptureScreenInput` remain in `Sources/`.
- [ ] `swift test` passes; new presenter tests exercise at least the happy path of each presenter via fake engines.
- [ ] `WindowCoordinator.swift` ≤ 150 lines.
- [ ] `Sources/Snipr/Support/DisplayGeometry.swift` exists and is the only place that scales display-points to pixel-rects.
- [ ] HotKey signature is `0x534E5052` ("SNPR" big-end natural) — sanity test in `Tests/SniprTests/HotKeyServiceTests.swift`.
- [ ] Manual smoke test: `⌘⇧4` capture, `⌘⇧6` record, both write files into `~/Library/Application Support/Snipr/Captures/`.

### Files to touch
- Edit: `Sources/Snipr/Services/ScreenCaptureService.swift`, `Sources/Snipr/Services/ScreenRecordingService.swift`, `Sources/Snipr/Services/WindowCoordinator.swift`, `Sources/Snipr/Services/HotKeyService.swift`, `Sources/Snipr/App/SniprAppModel.swift`, `Sources/Snipr/Views/ContentView.swift`.
- Add: `Sources/Snipr/Support/DisplayGeometry.swift`, `Sources/Snipr/Engines/{CaptureEngine,SCKCaptureEngine,RecordingEngine,SCKRecordingEngine}.swift`, `Sources/Snipr/Coordinators/WindowCoordinator.swift` (move from `Services/`), `Sources/Snipr/Presenters/{Overlay,Stack,Recording,Preview}Presenter.swift`.
- Tests add: `Tests/SniprTests/{OverlayPresenter,StackPresenter,RecordingPresenter,PreviewPresenter,HotKeyService}Tests.swift`.

### Handoff to Phase 1
- Engine protocols in place — Phase 1 wires window-capture filter through the same `CaptureEngine`.
- `OverlayPresenter` is the only thing that opens selection windows — Phase 1 adds magnifier + snapping inside it without touching the coordinator.

---

## Phase 1 — Perfect the capture moment

**Length:** ~1 week. **Branch:** `phase-1-capture-moment`. **Depends on:** Phase 0 merged.

### Goal
The half-second between hotkey press and pixels in the clipboard feels better than CleanShot's. This is the brand.

### Scope (in)
1. **Magnifier loupe** during selection.
   - 8× zoom of pixels around the cursor, ~120×120 px window, follows cursor with a 12 px offset.
   - Live RGB hex readout.
   - Implemented as a child `NSView` of the overlay; uses cached display image refreshed every 16 ms.
2. **Crosshair coordinates** — show "x, y" alongside "w × h" already drawn in `CaptureSelectionNSView.drawDimensions`.
3. **Edge / window snapping.**
   - On selection start, fetch `SCShareableContent.windows` once; convert their bounds to display points.
   - While dragging with `⌥` held, snap selection edges to the nearest window edge within 8 px.
4. **Last-region recall.**
   - `WindowCoordinator` remembers the last (display, rect) tuple in memory.
   - New action `SniprHotKeyAction.captureLastRegion` (default `⌘⇧5` repurposed, or new combo). Holding `⇧` after pressing the capture hotkey reuses last region.
5. **Numerical entry.** During selection, pressing `T` opens a small panel for typing exact `WxH+x+y`.
6. **Window capture mode.**
   - Dedicated overlay that fetches `SCShareableContent.windows`, highlights window under cursor with a tint and label (app name + title), click captures via SCK content filter for that window.
   - Replaces the placeholder alert in `WindowCoordinator.showWindowCaptureComingSoon`.
7. **Auto-clipboard toggle** + **clipboard-only mode.**
   - Add `SniprPreferences.copyToClipboardOnCapture: Bool` (default true).
   - Add `SniprPreferences.saveToDiskOnCapture: Bool` (default true). When false, capture flows through `ClipboardSink` only and is not added to the stack.
8. **Output format.**
   - `SniprPreferences.captureFormat: CaptureFormat` enum `{ png, jpeg(quality), heic(quality) }`.
   - Encode in `CapturedImage` consumer based on preference; default PNG.
9. **Auto-naming with token templates.**
   - `SniprPreferences.captureFilenameTemplate: String` default `"Snipr {date} {time}"`.
   - Tokens: `{date}`, `{time}`, `{app}`, `{window}`, `{w}`, `{h}`, `{seq}`.
10. **Cancel anywhere.** Right-click during selection cancels (Esc already works).
11. **Cut placeholders.** Remove `showWindowCaptureComingSoon`. Remove the in-app "Settings" tab from `ContentView` — only the standard `Settings { }` scene survives.

### Scope (out, deferred)
- OCR (Phase 3).
- Stack visual redesign (Phase 2).
- Recording audio / cursor ripples (Phase 3).
- Pin (Phase 3).
- Annotations beyond what already exists (Phase 3).

### Acceptance criteria
- [ ] `swift build -Xswiftc -warnings-as-errors` clean.
- [ ] `swift test` passes; new tests for `ClipboardSink`, `SniprPreferences` filename-template expansion, `OverlayPresenter` snap math.
- [ ] Manual: time-to-pixel ≤ 200 ms p50 measured with `os_signpost` between hotkey handler entry and `pngData.write` return on a 13" MBP. Add a test target or a one-off `MeasureCapture.swift` script under `script/`.
- [ ] Manual: window capture works on multi-display, hover highlight is accurate.
- [ ] Manual: loupe is pixel-accurate (verify by sampling a known color and confirming hex readout).
- [ ] No deprecated symbol warnings.

### Files to touch
- Edit: `Sources/Snipr/Presenters/OverlayPresenter.swift`, `Sources/Snipr/Views/CaptureOverlayView.swift`, `Sources/Snipr/Models/SniprPreferences.swift`, `Sources/Snipr/Engines/SCKCaptureEngine.swift`, `Sources/Snipr/Coordinators/WindowCoordinator.swift`, `Sources/Snipr/Views/ContentView.swift`, `Sources/Snipr/App/SniprApp.swift`.
- Add: `Sources/Snipr/Support/ClipboardSink.swift`, `Sources/Snipr/Support/CaptureFilenameTemplate.swift`, `Sources/Snipr/Views/MagnifierLoupeView.swift`, `Sources/Snipr/Views/WindowPickerOverlayView.swift`, `Sources/Snipr/Views/NumericalEntryPanel.swift`, `script/MeasureCapture.swift`.

### Handoff to Phase 2
- Stack now receives potentially many captures fast — Phase 2's pile visual must handle bursts.
- `ClipboardSink` exists for Phase 2's "Copy" quick-action.

---

## Phase 2 — Stack & post-capture UX

**Length:** ~1 week. **Branch:** `phase-2-stack-ux`. **Depends on:** Phase 1 merged.

### Goal
The stack is what people remember. Make it match the blueprint's "physical pile" + Raycast-style hover sidebar, with bundle drag-out and batch actions.

### Scope (in)
1. **Pile visual.**
   - Replace `LazyVStack` in `ThumbnailStackView.swift` with a custom layout that overlays cards with 3–5 px offset and 0.5–1.5° rotation alternating per item. Cap visible cards at 6.
2. **Hover expansion.**
   - On hover, animate pile into a vertical sidebar (Raycast-style, thin border, heavy `.ultraThinMaterial` blur).
   - Keyboard arrows navigate; `Enter` annotates; `⌘C` copies; `Del` deletes; `⌘P` pins.
3. **Multi-select.**
   - `⌘`-click toggles, `⇧`-click ranges. Selected cards get a 2 px accent border.
4. **Bundle drag-out.**
   - `onDrag` returns an array of `NSItemProvider` matching the selection (or all visible items if none selected).
5. **Quick-action buttons** on hover per card: Copy, Save, Reveal, Pin (placeholder until Phase 3), Annotate, Delete.
6. **Batch actions** in stack header menu:
   - Save All to Folder (`NSOpenPanel` directory chooser).
   - Combine into PDF (uses `PDFKit`).
   - Stitch Vertically (uses `vImage` for top-aligned concat — note this is the dumb concat, not the Phase 4 scrolling-stitch).
   - Clear Stack (already exists).
7. **Auto-hide refinements.**
   - Pause auto-hide while any preview window is key.
   - `showThumbnailStack` hotkey restores even if pinned closed.

### Scope (out, deferred)
- Pin floating reference window (Phase 3).
- OCR (Phase 3).
- Annotation tool expansion (Phase 3).
- Scrolling capture (Phase 4).

### Acceptance criteria
- [ ] `swift build -Xswiftc -warnings-as-errors` clean.
- [ ] `swift test` passes; new tests for batch PDF combine and stitch-vertical helpers.
- [ ] Manual: drag 5 selected items into Finder/Slack/Discord — all 5 land.
- [ ] Manual: full keyboard workflow — capture, navigate stack with arrows, copy with `⌘C`, annotate with Enter, delete with Del.
- [ ] Manual: pile visual matches blueprint within reasonable judgment (record a 5-second screen capture in the PR description).
- [ ] No regressions: existing pin/auto-hide preferences still respected.

### Files to touch
- Edit: `Sources/Snipr/Views/ThumbnailStackView.swift`, `Sources/Snipr/Presenters/StackPresenter.swift`, `Sources/Snipr/Stores/CaptureStore.swift` (add `selectedIDs` if needed), `Sources/Snipr/Models/SniprPreferences.swift`.
- Add: `Sources/Snipr/Views/ThumbnailPileLayout.swift`, `Sources/Snipr/Views/ThumbnailExpandedSidebar.swift`, `Sources/Snipr/Support/PDFCombiner.swift`, `Sources/Snipr/Support/VerticalStitcher.swift`.

### Handoff to Phase 3
- Pin quick-action button is wired but inert — Phase 3 implements `PinPresenter`.
- Preview window (annotation editor) will gain Text/Step/Pixelate/Highlight/Crop tools — `PreviewPresenter` shape stays the same.

---

## Phase 3 — Differentiator features

**Length:** ~1.5 weeks. **Branch:** `phase-3-differentiators`. **Depends on:** Phase 2 merged.

### Goal
The four features people switch tools for: OCR, Pin, expanded annotations, recording audio.

### Scope (in)
1. **OCR.**
   - `OCREngine` protocol; `VisionOCREngine` implementation using `VNRecognizeTextRequest` with `.accurate` recognition.
   - New action `SniprHotKeyAction.ocr` default `⌘⇧O`. Reuses selection overlay, on commit runs OCR on the captured pixels and writes recognized text to clipboard via `ClipboardSink`. No popup. Subtle `NSHapticFeedbackManager` cue.
   - `OCRHistoryStore` persists last 20 entries to UserDefaults. Surface in command palette as "Show OCR History" (re-copies on selection).
2. **Pin (floating reference window).**
   - `PinPresenter` creates a borderless, always-on-top, `.fullScreenAuxiliary`, draggable `NSPanel` per pinned image.
   - Scroll wheel adjusts alpha (0.2…1.0). Use a local `NSEvent` monitor for `.scrollWheel` while the panel is key/hovered.
   - Right-click menu: "Unpin", "Copy", "Save", "Always on Top toggle".
3. **Annotation refactor + new tools.**
   - Refactor `AnnotationLayer` enum to `AnnotationTool` protocol with per-tool draw + hit-test + serialization.
   - Implement: **Text** (NSTextView in canvas, system font picker, sized handles), **Step counter** (auto-incrementing numbered badges), **Pixelate** (`CIFilter.pixellate`), **Highlight** (multiply blend), **Crop** (destructive, applied on save).
   - Migrate the existing Arrow / Rectangle / Ellipse / Blur tools onto the protocol.
   - Maintain backward-compat for any persisted annotations (none currently — annotations are not persisted).
4. **Recording extras.**
   - Mic toggle in `RecordingHUDView`, starts the default input device via `SCStreamConfiguration.capturesAudio = true` plus a separate `AVCaptureDeviceInput` for mic.
   - System audio toggle (SCK).
   - Cursor click ripples — overlay layer composited at write time using mouse-down events captured via a global event tap during recording.
   - Trim handles in preview window for video items: simple in/out range, exports via `AVAssetExportSession`.
5. **Color picker / pixel sampler.**
   - New action `SniprHotKeyAction.colorPick` default `⌘⇧C` (verify no conflict with copy in any focused field — restrict to global hotkey context only).
   - Loupe + click captures hex / RGB / HSL to clipboard with format chosen in preferences.

### Scope (out, deferred)
- Scrolling capture (Phase 4).
- Quick share menu (Phase 4).
- Smart folders / chained workflows (Phase 4).

### Acceptance criteria
- [ ] `swift build -Xswiftc -warnings-as-errors` clean.
- [ ] `swift test` passes; new tests:
  - `OCREngineTests` (mocked Vision response handler — or integration test against a fixed PNG fixture under `Tests/Fixtures/`).
  - `PinPresenterTests` (alpha math, persistence of last opacity).
  - `AnnotationToolTests` (per-tool draw + hit-test).
  - `TrimExportTests` (range produces expected duration).
- [ ] Manual: OCR a 1080p region of code, paste into a text editor, verify accuracy and < 500 ms latency.
- [ ] Manual: pin a screenshot, scroll to 30%, drag over another window, verify always-on-top and opacity.
- [ ] Manual: every annotation tool round-trips through "annotate → copy → paste into Preview.app" without artifacts.
- [ ] Manual: record a 10 s clip with mic + system audio, verify both are present in the resulting `.mov`.

### Files to touch
- Edit: `Sources/Snipr/Engines/SCKRecordingEngine.swift`, `Sources/Snipr/Views/RecordingHUDView.swift`, `Sources/Snipr/Views/PreviewWindowView.swift`, `Sources/Snipr/Models/AnnotationLayer.swift` (rename + refactor), `Sources/Snipr/Support/AnnotationRenderer.swift`, `Sources/Snipr/Models/SniprPreferences.swift`, `Sources/Snipr/Coordinators/WindowCoordinator.swift`.
- Add: `Sources/Snipr/Engines/{OCREngine,VisionOCREngine}.swift`, `Sources/Snipr/Stores/OCRHistoryStore.swift`, `Sources/Snipr/Presenters/PinPresenter.swift`, `Sources/Snipr/Annotation/AnnotationTool.swift`, `Sources/Snipr/Annotation/Tools/{Arrow,Rect,Ellipse,Text,Step,Highlight,Blur,Pixelate,Crop}.swift`, `Sources/Snipr/Support/CursorRippleRecorder.swift`, `Sources/Snipr/Support/TrimExporter.swift`, `Sources/Snipr/Support/ColorPicker.swift`.

### Handoff to Phase 4
- `OCREngine` exists — Phase 4's chained workflows ("capture → OCR → translate") plug into it.
- `Pin` exists — quick share will reuse the floating-panel pattern.

---

## Phase 4 — Power features

**Length:** ~2 weeks. **Branch:** `phase-4-power`. **Depends on:** Phase 3 merged.

### Goal
The moat. Scrolling capture, quick share, smart folders, chained workflows.

### Scope (in)
1. **Scrolling capture.**
   - `StitchEngine` protocol; `VisionStitchEngine` implementation.
   - Flow: user invokes command, selects a window (reuse Phase 1 window picker), then scrolls inside it. We capture frames at 8–10 fps via `SCStream` against that window's content filter.
   - Use `vImage` row-correlation between consecutive frames to find vertical overlap; reject frames where overlap < 20 % (likely scrolled too fast).
   - Composite into a single tall `CGImage` written through the same `CapturedImage` path so it lands in the stack.
   - Minimalist top-of-screen progress bar showing captured vertical pixels.
2. **Quick share menu.**
   - Per-thumbnail "Share" button → `NSSharingServicePicker` (Mail, Messages, AirDrop, system Share). Explicitly **no** built-in cloud upload.
3. **Smart folders.**
   - `SniprPreferences.smartFolderRules: [SmartFolderRule]` — each rule maps app-name pattern → destination subfolder under the captures root.
   - Capture flow consults rules; settings UI lets the user add/remove.
4. **Chained workflows / command palette macros.**
   - Define `Workflow` as a sequence of `WorkflowStep` cases: `capture`, `ocr`, `translate(toLocale:)`, `clipboard`, `save`, `pin`, `annotate`.
   - Translate uses Apple's `Translation` framework (macOS 14.4+). Gracefully no-op on older OS.
   - Built-in workflows: "Capture → OCR → Clipboard", "Capture → OCR → Translate (system locale) → Clipboard", "Capture → Pin".
   - Add to command palette under their own section.
5. **Polish pass on prefs UI.**
   - Reorganize Settings into tabs: General, Capture, Recording, Annotation, Hotkeys, Storage, Advanced.

### Scope (out, deferred)
- App bundle / signing / Sparkle / Homebrew (Phase 5).

### Acceptance criteria
- [ ] `swift build -Xswiftc -warnings-as-errors` clean.
- [ ] `swift test` passes; new tests:
  - `VisionStitchEngineTests` (offline test: feed two known overlapping `CGImage`s, verify stitched height equals sum minus overlap).
  - `SmartFolderRuleTests` (pattern matching).
  - `WorkflowExecutorTests` (mock engines, verify steps run in order, errors short-circuit).
- [ ] Manual: scrolling capture works on Safari, VS Code, and Notion (the three canonical hard cases). 1000-pixel vertical scroll captures cleanly without visible seams.
- [ ] Manual: quick share opens `NSSharingServicePicker` with the file as the payload.
- [ ] Manual: smart folder routes captures from "Safari" into `~/.../Snipr/Captures/Safari/`.
- [ ] Manual: "Capture → OCR → Translate → Clipboard" yields translated text on clipboard end-to-end.

### Files to touch
- Edit: `Sources/Snipr/Models/SniprPreferences.swift`, `Sources/Snipr/Coordinators/WindowCoordinator.swift`, `Sources/Snipr/Stores/CaptureStore.swift` (smart-folder routing).
- Add: `Sources/Snipr/Engines/{StitchEngine,VisionStitchEngine}.swift`, `Sources/Snipr/Engines/TranslationEngine.swift`, `Sources/Snipr/Workflows/{Workflow,WorkflowStep,WorkflowExecutor}.swift`, `Sources/Snipr/Models/SmartFolderRule.swift`, `Sources/Snipr/Views/ScrollingCaptureProgressBar.swift`, `Sources/Snipr/Views/Settings/{General,Capture,Recording,Annotation,Hotkeys,Storage,Advanced}Tab.swift`.

### Handoff to Phase 5
- Feature surface is frozen — Phase 5 only does packaging, signing, distribution.

---

## Phase 5 — Distribution

**Length:** ~3–4 days. **Branch:** `phase-5-distribution`. **Depends on:** Phase 4 merged.

### Goal
People can actually install Snipr.

### Scope (in)
1. **Move from SwiftPM executable to Xcode app target.**
   - Generate `.xcodeproj` (manual, kept in repo) with proper `.app` bundle, entitlements (screen recording, microphone, accessibility for global hotkeys), and `Info.plist` usage strings.
   - Keep SwiftPM target for tests if practical; otherwise migrate tests into the Xcode project.
2. **Sparkle integration** for auto-update (`https://sparkle-project.org`). Self-hosted appcast on a static URL (e.g., GitHub Pages off this repo).
3. **Code sign + notarize.**
   - CI script under `script/` that signs with Developer ID, notarizes via `xcrun notarytool`, staples, and produces a `.dmg`.
4. **DMG packaging** with custom background and `/Applications` symlink.
5. **Homebrew cask** in a separate `homebrew-snipr` tap (or add to the main repo under `Casks/`).
6. **Local-only crash reporting**, opt-in. Writes `~/Library/Logs/Snipr/crash-*.log`. No network. No telemetry by default.
7. **Landing page** under `docs/`: 1 GIF, 5 features, download button. Push to GitHub Pages.

### Scope (out)
- Mac App Store submission (separate effort, post-1.0).
- Localization (post-1.0).

### Acceptance criteria
- [ ] `script/release.sh <version>` produces a signed, notarized, stapled `.dmg`.
- [ ] Installing from the DMG, launching, granting permissions, and capturing works end-to-end on macOS 14, 15, and 16 (test on the latest two; 14 manual smoke).
- [ ] `brew install --cask snipr` succeeds against the published tap.
- [ ] App bundle size ≤ 30 MB (uncompressed).
- [ ] Idle memory ≤ 60 MB measured via `Activity Monitor` after 1 minute idle.
- [ ] Cold launch ≤ 1 s on a 13" MBP M-series.

### Files to touch
- Add: `Snipr.xcodeproj/`, `script/release.sh`, `script/notarize.sh`, `script/build-dmg.sh`, `docs/index.html`, `docs/snipr.gif`, `Casks/snipr.rb` (or separate tap).

---

## Acceptance bar for v1.0 (overall)

These are the cross-phase quality gates verified at end of Phase 5.

- Time-to-pixel ≤ 200 ms p50.
- Idle memory ≤ 60 MB.
- App bundle ≤ 30 MB.
- Cold launch ≤ 1 s.
- Zero deprecated APIs.
- ≥ 70 % test coverage on engines + stores.
- Works on macOS 14, 15, 16.
- Notarized, signed, available via Homebrew.
- Zero telemetry. Zero accounts. Zero cloud calls by default.

---

## How to dispatch a phase to a subagent

Use `Agent` with `subagent_type: general-purpose` (or `everything-claude-code:planner` for re-planning). Bake this template into the dispatch prompt:

```
You are executing Phase <N> of /Users/graysonpatterson/Grayson/Snipr/plan.md.
Read plan.md in full before doing anything. Read every file under "Files to touch"
in full before editing it.

Operating rules: see "Operating rules for executing agents" in plan.md. Follow them.

Your scope is exactly the bullets under "Scope (in)" for Phase <N>. Do not pull
items from "Scope (out)". Do not refactor unrelated code.

End your work with `swift build -Xswiftc -warnings-as-errors && swift test`. Both
must pass. Paste the tail of the output into your final report.

Final report format:
1. Files changed (list).
2. Tests added (list).
3. Build + test output tail.
4. Manual-verification steps you ran (or "could not run, requires user").
5. Anything you punted on, with reasons.
```

Run phases sequentially. Do not parallelize across phases — they have hard dependencies. Within a phase, scope items can sometimes be parallelized across subagents, but only if the agent dispatching them has read the phase brief and confirms the items don't touch overlapping files.
