import AppKit
import ServiceManagement
import SwiftUI

/// Opens the Settings window (one at a time).
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(tab: SettingsView.Tab = .general) {
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Lemon Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(selection: tab))
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsWindow.window = nil }
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", formats = "Formats", compatibility = "Compatibility", folders = "Folders", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .formats: "doc.badge.gearshape"
            case .compatibility: "square.grid.3x3"
            case .folders: "folder"
            case .about: "info.circle"
            }
        }
    }

    @State var selection: Tab

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                Group {
                    switch tab {
                    case .general: GeneralTab()
                    case .formats: FormatsTab()
                    case .compatibility: CompatibilityTab()
                    case .folders: FoldersTab()
                    case .about: AboutTab()
                    }
                }
                .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .tint(.lemonDeep)
        .frame(minWidth: 560, minHeight: 520)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @State private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Look") {
                Picker("Wheel style", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Behaviour") {
                Toggle("Open Lemon when I log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Sound and trackpad feedback", isOn: $settings.feedback)
            }
            Section {
                Picker("Formats wheel", selection: $settings.convertShortcut) {
                    ForEach(DragShortcut.allCases) { Text($0.label).tag($0) }
                }
                Picker("Tools wheel", selection: $settings.toolsShortcut) {
                    ForEach(DragShortcut.allCases) { Text($0.label).tag($0) }
                }
                if settings.convertShortcut == settings.toolsShortcut {
                    Text("Choose different keys for the two wheels.").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Keys to hold while dragging")
            } footer: {
                Text("Start dragging files in Finder, then hold these keys.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Show Welcome Tour") { WelcomeWindow.show() }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS didn't allow this: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Formats

private struct FormatsTab: View {
    @State private var settings = AppSettings.shared
    @State private var search = ""
    @State private var selected: OutputFormat? = .jpg

    private var formats: [OutputFormat] {
        OutputFormat.allCases.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).padding(8)
                List(formats, id: \.self, selection: $selected) { format in
                    Text(format.label).tag(format)
                }
            }
            .frame(width: 160)
            Divider()
            Form {
                if let format = selected { options(for: format) } else { Text("Choose a format").foregroundStyle(.secondary) }
                Section("Compress tool") {
                    Picker("Strength", selection: $settings.conversion.compression) {
                        ForEach(Strength.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder private func options(for format: OutputFormat) -> some View {
        Section("\(format.label) defaults") {
            switch format.kind {
            case .image:
                if ImageEngine.isLossy(format) {
                    qualityPicker(format)
                } else {
                    Text("\(format.label) is lossless: nothing to set just for it.").foregroundStyle(.secondary)
                }
            case .video where format == .gif:
                Stepper("Frames per second: \(settings.conversion.gifFPS)", value: $settings.conversion.gifFPS, in: 5...30)
                Picker("Width", selection: $settings.conversion.gifWidth) {
                    ForEach([320, 480, 640, 800, 1080], id: \.self) { Text("Up to \($0) px").tag($0) }
                }
            case .video:
                qualityPicker(format)
                Picker("Height", selection: $settings.conversion.videoHeight) {
                    Text("Original").tag(Int?.none)
                    ForEach([2160, 1080, 720, 480], id: \.self) { Text("\($0)p").tag(Int?.some($0)) }
                }
            case .audio:
                if [.mp3, .m4a, .opus, .wma].contains(format) {
                    Picker("Bitrate", selection: bitrate(format)) {
                        ForEach([64, 96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                } else if format == .ogg {
                    qualityPicker(format)
                } else {
                    Text("\(format.label) is lossless: nothing to set.").foregroundStyle(.secondary)
                }
            case .document where format == .pdf:
                Text("Pictures keep their size; text uses Letter or A4 pages for your region.").foregroundStyle(.secondary)
            default:
                Text("No options for \(format.label).").foregroundStyle(.secondary)
            }
        }
        // These apply to every picture Lemon makes, so they're kept apart from the per-format choices.
        if format.kind == .image {
            Section {
                Toggle("Keep photo details (camera, location, date)", isOn: $settings.conversion.keepMetadata)
                Picker("Size", selection: $settings.conversion.maxImageSize) {
                    Text("Original").tag(Int?.none)
                    ForEach([3840, 2560, 1920, 1280], id: \.self) { Text("Up to \($0) px").tag(Int?.some($0)) }
                }
                if format == .jpg || format == .png { dpiPicker }
            } header: {
                Text("All picture formats")
            } footer: {
                Text("These settings apply to every picture format.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func qualityPicker(_ format: OutputFormat) -> some View {
        Picker("Quality", selection: Binding(get: { settings.conversion.quality(for: format) },
                                             set: { settings.conversion.quality[format] = $0 })) {
            ForEach(Quality.allCases) { Text($0.label).tag($0) }
        }
    }

    private var dpiPicker: some View {
        Picker("PDF pages as pictures", selection: $settings.conversion.pdfDPI) {
            Text("150 dpi").tag(150); Text("300 dpi").tag(300)
        }
    }

    private func bitrate(_ format: OutputFormat) -> Binding<Int> {
        Binding(get: { settings.conversion.bitrate(for: format) }, set: { settings.conversion.audioBitrate[format] = $0 })
    }
}

// MARK: - Compatibility

private struct CompatibilityTab: View {
    private let rows: [(FileKind, String)] = [
        (.image, "JPG, PNG, HEIC, WebP, AVIF, TIFF, BMP"), (.svg, "SVG"), (.gif, "GIF"),
        (.video, "MP4, MOV, MKV, WebM, AVI, WMV, M4V…"), (.audio, "MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA"),
        (.pdf, "PDF"), (.text, "TXT"), (.subtitle, "SRT, VTT"), (.archive, "ZIP, TAR, GZIP, RAR, 7Z"),
    ]

    var body: some View {
        Form {
            ForEach(rows, id: \.0) { kind, inputs in
                Section(inputs) {
                    LabeledContent("Convert to (Shift)") {
                        Text(ActionCatalog.outputs(for: kind).filter { kind != .svg || $0 != .docx }
                            .map(\.label).joined(separator: ", ")).multilineTextAlignment(.trailing)
                    }
                    let one = ActionCatalog.tools(for: kind, multiple: false).map(\.label)
                    let many = ActionCatalog.tools(for: kind, multiple: true).map(\.label)
                    if !one.isEmpty { LabeledContent("Tools, one file") { Text(one.joined(separator: ", ")).multilineTextAlignment(.trailing) } }
                    if !many.isEmpty { LabeledContent("Tools, several") { Text(many.joined(separator: ", ")).multilineTextAlignment(.trailing) } }
                }
            }
            Section {
                Text("Word (DOCX) is offered for JPG and PNG pictures and PDFs. Lemon can open RAR files but not create them (RAR needs a licence from its owner).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Folders

private struct FoldersTab: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Save results") {
                Picker("Where", selection: Binding(
                    get: { settings.conversion.outputFolderPath == nil },
                    set: { nextToOriginal in
                        if nextToOriginal { settings.conversion.outputFolderPath = nil } else { chooseFolder() }
                    })) {
                    Text("Next to the original file").tag(true)
                    Text("In a folder I choose").tag(false)
                }
                .pickerStyle(.radioGroup)
                if let path = settings.conversion.outputFolderPath {
                    LabeledContent("Folder") {
                        HStack {
                            Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                            Button("Change…", action: chooseFolder)
                        }
                    }
                }
            }
            Section {
                Text("Lemon never changes or replaces your files. Results are new copies; if a name is taken, a number is added (“photo 2.png”).")
                Text("The first time Lemon saves into Desktop, Documents or Downloads, macOS asks for permission. Click Allow.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.conversion.outputFolderPath = url.path
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text("Lemon").font(.largeTitle.bold())
                Text("Version \(version) · Free and open source").foregroundStyle(.secondary)
                HStack {
                    Link("Source Code", destination: ProjectInfo.repositoryURL).buttonStyle(.glassProminent).tint(.lemonDeep)
                    Link("Report a Problem", destination: ProjectInfo.issuesURL).buttonStyle(.glass)
                    Link("New Versions", destination: ProjectInfo.releasesURL).buttonStyle(.glass)
                }
                Text("All conversions happen on your Mac. Lemon never goes online and collects nothing.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                GroupBox("Licences") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ThirdParty.notice).font(.caption).textSelection(.enabled)
                        HStack {
                            licenceButton("Lemon's Licence (GPL-3.0)", file: "LICENSE-GPL-3.0")
                            licenceButton("FFmpeg's Licence (LGPL-2.1)", file: "FFmpeg-LGPL-2.1")
                            Link("FFmpeg Source", destination: ProjectInfo.ffmpegSourceURL)
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    /// Opens a licence text that ships inside the app.
    private func licenceButton(_ title: String, file: String) -> some View {
        Button(title) {
            if let url = Bundle.main.url(forResource: file, withExtension: "txt") { NSWorkspace.shared.open(url) }
        }
    }
}

/// Lemon's own licence, and the credits required by the open-source parts in its media helper.
enum ThirdParty {
    static let notice = """
    Lemon is free software: you can redistribute it and/or modify it under the terms of the \
    GNU General Public License, version 3 or later. It comes with no warranty.

    Audio and video features use FFmpeg 9.0.2 (https://ffmpeg.org) under the GNU Lesser General Public \
    License (LGPL) version 2.1. Lemon's copy is built without GPL or non-free parts and runs as a separate \
    helper (Contents/Helpers/ffmpeg). The exact source and build script (scripts/build-ffmpeg.sh) are in \
    Lemon's repository. You may replace the helper with your own build.

    FFmpeg includes LAME and mpg123 (LGPL 2.1), and libvorbis, libogg, Opus, libvpx and libwebp (BSD licences).
    """
}
