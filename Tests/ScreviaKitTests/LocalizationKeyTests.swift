import Foundation
import XCTest

@testable import ScreviaKit

/// Some titles build their key from an enum case, as `"prefix.\(rawValue)"`.
/// A missing key still compiles and shows the raw key to the user, so check
/// every case against the String Catalog itself.
///
/// The catalog is read as JSON rather than through `L10n`: the SwiftPM CLI
/// copies it uncompiled, so lookups in tests would all fall back to the key.
@MainActor
final class LocalizationKeyTests: XCTestCase {
    private static let languages = ["en", "ja"]

    private func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/ScreviaKit/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    private func assertTranslated(
        _ keys: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let strings = try catalog()
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in Self.languages where localizations?[language] == nil {
                XCTFail("\(key) has no \(language) translation", file: file, line: line)
            }
        }
    }

    func testBackgroundStyles() throws {
        try assertTranslated(BackgroundStyle.allCases.map { "background.\($0.rawValue)" })
    }

    func testImageFormats() throws {
        try assertTranslated(ImageFormat.allCases.map { "format.\($0.rawValue)" })
    }

    func testThumbnailPositions() throws {
        try assertTranslated(ThumbnailPosition.allCases.map { "thumbnail.\($0.rawValue)" })
    }

    func testPreferencesTabs() throws {
        try assertTranslated(PreferencesTab.allCases.map { "preferences.\($0.rawValue)" })
    }

    func testAnnotationTools() throws {
        try assertTranslated(AnnotationTool.allCases.map { "annotation.\($0.rawValue)" })
        try assertTranslated(AnnotationTool.allCases.map { "annotation.\($0.rawValue).usage" })
    }

    func testTextLanguages() throws {
        try assertTranslated(TextLanguage.allCases.map { "textLanguage.\($0.rawValue)" })
    }

    func testTextAppearances() throws {
        try assertTranslated(TextAppearance.allCases.map { "style.text.\($0.rawValue)" })
    }

    func testPaletteColourNames() throws {
        try assertTranslated(AnnotationColor.palette.compactMap { AnnotationColor.paletteKeys[$0] }.map { "color.\($0)" })
        XCTAssertEqual(AnnotationColor.paletteKeys.count, AnnotationColor.palette.count)
    }

    func testColourFormats() throws {
        try assertTranslated(ColorCodeFormat.allCases.map { "colorFormat.\($0.rawValue)" })
    }

    func testArrowHeadsAndStepFormats() throws {
        try assertTranslated(ArrowHead.allCases.map { "style.arrowHead.\($0.rawValue)" })
        try assertTranslated(StepFormat.allCases.map { "style.stepFormat.\($0.rawValue)" })
        try assertTranslated(FontDesign.allCases.map { "style.fontDesign.\($0.rawValue)" })
    }

    func testMagnifierShapes() throws {
        try assertTranslated(MagnifierShape.allCases.map { "style.magnifierShape.\($0.rawValue)" })
    }
}
