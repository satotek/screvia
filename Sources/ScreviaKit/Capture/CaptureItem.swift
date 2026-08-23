import AppKit

struct CaptureItem {
    let image: NSImage
    let fileURL: URL
    let displayID: UInt32
    let kind: CaptureKind

    init(
        image: NSImage,
        fileURL: URL,
        displayID: UInt32,
        kind: CaptureKind = .standard
    ) {
        self.image = image
        self.fileURL = fileURL
        self.displayID = displayID
        self.kind = kind
    }
}
