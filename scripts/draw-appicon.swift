#!/usr/bin/env swift
//
// Draws Screvia's app icon and writes every file the app needs from it.
//
//   swift scripts/draw-appicon.swift
//
// Writes Assets/AppIcon-master.png, Assets/AppIcon.iconset/, and
// App/AppIcon.icns. Each size is drawn from the vector shapes rather than
// scaled down from the master, so the small sizes stay sharp.
//
// The icon: capture brackets (taking the shot) around an arrow (marking it
// up), in the app's accent blue and signal coral. A number badge was tried
// instead of the arrow and dropped: on macOS a coloured circle with a digit
// on an app icon reads as an unread count.

import AppKit
import CoreGraphics

// Apple's macOS icon grid: the body is 824 of 1024 points, with the rest
// left transparent. Artwork that fills the canvas gets put in a grey
// container by macOS 26 and later.
let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// ScreviaTheme.accent and ScreviaTheme.signal.
let accent = rgb(0.26, 0.56, 0.98)
let coral = rgb(1.0, 0.43, 0.28)

func drawBody(_ c: CGContext) {
    let path = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // The grid allows for a drop shadow inside the transparent margin.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.3))
    c.addPath(path)
    c.setFillColor(rgb(0.86, 0.91, 0.99))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(path)
    c.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [rgb(0.98, 0.99, 1.0), rgb(0.86, 0.91, 0.99)] as CFArray,
        locations: [0, 1]
    )!
    c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // A faint rim keeps the light body distinct on a light Dock.
    c.addPath(path)
    c.setStrokeColor(rgb(0, 0, 0, 0.08))
    c.setLineWidth(4)
    c.strokePath()
    c.restoreGState()
}

func drawBrackets(_ c: CGContext) {
    let rect = CGRect(x: 236, y: 236, width: 552, height: 552)
    let arm: CGFloat = 150
    c.setStrokeColor(accent)
    c.setLineWidth(58)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    let (left, right, bottom, top) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
    for (a, corner, b) in [
        (CGPoint(x: left, y: top - arm), CGPoint(x: left, y: top), CGPoint(x: left + arm, y: top)),
        (CGPoint(x: right - arm, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: top - arm)),
        (CGPoint(x: right, y: bottom + arm), CGPoint(x: right, y: bottom), CGPoint(x: right - arm, y: bottom)),
        (CGPoint(x: left + arm, y: bottom), CGPoint(x: left, y: bottom), CGPoint(x: left, y: bottom + arm))
    ] {
        c.move(to: a)
        c.addLine(to: corner)
        c.addLine(to: b)
    }
    c.strokePath()
}

func drawArrow(_ c: CGContext) {
    let from = CGPoint(x: 380, y: 380)
    let to = CGPoint(x: 640, y: 640)
    let width: CGFloat = 70
    let head: CGFloat = 190
    let angle = atan2(to.y - from.y, to.x - from.x)

    // The shaft stops inside the head, so its round cap never shows past it.
    c.setStrokeColor(coral)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.move(to: from)
    c.addLine(to: CGPoint(x: to.x - cos(angle) * head * 0.8, y: to.y - sin(angle) * head * 0.8))
    c.strokePath()

    // Stroked as well as filled, to round the head's corners.
    c.setFillColor(coral)
    c.setLineWidth(width * 0.35)
    c.setLineJoin(.round)
    c.move(to: to)
    c.addLine(to: CGPoint(x: to.x - cos(angle - 0.5) * head, y: to.y - sin(angle - 0.5) * head))
    c.addLine(to: CGPoint(x: to.x - cos(angle + 0.5) * head, y: to.y - sin(angle + 0.5) * head))
    c.closePath()
    c.drawPath(using: .fillStroke)
}

func render(pixels: Int) -> CGImage {
    let c = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    c.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawBody(c)
    drawBrackets(c)
    drawArrow(c)
    return c.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = repoRoot.appending(path: "Assets")
let iconset = assets.appending(path: "AppIcon.iconset")
let icns = repoRoot.appending(path: "App/AppIcon.icns")

do {
    try writePNG(render(pixels: 1024), to: assets.appending(path: "AppIcon-master.png"))

    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try writePNG(render(pixels: points), to: iconset.appending(path: "icon_\(points)x\(points).png"))
        try writePNG(render(pixels: points * 2), to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    print("Wrote \(icns.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
