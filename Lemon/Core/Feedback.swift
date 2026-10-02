import AppKit

/// Small sounds, trackpad taps and error messages.
enum Feedback {
    static func hover() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func success() {
        NSSound(named: "Pop")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func showErrors(_ messages: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messages.count == 1 ? "Lemon couldn't convert a file" : "Lemon couldn't convert \(messages.count) files"
        alert.informativeText = messages.joined(separator: "\n")
        NSApp.activate()
        alert.runModal()
    }
}
