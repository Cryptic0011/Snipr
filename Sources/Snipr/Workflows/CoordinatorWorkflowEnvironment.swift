import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Real implementation of `WorkflowEnvironment` that bridges into the
/// existing `WindowCoordinator` plumbing. Lives here (rather than inside
/// the coordinator) so the coordinator stays a router and tests can keep
/// substituting fakes.
@MainActor
final class CoordinatorWorkflowEnvironment: WorkflowEnvironment {
    private weak var coordinator: WindowCoordinator?
    private let captureEngine: CaptureEngine
    private let ocrEngine: any OCREngine
    private let translationEngine: any TranslationEngine
    private let captureStore: CaptureStore
    private let preferences: SniprPreferences

    init(
        coordinator: WindowCoordinator,
        captureEngine: CaptureEngine,
        ocrEngine: any OCREngine,
        translationEngine: any TranslationEngine,
        captureStore: CaptureStore,
        preferences: SniprPreferences
    ) {
        self.coordinator = coordinator
        self.captureEngine = captureEngine
        self.ocrEngine = ocrEngine
        self.translationEngine = translationEngine
        self.captureStore = captureStore
        self.preferences = preferences
    }

    func captureImage() async throws -> CGImage? {
        guard let coordinator else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            coordinator.overlayPresenter.onSelectionComplete = { [weak self] _, displayID, screen, rect in
                Task { @MainActor in
                    guard let self else { continuation.resume(returning: nil); return }
                    // Same teardown delay as `CaptureFlowPresenter` —
                    // without it the overlay panel can still be on screen
                    // when SCK samples pixels and would land in the shot.
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    do {
                        let image = try await self.captureEngine.capture(
                            displayID: displayID,
                            rectInDisplayPoints: rect,
                            screen: screen
                        )
                        continuation.resume(returning: image.cgImage)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                    // Restore the original handler so subsequent overlays
                    // route through the coordinator, not this workflow.
                    coordinator.rewireOverlayHandlers()
                }
            }
            coordinator.overlayPresenter.onCancel = { [weak coordinator] in
                continuation.resume(returning: nil)
                coordinator?.rewireOverlayHandlers()
            }
            coordinator.overlayPresenter.showCaptureOverlays(mode: .screenshot, showMagnifier: preferences.showCaptureMagnifier, showCoordinates: preferences.showSelectionCoordinates)
        }
    }

    func ocrText(in image: CGImage) async throws -> String {
        try await ocrEngine.recognizeText(in: image)
    }

    func translate(text: String, to locale: Locale) async throws -> String {
        try await translationEngine.translate(text: text, toLocale: locale)
    }

    func writeToClipboard(text: String?, image: CGImage?) {
        if let text, !text.isEmpty {
            ClipboardSink.copyText(text)
            return
        }
        if let image, let pngData = pngData(from: image) {
            ClipboardSink.copy(data: pngData, format: .png)
        }
    }

    func saveImage(_ image: CGImage) async throws -> URL? {
        guard let pngData = pngData(from: image) else { return nil }
        let item = try captureStore.addCapture(
            pngData: pngData,
            pixelSize: CGSize(width: image.width, height: image.height),
            displayID: nil,
            fileExtension: "png",
            suggestedFilename: nil,
            subfolder: nil
        )
        return item.fileURL
    }

    func pinImage(_ image: CGImage, at savedURL: URL?) {
        guard let coordinator else { return }
        // The pin presenter requires a CaptureItem (file-backed); persist if
        // we don't already have a URL so the floating panel can read pixels.
        let fileURL: URL
        if let savedURL {
            fileURL = savedURL
        } else if let png = pngData(from: image) {
            do {
                let item = try captureStore.addCapture(
                    pngData: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    displayID: nil,
                    fileExtension: "png",
                    suggestedFilename: nil,
                    subfolder: nil
                )
                fileURL = item.fileURL
            } catch {
                return
            }
        } else {
            return
        }

        guard let item = captureStore.items.first(where: { $0.fileURL == fileURL }) else {
            return
        }
        coordinator.pin(item)
    }

    func annotateImage(at url: URL) {
        guard let coordinator,
              let item = captureStore.items.first(where: { $0.fileURL == url }) else { return }
        coordinator.openPreview(for: item)
    }

    private func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
