import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns the scrolling-capture flow: pick a window, stream frames at ~10 fps,
/// stop on user signal, run the stitch kernel, deposit the result in the
/// stack.
///
/// This is the presenter side of the Phase 4 moat feature. The kernel
/// (`VisionStitchEngine`) is unit-tested; this orchestration layer is best-
/// effort and best validated manually against Safari / VS Code / Notion.
@MainActor
final class ScrollingCapturePresenter {
    private let captureStore: CaptureStore
    private let preferences: SniprPreferences
    private let stitchEngine: any StitchEngine
    private let collector: ScrollingFrameCollector
    let progress = ScrollingCaptureProgress()
    private var progressWindow: NSPanel?

    var onError: ((Error) -> Void)?
    var onCaptureStored: (() -> Void)?

    init(
        captureStore: CaptureStore,
        preferences: SniprPreferences,
        stitchEngine: any StitchEngine = VisionStitchEngine(),
        collector: ScrollingFrameCollector? = nil
    ) {
        self.captureStore = captureStore
        self.preferences = preferences
        self.stitchEngine = stitchEngine
        // Wire the collector's progress callback through to the
        // observable progress model so the HUD updates as frames arrive.
        let progressModel = self.progress
        self.collector = collector ?? ScrollingFrameCollector(progressUpdate: { pixels in
            progressModel.update(capturedPixels: pixels)
        })
        // Stream death mid-scroll (window closed, display disconnected):
        // tell the user, then salvage whatever frames were already collected
        // instead of leaving the HUD "recording" a dead stream.
        self.collector.onUnexpectedStop = { [weak self] error in
            guard let self else { return }
            self.onError?(error)
            self.stopAndStitch()
        }
    }

