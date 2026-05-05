# Snipr Real Capture MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native Snipr macOS app: command palette, area capture overlay, local history, and floating thumbnail stack.

**Architecture:** Use a SwiftPM SwiftUI/AppKit macOS GUI executable. SwiftUI owns durable app state and views; AppKit bridge services own status item, global hotkeys, floating panels, open/save panels, and the selection overlay window lifecycle.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreGraphics, Carbon hotkeys, XCTest, SwiftPM GUI bundle staging.

---

## File Structure

- `Package.swift`: SwiftPM executable and test targets.
- `Sources/Snipr/App/SniprApp.swift`: app entrypoint, menu commands, app delegate activation.
- `Sources/Snipr/Models/CaptureItem.swift`: capture metadata.
- `Sources/Snipr/Models/SniprCommand.swift`: command palette action list.
- `Sources/Snipr/Stores/CaptureStore.swift`: local image and metadata persistence.
- `Sources/Snipr/Services/PermissionService.swift`: screen-recording permission checks.
- `Sources/Snipr/Services/ScreenCaptureService.swift`: display-region PNG capture.
- `Sources/Snipr/Services/HotKeyService.swift`: Carbon global hotkey registration.
- `Sources/Snipr/Services/WindowCoordinator.swift`: AppKit panel and overlay orchestration.
- `Sources/Snipr/Views/ContentView.swift`: compact home/history surface.
- `Sources/Snipr/Views/CommandPaletteView.swift`: Raycast-style command palette.
- `Sources/Snipr/Views/CaptureOverlayView.swift`: AppKit-backed drag selection overlay.
- `Sources/Snipr/Views/ThumbnailStackView.swift`: floating thumbnail stack.
- `Sources/Snipr/Views/PreviewWindowView.swift`: image preview and actions.
- `Sources/Snipr/Support/ImageTransfer.swift`: pasteboard, save panel, Finder helpers.
- `Sources/Snipr/Resources/SniprLogo.png`: supplied logo resource.
- `Tests/SniprTests/CaptureStoreTests.swift`: persistence behavior tests.
- `Tests/SniprTests/SniprCommandTests.swift`: command filtering tests.
- `script/build_and_run.sh`: build, bundle, launch, verify, logs.
- `.codex/environments/environment.toml`: Codex Run action.

## Task 1: Package And Test Harness

**Files:**
- Create: `Package.swift`
- Create: `Tests/SniprTests/SniprCommandTests.swift`
- Create: `Sources/Snipr/Models/SniprCommand.swift`

- [x] **Step 1: Write failing command tests**

Create `Tests/SniprTests/SniprCommandTests.swift` with tests for all commands and search filtering.

- [x] **Step 2: Run tests to verify red**

Run: `swift test --filter SniprCommandTests`
Expected: failure because the package and model do not exist yet.

- [x] **Step 3: Create SwiftPM package and command model**

Create a macOS 14 SwiftPM executable target plus a test target. Implement `SniprCommand` with stable IDs, titles, SF Symbols, shortcuts, and search filtering.

- [x] **Step 4: Run tests to verify green**

Run: `swift test --filter SniprCommandTests`
Expected: tests pass.

## Task 2: Capture Store

**Files:**
- Create: `Sources/Snipr/Models/CaptureItem.swift`
- Create: `Sources/Snipr/Stores/CaptureStore.swift`
- Create: `Tests/SniprTests/CaptureStoreTests.swift`

- [x] **Step 1: Write failing store tests**

Create temp-directory tests for adding a PNG capture, loading metadata on a new store, deleting one item, and clearing the stack.

- [x] **Step 2: Run tests to verify red**

Run: `swift test --filter CaptureStoreTests`
Expected: failure because store types do not exist.

- [x] **Step 3: Implement capture metadata and persistence**

Implement `CaptureItem` as `Codable`, and `CaptureStore` as `@Observable` with Application Support defaults plus test-injected root URLs.

- [x] **Step 4: Run tests to verify green**

Run: `swift test --filter CaptureStoreTests`
Expected: tests pass.

## Task 3: App Shell, Palette, And History UI

**Files:**
- Create: `Sources/Snipr/App/SniprApp.swift`
- Create: `Sources/Snipr/Views/ContentView.swift`
- Create: `Sources/Snipr/Views/CommandPaletteView.swift`
- Create: `Sources/Snipr/Services/WindowCoordinator.swift`
- Create: `Sources/Snipr/Services/PermissionService.swift`
- Create: `Sources/Snipr/Support/ImageTransfer.swift`
- Copy: `Flat Logo-no-background.png` to `Sources/Snipr/Resources/SniprLogo.png`

- [x] **Step 1: Implement app shell**

Create a regular SwiftUI macOS app with menu bar status item, app activation, status/history landing view, settings scene, and menu commands.

- [x] **Step 2: Implement command palette**

Create a floating panel with dark dense search UI, keyboard-friendly action rows, and actions connected to the coordinator.

- [x] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

## Task 4: Area Capture Overlay And Thumbnail Stack

**Files:**
- Create: `Sources/Snipr/Services/ScreenCaptureService.swift`
- Create: `Sources/Snipr/Services/HotKeyService.swift`
- Create: `Sources/Snipr/Views/CaptureOverlayView.swift`
- Create: `Sources/Snipr/Views/ThumbnailStackView.swift`
- Create: `Sources/Snipr/Views/PreviewWindowView.swift`
- Modify: `Sources/Snipr/Services/WindowCoordinator.swift`

- [x] **Step 1: Implement capture overlay**

Use AppKit overlay windows per screen and an `NSViewRepresentable` drag selection view that returns display-local rectangles.

- [x] **Step 2: Implement capture service**

Use `CGDisplayCreateImage(_:rect:)` for display-local captures, encode PNG data, and store through `CaptureStore`.

- [x] **Step 3: Implement thumbnail stack and preview**

Create bottom-right floating stack panel, context actions, double-click preview, copy, save as, reveal, delete, and clear stack.

- [x] **Step 4: Build**

Run: `swift build`
Expected: build succeeds.

## Task 5: Run Script And Verification

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [x] **Step 1: Add project run entrypoint**

Create `script/build_and_run.sh` for SwiftPM GUI bundle staging with `run`, `--debug`, `--logs`, `--telemetry`, and `--verify`.

- [x] **Step 2: Add Codex Run action**

Create `.codex/environments/environment.toml` pointing Run to `./script/build_and_run.sh`.

- [x] **Step 3: Run full verification**

Run:

```bash
swift test
./script/build_and_run.sh --verify
```

Expected: tests pass and the Snipr process launches from the staged app bundle.
