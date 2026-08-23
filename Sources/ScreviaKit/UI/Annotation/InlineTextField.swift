import AppKit
import SwiftUI

struct InlineTextField: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(L10n.text("annotation.textPlaceholder"))
                .foregroundStyle(.white.opacity(0.55))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
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
