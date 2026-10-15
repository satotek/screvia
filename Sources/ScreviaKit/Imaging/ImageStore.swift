import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ImageStore {
    /// The system clipboard, unless a test passes a private one. Held by
    /// name because NSPasteboard is not Sendable.
    var pasteboardName: NSPasteboard.Name = .general

    private var pasteboard: NSPasteboard {
        NSPasteboard(name: pasteboardName)
    }

    struct SavedImage {
        let fileURL: URL
        let data: Data?
        let format: ImageFormat
    }

    enum StoreError: LocalizedError {
        case desktopFolderUnavailable
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .desktopFolderUnavailable:
                return L10n.text("error.desktopFolderUnavailable")
            case .imageEncodingFailed:
                return L10n.text("error.imageEncodingFailed")
            }
        }
    }

    func save(
        _ image: NSImage,
        directory: URL,
        format: ImageFormat,
        jpegQuality: Double
    ) throws -> URL {
        try saveAndEncode(
            image,
            directory: directory,
            format: format,
            jpegQuality: jpegQuality,
            includeData: false
        ).fileURL
    }

    func saveAndEncode(
        _ image: NSImage,
        directory: URL,
        format: ImageFormat,
        jpegQuality: Double,
        includeData: Bool
    ) throws -> SavedImage {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let imageData = try encodedData(
            for: image,
            format: format,
            jpegQuality: jpegQuality
        ) else {
            Log.storage.error(
                "Failed to encode capture as \(format.rawValue, privacy: .public)"
            )
            throw StoreError.imageEncodingFailed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let baseName = "Screenshot-\(formatter.string(from: Date()))"
        var destination = directory.appendingPathComponent("\(baseName).\(format.fileExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName)-\(suffix).\(format.fileExtension)")
            suffix += 1
        }

        try imageData.write(to: destination, options: .atomic)
        // The path stays private: it contains the user's home directory.
        Log.storage.info(
            """
            Saved \(imageData.count, privacy: .public) bytes \
            as \(format.rawValue, privacy: .public) to \(destination.path)
            """
        )
        return SavedImage(
            fileURL: destination,
            data: includeData ? imageData : nil,
            format: format
        )
    }

    /// Writes to a path the user chose, in the format its extension names.
    /// Unlike `saveAndEncode`, this overwrites: the save panel has already
    /// asked.
    func write(_ image: NSImage, to url: URL, jpegQuality: Double) throws {
        let format = ImageFormat(fileExtension: url.pathExtension) ?? .png
        guard let data = try encodedData(for: image, format: format, jpegQuality: jpegQuality) else {
            Log.storage.error("Failed to encode an image as \(format.rawValue, privacy: .public)")
            throw StoreError.imageEncodingFailed
        }
        try data.write(to: url, options: .atomic)
        Log.storage.info("Saved \(data.count, privacy: .public) bytes to \(url.path)")
    }

    func copyToClipboard(_ image: NSImage) {
        // Encode PNG directly from the image's CGImage. The old path created
        // a TIFF representation and then decoded it again before encoding PNG.
        guard let pngData = try? encodedData(
            for: image,
            format: .png,
            jpegQuality: 1
        ) else {
            Log.storage.error("PNG encoding failed; falling back to TIFF on the pasteboard")
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            return
        }

        copyToClipboard(data: pngData, format: .png)
    }

    func copyToClipboard(data: Data, format: ImageFormat) {
        let pasteboard = pasteboard
        pasteboard.clearContents()
        pasteboard.setData(data, forType: format.pasteboardType)
    }

    func copyToClipboard(fileURL: URL) {
        guard let imageData = readImageData(at: fileURL) else {
            return
        }

        copyToClipboard(data: imageData.data, format: imageData.format)
    }

    func readImageData(at fileURL: URL) -> (data: Data, format: ImageFormat)? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let format = ImageFormat(fileExtension: fileURL.pathExtension)
        else {
            return nil
        }

        return (data, format)
    }

    /// `readImageData(at:)` off the caller's actor, for callers on the main
    /// actor that must not block on disk I/O.
    @concurrent
    func loadImageData(at fileURL: URL) async -> (data: Data, format: ImageFormat)? {
        readImageData(at: fileURL)
    }

    private func encodedData(
        for image: NSImage,
        format: ImageFormat,
        jpegQuality: Double
    ) throws -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.uniformTypeIdentifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: CFDictionary? = format == .jpeg
            ? [
                kCGImageDestinationLossyCompressionQuality:
                    max(0, min(1, jpegQuality))
            ] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

private nonisolated extension ImageFormat {
    var uniformTypeIdentifier: String {
        switch self {
        case .png:
            return UTType.png.identifier
        case .jpeg:
            return UTType.jpeg.identifier
        case .tiff:
            return UTType.tiff.identifier
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png":
            self = .png
        case "jpg", "jpeg":
            self = .jpeg
        case "tif", "tiff":
            self = .tiff
        default:
            return nil
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return NSPasteboard.PasteboardType(rawValue: "public.jpeg")
        case .tiff:
            return .tiff
        }
    }
}
