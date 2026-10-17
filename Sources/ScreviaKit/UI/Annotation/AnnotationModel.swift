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
    case balloon
    case step
    case blur
    case pixelate
    case magnifier
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
        case .balloon:
            return "bubble.left"
        case .step:
            return "1.circle"
        case .blur:
            return "eye.slash"
        case .pixelate:
            return "square.grid.3x3"
        case .magnifier:
            return "plus.magnifyingglass"
        case .crop:
            return "crop"
        case .liveText:
            return "text.viewfinder"
        }
    }

    var title: String {
        L10n.text("annotation.\(rawValue)")
    }

    /// What the tool does and how to use it, for its tooltip.
    var usage: String {
        L10n.text("annotation.\(rawValue).usage")
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

    /// Shows part of the image under it, so it needs the image's pixels to
    /// draw: blurred, pixelated or enlarged.
    var samplesImage: Bool {
        filterName != nil || self == .magnifier
    }

    /// Holds text the user types, edited in place on the canvas.
    var hasText: Bool {
        self == .text || self == .balloon
    }

    /// Drawn from one end to the other, so it is edited by its two endpoints
    /// rather than by the box around it.
    var isLine: Bool {
        self == .line || self == .arrow
    }

    /// Sized by the font size rather than by dragging, so the box follows
    /// the style and has no resize handles.
    var isSizedByFont: Bool {
        self == .text || self == .balloon || self == .step
    }

    /// Which style settings apply, so the style bar shows only those.
    var usesLineWidth: Bool {
        [.rectangle, .ellipse, .line, .arrow, .freehand, .balloon, .magnifier].contains(self)
    }

    var usesFill: Bool {
        [.rectangle, .ellipse, .text, .balloon].contains(self)
    }

    var usesColor: Bool {
        [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .balloon, .step, .magnifier].contains(self)
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

    /// `#RRGGBB`, as design tools write it.
    var hexString: String {
        func byte(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
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

    static let paletteKeys: [AnnotationColor: String] = [
        .red: "red", .orange: "orange", .yellow: "yellow", .green: "green",
        .blue: "blue", .purple: "purple", .black: "black", .white: "white"
    ]

    /// What to call it: the palette colour's name, or its hex code for a
    /// custom one. Swatches show only colour, which VoiceOver cannot.
    var name: String {
        Self.paletteKeys[self].map { L10n.text("color.\($0)") } ?? hexString
    }
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

nonisolated enum MagnifierShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case circle

    var id: String { rawValue }

    var title: String {
        L10n.text("style.magnifierShape.\(rawValue)")
    }

    var symbolName: String {
        switch self {
        case .rectangle: "square"
        case .circle: "circle"
        }
    }
}

nonisolated enum ArrowHead: String, Codable, CaseIterable, Identifiable {
    /// Two strokes, as the arrow has always been drawn.
    case open
    case filled

    var id: String { rawValue }

    var title: String {
        L10n.text("style.arrowHead.\(rawValue)")
    }

    var symbolName: String {
        switch self {
        case .open: "arrow.right"
        case .filled: "arrowtriangle.right.fill"
        }
    }
}

/// The system font's designs. Every one falls back to the system's own
/// Japanese font, so labels in either language keep the chosen weight.
nonisolated enum FontDesign: String, Codable, CaseIterable, Identifiable {
    case standard
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        L10n.text("style.fontDesign.\(rawValue)")
    }

    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

/// How steps count: ①②③, Ⓐ Ⓑ Ⓒ or Roman numerals, as ShareX offers.
nonisolated enum StepFormat: String, Codable, CaseIterable, Identifiable {
    case number
    case letter
    case roman

    var id: String { rawValue }

    var title: String {
        L10n.text("style.stepFormat.\(rawValue)")
    }

    /// The label for the `number`th step, counting from 1. Letters run on
    /// past Z as AA, AB, as spreadsheet columns do.
    func label(_ number: Int) -> String {
        let number = max(number, 1)
        switch self {
        case .number:
            return "\(number)"
        case .letter:
            var remaining = number
            var label = ""
            while remaining > 0 {
                remaining -= 1
                label = String(UnicodeScalar(UInt8(65 + remaining % 26))) + label
                remaining /= 26
            }
            return label
        case .roman:
            let numerals: [(Int, String)] = [
                (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
            ]
            var remaining = number
            var label = ""
            for (value, numeral) in numerals {
                while remaining >= value {
                    label += numeral
                    remaining -= value
                }
            }
            return label
        }
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
    /// How much the magnifier enlarges.
    var magnification: CGFloat = 2
    /// Round by default, like ShareX's.
    var magnifierShape: MagnifierShape = .circle
    var arrowHead: ArrowHead = .open
    /// A head at the start as well as the end.
    var arrowBothEnds = false
    /// For rectangles; zero is square corners.
    var cornerRadius: CGFloat = 0
    var stepFormat: StepFormat = .number
    var fontDesign: FontDesign = .standard

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
    static let magnifications: [CGFloat] = [1.5, 2, 3, 4]
    static let cornerRadii: [CGFloat] = [0, 4, 8, 16]
}

// In an extension, so the memberwise initializer survives.
nonisolated extension AnnotationStyle {
    private enum CodingKeys: String, CodingKey {
        case color, fillColor, lineWidth, fontSize, isBold, textAppearance, hasShadow
        case magnification, magnifierShape
        case arrowHead, arrowBothEnds, cornerRadius, stepFormat, fontDesign
    }

    /// The style is kept in preferences and in archived edits, both written
    /// before the later settings existed. Synthesized decoding would reject
    /// them for the missing keys, losing the remembered style and the edit,
    /// so every setting added since the first release is optional here.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(AnnotationColor.self, forKey: .color)
        fillColor = try container.decodeIfPresent(AnnotationColor.self, forKey: .fillColor)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        isBold = try container.decode(Bool.self, forKey: .isBold)
        textAppearance = try container.decode(TextAppearance.self, forKey: .textAppearance)
        hasShadow = try container.decode(Bool.self, forKey: .hasShadow)
        magnification = try container.decodeIfPresent(CGFloat.self, forKey: .magnification) ?? 2
        magnifierShape = try container.decodeIfPresent(MagnifierShape.self, forKey: .magnifierShape) ?? .circle
        arrowHead = try container.decodeIfPresent(ArrowHead.self, forKey: .arrowHead) ?? .open
        arrowBothEnds = try container.decodeIfPresent(Bool.self, forKey: .arrowBothEnds) ?? false
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        stepFormat = try container.decodeIfPresent(StepFormat.self, forKey: .stepFormat) ?? .number
        fontDesign = try container.decodeIfPresent(FontDesign.self, forKey: .fontDesign) ?? .standard
    }
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
    /// The width text wraps at, in image points, for a text box dragged
    /// out rather than clicked. Nil sizes the box to one line of text.
    var textWidth: CGFloat?
    /// Where a speech balloon points, in the same space as `start`. Nil for
    /// every other tool, which is also what edits saved before balloons
    /// decode to.
    var tail: CGPoint?
    /// The point a bent line or arrow passes through halfway along, in the
    /// same space as `start`. Nil is straight.
    var bend: CGPoint?
    /// The middle of what a magnifier enlarges, in the same space as
    /// `start`. Nil enlarges what is under the magnifier, following it as it
    /// moves; set, the magnifier can sit away from what it shows.
    var focus: CGPoint?
    var style: AnnotationStyle

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint] = [],
        text: String? = nil,
        textWidth: CGFloat? = nil,
        tail: CGPoint? = nil,
        bend: CGPoint? = nil,
        focus: CGPoint? = nil,
        style: AnnotationStyle = .standard
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.points = points
        self.text = text
        self.textWidth = textWidth
        self.tail = tail
        self.bend = bend
        self.focus = focus
        self.style = style
    }

    /// A copy with a new identity, so it can be selected and undone apart
    /// from the original.
    func duplicated() -> Annotation {
        Annotation(tool: tool, start: start, end: end, points: points, text: text, textWidth: textWidth, tail: tail, bend: bend, focus: focus, style: style)
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

/// Everything the editor can undo: the annotations, the crop, and the
/// effects on the whole image.
nonisolated struct AnnotationDocument: Equatable, Codable {
    var annotations: [Annotation] = []
    /// The visible part of the image, in annotation space. Cropping only
    /// narrows this, so annotations outside it survive an undo.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var effects = ImageEffects()
}

// In an extension, so the memberwise initializer survives.
nonisolated extension AnnotationDocument {
    private enum CodingKeys: String, CodingKey {
        case annotations
        case crop
        case effects
    }

    /// Edits archived before effects existed have no `effects` key, and
    /// synthesized decoding would reject them despite the default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotations = try container.decode([Annotation].self, forKey: .annotations)
        crop = try container.decode(CGRect.self, forKey: .crop)
        effects = try container.decodeIfPresent(ImageEffects.self, forKey: .effects) ?? ImageEffects()
    }
}

/// Framing added around the whole image on export, outside the crop, as
/// ShareX's image effects do. Sizes are in image points.
nonisolated struct ImageEffects: Codable, Equatable {
    var borderColor: AnnotationColor?
    var borderWidth: CGFloat = 6
    var hasShadow = false

    var isEmpty: Bool {
        borderColor == nil && !hasShadow
    }

    /// The border's thickness, or zero without one.
    var borderThickness: CGFloat {
        borderColor == nil ? 0 : borderWidth
    }

    static let borderWidths: [CGFloat] = [2, 6, 12]
    /// Room around the bordered image for the shadow to fade out in.
    static let shadowMargin: CGFloat = 32
    static let shadowBlur: CGFloat = 18
    static let shadowDrop: CGFloat = 6
}
