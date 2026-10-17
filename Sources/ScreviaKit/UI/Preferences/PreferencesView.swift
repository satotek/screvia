import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case saving
    case capture
    case appearance
    case shortcuts

    var id: String { rawValue }

    var title: String {
        L10n.text("preferences.\(rawValue)")
    }

    /// A note under the whole pane.
    var footer: String? {
        self == .shortcuts ? L10n.text("preferences.shortcutsHint") : nil
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .saving:
            return "folder"
        case .capture:
            return "viewfinder"
        case .appearance:
            return "rectangle.on.rectangle"
        case .shortcuts:
            return "keyboard"
        }
    }
}

/// One pane of the Settings window. It is as tall as its contents, and the
/// window takes that size when the pane is chosen.
struct PreferencesPane: View {
    let tab: PreferencesTab
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        VStack(spacing: 16) {
            PreferencesGrid {
                switch tab {
                case .general:
                    GeneralPreferences(settings: settings)
                case .saving:
                    SavingPreferences(settings: settings)
                case .capture:
                    CapturePreferences(settings: settings)
                case .appearance:
                    AppearancePreferences(settings: settings)
                case .shortcuts:
                    ShortcutPreferences()
                }
            }

            // Below the grid rather than in it: a note wider than the rows
            // would widen the grid and push them off the window's middle.
            if let footer = tab.footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralPreferences: View {
    @ObservedObject var settings: ScreviaSettings
    @State private var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @State private var launchAtLoginError: String?

    var body: some View {
        PreferencesRow(L10n.text("preferences.startup")) {
            Toggle(
                L10n.text("preferences.launchAtLogin"),
                isOn: Binding(
                    get: { isLaunchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                )
            )

            if LaunchAtLoginManager.requiresApproval {
                PreferencesHint(L10n.text("preferences.launchAtLoginApprovalHint"))
                Button(L10n.text("preferences.openLoginItemsSettings")) {
                    LaunchAtLoginManager.openSystemSettings()
                }
            }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        PreferencesRow(L10n.text("preferences.afterCapture")) {
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
        }

        PreferencesSeparator()

        PreferencesRow(L10n.text("preferences.thumbnailPosition")) {
            ThumbnailPositionPicker(selection: $settings.thumbnailPosition)
        }
        .disabled(!settings.showThumbnail || settings.openEditorAfterCapture)

        PreferencesRow(L10n.text("preferences.autoClose")) {
            PreferencesSlider(value: $settings.thumbnailDuration, range: 1...12, step: 1) {
                L10n.format("preferences.seconds", Int($0))
            }
        }
        .disabled(!settings.showThumbnail || settings.openEditorAfterCapture)

        PreferencesRow(L10n.text("preferences.historyLimit")) {
            Picker(L10n.text("preferences.historyLimit"), selection: $settings.historyLimit) {
                ForEach(ScreviaSettings.historyLimitChoices, id: \.self) { limit in
                    Text(L10n.format("preferences.historyLimitCount", limit)).tag(limit)
                }
            }
            .labelsHidden()
            .fixedSize()
        }

        PreferencesSeparator()

        PreferencesRow(L10n.text("preferences.permissions")) {
            Button(L10n.text("preferences.openScreenRecordingSettings")) {
                openPrivacySettings("Privacy_ScreenCapture")
            }
            Button(L10n.text("preferences.openAccessibilitySettings")) {
                openPrivacySettings("Privacy_Accessibility")
            }
        }

        PreferencesSeparator()

        PreferencesRow {
            Button(L10n.text("preferences.reset")) {
                settings.reset()
            }
        }
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

    private func openPrivacySettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct SavingPreferences: View {
    @ObservedObject var settings: ScreviaSettings

    /// What the next capture from Safari would be called.
    private var fileNameExample: String {
        let template = FileNameTemplate(settings.fileNameTemplate)
        let name = template.render(date: Date(), app: "Safari", counter: settings.fileNameCounter + 1)
        return "\(name).\(settings.imageFormat.fileExtension)"
    }

    var body: some View {
        PreferencesRow(L10n.text("preferences.saveLocation")) {
            Toggle(L10n.text("preferences.saveToFile"), isOn: $settings.saveToFile)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: settings.saveDirectoryPath))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text((settings.saveDirectoryPath as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(settings.saveDirectoryPath)
                .frame(maxWidth: 230, alignment: .leading)

                Button(L10n.text("preferences.choose"), action: chooseFolder)
            }
            .disabled(!settings.saveToFile)

            PreferencesHint(L10n.text(settings.saveToFile ? "preferences.createFolderHint" : "preferences.unsavedHint"))
        }

        PreferencesSeparator()

        Group {
            PreferencesRow(L10n.text("preferences.fileName")) {
                TextField(L10n.text("preferences.fileNameTemplate"), text: $settings.fileNameTemplate)
                    .labelsHidden()
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 300)
                Text(L10n.format("preferences.fileNameExampleValue", fileNameExample))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                PreferencesHint(L10n.text("preferences.fileNameTokens"))
            }

            PreferencesRow(L10n.text("preferences.fileFormat")) {
                Picker(L10n.text("preferences.fileFormat"), selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if settings.imageFormat == .jpeg {
                PreferencesRow(L10n.text("preferences.jpegQuality")) {
                    PreferencesSlider(value: $settings.jpegQuality, range: 0.5...1, step: 0.01) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                }
            }

            PreferencesRow(L10n.text("preferences.retina")) {
                Toggle(L10n.text("preferences.downscaleRetina"), isOn: $settings.downscaleRetina)
                PreferencesHint(L10n.text("preferences.downscaleRetinaHint"))
            }
        }
        .disabled(!settings.saveToFile)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("preferences.choose")
        panel.directoryURL = URL(fileURLWithPath: settings.saveDirectoryPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}

struct CapturePreferences: View {
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        PreferencesRow(L10n.text("preferences.captureOptions")) {
            Toggle(L10n.text("preferences.includeCursor"), isOn: $settings.includeCursor)
            Toggle(L10n.text("preferences.hideDesktopIcons"), isOn: $settings.hideDesktopIcons)
        }

        PreferencesRow(L10n.text("preferences.windowCapture")) {
            Toggle(L10n.text("preferences.includeWindowShadow"), isOn: $settings.includeWindowShadow)
            PreferencesHint(L10n.text("preferences.windowShadowHint"))
        }

        PreferencesSeparator()

        PreferencesRow(L10n.text("preferences.textCapture")) {
            Picker(L10n.text("preferences.textLanguage"), selection: $settings.textLanguage) {
                ForEach(TextLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .fixedSize()
            Toggle(L10n.text("preferences.textJoinLines"), isOn: $settings.textJoinLines)
            PreferencesHint(L10n.text("preferences.textJoinLinesHint"))
        }
    }
}

struct AppearancePreferences: View {
    @ObservedObject var settings: ScreviaSettings

    var body: some View {
        PreferencesRow(L10n.text("preferences.background")) {
            BackgroundStylePicker(selection: $settings.backgroundStyle)
        }

        PreferencesRow(L10n.text("preferences.padding")) {
            PreferencesSlider(value: $settings.padding, range: 0...96, step: 4) {
                "\(Int($0)) pt"
            }
        }

        PreferencesRow(L10n.text("preferences.cornerRadius")) {
            PreferencesSlider(value: $settings.cornerRadius, range: 0...40, step: 2) {
                "\(Int($0)) pt"
            }
        }

        PreferencesRow(L10n.text("preferences.shadow")) {
            Toggle(L10n.text("preferences.addSoftShadow"), isOn: $settings.shadowEnabled)
        }

        PreferencesSeparator()

        PreferencesRow(L10n.text("preferences.preview")) {
            FramedPreview(settings: settings)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .alignmentGuide(.firstTextBaseline) { $0[.top] + 14 }
            PreferencesHint(L10n.text("preferences.styleHint"))
        }
    }
}

struct ShortcutPreferences: View {
    var body: some View {
        ForEach(ShortcutAction.allCases, id: \.shortcutName) { action in
            ShortcutRow(action: action)
        }

        PreferencesSeparator()
    }
}

struct ShortcutRow: View {
    let action: ShortcutAction

    @State private var shortcut: KeyboardShortcuts.Shortcut?

    private var isCustomized: Bool {
        shortcut != action.shortcutName.initialShortcut
    }

    var body: some View {
        PreferencesRow(action.title) {
            // The recorder owns persistence: clicking it captures the next
            // key combination and writes it straight to UserDefaults.
            KeyboardShortcuts.Recorder(for: action.shortcutName) { newValue in
                shortcut = newValue
            }
            // The recorder keeps its own width and would sit centred in a
            // wider frame, apart from its label.
            .fixedSize()
            // Beside the recorder but taking no room: the rows keep their
            // place as they are customised, and the hidden button does not
            // push the list off the window's middle.
            .overlay(alignment: .trailing) {
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
                .offset(x: 28)
            }
        }
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
    PreferencesPane(tab: .general, settings: .previewInstance())
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
