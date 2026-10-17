import AppKit
import XCTest

@testable import ScreviaKit

final class EditArchiveTests: XCTestCase {
    private var root: URL!
    private var archive: EditArchive!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        archive = EditArchive(directory: root.appending(path: "Edits"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        archive = nil
        try super.tearDownWithError()
    }

    /// 200 × 100 pixels at 2×, like a capture on a Retina screen.
    private func original() -> NSImage {
        NSImage(cgImage: TestImages.gradientCGImage(width: 200, height: 100), size: NSSize(width: 100, height: 50))
    }

    private func document() -> AnnotationDocument {
        var style = AnnotationStyle.standard
        style.fontSize = 30
        return AnnotationDocument(
            annotations: [
                Annotation(tool: .arrow, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.6, y: 0.7)),
                Annotation(
                    tool: .freehand,
                    start: CGPoint(x: 0.1, y: 0.1),
                    end: CGPoint(x: 0.3, y: 0.3),
                    points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.3)]
                ),
                Annotation(tool: .text, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5), text: "注釈", style: style)
            ],
            crop: CGRect(x: 0.1, y: 0, width: 0.8, height: 1)
        )
    }

    /// Stands in for the flattened image the editor saves.
    private func writeSavedFile(named name: String = "Screenshot.png", width: Int = 200) throws -> URL {
        let url = root.appending(path: name)
        try ImageStore().write(TestImages.nsImage(width: width, height: 100), to: url, jpegQuality: 1)
        return url
    }

    func testAnEditComesBackAsItWasSaved() throws {
        let file = try writeSavedFile()
        let document = document()
        try archive.store(original: original(), document: document, for: file)

        let edit = try XCTUnwrap(archive.edit(for: file))
        let image = try XCTUnwrap(edit.original)
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(edit.document, document)
        XCTAssertEqual(image.size, NSSize(width: 100, height: 50), "Styles are in points, so the size must survive")
        XCTAssertEqual(pixels.width, 200, "The original must keep its pixels")
    }

    func testAnotherFileHasNoEdit() throws {
        let file = try writeSavedFile()
        let other = try writeSavedFile(named: "Other.png")
        try archive.store(original: original(), document: document(), for: file)

        XCTAssertNil(archive.edit(for: other))
    }

    /// Reopening the old annotations would discard what the other app did.
    func testAFileChangedElsewhereLosesItsEdit() throws {
        let file = try writeSavedFile()
        try archive.store(original: original(), document: document(), for: file)

        _ = try writeSavedFile(width: 300)

        XCTAssertNil(archive.edit(for: file))
    }

    func testStoringAgainReplacesTheEdit() throws {
        let file = try writeSavedFile()
        try archive.store(original: original(), document: document(), for: file)

        _ = try writeSavedFile(width: 300)
        try archive.store(original: original(), document: AnnotationDocument(), for: file)

        XCTAssertEqual(archive.edit(for: file)?.document, AnnotationDocument())
    }

    func testPruneDropsEditsWhoseFileIsGoneOrChanged() throws {
        let deleted = try writeSavedFile(named: "Deleted.png")
        let changed = try writeSavedFile(named: "Changed.png")
        let kept = try writeSavedFile(named: "Kept.png")
        for file in [deleted, changed, kept] {
            try archive.store(original: original(), document: document(), for: file)
        }
        try FileManager.default.removeItem(at: deleted)
        _ = try writeSavedFile(named: "Changed.png", width: 300)

        archive.prune()

        XCTAssertEqual(try entryCount(), 1)
        XCTAssertNotNil(archive.edit(for: kept))
    }

    func testPruneKeepsOnlyTheNewestUpToTheLimit() throws {
        let files = try (0..<3).map { try writeSavedFile(named: "Shot-\($0).png") }
        for file in files {
            try archive.store(original: original(), document: document(), for: file)
        }

        archive.limit = 2
        archive.prune()

        XCTAssertNil(archive.edit(for: files[0]), "The oldest edit goes first")
        XCTAssertNotNil(archive.edit(for: files[1]))
        XCTAssertNotNil(archive.edit(for: files[2]))
    }

    private func entryCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: archive.directory.path).count
    }

    /// Edits archived before balloons and image effects have neither key.
    /// They must still open, with no tails and no effects.
    func testAnEditFromBeforeEffectsStillDecodes() throws {
        let saved = document()
        let encoded = try JSONEncoder().encode(saved)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["effects"] = nil
        let older = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: older)

        XCTAssertEqual(decoded.annotations, saved.annotations)
        XCTAssertEqual(decoded.effects, ImageEffects())
        XCTAssertTrue(decoded.annotations.allSatisfy { $0.tail == nil })
    }

    func testEffectsAndTailsAreArchived() throws {
        var saved = document()
        saved.effects.borderColor = .green
        saved.effects.hasShadow = true
        saved.annotations.append(
            Annotation(tool: .balloon, start: .zero, end: CGPoint(x: 0.2, y: 0.1), text: "!", tail: CGPoint(x: 0.5, y: 0.5))
        )

        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(saved))

        XCTAssertEqual(decoded, saved)
    }

    /// The style is remembered in preferences and archived with each edit,
    /// both written before the later settings, from the magnifier's zoom
    /// and shape on, existed.
    func testAStyleFromBeforeMagnifierSettingsStillDecodes() throws {
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnnotationStyle.standard)) as? [String: Any]
        )
        for key in ["magnification", "magnifierShape", "arrowHead", "arrowBothEnds", "cornerRadius", "stepFormat"] {
            json[key] = nil
        }

        let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded, .standard)
    }
}
