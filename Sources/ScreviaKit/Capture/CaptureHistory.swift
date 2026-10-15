import Foundation

enum CaptureKind: String, Codable, Equatable {
    case standard
    case scrolling

    var symbolName: String {
        switch self {
        case .standard:
            return "photo"
        case .scrolling:
            return "arrow.down.to.line"
        }
    }
}

struct CaptureHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let filePath: String
    let displayID: UInt32
    let capturedAt: Date
    let kind: CaptureKind

    private enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case displayID
        case capturedAt
        case kind
    }

    init(
        id: UUID = UUID(),
        fileURL: URL,
        displayID: UInt32,
        capturedAt: Date = Date(),
        kind: CaptureKind = .standard
    ) {
        self.id = id
        self.filePath = fileURL.standardizedFileURL.path
        self.displayID = displayID
        self.capturedAt = capturedAt
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filePath = try container.decode(String.self, forKey: .filePath)
        displayID = try container.decode(UInt32.self, forKey: .displayID)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        // History written before capture kinds were introduced remains valid.
        kind = try container.decodeIfPresent(CaptureKind.self, forKey: .kind) ?? .standard
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(kind, forKey: .kind)
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath, isDirectory: false)
    }

}

final class CaptureHistoryStore {
    private enum Key {
        static let entries = "captureHistory.entries"
    }

    static let defaultLimit = 30

    /// How many entries to keep; the oldest go first. Lowering it trims at
    /// the next capture rather than at once.
    var limit = CaptureHistoryStore.defaultLimit

    private let fileManager: FileManager

    private(set) var entries: [CaptureHistoryEntry] = []

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        // History is intentionally session-scoped. Captured files remain in
        // the configured save directory, but a new launch starts with an
        // empty, lightweight history strip.
        defaults.removeObject(forKey: Key.entries)
    }

    func record(
        fileURL: URL,
        displayID: UInt32,
        capturedAt: Date = Date(),
        kind: CaptureKind = .standard
    ) {
        let entry = CaptureHistoryEntry(
            fileURL: fileURL,
            displayID: displayID,
            capturedAt: capturedAt,
            kind: kind
        )

        entries.removeAll { $0.filePath == entry.filePath }
        entries.insert(entry, at: 0)
        if entries.count > max(limit, 1) {
            entries = Array(entries.prefix(max(limit, 1)))
        }
    }

    func remove(_ entry: CaptureHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func pruneMissingFiles() {
        let validEntries = entries.filter { fileManager.fileExists(atPath: $0.filePath) }
        guard validEntries.count != entries.count else {
            return
        }

        entries = validEntries
    }
}
