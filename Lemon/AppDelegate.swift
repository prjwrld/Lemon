import AppKit
import Observation

/// Things the menu needs to know about.
@Observable
final class AppState {
    var lastResults: [URL] = []
}

/// Connects the parts: drag watcher → wheel → editor (if any) → job → saved files.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private let watcher = DragWatcher()
    private let wheel = WheelController()
    private let hud = ProgressHUD()
    #if DEBUG
    private var demoBackdrop: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .utility).async { SafeSaver.removeLeftovers() }
        watcher.onDrag = { [weak self] files, point, mode in
            self?.wheel.show(files: files, at: point, mode: mode) ?? false
        }
        watcher.onModeChange = { [weak self] mode in
            self?.wheel.switchMode(to: mode) ?? false
        }
        watcher.onDragEnded = { [weak self] in
            self?.wheel.hide()
        }
        wheel.onChoose = { [weak self] files, action in
            self?.choose(action, files: files)
        }
        JobCenter.shared.onFinished = { [weak self] _, urls in
            self?.finished(urls)
        }
        watcher.start()
        hud.start()

        let demo = ["LemonDemoWheel", "LemonDemoEditor", "LemonDemoSettings"].contains { UserDefaults.standard.object(forKey: $0) != nil }
        if !AppSettings.shared.hasSeenWelcome && !demo {
            WelcomeWindow.show()
        }

        #if DEBUG
        runDesignDemoIfAsked()
        #endif
    }

    /// Something was dropped on the wheel.
    private func choose(_ action: Action, files: [URL]) {
        if case .tool(let tool) = action, tool.needsEditor {
            EditorPresenter.present(tool, files: files) { [weak self] options in
                self?.start(action, files: files, options: options)
            }
        } else {
            start(action, files: files, options: .none)
        }
    }

    private func start(_ action: Action, files: [URL], options: ToolOptions) {
        let settings = AppSettings.shared.conversion
        JobCenter.shared.start(title(for: action, files: files)) { context in
            try await Processor.run(action, files: files, options: options, settings: settings, context: context)
        }
    }

    private func title(for action: Action, files: [URL]) -> String {
        let what = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        switch action {
        case .convert(let format): return "\(what) → \(format.label)"
        case .tool(let tool): return "\(tool.label): \(what)"
        }
    }

    private func finished(_ urls: [URL]) {
        if !urls.isEmpty { state.lastResults = urls }
        if AppSettings.shared.feedback { Feedback.success() }
    }

    #if DEBUG
    /// Design helper: run with "-LemonDemoWheel YES" to show the wheel for 8 seconds,
    /// highlighting each slice in turn. Add "-LemonDemoMode tools" for the tools wheel,
    /// "-LemonDemoFile /path/file" to choose the file type, and
    /// "-LemonDemoBackdrop /path/to/image" to put a picture behind it, to judge the glass.
    private func runDesignDemoIfAsked() {
        let defaults = UserDefaults.standard
        // "-LemonDemoSettings about" opens Settings on that tab.
        if let name = defaults.string(forKey: "LemonDemoSettings"),
           let tab = SettingsView.Tab.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) {
            SettingsWindow.show(tab: tab)
        }
        guard defaults.bool(forKey: "LemonDemoWheel") || defaults.string(forKey: "LemonDemoEditor") != nil,
              let screen = NSScreen.main else { return }
        if let path = defaults.string(forKey: "LemonDemoBackdrop"), let image = NSImage(contentsOfFile: path) {
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
        let demoFile = URL(fileURLWithPath: defaults.string(forKey: "LemonDemoFile") ?? "/tmp/demo.jpg")
        // "-LemonDemoEditor crop" opens an editor for the demo file instead of the wheel.
        if let name = defaults.string(forKey: "LemonDemoEditor"), let tool = Tool(rawValue: name) {
            let files = (defaults.string(forKey: "LemonDemoFiles")?.components(separatedBy: "|").map { URL(fileURLWithPath: $0) }) ?? [demoFile]
            EditorPresenter.present(tool, files: files) { _ in }
            return
        }
        let mode = WheelMode(rawValue: defaults.string(forKey: "LemonDemoMode") ?? "") ?? .convert
        _ = wheel.show(files: [demoFile], at: NSPoint(x: screen.frame.midX, y: screen.frame.midY), mode: mode)
        for (step, slice) in [0, 1, 2, nil].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(step) * 1.5) { self.wheel.demoHover(slice) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.wheel.hide() }
    }
    #endif
}
