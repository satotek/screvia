#!/usr/bin/env swift
//
// Builds Screvia.app and wraps it in a drag-and-drop disk image.
//
//   swift scripts/CreateDMG.swift [--sign <identity>]
//
// Signing and notarization for distribution are deliberately separate steps;
// this only produces the image.

import Foundation

struct CommandError: LocalizedError {
    let command: String
    let status: Int32
    var errorDescription: String? { "\(command) exited with status \(status)" }
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String], captureOutput: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let pipe = Pipe()
    if captureOutput {
        process.standardOutput = pipe
    }

    try process.run()
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

let appName = "Screvia"
let fm = FileManager.default

var signingIdentity: String?
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
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

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let appDir = repoRoot.appending(path: ".build/\(appName).app")
let distDir = repoRoot.appending(path: "dist")
let plistPath = repoRoot.appending(path: "Sources/ScreviaKit/Resources/Info.plist")

do {
    // Read the version from the same Info.plist the app ships, so the image
    // name can never drift from what the app reports.
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: plistPath),
        format: nil
    ) as? [String: Any]
    guard let version = plist?["CFBundleShortVersionString"] as? String else {
        throw CommandError(command: "read CFBundleShortVersionString", status: 1)
    }

    // Reuse the canonical app build, but never launch the app while preparing
    // a distributable image.
    var buildArguments = ["scripts/BuildApp.swift", "--no-open"]
    if let signingIdentity {
        buildArguments += ["--sign", signingIdentity]
    }
    try run("/usr/bin/swift", buildArguments)

    let staging = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "screvia-dmg-\(UUID().uuidString)/\(appName)")
    defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)

    // ditto rather than FileManager: it preserves the extended attributes and
    // resource forks that a signed bundle depends on.
    try run("/usr/bin/ditto", [appDir.path, staging.appending(path: "\(appName).app").path])
    try fm.createSymbolicLink(
        at: staging.appending(path: "Applications"),
        withDestinationURL: URL(fileURLWithPath: "/Applications")
    )

    try fm.createDirectory(at: distDir, withIntermediateDirectories: true)
    let dmgPath = distDir.appending(path: "\(appName)-\(version).dmg")

    // UDZO is a compressed, read-only image, the usual shape for drag-and-drop
    // distribution.
    try run("/usr/bin/hdiutil", [
        "create",
        "-volname", appName,
        "-srcfolder", staging.path,
        "-ov",
        "-format", "UDZO",
        dmgPath.path
    ])

    print("Created \(dmgPath.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
