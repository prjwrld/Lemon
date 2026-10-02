import SwiftUI

/// The app's starting point. Lemon has no main window and no Dock icon
/// (LSUIElement is set in the build settings). It only lives in the menu bar.
@main
struct LemonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Lemon", systemImage: "arrow.triangle.2.circlepath.circle") {
            MenuContent(state: appDelegate.state)
        }
    }
}

/// The items in the menu bar menu.
private struct MenuContent: View {
    let state: AppState

    var body: some View {
        Text("Hold Shift while dragging images")
        Text("Drop on a slice to convert")

        Divider()

        Button("Reveal Last Result") {
            NSWorkspace.shared.activateFileViewerSelecting(state.lastResults)
        }
        .disabled(state.lastResults.isEmpty)

        Divider()

        Button("Quit Lemon") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
