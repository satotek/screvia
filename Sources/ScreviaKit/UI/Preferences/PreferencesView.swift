import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case capture
    case appearance

    var id: String { rawValue }

    var title: String {
        L10n.text("preferences.\(rawValue)")
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .capture:
            return "viewfinder"
        case .appearance:
            return "rectangle.on.rectangle"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var settings: ScreviaSettings
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                content
            }

            Divider()
            HStack {
                Button(L10n.text("preferences.reset")) {
                    settings.reset()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()
                Text(L10n.text("preferences.autoSaved"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SCREVIA")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ForEach(PreferencesTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab ? ScreviaTheme.accent.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 168)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:
            GeneralPreferences(settings: settings)
        case .capture:
            CapturePreferences(settings: settings)
        case .appearance:
            AppearancePreferences(settings: settings)
        }
    }
}

struct GeneralPreferences: View {
    @ObservedObject var settings: ScreviaSettings
    @State private var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @State private var launchAtLoginError: String?

    /// What the next capture from Safari would be called.
    private var fileNameExample: String {
        let template = FileNameTemplate(settings.fileNameTemplate)
        let name = template.render(date: Date(), app: "Safari", counter: settings.fileNameCounter + 1)
        return "\(name).\(settings.imageFormat.fileExtension)"
    }

    var body: some View {
        Form {
            Section {
                Toggle(L10n.text("preferences.saveToFile"), isOn: $settings.saveToFile)

                VStack(alignment: .leading, spacing: 9) {
                    Text(L10n.text("preferences.saveLocation"))
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(ScreviaTheme.accent)
                        Text(settings.saveDirectoryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(L10n.text("preferences.choose"), action: chooseFolder)
                    }
                }
                .disabled(!settings.saveToFile)
            } header: {
                Text(L10n.text("preferences.whereCapturesGo"))
            } footer: {
                Text(L10n.text(settings.saveToFile ? "preferences.createFolderHint" : "preferences.unsavedHint"))
            }

            Section {
                TextField(L10n.text("preferences.fileNameTemplate"), text: $settings.fileNameTemplate)
                    .font(.system(size: 12, design: .monospaced))
                LabeledContent(L10n.text("preferences.fileNameExample")) {
                    Text(fileNameExample)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text(L10n.text("preferences.fileName"))
            } footer: {
                Text(L10n.text("preferences.fileNameTokens"))
            }
            .disabled(!settings.saveToFile)

            Section(L10n.text("preferences.fileFormat")) {
                Picker(L10n.text("preferences.defaultFormat"), selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                if settings.imageFormat == .jpeg {
                    HStack {
                        Text(L10n.text("preferences.jpegQuality"))
                        Slider(value: $settings.jpegQuality, in: 0.5...1, step: 0.01)
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            Section(L10n.text("preferences.afterCapture")) {
                // Without a saved file the clipboard is where captures land,
                // so it is shown on and cannot be turned off.
                Toggle(
                    L10n.text("preferences.copyToClipboard"),
                    isOn: settings.saveToFile ? $settings.copyToClipboard : .constant(true)
                )
                .disabled(!settings.saveToFile)
                Toggle(L10n.text("preferences.openEditorAfterCapture"), isOn: $settings.openEditorAfterCapture)
                Toggle(L10n.text("preferences.showThumbnail"), isOn: $settings.showThumbnail)
                    .disabled(settings.openEditorAfterCapture)
                Toggle(L10n.text("preferences.playSound"), isOn: $settings.playSound)
                Picker(L10n.text("preferences.historyLimit"), selection: $settings.historyLimit) {
                    ForEach(ScreviaSettings.historyLimitChoices, id: \.self) { limit in
                        Text(L10n.format("preferences.historyLimitCount", limit)).tag(limit)
                    }
                }
            }

            Section(L10n.text("preferences.startup")) {
                Toggle(
                    L10n.text("preferences.launchAtLogin"),
                    isOn: Binding(
                        get: { isLaunchAtLoginEnabled },
                        set: { setLaunchAtLogin($0) }
                    )
                )

                Text(L10n.text("preferences.launchAtLoginHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if LaunchAtLoginManager.requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(ScreviaTheme.accent)
                        Text(L10n.text("preferences.launchAtLoginApprovalHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button(L10n.text("preferences.openLoginItemsSettings")) {
                            LaunchAtLoginManager.openSystemSettings()
                        }
                    }
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section(L10n.text("preferences.permissions")) {
                Button(L10n.text("preferences.openScreenRecordingSettings")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
                Button(L10n.text("preferences.openAccessibilitySettings")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshLaunchAtLoginStatus()
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        if case .enabled = launchAtLoginStatus {
            return true
        }
        return false
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil

        do {
            try LaunchAtLoginManager.setEnabled(enabled)
        } catch {
            launchAtLoginError = L10n.format(
                "preferences.launchAtLoginError",
                error.localizedDescription
            )
        }

        refreshLaunchAtLoginStatus()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginManager.status
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("preferences.choose")
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}

struct CapturePreferences: View {
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        Form {
            Section(L10n.text("preferences.captureOptions")) {
                Toggle(L10n.text("preferences.includeCursor"), isOn: $settings.includeCursor)
                Toggle(L10n.text("preferences.hideDesktopIcons"), isOn: $settings.hideDesktopIcons)
                Toggle(L10n.text("preferences.downscaleRetina"), isOn: $settings.downscaleRetina)
                Text(L10n.text("preferences.downscaleRetinaHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("preferences.textCapture")) {
                Picker(L10n.text("preferences.textLanguage"), selection: $settings.textLanguage) {
                    ForEach(TextLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Toggle(L10n.text("preferences.textJoinLines"), isOn: $settings.textJoinLines)
                Text(L10n.text("preferences.textJoinLinesHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("preferences.windowCapture")) {
                Toggle(L10n.text("preferences.includeWindowShadow"), isOn: $settings.includeWindowShadow)
                Text(L10n.text("preferences.windowShadowHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("preferences.quickAccess")) {
                Picker(L10n.text("preferences.thumbnailPosition"), selection: $settings.thumbnailPosition) {
                    ForEach(ThumbnailPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }

                HStack {
                    Text(L10n.text("preferences.autoClose"))
                    Slider(value: $settings.thumbnailDuration, in: 1...12, step: 1)
                    Text("\(Int(settings.thumbnailDuration))s")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Section(L10n.text("preferences.shortcuts")) {
                ForEach(ShortcutAction.allCases, id: \.shortcutName) { action in
                    ShortcutRow(action: action)
                }

                Text(L10n.text("preferences.shortcutsHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppearancePreferences: View {
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        Form {
            Section {
                Picker(L10n.text("preferences.background"), selection: $settings.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                HStack {
                    Text(L10n.text("preferences.padding"))
                    Slider(value: $settings.padding, in: 0...96, step: 4)
                    Text("\(Int(settings.padding)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                }

                HStack {
                    Text(L10n.text("preferences.cornerRadius"))
                    Slider(value: $settings.cornerRadius, in: 0...40, step: 2)
                    Text("\(Int(settings.cornerRadius)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                }

                Toggle(L10n.text("preferences.addSoftShadow"), isOn: $settings.shadowEnabled)
            } header: {
                Text(L10n.text("preferences.screenshotFrame"))
            } footer: {
                Text(L10n.text("preferences.styleHint"))
            }

            Section(L10n.text("preferences.preview")) {
                FramedPreview(settings: settings)
                    .frame(height: 156)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShortcutRow: View {
    let action: ShortcutAction

    @State private var shortcut: KeyboardShortcuts.Shortcut?

    private var isCustomized: Bool {
        shortcut != action.shortcutName.initialShortcut
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ScreviaTheme.accent)
                .frame(width: 26, height: 26)
                .background(
                    ScreviaTheme.surface,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text(action.title)

            Spacer(minLength: 12)

            // Kept in the layout even when hidden so the recorders stay aligned
            // in a column rather than shifting as rows are customized.
            Button {
                KeyboardShortcuts.reset(action.shortcutName)
                shortcut = action.shortcutName.initialShortcut
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(L10n.text("preferences.shortcutRevert"))
            .opacity(isCustomized ? 1 : 0)
            .disabled(!isCustomized)

            // The recorder owns persistence: clicking it captures the next key
            // combination and writes it straight to UserDefaults.
            KeyboardShortcuts.Recorder(for: action.shortcutName) { newValue in
                shortcut = newValue
            }
            .frame(width: 130)
        }
        .padding(.vertical, 3)
        .onAppear {
            shortcut = KeyboardShortcuts.getShortcut(for: action.shortcutName)
        }
    }
}

struct FramedPreview: View {
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: CGFloat(settings.cornerRadius), style: .continuous)
                    .fill(settings.backgroundStyle.previewColor)
                    .frame(width: 226, height: 100)
                    .overlay {
                        RoundedRectangle(cornerRadius: CGFloat(settings.cornerRadius), style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(
                        color: .black.opacity(settings.shadowEnabled ? 0.24 : 0),
                        radius: settings.shadowEnabled ? 14 : 0,
                        y: settings.shadowEnabled ? 8 : 0
                    )
                    .overlay {
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(settings.backgroundStyle == .midnight ? 0.82 : 0.72))
                                .frame(width: 94, height: 7)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(settings.backgroundStyle == .midnight ? 0.30 : 0.42))
                                .frame(width: 148, height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.white.opacity(settings.backgroundStyle == .midnight ? 0.22 : 0.32))
                                .frame(width: 124, height: 5)
                        }
                    }
            }
            .padding(CGFloat(settings.padding).clamped(to: 0...28))
        }
    }
}

extension BackgroundStyle {
    var previewColor: Color {
        switch self {
        case .none:
            return Color.clear
        case .paper:
            return Color(red: 0.97, green: 0.97, blue: 0.97)
        case .mist:
            return Color(red: 0.88, green: 0.91, blue: 0.96)
        case .midnight:
            return Color(red: 0.075, green: 0.09, blue: 0.13)
        case .sage:
            return Color(red: 0.79, green: 0.88, blue: 0.83)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#if DEBUG
#Preview("Preferences") {
    PreferencesView(settings: .previewInstance())
        .frame(width: 720, height: 540)
}

#Preview("Appearance / framed") {
    let settings = ScreviaSettings.previewInstance()
    settings.backgroundStyle = .mist
    settings.padding = 20
    settings.cornerRadius = 18
    settings.shadowEnabled = true
    return FramedPreview(settings: settings)
        .frame(width: 380, height: 200)
        .padding()
}
#endif
