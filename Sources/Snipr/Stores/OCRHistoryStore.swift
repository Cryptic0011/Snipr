import Foundation
import Observation

/// One persisted OCR result.
struct OCRHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    /// First non-empty line, trimmed, suitable for showing as a single-row
    /// label in the command palette.
    var preview: String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Persists the most recent OCR results so the user can re-copy them from the
/// command palette without re-running OCR.
@MainActor
@Observable
final class OCRHistoryStore {
    static let maxEntries = 20
    private let key: String
    @ObservationIgnored
    private let defaults: UserDefaults

    private(set) var entries: [OCRHistoryEntry]

    init(defaults: UserDefaults = .standard, key: String = "ocrHistory") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([OCRHistoryEntry].self, from: data) {
            self.entries = stored
        } else {
            self.entries = []
        }
    }

    func append(text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var next = entries
        next.removeAll { $0.text == trimmed }
        next.insert(OCRHistoryEntry(text: trimmed, createdAt: date), at: 0)
        if next.count > Self.maxEntries {
            next = Array(next.prefix(Self.maxEntries))
        }
        entries = next
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
