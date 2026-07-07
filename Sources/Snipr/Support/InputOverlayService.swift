import AppKit
import ApplicationServices
import SwiftUI

/// Formats a key event for the on-screen keystroke HUD. Pure so it's testable
/// without synthesizing NSEvents.
enum KeystrokeDisplay {
    private static let specialKeys: [UInt16: String] = [
        36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        116: "Page Up", 121: "Page Down", 115: "Home", 119: "End", 117: "⌦"
    ]

    static func text(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        if let special = specialKeys[keyCode] {
            parts.append(special)
        } else if let characters, let first = characters.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(first),
                  !(0xF700...0xF8FF).contains(first.value) { // function-key private-use range
            parts.append(characters.uppercased())
        }
        return parts.joined()
    }
}

/// Shows pressed keys and click ripples on screen while a recording runs.
/// The panels use the default window sharing type on purpose — they exist to
/// be captured. Keystrokes require Input Monitoring access; clicks need none.
@MainActor
final class InputOverlayService {
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var hudPanel: NSPanel?
    private var hudDismissTask: Task<Void, Never>?
    /// Recorded area in global Cocoa coordinates; the keystroke HUD is
    /// positioned inside it so it actually lands in the recording.
    private var region: CGRect?

    /// Global keyDown monitors are gated by Input Monitoring (ListenEvent),
    /// not Accessibility — AXIsProcessTrusted is the wrong check for them.
    static var hasInputMonitoringAccess: Bool { CGPreflightListenEventAccess() }

    static func requestInputMonitoringAccess() {
        _ = CGRequestListenEventAccess()
    }

    var isActive: Bool { keyMonitor != nil || clickMonitor != nil }

    /// Click ripples work without any permission; keystroke monitoring only
    /// attaches when the app has Input Monitoring access.
    func start(keystrokes: Bool, clicks: Bool, region: CGRect? = nil) {
        stop()
        self.region = region
        if keystrokes {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                let text = KeystrokeDisplay.text(
                    keyCode: event.keyCode,
                    modifiers: event.modifierFlags,
                    characters: event.charactersIgnoringModifiers
                )
                DispatchQueue.main.async { [weak self] in
                    self?.showKeystroke(text)
                }
            }
        }
        if clicks {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                let location = NSEvent.mouseLocation
                DispatchQueue.main.async { [weak self] in
                    self?.showClickRipple(at: location)
                }
            }
        }
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
        region = nil
        hudDismissTask?.cancel()
        hudPanel?.close()
        hudPanel = nil
    }

    private func showKeystroke(_ text: String) {
        guard !text.isEmpty, let screen = NSScreen.main else { return }

        hudDismissTask?.cancel()
        hudPanel?.close()
        hudPanel = nil

        let content = Text(text)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        let hosting = NSHostingView(rootView: content)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        let anchor = region ?? screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: anchor.midX - hosting.fittingSize.width / 2,
            y: anchor.minY + min(40, max(8, anchor.height * 0.06))
        ))
        panel.orderFrontRegardless()
        hudPanel = panel

        hudDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled, self?.hudPanel === panel else { return }
            panel.close()
            self?.hudPanel = nil
        }
    }

    private func showClickRipple(at location: NSPoint) {
        let size: CGFloat = 56
        let panel = NSPanel(
            contentRect: NSRect(
                x: location.x - size / 2,
                y: location.y - size / 2,
                width: size,
                height: size
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: ClickRippleView())
        panel.orderFrontRegardless()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            panel.close()
        }
    }
}

private struct ClickRippleView: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.white, lineWidth: 3)
            .scaleEffect(expanded ? 1.0 : 0.25)
            .opacity(expanded ? 0 : 0.9)
            .animation(.easeOut(duration: 0.4), value: expanded)
            .onAppear { expanded = true }
    }
}
