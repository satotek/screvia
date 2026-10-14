## Install

Requires macOS 14 or later, on Apple silicon or Intel.

1. Download `Screvia-<version>.dmg`, open it, and drag Screvia to Applications.
2. Open Screvia once. macOS blocks it because the app is not notarized.
3. Go to System Settings → Privacy & Security, scroll to Security, and click
   **Open Anyway**, then confirm.

Or clear the quarantine flag from Terminal instead of steps 2–3:

```sh
xattr -dr com.apple.quarantine /Applications/Screvia.app
```

Screvia asks for Screen Recording on first capture, and for Accessibility
the first time you use scrolling capture. Every release is signed with the
same certificate, so updating keeps both permissions.

`Screvia-<version>.dmg.sha256` holds the image's SHA-256 checksum.
