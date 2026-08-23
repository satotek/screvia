import AppKit
import SwiftUI

@MainActor
final class FloatingThumbnailController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(
        capture: CaptureItem,
        settings: ScreviaSettings,
        onEdit: @escaping () -> Void,
        onPin: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 238),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let content = ThumbnailView(
            capture: capture,
            previewImage: ImagePreview.downsample(capture.image, maxPixelDimension: 1_024),
            onEdit: { [weak self] in
                self?.dismiss()
                onEdit()
            },
            onPin: { [weak self] in
                self?.dismiss()
                onPin()
            },
            onCopy: onCopy,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: content)

        let screen = ScreenUtilities.screen(for: capture.displayID) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            panel.setFrameOrigin(origin(for: panel.frame.size, on: screen, position: settings.thumbnailPosition))
        }

        self.panel = panel
        panel.orderFrontRegardless()

        let duration = max(1, settings.thumbnailDuration)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func origin(
        for size: NSSize,
        on screen: NSScreen,
        position: ThumbnailPosition
    ) -> NSPoint {
        let frame = screen.visibleFrame
        let margin: CGFloat = 18

        switch position {
        case .bottomRight:
            return NSPoint(x: frame.maxX - size.width - margin, y: frame.minY + margin)
        case .bottomLeft:
            return NSPoint(x: frame.minX + margin, y: frame.minY + margin)
        case .topRight:
            return NSPoint(x: frame.maxX - size.width - margin, y: frame.maxY - size.height - margin)
        case .topLeft:
            return NSPoint(x: frame.minX + margin, y: frame.maxY - size.height - margin)
        }
    }
}

private struct ThumbnailView: View {
    let capture: CaptureItem
    let previewImage: NSImage
    let onEdit: () -> Void
    let onPin: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScreviaSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ScreviaTheme.mint)
                            .frame(width: 6, height: 6)
                        Text(L10n.text("app.captured"))
                            .font(ScreviaTheme.utilityFont)
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("app.dismiss"))
                }

                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 266, maxHeight: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .onDrag {
                        NSItemProvider(object: capture.fileURL as NSURL)
                    }

                HStack(spacing: 8) {
                    Text(capture.fileURL.lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pixelSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 7) {
                    actionButton("pencil", L10n.text("app.edit"), action: onEdit, prominent: true)
                    actionButton("doc.on.doc", L10n.text("app.copy"), action: onCopy)
                    actionButton("pin", L10n.text("app.pin"), action: onPin)
                }
            }
            .padding(13)
        }
    }

    private var pixelSize: String {
        "\(Int(capture.image.size.width.rounded())) × \(Int(capture.image.size.height.rounded()))"
    }

    private func actionButton(
        _ symbol: String,
        _ title: String,
        action: @escaping () -> Void,
        prominent: Bool = false
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? ScreviaTheme.accent : .secondary)
    }
}

#if DEBUG
#Preview("Floating thumbnail") {
    ThumbnailView(
        capture: PreviewFixtures.capture,
        previewImage: PreviewFixtures.sampleImage(),
        onEdit: {},
        onPin: {},
        onCopy: {},
        onDismiss: {}
    )
    .padding(40)
}
#endif
