import XCTest

@testable import ScreviaKit

final class ShortcutKeysTests: XCTestCase {
    func testEachModifierIsAKeyOfItsOwn() {
        XCTAssertEqual(ShortcutKeys.split("⌃⇧4"), ["⌃", "⇧", "4"])
        XCTAssertEqual(ShortcutKeys.split("⌘⌥⌃⇧A"), ["⌘", "⌥", "⌃", "⇧", "A"])
    }

    func testAKeyNamedInSeveralLettersStaysOneKey() {
        XCTAssertEqual(ShortcutKeys.split("⌃F12"), ["⌃", "F12"])
        XCTAssertEqual(ShortcutKeys.split("⇧Space"), ["⇧", "Space"])
    }

    func testNoShortcutHasNoKeys() {
        XCTAssertEqual(ShortcutKeys.split(""), [])
    }
}
