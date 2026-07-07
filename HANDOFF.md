# Snipr — Handoff for Phase 5 (Distribution) and Phase 4.5 (Scrolling Capture)

**Last update:** 2026-07-07. Phases 0–4 complete, Phase 4.5 (scrolling capture) landed via the display-filter frame source (`8d0a416`), and Phase 5 distribution is live: signed/notarized/stapled DMG plus Sparkle auto-update — see `RELEASING.md`, releases at https://github.com/Cryptic0011/Snipr. 163 tests pass. Build clean with `swift build -Xswiftc -warnings-as-errors`.

> Sections below dated 2026-05-07 predate Phase 4.5/5; where they conflict with the line above (test counts, scrolling capture disabled, "no remote"), the line above wins.

This document gives a fresh agent enough context to pick up the project without reading every prior commit. It complements `plan.md` (the master plan) and `Prompt.md` (the original product blueprint).

---

## Current state

- **`main`** is the integration branch. Every phase has been fast-forwarded into it.
- **Build:** `swift build -Xswiftc -warnings-as-errors` is green.
- **Tests:** `swift test` → 127 tests, 0 failures.
- **No deprecated APIs.** No `@unchecked Sendable` without a documented `// reason:` comment.
- **No active branches** at the time of writing. New phases get a `phase-N-<slug>` branch.

```
SniprApp
├── App/                        — SniprApp + AppModel + AppDelegate
├── Coordinators/               — WindowCoordinator (router)
├── Presenters/                 — Overlay, Stack, Recording, Preview, CaptureFlow,
│                                 CommandPalette, CaptureToolbar, Pin, ScrollingCapture
├── Engines/                    — Capture (SCK stills), Recording (SCStream),
│                                 OCR (Vision), Stitch (vImage), Translation (stub),
│                                 ScrollingFrameCollector
├── Annotation/Tools/           — Arrow, Rect, Ellipse, Blur, Pixelate, Highlight,
│                                 Text, Step, Crop (protocol-based)
├── Stores/                     — CaptureStore, OCRHistoryStore, SniprPreferences
├── Models/                     — HotKeyBinding, SniprCommand, SmartFolderRule,
│                                 CaptureFormat, AnnotationLayer
├── Workflows/                  — Workflow + WorkflowStep + Executor
├── Views/                      — including Settings/{General,Capture,Recording,
│                                 Annotation,Hotkeys,Storage,Advanced}Tab.swift
└── Support/                    — DisplayGeometry, ClipboardSink, ColorPicker,
                                  ShareMenu, PDFCombiner, VerticalStitcher,
                                  CaptureFilenameTemplate, EdgeSnap, TrimExporter
```

## What ships today (Phases 0–4)

### Capture
- ScreenCaptureKit stills (`SCScreenshotManager.captureImage`).
- Selection overlay with magnifier loupe (8× zoom + RGB hex readout), live coordinates, window-edge snapping with ⌥, numerical entry with `T`, right-click + Esc cancel.
- Window picker mode (`⌘⇧5` toolbar → Capture Window) with macOS-Screenshot-app-style dim layer + blue tint + white edge + camera glyph label.
- Full-screen capture, last-region recall, format prefs (PNG/JPEG/HEIC + quality), filename templates with `{date} {time} {app} {window} {w} {h} {seq}` tokens, clipboard-only mode.

### Recording
- SCStream-driven `.mov` recording via `AVAssetWriter`. System-audio toggle wired through `SCStreamConfiguration.capturesAudio`. Recording HUD + dimmed region frame (region frame is excluded from the recording via `NSWindow.sharingType = .none`). Cancel + stop wired.
- Mic capture is still a punt — Settings → Recording explicitly says "Microphone capture is not available yet."
- Cursor click ripples are a punt — needs a post-pass `AVVideoComposition` over the stopped asset.
- Trim view with in/out sliders + `AVAssetExportSession` export.

