# Editor roadmap

Where the annotation editor is headed. The yardstick is ShareX's image
editor: what it offers, which parts Screvia adopts, and in what order.

## How the editor is built

- **One renderer.** `AnnotationRenderer` draws into a `CGContext` with a
  top-left origin. The canvas calls it through SwiftUI's `Canvas`, and export
  calls it on a bitmap at the capture's pixel size, so a tool is written once
  and the editor shows what gets saved.
- **A document.** `AnnotationDocument` holds the annotations and the crop,
  and is what undo snapshots. Annotation coordinates are fractions of the
  image (0–1, top-left origin).
- **Styles in image points.** Line widths and font sizes are in the
  capture's points, so they keep their proportion at any zoom and in the
  export. The last-used style is stored in preferences.
- **Text and steps are sized by font.** Their box follows the font size
  rather than a drag, as in ShareX, so labels can share a size. They move
  but have no resize handles.

## Phases

**Phase 0 — foundation (done).** One renderer; per-annotation style; select,
move, resize and delete.

**Phase 1 (done).**

- Tools: line, freehand, step (①②③, numbered by order, renumbered on
  delete)
- Text: colour, size, bold, and a box, outline or plain appearance;
  double-click to edit again
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
- Font choice; text that wraps inside a dragged box

**Not planned.** Cursor drawing (the capture settings cover it), cut out,
upload, print.

## Crop is a viewport

Every other tool adds a shape on top of the image; crop changes what is
kept. Rather than cutting the image and remapping every annotation, the crop
is a rectangle in annotation space stored in the document. The canvas shows
only that part (`CanvasLayout`), and export draws everything and then cuts
the bitmap. Annotations outside the crop are untouched, so undoing a crop
brings them back exactly.
