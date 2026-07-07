@preconcurrency import AVFoundation
import AppKit

/// Floating circular webcam preview shown during recordings. The panel keeps
/// the default window sharing type so it lands *in* the recording — that's
/// the point. Draggable by its body; sits bottom-left by default.
@MainActor
final class WebcamBubblePresenter {
    private var panel: NSPanel?
    private var session: AVCaptureSession?

    var isActive: Bool { panel != nil }

    func show() {
        guard panel == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            ToastPresenter.show("No camera available", systemImage: "video.slash")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let diameter: CGFloat = 160
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        previewLayer.cornerRadius = diameter / 2
        previewLayer.masksToBounds = true
        previewLayer.borderWidth = 2.5
        previewLayer.borderColor = CGColor(red: 0.804, green: 0.667, blue: 0.329, alpha: 1)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        container.wantsLayer = true
        container.layer?.addSublayer(previewLayer)

        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.visibleFrame.minX + 24,
            y: screen.visibleFrame.minY + 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: diameter, height: diameter)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.session = session

        // startRunning blocks while the camera spins up; keep it off the
        // main thread. The session is confined to this class after handoff.
        nonisolated(unsafe) let startingSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            startingSession.startRunning()
        }
    }

    func hide() {
        if let session {
            nonisolated(unsafe) let stoppingSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                stoppingSession.stopRunning()
            }
        }
        session = nil
        panel?.close()
        panel = nil
    }
}
