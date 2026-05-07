import AppKit
import Foundation
import UniformTypeIdentifiers

/// Output format the user has selected for new captures. Quality only applies
/// to lossy formats; PNG ignores it. Default is `.png` with no quality knob.
enum CaptureFormat: Sendable, Equatable, Codable {
    case png
    case jpeg(quality: Double)
    case heic(quality: Double)

    static let `default`: CaptureFormat = .png

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    /// Pasteboard type for clipboard writes. PNG goes on `.png`, lossy
    /// formats land on `.tiff` (NSImage's lossless lingua franca) so paste
    /// targets that don't grok HEIC still get pixels. The lossy file on disk
    /// uses the chosen container; this branch is just clipboard interop.
    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png: .png
        case .jpeg, .heic: .tiff
        }
    }

    /// Clamped 0…1 quality for lossy formats. `nil` when not applicable.
    var quality: Double? {
        switch self {
        case .png: nil
        case .jpeg(let q), .heic(let q): max(0, min(1, q))
        }
    }
}

extension NSPasteboard.PasteboardType {
    /// `public.png` UTI as an `NSPasteboard.PasteboardType`. Standard library
    /// only exposes `.tiff` and `.pdf` etc. by name — every other UTI we want
    /// to write goes through string init.
    static let png = NSPasteboard.PasteboardType("public.png")
}
