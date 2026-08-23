// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Screvia",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Screvia", targets: ["Screvia"]),
        // Exists so Xcode generates a "ScreviaKit" scheme. Previews must
        // run under a scheme that does not build the executable, which
        // would otherwise demand ENABLE_DEBUG_DYLIB. Static by default, so
        // the app still links it exactly as before.
        .library(name: "ScreviaKit", targets: ["ScreviaKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
        .package(url: "https://github.com/cybozu/LicenseList", from: "2.5.0")
    ],
    targets: [
        // Everything but `@main` lives here. Xcode can only render SwiftUI
        // previews for targets it builds as a dynamic library, which an
        // executable target is not — hence the split.
        .target(
            name: "ScreviaKit",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LicenseList", package: "LicenseList")
            ],
            path: "Sources/ScreviaKit",
            resources: [
                .copy("Resources"),
                .copy("en.lproj"),
                .copy("ja.lproj")
            ]
        ),
        .executableTarget(
            name: "Screvia",
            dependencies: ["ScreviaKit"],
            path: "Sources/Screvia"
        )
    ],
    swiftLanguageModes: [.v5]
)
