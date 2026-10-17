# Testing

```sh
export PLL_SOURCE_PACKAGES_PATH="$PWD/.build"
swift test
```

Tests live in `Tests/ScreviaKitTests/` and run against `ScreviaKit` through
`@testable import`. They need no display, no permissions and no network, so
they run identically on a laptop and in CI.

## What is tested, and what is not

The dividing line is whether behaviour is **deterministic without a screen or
a user**.

| Tested | Not tested |
| --- | --- |
| Settings persistence and defaults | Actual screen capture (needs a display and Screen Recording permission) |
| Capture history bookkeeping | Scroll event posting (needs Accessibility permission and a live target app) |
| Scroll frame stitching maths | SwiftUI view rendering |
| Image processing geometry | Global hotkey registration (Carbon, process-wide) |
| Annotation hit testing, moving, resizing and export | The editor's pointer handling (SwiftUI gestures) |
| Saving, encoding, clipboard | Launch at login against the real `SMAppService` |
| Thumbnail generation and caching | |

The untested column is not an oversight — those paths depend on system state
that a unit test cannot honestly stand in for. They are covered by running the
app.

## Suites

**`ScreviaSettingsTests`** — defaults, round-tripping every property through
`UserDefaults` (the editor's style included, with unreadable JSON falling back
to the standard style; the self-timer, with values outside its choices
falling back to off; the history size likewise falling back to 30), the file
number advancing only for templates that show it and surviving a relaunch,
unknown stored enum values falling back instead of crashing,
`styleOptions` clamping negative geometry, and `reset` persisting rather than
only changing memory.

**`CaptureHistoryStoreTests`** — newest-first ordering, path-standardized
deduplication, the 30-entry cap and a lower one, removal, session scoping, pruning entries
whose file is gone, and decoding history written before capture kinds existed.

**`ImageStitcherTests`** — per-index frame storage, difference scoring,
recovering a known scroll distance through overlap detection, and the stitched
canvas excluding overlapping strips.

**`ImageProcessorTests`** — the unstyled pass-through, padding and shadow
margin geometry, every background style producing a drawable image, and
Retina images downscaled to one pixel per point while 1× ones pass through.

**`ImageStoreTests`** — Save As writing the format its extension names and
replacing an existing file, directory creation, per-format extensions, the numeric
suffix that keeps two captures in the same second from overwriting each other,
JPEG quality actually reaching the encoder, and PNG (not TIFF) reaching the
pasteboard.

**`AnnotationGeometryTests`** — hit testing boxes by their inside (only
their outline for see-through ones under a drawing tool) and lines and
freehand by their stroke, finding handles in view space, moves stopping
at the image or crop edge without snapping a shape already past it, corner
and edge resizing, a box flipping when dragged past its opposite side,
freehand points scaling with their box, step numbering, duplicates getting
a new identity, a balloon's tail being its only handle, moving with it
and catching clicks along its length, bent lines passing through their
handle and hit along the curve, step labels in each format, and a magnifier enlarging an area
smaller by its zoom around a focus that it carries when moved and that
aiming moves without moving it, staying a circle in image points with only
corner handles when round.

**`AnnotationRendererTests`** — export keeping the capture's pixel size
rather than the main screen's scale, shapes landing in the right half
despite the coordinate flip, crops cut at full resolution and from the top,
text boxes following the font size, steps staying round on a non-square
image, a balloon's tail reaching its tip, the magnifier showing its focus rather
than what is under it, only inside its circle when round, and keeping its
proportions when aimed past the edge, border and shadow framing the
cropped image at full resolution, filled heads and heads at both ends, a
bent arrow drawn through its bend, and rounded corners.

**`CanvasLayoutTests`** — fitting the image inside the margin, a cropped
image extending past the visible rect so annotation space still lines up,
and zoom growing the scrollable content.

**`PixelReaderTests`** — the eyedropper reading the full image from the
top, the far edge staying inside, an area averaging its sRGB values rather
than light, and each colour code format.

