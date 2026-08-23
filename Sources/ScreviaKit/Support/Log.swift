import Foundation
import OSLog

/// Unified logging entry points, one `Logger` per area of the app.
///
/// Categories exist so Console.app can be filtered down to the part that
/// misbehaved. Filter on `subsystem:dev.satotek.screvia` to see everything, or
/// add `category:capture` to narrow it.
///
/// Note on privacy: string interpolation into a `Logger` is redacted by default
/// and shows as `<private>` in Console. That default is right for us — capture
/// paths contain the user's home directory — so mark a value `.public` only
/// when it carries no personal information.
enum Log {
    private static let subsystem = "dev.satotek.screvia"

    /// Screen, area, window and scrolling capture.
    static let capture = Logger(subsystem: subsystem, category: "capture")

    /// Encoding, writing to disk and the clipboard.
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Global hotkeys.
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")

    /// Windows, popovers and the annotation editor.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Lifecycle, and every error that reaches the user as an alert.
    static let app = Logger(subsystem: subsystem, category: "app")
}
