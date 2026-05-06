import Foundation

enum CaptureSourceType: String, Codable, Sendable {
    case area
    case recording
}

enum CaptureMediaType: String, Codable, Sendable {
    case image
    case video
}

struct CaptureItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let displayID: UInt32?
    let sourceType: CaptureSourceType
    let mediaType: CaptureMediaType
    let duration: TimeInterval?

    var filename: String {
        fileURL.lastPathComponent
    }

    var dimensionsText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var detailText: String {
        switch mediaType {
        case .image:
            dimensionsText
        case .video:
            if let duration {
                "\(dimensionsText) • \(Self.durationFormatter.string(from: duration) ?? "\(Int(duration))s")"
            } else {
                dimensionsText
            }
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case fileURL
        case createdAt
        case pixelWidth
        case pixelHeight
        case displayID
        case sourceType
        case mediaType
        case duration
    }

    init(
        id: UUID,
        fileURL: URL,
        createdAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        displayID: UInt32?,
        sourceType: CaptureSourceType,
        mediaType: CaptureMediaType,
        duration: TimeInterval?
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayID = displayID
        self.sourceType = sourceType
        self.mediaType = mediaType
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        displayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID)
        sourceType = try container.decode(CaptureSourceType.self, forKey: .sourceType)
        mediaType = try container.decodeIfPresent(CaptureMediaType.self, forKey: .mediaType) ?? .image
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }
}
