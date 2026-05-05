# Snipr Real Capture MVP Design

Date: 2026-05-05

## Goal

Snipr v0.1 is a local-first macOS screenshot utility inspired by CleanShot X and Raycast. The first release should prove the product spine: trigger a capture quickly, select a screen region, store the result locally, show it in a floating thumbnail stack, and make common actions fast.

This first slice intentionally favors working capture flow over breadth. Annotation, OCR, video recording, scrolling capture, pinned overlays, and cloud sharing are deferred until the capture, file, and stack lifecycle are reliable.

## Product Scope

### In Scope

- Native Swift 6+ macOS app using SwiftUI with AppKit interop where needed.
- Regular app with menu bar presence.
- Raycast-style command palette opened by `Command-Shift-Space`.
- Area capture action opened from the command palette and menu bar.
- Full-screen area selection overlay across available displays.
- PNG capture saved to local Application Support storage.
- Floating thumbnail stack in the bottom-right corner.
- Capture history based on local image files plus JSON metadata.
- Basic actions for each capture:
  - copy image to clipboard
  - save as
  - reveal in Finder
  - open preview window
  - delete
  - clear stack
- Use the supplied Snipr logo assets for app identity.
- Clear screen-recording permission status and recovery instructions.

### Out of Scope For v0.1

- Annotation editor tools.
- OCR and OCR history.
- Screen recording.
- Scrolling capture and stitching.
- Window-specific capture.
- Pin/reference overlays.
- Drag-all batching.
- Cloud, BYOC, sharing links, or upload destinations.
- Custom `.snipr` project format.

## Architecture

### App Structure

The app will use a multi-file native macOS structure:

- `App/SniprApp.swift`: app entry point, app delegate, scene declarations, global hotkey registration.
- `Views/ContentView.swift`: minimal home/status surface.
- `Views/CommandPaletteView.swift`: searchable command palette UI.
- `Views/CaptureOverlayView.swift`: SwiftUI selection overlay content hosted inside AppKit overlay windows.
- `Views/ThumbnailStackView.swift`: floating capture stack UI.
- `Views/PreviewWindowView.swift`: capture preview and actions.
- `Models/CaptureItem.swift`: capture metadata model.
- `Models/SniprCommand.swift`: command palette action model.
- `Stores/CaptureStore.swift`: in-memory stack plus durable history loading and saving.
- `Services/ScreenCaptureService.swift`: display and region capture implementation.
- `Services/HotKeyService.swift`: global hotkey handling.
- `Services/PermissionService.swift`: screen-recording permission checks.
- `Services/WindowCoordinator.swift`: AppKit windows, panels, and overlay lifecycle.
- `Support/AssetCatalog`, formatters, and small extensions.

### Scene Model

Snipr will launch as a regular macOS app with a Dock icon for the MVP. It will also install a menu bar item for persistent quick access. Keeping the app regular during v0.1 makes permission prompts, debugging, previews, and history surfaces easier to inspect. A later release can decide whether to offer menu-bar-only accessory mode.

Scenes:

- Primary `WindowGroup`: compact status/history landing surface.
- `Settings`: a minimal preferences scene containing permission status and the default capture folder.
- AppKit-managed floating panels:
  - command palette panel
  - selection overlay panels
  - thumbnail stack panel
  - capture preview windows

### State Ownership

`CaptureStore` is the app-owned source of truth for recent captures. It owns:

- loaded history items
- current floating stack items
- metadata writes
- delete and clear operations

`WindowCoordinator` owns transient UI lifecycle:

- showing and hiding the command palette
- presenting capture overlays for all displays
- presenting and positioning the thumbnail stack
- opening preview windows

Capture selection state remains local to the overlay flow until the user completes or cancels the drag.

## Capture Flow

