import SwiftUI

/// Laid out as Mac apps' settings are: labels right-aligned in a column,
/// their controls to the right, groups split by a line.
enum PreferencesLayout {
    static let labelWidth: CGFloat = 170
    static let spacing: CGFloat = 12
}

struct PreferencesRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String = "", @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PreferencesLayout.spacing) {
            Text(label)
                .multilineTextAlignment(.trailing)
                .frame(width: PreferencesLayout.labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A line of explanation under a control, wrapped to the control column.
struct PreferencesHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A slider with its value written beside it.
struct PreferencesSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 220)
            Text(format(value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// The capture backgrounds as pictures of a window on each, since a name
/// such as "Mist" says little about how a capture will look.
struct BackgroundStylePicker: View {
    @Binding var selection: BackgroundStyle

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(BackgroundStyle.allCases) { style in
                let isSelected = selection == style
                Button {
                    selection = style
                } label: {
                    VStack(spacing: 5) {
                        BackgroundSwatch(style: style)
                            .frame(width: 56, height: 40)
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: isSelected ? 2.5 : 1
                                    )
                            }
                        Text(style.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // Lines the row's label up with the swatches rather than with the
        // names under them.
        .alignmentGuide(.firstTextBaseline) { $0[.top] + 14 }
    }
}

private struct BackgroundSwatch: View {
    let style: BackgroundStyle

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if style == .none {
                Checkerboard()
            } else {
                style.previewColor
            }

            // A window in the lower right, as a capture sits on its background.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.26))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                    }
                    .frame(height: 4)
                    .padding(4)
                }
                .frame(width: 38, height: 27)
                .offset(x: style == .none ? 0 : -1, y: style == .none ? 0 : -1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The grey squares that stand for transparency.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 5
            for row in 0..<Int((size.height / square).rounded(.up)) {
                for column in 0..<Int((size.width / square).rounded(.up)) {
                    let rect = CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)
                    let shade = (row + column).isMultiple(of: 2) ? 0.42 : 0.3
                    context.fill(Path(rect), with: .color(Color(white: shade)))
                }
            }
        }
    }
}

/// Where the thumbnail appears, chosen on a picture of the screen.
struct ThumbnailPositionPicker: View {
    @Binding var selection: ThumbnailPosition

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }

                ForEach(ThumbnailPosition.allCases) { position in
                    let isSelected = selection == position
                    Button {
                        selection = position
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.14))
                            .frame(width: 24, height: 15)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(position.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                    .padding(6)
                }
            }
            .frame(width: 112, height: 70)

            Text(selection.displayName)
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.firstTextBaseline) { $0[.top] + 14 }
    }
}

private extension ThumbnailPosition {
    var alignment: Alignment {
        switch self {
        case .bottomRight: .bottomTrailing
        case .bottomLeft: .bottomLeading
        case .topRight: .topTrailing
        case .topLeft: .topLeading
        }
    }
}
