import AppKit
import SwiftUI

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

enum AppIconAsset {
    @MainActor
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
            ScreviaBundle.resources.path(forResource: "AppIcon", ofType: "icns"),
            ScreviaBundle.resources.path(
                forResource: "AppIcon",
                ofType: "icns",
                inDirectory: "Resources"
            )
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

struct AboutAppIcon: View {
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

struct AboutView: View {
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

#if DEBUG
#Preview("About") {
    AboutView()
}
#endif
