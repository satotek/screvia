#!/usr/bin/env swift
//
// Builds Screvia.app and wraps it in a drag-and-drop disk image.
//
//   swift scripts/CreateDMG.swift [--sign <identity>]
//
// --sign is passed through to BuildApp.swift, which signs the app; the image
// itself is left unsigned. Notarization is out of scope.

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
let projectYAMLPath = repoRoot.appending(path: "project.yml")

do {
    // Read the version from project.yml — the build setting Info.plist
    // expands — so the image name can never drift from the app.
    let projectYAML = try String(contentsOf: projectYAMLPath, encoding: .utf8)
    guard let versionLine = projectYAML
        .components(separatedBy: .newlines)
        .first(where: { $0.contains("MARKETING_VERSION:") }) else {
        throw CommandError(command: "find MARKETING_VERSION in project.yml", status: 1)
    }
    let version = versionLine
        .split(separator: ":", maxSplits: 1)[1]
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

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
    //
    // macOS 27 deprecates `hdiutil create` in favour of `diskutil image`,
    // which older systems lack, so probe for it rather than assume.
    // `diskutil image` will not overwrite, unlike hdiutil's -ov.
    try? fm.removeItem(at: dmgPath)
    if (try? run("/usr/sbin/diskutil", ["image", "create", "from", "--help"], captureOutput: true)) != nil {
        try run("/usr/sbin/diskutil", [
            "image", "create", "from",
            "--format", "UDZO",
            "--volumeName", appName,
            staging.path,
            dmgPath.path
        ])
    } else {
        try run("/usr/bin/hdiutil", [
            "create",
            "-volname", appName,
            "-srcfolder", staging.path,
            "-format", "UDZO",
            dmgPath.path
        ])
    }

    print("Created \(dmgPath.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
