import AppKit
import Foundation
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case ellipse
    case blur

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow:
            "Arrow"
        case .rectangle:
            "Box"
        case .ellipse:
            "Circle"
        case .blur:
            "Blur"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow:
            "arrow.up.right"
        case .rectangle:
            "rectangle"
        case .ellipse:
            "circle"
        case .blur:
            "drop.degreesign.slash"
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
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var ink: AnnotationInk
    var lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        ink: AnnotationInk,
        lineWidth: CGFloat = 5
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.ink = ink
        self.lineWidth = lineWidth
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
        hypot(end.x - start.x, end.y - start.y) > 8
    }
}
