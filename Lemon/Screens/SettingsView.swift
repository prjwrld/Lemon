import AppKit
import ServiceManagement
import SwiftUI

/// Opens the Settings window (one at a time).
enum SettingsWindow {
    private static var window: NSWindow?
    private static let selection = SettingsSelection()

    static func show(tab: SettingsView.Tab = .general) {
        selection.tab = tab
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Lemon Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 460)
        let hostingView = NSHostingView(rootView: SettingsView(selection: selection))
        // Only the minimum size comes from SwiftUI, so long pages scroll instead of growing the window.
        hostingView.sizingOptions = [.minSize]
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 800, height: 580))
        window.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsWindow.window = nil }
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Which page Settings shows, so `SettingsWindow.show(tab:)` can switch it while open.
@Observable
final class SettingsSelection {
    var tab: SettingsView.Tab? = .general
}

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general, shortcuts, formats, saving, supported, licence, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .formats: "Quality & Size"
            case .saving: "Saving"
            case .supported: "File Types"
            case .licence: "Licence"
            case .about: "About"
            }
        }

        var subtitle: String {
            switch self {
            case .general: "How Lemon starts, sounds, looks and updates."
            case .shortcuts: "The keys you hold while dragging files to open a wheel."
            case .formats: "How good the files Lemon makes should look and sound, and how big they can be."
            case .saving: "Where Lemon puts the new files it makes."
            case .supported: "Every kind of file Lemon understands, and what it can do with each."
            case .licence: "Your free uses, buying Lemon, and your licence key."
            case .about: "Version, help and acknowledgements."
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .shortcuts: "keyboard.fill"
            case .formats: "slider.horizontal.3"
            case .saving: "folder.fill"
            case .supported: "doc.on.doc.fill"
            case .licence: "key.fill"
            case .about: "info"
            }
        }

        var color: Color {
            switch self {
            case .general: .gray
            case .shortcuts: .indigo
            case .formats: .orange
            case .saving: .blue
            case .supported: .teal
            case .licence: .lemonDeep
            case .about: .secondary
            }
        }
    }

    @Bindable var selection: SettingsSelection

    var body: some View {
        // A plain sidebar next to the page. (NavigationSplitView adds its own window toolbar,
        // which shifted the pages under the title bar when the window became active.)
        HStack(spacing: 0) {
            List(Tab.allCases, selection: $selection.tab) { tab in
                Label { Text(tab.title) } icon: { SettingsIcon(symbol: tab.symbol, color: tab.color) }
                    .padding(.vertical, 2)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .safeAreaInset(edge: .bottom) { LicenceBadge { selection.tab = .licence } }
            .frame(width: 210)
            .background(.background.secondary)
            Divider()
            Group {
                switch selection.tab ?? .general {
                case .general: GeneralPage()
                case .shortcuts: ShortcutsPage()
                case .formats: FormatsPage()
                case .saving: SavingPage()
                case .supported: SupportedFilesPage()
                case .licence: LicencePage()
                case .about: AboutPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .tint(.lemonDeep)
        .frame(minWidth: 680, minHeight: 460)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @State private var settings = AppSettings.shared
    @State private var updates = Updates.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsPage(tab: .general) {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Open Lemon when you log in")
                    Text("Recommended. Lemon has to be running for the wheel to appear.")
                }
                .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle(isOn: $settings.feedback) {
                    Text("Sound and trackpad feedback")
                    Text("A gentle tap on the trackpad when you move over a choice, and a sound when a file is ready.")
                }
            }
            Section("Wheel look") {
                HStack(spacing: 20) {
                    ForEach(AppSettings.Appearance.allCases) { look in
                        ChoiceCard(title: look.label, isSelected: settings.appearance == look) {
                            settings.appearance = look
                        } preview: { WheelLookPreview(appearance: look) }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            if updates.isAvailable {
                Section("Updates") {
                    Toggle(isOn: $updates.automatic) {
                        Text("Install updates automatically")
                        Text("Lemon checks once a day and installs new versions when it quits.")
                    }
                    LabeledContent {
                        Button("Check Now") { updates.checkNow() }
                    } label: {
                        Text("Lemon \(updates.version)")
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Show Tour") { WelcomeWindow.show() }
                } label: {
                    Text("Welcome tour")
                    Text("A two-minute walk through Lemon with a practice photo.")
                }
            }
        }
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

// MARK: - Shortcuts

private struct ShortcutsPage: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPage(tab: .shortcuts) {
            Section {
                HStack(alignment: .top, spacing: 0) {
                    step(1, "Start dragging files", "in Finder, on the desktop or in any app")
                    step(2, "Hold the keys", "a wheel appears under the pointer")
                    step(3, "Drop on a choice", "Lemon saves a new copy")
                }
                .padding(.vertical, 6)
            } header: {
                Text("How it works")
            }
            shortcutSection("Formats wheel", "Converts files: PNG, MP4, MP3, PDF and more.",
                             selection: $settings.convertShortcut)
            shortcutSection("Tools wheel", "Edits files: crop, compress, trim, redact and more.",
                             selection: $settings.toolsShortcut)
            if settings.convertShortcut == settings.toolsShortcut {
                Section {
                    Label("Both wheels use the same keys. Choose different keys for one of them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Text("Let go of the keys and the wheel closes without doing anything.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutSection(_ title: String, _ detail: String, selection: Binding<DragShortcut>) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                KeyCaps(shortcut: selection.wrappedValue)
            }
            Picker("Keys to hold", selection: selection) {
                ForEach(DragShortcut.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text("\(number)")
                .font(.callout.bold()).foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Color.lemon, in: .circle)
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quality & Size

private struct FormatsPage: View {
    @State private var settings = AppSettings.shared

    private static let pictureFormats: [OutputFormat] = [.jpg, .heic, .webp, .avif]
    private static let videoFormats: [OutputFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv]

    var body: some View {
        SettingsPage(tab: .formats) {
            Section {
                qualityPicker("Quality", formats: Self.pictureFormats)
                Picker("Largest size", selection: $settings.conversion.maxImageSize) {
                    Text("Keep original size").tag(Int?.none)
                    ForEach([3840, 2560, 1920, 1280], id: \.self) { Text("\($0) px on the longest side").tag(Int?.some($0)) }
                }
                Toggle(isOn: $settings.conversion.keepMetadata) {
                    Text("Keep photo details")
                    Text("Camera, location and date taken.")
                }
                Picker("PDF pages turned into pictures", selection: $settings.conversion.pdfDPI) {
                    Text("Standard (150 dpi)").tag(150); Text("Sharp (300 dpi)").tag(300)
                }
                perFormat(Self.pictureFormats)
            } header: {
                sectionHeader("Pictures", "photo")
            } footer: {
                footer("Quality applies to JPG, HEIC, WebP and AVIF. PNG, TIFF and BMP are always lossless.")
            }

            Section {
                qualityPicker("Quality", formats: Self.videoFormats)
                Picker("Largest size", selection: $settings.conversion.videoHeight) {
                    Text("Keep original size").tag(Int?.none)
                    ForEach([2160, 1080, 720, 480], id: \.self) { Text("\($0)p").tag(Int?.some($0)) }
                }
                perFormat(Self.videoFormats)
            } header: {
                sectionHeader("Video", "film")
            } footer: {
                footer("Videos are never made bigger than the original.")
            }

            Section {
                Stepper("Frames per second: \(settings.conversion.gifFPS)", value: $settings.conversion.gifFPS, in: 5...30)
                Picker("Width", selection: $settings.conversion.gifWidth) {
                    ForEach([320, 480, 640, 800, 1080], id: \.self) { Text("Up to \($0) px").tag($0) }
                }
            } header: {
                sectionHeader("GIF", "play.square.stack")
            } footer: {
                footer("Fewer frames and a smaller width make lighter GIFs.")
            }

            Section {
                bitratePicker(.mp3)
                bitratePicker(.m4a)
                bitratePicker(.opus)
                bitratePicker(.wma)
                Picker("OGG quality", selection: quality(.ogg)) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                sectionHeader("Audio", "waveform")
            } footer: {
                footer("Higher bitrates sound better and make bigger files. WAV, FLAC and AIFF are always lossless.")
            }

            Section {
                Picker("Strength", selection: $settings.conversion.compression) {
                    ForEach(Strength.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                sectionHeader("Compress tool", "arrow.down.right.and.arrow.up.left")
            } footer: {
                footer("Strong makes much smaller files and may lower quality you can see.")
            }
        }
    }

    /// One picker that sets the quality for all the given formats at once.
    private func qualityPicker(_ title: String, formats: [OutputFormat]) -> some View {
        let binding = Binding<Quality>(
            get: { settings.conversion.quality(for: formats[0]) },
            set: { value in formats.forEach { settings.conversion.quality[$0] = value } })
        return Picker(title, selection: binding) {
            ForEach(Quality.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// For people who want a different quality for one format.
    private func perFormat(_ formats: [OutputFormat]) -> some View {
        DisclosureGroup("Different quality for each format") {
            ForEach(formats, id: \.self) { format in
                Picker(format.label, selection: quality(format)) {
                    ForEach(Quality.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    private func quality(_ format: OutputFormat) -> Binding<Quality> {
        Binding(get: { settings.conversion.quality(for: format) }, set: { settings.conversion.quality[format] = $0 })
    }

    private func bitratePicker(_ format: OutputFormat) -> some View {
        Picker("\(format.label) bitrate", selection: Binding(
            get: { settings.conversion.bitrate(for: format) },
            set: { settings.conversion.audioBitrate[format] = $0 })) {
            ForEach([64, 96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
        }
    }

    private func sectionHeader(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Saving

private struct SavingPage: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPage(tab: .saving) {
            Section {
                Picker("Save new files", selection: Binding(
                    get: { settings.conversion.outputFolderPath == nil },
                    set: { nextToOriginal in
                        if nextToOriginal { settings.conversion.outputFolderPath = nil } else { chooseFolder() }
                    })) {
                    Text("Next to the original file").tag(true)
                    Text("In a folder I choose").tag(false)
                }
                .pickerStyle(.radioGroup)
                if let path = settings.conversion.outputFolderPath {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent).font(.callout.weight(.medium))
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        Button("Change…", action: chooseFolder)
                    }
                }
            }
            Section("Good to know") {
                note("lock.doc.fill", .green, "Your originals are never changed or replaced. Every result is a new copy.")
                note("number", .blue, "If a name is taken, Lemon adds a number: “photo 2.png”.")
                note("hand.raised.fill", .orange, "The first time Lemon saves into Desktop, Documents or Downloads, macOS asks for permission. Click Allow.")
            }
        }
    }

    private func note(_ symbol: String, _ color: Color, _ text: String) -> some View {
        Label { Text(text).font(.callout) } icon: { Image(systemName: symbol).foregroundStyle(color) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Lemon saves the files it makes."
        if panel.runModal() == .OK, let url = panel.url {
            settings.conversion.outputFolderPath = url.path
        }
    }
}

// MARK: - Supported Files

private struct SupportedFilesPage: View {
    private let rows: [(kind: FileKind, name: String, symbol: String, inputs: String)] = [
        (.image, "Pictures", "photo", "JPG, PNG, HEIC, WebP, AVIF, TIFF, BMP"),
        (.svg, "Vector drawings", "scribble.variable", "SVG"),
        (.gif, "Animated GIFs", "play.square.stack", "GIF"),
        (.video, "Video", "film", "MP4, MOV, MKV, WebM, AVI, WMV, M4V…"),
        (.audio, "Audio", "waveform", "MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA"),
        (.pdf, "PDF documents", "doc.richtext", "PDF"),
        (.text, "Text", "doc.plaintext", "TXT"),
        (.subtitle, "Subtitles", "captions.bubble", "SRT, VTT"),
        (.archive, "Archives", "archivebox", "ZIP, TAR, GZIP, RAR, 7Z"),
    ]

    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPage(tab: .supported) {
            ForEach(rows, id: \.kind) { row in
                Section {
                    line("Convert to", keys: settings.convertShortcut,
                         ActionCatalog.outputs(for: row.kind).filter { row.kind != .svg || $0 != .docx }.map(\.label))
                    let one = ActionCatalog.tools(for: row.kind, multiple: false).map(\.label)
                    let many = ActionCatalog.tools(for: row.kind, multiple: true).map(\.label)
                    if !one.isEmpty { line("Tools", keys: settings.toolsShortcut, one) }
                    if !many.isEmpty { line("Tools for several files", keys: settings.toolsShortcut, many) }
                } header: {
                    HStack {
                        Label(row.name, systemImage: row.symbol)
                        Spacer()
                        Text(row.inputs).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("Word (DOCX) is offered for JPG and PNG pictures and for PDFs. Lemon can open RAR files but not create them (RAR needs a licence from its owner).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func line(_ title: String, keys: DragShortcut, _ items: [String]) -> some View {
        LabeledContent {
            Text(items.joined(separator: " · ")).multilineTextAlignment(.trailing)
        } label: {
            Text(title)
            Text(keys.label)
        }
    }
}

// MARK: - Licence

private struct LicencePage: View {
    var body: some View {
        SettingsPage(tab: .licence) {
            Section {
                LicencePanel().padding(.vertical, 8)
            }
            Section {
                HStack(spacing: 16) {
                    Link("Privacy", destination: StoreConfig.privacyURL)
                    Link("Terms", destination: StoreConfig.termsURL)
                    Link("Refunds", destination: StoreConfig.refundsURL)
                    Link("Contact Support", destination: StoreConfig.supportURL)
                }
                .font(.callout)
            } footer: {
                Text("Lemon goes online only to activate or check your licence key. Your files never leave your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                    Text("Lemon").font(.largeTitle.bold())
                    Text(version).foregroundStyle(.secondary)
                    Text("Convert and edit files by dragging them.").font(.callout)
                }
                HStack {
                    Link(destination: StoreConfig.websiteURL) { Label("Website", systemImage: "safari") }
                    Link(destination: StoreConfig.supportURL) { Label("Contact Support", systemImage: "envelope") }
                    if Updates.shared.isAvailable {
                        Button { Updates.shared.checkNow() } label: { Label("Check for Updates", systemImage: "arrow.down.circle") }
                    }
                }
                .buttonStyle(.glass)
                Label("Your files never leave your Mac. Lemon goes online only to check your licence key.",
                      systemImage: "lock.shield.fill")
                    .font(.callout).foregroundStyle(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ThirdParty.notice).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("FFmpeg's Licence (LGPL 2.1)") {
                                if let url = Bundle.main.url(forResource: "FFmpeg-LGPL-2.1", withExtension: "txt") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Link("FFmpeg Source", destination: StoreConfig.ffmpegSourceURL)
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Text("Acknowledgements").font(.headline)
                }
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Credits required by the open-source parts in Lemon's media helper.
enum ThirdParty {
    static let notice = """
    Audio and video features use FFmpeg 9.0.2 (https://ffmpeg.org) under the GNU Lesser General Public \
    License (LGPL) version 2.1. Lemon's copy is built without GPL or non-free parts and runs as a separate \
    program (Contents/Helpers/ffmpeg) that you may replace with your own build. Its exact source is linked \
    below; the build settings are available from support.

    FFmpeg includes LAME and mpg123 (LGPL 2.1), and libvorbis, libogg, Opus, libvpx and libwebp (BSD licences).
    """
}
