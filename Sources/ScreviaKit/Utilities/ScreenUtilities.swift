import AppKit
import CoreGraphics

struct DisplayInfo: Identifiable {
    let id: UInt32
    let name: String
    let localizedName: String
    let frame: CGRect
    let isMain: Bool

    var displayID: CGDirectDisplayID { id }
}

enum ScreenUtilities {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screen in
            self.displayID(for: screen) == displayID
        }
    }

    static func screenAtMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    static func displayInfos() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let displayID = displayID(for: screen) else {
                return nil
            }

            return DisplayInfo(
                id: displayID,
                name: L10n.format("app.displayNumber", index + 1),
                localizedName: screen.localizedName,
                frame: screen.frame,
                isMain: screen == NSScreen.main
            )
        }
    }
}
