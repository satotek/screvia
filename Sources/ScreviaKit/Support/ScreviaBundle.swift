import Foundation

/// Locates the SwiftPM resource bundle without going through `Bundle.module`.
///
/// The generated `Bundle.module` accessor looks in exactly one place —
/// `Bundle.main.bundleURL/Screvia_ScreviaKit.bundle` — and calls `fatalError`
/// when it is not there. Screvia.app keeps the bundle in `Contents/Resources`,
/// because anything sitting beside `Contents` is unsealed content that codesign
/// refuses to sign. On this machine the accessor's hard-coded `.build` fallback
/// hides the mismatch; on any other machine it would crash on first use.
nonisolated enum ScreviaBundle {
    /// SwiftPM names resource bundles `{package}_{target}.bundle`.
    private static let bundleName = "Screvia_ScreviaKit.bundle"

    private final class Token {}

    static let resources: Bundle = {
        let token = Bundle(for: Token.self)
        let searchRoots = [
            Bundle.main.resourceURL,        // Screvia.app/Contents/Resources
            Bundle.main.bundleURL,          // beside a command line executable
            token.resourceURL,
            token.bundleURL.deletingLastPathComponent()
        ]

        for root in searchRoots.compactMap({ $0 }) {
            let candidate = root.appending(path: bundleName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        // Better a main bundle that resolves nothing than a crash: callers fall
        // back to their key or skip the asset.
        Log.app.error("Resource bundle \(bundleName, privacy: .public) not found")
        return .main
    }()
}
