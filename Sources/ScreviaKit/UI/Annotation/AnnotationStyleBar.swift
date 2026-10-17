import AppKit
import SwiftUI

/// The style settings that apply to `tool`. Each change is handed back as an
/// edit rather than a whole style, so applying it to a selected annotation
/// changes only that one setting.
struct AnnotationStyleBar: View {
    let style: AnnotationStyle
    let tool: AnnotationTool
    let onChange: (@escaping (inout AnnotationStyle) -> Void) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if tool.usesColor {
                colorSwatches
            }

            if tool.usesFill {
                fillMenu
            }

            if tool.usesLineWidth {
                Stepper(
                    L10n.format("style.lineWidth", Int(style.lineWidth)),
                    value: binding(\.lineWidth),
                    in: AnnotationStyle.lineWidthRange,
                    step: 1
                )
                .fixedSize()
            }

            if tool.isSizedByFont {
                Stepper(
                    L10n.format("style.fontSize", Int(style.fontSize)),
                    value: binding(\.fontSize),
                    in: AnnotationStyle.fontSizeRange,
                    step: 2
                )
                .fixedSize()
            }

            if tool.hasText {
                Picker(L10n.text("style.fontDesign"), selection: binding(\.fontDesign)) {
                    ForEach(FontDesign.allCases) { design in
                        Text(design.title).tag(design)
                    }
                }
                .fixedSize()
                .help(L10n.text("style.fontDesign"))

                Toggle(isOn: binding(\.isBold)) {
                    Image(systemName: "bold")
                }
                .toggleStyle(.button)
                .help(L10n.text("style.bold"))
            }

            if tool == .text {
                Picker(L10n.text("style.text"), selection: binding(\.textAppearance)) {
                    ForEach(TextAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if tool == .magnifier {
                magnifierControls
            }

            if tool == .arrow {
                arrowControls
            }

            if tool == .rectangle {
                Picker(L10n.text("style.cornerRadius"), selection: binding(\.cornerRadius)) {
                    ForEach(AnnotationStyle.cornerRadii, id: \.self) { radius in
                        Text(radius == 0 ? L10n.text("style.squareCorners") : L10n.format("effects.points", Int(radius)))
                            .tag(radius)
                    }
                }
                .fixedSize()
                .help(L10n.text("style.cornerRadius"))
            }

            if tool == .step {
                Picker(L10n.text("style.stepFormat"), selection: binding(\.stepFormat)) {
                    ForEach(StepFormat.allCases) { format in
                        Text(format.label(1)).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L10n.text("style.stepFormat"))
            }

            if tool.usesShadow {
                Toggle(L10n.text("style.shadow"), isOn: binding(\.hasShadow))
                    .toggleStyle(.checkbox)
            }

            if tool == .crop {
                Text(L10n.text("annotation.cropHint"))
                    .foregroundStyle(.secondary)
            }

            if tool == .liveText {
                Text(L10n.text("annotation.liveTextHint"))
                    .foregroundStyle(.secondary)
            }

            if tool == .magnifier {
                Text(L10n.text("annotation.magnifierHint"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }

    private var arrowControls: some View {
        HStack(spacing: 8) {
            Picker(L10n.text("style.arrowHead"), selection: binding(\.arrowHead)) {
                ForEach(ArrowHead.allCases) { head in
                    Image(systemName: head.symbolName)
                        .accessibilityLabel(head.title)
                        .tag(head)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L10n.text("style.arrowHead"))

            Toggle(isOn: binding(\.arrowBothEnds)) {
                Image(systemName: "arrow.left.and.right")
            }
            .toggleStyle(.button)
            .help(L10n.text("style.arrowBothEnds"))
        }
    }

    private var magnifierControls: some View {
        HStack(spacing: 8) {
            Picker(L10n.text("style.magnification"), selection: binding(\.magnification)) {
                ForEach(AnnotationStyle.magnifications, id: \.self) { zoom in
                    Text(L10n.format("style.magnificationValue", zoom.formatted())).tag(zoom)
                }
            }
            .fixedSize()
            .help(L10n.text("style.magnification"))

            Picker(L10n.text("style.magnifierShape"), selection: binding(\.magnifierShape)) {
                ForEach(MagnifierShape.allCases) { shape in
                    Image(systemName: shape.symbolName)
                        .accessibilityLabel(shape.title)
                        .tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(L10n.text("style.magnifierShape"))
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: 5) {
            ForEach(AnnotationColor.palette, id: \.self) { color in
                Button {
                    onChange { $0.color = color }
                } label: {
                    swatch(color, isSelected: style.color == color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .help(color.name)
            }

            ColorPicker(
                L10n.text("style.customColor"),
                selection: Binding(
                    get: { Color(cgColor: style.color.cgColor) },
                    set: { newValue in
                        if let color = AnnotationColor(NSColor(newValue).cgColor) {
                            onChange { $0.color = color }
                        }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .help(L10n.text("style.customColor"))
        }
    }

    private var fillMenu: some View {
        Menu {
            Button(L10n.text("style.noFill")) {
                onChange { $0.fillColor = nil }
            }
            ForEach(AnnotationColor.palette, id: \.self) { color in
                Button {
                    onChange { $0.fillColor = color }
                } label: {
                    Label { Text(color.name) } icon: { Image(nsImage: Self.swatchImage(color)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(L10n.text("style.fill"))
                if let fill = style.fillColor {
                    swatch(fill, isSelected: false)
                } else {
                    Image(systemName: "nosign")
                }
            }
        }
        .fixedSize()
    }

    private func swatch(_ color: AnnotationColor, isSelected: Bool) -> some View {
        Circle()
            .fill(Color(cgColor: color.cgColor))
            .frame(width: 14, height: 14)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            }
            .padding(2)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
    }

    /// Menu items show images, not arbitrary views, so the fill swatches
    /// are drawn by hand.
    static func swatchImage(_ color: AnnotationColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AnnotationStyle, Value>) -> Binding<Value> {
        Binding(
            get: { style[keyPath: keyPath] },
            set: { newValue in
                onChange { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

#if DEBUG
#Preview("Style bar") {
    VStack(alignment: .leading, spacing: 12) {
        AnnotationStyleBar(style: .standard, tool: .rectangle, onChange: { _ in })
        AnnotationStyleBar(style: .standard, tool: .text, onChange: { _ in })
    }
    .padding()
}
#endif
