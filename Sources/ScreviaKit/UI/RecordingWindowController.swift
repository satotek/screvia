import AVKit
import SwiftUI

/// Shows a finished recording, already saved as MP4, to trim it, save it
/// as a GIF too, copy it, or find it in the Finder.
final class RecordingWindowController: NSObject, NSWindowDelegate {
    private static let barHeight: CGFloat = 52

    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var model: RecordingModel?
    private var onNotice: ((String, String) -> Void)?

    /// `onNotice` shows a short message with an SF Symbol.
    func show(videoURL: URL, onNotice: @escaping (String, String) -> Void) async {
        let size = await Self.windowSize(for: videoURL)
        window?.close()
        self.onNotice = onNotice

        let model = RecordingModel(videoURL: videoURL)
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: videoURL)
        playerView.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSHostingView(rootView: RecordingBar(
            model: model,
            onTrim: { [weak self] in self?.trim() },
            onSaveGIF: { [weak self] in self?.saveGIF() },
            onCopy: { [weak self] in self?.copyVideo() },
            onReveal: { [weak self] in self?.reveal() }
        ))
        // As in TextCaptureWindowController: the window is sized here and
        // by the user, never by the content.
        bar.sizingOptions = [.minSize]
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(playerView)
        content.addSubview(bar)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: playerView.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // Fixed, so the player keeps the rest: unpinned, the bar grew
            // into the player's space when AVKit's trimming bar replaced
            // the playback controls.
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight)
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        updateTitle(window, url: videoURL)
        window.center()

        self.window = window
        self.playerView = playerView
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        playerView?.player?.pause()
        playerView?.player = nil
        playerView = nil
        model = nil
        window = nil
    }

    /// The video's own size, or as much of it as fits two thirds of the
    /// screen, with room for the bar.
    private static func windowSize(for url: URL) async -> NSSize {
        let barHeight = Self.barHeight
        let fallback = NSSize(width: 720, height: 460)
        guard
            let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
            let naturalSize = try? await track.load(.naturalSize),
            let screen = NSScreen.main
        else {
            return fallback
        }
        let scale = screen.backingScaleFactor
        let video = CGSize(width: naturalSize.width / scale, height: naturalSize.height / scale)
        let limit = CGSize(width: screen.visibleFrame.width * 2 / 3, height: screen.visibleFrame.height * 2 / 3 - barHeight)
        let fit = min(1, limit.width / max(video.width, 1), limit.height / max(video.height, 1))
        return NSSize(
            width: max(520, (video.width * fit).rounded()),
            height: max(320, (video.height * fit).rounded() + barHeight)
        )
    }

    private func updateTitle(_ window: NSWindow, url: URL) {
        window.title = url.lastPathComponent
        // The proxy icon in the title bar drags the file into other apps.
        window.representedURL = url
    }

    // MARK: - Actions

    /// AVKit's own trimming bar; confirming it rewrites the saved file.
    private func trim() {
        guard let playerView, playerView.canBeginTrimming, let model else {
            return
        }
        Task { [weak self] in
            guard
                await playerView.beginTrimming() == .okButton,
                let item = playerView.player?.currentItem
            else {
                return
            }
            let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
            let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
            guard end > start else {
                return
            }
            self?.applyTrim(CMTimeRange(start: start, end: end), to: model.videoURL)
        }
    }

    private func applyTrim(_ range: CMTimeRange, to url: URL) {
        guard let model else {
            return
        }
        model.isBusy = true
        playerView?.player?.pause()
        let trimmed = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        Task { [weak self] in
            defer { model.isBusy = false }
            do {
                try await VideoExport.trim(url, to: range, destination: trimmed)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: trimmed)
                self?.playerView?.player = AVPlayer(url: url)
            } catch {
                try? FileManager.default.removeItem(at: trimmed)
                ErrorPresenter.present(error)
            }
        }
    }

    private func saveGIF() {
        guard let model else {
            return
        }
        let source = model.videoURL
        let destination = ImageStore.availableURL(
            in: source.deletingLastPathComponent(),
            baseName: source.deletingPathExtension().lastPathComponent,
            fileExtension: "gif"
        )
        let maxWidth = model.gifMaxWidth
        model.isBusy = true
        Task { [weak self] in
            defer { model.isBusy = false }
            do {
                try await VideoExport.gif(from: source, maxWidth: maxWidth, destination: destination)
                self?.onNotice?(L10n.text("recording.gifSaved"), "checkmark.circle.fill")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    /// The file itself, which Finder, Mail and chat apps paste as a video.
    private func copyVideo() {
        guard let model else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([model.videoURL as NSURL])
        onNotice?(L10n.text("recording.copied"), "doc.on.doc.fill")
    }

    private func reveal() {
        guard let model else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([model.videoURL])
    }
}

@Observable
final class RecordingModel {
    static let gifWidthChoices: [Int?] = [nil, 1280, 800, 480]
    private static let gifWidthKey = "gifMaxWidth"

    let videoURL: URL
    var isBusy = false
    /// nil keeps the video's own width. Remembered between recordings.
    var gifMaxWidth: Int? {
        didSet {
            UserDefaults.standard.set(gifMaxWidth ?? 0, forKey: Self.gifWidthKey)
        }
    }

    init(videoURL: URL) {
        self.videoURL = videoURL
        let stored = UserDefaults.standard.object(forKey: Self.gifWidthKey) as? Int ?? 800
        gifMaxWidth = stored > 0 ? stored : nil
    }
}

struct RecordingBar: View {
    @Bindable var model: RecordingModel
    let onTrim: () -> Void
    let onSaveGIF: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(L10n.text("recording.trim"), systemImage: "timeline.selection", action: onTrim)

            Spacer()

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text("recording.saving"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker(L10n.text("recording.gifWidth"), selection: $model.gifMaxWidth) {
                ForEach(RecordingModel.gifWidthChoices, id: \.self) { width in
                    Text(width.map { L10n.format("recording.widthPixels", $0) } ?? L10n.text("recording.originalSize"))
                        .tag(width)
                }
            }
            .fixedSize()

            Button(L10n.text("recording.saveGIF"), action: onSaveGIF)
                .keyboardShortcut(.defaultAction)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .help(L10n.text("recording.copy"))

            Button(action: onReveal) {
                Image(systemName: "folder")
            }
            .help(L10n.text("recording.reveal"))
        }
        .disabled(model.isBusy)
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

#if DEBUG
#Preview("Recording bar") {
    RecordingBar(
        model: RecordingModel(videoURL: URL(fileURLWithPath: "/tmp/Screenshot.mp4")),
        onTrim: {},
        onSaveGIF: {},
        onCopy: {},
        onReveal: {}
    )
    .frame(width: 640)
}
#endif
