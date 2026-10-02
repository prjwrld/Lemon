import AppKit
import ServiceManagement
import SwiftUI

/// Opens the welcome tour (one at a time).
enum WelcomeWindow {
    private static var window: GlassWindow?

    static func show() {
        if let window { window.present(); return }
        let window = GlassWindow(size: CGSize(width: 560, height: 500)) {
            WelcomeView(onClose: { WelcomeWindow.window?.close() })
        }
        window.onClose = {
            WelcomeWindow.window = nil
            AppSettings.shared.hasSeenWelcome = true
        }
        self.window = window
        window.present()
    }

    /// A folder for practice files. Results saved here don't count as trial uses.
    nonisolated static let practiceFolder: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lemon/Practice", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    nonisolated static func isPractice(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(practiceFolder.standardizedFileURL.path)
    }
}

struct WelcomeView: View {
    let onClose: () -> Void

    @State private var step = 0
    @State private var settings = AppSettings.shared
    @State private var license = LicenseManager.shared
    @State private var jobs = JobCenter.shared
    @State private var practicePhoto: URL?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let titles = ["Convert with a drag", "Tools with a different key", "Where your files go", "Lemon lives in the menu bar"]

    var body: some View {
        GlassShell(title: "Welcome to Lemon", subtitle: "Step \(step + 1) of 4", onClose: onClose) {
            VStack(spacing: 16) {
                Text(titles[step]).font(.title.bold())
                Group {
                    switch step {
                    case 0: practice(keys: settings.convertShortcut.label, target: "PNG", result: "a PNG copy")
                    case 1: practice(keys: settings.toolsShortcut.label, target: "Crop or Compress", result: "a cropped or smaller copy")
                    case 2: savingStep
                    default: menuBarStep
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    ForEach(0..<4) { Circle().fill($0 == step ? Color.lemonDeep : .secondary.opacity(0.4)).frame(width: 7, height: 7) }
                }
            }
        } footer: {
            HStack {
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.glass) }
                Spacer()
                Button(step == 3 ? "Start Using Lemon" : "Next") {
                    if step == 3 { onClose() } else { step += 1 }
                }
                .buttonStyle(.glassProminent).tint(.lemonDeep).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .task { practicePhoto = makePracticePhoto() }
    }

    // MARK: Steps

    private func practice(keys: String, target: String, result: String) -> some View {
        VStack(spacing: 14) {
            Text("Start dragging this photo, then hold **\(keys)**. Drop it on **\(target)**.")
                .multilineTextAlignment(.center)
            if let practicePhoto {
                VStack(spacing: 6) {
                    Image(nsImage: NSImage(contentsOf: practicePhoto) ?? NSImage())
                        .resizable().scaledToFit().frame(width: 150, height: 110)
                        .clipShape(.rect(cornerRadius: 12)).shadow(radius: 6)
                    Text(practicePhoto.lastPathComponent).font(.caption)
                }
                .onDrag { NSItemProvider(object: practicePhoto as NSURL) }
                .help("Drag me")
            }
            if let saved = latestPracticeResult {
                Label("It worked! Lemon saved \(saved.lastPathComponent).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Lemon will save \(result) next to the original. Practice files don't use your free uses.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var savingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Results are saved next to the original file, as new copies.", systemImage: "doc.on.doc")
            Label("Your originals are never changed. A taken name gets a number: “photo 2.png”.", systemImage: "lock.doc")
            Label("macOS may ask once before Lemon saves into Desktop, Documents or Downloads. Click Allow.", systemImage: "hand.raised")
            Label("Everything happens on your Mac. Nothing is uploaded.", systemImage: "lock.shield")
            Button("Choose a Different Folder…") { SettingsWindow.show(tab: .folders) }.buttonStyle(.glass)
        }
        .labelStyle(WelcomeLabelStyle())
    }

    private var menuBarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Click Lemon's icon in the menu bar for Settings, your last result, and the tour.",
                  systemImage: "menubar.arrow.up.rectangle")
            Toggle("Open Lemon when I log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            Label(license.isLicensed ? "Lemon is licensed on this Mac. Thank you!" :
                    "You have \(license.usesLeft) free uses. After that, buy Lemon once to keep using it.",
                  systemImage: "gift")
            if !license.isLicensed {
                Button("Buy Lemon or Enter a Key…") { PurchaseWindow.show() }.buttonStyle(.glass)
            }
        }
        .labelStyle(WelcomeLabelStyle())
    }

    // MARK: Practice files

    private var latestPracticeResult: URL? {
        for job in jobs.jobs.reversed() {
            if case .finished(let urls) = job.state, let url = urls.first, WelcomeWindow.isPractice(url) { return url }
        }
        return nil
    }

    /// A small lemon-yellow photo to practise on.
    private func makePracticePhoto() -> URL? {
        let url = WelcomeWindow.practiceFolder.appendingPathComponent("Practice Photo.jpg")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let context = ImageEngine.makeContext(width: 800, height: 560, alpha: false) else { return nil }
        let colors = [CGColor(srgbRed: 1, green: 0.88, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.98, green: 0.6, blue: 0.1, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 800, y: 560), options: [])
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
        context.fillEllipse(in: CGRect(x: 250, y: 130, width: 300, height: 300))
        guard let image = context.makeImage() else { return nil }
        try? ImageEngine.write(image, to: url, format: .jpg, quality: 0.9)
        return url
    }
}

private struct WelcomeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.foregroundStyle(Color.lemonDeep).frame(width: 22)
            configuration.title
        }
    }
}
