import Foundation
import Observation

@Observable
final class CaptureStore {
    private(set) var items: [CaptureItem] = []

    let rootDirectory: URL
    private let imagesDirectory: URL
    private let recordingsDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = CaptureStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.imagesDirectory = rootDirectory.appending(path: "Images", directoryHint: .isDirectory)
        self.recordingsDirectory = rootDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        self.indexURL = rootDirectory.appending(path: "captures.json")
        self.fileManager = fileManager
        load()
    }

    @discardableResult
    func addCapture(
        pngData: Data,
        pixelSize: CGSize,
        displayID: UInt32?,
        fileExtension: String = "png",
        suggestedFilename: String? = nil,
        subfolder: String? = nil
    ) throws -> CaptureItem {
        try ensureDirectoriesExist()

        // Resolve the destination directory. Phase 4 smart folders pass an
        // optional subfolder string (possibly nested via "/"); we sanitize
        // illegal path characters and then create the directory on demand.
        // When the subfolder is nil/empty we keep the existing on-disk shape.
        let destinationDirectory: URL
        if let subfolder, !subfolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sanitized = Self.sanitize(subfolder: subfolder)
            destinationDirectory = imagesDirectory.appending(path: sanitized, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } else {
            destinationDirectory = imagesDirectory
        }

        let id = UUID()
        let baseFilename: String
        if let suggested = suggestedFilename,
           let unique = Self.uniqueFilename(in: destinationDirectory, suggestion: suggested) {
            baseFilename = unique
        } else {
            baseFilename = "\(id.uuidString).\(fileExtension)"
        }
        let imageURL = destinationDirectory.appending(path: baseFilename)
        try pngData.write(to: imageURL, options: [.atomic])

        let item = CaptureItem(
            id: id,
            fileURL: imageURL,
            createdAt: Date(),
            pixelWidth: Int(pixelSize.width.rounded()),
            pixelHeight: Int(pixelSize.height.rounded()),
            displayID: displayID,
            sourceType: .area,
            mediaType: .image,
            duration: nil
        )

        items.insert(item, at: 0)
        try persist()
        return item
    }

    func nextRecordingURL() throws -> URL {
        try ensureDirectoriesExist()
        return recordingsDirectory.appending(path: "\(UUID().uuidString).mov")
    }

    @discardableResult
    func addRecording(
        fileURL: URL,
        pixelSize: CGSize,
        displayID: UInt32?,
        duration: TimeInterval
    ) throws -> CaptureItem {
        try ensureDirectoriesExist()

        let item = CaptureItem(
            id: UUID(),
            fileURL: fileURL,
            createdAt: Date(),
            pixelWidth: Int(pixelSize.width.rounded()),
            pixelHeight: Int(pixelSize.height.rounded()),
            displayID: displayID,
            sourceType: .recording,
            mediaType: .video,
            duration: duration
        )

        items.insert(item, at: 0)
        try persist()
        return item
    }

    func delete(_ item: CaptureItem) throws {
        items.removeAll { $0.id == item.id }

        if fileManager.fileExists(atPath: item.fileURL.path) {
            try fileManager.removeItem(at: item.fileURL)
        }

        try persist()
    }

    func clear() throws {
        let existingItems = items
        items.removeAll()

        for item in existingItems where fileManager.fileExists(atPath: item.fileURL.path) {
            try fileManager.removeItem(at: item.fileURL)
        }

        try persist()
    }

    func reload() {
        load()
    }

    static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")

        return base
            .appending(path: "Snipr", directoryHint: .isDirectory)
            .appending(path: "Captures", directoryHint: .isDirectory)
    }

    private func load() {
        do {
            try ensureDirectoriesExist()

            guard fileManager.fileExists(atPath: indexURL.path) else {
                items = []
                return
            }

            let data = try Data(contentsOf: indexURL)
            let decodedItems = try JSONDecoder.snipr.decode([CaptureItem].self, from: data)

            items = decodedItems.filter { fileManager.fileExists(atPath: $0.fileURL.path) }
        } catch {
            items = []
        }
    }

    private func persist() throws {
        try ensureDirectoriesExist()
        let data = try JSONEncoder.snipr.encode(items)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
    }

    /// Strip path traversal segments and clamp to a single chain of folder
    /// names. Users can write `Work/Safari` and we'll honor that; anything
    /// resembling `..` or absolute paths gets dropped so a misconfigured rule
    /// can't escape the captures root.
    private static func sanitize(subfolder: String) -> String {
        let segments = subfolder
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { component -> String in
                let cleaned = component.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.replacingOccurrences(of: "..", with: "")
            }
            .filter { !$0.isEmpty }
        return segments.joined(separator: "/")
    }

    /// Disambiguate a user-friendly filename by appending ` (n)` if the base
    /// is already on disk. Keeps the captures folder readable when a
    /// template-based name collides (e.g. two captures within the same
    /// second).
    private static func uniqueFilename(in directory: URL, suggestion: String) -> String? {
        guard !suggestion.isEmpty else { return nil }
        let fileManager = FileManager.default
        let candidate = directory.appending(path: suggestion)
        if !fileManager.fileExists(atPath: candidate.path) {
            return suggestion
        }

        let url = URL(fileURLWithPath: suggestion)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        for index in 2...999 {
            let next = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let nextURL = directory.appending(path: next)
            if !fileManager.fileExists(atPath: nextURL.path) {
                return next
            }
        }
        return nil
    }
}

private extension JSONEncoder {
    static var snipr: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var snipr: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
