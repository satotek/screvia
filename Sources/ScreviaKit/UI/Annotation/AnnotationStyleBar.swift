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

            if tool == .text {
                Toggle(isOn: binding(\.isBold)) {
                    Image(systemName: "bold")
                }
                .toggleStyle(.button)
                .help(L10n.text("style.bold"))

                Picker(L10n.text("style.text"), selection: binding(\.textAppearance)) {
                    ForEach(TextAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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
        }
        .font(.callout)
        .controlSize(.small)
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
                    Image(nsImage: Self.swatchImage(color))
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
    private static func swatchImage(_ color: AnnotationColor) -> NSImage {
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
