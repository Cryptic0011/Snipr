import Foundation

enum SniprCommandID: String, CaseIterable, Codable, Sendable {
    case captureArea
    case recordArea
    case openHistory
    case clearStack
    case openSettings
    case quit
}

struct SniprCommand: Identifiable, Equatable, Sendable {
    let id: SniprCommandID
    let title: String
    let subtitle: String
    let systemImage: String
    let shortcut: String

    static let all: [SniprCommand] = [
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
            shortcut: "⌘⇧5"
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

    static func filtered(by query: String) -> [SniprCommand] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return all
        }

        let tokens = trimmedQuery
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        let titleMatches = all.filter { command in
            matches(tokens, in: command.title)
        }

        if !titleMatches.isEmpty {
            return titleMatches
        }

        return all.filter { command in
            matches(tokens, in: "\(command.title) \(command.subtitle) \(command.id.rawValue)")
        }
    }

    private static func matches(_ tokens: [String], in candidate: String) -> Bool {
        let haystack = candidate.lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}
