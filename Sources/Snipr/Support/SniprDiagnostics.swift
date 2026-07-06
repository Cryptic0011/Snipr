import AppKit
import OSLog

enum SniprDiagnostics {
    private static let fallbackSubsystem = "com.grayson.snipr"

    static let windowing = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? fallbackSubsystem,
        category: "Windowing"
    )

    @MainActor
    static func disableRestoration(for window: NSWindow) {
        window.isRestorable = false
    }
}
