import XCTest

@testable import ScreviaKit

@MainActor
final class ScreviaSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // A throwaway suite rather than .standard, so the tests can never
        // disturb the developer's own Screvia preferences.
        suiteName = "ScreviaSettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultsMatchTheDocumentedStartingConfiguration() {
        let settings = ScreviaSettings(defaults: defaults)

        XCTAssertEqual(settings.imageFormat, .png)
        XCTAssertEqual(settings.jpegQuality, 0.92)
        XCTAssertTrue(settings.copyToClipboard)
        XCTAssertTrue(settings.showThumbnail)
        XCTAssertFalse(settings.playSound)
        XCTAssertTrue(settings.includeWindowShadow)
        XCTAssertEqual(settings.thumbnailPosition, .bottomRight)
        XCTAssertEqual(settings.thumbnailDuration, 6)
        XCTAssertEqual(settings.backgroundStyle, .none)
        XCTAssertEqual(settings.padding, 0)
        XCTAssertEqual(settings.cornerRadius, 16)
        XCTAssertFalse(settings.shadowEnabled)
    }

    func testDefaultSaveDirectoryIsAScreviaFolder() {
        let settings = ScreviaSettings(defaults: defaults)

        XCTAssertEqual(settings.saveDirectoryURL.lastPathComponent, "Screvia")
    }

    // MARK: - Persistence

    func testEveryPropertyRoundTripsThroughUserDefaults() {
        let settings = ScreviaSettings(defaults: defaults)
        settings.saveDirectoryPath = "/tmp/screvia-test"
        settings.imageFormat = .jpeg
        settings.jpegQuality = 0.5
        settings.copyToClipboard = false
        settings.showThumbnail = false
        settings.playSound = true
        settings.includeWindowShadow = false
        settings.thumbnailPosition = .topLeft
        settings.thumbnailDuration = 11
        settings.backgroundStyle = .midnight
        settings.padding = 24
        settings.cornerRadius = 8
        settings.shadowEnabled = true

        // A second instance reads the same suite from scratch, which is what
        // a relaunch does.
        let reloaded = ScreviaSettings(defaults: defaults)

        XCTAssertEqual(reloaded.saveDirectoryPath, "/tmp/screvia-test")
        XCTAssertEqual(reloaded.imageFormat, .jpeg)
        XCTAssertEqual(reloaded.jpegQuality, 0.5)
        XCTAssertFalse(reloaded.copyToClipboard)
        XCTAssertFalse(reloaded.showThumbnail)
        XCTAssertTrue(reloaded.playSound)
        XCTAssertFalse(reloaded.includeWindowShadow)
        XCTAssertEqual(reloaded.thumbnailPosition, .topLeft)
        XCTAssertEqual(reloaded.thumbnailDuration, 11)
        XCTAssertEqual(reloaded.backgroundStyle, .midnight)
        XCTAssertEqual(reloaded.padding, 24)
        XCTAssertEqual(reloaded.cornerRadius, 8)
        XCTAssertTrue(reloaded.shadowEnabled)
    }

    /// A preferences file edited by hand, or written by a newer build, must
    /// not leave the app with an unusable format.
    func testUnknownStoredEnumValuesFallBackToTheDefault() {
        defaults.set("bmp", forKey: "imageFormat")
        defaults.set("centre", forKey: "thumbnailPosition")
        defaults.set("neon", forKey: "backgroundStyle")

        let settings = ScreviaSettings(defaults: defaults)

        XCTAssertEqual(settings.imageFormat, .png)
        XCTAssertEqual(settings.thumbnailPosition, .bottomRight)
        XCTAssertEqual(settings.backgroundStyle, .none)
    }

    // MARK: - styleOptions

    func testStyleOptionsMirrorTheStoredValues() {
        let settings = ScreviaSettings(defaults: defaults)
        settings.backgroundStyle = .mist
        settings.padding = 18
        settings.cornerRadius = 12
        settings.shadowEnabled = true

        let options = settings.styleOptions

        XCTAssertEqual(options.backgroundStyle, .mist)
        XCTAssertEqual(options.padding, 18)
        XCTAssertEqual(options.cornerRadius, 12)
        XCTAssertTrue(options.shadowEnabled)
    }

    /// Negative geometry would make ImageProcessor build an inverted rect, so
    /// styleOptions clamps rather than trusting the stored value.
    func testStyleOptionsClampNegativeGeometryToZero() {
        let settings = ScreviaSettings(defaults: defaults)
        settings.padding = -10
        settings.cornerRadius = -4

        let options = settings.styleOptions

        XCTAssertEqual(options.padding, 0)
        XCTAssertEqual(options.cornerRadius, 0)
    }

    // MARK: - reset

    func testResetRestoresEveryDefault() {
        let settings = ScreviaSettings(defaults: defaults)
        settings.imageFormat = .tiff
        settings.jpegQuality = 0.6
        settings.copyToClipboard = false
        settings.playSound = true
        settings.thumbnailPosition = .topRight
        settings.backgroundStyle = .sage
        settings.padding = 40
        settings.shadowEnabled = true

        settings.reset()

        XCTAssertEqual(settings.imageFormat, .png)
        XCTAssertEqual(settings.jpegQuality, 0.92)
        XCTAssertTrue(settings.copyToClipboard)
        XCTAssertFalse(settings.playSound)
        XCTAssertEqual(settings.thumbnailPosition, .bottomRight)
        XCTAssertEqual(settings.backgroundStyle, .none)
        XCTAssertEqual(settings.padding, 0)
        XCTAssertFalse(settings.shadowEnabled)
    }

    func testResetIsPersistedRatherThanOnlyInMemory() {
        let settings = ScreviaSettings(defaults: defaults)
        settings.imageFormat = .jpeg
        settings.padding = 40

        settings.reset()

        let reloaded = ScreviaSettings(defaults: defaults)
        XCTAssertEqual(reloaded.imageFormat, .png)
        XCTAssertEqual(reloaded.padding, 0)
    }

    // MARK: - ImageFormat

    func testImageFormatFileExtensions() {
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ImageFormat.tiff.fileExtension, "tiff")
    }
}
