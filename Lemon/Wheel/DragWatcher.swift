import AppKit

/// Notices when files are dragged anywhere on the Mac while the chosen keys are held
/// (Shift for formats, Option + Shift for tools, by default).
///
/// How it works: when the mouse button goes down in any app, we start a small
/// timer. While the button is held, the timer checks: are the right keys held,
/// has a new drag started (the shared "drag" pasteboard changed), and does that drag
/// contain files? If yes, we ask for the wheel. Watching mouse clicks this way needs
/// no special permission. The wheel is open only while the keys are held: changing
/// the keys mid-drag switches wheels, and letting go of them closes it.
final class DragWatcher {
    /// Called to show the wheel. Return true if it was shown.
    var onDrag: ((_ files: [URL], _ screenPoint: NSPoint, _ mode: WheelMode) -> Bool)?
    /// Called when the keys change to the other wheel's shortcut while the wheel is open.
    /// Return false if that wheel has nothing to offer for these files.
    var onModeChange: ((WheelMode) -> Bool)?
    /// Called when the mouse button is released after the wheel was shown.
    var onDragEnded: (() -> Void)?
    /// Called when the keys are let go mid-drag: the wheel closes. Holding them again reopens it.
    var onKeysReleased: (() -> Void)?

    private enum Phase {
        case idle
        case watching(changeCountAtMouseDown: Int)
        case wheelShown(WheelMode)
    }

    private var phase = Phase.idle
    /// Modes already tried for this drag that had nothing to offer.
    private var emptyModes: Set<WheelMode> = []
    /// When the keys were let go while the wheel was open. A very short grace period
    /// ignores keys that flicker for a moment, e.g. while changing from one combination to the other.
    private var keysReleasedAt: TimeInterval?
    private static let releaseGrace: TimeInterval = 0.05
    private var monitors: [Any] = []
    private var timer: Timer?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private let settings = AppSettings.shared

    func start() {
        // Global monitors see other apps; local ones see Lemon's own windows (the welcome tour).
        let globalDown = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseWentDown() }
        }
        let globalDragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        let localDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseWentDown() }
            return event
        }
        let localDragged = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDragged() }
            return event
        }
        monitors = [globalDown, globalDragged, localDown, localDragged].compactMap { $0 }
    }

    private func mouseWentDown() {
        phase = .watching(changeCountAtMouseDown: dragPasteboard.changeCount)
        emptyModes = []
        startTimer()
    }

    private func mouseDragged() {
        if case .idle = phase {
            // We missed the mouse-down, so any existing drag counts as new.
            phase = .watching(changeCountAtMouseDown: -1)
            emptyModes = []
            startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Which wheel the held keys ask for, if any.
    private var requestedMode: WheelMode? {
        let flags = NSEvent.modifierFlags
        if settings.toolsShortcut.matches(flags) { return .tools }
        if settings.convertShortcut.matches(flags) { return .convert }
        return nil
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            finishDrag()
            return
        }

        switch phase {
        case .idle:
            return
        case .wheelShown(let current):
            guard let mode = requestedMode else {
                // Keys let go: close the wheel, but keep watching this drag so holding them again reopens it.
                let now = ProcessInfo.processInfo.systemUptime
                if let releasedAt = keysReleasedAt {
                    if now - releasedAt >= Self.releaseGrace {
                        keysReleasedAt = nil
                        phase = .watching(changeCountAtMouseDown: -1)
                        onKeysReleased?()
                    }
                } else {
                    keysReleasedAt = now
                }
                return
            }
            keysReleasedAt = nil
            if mode != current, !emptyModes.contains(mode) {
                if onModeChange?(mode) == true { phase = .wheelShown(mode) } else { emptyModes.insert(mode) }
            }
        case .watching(let startCount):
            guard let mode = requestedMode, !emptyModes.contains(mode),
                  dragPasteboard.changeCount != startCount
            else { return }
            let files = dragPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
            if !files.isEmpty, onDrag?(files, NSEvent.mouseLocation, mode) == true {
                phase = .wheelShown(mode)
            } else {
                emptyModes.insert(mode)
            }
        }
    }

    private func finishDrag() {
        timer?.invalidate()
        timer = nil
        if case .wheelShown = phase {
            onDragEnded?()
        }
        phase = .idle
        keysReleasedAt = nil
    }
}