1. User chooses `Capture Area` from the command palette, menu bar, or hotkey.
2. `PermissionService` checks screen-recording access.
3. If permission is missing, Snipr opens the status window with recovery guidance.
4. If permission is available, `WindowCoordinator` creates borderless overlay panels over each display.
5. User drags a region.
6. Overlay displays selection bounds and dimensions.
7. On mouse up, the overlay returns the selected rect and target display.
8. `ScreenCaptureService` captures the selected region as PNG data.
9. `CaptureStore` writes the image and metadata to Application Support.
10. The new item is added to the floating stack and becomes the top thumbnail.
11. User can copy, save, preview, reveal, or delete the capture.

Cancel paths:

- `Escape` cancels the selection overlay.
- Clicking without a meaningful drag cancels capture.
- Permission denial leaves no partial history item.

## UI Design

Snipr should feel dark, compact, command-driven, and quiet.

### Command Palette

The palette is a centered floating panel with:

- dark material background
- 4-8 px corner radius
- sharp separator lines
- top search field
- dense list rows with SF Symbol, command title, and shortcut hint
- keyboard navigation with up/down and return

Initial commands:

- Capture Area
- Open Recent History
- Clear Stack
- Open Settings
- Quit Snipr

### Area Selection Overlay

The overlay freezes the user workflow visually with a translucent layer over the current displays. The selected region uses a high-contrast sky or emerald accent. The bounds label shows pixel dimensions without becoming visually loud.

### Thumbnail Stack

The stack appears in the bottom-right of the active display. v0.1 uses a compact vertical pile with slight offsets. Right-click context actions are required. Hover-revealed action buttons are deferred to a later slice.

Each thumbnail supports:

- double-click to preview
- context menu actions
- copy action
- delete action

### Preview Window

The preview window is a simple focused surface:

- captured image scaled to fit
- toolbar actions for copy, save as, reveal, delete
- metadata display for creation time and dimensions

## Storage

Captures are stored locally under Application Support:

`~/Library/Application Support/Snipr/Captures/`

Storage layout:

- `captures.json`: metadata index
- `Images/<capture-id>.png`: PNG image files

Metadata fields:

- stable ID
- file URL
- created date
- pixel width and height
- display ID when available
- source type, initially `area`

The store should tolerate missing files by skipping broken entries and rewriting the index on the next mutation.

## Permissions

Screen capture requires macOS Screen Recording permission. The app should:

- check permission before starting selection
- explain that permission is required when missing
- offer a button to open System Settings to the right privacy pane
- avoid repeated noisy prompts

Accessibility, microphone, camera, and automation permissions are not required for v0.1.

## Error Handling

- Permission missing: show status window with setup action.
- Capture returns nil or empty image: dismiss overlay and show a lightweight error in the status window.
- File write fails: keep image in memory if possible and show save/copy options.
- History index corrupt: preserve image files, rebuild or start with an empty index, and rewrite on next save.
- Multi-display mismatch: fall back to capturing from the display that contains the selected rect.

## Testing And Verification

Manual verification is required for the first MVP because screen-capture permission and overlay behavior are system-integrated.

Build checks:

- `swift build` or `xcodebuild` depending on scaffold choice.
- App launches without crashing.
- Menu bar item appears.
- Command palette opens with `Command-Shift-Space`.
- Capture Area opens overlay.
- Dragging a region creates a PNG file.
- Thumbnail stack appears.
- Copy places an image on the pasteboard.
- Save As writes a user-chosen PNG.
- Delete removes the item from stack, metadata, and disk.
- Relaunch restores recent history.

## Future Slices

1. OCR selection to clipboard using Vision.
2. Annotation editor with arrow, rectangle, circle, text, blur, pixelate, and step numbers.
3. Pin/reference overlays with opacity control.
4. Window capture and improved display/window detection.
5. Drag-and-drop thumbnails and batch stack actions.
6. Screen recording through ScreenCaptureKit.
7. Scrolling capture and stitching.
8. BYOC/local sharing destinations.
