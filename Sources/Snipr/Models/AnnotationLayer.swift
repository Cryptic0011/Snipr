import AppKit
import Foundation
import SwiftUI

enum AnnotationKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case arrow
    case line
    case rectangle
    case ellipse
    case blur
    case text
    case step
    case highlight
    case pixelate
    case crop

    var id: String { rawValue }

    static var editorTools: [AnnotationKind] {
        allCases.filter { $0 != .crop }
    }

    var title: String {
        switch self {
        case .arrow:
            "Arrow"
        case .line:
            "Line"
        case .rectangle:
            "Box"
        case .ellipse:
            "Circle"
        case .blur:
            "Blur"
        case .text:
            "Text"
        case .step:
            "Step"
        case .highlight:
            "Highlight"
        case .pixelate:
            "Pixelate"
        case .crop:
            "Crop"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow:
            "arrow.up.right"
        case .line:
            "line.diagonal"
        case .rectangle:
            "rectangle"
        case .ellipse:
            "circle"
        case .blur:
            "drop.degreesign.slash"
        case .text:
            "textformat"
        case .step:
            "1.circle.fill"
        case .highlight:
            "highlighter"
        case .pixelate:
            "square.grid.3x3.fill"
        case .crop:
            "crop"
        }
    }
}

enum AnnotationInk: String, CaseIterable, Identifiable {
    case white
    case red
    case amber
    case blue
    case green

    var id: String { rawValue }

    var color: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        switch self {
        case .white:
            NSColor.white
        case .red:
            NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.30, alpha: 1.0)
        case .amber:
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.26, alpha: 1.0)
        case .blue:
            NSColor(calibratedRed: 0.36, green: 0.64, blue: 1.0, alpha: 1.0)
        case .green:
            NSColor(calibratedRed: 0.33, green: 0.86, blue: 0.50, alpha: 1.0)
        }
    }
}

struct AnnotationLayer: Identifiable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var start: CGPoint
    var end: CGPoint
    var ink: AnnotationInk
    var lineWidth: CGFloat
    /// User-supplied text content (used by Text and Step tools).
    var text: String
    /// Step number (used by Step tool).
    var stepNumber: Int
    /// Font size (used by Text tool).
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        start: CGPoint,
        end: CGPoint,
        ink: AnnotationInk,
        lineWidth: CGFloat = 5,
        text: String = "",
        stepNumber: Int = 1,
        fontSize: CGFloat = 28
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.ink = ink
        self.lineWidth = lineWidth
        self.text = text
        self.stepNumber = stepNumber
        self.fontSize = fontSize
    }

    var bounds: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var isMeaningful: Bool {
        switch kind {
        case .step:
            true // a single-point tap is meaningful for step badges
        case .text:
            !text.isEmpty
        default:
            hypot(end.x - start.x, end.y - start.y) > 8
        }
    }
}
