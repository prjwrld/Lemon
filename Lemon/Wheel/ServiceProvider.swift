import AppKit

/// "Convert with Lemon" and "Lemon Tools" in Finder's right-click menu (and the Services menu).
///
/// How it works: Info.plist lists the two services (NSServices) with the messages convertFiles and toolFiles.
/// macOS hands the selected files straight to the running Lemon (launching it first if needed) by calling the
/// matching method below with a pasteboard that holds them. No Automator workflow, no extra permission.
/// The wheel then opens at the pointer in click mode: hover a slice and click it.
final class ServiceProvider: NSObject {
    private let wheel: WheelController
    /// Files from calls still arriving: some file managers call once per selected file.
    private var pending: [URL] = []
    private var pendingMode = WheelMode.convert
    private var collectTimer: Timer?
    private static let collectWindow: TimeInterval = 0.35

    init(wheel: WheelController) {
        self.wheel = wheel
    }

    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if !receive(pasteboard, mode: .convert) { error.pointee = Self.noFilesMessage }
    }

    @objc func toolFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if !receive(pasteboard, mode: .tools) { error.pointee = Self.noFilesMessage }
    }

    private static let noFilesMessage = "Lemon couldn't find any files in the selection." as NSString

    /// Adds the pasteboard's files to the ones being collected, and opens the wheel once no more arrive
    /// for a moment. Returns false if the pasteboard names no existing file.
    @discardableResult
    func receive(_ pasteboard: NSPasteboard, mode: WheelMode) -> Bool {
        let files = Self.files(on: pasteboard)
        guard !files.isEmpty else { return false }
        pending += files
        pendingMode = mode
        collectTimer?.invalidate()
        collectTimer = Timer.scheduledTimer(withTimeInterval: Self.collectWindow, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.openWheel() }
        }
        return true
    }

    private func openWheel() {
        collectTimer = nil
        var seen = Set<String>()
        let files = pending.filter { seen.insert($0.standardizedFileURL.path).inserted }
        pending = []
        if !wheel.show(files: files, at: NSEvent.mouseLocation, mode: pendingMode, interaction: .click) {
            NSSound.beep()   // Lemon has nothing to offer for these files
        }
    }

    /// The existing files and folders on a pasteboard. Finder puts file URLs there; other file managers may put
    /// the older NSFilenamesPboardType list of paths, or only file-URL strings: the first of these that names any.
    static func files(on pasteboard: NSPasteboard) -> [URL] {
        let sources: [() -> [URL]] = [
            {
                pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            },
            {
                let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
                return paths.map { URL(fileURLWithPath: $0) }
            },
            {
                (pasteboard.pasteboardItems ?? []).compactMap { item in
                    item.string(forType: .fileURL).flatMap(URL.init(string:))
                }
            },
        ]
        for source in sources {
            let files = source().filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
            if !files.isEmpty { return files }
        }
        return []
    }
}
