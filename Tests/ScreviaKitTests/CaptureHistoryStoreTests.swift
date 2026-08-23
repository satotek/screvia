import XCTest

@testable import ScreviaKit

@MainActor
final class CaptureHistoryStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CaptureHistoryStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeStore(fileManager: FileManager = .default) -> CaptureHistoryStore {
        CaptureHistoryStore(defaults: defaults, fileManager: fileManager)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/screvia-tests/\(name)")
    }

    // MARK: - record

    func testANewStoreStartsEmpty() {
        XCTAssertTrue(makeStore().entries.isEmpty)
    }

    func testRecordedEntriesAreNewestFirst() {
        let store = makeStore()

        store.record(fileURL: url("first.png"), displayID: 1)
        store.record(fileURL: url("second.png"), displayID: 1)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].fileURL.lastPathComponent, "second.png")
        XCTAssertEqual(store.entries[1].fileURL.lastPathComponent, "first.png")
    }

    func testRecordPreservesTheDisplayAndKind() {
        let store = makeStore()

        store.record(fileURL: url("tall.png"), displayID: 7, kind: .scrolling)

        let entry = store.entries[0]
        XCTAssertEqual(entry.displayID, 7)
        XCTAssertEqual(entry.kind, .scrolling)
    }

    /// Re-saving the same path — re-editing a capture, for instance — should
    /// move that entry to the top rather than showing it twice.
    func testRecordingTheSamePathMovesItToTheFrontWithoutDuplicating() {
        let store = makeStore()

        store.record(fileURL: url("a.png"), displayID: 1)
        store.record(fileURL: url("b.png"), displayID: 1)
        store.record(fileURL: url("a.png"), displayID: 1)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].fileURL.lastPathComponent, "a.png")
        XCTAssertEqual(store.entries[1].fileURL.lastPathComponent, "b.png")
    }

    func testDeduplicationComparesStandardizedPaths() {
        let store = makeStore()

        store.record(fileURL: URL(fileURLWithPath: "/tmp/screvia-tests/x.png"), displayID: 1)
        store.record(fileURL: URL(fileURLWithPath: "/tmp/screvia-tests/./x.png"), displayID: 1)

        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - Capacity

    func testHistoryIsCappedAtTheMaximumKeepingTheNewest() {
        let store = makeStore()
        let overflow = CaptureHistoryStore.maximumEntries + 5

        for index in 0..<overflow {
            store.record(fileURL: url("shot-\(index).png"), displayID: 1)
        }

        XCTAssertEqual(store.entries.count, CaptureHistoryStore.maximumEntries)
        XCTAssertEqual(store.entries.first?.fileURL.lastPathComponent, "shot-\(overflow - 1).png")
        // The five oldest fell off the end.
        XCTAssertFalse(store.entries.contains { $0.fileURL.lastPathComponent == "shot-0.png" })
    }

    // MARK: - remove

    func testRemoveDropsOnlyTheGivenEntry() {
        let store = makeStore()
        store.record(fileURL: url("keep.png"), displayID: 1)
        store.record(fileURL: url("drop.png"), displayID: 1)

        let target = try! XCTUnwrap(store.entries.first { $0.fileURL.lastPathComponent == "drop.png" })
        store.remove(target)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].fileURL.lastPathComponent, "keep.png")
    }

    func testRemovingAnUnknownEntryIsANoOp() {
        let store = makeStore()
        store.record(fileURL: url("keep.png"), displayID: 1)

        store.remove(CaptureHistoryEntry(fileURL: url("never-recorded.png"), displayID: 1))

        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - Session scoping

    /// History is deliberately session-scoped: a relaunch starts with an
    /// empty strip even though the files themselves are still on disk.
    func testANewStoreDoesNotInheritEntriesFromAPreviousSession() {
        let first = makeStore()
        first.record(fileURL: url("from-last-session.png"), displayID: 1)

        XCTAssertTrue(makeStore().entries.isEmpty)
    }

    // MARK: - pruneMissingFiles

    func testPruneRemovesEntriesWhoseFileIsGone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let present = directory.appendingPathComponent("present.png")
        try Data("x".utf8).write(to: present)
        let missing = directory.appendingPathComponent("missing.png")

        let store = makeStore()
        store.record(fileURL: present, displayID: 1)
        store.record(fileURL: missing, displayID: 1)

        store.pruneMissingFiles()

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].fileURL.lastPathComponent, "present.png")
    }

    // MARK: - CaptureHistoryEntry decoding

    /// History written before capture kinds existed has no `kind` field, and
    /// must still decode rather than throwing.
    func testDecodingAnEntryWithoutAKindDefaultsToStandard() throws {
        let json = """
        {
            "id": "0783A1B0-1F84-4F5E-9A9B-2C2F0F5B6D11",
            "filePath": "/tmp/legacy.png",
            "displayID": 1,
            "capturedAt": 750000000
        }
        """

        let entry = try JSONDecoder().decode(
            CaptureHistoryEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.kind, .standard)
        XCTAssertEqual(entry.filePath, "/tmp/legacy.png")
    }

    func testEntryRoundTripsThroughCoding() throws {
        let original = CaptureHistoryEntry(
            fileURL: url("round-trip.png"),
            displayID: 3,
            kind: .scrolling
        )

        let decoded = try JSONDecoder().decode(
            CaptureHistoryEntry.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }
}
