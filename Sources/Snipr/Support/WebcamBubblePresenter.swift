@preconcurrency import AVFoundation
import AppKit

/// Border color presets for the webcam bubble.
enum WebcamBorderColor: String, CaseIterable, Identifiable, Sendable {
    case white
    case brass
    case black
    case blue
    case green
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var cgColor: CGColor {
        switch self {
        case .white: CGColor(gray: 1, alpha: 1)
        case .brass: CGColor(red: 0.804, green: 0.667, blue: 0.329, alpha: 1)
        case .black: CGColor(gray: 0, alpha: 1)
        case .blue: CGColor(red: 0.25, green: 0.52, blue: 0.95, alpha: 1)
        case .green: CGColor(red: 0.27, green: 0.72, blue: 0.42, alpha: 1)
        case .red: CGColor(red: 0.90, green: 0.30, blue: 0.28, alpha: 1)
        }
    }
}

/// Floating circular webcam preview shown during recordings. The panel keeps
/// the default window sharing type so it lands *in* the recording — that's
/// the point. Draggable by its body; placed inside the recorded region so it
/// actually appears in the capture without dragging.
@MainActor
final class WebcamBubblePresenter {
    private var panel: NSPanel?
    private var session: AVCaptureSession?

    var isActive: Bool { panel != nil }

    /// Bottom-left corner inside the region, inset; centered when the region
    /// is too small for the bubble. Pure so it's testable.
    static func bubbleOrigin(region: CGRect, diameter: CGFloat, inset: CGFloat = 20) -> CGPoint {
        if region.width < diameter + inset * 2 || region.height < diameter + inset * 2 {
            return CGPoint(
                x: region.midX - diameter / 2,
                y: region.midY - diameter / 2
            )
        }
        return CGPoint(x: region.minX + inset, y: region.minY + inset)
    }

    /// - Parameter region: recorded area in global screen (Cocoa) coordinates;
    ///   nil falls back to the main screen's visible frame.
    func show(
        in region: NSRect? = nil,
        diameter: CGFloat = 160,
        borderColor: WebcamBorderColor = .white
    ) {
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

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        previewLayer.cornerRadius = diameter / 2
        previewLayer.masksToBounds = true
        previewLayer.borderWidth = 2.5
        previewLayer.borderColor = borderColor.cgColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        container.wantsLayer = true
        container.layer?.addSublayer(previewLayer)

        guard let screen = NSScreen.main else { return }
        let origin = Self.bubbleOrigin(
            region: region ?? screen.visibleFrame,
            diameter: diameter
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
