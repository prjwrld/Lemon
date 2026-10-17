import AppKit
import Observation
import Sparkle

/// Automatic updates (Sparkle). Lemon checks https://lemon-updates.edupurspose.workers.dev/appcast.xml once a day,
/// downloads a new version in the background and installs it when Lemon quits. Updates are signed with Lemon's
/// update key (see Config/Info.plist and scripts/release.sh), so only real Lemon releases are installed.
@Observable
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    /// Download and install new versions without asking.
    var automatic = false {
        didSet {
            guard let updater, updater.automaticallyDownloadsUpdates != automatic else { return }
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = automatic
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }

    /// False in Debug builds, which aren't released (their build number would always look out of date).
    var isAvailable: Bool { controller != nil }

    private override init() {
        super.init()
        #if !DEBUG
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        automatic = controller?.updater.automaticallyDownloadsUpdates ?? true
        #endif
    }

    /// Starts updates (called once at launch).
    func start() {}

    func checkNow() { controller?.checkForUpdates(nil) }

    var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: SPUStandardUserDriverDelegate

    /// A menu bar app has no window open when a scheduled check finds an update, so Sparkle shows a gentle
    /// reminder instead of popping a window over whatever the person is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