    /// Start collecting frames against the given on-screen window. Shows a
    /// minimalist HUD at the top of the main screen with a Stop button.
    func start(scWindow: SCWindow, appName: String?) {
        progress.start()
        showProgressHUD()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.collector.start(scWindow: scWindow)
            } catch {
                self.hideProgressHUD()
                self.progress.finish()
                self.onError?(error)
            }
        }
    }

    /// Commit the in-progress scrolling capture: stop the collector, run
    /// the stitch kernel, deposit the result in the capture store.
    func stopAndStitch(appName: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let frames = await self.collector.stop()
            self.progress.finish()
            self.hideProgressHUD()

            guard !frames.isEmpty else {
                SniprDiagnostics.windowing.error("ScrollingCapture stop produced no frames")
                self.onError?(StitchError.noFrames)
                return
            }

            // Field diagnostics: `defaults write com.grayson.snipr
            // SniprDebugKeepScrollFrames -bool YES` dumps the raw frames so a
            // bad stitch can be reproduced offline as a fixture.
            if UserDefaults.standard.bool(forKey: "SniprDebugKeepScrollFrames") {
                Self.dumpDebugFrames(frames)
            }

            do {
                let format = self.preferences.captureFormat
                let job = ScrollingStitchJob(frames: frames, stitchEngine: self.stitchEngine, format: format)
                let result = try await Task.detached(priority: .userInitiated) {
                    try job.run()
                }.value
                if let reason = result.salvageReason {
                    SniprDiagnostics.windowing.error("ScrollingCapture stitch failed, kept first frame error=\(String(describing: reason), privacy: .public)")
                    self.onError?(ScrollingStitchSalvageNotice(underlying: reason))
                }
                let suggested = CaptureFilenameTemplate.expand(
                    template: self.preferences.captureFilenameTemplate,
                    date: Date(),
                    appName: appName,
                    windowTitle: nil,
                    pixelSize: result.pixelSize,
                    sequence: 0,
                    fileExtension: format.fileExtension
                )

                let subfolder = SmartFolderRouter.subfolder(
                    forAppName: appName,
                    rules: self.preferences.smartFolderRules
                )
                _ = try self.captureStore.addCapture(
                    pngData: result.data,
                    pixelSize: result.pixelSize,
                    displayID: nil,
                    fileExtension: format.fileExtension,
                    suggestedFilename: suggested,
                    subfolder: subfolder
                )
                self.onCaptureStored?()
            } catch {
                SniprDiagnostics.windowing.error("ScrollingCapture stitch failed error=\(String(describing: error), privacy: .public)")
                self.onError?(error)
            }
        }
    }

    func cancel() {
        collector.cancel()
        progress.finish()
        hideProgressHUD()
    }

    private func encode(_ image: CGImage, format: CaptureFormat) -> Data {
        Self.encode(image, format: format)
    }

    nonisolated fileprivate static func encode(_ image: CGImage, format: CaptureFormat) -> Data {
        let data = NSMutableData()
        let utType: CFString
        switch format {
        case .png: utType = UTType.png.identifier as CFString
        case .jpeg: utType = UTType.jpeg.identifier as CFString
        case .heic: utType = UTType.heic.identifier as CFString
        }
        guard let destination = CGImageDestinationCreateWithData(data, utType, 1, nil) else {
            // Fallback: PNG via ImageIO.
            let png = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
            return png as Data
        }
        var properties: [CFString: Any] = [:]
        if let quality = format.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private nonisolated static func dumpDebugFrames(_ frames: [CGImage]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SniprScrollFrames-\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (index, frame) in frames.enumerated() {
                let url = dir.appendingPathComponent(String(format: "frame-%03d.png", index))
                guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, frame, nil)
                CGImageDestinationFinalize(dest)
            }
            SniprDiagnostics.windowing.error("ScrollingCapture debug frames dumped to \(dir.path, privacy: .public)")
        } catch {
            SniprDiagnostics.windowing.error("ScrollingCapture debug frame dump failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private func showProgressHUD() {
        guard progressWindow == nil, let screen = NSScreen.main else { return }
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 48
        let frame = NSRect(
            x: screen.visibleFrame.midX - panelWidth / 2,
            y: screen.visibleFrame.maxY - panelHeight - 12,
            width: panelWidth,
            height: panelHeight
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.sharingType = .none
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let view = ScrollingCaptureProgressBar(
            progress: progress,
            onStop: { [weak self] in self?.stopAndStitch() },
            onCancel: { [weak self] in self?.cancel() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        progressWindow = panel
    }

    private func hideProgressHUD() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
    }
}

/// The stitch failed but the user still got a capture: the first collected
/// frame was kept so minutes of setup aren't thrown away with the seams.
struct ScrollingStitchSalvageNotice: LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        "Couldn't stitch the scroll, so the first frame was kept in your stack instead. \(underlying.localizedDescription)"
    }
}

// Internal (not private) so the salvage path is unit-testable with a fake
// stitch engine — the SCStream side of scrolling capture can't run in tests.
struct ScrollingStitchJob: @unchecked Sendable {
    let frames: [CGImage]
    let stitchEngine: any StitchEngine
    let format: CaptureFormat

    struct Output {
        let data: Data
        let pixelSize: CGSize
        /// Non-nil when stitching failed and `data` is the first frame,
        /// salvaged, rather than the tall composite.
        let salvageReason: Error?
    }

    func run() throws -> Output {
        do {
            guard let stitched = try stitchEngine.stitch(frames: frames) else {
                throw StitchError.allFramesRejected
            }
            return Output(
                data: ScrollingCapturePresenter.encode(stitched, format: format),
                pixelSize: CGSize(width: stitched.width, height: stitched.height),
                salvageReason: nil
            )
        } catch {
            // Salvage: a single viewport screenshot beats losing the whole
            // session. Only a truly empty session still fails.
            guard let first = frames.first else { throw error }
            return Output(
                data: ScrollingCapturePresenter.encode(first, format: format),
                pixelSize: CGSize(width: first.width, height: first.height),
                salvageReason: error
            )
        }
    }
}