**`HistoryThumbnailLoaderTests`** — thumbnail sizing and cache-key
distinctness, including a file replaced at the same path.

**`EditArchiveTests`** — a saved edit coming back with its document, point
size and pixels, only for its own file, and not once another app changed
the file; pruning edits whose file is gone or changed, then the oldest past
the limit; and edits and styles saved before balloons, effects and the
magnifier's settings still decoding.

**`ImageImportTests`** — imported images sized like a capture from this
screen without losing pixels, non-images rejected, and the clipboard read
whether it holds pixels or a copied image file (on a private pasteboard, so
the user's clipboard is untouched).

**`TextRecognizerTests`** — English lines read top to bottom, Japanese read
as Japanese (it fails if English is listed first), and an image with no text
reported as such, and lines joined without spaces between Japanese and
with them between Latin text. The first run of the suite loads Vision's model and takes
several seconds; later runs are fast. On GitHub's macOS runners Vision cannot
recognize text at all, so the tests that need it are skipped there; the
line-joining tests still run.

**`FileNameTemplateTests`** — the standard template reproducing the names
Screvia always used, every token filled in, a blank template falling back,
and characters that break file names replaced.

**`CursorSnapshotTests`** — the pointer drawn at its hot spot, in pixels, on
a 2× screen capture.

**`LocalizationKeyTests`** — every enum case whose title is looked up as
`"prefix.\(rawValue)"` has an en and a ja string in the catalog. Such keys
compile whether or not they exist, and a missing one shows the raw key.

**`LaunchAtLoginControllerTests`** — status mapping and register/unregister
behaviour against a fake service.

## Conventions

**Inject the dependency rather than reaching for a global.**
`ScreviaSettings` and `CaptureHistoryStore` take a `UserDefaults`, so tests
pass a throwaway suite and can never disturb the developer's own preferences:

```swift
suiteName = "ScreviaSettingsTests-\(UUID().uuidString)"
defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
// ... and removePersistentDomain in tearDown
```

`LaunchAtLoginController` takes a `LaunchAtLoginService`, so tests supply a
fake instead of registering the real app as a login item.

**Use deterministic images, not real screenshots.** `TestImages` builds
bitmaps with known pixel values — a gradient where every row differs, so any
vertical offset is detectable, or a flat colour where only the dimensions
matter. Asserting on a real screenshot would test the display, not the code.

**`setUp`/`tearDown` are `async throws` in `@MainActor` suites.** The
non-async `setUpWithError` runs nonisolated, which produces Swift 6 isolation
warnings when touching main-actor state. The async variants inherit the
suite's isolation.

**Files go to a per-test temporary directory** named with a UUID and removed
in `tearDown`.

## Writing a regression test

When a bug is fixed, the test for it should be **confirmed to fail against the
unfixed code**. Re-introduce the bug, run the suite, see it go red, then
restore the fix. A regression test that was never seen failing is not yet
known to test anything.

Three current tests came from this, all marked `/// Regression test.` in
source:

- `ImageStitcherTests.testStoreWritesADistinctFilePerIndex` — every scroll
  frame was written to one fixed filename, so a scrolling capture stitched N
  copies of the last frame.
- `HistoryThumbnailLoaderTests.testDifferentFilesDoNotShareACacheEntry` — the
  cache key was a constant, so the first thumbnail generated was returned for
  every entry in the history strip.
- `HistoryThumbnailLoaderTests.testAReplacedFileGetsANewThumbnail` — the
  cache was keyed by path alone, so saving a reopened edit over its file
  left the history strip showing the old picture.

The first two were missing string interpolations (`"frame-(index).png"` instead of
`"frame-\(index).png"`), which compile perfectly happily as literals.

## Where to add next

`AnnotationModel` is the largest piece of pure logic still uncovered — undo/
redo stacks and annotation coordinate transforms — and it needs no system
state to test.
