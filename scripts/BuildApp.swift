#!/usr/bin/env swift
//
// Assembles .build/Screvia.app from a release build.
//
//   swift scripts/BuildApp.swift [--no-open] [--sign <identity>]
//
// SwiftPM produces a bare executable, not an app bundle, so the gap has to be
// filled by hand. This is a script rather than a SwiftPM command plugin because
// the work — spawning codesign, copying read-only resource bundles, launching
// the result — sits awkwardly inside the plugin sandbox.

import Foundation

// MARK: - Shell helpers

struct CommandError: LocalizedError {
    let command: String
    let status: Int32
    var errorDescription: String? { "\(command) exited with status \(status)" }
}

@discardableResult
func run(
    _ launchPath: String,
    _ arguments: [String],
    environment: [String: String]? = nil,
    captureOutput: Bool = false
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    if let environment {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    let pipe = Pipe()
    if captureOutput {
        process.standardOutput = pipe
    }

    try process.run()
    // Read before waiting: a full pipe buffer would deadlock the child.
    let data = captureOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CommandError(
            command: ([launchPath] + arguments).joined(separator: " "),
            status: process.terminationStatus
        )
    }

    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

let fm = FileManager.default

func replaceDirectory(at url: URL) throws {
    if fm.fileExists(atPath: url.path) {
        try fm.removeItem(at: url)
    }
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
}

func copy(_ source: URL, to destination: URL) throws {
    if fm.fileExists(atPath: destination.path) {
        try fm.removeItem(at: destination)
    }
    try fm.copyItem(at: source, to: destination)
}

// MARK: - Arguments

var shouldOpen = true
var signingIdentity = "-"

var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--no-open":
        shouldOpen = false
    case "--sign":
        guard let identity = arguments.first else {
            FileHandle.standardError.write(Data("--sign needs an identity\n".utf8))
            exit(2)
        }
        arguments.removeFirst()
        signingIdentity = identity
    default:
        FileHandle.standardError.write(Data("unknown argument: \(argument)\n".utf8))
        exit(2)
    }
}

// MARK: - Layout

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let buildRoot = repoRoot.appending(path: ".build")
let resources = repoRoot.appending(path: "Sources/ScreviaKit/Resources")
// Bundle metadata the app needs but ScreviaKit never reads at runtime.
let appBundle = repoRoot.appending(path: "AppBundle")
let appDir = buildRoot.appending(path: "Screvia.app")

let swiftBin = "/usr/bin/swift"
// LicenseList's build plugin looks for Xcode's SourcePackages layout. The
// SwiftPM CLI uses .build instead, which has the same shape
// (workspace-state.json + checkouts/), so point the plugin at it.
let buildEnvironment = ["PLL_SOURCE_PACKAGES_PATH": buildRoot.path]

do {
    // `--show-bin-path` only prints the destination; it does not compile.
    // Build first so packaging can never reuse an older executable.
    try run(swiftBin, ["build", "-c", "release"], environment: buildEnvironment)
    let binDir = URL(fileURLWithPath: try run(
        swiftBin,
        ["build", "-c", "release", "--show-bin-path"],
        environment: buildEnvironment,
        captureOutput: true
    ))

    // Start clean: SwiftPM emits resource bundles read-only (mode 444), so a
    // second run could not overwrite what the first one left behind.
    try replaceDirectory(at: appDir)
    let contents = appDir.appending(path: "Contents")
    try fm.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: contents.appending(path: "Resources"), withIntermediateDirectories: true)

    try copy(binDir.appending(path: "Screvia"), to: contents.appending(path: "MacOS/Screvia"))
    try copy(appBundle.appending(path: "Info.plist"), to: contents.appending(path: "Info.plist"))
    try copy(
        resources.appending(path: "AppIcon.icns"),
        to: contents.appending(path: "Resources/AppIcon.icns")
    )

    for language in ["en.lproj", "ja.lproj"] {
        try copy(
            repoRoot.appending(path: "Sources/ScreviaKit/\(language)"),
            to: contents.appending(path: "Resources/\(language)")
        )
    }

    // Every SwiftPM resource bundle, ours and our dependencies'. These belong
    // in Contents/Resources: anything at the .app root is "unsealed content"
    // and makes codesign refuse to sign the bundle.
    let bundles = try fm.contentsOfDirectory(at: binDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "bundle" }
    guard !bundles.isEmpty else {
        throw CommandError(command: "locate resource bundles in \(binDir.path)", status: 1)
    }
    for bundle in bundles {
        try copy(bundle, to: contents.appending(path: "Resources/\(bundle.lastPathComponent)"))
    }

    // Our own assets also go straight into Contents/Resources so the app reads
    // them from the standard location rather than depending on Bundle.module,
    // whose generated accessor only ever looks beside the .app.
    try copy(
        resources.appending(path: "MenuBarIcon.pdf"),
        to: contents.appending(path: "Resources/MenuBarIcon.pdf")
    )

    // SMAppService requires a code-signed app. Ad-hoc ("-") is enough locally;
    // distributors pass a Developer ID with --sign.
    try run("/usr/bin/codesign", ["--force", "--deep", "--sign", signingIdentity, appDir.path])

    print("Built \(appDir.path)")

    if shouldOpen {
        try run("/usr/bin/open", [appDir.path])
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
