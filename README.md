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
- Xcode 26.5+ and Swift 6 to build
- Screen Recording permission; Accessibility permission is additionally
  required for scrolling capture

## Build

```sh
export PLL_SOURCE_PACKAGES_PATH="$PWD/.build"
swift build

swift scripts/BuildApp.swift              # assemble .build/Screvia.app and launch it
swift scripts/BuildApp.swift --no-open    # assemble it only
swift scripts/CreateDMG.swift             # build, then wrap it in dist/Screvia-<version>.dmg
```

Pass `--sign <identity>` to either script to use a Developer ID instead of the
ad-hoc signature applied by default.

`PLL_SOURCE_PACKAGES_PATH` points [LicenseList][licenselist]'s build plugin at
SwiftPM's checkout directory. The plugin looks for Xcode's `SourcePackages`
layout, which the command line puts under `.build` instead. Xcode resolves this
on its own, and the scripts set the variable themselves.

The packaging scripts are Swift rather than shell, matching
`generate-icons.swift` and `regrid-appicon.swift` in the same directory.

Opening the package in Xcode requires trusting the `PrepareLicenseList` build
plugin once, on the first build.

## Architecture

Everything except `@main` lives in the `ScreviaKit` library target, with the
executable target holding a single file. Xcode can only render SwiftUI previews
for targets it builds as a dynamic library, which an executable target is not —
so the split is what makes the previews work. Select the `ScreviaKit` scheme to
use them.

```
Sources/
  Screvia/        @main only
  ScreviaKit/
    App/          AppDelegate, ScreviaModel — the app's side effects
    Capture/      ScreenCaptureKit services and the selection overlays
    UI/           SwiftUI views and the AppKit window controllers
    Utilities/    Settings, image encoding, hotkeys, logging
```

Views take plain values and closures rather than reaching for singletons, which
keeps them previewable; `PreviewFixtures.swift` supplies the sample data.

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
