import KeyboardShortcuts
import SwiftUI

struct CaptureHubView: View {
    let displays: [DisplayInfo]
    let history: [CaptureHistoryEntry]
    let onCaptureFullScreen: (UInt32?) -> Void
    let onCaptureArea: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureScroll: () -> Void
    let onCaptureText: () -> Void
    let onCaptureLastArea: () -> Void
    let onRecordScreen: () -> Void
    let captureDelay: Int
    let onCaptureDelayChange: (Int) -> Void
    let onEditHistory: (CaptureHistoryEntry) -> Void
    let onCopyHistory: (CaptureHistoryEntry) -> Void
    let onPinHistory: (CaptureHistoryEntry) -> Void
    let onRemoveHistory: (CaptureHistoryEntry) -> Void
    let onOpenImage: () -> Void
    let onEditClipboard: () -> Void
    let onOpenPreferences: () -> Void
    let onOpenAbout: () -> Void
    let onOpenLicenses: () -> Void
    /// The version a scheduled check found, until the user looks at it.
    let availableUpdate: String?
    let onCheckForUpdates: () -> Void
    let isScreenRecordingGranted: Bool
    let onOpenScreenRecordingSettings: () -> Void
    let onRevealFolder: () -> Void
    let onQuit: () -> Void

    @State private var selectedDisplayID: UInt32?
    /// The delay chosen while the hub is open. `captureDelay` is the value
    /// when it opened, and nothing redraws the hub when the setting
    /// changes, so the button would keep showing the old one.
    @State private var chosenDelay: Int?

    private var delay: Int { chosenDelay ?? captureDelay }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            captureModes
            tools
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

