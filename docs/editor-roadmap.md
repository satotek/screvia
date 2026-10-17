# Editor roadmap

Where the annotation editor is headed; the wider plan is in
[roadmap.md](roadmap.md). The yardstick is ShareX's image
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

**Phase 2 (in progress).** Done so far: speech balloon, magnifier, the
border and shadow image effects, picking up annotations with any tool, and a
readout of the colour under the pointer (Tab copies it, in a choice of
formats; the eyedropper picks a point or an area's average), the output
size and the true zoom, after Shottr's.

While an editor is open the app is a regular one, in the Dock and ⌘-Tab,
and goes back to a menu bar app when it closes.

Any tool picks up the annotation a drag starts on, as in ShareX, so one just
drawn can be adjusted without switching tools. With a drawing tool an
unfilled box or a highlight counts only its outline, so drawing inside one
still works. A plain click on empty space, where a drag would draw, switches
to the select tool; tools a click itself uses (text, balloon, step,
freehand) keep it.

The magnifier follows ShareX's: a circle by default, enlarging what is under
it, dragged from anywhere inside to move. On top of that, ⌥-dragging it aims
it at something else, as Snagit's can, leaving the magnifier where there is
room for it; the area it enlarges is then marked and can be dragged too.
That stays off the plain drag, since a handle in the middle would take the
drag that moves it.

Lines and arrows bend through a handle halfway along, as Shottr's do,
rather than through a separate curved-arrow tool; dragging it back onto the
straight line straightens them. Arrows have open or filled heads, at one end
or both; rectangles have rounded corners; steps count in numbers, letters or
Roman numerals.

Text comes in the system font's four designs (standard, rounded, serif,
monospaced) rather than a list of every installed font, which would be
hundreds long; each falls back to the system's Japanese font. Dragging with
the text tool makes a box that wraps at that width, with side handles to
change it; a click still makes one that grows with its single line.

- Tools: inserted images, emoji stickers, smart eraser
- Stacking order, paste from the clipboard
- Auto crop, rotate and flip, resize, canvas size
- More image effects

**Not planned.** Cursor drawing (the capture settings cover it), cut out,
upload, print.

## Crop is a viewport

Every other tool adds a shape on top of the image; crop changes what is
kept. Rather than cutting the image and remapping every annotation, the crop
is a rectangle in annotation space stored in the document. The canvas shows
only that part (`CanvasLayout`), and export draws everything and then cuts
the bitmap. Annotations outside the crop are untouched, so undoing a crop
brings them back exactly.
