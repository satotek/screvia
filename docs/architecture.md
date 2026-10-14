# Architecture

How Screvia is put together, and why. For build mechanics see
[build-and-packaging.md](build-and-packaging.md); for the test strategy see
[testing.md](testing.md).

## Shape of the project

Screvia is a menu bar app with no main window and no Dock icon
(`LSUIElement`). It ships as a hybrid of an Xcode project and a SwiftPM
package:

```
App/                    The .xcodeproj app target — @main and Info.plist only
Sources/ScreviaKit/     Everything else, as a SwiftPM library
Tests/ScreviaKitTests/  Tests against that library
project.yml             Source of truth for Screvia.xcodeproj (XcodeGen)
```

`Screvia.xcodeproj` embeds `ScreviaKit` as a local package dependency. The app
target holds one file, `App/ScreviaApp.swift`, whose only job is `@main`.

### Why the app is nearly empty

Two reasons, and the second is the one that forced the split.

1. Anything in the app target can only be reached by building the app.
   Anything in `ScreviaKit` can also be reached by `swift build` and
   `swift test`, which is what makes the suite in `Tests/` possible at all.

2. **Xcode renders SwiftUI previews only for targets it builds as a dynamic
   library.** An app target is not one, so previewing a view that lives in the
   app target demands `ENABLE_DEBUG_DYLIB`. Moving the views into a library
   sidesteps that entirely — select the **ScreviaKit** scheme in Xcode and
   previews work with no extra build settings.

## Runtime structure

`AppDelegate` owns the status bar item and two coordinators. There is
deliberately no single "app model" object above them:

```
AppDelegate
├── ScreviaSettings          @Published, backed by UserDefaults
├── CaptureCoordinator       capture → process → save → present, + history
└── WindowsCoordinator       Preferences / About / Licenses windows
```

`SystemSettingsService` (system settings deep links, folder reveal) and
`ErrorPresenter` (the alert flow) hold no state, so they are plain enums with
static members rather than instances anyone has to own.

### Why two coordinators and no facade

These previously lived in one `ScreviaModel` class that `AppDelegate` talked
to as a facade. It had grown to 451 lines spanning capture orchestration,
history, three window controllers, system deep links, and error presentation
— a God Object.

The split follows what actually has state and cross-method coordination:

- **`CaptureCoordinator`** genuinely coordinates. A capture flows through
  selection overlay → `CaptureService` → `CaptureProcessingPipeline` →
  `ImageStore` → history → thumbnail/editor/clipboard, and steps share state
  along the way. That is what earns the name.
- **`WindowsCoordinator`** is thin, but it exists so `AppDelegate` holds one
  reference instead of three window controllers.
- Everything else was **stateless pass-through**, so it became free functions
  rather than another object.

The facade went away because `AppDelegate` rebuilds the popover's view on
every toggle anyway — a forwarding layer added indirection and nothing else.

### The capture pipeline

```
selection overlay          AreaSelectionController / WindowSelectionController
        │
CaptureService             ScreenCaptureKit (SCScreenshotManager)
        │                  ScrollingCaptureService for scroll captures
CaptureProcessingPipeline  actor — ImageProcessor + ImageStore off the main actor
        │
CaptureCoordinator         history, thumbnail, editor, clipboard
```

`CaptureProcessingPipeline` is an `actor` for two reasons: it keeps image
encoding off the main actor so the UI does not stutter on a large capture, and
it serializes writes so two hotkeys pressed together cannot race while picking
a unique destination filename.

### Scrolling capture

`ScrollingCaptureService` posts Quartz scroll wheel events and captures the
viewport repeatedly, rather than scripting individual apps. That keeps it
working across browsers, document readers, terminals and native AppKit apps
with one implementation.

`ImageStitcher` then joins the frames. It compares consecutive viewports to
find how far the content actually moved (`bestOverlap`), stops early when two
frames are near-identical because the document has hit its end
(`differenceScore`), and writes each frame to disk while working so the final
canvas is the only large allocation left in memory.

Because the events are posted globally, this path needs Accessibility
permission on top of Screen Recording.

## UI conventions

**Views take values and closures, never singletons.** Every SwiftUI view in
`Sources/ScreviaKit/UI/` receives plain data and callbacks — see
`CaptureHubView`'s parameter list. This is what makes them previewable in
isolation; `PreviewFixtures.swift` supplies the sample data.

**AppKit owns the windows, SwiftUI owns the contents.** Each standalone window
is an `NSWindowController` hosting an `NSHostingView`. A menu bar app has no
menu bar of its own and no scene-based lifecycle, so the AppKit side stays
explicit rather than fighting SwiftUI's window management.

## Concurrency

