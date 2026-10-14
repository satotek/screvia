# Build and packaging

How the project is built, why it is arranged this way, and what to do when
the build system misbehaves.

## The hybrid layout

`Screvia.xcodeproj` is **generated** from `project.yml` by [XcodeGen][xg] and
is gitignored. `project.yml` is the source of truth.

The usual objection to committing an `.xcodeproj` is that `.pbxproj` conflicts
are unmergeable and unreviewable. Generating it removes that entirely: the
project file is a build artifact, and changes to it show up as readable YAML
diffs. The cost is that a fresh clone must run `xcodegen generate` before
Xcode can open anything.

```sh
xcodegen generate
open Screvia.xcodeproj
```

`App/Info.plist` is also generated (from the `info.properties` block in
`project.yml`) and gitignored for the same reason.

### Division of labour

| | Owns |
| --- | --- |
| `project.yml` → `Screvia.xcodeproj` | The app bundle: `@main`, Info.plist, icon, code signing |
| `Package.swift` → `ScreviaKit` | All application code, resources, and tests |

`Package.swift` has **no executable target**. The app exists only in the
Xcode project, which consumes `ScreviaKit` as a local package dependency.
`swift build` therefore builds a library, not a runnable app — that is
expected.

The payoff is that Xcode does the app-bundle work natively: copying resource
bundles into `Contents/Resources`, embedding the Swift runtime, generating
`PkgInfo`, and code signing. Before this, `scripts/BuildApp.swift`
re-implemented those steps by hand and hit their edge cases one at a time.

## Building

From Xcode: generate the project, open it, run the **Screvia** scheme.

From the command line:

```sh
swift scripts/BuildApp.swift              # generate, build, and open .build/Screvia.app
swift scripts/BuildApp.swift --no-open    # build only
swift scripts/CreateDMG.swift             # build, then wrap in dist/Screvia-<version>.dmg
```

### Signing

The signature decides whether macOS remembers privacy permissions. An ad-hoc
signature identifies the app by its binary hash, so macOS asks for Screen
Recording again after every rebuild or update. A certificate ties the identity
to the bundle ID and certificate instead, and the grant survives.

Without `--sign`, the scripts use the first of these the Mac has:

1. **`Screvia Code Signing`** — a self-signed certificate, valid until 2036,
   that releases are signed with. Needs no Apple Developer Program membership;
   Gatekeeper treats the app as unnotarized either way. Using it locally too
   means a local build and an installed release count as the same app.
2. **`Apple Development`** — free with an Apple ID (Xcode → Settings →
   Accounts).
3. **Ad-hoc**, as on CI.

`--sign <identity>` picks another certificate and `--sign -` forces ad-hoc.
Apple-issued certificates go through xcodebuild's own signing, with the team
ID read from the certificate. Anything else is built ad-hoc and re-signed with
`codesign` afterwards, inside out, because xcodebuild requires a team.

If xcodebuild's signer differs from the previous build, the script discards
`.build/DerivedData/Build` first: an incremental build would re-sign the
nested resource bundles without resealing the app around them.

The certificate and its private key live in the maintainer's login keychain.
Back them up (Keychain Access → export as .p12); losing them means every user
grants Screen Recording once more after the next update.

`SMAppService` (launch at login) requires a signed app, which is why even
local builds are signed.

### Releases

Pushing a `v*` tag runs `.github/workflows/release.yml`. It checks the tag
against `MARKETING_VERSION`, imports the certificate from the
`SCREVIA_SIGNING_P12` and `SCREVIA_SIGNING_P12_PASSWORD` secrets into a
throwaway keychain, runs `CreateDMG.swift`, and publishes the image and its
SHA-256 to GitHub Releases with `.github/release-notes.md` above the generated
notes.

```sh
# after bumping MARKETING_VERSION in project.yml
git tag v0.2.0 && git push origin v0.2.0
```

`BuildApp.swift` runs `xcodegen generate`, then `xcodebuild` with a
`-derivedDataPath` under `.build`, then `ditto`s the result to
`.build/Screvia.app`.

`CreateDMG.swift` reads the version from `MARKETING_VERSION` in `project.yml`,
so the image name cannot drift from what the app reports.

### Why the scripts are Swift

`scripts/` holds four Swift scripts and no shell. They started as `.sh` files;
`zsh`'s word-splitting rules silently produced empty arguments in a loop that
looked correct, which was the prompt to switch. Swift also matches the rest of
the repo, so there is one language to read.

## Previews

Select the **ScreviaKit** scheme, not Screvia. Xcode renders SwiftUI previews
only for targets it builds as a dynamic library; the app target is not one, so
previewing under the Screvia scheme demands `ENABLE_DEBUG_DYLIB`. See
[architecture.md](architecture.md#why-the-app-is-nearly-empty).

## Building ScreviaKit alone

```sh
export PLL_SOURCE_PACKAGES_PATH="$PWD/.build"
swift build
swift test
```

This path is what CI uses for compiling and testing, and it works without
Xcode open.

`PLL_SOURCE_PACKAGES_PATH` points LicenseList's build plugin at SwiftPM's
checkout directory. The plugin expects Xcode's `SourcePackages` layout; the
SwiftPM CLI puts the same structure under `.build` instead. `BuildApp.swift`
sets it itself, so it is only needed when invoking `swift` directly.

## CI

`.github/workflows/ci.yml` runs on the `xcode-27` image with Xcode 27.0 and,
on every push to `main` and every pull request:

1. installs XcodeGen
2. `swift build` and `swift test --parallel`
3. `swift scripts/BuildApp.swift --no-open`
4. `codesign --verify --deep --strict`

Step 3 exists because packaging regressions do not show up in a compile.
Running the same script a developer runs means CI exercises the real
packaging path rather than a parallel one.

Dependabot (`.github/dependabot.yml`) checks SwiftPM dependencies weekly and
GitHub Actions monthly.

## App icon

`Assets/AppIcon-master.png` is the artwork; `scripts/generate-icons.swift`
produces the `.iconset` and `.icns`.

macOS expects the icon art to occupy **824 of 1024 points** (80.5%), leaving a
transparent margin. Edge-to-edge artwork gets wrapped in the system's own
container on macOS 26 and reads as visibly oversized.
`scripts/regrid-appicon.swift` rescales by the alpha bounding box to put art
back on that grid.

## Troubleshooting

**`Validate plug-in "PrepareLicenseList"` fails in Xcode.** Build-tool plugins
need one-time trust. Xcode shows a **Trust & Enable** prompt on first build;
the decision is stored in `~/Library/org.swift.swiftpm/security/`.

**`error: SourcePackages not found`.** `PLL_SOURCE_PACKAGES_PATH` is unset —
see above.

**A rebuilt app still shows old behaviour.** `open` on an already-running
`LSUIElement` app with the same bundle ID just re-activates the existing
process. Kill it first:

```sh
pkill -f 'Screvia.app/Contents/MacOS/Screvia'
```

**`codesign: unsealed contents present in the bundle root`.** Something was
copied beside `Contents/` instead of inside `Contents/Resources/`. Xcode
handles this now, so it should only appear if the packaging scripts are
changed.

**IRGen crash with `SmallVector unable to grow` and no source location.** See
the concurrency note in [architecture.md](architecture.md#one-toolchain-landmine).

[xg]: https://github.com/yonaskolb/XcodeGen
