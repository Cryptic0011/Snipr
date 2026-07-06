import Foundation

enum SniprCommandID: String, CaseIterable, Codable, Sendable {
    case captureArea
    case recordArea
    case captureToolbar
    case openHistory
    case clearStack
    case openSettings
    case quit
    case ocrSelection
    case showOCRHistory
    case pickColor
    case scrollingCapture

    /// The hotkey action whose user-configured binding supplies this
    /// command's shortcut hint. Commands without one show a fixed system
    /// shortcut (⌘, / ⌘Q) or none.
    var hotKeyAction: SniprHotKeyAction? {
        switch self {
        case .captureArea: .captureArea
        case .recordArea: .screenRecord
        case .captureToolbar: .captureToolbar
        case .openHistory: .openApp
        case .clearStack: .clearStack
        case .ocrSelection: .ocr
        case .pickColor: .colorPick
        case .scrollingCapture: .scrollingCapture
        case .openSettings, .quit, .showOCRHistory: nil
        }
    }
}

struct SniprCommand: Identifiable, Equatable, Sendable {
    let id: SniprCommandID
    let title: String
    let subtitle: String
    let systemImage: String
    var shortcut: String

    /// The palette rendered from the user's actual bindings — rebinding a
    /// hotkey updates the hint instead of showing a stale hard-coded string.
    static func all(bindings: [SniprHotKeyAction: HotKeyBinding]) -> [SniprCommand] {
        all.map { command in
            guard let action = command.id.hotKeyAction, let binding = bindings[action] else {
                return command
            }
            var updated = command
            updated.shortcut = binding.isEnabled ? binding.displayText : ""
            return updated
        }
    }

    static let all: [SniprCommand] = [
        .init(
            id: .captureToolbar,
            title: "Open Capture Toolbar",
            subtitle: "Choose screenshot or recording mode",
            systemImage: "camera.viewfinder",
            shortcut: "⌘⇧5"
        ),
        .init(
            id: .captureArea,
            title: "Capture Area",
            subtitle: "Select a screen region",
            systemImage: "selection.pin.in.out",
            shortcut: "⌘⇧4"
        ),
        .init(
            id: .recordArea,
            title: "Record Area",
            subtitle: "Record a selected screen region",
            systemImage: "record.circle",
            shortcut: "⌘⇧6"
        ),
        .init(
            id: .ocrSelection,
            title: "OCR Selection",
            subtitle: "Recognize text in a region — copies to clipboard",
            systemImage: "textformat.123",
            shortcut: "⌘⇧O"
        ),
        .init(
            id: .showOCRHistory,
            title: "Show OCR History",
            subtitle: "Re-copy a previous OCR result",
            systemImage: "list.bullet.rectangle",
            shortcut: ""
        ),
        .init(
            id: .pickColor,
            title: "Pick Color",
            subtitle: "Sample a pixel color and copy it",
            systemImage: "eyedropper",
            shortcut: "⌘⇧C"
        ),
        .init(
            id: .scrollingCapture,
            title: "Scrolling Capture",
            subtitle: "Pick a window, scroll inside it, stitch the result",
            systemImage: "rectangle.portrait.and.arrow.right",
            shortcut: "⌘⇧V"
        ),
        .init(
            id: .openHistory,
            title: "Open Recent History",
            subtitle: "Review local captures",
            systemImage: "clock.arrow.circlepath",
            shortcut: "⌘Y"
        ),
        .init(
            id: .clearStack,
            title: "Clear Stack",
            subtitle: "Remove floating thumbnails",
            systemImage: "rectangle.stack.badge.minus",
            shortcut: "⌘⌫"
        ),
        .init(
            id: .openSettings,
            title: "Open Settings",
            subtitle: "Permissions and defaults",
            systemImage: "gearshape",
            shortcut: "⌘,"
        ),
        .init(
            id: .quit,
            title: "Quit Snipr",
            subtitle: "Close the app",
            systemImage: "power",
            shortcut: "⌘Q"
        )
    ]

    static func filtered(by query: String, bindings: [SniprHotKeyAction: HotKeyBinding]? = nil) -> [SniprCommand] {
        let commands = bindings.map(all(bindings:)) ?? all
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return commands
        }

        let tokens = trimmedQuery
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        let titleMatches = commands.filter { command in
            matches(tokens, in: command.title)
        }

        if !titleMatches.isEmpty {
            return titleMatches
        }

        return commands.filter { command in
            matches(tokens, in: "\(command.title) \(command.subtitle) \(command.id.rawValue)")
        }
    }

    private static func matches(_ tokens: [String], in candidate: String) -> Bool {
        let haystack = candidate.lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}
