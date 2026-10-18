import AppKit
import Sparkle

/// Finds and installs new versions of Screvia with Sparkle.
///
/// Nothing reaches the network until the user agrees. Info.plist leaves
/// `SUEnableAutomaticChecks` out, so Sparkle asks on the second launch
/// whether to check automatically, and checks only if the user says yes, or
/// when they choose Check for Updates. A check fetches the appcast from
/// GitHub; no information about the user or their captures is sent.
///
/// Updates are verified twice: the download against the EdDSA public key in
/// Info.plist, and the new app against this one's code signature, which is
/// why releases must stay signed with the same certificate.
public final class SoftwareUpdater: NSObject, ObservableObject {
    /// The version found by a scheduled check that is waiting for the user,
    /// shown in the capture hub rather than in a window that would take the
    /// focus from whatever they are doing.
    @Published private(set) var availableVersion: String?

    @Published var automaticallyChecks: Bool {
        didSet {
            if updater.automaticallyChecksForUpdates != automaticallyChecks {
                updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    @Published var automaticallyInstalls: Bool {
        didSet {
            if updater.automaticallyDownloadsUpdates != automaticallyInstalls {
                updater.automaticallyDownloadsUpdates = automaticallyInstalls
            }
        }
    }

    private var controller: SPUStandardUpdaterController!
    private var updater: SPUUpdater { controller.updater }

    public override init() {
        automaticallyChecks = false
        automaticallyInstalls = false
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        refresh()
    }

    /// Starts Sparkle's schedule. Separate from `init` so that previews and
    /// tests can make one without it.
    func start() {
        do {
            try updater.start()
        } catch {
            Log.app.error("Sparkle could not start: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Reads the settings again: Sparkle's own question on the second
    /// launch, and its update window, change them without telling us.
    func refresh() {
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
    }
}

extension SoftwareUpdater: SPUStandardUserDriverDelegate {
    // Screvia is a menu bar app, usually not the active one, so a window
    // opened by a scheduled check would come up behind the user's work or
    // take its focus. Sparkle shows the update itself only where it would
    // anyway have the user's attention, just after launch; otherwise the
    // capture hub offers it until the user looks.
    public var supportsGentleScheduledUpdateReminders: Bool { true }

    public func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            availableVersion = update.displayVersionString
        }
    }

    public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    public func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        refresh()
    }
}
