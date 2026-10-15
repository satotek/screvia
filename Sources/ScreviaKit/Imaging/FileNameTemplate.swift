import Foundation

/// A file name pattern with tokens:
///
/// - `{date}`: 2026-10-15
/// - `{time}`: 23.32.09, with dots because Finder shows a colon as a slash
/// - `{app}`: the app the capture came from
/// - `{n}`: a number that goes up with each capture that uses it
nonisolated struct FileNameTemplate {
    /// What Screvia named files before the template existed.
    static let standard = "Screenshot-{date}-{time}"

    let pattern: String

    init(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pattern = trimmed.isEmpty ? Self.standard : trimmed
    }

    var usesCounter: Bool {
        pattern.contains("{n}")
    }

    func render(date: Date, app: String?, counter: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HH.mm.ss"
        let time = formatter.string(from: date)

        let name = pattern
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{app}", with: app ?? "Screen")
            .replacingOccurrences(of: "{n}", with: String(counter))
        return Self.sanitized(name)
    }

    /// A slash would make a subfolder and a colon shows as a slash in
    /// Finder; a leading dot would hide the file.
    private static func sanitized(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? "Screenshot" : cleaned
    }
}
