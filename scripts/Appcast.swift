#!/usr/bin/env swift
//
// Prints the Sparkle appcast for one release: the feed installed copies of
// Screvia read to find out whether a newer version exists.
//
//   swift scripts/Appcast.swift <version> <build> <dmg> <signature> <notes.md>
//
// <signature> is the disk image's EdDSA signature from `sign_update -p`, and
// <notes.md> the changes to show in the update window. The feed holds just
// this release: it is attached to the release and read through
// releases/latest/download, so the newest release's feed is the one found,
// and Sparkle needs no older items to update from any version.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 5 else {
    fail("usage: swift scripts/Appcast.swift <version> <build> <dmg> <signature> <notes.md>")
}
let (version, build, dmgPath, signature, notesPath) =
    (arguments[0], arguments[1], arguments[2], arguments[3], arguments[4])

guard Int(build) != nil else {
    fail("the build number must be an integer, not \(build)")
}
guard
    let size = (try? FileManager.default.attributesOfItem(atPath: dmgPath))?[.size] as? Int,
    let notes = try? String(contentsOfFile: notesPath, encoding: .utf8)
else {
    fail("cannot read \(dmgPath) or \(notesPath)")
}
// The notes go inside a CDATA section, which this would end early.
guard !notes.contains("]]>") else {
    fail("the release notes contain ]]>")
}

let repository = "https://github.com/satotek/screvia"
let dmgName = URL(fileURLWithPath: dmgPath).lastPathComponent

let dateFormatter = DateFormatter()
dateFormatter.locale = Locale(identifier: "en_US_POSIX")
dateFormatter.timeZone = TimeZone(identifier: "UTC")
dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

print("""
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Screvia</title>
    <link>\(repository)</link>
    <item>
      <title>Screvia \(escaped(version))</title>
      <pubDate>\(dateFormatter.string(from: Date()))</pubDate>
      <sparkle:version>\(build)</sparkle:version>
      <sparkle:shortVersionString>\(escaped(version))</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>\(repository)/releases/tag/v\(escaped(version))</link>
      <description sparkle:format="markdown"><![CDATA[
\(notes.trimmingCharacters(in: .whitespacesAndNewlines))
]]></description>
      <enclosure
        url="\(repository)/releases/download/v\(escaped(version))/\(escaped(dmgName))"
        length="\(size)"
        type="application/octet-stream"
        sparkle:edSignature="\(escaped(signature))"/>
    </item>
  </channel>
</rss>
""")
