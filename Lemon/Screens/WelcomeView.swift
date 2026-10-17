import AppKit
import ServiceManagement
import SwiftUI

/// Opens the welcome tour (one at a time).
enum WelcomeWindow {
    private static var window: GlassWindow?

    /// `step` starts the tour part-way through (used by the debug demo option).
    static func show(step: Int = 0) {
        if let window { window.present(); return }
        let window = GlassWindow(size: CGSize(width: 660, height: 560)) {
            WelcomeView(onClose: { WelcomeWindow.window?.close() }, startStep: step)
        }
        window.onClose = {
            WelcomeWindow.window = nil
            AppSettings.shared.hasSeenWelcome = true
        }
        self.window = window
        window.present()
    }
}

struct WelcomeView: View {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void, startStep: Int = 0) {
        self.onClose = onClose
        _step = State(initialValue: Step(rawValue: startStep) ?? .welcome)
    }

    private enum Step: Int, CaseIterable {
        case welcome, convert, tools, saving, done
        var name: String {
            switch self {
            case .welcome: "Welcome"
            case .convert: "Convert"
            case .tools: "Tools"
            case .saving: "Saving"
            case .done: "Done"
            }
        }
    }

    @State private var step: Step
    @State private var settings = AppSettings.shared
    @State private var license = LicenseManager.shared
    @State private var jobs = JobCenter.shared
    @State private var practicePhoto: URL?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Jobs that already existed when the current step opened, so each practice step
    /// only celebrates its own result.
    @State private var knownJobs: Set<UUID> = []
    /// The practice result for each step. Kept here because finished jobs leave the job list.
    @State private var results: [Step: URL] = [:]

    var body: some View {
        GlassShell(title: "Welcome to Lemon", subtitle: "Step \(step.rawValue + 1) of \(Step.allCases.count)", onClose: onClose) {
            VStack(spacing: 18) {
                progress
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .convert: practiceStep(keys: settings.convertShortcut, target: "PNG",
                                                title: "Try it: convert a photo")
                    case .tools: practiceStep(keys: settings.toolsShortcut, target: "Crop or Compress",
                                              title: "Try it: edit with a tool")
                    case .saving: savingStep
                    case .done: doneStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .id(step)
            }
        } footer: {
            HStack {
                if step != .done {
                    Button("Skip Tour", action: onClose).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                if step != .welcome {
                    Button("Back") { move(-1) }.buttonStyle(.glass)
                }
                Button(step == .done ? "Start Using Lemon" : "Continue") {
                    if step == .done { onClose() } else { move(1) }
                }
                .buttonStyle(.glassProminent).tint(.lemonDeep).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .task { practicePhoto = makePracticePhoto() }
        .onChange(of: newPracticeResult) {
            if let url = newPracticeResult, step == .convert || step == .tools { results[step] = url }
        }
    }

    private func move(_ by: Int) {
        guard let next = Step(rawValue: step.rawValue + by) else { return }
        knownJobs = Set(jobs.jobs.map(\.id))
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    // MARK: Progress

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.lemonDeep : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                    Text(item.name)
                        .font(.caption2.weight(item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? .primary : .secondary)
                }
            }
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            VStack(spacing: 6) {
                Text("Convert and edit files by dragging them").font(.title.bold()).multilineTextAlignment(.center)
                Text("No windows to open, no files to upload. Drag, hold a key, drop.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                promise("hand.draw.fill", "Works with files from Finder, the desktop and any app you can drag from.")
                promise("doc.on.doc.fill", "Your originals are never changed. Lemon always saves a new copy.")
                promise("lock.shield.fill", "Everything happens on your Mac. Your files never leave it.")
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private func practiceStep(keys: DragShortcut, target: String, title: String) -> some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.bold())
            HStack(alignment: .center, spacing: 22) {
                if let practicePhoto {
                    VStack(spacing: 6) {
                        Image(nsImage: NSImage(contentsOf: practicePhoto) ?? NSImage())
                            .resizable().scaledToFit().frame(width: 150, height: 106)
                            .clipShape(.rect(cornerRadius: 12)).shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        Label("Drag me", systemImage: "hand.point.up.left.fill").font(.caption.weight(.medium))
                    }
                    .onDrag { NSItemProvider(object: practicePhoto as NSURL) }
                    .help("Start dragging this photo")
                }
                VStack(alignment: .leading, spacing: 12) {
                    instruction(1, Text("Start dragging the photo."))
                    HStack(spacing: 8) {
                        instruction(2, Text("While dragging, hold"))
                        KeyCaps(shortcut: keys)
                    }
                    instruction(3, Text("Drop it on **\(target)**."))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            if let saved = results[step] {
                Label("It worked! Lemon saved “\(saved.lastPathComponent)”.", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }.buttonStyle(.glass)
            } else {
                Text("Let go of the keys and the wheel closes. This practice photo doesn't use up your free uses.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var savingStep: some View {
        VStack(spacing: 18) {
            Text("New files appear next to the original").font(.title2.bold())
            HStack(spacing: 16) {
                fileIcon("photo.heic", highlighted: false)
                Image(systemName: "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(Color.lemonDeep)
                HStack(spacing: 10) {
                    fileIcon("photo.heic", highlighted: false)
                    fileIcon("photo.png", highlighted: true)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                promise("lock.doc.fill", "The original stays exactly as it was.")
                promise("number", "If a name is taken, Lemon adds a number: “photo 2.png”.")
                promise("hand.raised.fill", "macOS may ask once before Lemon saves into Desktop, Documents or Downloads. Click Allow.")
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            Button("Save to a Different Folder…") { SettingsWindow.show(tab: .saving) }.buttonStyle(.glass)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Text("Lemon lives in the menu bar").font(.title2.bold())
            HStack(spacing: 14) {
                Text("Settings, your last result and this tour are always one click away:")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "wifi").foregroundStyle(.secondary)
                    Image("MenuBarIcon")
                        .padding(4)
                        .background(Color.primary.opacity(0.15), in: .rect(cornerRadius: 5))
                    Text("9:41").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Lemon when you log in")
                        Text("So the wheel is always ready.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Open Lemon when you log in", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                .onChange(of: launchAtLogin) {
                    try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
                Divider()
                if license.isLicensed {
                    Label("Lemon is activated on this Mac. Thank you!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label {
                        Text(license.usesLeft == 0
                             ? "Your free uses are used up. Buy Lemon once to keep using it."
                             : "You have **\(license.usesLeft) free uses**. After that, buy Lemon once to keep using it.")
                    } icon: {
                        Image(systemName: "gift.fill").foregroundStyle(Color.lemonDeep)
                    }
                    HStack {
                        Button("Buy Lemon") { NSWorkspace.shared.open(StoreConfig.preferredBuyURL) }.buttonStyle(.glass)
                        Button("I Have a Licence Key") { SettingsWindow.show(tab: .licence) }.buttonStyle(.glass)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: Pieces

    private func promise(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Color.lemonDeep).frame(width: 22) }
    }

    private func instruction(_ number: Int, _ text: Text) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.bold()).foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.lemon, in: .circle)
            text
        }
    }

    private func fileIcon(_ name: String, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "photo.fill")
                .font(.system(size: 26))
                .foregroundStyle(highlighted ? Color.lemonDeep : .secondary)
                .frame(width: 52, height: 52)
                .background(.background, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(highlighted ? Color.lemonDeep : Color.secondary.opacity(0.3),
                                                                        lineWidth: highlighted ? 2 : 1))
            Text(name).font(.caption)
        }
    }

    // MARK: Practice files

    /// The newest practice result from a job that started after this step opened.
    private var newPracticeResult: URL? {
        for job in jobs.jobs.reversed() where !knownJobs.contains(job.id) {
            if case .finished(let urls) = job.state, let url = urls.first, Practice.contains(url) { return url }
        }
        return nil
    }

    /// A small lemon-yellow photo to practise on.
    private func makePracticePhoto() -> URL? {
        let url = Practice.folder.appendingPathComponent("Practice Photo.jpg")
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