The package builds in **Swift 6 language mode** — complete strict concurrency
checking, no warnings suppressed — with the same defaults Xcode 27 gives a new
app target (`Package.swift`'s `swiftSettings`):

- **Default isolation is `MainActor`.** Undecorated code runs on the main
  actor, so UI types carry no annotation. Anything that has to leave it says
  so with `nonisolated`.
- **Async functions stay on their caller's actor**
  (`NonisolatedNonsendingByDefault`). Being `async` no longer moves work off
  the main actor; only `@concurrent` does.

The exceptions to "everything is main-actor" are deliberate:

- The imaging and capture types (`ImageProcessor`, `ImageStore`,
  `ImageStitcher`, `HistoryThumbnailLoader`, `CaptureService`,
  `ScrollingCaptureService`) and the values passed to them are `nonisolated`,
  so `CaptureProcessingPipeline` and `@concurrent` functions can use them.
  `CaptureService.captureMainDisplay()` alone stays `@MainActor`: it reads the
  mouse location.
- `CaptureProcessingPipeline` is an `actor` (see above).
- Heavy work leaves the main actor through `@concurrent` functions rather than
  `Task.detached`: the scrolling capture loop, thumbnail decoding
  (`HistoryThumbnailLoader.loadPNGData`) and history file reads. Unlike a
  detached task, the work stays part of the caller's task, so `.task(id:)`
  cancellation and priority reach it.
- Window capture through ScreenCaptureKit is deliberately *not*
  `@concurrent`: it only awaits the system, so it runs on the caller's actor.
- `HistoryThumbnailLoader`'s `NSCache` sits behind an `@unchecked Sendable`
  box. `NSCache` is documented thread-safe; the annotation asserts what Apple
  already guarantees but the type system cannot express.
- `ScrollingCaptureService` imports `ApplicationServices` with
  `@preconcurrency`, because `kAXTrustedCheckOptionPrompt` imports as a global
  `var` from a header that predates `Sendable` auditing.

### One toolchain landmine

Passing a `@MainActor` instance method as a bare method reference — rather
than wrapping it in a closure literal — can crash `swift-frontend`'s IRGen on
Swift 6.3.2 while emitting the isolation-forwarding thunk:

```swift
set: setLaunchAtLogin      // crashed the compiler
set: { setLaunchAtLogin($0) }   // fine, and identical at runtime
```

If a build dies with `SmallVector unable to grow` inside IRGen and no source
location, look for this pattern first.

## Localization

All UI strings live in one String Catalog:
`Sources/ScreviaKit/Resources/Localizable.xcstrings` (English and Japanese).
Both `xcodebuild` and the SwiftPM CLI compile it into per-language `.strings`
inside the resource bundle.

It lives in `ScreviaKit` rather than the app target so that previews — which
load `ScreviaKit` as a standalone dylib, with no app bundle around it — see
the same strings the shipped app does.

`App/en.lproj` and `App/ja.lproj` hold exactly one key,
`NSScreenCaptureUsageDescription`. That string belongs to `App/Info.plist` for
the system permission prompt, and Info.plist localization cannot live inside
the package.

`L10n` (in `Support/Localization.swift`) is the only lookup path, and it
resolves through `ScreviaBundle`.

### ScreviaBundle

`ScreviaBundle` locates the resource bundle by hand instead of using SwiftPM's
generated `Bundle.module`. The generated accessor looks in exactly one place
and calls `fatalError` when the bundle is not there — but `Screvia.app` keeps
it in `Contents/Resources`, because anything beside `Contents` is unsealed
content that `codesign` refuses to sign. `ScreviaBundle` searches the
plausible locations and logs an error instead of crashing.

## Logging

Screvia logs through the unified logging system under the subsystem
`dev.satotek.screvia`, with categories in `Support/Log.swift`: `capture`,
`storage`, `shortcuts`, `ui`, `app`.

**Capture paths stay private; error types, formats and hotkey names are
public.** A screenshot path contains the user's home directory, so it is never
marked `.public`.

```sh
log stream --predicate 'subsystem == "dev.satotek.screvia"' --level info
```

## Privacy

No network code ships in the app. Captures are written to the configured
folder and never leave the machine. Capture history is session-scoped: the
files stay on disk, but a relaunch starts with an empty history strip.

## Dependencies

Two, both build-time-resolved SwiftPM packages:

- **[KeyboardShortcuts][ks]** — remappable global hotkeys, registered through
  Carbon's `RegisterEventHotKey` so they do not collide with other apps.
  Chosen over `NSEvent.addGlobalMonitorForEvents`, which cannot claim a
  combination exclusively.
- **[LicenseList][ll]** — generates the open source license list from the
  resolved package checkouts at build time, so the Licenses window can never
  drift from what actually ships.

Everything else is Apple frameworks only.

[ks]: https://github.com/sindresorhus/KeyboardShortcuts
[ll]: https://github.com/cybozu/LicenseList
