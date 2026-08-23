import AppKit
import LicenseList
import SwiftUI

// MARK: - Windows

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // A panel, not a document window: fixed size, no title text, sized to
        // its content the way the standard macOS About box is.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class LicensesWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("about.openSource")
        window.minSize = NSSize(width: 420, height: 320)
        window.contentView = NSHostingView(rootView: LicensesView())
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - App metadata

enum AppInfo {
    /// Read from the bundle rather than hardcoded, so this can never disagree
    /// with Info.plist. Nil under `swift run`, where there is no app bundle.
    static var versionDescription: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        let build = info?["CFBundleVersion"] as? String ?? "—"
        return L10n.format("about.versionFormat", short, build)
    }

    /// `NSHumanReadableCopyright` is the standard key the system About panel
    /// reads too, so there is no second place to keep this in sync.
    static var copyright: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }

    static let repositoryURL = URL(string: "https://github.com/satotek/screvia")!
}

// MARK: - About

private enum AppIconAsset {
    static func load() -> NSImage? {
        let paths = [
            Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
            Bundle.main.resourceURL?
                .appendingPathComponent("AppIcon.icns")
                .path(percentEncoded: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns")
                .path(percentEncoded: false),
            Bundle.main.bundleURL
                .appendingPathComponent("Screvia_ScreviaKit.bundle/Resources/AppIcon.icns")
                .path(percentEncoded: false),
            Bundle.main.bundleURL
                .appendingPathComponent(
                    "Contents/Resources/Screvia_ScreviaKit.bundle/Resources/AppIcon.icns"
                )
                .path(percentEncoded: false),
            Bundle.module.path(forResource: "AppIcon", ofType: "icns"),
            Bundle.module.path(forResource: "AppIcon", ofType: "icns", inDirectory: "Resources")
        ].compactMap { $0 }

        for path in paths {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        // Keep AppKit as a last-resort source for development previews or
        // hosts that provide the application icon without our asset bundle.
        return NSApplication.shared.applicationIconImage
    }
}

private struct AboutAppIcon: View {
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(ScreviaTheme.accent)
                    .background(
                        ScreviaTheme.surface,
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .onAppear {
            image = AppIconAsset.load()
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            AboutAppIcon()

            Text("Screvia")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 14)

            if let version = AppInfo.versionDescription {
                Text(version)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            Link(
                AppInfo.repositoryURL.absoluteString,
                destination: AppInfo.repositoryURL
            )
            .font(.system(size: 11))
            .padding(.top, 16)

            if let copyright = AppInfo.copyright {
                Text(copyright)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Licenses

/// The list comes from LicenseList's `PrepareLicenseList` build plugin, which
/// reads SwiftPM's resolved checkouts and pulls each package's LICENSE file —
/// nothing here needs updating when a dependency is added. Only the data is
/// borrowed; the presentation stays ours so it matches the rest of the app.
private struct LicensesView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Library.libraries) { library in
                    LicenseRow(library: library)
                }
            } footer: {
                Text(L10n.text("about.frameworksNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LicenseRow: View {
    let library: Library

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(library.licenseBody)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)

                    if let host = library.url?.host() {
                        Text(host)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let licenseLabel = library.licenseLabel {
                    Text(licenseLabel)
                        .font(ScreviaTheme.utilityFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            ScreviaTheme.surface,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }

                if let url = library.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(url.absoluteString)
                }
            }
        }
    }
}

private extension Library {
    /// A short badge for the license, sniffed from the text's opening lines.
    ///
    /// Returns nil rather than guessing when the text is not recognised — an
    /// unlabelled row is honest, a mislabelled one is not.
    var licenseLabel: String? {
        let head = licenseBody.prefix(300).lowercased()

        if head.contains("mit license") {
            return "MIT"
        }
        if head.contains("apache license") {
            return "Apache 2.0"
        }
        if head.contains("mozilla public license") {
            return "MPL 2.0"
        }
        if head.contains("gnu general public license") {
            return "GPL"
        }
        if head.contains("redistribution and use in source and binary forms") {
            return "BSD"
        }
        return nil
    }
}

#if DEBUG
#Preview("About") {
    AboutView()
}

#Preview("Licenses") {
    LicensesView()
        .frame(width: 520, height: 460)
}
#endif
