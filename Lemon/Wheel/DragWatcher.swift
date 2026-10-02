import AppKit

/// Notices when the user drags files anywhere on the Mac while holding Shift.
///
/// How it works: when the mouse button goes down in any app, we start a small
/// timer. While the button is held, the timer checks three things:
/// is Shift held, has a new drag started (the shared "drag" pasteboard changed),
/// and does that drag contain files? If yes, we ask for the wheel.
/// Watching mouse clicks this way needs no special permission.
final class DragWatcher {
    /// Called once per drag. Return true if the wheel was shown.
    var onShiftDrag: ((_ files: [URL], _ screenPoint: NSPoint) -> Bool)?
    /// Called when the mouse button is released after the wheel was shown.
    var onDragEnded: (() -> Void)?

    private enum Phase {
        case idle
        case watching(changeCountAtMouseDown: Int)
        case wheelShown
        case ignored // this drag had no usable files
    }

    private var phase = Phase.idle
    private var monitors: [Any] = []
    private var timer: Timer?
    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseWentDown() }
        }
        // Backup: if a drag starts without us seeing the mouse-down.
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        monitors = [down, dragged].compactMap { $0 }
    }

    private func mouseWentDown() {
        phase = .watching(changeCountAtMouseDown: dragPasteboard.changeCount)
        startTimer()
    }

    private func mouseDragged() {
        if case .idle = phase {
            // We missed the mouse-down, so any existing drag counts as new.
            phase = .watching(changeCountAtMouseDown: -1)
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

    private func tick() {
        let buttonHeld = NSEvent.pressedMouseButtons & 1 != 0
        guard buttonHeld else {
            finishDrag()
            return
        }

        guard case let .watching(startCount) = phase,
              NSEvent.modifierFlags.contains(.shift),
              dragPasteboard.changeCount != startCount
        else { return }

        let files = dragPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        if !files.isEmpty, onShiftDrag?(files, NSEvent.mouseLocation) == true {
            phase = .wheelShown
        } else {
            phase = .ignored
        }
    }

    private func finishDrag() {
        timer?.invalidate()
        timer = nil
        if case .wheelShown = phase {
            onDragEnded?()
        }
        phase = .idle
    }
}
