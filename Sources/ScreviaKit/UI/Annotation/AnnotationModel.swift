import AppKit
import SwiftUI

nonisolated enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case arrow
    case highlight
    case text
    case blur
    case pixelate

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .arrow:
            return "arrow.up.right"
        case .highlight:
            return "highlighter"
        case .text:
            return "textformat"
        case .blur:
            return "eye.slash"
        case .pixelate:
            return "square.grid.3x3"
        }
    }

    var title: String {
        L10n.text("annotation.\(rawValue)")
    }

    /// Core Image filter backing this tool, if it is a redaction tool.
    var filterName: String? {
        switch self {
        case .blur:
            return "CIGaussianBlur"
        case .pixelate:
            return "CIPixellate"
        default:
            return nil
        }
    }

    /// Drawn from one end to the other, so it is edited by its two endpoints
    /// rather than by the box around it.
    var isLine: Bool {
        self == .arrow
    }
}

enum AnnotationZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 3.0
    static let step: CGFloat = 0.1

    static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

/// How an annotation is stroked. Line width is in image points, so it keeps
/// its proportion to the image at every zoom level and in the export.
nonisolated struct AnnotationStyle: Equatable {
    var color: CGColor
    var lineWidth: CGFloat

    static let standard = AnnotationStyle(
        color: CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1),
        lineWidth: 4
    )
}

/// `start` and `end` are fractions of the image (0...1, top-left origin), so
/// an annotation stays put under zoom and survives the downsampled preview.
nonisolated struct Annotation: Identifiable, Equatable {
    let id: UUID
    let tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var text: String?
    var style: AnnotationStyle

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        text: String? = nil,
        style: AnnotationStyle = .standard
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
        self.style = style
    }
}
