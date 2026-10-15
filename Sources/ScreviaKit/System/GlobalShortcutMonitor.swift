import AppKit
import KeyboardShortcuts

enum ShortcutAction: CaseIterable {
    case captureFullScreen
    case captureArea
    case captureWindow
    case captureScroll
    case captureText
    case captureLastArea

    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .captureFullScreen:
            return .captureFullScreen
        case .captureArea:
            return .captureArea
        case .captureWindow:
            return .captureWindow
        case .captureScroll:
            return .captureScroll
        case .captureText:
            return .captureText
        case .captureLastArea:
            return .captureLastArea
        }
    }

    /// Also used by the menu bar popover's tiles, so the two surfaces cannot
    /// drift apart.
    var symbol: String {
        switch self {
        case .captureFullScreen:
            return "rectangle.inset.filled"
        case .captureArea:
            return "crop"
        case .captureWindow:
            return "macwindow"
        case .captureScroll:
            return "arrow.down.to.line"
        case .captureText:
            return "text.viewfinder"
        case .captureLastArea:
            return "arrow.counterclockwise"
        }
    }

    var title: String {
        switch self {
        case .captureFullScreen:
            return L10n.text("preferences.captureFullScreen")
        case .captureArea:
            return L10n.text("preferences.captureArea")
        case .captureWindow:
            return L10n.text("preferences.captureWindow")
        case .captureScroll:
            return L10n.text("preferences.captureScroll")
        case .captureText:
            return L10n.text("preferences.captureText")
        case .captureLastArea:
            return L10n.text("preferences.captureLastArea")
        }
    }
}

// The initial shortcuts match what the app shipped with while these were
// hardcoded, so existing muscle memory keeps working. A user-set shortcut is
// stored in UserDefaults by KeyboardShortcuts and wins over the initial one.
extension KeyboardShortcuts.Name {
    static let captureFullScreen = Self(
        "captureFullScreen",
        initial: .init(.three, modifiers: [.control, .shift])
    )
    static let captureArea = Self(
        "captureArea",
        initial: .init(.four, modifiers: [.control, .shift])
    )
    static let captureWindow = Self(
        "captureWindow",
        initial: .init(.five, modifiers: [.control, .shift])
    )
    static let captureScroll = Self(
        "captureScroll",
        initial: .init(.six, modifiers: [.control, .shift])
    )
    static let captureText = Self(
        "captureText",
        initial: .init(.seven, modifiers: [.control, .shift])
    )
    static let captureLastArea = Self(
        "captureLastArea",
        initial: .init(.eight, modifiers: [.control, .shift])
    )
}

final class GlobalShortcutMonitor {
    func start(handler: @escaping (ShortcutAction) -> Void) {
        stop()

        for action in ShortcutAction.allCases {
            // onKeyUp rather than onKeyDown: a capture that starts on key-down
            // would photograph the modifier keys still being held.
            KeyboardShortcuts.onKeyUp(for: action.shortcutName) {
                Log.shortcuts.info(
                    "Hotkey fired: \(action.shortcutName.rawValue, privacy: .public)"
                )
                handler(action)
            }
        }
    }

    func stop() {
        Log.shortcuts.debug("Removing all hotkey handlers")
        KeyboardShortcuts.removeAllHandlers()
    }
}
