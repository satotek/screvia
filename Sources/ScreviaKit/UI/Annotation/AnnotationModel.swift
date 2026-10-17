import AppKit
import SwiftUI

nonisolated enum AnnotationTool: String, Codable, CaseIterable, Identifiable {
    case select
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand
    case highlight
    case text
    case step
    case blur
    case pixelate
    case crop
    /// Not an annotation: selects text in the image, through Live Text.
    case liveText

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .line:
            return "line.diagonal"
        case .arrow:
            return "arrow.up.right"
        case .freehand:
            return "scribble.variable"
        case .highlight:
            return "highlighter"
        case .text:
            return "textformat"
        case .step:
            return "1.circle"
        case .blur:
            return "eye.slash"
        case .pixelate:
            return "square.grid.3x3"
        case .crop:
            return "crop"
        case .liveText:
            return "text.viewfinder"
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
        self == .line || self == .arrow
    }

    /// Sized by the font size rather than by dragging, so the box follows
    /// the style and has no resize handles.
    var isSizedByFont: Bool {
        self == .text || self == .step
    }

    /// Which style settings apply, so the style bar shows only those.
    var usesLineWidth: Bool {
        [.rectangle, .ellipse, .line, .arrow, .freehand].contains(self)
    }

    var usesFill: Bool {
        [.rectangle, .ellipse, .text].contains(self)
    }

    var usesColor: Bool {
        [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .step].contains(self)
    }

    var usesShadow: Bool {
        usesColor
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

/// An sRGB colour that can be stored in preferences, which CGColor cannot.
nonisolated struct AnnotationColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Black or white, whichever stands out against this colour; used for
    /// text outlines and step numbers.
    var contrasting: AnnotationColor {
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.6 ? .black : .white
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(_ cgColor: CGColor) {
        guard
            let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
            let components = converted.components, components.count >= 3
        else {
            return nil
        }
        self.init(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2]),
            alpha: Double(converted.alpha)
        )
    }

    static let red = AnnotationColor(red: 1, green: 0.23, blue: 0.19)
    static let orange = AnnotationColor(red: 1, green: 0.58, blue: 0)
    static let yellow = AnnotationColor(red: 1, green: 0.8, blue: 0)
    static let green = AnnotationColor(red: 0.2, green: 0.78, blue: 0.35)
    static let blue = AnnotationColor(red: 0, green: 0.48, blue: 1)
    static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    static let black = AnnotationColor(red: 0, green: 0, blue: 0)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

nonisolated enum TextAppearance: String, Codable, CaseIterable, Identifiable {
    /// On a filled box, the fill colour or translucent black.
    case background
    /// Outlined in a contrasting colour, so it reads on any capture.
    case outline
    case plain

    var id: String { rawValue }

    var title: String {
        L10n.text("style.text.\(rawValue)")
    }
}

/// How an annotation looks. Sizes are in image points, so they keep their
/// proportion to the image at every zoom level and in the export.
nonisolated struct AnnotationStyle: Codable, Equatable {
    var color: AnnotationColor
    /// Fills shapes, and is the box behind background-style text.
    var fillColor: AnnotationColor?
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var isBold: Bool
    var textAppearance: TextAppearance
    var hasShadow: Bool

    static let standard = AnnotationStyle(
        color: .red,
        fillColor: nil,
        lineWidth: 4,
        fontSize: 20,
        isBold: true,
        textAppearance: .background,
        hasShadow: false
    )

    static let lineWidthRange: ClosedRange<CGFloat> = 1...24
    static let fontSizeRange: ClosedRange<CGFloat> = 8...144
}

/// `start` and `end` are fractions of the image (0...1, top-left origin), so
/// an annotation stays put under zoom and survives the downsampled preview.
nonisolated struct Annotation: Identifiable, Equatable, Codable {
    let id: UUID
    let tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    /// The stroke of a freehand drawing, in the same space as `start`.
    var points: [CGPoint]
    var text: String?
    var style: AnnotationStyle

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint] = [],
        text: String? = nil,
        style: AnnotationStyle = .standard
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.style = style
    }

    /// A copy with a new identity, so it can be selected and undone apart
    /// from the original.
    func duplicated() -> Annotation {
        Annotation(tool: tool, start: start, end: end, points: points, text: text, style: style)
    }

    /// The number each step marker shows: its position among the steps, so
    /// deleting one renumbers the rest.
    static func stepNumbers(in annotations: [Annotation]) -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for annotation in annotations where annotation.tool == .step {
            numbers[annotation.id] = numbers.count + 1
        }
        return numbers
    }
}

/// Everything the editor can undo: the annotations, and the crop.
nonisolated struct AnnotationDocument: Equatable, Codable {
    var annotations: [Annotation] = []
    /// The visible part of the image, in annotation space. Cropping only
    /// narrows this, so annotations outside it survive an undo.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
}
