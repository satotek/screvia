# Screvia

**A native macOS screenshot app that keeps every capture on your Mac.**

[![Issues](https://img.shields.io/github/issues/satotek/screvia)](https://github.com/satotek/screvia/issues)
[![Stars](https://img.shields.io/github/stars/satotek/screvia)](https://github.com/satotek/screvia/stargazers)
[![Top language](https://img.shields.io/github/languages/top/satotek/screvia)](https://github.com/satotek/screvia/)
[![License](https://img.shields.io/github/license/satotek/screvia)](https://github.com/satotek/screvia/blob/main/LICENSE)

`Swift` `SwiftUI` `AppKit` `ScreenCaptureKit` `macOS`

Screvia lives in the menu bar. Capture a screen, a region, a window or a whole
scrolling page, annotate it, pin it above your work, and save it — all through
Apple's own frameworks. Nothing is uploaded, and no network code ships in the
app at all.

## Features

**Capture**

- Full screen, region, and window capture across multiple displays
- Scrolling capture: pick a window, and Screvia scrolls it and stitches the
  frames together by comparing their overlap
- Global hotkeys for every capture mode, remappable in Preferences

**After the shot**

- Quick Access thumbnail with a configurable corner and dismiss delay
- Session history of the last 30 captures, ready to re-edit, copy or pin
- Pin a screenshot on top of everything else while you work

**Annotate**

- Rectangle, ellipse, arrow, highlight and text
- Blur and pixelate for redaction, rendered live on the canvas so what you see
  before saving is what gets saved
- Undo/redo with `⌘Z` / `⇧⌘Z`

**Output**

- PNG, JPEG or TIFF into any folder, with adjustable JPEG quality
- PNG on the clipboard rather than the uncompressed TIFF AppKit would
  otherwise hand over
- Background, padding, corner radius and shadow styling

## Requirements

- macOS 14 or later
- Xcode 27+ and Swift 6 to build
- [XcodeGen][xcodegen] (`brew install xcodegen`) to generate `Screvia.xcodeproj`
- Screen Recording permission; Accessibility permission is additionally
  required for scrolling capture

## Build

`Screvia.xcodeproj` is generated from `project.yml` and gitignored, so the
first step is always to generate it:

```sh
xcodegen generate
open Screvia.xcodeproj    # then run the Screvia scheme
```

Or from the command line:

```sh
swift scripts/BuildApp.swift              # generate, build, and open .build/Screvia.app
swift scripts/BuildApp.swift --no-open    # build it only
swift scripts/CreateDMG.swift             # build, then wrap it in dist/Screvia-<version>.dmg
```

Pass `--sign <identity>` to either script to use a Developer ID instead of the
ad-hoc signature applied by default.

The packaging scripts are Swift rather than shell, matching
`generate-icons.swift` and `regrid-appicon.swift` in the same directory.

Opening the project in Xcode requires trusting the `PrepareLicenseList` build
plugin once, on the first build.

`ScreviaKit` also builds standalone through the SwiftPM CLI (`swift build`,
`swift test`) for CI and for editing outside Xcode. That path sets
`PLL_SOURCE_PACKAGES_PATH="$PWD/.build"` so LicenseList's build plugin — which
expects Xcode's `SourcePackages` layout — finds SwiftPM's checkout directory
instead.

## Tests

```sh
export PLL_SOURCE_PACKAGES_PATH="$PWD/.build"
swift test
```

The suite covers the parts that are deterministic without a screen or a user:
settings persistence and defaults, capture history (ordering, deduplication,
the 30-entry cap, decoding older entries), the scrolling-capture stitcher
(frame storage, overlap detection, canvas geometry), image processing
geometry, saving and clipboard encoding, and thumbnail generation. Capture
itself needs Screen Recording permission and a real display, so it is
exercised by running the app rather than by the suite.

## Architecture

Everything except the app entry point lives in the `ScreviaKit` SwiftPM
library, embedded as a local package dependency of the `Screvia.xcodeproj` app
target. Xcode can only render SwiftUI previews for a target it builds as a
dynamic library, which the `.xcodeproj` app target is not — so the split is
what makes previews work. Select the `ScreviaKit` scheme in Xcode to use them.

`AppDelegate` holds two coordinators rather than one combined app model:
`CaptureCoordinator` runs the capture -> process -> save -> present pipeline
and owns capture history, and `WindowsCoordinator` owns the Preferences/About/
Licenses windows. `SystemSettingsService` and `ErrorPresenter` are stateless
and shared by both.

```
App/                @main, Info.plist (Screvia.xcodeproj's app target)
Sources/ScreviaKit/
  App/              AppDelegate — owns the menu bar item and the coordinators
  Capture/          CaptureCoordinator, ScreenCaptureKit services, selection overlays
  UI/               SwiftUI views, AppKit window controllers, WindowsCoordinator
  System/           Launch-at-login, global hotkeys, system settings deep links
  Support/          Settings, logging, localization, error presentation
project.yml         Source of truth for Screvia.xcodeproj (XcodeGen)
```

Views take plain values and closures rather than reaching for singletons, which
keeps them previewable; `PreviewFixtures.swift` supplies the sample data.

UI strings live in a single String Catalog,
`Sources/ScreviaKit/Resources/Localizable.xcstrings`, compiled by both
`xcodebuild` and the SwiftPM CLI into per-language `.strings`. Keeping it
inside `ScreviaKit` rather than the app target means previews — which load
`ScreviaKit` as a standalone dylib — see the same localized strings the app
does; `App/en.lproj` and `App/ja.lproj` hold only the localized
`NSScreenCaptureUsageDescription` for the system permission prompt, which
belongs to `App/Info.plist` and can't live in the package.

## Logging

Screvia logs through the unified logging system. Capture paths stay private;
error types, formats and hotkey names are public.

```sh
log stream --predicate 'subsystem == "dev.satotek.screvia"' --level info
```

## Dependencies

- [KeyboardShortcuts][keyboardshortcuts] — remappable global hotkeys, registered
  through Carbon so they do not collide with other apps
- [LicenseList][licenselist] — generates the open source license list from the
  resolved package checkouts, so it can never fall out of date

Everything else is built on Apple frameworks only.

## License

MIT — see [LICENSE](LICENSE).

[keyboardshortcuts]: https://github.com/sindresorhus/KeyboardShortcuts
[licenselist]: https://github.com/cybozu/LicenseList
[xcodegen]: https://github.com/yonaskolb/XcodeGen
