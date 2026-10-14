import AppKit
import Combine
import Foundation

nonisolated enum ImageFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case tiff

    var id: String { rawValue }

    var displayName: String {
        L10n.text("format.\(rawValue)")
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .tiff:
            return "tiff"
        }
    }
}

nonisolated enum BackgroundStyle: String, CaseIterable, Identifiable {
    case none
    case paper
    case mist
    case midnight
    case sage

    var id: String { rawValue }

    var displayName: String {
        L10n.text("background.\(rawValue)")
    }

    var color: NSColor {
        switch self {
        case .none:
            return .clear
        case .paper:
            return NSColor(calibratedWhite: 0.97, alpha: 1)
        case .mist:
            return NSColor(srgbRed: 0.88, green: 0.91, blue: 0.96, alpha: 1)
        case .midnight:
            return NSColor(srgbRed: 0.075, green: 0.09, blue: 0.13, alpha: 1)
        case .sage:
            return NSColor(srgbRed: 0.79, green: 0.88, blue: 0.83, alpha: 1)
        }
    }
}

enum ThumbnailPosition: String, CaseIterable, Identifiable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

    var id: String { rawValue }

    var displayName: String {
        L10n.text("thumbnail.\(rawValue)")
    }
}

nonisolated struct CaptureStyleOptions {
    let backgroundStyle: BackgroundStyle
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadowEnabled: Bool
}

final class ScreviaSettings: ObservableObject {
    private enum Key {
        static let saveDirectoryPath = "saveDirectoryPath"
        static let imageFormat = "imageFormat"
        static let jpegQuality = "jpegQuality"
        static let copyToClipboard = "copyToClipboard"
        static let showThumbnail = "showThumbnail"
        static let playSound = "playSound"
        static let includeWindowShadow = "includeWindowShadow"
        static let thumbnailPosition = "thumbnailPosition"
        static let thumbnailDuration = "thumbnailDuration"
        static let backgroundStyle = "backgroundStyle"
        static let padding = "padding"
        static let cornerRadius = "cornerRadius"
        static let shadowEnabled = "shadowEnabled"
    }

    private let defaults: UserDefaults

    @Published var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: Key.saveDirectoryPath) }
    }

    @Published var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: Key.imageFormat) }
    }

    @Published var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: Key.jpegQuality) }
    }

    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }

    @Published var showThumbnail: Bool {
        didSet { defaults.set(showThumbnail, forKey: Key.showThumbnail) }
    }

    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }

    @Published var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: Key.includeWindowShadow) }
    }

    @Published var thumbnailPosition: ThumbnailPosition {
        didSet { defaults.set(thumbnailPosition.rawValue, forKey: Key.thumbnailPosition) }
    }

    @Published var thumbnailDuration: Double {
        didSet { defaults.set(thumbnailDuration, forKey: Key.thumbnailDuration) }
    }

    @Published var backgroundStyle: BackgroundStyle {
        didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.backgroundStyle) }
    }

    @Published var padding: Double {
        didSet { defaults.set(padding, forKey: Key.padding) }
    }

    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
    }

    @Published var shadowEnabled: Bool {
        didSet { defaults.set(shadowEnabled, forKey: Key.shadowEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultDirectory = Self.defaultSaveDirectoryURL.path
        saveDirectoryPath = defaults.string(forKey: Key.saveDirectoryPath) ?? defaultDirectory
        imageFormat = ImageFormat(rawValue: defaults.string(forKey: Key.imageFormat) ?? "png") ?? .png
        jpegQuality = defaults.object(forKey: Key.jpegQuality) as? Double ?? 0.92
        copyToClipboard = defaults.object(forKey: Key.copyToClipboard) as? Bool ?? true
        showThumbnail = defaults.object(forKey: Key.showThumbnail) as? Bool ?? true
        playSound = defaults.object(forKey: Key.playSound) as? Bool ?? false
        includeWindowShadow = defaults.object(forKey: Key.includeWindowShadow) as? Bool ?? true
        thumbnailPosition = ThumbnailPosition(
            rawValue: defaults.string(forKey: Key.thumbnailPosition) ?? "bottomRight"
        ) ?? .bottomRight
        thumbnailDuration = defaults.object(forKey: Key.thumbnailDuration) as? Double ?? 6
        backgroundStyle = BackgroundStyle(
            rawValue: defaults.string(forKey: Key.backgroundStyle) ?? "none"
        ) ?? .none
        padding = defaults.object(forKey: Key.padding) as? Double ?? 0
        cornerRadius = defaults.object(forKey: Key.cornerRadius) as? Double ?? 16
        shadowEnabled = defaults.object(forKey: Key.shadowEnabled) as? Bool ?? false
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }

    var styleOptions: CaptureStyleOptions {
        CaptureStyleOptions(
            backgroundStyle: backgroundStyle,
            padding: CGFloat(max(0, padding)),
            cornerRadius: CGFloat(max(0, cornerRadius)),
            shadowEnabled: shadowEnabled
        )
    }

    func reset() {
        saveDirectoryPath = Self.defaultSaveDirectoryURL.path
        imageFormat = .png
        jpegQuality = 0.92
        copyToClipboard = true
        showThumbnail = true
        playSound = false
        includeWindowShadow = true
        thumbnailPosition = .bottomRight
        thumbnailDuration = 6
        backgroundStyle = .none
        padding = 0
        cornerRadius = 16
        shadowEnabled = false
    }

    private static var defaultSaveDirectoryURL: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return desktop.appendingPathComponent("Screvia", isDirectory: true)
    }
}
