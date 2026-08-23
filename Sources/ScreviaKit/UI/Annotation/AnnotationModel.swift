import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
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
}

enum AnnotationZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 3.0
    static let step: CGFloat = 0.1

    static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

struct Annotation: Identifiable {
    let id: UUID
    let tool: AnnotationTool
    let start: CGPoint
    let end: CGPoint
    var text: String?

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        text: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
    }
}
