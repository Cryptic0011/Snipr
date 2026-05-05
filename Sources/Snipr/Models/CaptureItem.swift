import Foundation

enum CaptureSourceType: String, Codable, Sendable {
    case area
}

struct CaptureItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let displayID: UInt32?
    let sourceType: CaptureSourceType

    var filename: String {
        fileURL.lastPathComponent
    }

    var dimensionsText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
}
