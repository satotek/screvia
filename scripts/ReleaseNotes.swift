#!/usr/bin/env swift
//
// Prints a version's release notes: its section of CHANGELOG.md, a link to
// the full diff, then the install notes every release carries.
//
//   swift scripts/ReleaseNotes.swift [--changes-only] <version>
//
// --changes-only leaves out the link and the install notes, for the update
// window of an app that is already installed.
//
// Fails when CHANGELOG.md has no section for the version, or an empty one,
// so a release cannot go out with notes nobody wrote.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let changesOnly = arguments.first == "--changes-only"
if changesOnly {
    arguments.removeFirst()
}
guard arguments.count == 1, let version = arguments.first else {
    fail("usage: swift scripts/ReleaseNotes.swift [--changes-only] <version>")
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard
    let changelog = try? String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8),
    let installNotes = try? String(contentsOf: root.appendingPathComponent(".github/release-notes.md"), encoding: .utf8)
else {
    fail("cannot read CHANGELOG.md or .github/release-notes.md")
}

let lines = changelog.components(separatedBy: "\n")

// A section runs from its "## [version]" heading to the next "## " heading.
guard let heading = lines.firstIndex(where: { $0.hasPrefix("## [\(version)]") }) else {
    fail("CHANGELOG.md has no section for \(version); rename [Unreleased] to [\(version)] - <date>")
}
let end = lines[(heading + 1)...].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
var body = Array(lines[(heading + 1)..<end])

// The link definitions at the bottom of the file follow the last section.
while let last = body.last, last.isEmpty || last.hasPrefix("[") {
    body.removeLast()
}
let notes = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
guard !notes.isEmpty else {
    fail("the \(version) section of CHANGELOG.md is empty")
}

// The same comparison the heading links to, which GitHub does not resolve
// inside a release body.
let link = lines.first { $0.hasPrefix("[\(version)]: ") }.map { String($0.dropFirst("[\(version)]: ".count)) }

var output = notes + "\n"
if !changesOnly {
    if let link {
        output += "\n**Full Changelog**: \(link)\n"
    }
    output += "\n" + installNotes.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
}

/// Joins lines wrapped in the source into one: a release body, unlike a
/// Markdown file, turns every line break into a visible one.
func unwrapped(_ text: String) -> String {
    var result: [String] = []
    var inCode = false
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            inCode.toggle()
            result.append(line)
            continue
        }
        let startsBlock = trimmed.isEmpty || inCode || trimmed.hasPrefix("#") || trimmed.hasPrefix("- ")
            || trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        if !startsBlock, let previous = result.last,
           !previous.isEmpty, !previous.hasPrefix("#"), !previous.hasPrefix("```") {
            result[result.count - 1] = previous + " " + trimmed
        } else {
            result.append(line)
        }
    }
    return result.joined(separator: "\n")
}

print(unwrapped(output), terminator: "")
