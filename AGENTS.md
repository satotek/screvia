# AGENTS.md

What isn't obvious from reading the code. Background in [docs/](docs/).

## Build

```sh
export PLL_SOURCE_PACKAGES_PATH="$PWD/.build"   # LicenseList's plugin fails without it
swift test
swift scripts/BuildApp.swift --no-open          # the actual .app
```

`swift build` yields a library, not a runnable app: the app target lives in
`Screvia.xcodeproj`, which is **generated from `project.yml` and gitignored**.
Edit `project.yml`, never the `.xcodeproj`. Packaging breaks don't surface in
a library build, so build the app before calling a change done.

## Conventions

- User-facing strings → `Localizable.xcstrings`, read via `L10n`, en + ja.
- Logging → `Log`. Capture paths stay private, never `.public`.
- Views take values and closures, not singletons — that is what keeps previews
  working.
- A regression test counts only once seen failing against the unfixed code.

## Traps

- `open` on the running app only re-activates it. `pkill -f
  'Screvia.app/Contents/MacOS/Screvia'` first.
- Previews need the **ScreviaKit** scheme, not Screvia.
- `set: someMethod` on a `@MainActor` method crashes swift-frontend; wrap it —
  `set: { someMethod($0) }`.
