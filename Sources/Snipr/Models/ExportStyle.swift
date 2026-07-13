import CoreGraphics
import Foundation
import SwiftUI

/// Codable sRGB color for persisted style choices.
struct RGBA: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(resolved.redComponent)
        green = Double(resolved.greenComponent)
        blue = Double(resolved.blueComponent)
        alpha = Double(resolved.alphaComponent)
    }
}

/// Output canvas shape. Non-auto aspects expand the padded canvas so the
/// background — never black bars — fills platform-standard frames.
enum CanvasAspect: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case widescreen
    case portrait
    case square
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .widescreen: "16:9"
        case .portrait: "9:16"
        case .square: "1:1"
        case .standard: "4:3"
        }
    }

    var ratio: Double? {
        switch self {
        case .auto: nil
        case .widescreen: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .square: 1
        case .standard: 4.0 / 3.0
        }
    }
}

/// User-adjustable export framing. Defaults reproduce the pre-style export
/// exactly (8% padding, radius 16, 45% shadow, canvas hugging the video).
struct ExportStyle: Codable, Equatable, Sendable {
    var paddingFraction: Double = 0.08
    var cornerRadius: Double = 16
    var shadowOpacity: Double = 0.45
    var aspect: CanvasAspect = .auto

    /// Padded canvas, then expanded — one dimension only, never shrunk —
    /// to the target aspect. Even-pixel rounding stays the compositor's job.
    func canvas(for videoSize: CGSize) -> (canvas: CGSize, padding: CGFloat) {
        // Belt-and-braces: even if a caller builds an ExportStyle directly
        // (bypassing load()'s clamping) with a negative paddingFraction, never
        // let padding go negative — that can shrink the canvas to zero/negative
        // and crash AVAssetExportSession ("renderSize must be positive").
        let padding = max(0, (min(videoSize.width, videoSize.height) * paddingFraction).rounded())
        var canvas = CGSize(
            width: videoSize.width + padding * 2,
            height: videoSize.height + padding * 2
        )
        if let ratio = aspect.ratio {
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        return (canvas, padding)
    }

    static let defaultsKey = "videoExportStyle"
    /// Screenshot export keeps its own style so it never clobbers the video one.
    static let screenshotDefaultsKey = "screenshotExportStyle"

    static func load(from defaults: UserDefaults = .standard, key: String = defaultsKey) -> ExportStyle {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(ExportStyle.self, from: data) else {
            return ExportStyle()
        }
        return stored.clamped()
    }

    func save(to defaults: UserDefaults = .standard, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    /// Clamps every field to the range its Style popover slider allows. A
    /// hand-edited or corrupted `videoExportStyle` defaults blob (e.g.
    /// paddingFraction ≤ -0.5) can otherwise reach `canvas(for:)` with a
    /// zero/negative canvas, which makes `AVAssetExportSession` throw an
    /// uncatchable NSInvalidArgumentException ("video composition must have
    /// a positive renderSize") and kill the process.
    func clamped() -> ExportStyle {
        var style = self
        style.paddingFraction = min(max(paddingFraction, 0), 0.30)
        style.cornerRadius = min(max(cornerRadius, 0), 40)
        style.shadowOpacity = min(max(shadowOpacity, 0), 1)
        return style
    }
}
