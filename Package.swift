// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Screvia",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The Screvia.xcodeproj app target (see project.yml) depends on
        // this product directly; there is no SwiftPM executable target
        // anymore. Previews render off the same product's scheme.
        .library(name: "ScreviaKit", targets: ["ScreviaKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/cybozu/LicenseList", from: "2.5.0")
    ],
    targets: [
        .target(
            name: "ScreviaKit",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LicenseList", package: "LicenseList")
            ],
            path: "Sources/ScreviaKit",
            resources: [
                // .process rather than .copy so Xcode's build system compiles
                // Localizable.xcstrings into per-language .strings when this
                // target builds as an embedded local package; the SwiftPM CLI
                // build (swift build/test) just copies it as-is instead.
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ScreviaKitTests",
            dependencies: ["ScreviaKit"],
            path: "Tests/ScreviaKitTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
