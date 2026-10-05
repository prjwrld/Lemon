import AppKit

/// Small sounds and trackpad taps. (Errors are shown in the progress panel.)
enum Feedback {
    static func hover() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func success() {
        NSSound(named: "Pop")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