            if let availableUpdate {
                Button(action: onCheckForUpdates) {
                    Label(L10n.format("hub.updateAvailable", availableUpdate), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ScreviaTheme.accent)
            }

            Menu {
                Button(L10n.text("app.settings"), systemImage: "gearshape", action: onOpenPreferences)
                Button(L10n.text("app.checkForUpdates"), systemImage: "arrow.down.circle", action: onCheckForUpdates)

                Divider()

                Button(L10n.text("about.menuTitle"), systemImage: "info.circle", action: onOpenAbout)
                Button(L10n.text("licenses.title"), systemImage: "building.columns", action: onOpenLicenses)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
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

    /// Area first and always picked out, as the mode used most; the others
    /// stay quiet until hovered, so no tile looks chosen when none is.
    @ViewBuilder
    private var captureModes: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ],
            spacing: 6
        ) {
            CaptureModeTile(
                title: L10n.text("app.area"),
                shortcut: shortcutLabel(for: .captureArea),
                symbol: ShortcutAction.captureArea.symbol,
                accented: true,
                action: onCaptureArea
            )
            CaptureModeTile(
                title: L10n.text("app.fullScreen"),
                shortcut: shortcutLabel(for: .captureFullScreen),
                symbol: ShortcutAction.captureFullScreen.symbol,
                accented: false,
                action: { onCaptureFullScreen(selectedDisplayID) }
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
                accented: false,
                action: onCaptureScroll
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)

        RecordTile(
            title: L10n.text("hub.record"),
            shortcut: shortcutLabel(for: .recordScreen),
            action: onRecordScreen
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// The smaller capture modes, the self-timer and the editor for images
    /// Screvia did not capture, as one row of equal buttons. Their full
    /// names are in the tooltips.
    private var tools: some View {
        HStack(spacing: 2) {
            ToolButton(
                symbol: ShortcutAction.captureText.symbol,
                title: L10n.text("app.captureText"),
                action: onCaptureText
            )
            .help(shortcutHelp(L10n.text("preferences.captureText"), for: .captureText))
            ToolButton(
                symbol: ShortcutAction.captureLastArea.symbol,
                title: L10n.text("hub.lastArea"),
                action: onCaptureLastArea
            )
            .help(shortcutHelp(L10n.text("preferences.captureLastArea"), for: .captureLastArea))
            Menu {
                Picker(L10n.text("app.timer"), selection: Binding(get: { delay }, set: { chosenDelay = $0; onCaptureDelayChange($0) })) {
                    ForEach(ScreviaSettings.captureDelayChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? L10n.text("app.timerOff") : L10n.format("app.timerSeconds", seconds))
                            .tag(seconds)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                // The set delay in place of the name, so a timer left on
                // shows before the next capture waits for it.
                ToolLabel(
                    symbol: "timer",
                    title: delay == 0 ? L10n.text("app.timer") : L10n.format("app.timerSeconds", delay),
                    accented: delay != 0
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .help(L10n.text("app.timerHelp"))
            ToolButton(symbol: "photo", title: L10n.text("hub.openImage"), action: onOpenImage)
                .help(L10n.text("import.openImage"))
            ToolButton(symbol: "doc.on.clipboard", title: L10n.text("hub.clipboard"), action: onEditClipboard)
                .help(L10n.text("import.fromClipboard"))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func shortcutHelp(_ title: String, for action: ShortcutAction) -> String {
        let shortcut = shortcutLabel(for: action)
        return shortcut.isEmpty ? title : "\(title)  \(shortcut)"
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
                // A line rather than a box: until something is captured
                // there is nothing here worth the space.
                Text(L10n.text("app.noRecentCaptures"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
        .padding(.bottom, 12)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ScreviaTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 2) {
                FooterButton(symbol: "folder", title: L10n.text("app.folder"), action: onRevealFolder)
                // Only when something is wrong: once granted, the setting
                // has nothing more to offer from here.
                if !isScreenRecordingGranted {
                    FooterButton(
                        symbol: "exclamationmark.triangle.fill",
                        title: L10n.text("hub.allowScreenRecording"),
                        tint: .orange,
                        action: onOpenScreenRecordingSettings
                    )
                }
                Spacer()
                FooterButton(symbol: "power", title: L10n.text("app.quit"), action: onQuit)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}

/// A shortcut such as "⌃⇧4" split into its keys, one keycap each.
nonisolated enum ShortcutKeys {
    private static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "🌐"]

    static func split(_ shortcut: String) -> [String] {
        var keys: [String] = []
        var rest = Substring(shortcut)
        while let first = rest.first, modifiers.contains(first) {
            keys.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty {
            keys.append(String(rest))
        }
        return keys
    }
}

private struct Keycaps: View {
    let shortcut: String
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(ShortcutKeys.split(shortcut).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(ScreviaTheme.keycapFont)
                    .foregroundStyle(tint)
                    .frame(minWidth: 11)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(tint.opacity(0.45), lineWidth: 0.5)
                    }
            }
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

    private var background: Color {
        if accented {
            return ScreviaTheme.accent.opacity(isHovering ? 0.24 : 0.16)
        }
        return isHovering ? ScreviaTheme.surfaceHover : ScreviaTheme.surface
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(accented || isHovering ? ScreviaTheme.accent : Color.primary.opacity(0.75))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accented ? ScreviaTheme.accent : Color.primary)
                if !shortcut.isEmpty {
                    Keycaps(shortcut: shortcut, tint: accented ? ScreviaTheme.accent : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.format("app.capture", title))
    }
}

/// Recording, as one wide row under the capture modes: a different kind of
/// capture, so it does not take a place among the stills.
private struct RecordTile: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: ShortcutAction.recordScreen.symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.red.opacity(isHovering ? 1 : 0.85))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !shortcut.isEmpty {
                    Keycaps(shortcut: shortcut, tint: .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHovering ? ScreviaTheme.surfaceHover : ScreviaTheme.surface,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(L10n.text("hub.recordHelp"))
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
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint ?? (isHovering ? Color.primary : Color.secondary))
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

private struct ToolButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolLabel(symbol: symbol, title: title, accented: false)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// An icon over a short name, shared by the tool buttons and the timer's
/// menu so the five line up.
private struct ToolLabel: View {
    let symbol: String
    let title: String
    let accented: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            // A fixed height, as symbols differ in theirs and would
            // otherwise push their names out of line.
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(accented ? ScreviaTheme.accent : (isHovering ? Color.primary : Color.primary.opacity(0.75)))
                .frame(height: 18)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(accented ? ScreviaTheme.accent : (isHovering ? Color.primary : Color.secondary))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            isHovering ? ScreviaTheme.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        onCaptureText: {},
        onCaptureLastArea: {},
        onRecordScreen: {},
        captureDelay: 0,
        onCaptureDelayChange: { _ in },
        onEditHistory: { _ in },
        onCopyHistory: { _ in },
        onPinHistory: { _ in },
        onRemoveHistory: { _ in },
        onOpenImage: {},
        onEditClipboard: {},
        onOpenPreferences: {},
        onOpenAbout: {},
        onOpenLicenses: {},
        availableUpdate: nil,
        onCheckForUpdates: {},
        isScreenRecordingGranted: true,
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
        onCaptureText: {},
        onCaptureLastArea: {},
        onRecordScreen: {},
        captureDelay: 0,
        onCaptureDelayChange: { _ in },
        onEditHistory: { _ in },
        onCopyHistory: { _ in },
        onPinHistory: { _ in },
        onRemoveHistory: { _ in },
        onOpenImage: {},
        onEditClipboard: {},
        onOpenPreferences: {},
        onOpenAbout: {},
        onOpenLicenses: {},
        availableUpdate: nil,
        onCheckForUpdates: {},
        isScreenRecordingGranted: true,
        onOpenScreenRecordingSettings: {},
        onRevealFolder: {},
        onQuit: {}
    )
}
#endif
