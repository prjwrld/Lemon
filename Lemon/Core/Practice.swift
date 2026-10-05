import Foundation

/// The welcome tour's practice files live in their own folder, and their results are
/// always saved next to them (never in the Settings → Folders folder), so the tour can find them.
nonisolated enum Practice {
    static let folder: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lemon/Practice", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path)
    }
}