### Stack
- Pile visual (alternating 0.5–1.5° tilt, 3–5 px offset, capped at 6 visible).
- Hover expansion to a Raycast-style sidebar with `.ultraThinMaterial`. Real cursor-position check (`NSEvent.mouseLocation`) prevents the SwiftUI `.onHover(false)` spurious collapse during the resize animation.
- Auto-hide cancellation race fixed: cancelled `Task.sleep` no longer falls through to `hide()`.
- Multi-select (⌘-click toggle, ⇧-click range, accent border).
- Bundle drag-out via dedicated grip glyph.
- Per-row hover quick actions: Copy, Save, Reveal, Pin, Annotate, Share, Delete.
- Header batch menu: Save All to Folder, Combine into PDF, Stitch Vertically (dumb concat), Clear Stack.
- `showStack` hotkey force-restores even if pinned-closed.
- Preview-aware auto-hide pauses while a preview window is key.

### Annotation
- Tool protocol with: Arrow, Rect, Ellipse, Blur, Pixelate, Highlight, Text (sheet entry, system font picker), Step (auto-incrementing badges), Crop (destructive on save).
- Settings → Annotation lists tools and exposes Color Output Format.

### OCR / Pin / Color picker
- OCR: `⌘⇧O` → Vision `.accurate` → clipboard write + haptic, no popup. "Show OCR History" surfaces last 20 in the palette.
- Pin: floating `.fullScreenAuxiliary` panel per pinned image, scroll-wheel opacity (0.2…1.0 clamp), right-click menu.
- Color picker: `⌘⇧C` loupe → click samples pixel → hex/RGB/HSL via prefs.

### Workflows / Smart folders / Share
- `Workflow` / `WorkflowStep` / `WorkflowExecutor` with mockable seams. Built-ins: "Capture → OCR → Clipboard" (works), "Capture → Pin" (works), "Capture → OCR → Translate → Clipboard" (registered as `(preview)`, alerts on selection).
- Smart folders: `SmartFolderRule` matches app-name pattern → subfolder under captures root.
- Quick share via `NSSharingServicePicker` from stack hover and preview toolbars. **No cloud upload by design.**

### Settings
- Tabbed: General / Capture / Recording / Annotation / Hotkeys / Storage / Advanced. Every preference reachable.

### Hotkeys (defaults)
- ⌘⇧4 capture area · ⌘⇧5 capture toolbar · ⌘⇧6 record area · ⌘⇧Space command palette · ⌘⇧S show stack · ⌘⌥Esc hide stack · ⌘⌫ clear stack · ⌘⇧O OCR · ⌘⇧C color pick · ⌘⌥S open Snipr · ⌘⇧W capture window (disabled by default) · ⌘⇧7 last region (disabled by default).

---

## Known issues / explicit punts

1. **Scrolling capture (`SniprHotKeyAction.scrollingCapture`)** — disabled at the user surface. SCK's `SCContentFilter(desktopIndependentWindow:)` stream terminates ~150ms after `startCapture()` with `SCStreamErrorDomain Code=-3815 "Failed to find any displays or windows to capture"`. Reproduces on every attempt, even after re-fetching the SCWindow at filter-creation time and using `minimumFrameInterval = CMTime(value: 1, timescale: 30)` + `queueDepth = 5`. **The kernel is correct** (`VisionStitchEngine` is unit-tested with overlap recovery within ±5 rows). What needs a rewrite is the frame source — see Phase 4.5 brief below. Engine + presenter + tests are retained intact; flipping `HotKeyDefaults.bindings[.scrollingCapture].isEnabled = true`, restoring `isAvailable`, and re-adding the `SniprCommand` palette entry will surface the feature again.

2. **Translate workflow step** — Apple's `Translation` framework on macOS is presentation-driven (`TranslationSession` requires a SwiftUI host with `.translationTask`). The current `PendingTranslationEngine` throws `unsupportedOnThisOS`. The "Capture → OCR → Translate → Clipboard" workflow is in the palette as `(preview)` and surfaces an alert. Other workflows work end-to-end.

3. **Mic capture during recording** — punt from Phase 3. Mixing mic + system audio in one `AVAssetWriter` requires an audio mixer node and a Microphone usage-description Info.plist that SwiftPM doesn't generate. Phase 5 (Xcode app target with proper entitlements) unblocks this.

4. **Cursor click ripples during recording** — punt from Phase 3. Needs an `AVVideoComposition` post-pass over the stopped asset, or per-frame `CIFilter` chain wired into the writer.

