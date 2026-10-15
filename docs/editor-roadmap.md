# Editor roadmap

Where the annotation editor is headed. The yardstick is ShareX's image
editor: what it offers, which parts Screvia adopts, and in what order.

## Foundation first

Two things in the current editor make every new tool cost double, so they
come before any feature.

- **One renderer.** The canvas draws with SwiftUI's `Canvas`
  (`AnnotationCanvas`), while copy and save draw again with `NSBezierPath`
  (`AnnotationEditorView.flattenedImage`). Each tool is written twice, and the
  two can disagree. Both should call one function that draws into a
  `CGContext`, and export should render at the image's pixel size.
- **Annotations that can be edited.** An `Annotation` is a tool and two
  points, fixed once drawn: no colour, no line width, no way to select it
  again. It needs a style, a shape that fits each tool (freehand is a list of
  points, a step is one point and a number), hit testing, and handles.

## Phases

**Phase 0 — foundation.** One renderer; per-annotation style; select, move,
resize and delete.

**Phase 1.**

- Tools: line, freehand, step (①②③, numbered automatically)
- Text with an outline or a background
- Stroke colour, fill colour, line width, shadow on or off, remembered
  between sessions
- Duplicate, delete, delete all
- Crop
- Save As

**Phase 2.**

- Tools: speech balloon, magnifier, curved arrow, inserted images, emoji
  stickers, smart eraser
- Corner radius, arrowhead styles, step formats (letters, Roman numerals)
- Stacking order, paste from the clipboard
- Auto crop, rotate and flip, resize, canvas size
- Image effects, starting with border and shadow

**Not planned.** Cursor drawing (the capture settings cover it), cut out,
upload, print.

## Crop is different

Every other tool adds a shape on top of the image; crop changes the image.
Annotation coordinates are fractions of the image (0–1), so a crop has to
remap them, and undo has to record image changes as well as annotation
changes.
