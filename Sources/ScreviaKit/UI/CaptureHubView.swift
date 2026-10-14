import KeyboardShortcuts
import SwiftUI

struct CaptureHubView: View {
    let displays: [DisplayInfo]
    let history: [CaptureHistoryEntry]
    let onCaptureFullScreen: (UInt32?) -> Void
    let onCaptureArea: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureScroll: () -> Void
    let onEditHistory: (CaptureHistoryEntry) -> Void
    let onCopyHistory: (CaptureHistoryEntry) -> Void
    let onPinHistory: (CaptureHistoryEntry) -> Void
    let onRemoveHistory: (CaptureHistoryEntry) -> Void
    let onOpenPreferences: () -> Void
    let onOpenAbout: () -> Void
    let onOpenLicenses: () -> Void
    let onOpenScreenRecordingSettings: () -> Void
    let onRevealFolder: () -> Void
    let onQuit: () -> Void

    @State private var selectedDisplayID: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            captureModes
            displayPicker
            recentCaptureSection
            footer
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ScreviaTheme.accent)

            Text("Screvia")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Menu {
                Button(L10n.text("app.settings"), systemImage: "gearshape", action: onOpenPreferences)

                Divider()

                Button(L10n.text("about.menuTitle"), systemImage: "info.circle", action: onOpenAbout)
                Button(L10n.text("licenses.title"), systemImage: "building.columns", action: onOpenLicenses)
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .frame(width: 22)
            .help(L10n.text("app.menu"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var captureModes: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ],
            spacing: 6
        ) {
            CaptureModeTile(
                title: L10n.text("app.fullScreen"),
                shortcut: shortcutLabel(for: .captureFullScreen),
                symbol: ShortcutAction.captureFullScreen.symbol,
                accented: false,
                action: { onCaptureFullScreen(selectedDisplayID) }
            )
            CaptureModeTile(
                title: L10n.text("app.area"),
                shortcut: shortcutLabel(for: .captureArea),
                symbol: ShortcutAction.captureArea.symbol,
                accented: false,
                action: onCaptureArea
            )
            CaptureModeTile(
                title: L10n.text("app.window"),
                shortcut: shortcutLabel(for: .captureWindow),
                symbol: ShortcutAction.captureWindow.symbol,
                accented: false,
                action: onCaptureWindow
            )
            CaptureModeTile(
                title: L10n.text("app.scroll"),
                shortcut: shortcutLabel(for: .captureScroll),
                symbol: ShortcutAction.captureScroll.symbol,
                accented: true,
                action: onCaptureScroll
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    /// Reads the user's current binding so the popover never disagrees with the
    /// Preferences window. Empty when the shortcut has been cleared.
    private func shortcutLabel(for action: ShortcutAction) -> String {
        KeyboardShortcuts.getShortcut(for: action.shortcutName)?.description ?? ""
    }

    @ViewBuilder
    private var displayPicker: some View {
        if displays.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("app.display"))
                    .font(ScreviaTheme.sectionFont)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        DisplayChip(
                            title: L10n.text("app.pointer"),
                            isSelected: selectedDisplayID == nil,
                            action: { selectedDisplayID = nil }
                        )
                        ForEach(displays) { display in
                            DisplayChip(
                                title: display.isMain ? L10n.text("app.main") : display.name,
                                isSelected: selectedDisplayID == display.id,
                                action: { selectedDisplayID = display.id }
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var recentCaptureSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("app.recent"))
                    .font(ScreviaTheme.sectionFont)
                    .foregroundStyle(.secondary)

                Spacer()

                if !history.isEmpty {
                    Text(L10n.format("app.recentCount", history.count))
                        .font(ScreviaTheme.keycapFont)
                        .foregroundStyle(.tertiary)
                }
            }

            if history.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(ScreviaTheme.accent)
                    Text(L10n.text("app.noRecentCaptures"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(ScreviaTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(history.prefix(5))) { entry in
                            RecentCaptureCard(
                                entry: entry,
                                onEdit: { onEditHistory(entry) },
                                onCopy: { onCopyHistory(entry) },
                                onPin: { onPinHistory(entry) },
                                onRemove: { onRemoveHistory(entry) }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ScreviaTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 2) {
                FooterButton(symbol: "folder", title: L10n.text("app.folder"), action: onRevealFolder)
                FooterButton(symbol: "lock.shield", title: L10n.text("app.access"), action: onOpenScreenRecordingSettings)
                Spacer()
                FooterButton(symbol: "power", title: L10n.text("app.quit"), action: onQuit)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}

private struct CaptureModeTile: View {
    let title: String
    let shortcut: String
    let symbol: String
    let accented: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isHovering || accented ? ScreviaTheme.accent : Color.primary.opacity(0.75))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(shortcut)
                    .font(ScreviaTheme.keycapFont)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isHovering ? ScreviaTheme.surfaceHover : ScreviaTheme.surface,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if accented {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ScreviaTheme.accent.opacity(0.22), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.format("app.capture", title))
    }
}

private struct DisplayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? ScreviaTheme.accent : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? ScreviaTheme.accent.opacity(0.14)
                        : (isHovering ? ScreviaTheme.surfaceHover : ScreviaTheme.surface),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct RecentCaptureCard: View {
    let entry: CaptureHistoryEntry
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Button(action: onEdit) {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 112, height: 72)
                    .background(ScreviaTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isHovering ? ScreviaTheme.accent.opacity(0.6) : ScreviaTheme.hairline, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if entry.kind == .scrolling {
                            Label(L10n.text("app.scrollCapture"), systemImage: entry.kind.symbolName)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(ScreviaTheme.accent.opacity(0.92), in: Capsule())
                                .padding(5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onDrag {
                    NSItemProvider(object: entry.fileURL as NSURL)
                }

                Menu {
                    Button(L10n.text("app.edit"), action: onEdit)
                    Button(L10n.text("app.copy"), action: onCopy)
                    Button(L10n.text("app.pin"), action: onPin)
                    Divider()
                    Button(L10n.text("app.removeFromHistory"), role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 3)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                    .opacity(isHovering ? 1 : 0.72)
            }

            HStack(spacing: 4) {
                Text(entry.fileURL.lastPathComponent)
                    .font(.system(size: 9, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 112, alignment: .leading)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.text("app.edit"))
        .task(id: entry.filePath) {
            let data = await HistoryThumbnailLoader.loadPNGData(for: entry.fileURL)

            guard !Task.isCancelled else {
                return
            }
            thumbnail = data.flatMap(NSImage.init(data:))
        }
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    isHovering ? ScreviaTheme.surface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#if DEBUG
#Preview("Capture hub") {
    CaptureHubView(
        displays: PreviewFixtures.displays,
        history: PreviewFixtures.history,
        onCaptureFullScreen: { _ in },
        onCaptureArea: {},
        onCaptureWindow: {},
        onCaptureScroll: {},
        onEditHistory: { _ in },
        onCopyHistory: { _ in },
        onPinHistory: { _ in },
        onRemoveHistory: { _ in },
        onOpenPreferences: {},
        onOpenAbout: {},
        onOpenLicenses: {},
        onOpenScreenRecordingSettings: {},
        onRevealFolder: {},
        onQuit: {}
    )
}

#Preview("Capture hub / empty") {
    CaptureHubView(
        displays: [PreviewFixtures.displays[0]],
        history: [],
        onCaptureFullScreen: { _ in },
        onCaptureArea: {},
        onCaptureWindow: {},
        onCaptureScroll: {},
        onEditHistory: { _ in },
        onCopyHistory: { _ in },
        onPinHistory: { _ in },
        onRemoveHistory: { _ in },
        onOpenPreferences: {},
        onOpenAbout: {},
        onOpenLicenses: {},
        onOpenScreenRecordingSettings: {},
        onRevealFolder: {},
        onQuit: {}
    )
}
#endif
