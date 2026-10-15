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
- Capture text: select an area and a window shows its text, Japanese
  included, recognized on your Mac by Vision; copy all of it, edit it first,
  or pick out part of the image with Live Text
- Select just part of the text in a capture with Live Text, in the editor
  or on a pinned image, and copy it
- Capture the previous area again, and a self-timer of 3, 5 or 10 seconds
  for menus and hover states
- Global hotkeys for every capture mode, remappable in Preferences

**After the shot**

- Quick Access thumbnail with a configurable corner and dismiss delay
- Session history of the last 30 captures, ready to re-edit, copy or pin
- Pin a screenshot on top of everything else while you work

**Annotate**

- Rectangle, ellipse, line, arrow, freehand, highlight, text and numbered
  steps that renumber themselves
- Colour, fill, line width and shadow; text in a box, outlined or plain, at
  any size, with the last style remembered
- Select, move, resize, duplicate and delete annotations; double-click text to
  change it
- Blur and pixelate for redaction, and crop, all drawn by the same renderer as
  the saved image, so what you see is what gets saved
- Open any image, not only captures: from the clipboard, a file, a drop on the
  menu bar icon, or Finder's Open With
- Undo/redo with `⌘Z` / `⇧⌘Z`, and Save As

**Output**

- PNG, JPEG or TIFF into any folder, with adjustable JPEG quality
- PNG on the clipboard rather than the uncompressed TIFF AppKit would
  otherwise hand over
- Background, padding, corner radius and shadow styling

## Install

Download the `.dmg` from [Releases](https://github.com/satotek/screvia/releases)
and drag Screvia to Applications.

Screvia is signed but not notarized, so macOS blocks the first launch. Open it
once, then allow it under System Settings → Privacy & Security → **Open
Anyway**. Or, from Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Screvia.app
```

Every release is signed with the same certificate, so updating keeps the
Screen Recording and Accessibility permissions you already granted.

## Requirements

- macOS 14 or later, on Apple silicon or Intel
- Xcode 27+ and Swift 6 to build
- [XcodeGen][xcodegen] (`brew install xcodegen`) to generate `Screvia.xcodeproj`
- Screen Recording permission; Accessibility permission is additionally
  required for scrolling capture

## Build

`Screvia.xcodeproj` is generated from `project.yml` and gitignored, so the
first step on a fresh clone is always to generate it:

```sh
xcodegen generate
open Screvia.xcodeproj    # then run the Screvia scheme
```

Or from the command line:

```sh
swift scripts/BuildApp.swift    # generate, build, and open .build/Screvia.app
swift scripts/CreateDMG.swift   # build, then wrap it in dist/Screvia-<version>.dmg
```

See [docs/build-and-packaging.md](docs/build-and-packaging.md) for signing,
previews, CI and troubleshooting.

## Documentation

- [Architecture](docs/architecture.md) — how the app is structured and why
- [Build and packaging](docs/build-and-packaging.md) — the hybrid
  XcodeGen/SwiftPM setup, scripts, CI
- [Testing](docs/testing.md) — what is covered, what deliberately is not, and
  the conventions for adding more
- [Roadmap](docs/roadmap.md) — where Screvia is headed and in what order,
  with the editor's own plan in [editor-roadmap.md](docs/editor-roadmap.md)

Contributors should also read [AGENTS.md](AGENTS.md) for the working
conventions.

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
