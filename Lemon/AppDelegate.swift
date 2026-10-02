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
    #if DEBUG
    private var demoBackdrop: NSWindow?
    #endif

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
        // Add "-LemonDemoBackdrop /path/to/image" to put a picture behind it, to judge the glass.
        if UserDefaults.standard.bool(forKey: "LemonDemoWheel"), let screen = NSScreen.main {
            if let path = UserDefaults.standard.string(forKey: "LemonDemoBackdrop"),
               let image = NSImage(contentsOfFile: path) {
                let size: CGFloat = 560
                let window = NSWindow(
                    contentRect: NSRect(x: screen.frame.midX - size / 2, y: screen.frame.midY - size / 2, width: size, height: size),
                    styleMask: .borderless, backing: .buffered, defer: false)
                let imageView = NSImageView(image: image)
                imageView.imageScaling = .scaleAxesIndependently
                window.contentView = imageView
                window.level = .floating
                window.orderFrontRegardless()
                demoBackdrop = window
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.3) { self.demoBackdrop?.orderOut(nil) }
            }
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