5. **In-memory selection state in stack** — `selection: Set<UUID>` is `@State`, not persisted. Intentional: selection should not survive an app restart.

6. **One legacy field**: `RecordingPresenter.capturesSystemAudio` is now redundant since `preferences.recordSystemAudio` is the source of truth. Left in place as a fallback for the legacy initializer; safe to remove with a small refactor.

---

## How to run / verify locally

```bash
cd /Users/graysonpatterson/Grayson/Snipr

# Build with strict warnings
swift build -Xswiftc -warnings-as-errors

# Run the test suite
swift test

# Launch the app
swift run

# Strip TCC by rebuilding (each build changes the ad-hoc CDHash, so TCC re-prompts)
swift build && swift run
```

If permissions need a hard reset, the app's ad-hoc signing identifier rotates every build — TCC sees each rebuild as a new app and re-prompts. Avoid `tccutil reset` system-wide; it nukes every other app's permissions too.

---

## Phase 5 — Distribution (next phase)

**Branch suggestion:** `phase-5-distribution`. **Length:** ~3–4 agent-days.

The full brief is in `plan.md` under "Phase 5 — Distribution". Highlights:

1. **Move from SwiftPM executable to Xcode app target.** Generate `Snipr.xcodeproj` (kept in repo). Proper `.app` bundle, entitlements (screen recording, microphone for the still-pending Phase 3 mic capture, accessibility for global hotkeys), Info.plist usage strings. Keep SwiftPM target for tests if practical, otherwise migrate tests into the Xcode project.
2. **Sparkle integration** for auto-update. Self-hosted appcast on a static URL.
3. **Code sign + notarize.** `script/release.sh <version>` should produce a signed, stapled `.dmg`. Use `xcrun notarytool`.
4. **DMG packaging** with custom background and `/Applications` symlink.
5. **Homebrew cask.**
6. **Local-only crash reporting**, opt-in. Writes `~/Library/Logs/Snipr/crash-*.log`. No telemetry.
7. **Landing page** in `docs/`. 1 GIF, 5 features, download button. GitHub Pages.

Acceptance gate: `script/release.sh <version>` produces a signed/notarized/stapled `.dmg`. Installing from it works on macOS 14, 15, 16. Bundle ≤ 30 MB, idle memory ≤ 60 MB, cold launch ≤ 1 s.

**Phase 5 dispatch prompt template** is at the bottom of `plan.md` ("How to dispatch a phase to a subagent").

---

## Phase 4.5 — Scrolling Capture (post-Phase 5)

**Why this is a half-phase, not part of 5:** It's invisible to distribution and re-uses code already on disk. Don't merge into Phase 5 — distribution gets blocked on every SCK experiment.

### What's already in place
- `Sources/Snipr/Engines/StitchEngine.swift` — protocol with `noFrames`, `unequalWidths`, `allFramesRejected` errors.
- `Sources/Snipr/Engines/VisionStitchEngine.swift` — vImage row-correlation kernel. Walks frames in order, finds best vertical overlap with mean-absolute-error ≤ 6 (per-pixel byte difference), rejects pairs where `overlap < 20% * frame.height`. Composites kept frames into one tall `CGImage`. **Tested** (`Tests/SniprTests/VisionStitchEngineTests.swift`, 5 cases).
- `Sources/Snipr/Engines/ScrollingFrameCollector.swift` — SCStream-driven frame collector (currently broken, see below).
- `Sources/Snipr/Presenters/ScrollingCapturePresenter.swift` — orchestration, progress HUD show/hide, store/encode.
- `Sources/Snipr/Views/ScrollingCaptureProgressBar.swift` — progress UI with Stop / Cancel.
- `Sources/Snipr/Coordinators/WindowCoordinator.swift` — `startScrollingCapture()` enters a "scrolling mode" that retargets the picker `onWindowPicked` callback to `startScrolling(entry:)` instead of single-shot capture.

### Why the current path fails
`SCContentFilter(desktopIndependentWindow:)` is documented as "capture this window's content even if occluded." Empirically with our config the **stream** terminates within ~150 ms of `startCapture()` with `-3815`. We get 1–4 frames then `didStopWithError` fires. We tried:

