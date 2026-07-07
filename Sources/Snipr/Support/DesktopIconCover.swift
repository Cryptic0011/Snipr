import AppKit

/// Hides desktop icons by floating a wallpaper-painted window just above the
/// icon layer on every screen. Non-destructive — nothing in Finder changes,
/// closing the windows brings the icons back.
@MainActor
final class DesktopIconCover {
    private var windows: [NSWindow] = []

    var isActive: Bool { !windows.isEmpty }

    /// Returns the new state: true when icons are now hidden.
    @discardableResult
    func toggle() -> Bool {
        if isActive {
            hide()
        } else {
            show()
        }
        return isActive
    }

    func show() {
        hide()
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            SniprDiagnostics.disableRestoration(for: window)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.ignoresMouseEvents = true
            window.hasShadow = false

            if let url = NSWorkspace.shared.desktopImageURL(for: screen),
               let image = NSImage(contentsOf: url) {
                let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.image = image
                view.imageScaling = .scaleAxesIndependently
                window.contentView = view
            } else {
                window.backgroundColor = .windowBackgroundColor
            }

            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}
