import CoreGraphics

/// Preset tints for the synthetic recording cursor. Presets, not a color
/// picker — same philosophy as BeautifyStyle / WebcamBorderColor.
enum CursorColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case white
    case black
    case brass
    case blue
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Arrow body fill.
    var fill: CGColor {
        switch self {
        case .white: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        case .brass: CGColor(red: 0.80, green: 0.67, blue: 0.33, alpha: 1)
        case .blue: CGColor(red: 0.25, green: 0.51, blue: 0.96, alpha: 1)
        case .red: CGColor(red: 0.91, green: 0.28, blue: 0.24, alpha: 1)
        }
    }

    /// Contrasting outline so the arrow reads on any content.
    var outline: CGColor {
        switch self {
        case .white: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
        default: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        }
    }
}