- Re-fetching `SCWindow` from a fresh `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` immediately before constructing the filter.
- Bumping `minimumFrameInterval` from `CMTime(1, 10)` (10 fps) to `CMTime(1, 30)` (30 fps).
- Setting `queueDepth = 5` (default is 3).
- Trying `SCContentFilter(display:includingWindows:)` — Swift-obsoleted as of Swift 3, so unavailable.

### The recommended Phase 4.5 architecture

Switch the frame source to **full-display capture + per-frame crop**:

1. In `ScrollingFrameCollector.start(scWindow:)`, build the filter as `SCContentFilter(display: scDisplay, excludingWindows: <Snipr's own windows>)` — this is the same filter shape the stable recording engine uses (see `Sources/Snipr/Engines/SCKRecordingEngine.swift`).
2. Set `configuration.sourceRect` to the target window's pixel-rect (computed via `DisplayGeometry.pixelRect(forDisplayPointsRect:displayID:screen:)`). Or skip `sourceRect` and crop in the sample-buffer adapter.
3. Track the target window's frame each tick: read `scWindow.frame` from a fresh `SCShareableContent` poll once a second (or just compute it from `CGWindowListCopyWindowInfo` for cheap polling). If the user moves the window mid-scroll, frames track. Stop the stream if the window disappears.
4. Each frame's relevant pixels are cropped to the window's current rect at sample-buffer-arrival time (cheap CIImage crop).
5. Pass cropped frames to the existing `VisionStitchEngine.stitch(frames:)` — no kernel changes required.

Re-enable the user surface with three small edits:
- `Models/HotKeyBinding.swift` → `isAvailable: Bool { true }` (drop the `.scrollingCapture` exception) and `HotKeyDefaults.bindings[.scrollingCapture].isEnabled = true`.
- `Models/SniprCommand.swift` → restore the omitted palette entry (the `id`/title/subtitle/systemImage/shortcut block is in the comment that replaces it).

### Acceptance criteria for Phase 4.5
- Stream stays alive for ≥ 30 s while user scrolls inside the target window.
- Stitched output of 1000+ vertical pixels on Safari, VS Code, and Notion has no visible seams (record a short demo in the PR).
- All 127 existing tests stay green; new tests cover the crop math.
- No new deprecated APIs, no new unchecked Sendable.

---

## Important conventions a fresh agent should respect

1. **Read `plan.md` "Operating rules for executing agents" before any edit.** They're non-negotiable.
2. **Build with `swift build -Xswiftc -warnings-as-errors`** before claiming done.
3. **One commit per logical task.** Conventional-commit style. Co-author trailer:
   ```
   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   ```
4. **Don't refactor unrelated code.** The existing structure is deliberate.
5. **Don't merge to `main` from a phase branch yourself.** Final report, leave the branch, let the user merge.
6. **Surface punts honestly in the final report.** Better than half-finishing five things.
7. **Don't ship visible bugs to "test in production".** The user smoke-tests every phase and surfaces what breaks. Build that loop into your phase plan.
8. **Diagnostic NSLogs go in commits like `chore(debug): …` and get stripped before the phase merges.** Don't leave them in.

## Test-suite shape

127 tests across:
- `CaptureStoreTests`, `SniprPreferencesTests`, `SniprCommandTests`, `AnnotationRendererTests` (Phase 0)
- `OverlayPresenter / StackPresenter / RecordingPresenter / PreviewPresenter / HotKeyService / FakeEngines` (Phase 0)
- `CaptureFilenameTemplate / CaptureFlowPresenter / ClipboardSink / EdgeSnap` (Phase 1)
- `ThumbnailPileLayout / PDFCombiner / VerticalStitcher` (Phase 2)
- `OCREngine / OCRHistoryStore / ColorPicker / PinPresenter / AnnotationTool / TrimExport` (Phase 3)
- `SmartFolderRule / WorkflowExecutor / VisionStitchEngine / ScrollingCaptureProgress` (Phase 4)

When adding tests, group them by feature and keep names sentence-cased (`testStitchUsesWidestImageAsCanvasWidth`).

---

That's everything. The code is in good shape, the bones are clean, and the remaining work is well-scoped. Phase 5 is mostly packaging mechanics; Phase 4.5 is one focused engineering session. Either is shippable in a single agent dispatch.
