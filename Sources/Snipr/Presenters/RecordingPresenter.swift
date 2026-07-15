import AppKit
import Observation
import SwiftUI

/// Owns the recording HUD + region-frame panels and the lifecycle of an
/// active screen recording. The coordinator hands a selection rect to
/// `start(...)` and the presenter handles the rest, calling back into the
/// coordinator (via closures) when the user stops or cancels.
@MainActor
@Observable
final class RecordingPresenter {
    private let recordingEngine: RecordingEngine
    private let captureStore: CaptureStore
    private let preferences: SniprPreferences?
    private var recordingHUDPanel: NSPanel?
    private var recordingRegionFramePanel: NSPanel?
    private var activeRecordingDisplayID: CGDirectDisplayID?
    private let inputOverlays = InputOverlayService()
    private let webcamBubble = WebcamBubblePresenter()
    private let cursorSampler = CursorSampler()
    private var activeRecordingRegion: NSRect?   // global Cocoa coords
    /// True while `stop()`'s Task is still finalizing. `isRecording` flips
    /// false as soon as the engine stops, but the cursor bake can take
    /// seconds afterwards and its tail clears `activeRecordingRegion` /
    /// `activeRecordingDisplayID` — `start()` gates on this so a rapid
    /// re-start can't have that state silently clobbered.
    private var isFinalizingRecording = false

    /// Test seam: how many cursor positions the sampler has captured so
    /// far. Lets tests wait for the 60 Hz timer to actually tick before
    /// stopping, making bake-path preconditions deterministic.
    var capturedCursorSampleCount: Int {
        cursorSampler.samples.count
    }

    /// Called when a new recording lands in the capture store so the
    /// coordinator can reveal the stack.
    var onRecordingFinished: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(recordingEngine: RecordingEngine, captureStore: CaptureStore, preferences: SniprPreferences? = nil) {
        self.recordingEngine = recordingEngine
        self.captureStore = captureStore
        self.preferences = preferences
        recordingEngine.onUnexpectedStop = { [weak self] error in
            self?.handleUnexpectedStop(error)
        }
    }

    /// The stream died without the user asking (display disconnect, window
    /// server restart). Tell the user why, then run the normal stop path so
    /// the partial recording is finalized and the HUD comes down instead of
    /// showing "recording" forever.
    private func handleUnexpectedStop(_ error: Error) {
        onError?(error)
        stop()
    }

    var isRecording: Bool {
        recordingEngine.isRecording
    }

    func start(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        guard !recordingEngine.isRecording, !isFinalizingRecording else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: 120_000_000)

            do {
                let format = preferences?.recordingFormat ?? .mov
                let destinationURL = try captureStore.nextRecordingURL(fileExtension: format.fileExtension)
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
                showRecordingRegionFrame(screen: screen, rect: rect)
                showRecordingHUD()
                startRecordingCompanions(screen: screen, rect: rect)
            } catch {
                onError?(error)
            }
        }
    }

    func stop() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.isFinalizingRecording = true
            defer { self.isFinalizingRecording = false }

            do {
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
            } catch {
                self.activeRecordingDisplayID = nil
                self.cursorSampler.discard()
                self.activeRecordingRegion = nil
                self.closeRecordingHUD()
                self.onError?(error)
            }
        }
    }

    func cancel() {
        recordingEngine.cancel()
        activeRecordingDisplayID = nil
        cursorSampler.discard()
        activeRecordingRegion = nil
        closeRecordingHUD()
    }

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
        do {
            _ = try FileManager.default.replaceItemAt(video.fileURL, withItemAt: bakedURL)
        } catch {
            // Don't orphan the baked temp file if the atomic swap fails —
            // the raw recording at the original URL is what survives.
            try? FileManager.default.removeItem(at: bakedURL)
            throw error
        }
        return RecordedVideo(fileURL: video.fileURL, pixelSize: video.pixelSize, duration: video.duration)
    }

    /// Keystroke/click overlays and the webcam bubble live exactly as long as
    /// the recording. The overlays need Accessibility access for global
    /// event monitors; ask once and skip quietly if the user declines.
    private func startRecordingCompanions(screen: NSScreen, rect: CGRect) {
        guard let preferences else { return }
        // The selection rect is top-left-origin display points; convert to
        // global Cocoa coordinates (same math as the region frame) so the
        // companions land *inside* the recorded area.
        let regionInScreen = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        if preferences.showKeystrokesWhileRecording || preferences.showClicksWhileRecording {
            let trusted = InputOverlayService.hasInputMonitoringAccess
            // Click ripples never need permission; keystrokes need Input
            // Monitoring — prompt once and carry on without them.
            inputOverlays.start(
                keystrokes: preferences.showKeystrokesWhileRecording && trusted,
                clicks: preferences.showClicksWhileRecording,
                region: regionInScreen
            )
            if preferences.showKeystrokesWhileRecording, !trusted {
                InputOverlayService.requestInputMonitoringAccess()
                ToastPresenter.show("Grant Input Monitoring, then relaunch Snipr for keystroke overlays", systemImage: "exclamationmark.triangle")
            }
        }
        if preferences.showWebcamWhileRecording {
            webcamBubble.show(
                in: regionInScreen,
                diameter: preferences.webcamBubbleDiameter,
                borderColor: preferences.webcamBubbleBorderColor
            )
        }
    }

    private func stopRecordingCompanions() {
        inputOverlays.stop()
        webcamBubble.hide()
    }

    private func showRecordingRegionFrame(screen: NSScreen, rect: CGRect) {
        closeRecordingRegionFrame()

        let padding: CGFloat = 8
        let frameRect = NSRect(
            x: screen.frame.minX + rect.minX - padding,
            y: screen.frame.maxY - rect.maxY - padding,
            width: rect.width + padding * 2,
            height: rect.height + padding * 2
        )
        let panel = NSPanel(
            contentRect: frameRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // SCK honors NSWindow.sharingType — .none keeps this overlay out of
        // the recording so the red frame doesn't appear in the saved file.
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: RecordingRegionFrameView(size: rect.size, padding: padding))
        recordingRegionFramePanel = panel
        panel.orderFrontRegardless()
    }

    private func showRecordingHUD() {
        closeRecordingHUDPanelOnly()

        guard let screen = NSScreen.main else {
            return
        }

        let size = NSSize(width: 246, height: 58)
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Keep the HUD out of the recording too — even though it sits outside
        // the user-selected region, this is hygiene against future region picks
        // that overlap it.
        panel.sharingType = .none
        panel.contentView = NSHostingView(
            rootView: RecordingHUDView(
                startedAt: Date(),
                onStop: { [weak self] in
                    self?.stop()
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )
        )
        recordingHUDPanel = panel
        panel.orderFrontRegardless()
    }

    private func closeRecordingHUD() {
        closeRecordingHUDPanelOnly()
        closeRecordingRegionFrame()
        stopRecordingCompanions()
    }

    private func closeRecordingHUDPanelOnly() {
        recordingHUDPanel?.orderOut(nil)
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
    }

    private func closeRecordingRegionFrame() {
        recordingRegionFramePanel?.orderOut(nil)
        recordingRegionFramePanel?.close()
        recordingRegionFramePanel = nil
    }
}
