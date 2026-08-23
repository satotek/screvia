import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: ScreviaBundle.resources,
            value: key,
            comment: ""
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
