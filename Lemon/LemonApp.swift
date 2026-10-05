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
    @State private var settings = AppSettings.shared

    var body: some View {
        Text("Drag files and hold \(settings.convertShortcut.label) for formats")
        Text("or \(settings.toolsShortcut.label) for tools")

        Divider()

        Button("Reveal Last Result") {
            NSWorkspace.shared.activateFileViewerSelecting(state.lastResults)
        }
        .disabled(state.lastResults.isEmpty)

        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("Welcome Tour…") { WelcomeWindow.show() }

        Divider()

        Button("About Lemon") { SettingsWindow.show(tab: .about) }
        Button("Report a Problem…") { NSWorkspace.shared.open(ProjectInfo.issuesURL) }

        Divider()

        Button("Quit Lemon") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
