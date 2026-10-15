import XCTest

@testable import ScreviaKit

final class FileNameTemplateTests: XCTestCase {
    /// 2026-10-15 23:32:09 in the test machine's time zone.
    private let date: Date = {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 10, 15)
        (components.hour, components.minute, components.second) = (23, 32, 9)
        return Calendar.current.date(from: components)!
    }()

    /// The standard template reproduces the names Screvia always used, so
    /// nobody's folder changes naming after an update.
    func testTheStandardTemplateMatchesTheOldNames() {
        let name = FileNameTemplate(FileNameTemplate.standard).render(date: date, app: nil, counter: 0)

        XCTAssertEqual(name, "Screenshot-2026-10-15-23.32.09")
    }

    func testEveryTokenIsFilledIn() {
        let name = FileNameTemplate("{app} {date} {time} #{n}").render(date: date, app: "Safari", counter: 7)

        XCTAssertEqual(name, "Safari 2026-10-15 23.32.09 #7")
    }

    func testABlankTemplateFallsBackToTheStandardOne() {
        XCTAssertEqual(FileNameTemplate("   ").pattern, FileNameTemplate.standard)
    }

    /// A slash would make a folder, a colon shows as a slash in Finder, and
    /// a leading dot hides the file.
    func testCharactersThatBreakFileNamesAreReplaced() {
        let name = FileNameTemplate(".{app}").render(date: date, app: "A/B: C", counter: 0)

        XCTAssertEqual(name, "A-B- C")
    }

    func testOnlyTemplatesWithNUseTheCounter() {
        XCTAssertTrue(FileNameTemplate("x-{n}").usesCounter)
        XCTAssertFalse(FileNameTemplate("x-{date}").usesCounter)
    }
}
