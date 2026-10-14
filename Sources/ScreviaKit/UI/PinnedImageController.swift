import AppKit
import SwiftUI

final class PinnedImageController {
    private var panels: [NSPanel] = []

    func pin(_ image: NSImage, displayID: UInt32) {
        let imageSize = image.size
        let maxWidth: CGFloat = 520
        let maxHeight: CGFloat = 900
        let scale = min(
            1,
            maxWidth / max(imageSize.width, 1),
            maxHeight / max(imageSize.height, 1)
        )
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let view = PinnedImageView(
            image: ImagePreview.downsample(image, maxPixelDimension: 2_048),
            onClose: { [weak self, weak panel] in
                panel?.orderOut(nil)
                if let panel {
                    self?.panels.removeAll { $0 === panel }
                }
            }
        )
        panel.contentView = NSHostingView(rootView: view)

        if let screen = ScreenUtilities.screen(for: displayID) ?? NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 34,
                y: frame.maxY - size.height - 34
            ))
        }

        panels.append(panel)
        panel.orderFrontRegardless()
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .background(.black.opacity(0.04))
    }
}

#if DEBUG
#Preview("Pinned image") {
    PinnedImageView(image: PreviewFixtures.sampleImage(), onClose: {})
        .frame(width: 480, height: 300)
}
#endif
