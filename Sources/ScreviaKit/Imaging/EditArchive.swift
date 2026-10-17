import AppKit
import CryptoKit

/// An edit as it was saved: what it takes to open the file again with its
/// annotations still editable rather than burnt in.
nonisolated struct ArchivedEdit {
    /// The image before annotating, as PNG.
    let originalPNG: Data
    /// The original's size in points. Annotation styles are measured in
    /// points, so the original must come back at the size it was edited at.
    let pointSize: CGSize
    let document: AnnotationDocument

    var original: NSImage? {
        guard
            let image = NSImage(data: originalPNG),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}

/// Keeps the original and the annotations of every image the editor saves,
/// keyed by the saved file.
///
/// The saved file stays an ordinary image that any app can open; the edit
/// lives beside it here. An edit applies only while the file is exactly as
/// Screvia wrote it: once another app changes it, reopening the old
/// annotations would throw that change away.
nonisolated struct EditArchive {
    let directory: URL
    /// How many edits to keep; the oldest go first. Each holds a full-size
    /// original, so this bounds the space the archive takes.
    var limit = 50

    static var standardDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "dev.satotek.screvia/Edits", directoryHint: .isDirectory)
    }

    private struct Record: Codable {
        let filePath: String
        let file: FileSignature
        let pointWidth: Double
        let pointHeight: Double
        let document: AnnotationDocument
        let archivedAt: Date
    }

    /// Enough to tell whether a file was replaced since it was archived.
    private struct FileSignature: Codable {
        let size: Int
        let modified: Date

        init?(of fileURL: URL) {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                let size = attributes[.size] as? Int,
                let modified = attributes[.modificationDate] as? Date
            else {
                return nil
            }
            self.size = size
            self.modified = modified
        }

        /// The date survives JSON only to about a microsecond.
        func matches(_ other: FileSignature) -> Bool {
            size == other.size && abs(modified.timeIntervalSince(other.modified)) < 0.001
        }
    }

    private enum Name {
        static let original = "original.png"
        static let record = "edit.json"
    }

    /// Records the edit that produced `fileURL`. Call it after the file is
    /// written, as the file's current size and date are what later reads
    /// check against.
    func store(original: NSImage, document: AnnotationDocument, for fileURL: URL) throws {
        guard let signature = FileSignature(of: fileURL) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let entry = entryDirectory(for: fileURL)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        try ImageStore().write(original, to: entry.appending(path: Name.original), jpegQuality: 1)

        let record = Record(
            filePath: fileURL.standardizedFileURL.path,
            file: signature,
            pointWidth: original.size.width,
            pointHeight: original.size.height,
            document: document,
            archivedAt: Date()
        )
        try JSONEncoder().encode(record).write(to: entry.appending(path: Name.record), options: .atomic)
    }

    /// `store` off the caller's actor: encoding a full-size original is slow.
    @concurrent
    func storeInBackground(original: NSImage, document: AnnotationDocument, for fileURL: URL) async throws {
        try store(original: original, document: document, for: fileURL)
    }

    /// The edit that produced `fileURL`, if the file has not changed since.
    func edit(for fileURL: URL) -> ArchivedEdit? {
        let entry = entryDirectory(for: fileURL)
        guard
            let record = record(in: entry),
            record.filePath == fileURL.standardizedFileURL.path,
            let signature = FileSignature(of: fileURL),
            signature.matches(record.file),
            let originalPNG = try? Data(contentsOf: entry.appending(path: Name.original))
        else {
            return nil
        }
        return ArchivedEdit(
            originalPNG: originalPNG,
            pointSize: CGSize(width: record.pointWidth, height: record.pointHeight),
            document: record.document
        )
    }

    /// `edit(for:)` off the caller's actor: the original is a full-size image.
    @concurrent
    func loadEdit(for fileURL: URL) async -> ArchivedEdit? {
        edit(for: fileURL)
    }

    /// Drops edits whose file is gone or was changed by another app, then
    /// the oldest beyond `limit`.
    func prune() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var kept: [(entry: URL, archivedAt: Date)] = []
        for entry in entries {
            guard
                let record = record(in: entry),
                let signature = FileSignature(of: URL(fileURLWithPath: record.filePath)),
                signature.matches(record.file)
            else {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            kept.append((entry, record.archivedAt))
        }

        for stale in kept.sorted(by: { $0.archivedAt > $1.archivedAt }).dropFirst(max(limit, 0)) {
            try? FileManager.default.removeItem(at: stale.entry)
        }
    }

    @concurrent
    func pruneInBackground() async {
        prune()
    }

    private func record(in entry: URL) -> Record? {
        guard let data = try? Data(contentsOf: entry.appending(path: Name.record)) else {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// A fixed-length name for any path, which may be longer than a file
    /// name can be or contain characters one cannot.
    private func entryDirectory(for fileURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(fileURL.standardizedFileURL.path.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name, directoryHint: .isDirectory)
    }
}
