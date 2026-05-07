import AppKit
import CoreGraphics
import Foundation

/// Output format for sampled colors. Persisted via `SniprPreferences`; the
/// default is hex because that's what most designers / web devs paste back in.
enum ColorOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case hex
    case rgb
    case hsl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex: "Hex (#RRGGBB)"
        case .rgb: "RGB(r, g, b)"
        case .hsl: "HSL(h, s%, l%)"
        }
    }
}

/// Pure-math helpers for the color picker / pixel sampler. Kept out of any
/// view so it's trivially unit-testable.
enum ColorPicker {
    /// Format a sampled color (each channel in [0, 1]) according to the chosen
    /// output format.
    static func format(red: Double, green: Double, blue: Double, format: ColorOutputFormat) -> String {
        let r = clampByte(red)
        let g = clampByte(green)
        let b = clampByte(blue)

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = rgbToHSL(r: red, g: green, b: blue)
            let hi = Int(h.rounded())
            let si = Int((s * 100).rounded())
            let li = Int((l * 100).rounded())
            return "hsl(\(hi), \(si)%, \(li)%)"
        }
    }

    /// Sample the pixel at `point` in the given image. `point` is in image
    /// coordinates (top-left origin). Returns linear sRGB-ish components in
    /// [0, 1] suitable for round-tripping through the formatters.
    static func sample(image: CGImage, at point: CGPoint) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let x = max(0, min(image.width - 1, Int(point.x)))
        let y = max(0, min(image.height - 1, Int(point.y)))

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * 1
        var data = [UInt8](repeating: 0, count: bytesPerPixel)
        guard let ctx = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.translateBy(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let r = Double(data[0]) / 255
        let g = Double(data[1]) / 255
        let b = Double(data[2]) / 255
        let a = Double(data[3]) / 255
        return (r, g, b, a)
    }

    private static func clampByte(_ component: Double) -> Int {
        Int((max(0, min(1, component)) * 255).rounded())
    }

    /// Standard RGB → HSL conversion. Returns hue in degrees [0, 360),
    /// saturation and lightness in [0, 1].
    static func rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let l = (maxV + minV) / 2

        guard maxV != minV else {
            return (0, 0, l)
        }

        let delta = maxV - minV
        let s = l > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)

        var h: Double
        switch maxV {
        case r:
            h = (g - b) / delta + (g < b ? 6 : 0)
        case g:
            h = (b - r) / delta + 2
        default:
            h = (r - g) / delta + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        if h >= 360 { h -= 360 }
        return (h, s, l)
    }
}
