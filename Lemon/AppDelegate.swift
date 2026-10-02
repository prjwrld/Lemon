import AppKit
import Observation

/// Things the menu needs to know about.
@Observable
final class AppState {
    var lastResults: [URL] = []
}

/// Connects the parts: drag watcher → wheel → converter → feedback.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private let watcher = DragWatcher()
    private let wheel = WheelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher.onShiftDrag = { [weak self] files, point in
            self?.wheel.show(files: files, at: point) ?? false
        }
        watcher.onDragEnded = { [weak self] in
            self?.wheel.hide()
        }
        wheel.onChoose = { [weak self] files, format in
            self?.convert(files, to: format)
        }
        watcher.start()

        #if DEBUG
        // Design helper: run with "-LemonDemoWheel YES" to show the wheel for 8 seconds,
        // highlighting each slice in turn.
        if UserDefaults.standard.bool(forKey: "LemonDemoWheel"), let screen = NSScreen.main {
            let demoFile = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/demo.jpg")
            _ = wheel.show(files: [demoFile], at: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
            for (step, slice) in [0, 1, 2, nil].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(step) * 1.5) { self.wheel.demoHover(slice) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.wheel.hide() }
        }
        #endif
    }

    private func convert(_ files: [URL], to format: ImageFormat) {
        Task {
            // The heavy work runs off the main thread, so the UI stays smooth.
            let outcome = await Task.detached(priority: .userInitiated) {
                ImageConverter.convert(files, to: format)
            }.value

            if !outcome.saved.isEmpty {
                state.lastResults = outcome.saved
                Feedback.success()
            }
            if !outcome.failures.isEmpty {
                Feedback.showErrors(outcome.failures)
            }
        }
    }
}
