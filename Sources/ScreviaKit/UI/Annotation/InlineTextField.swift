import AppKit
import SwiftUI

struct InlineTextField: View {
    @Binding var text: String
    /// The annotation's own font at the current zoom, so the text does not
    /// jump in size when editing ends.
    let font: NSFont
    let horizontalPadding: CGFloat
    /// Wraps within the field's width, for a text box dragged out.
    var wraps = false
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(L10n.text("annotation.textPlaceholder"))
                .foregroundStyle(.white.opacity(0.55)),
            axis: wraps ? .vertical : .horizontal
        )
        .textFieldStyle(.plain)
        .font(Font(font))
        .foregroundStyle(.white)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ScreviaTheme.accent, lineWidth: 2)
        }
        .shadow(color: ScreviaTheme.accent.opacity(0.3), radius: 12)
        .focused($isFocused)
        .onSubmit {
            onCommit()
        }
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .accessibilityLabel(L10n.text("annotation.text"))
    }
}
