# Changelog

Changes that users of Screvia will notice, newest first. The release
workflow publishes each version's section as its release notes, so a
version cannot be released until its section is written.

## [Unreleased]

### Fixed

- Pressing a capture shortcut again while choosing an area or window no
  longer leaves a second overlay on screen that could not be closed.
- The menu bar shows Screvia's own icon again, instead of a stand-in.
- Copying colours with Tab several times in a row no longer crashes the
  app.

### Changed

- A full-screen or area capture taken with its shortcut while the capture
  hub is open now includes the hub, so Screvia can capture itself.
- The capture hub is tidier: area capture comes first and stands out,
  shortcuts show as keys, the smaller tools sit in one even row with the
  timer's delay on its button, and the permissions button appears only
  while Screen Recording is not allowed.

## [0.5.0] - 2026-10-19

### Added

- A loupe beside the pointer while choosing an area: the pixels under it
  enlarged, with its position, the colour there and, while dragging, the
  selection's size. It can be turned off under Settings → Capture.
- A smart eraser in the editor, which covers what you drag over with the
  colour around it, and picks the colour again when moved or resized.
- Rounded corners for the whole image, and greyscale or inverted colours,
  in the editor's effects menu.
- Screvia updates itself. It asks once whether to check for updates
  automatically, and Settings → General can change that, download and
  install updates on their own, or check now. Updates installed this way
  need no trip to Privacy & Security.

## [0.4.0] - 2026-10-18

### Added

- Speech balloons with a tail you can point, and a round or square
  magnifier at 1.5–4× that ⌥-dragging aims at something else.
- Lines and arrows bend from a handle in the middle; arrowheads open or
  filled, at one end or both; rounded rectangles; steps numbered 1 2 3,
  A B C or I II III.
- Text in a standard, rounded, serif or monospaced design, and text boxes
  that wrap at a width you drag out.
- Paste or insert pictures and emoji stickers, and arrange annotations from
  front to back.
- The colour under the pointer, copied with Tab as HEX, CSS or Swift code,
  an eyedropper for a point or an area's average, and the size Save writes.
- Rotate, flip, resize and trim a plain border, with annotations following
  the picture; a margin, a border and a drop shadow around the whole image.
- Saved edits keep their annotations editable when reopened, from history
  or the file itself; the saved file stays an ordinary image.

### Changed

- The app shows in the Dock and ⌘-Tab while the editor is open, so an
  editor behind another window can be brought back.
- Settings is a window of fixed-size panes under a toolbar, laid out in
  labelled columns with pictures for the capture backgrounds. It floats
  rather than filling the screen under tiling window managers.

### Fixed

- A file replaced at the same path no longer keeps its old thumbnail in
  history.

## [0.3.0] - 2026-10-15

### Added

- Capture text: select an area and its text, Japanese included, is
  recognized on your Mac; copy all of it, edit it first, or pick out part
  of it with Live Text.
- Select and copy part of the text in a capture with Live Text, in the
  editor or on a pinned image.
- Capture the previous area again, and a self-timer of 3, 5 or 10 seconds.
- File names from a template of date, time, app and a counting number.
- Clipboard-only captures, opening the editor straight after capturing,
  including the pointer, hiding desktop icons, and saving Retina captures
  at 1×.

### Fixed

- The editor and pinned windows no longer resize themselves.

## [0.2.0] - 2026-10-15

### Added

- Select, move, resize and delete annotations with any tool; duplicate,
  delete all, Save As and crop.
- Line, freehand, and numbered steps that renumber when one is deleted.
- Colour, fill, line width and shadow, and for text its size, weight and a
  box, outlined or plain look, with the last style remembered.
- Open any image in the editor: from the clipboard, a file, a drop on the
  menu bar icon, or Finder's Open With.
- A guide to the Screen Recording setting at launch while the permission
  is missing.
- A new app icon.

### Fixed

- The capture hub no longer appears in captures started from it.
- The "none" capture background showed its untranslated key.

## [0.1.1] - 2026-10-15

### Fixed

- Runs on Intel Macs: 0.1.0 was built for Apple silicon only.
- The About window shows the right version, and builds have their own
  build numbers.

## [0.1.0] - 2026-10-15

### Added

- Full screen, region, window and scrolling capture across displays, with
  remappable global hotkeys.
- A Quick Access thumbnail, a history of the last 30 captures, and pinned
  screenshots that float above other windows.
- An editor with rectangles, ellipses, arrows, highlights, text, blur and
  pixelation, and undo.
- PNG, JPEG or TIFF output, PNG on the clipboard, and backgrounds with
  padding, rounded corners and a shadow.
- Launch at login.
- Releases signed with the same certificate every time, so updating keeps
  the Screen Recording and Accessibility permissions.

[Unreleased]: https://github.com/satotek/screvia/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/satotek/screvia/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/satotek/screvia/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/satotek/screvia/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/satotek/screvia/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/satotek/screvia/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/satotek/screvia/releases/tag/v0.1.0
