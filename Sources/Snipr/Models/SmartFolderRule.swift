import Foundation

/// Routing rule that maps a (case-insensitive) substring of an app name to a
/// destination subfolder under the captures root.
///
/// Phase 4 introduces these so power users can keep "Safari" captures separate
/// from "Xcode" captures without manually re-saving each one. The match
/// semantics are deliberately small:
///
/// * Empty `appPattern` matches **nothing** — safer than matches-everything,
///   which would silently re-route every capture into the rule's subfolder.
/// * Match is case-insensitive `contains` so users don't have to type the
///   exact bundle display name.
/// * `subfolder` is interpreted relative to `Captures/Images`. Slashes are
///   honored so users can do nested folders like `"Work/Safari"`.
struct SmartFolderRule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var appPattern: String
    var subfolder: String

    init(id: UUID = UUID(), appPattern: String, subfolder: String) {
        self.id = id
        self.appPattern = appPattern
        self.subfolder = subfolder
    }

    /// Whether the rule fires for the given app name. `nil` and empty patterns
    /// never match — they're treated as "no rule configured" rather than a
    /// catch-all.
    func matches(appName: String?) -> Bool {
        let pattern = appPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, let appName, !appName.isEmpty else {
            return false
        }
        return appName.range(of: pattern, options: .caseInsensitive) != nil
    }
}

enum SmartFolderRouter {
    /// First matching rule wins; nil if no rule matches. Empty rules array
    /// short-circuits — common path is "no smart folders configured".
    static func subfolder(forAppName appName: String?, rules: [SmartFolderRule]) -> String? {
        guard !rules.isEmpty else { return nil }
        for rule in rules where rule.matches(appName: appName) {
            let trimmed = rule.subfolder.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}
