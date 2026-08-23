import SwiftUI

enum ScreviaTheme {
    static let accent = Color(red: 0.26, green: 0.56, blue: 0.98)
    static let signal = Color(red: 1.0, green: 0.43, blue: 0.28)
    static let ink = Color(red: 0.075, green: 0.09, blue: 0.13)
    static let quietInk = Color(red: 0.17, green: 0.20, blue: 0.26)
    static let mint = Color(red: 0.35, green: 0.84, blue: 0.66)

    /// Neutral fill used by tiles, chips and rows. Hover lifts it slightly
    /// instead of introducing a new colour, so the accent stays meaningful.
    static let surface = Color.primary.opacity(0.05)
    static let surfaceHover = Color.primary.opacity(0.09)
    static let hairline = Color.primary.opacity(0.09)

    static let displayFont = Font.system(size: 24, weight: .bold, design: .rounded)
    static let utilityFont = Font.system(size: 10, weight: .semibold, design: .monospaced)

    /// Section headings. Sentence case at UI weight — the all-caps monospaced
    /// treatment reads as decoration in a menu bar popover.
    static let sectionFont = Font.system(size: 11, weight: .semibold)
    static let keycapFont = Font.system(size: 10, weight: .medium, design: .rounded)
}

struct ScreviaSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
    }
}

#if DEBUG
#Preview("Surface") {
    ScreviaSurface {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screvia").font(ScreviaTheme.displayFont)
            Text("SURFACE")
                .font(ScreviaTheme.utilityFont)
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
    .padding(40)
}
#endif
