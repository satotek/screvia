import Foundation

enum L10n {
    private static let bundle: Bundle = {
        // The packaged app keeps its localizations in Contents/Resources. When
        // running through `swift run`, SwiftPM's generated resource bundle is
        // the correct fallback.
        let mainBundle = Bundle.main
        if mainBundle.path(forResource: "en", ofType: "lproj") != nil
            || mainBundle.path(forResource: "ja", ofType: "lproj") != nil {
            return mainBundle
        }
        return .module
    }()

    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: bundle,
            value: key,
            comment: ""
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
