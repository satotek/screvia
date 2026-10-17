# Roadmap

What Screvia is aiming to be, and the order of the work. The editor has its
own plan in [editor-roadmap.md](editor-roadmap.md).

## Position

ShareX for the Mac: free, and nothing leaves the Mac. Screvia does not chase
CleanShot X's everything-included scope. It competes on a capable editor and
on keeping captures local, which rules out cloud sharing.

Compared with the common alternatives (as of October 2026, after OCR and
the self-timer landed):

| | Screvia has | Screvia lacks |
| --- | --- | --- |
| macOS (⇧⌘5) | Scrolling capture, backgrounds, pinning, history, an editor | Screen recording |
| CleanShot X | Price, local-only | Recording, cloud |
| Shottr | A ShareX-style editor | Pixel loupe and measuring, colour picker |
| Snagit | Price, native and light | Recording, templates, step capture |
| Xnapper | Price | Automatic balancing, social presets |

## Order

1. **Edit any image** (done in 0.2.0), not only Screvia's own captures:
   from the clipboard, from a file, dropped on the menu bar icon, or via
   Finder's Open With.
2. **Small, high-value capture features** (done): OCR with Vision on
   device, as a capture mode and in the editor; a self-timer counting down
   in the menu bar; and capturing the previous area again.
3. **Re-editing after saving** (done): the original and the annotations of
   every saved edit are kept in Application Support, so reopening the file
   from history or Finder brings the annotations back, until another app
   changes the file.
4. **The rest of the editor's phase 2** (started): speech balloons, the
   magnifier, and border and shadow effects are done; the rest of phase 2
   is in [editor-roadmap.md](editor-roadmap.md).
5. **Pixel loupe and measuring while selecting.** The colour picker is done,
   in the editor: the colour under the pointer, Tab to copy it, and an
   eyedropper.

**Deferred.** Notarization (needs the paid Apple Developer Program) and
automatic updates with Sparkle. Without them a first launch meets
Gatekeeper's warning; that is accepted for now.

**Not planned.** Screen recording and GIFs (a separate product's worth of
work), cloud sharing links (gives up local-only).
