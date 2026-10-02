import AppKit
import Observation

/// Quality choices used by several formats.
nonisolated enum Quality: String, CaseIterable, Codable, Sendable, Identifiable {
    case smaller, balanced, higher
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smaller: "Smaller File"
        case .balanced: "Balanced"
        case .higher: "Higher Quality"
        }
    }
    /// 0…1 quality for JPG, HEIC, AVIF and WebP.
    var imageQuality: Double {
        switch self {
        case .smaller: 0.6
        case .balanced: 0.8
        case .higher: 0.92
        }
    }
}

/// How hard the Compress tool squeezes.
nonisolated enum Strength: String, CaseIterable, Codable, Sendable, Identifiable {
    case balanced, strong
    var id: String { rawValue }
    var label: String { self == .balanced ? "Balanced" : "Strong" }
}

/// The key combination held while dragging.
nonisolated enum DragShortcut: String, CaseIterable, Codable, Sendable, Identifiable {
    case shift, option, control, optionShift, controlShift, controlOption
    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: [.shift]
        case .option: [.option]
        case .control: [.control]
        case .optionShift: [.option, .shift]
        case .controlShift: [.control, .shift]
        case .controlOption: [.control, .option]
        }
    }

    var label: String {
        switch self {
        case .shift: "⇧ Shift"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .optionShift: "⌥ Option + ⇧ Shift"
        case .controlShift: "⌃ Control + ⇧ Shift"
        case .controlOption: "⌃ Control + ⌥ Option"
        }
    }

    /// True if exactly these keys are held (Command and Caps Lock are ignored).
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.shift, .option, .control]) == self.flags
    }
}

/// Everything the converters need to know. A plain value, so it can be handed to
/// background work safely; saved as JSON in UserDefaults.
nonisolated struct ConversionSettings: Codable, Sendable, Equatable {
    var quality: [OutputFormat: Quality] = [:]
    var keepMetadata = true
    /// Longest side for converted pictures, or nil to keep the original size.
    var maxImageSize: Int?
    var compression: Strength = .balanced
    /// Video height (e.g. 1080), or nil to keep the original.
    var videoHeight: Int?
    var audioBitrate: [OutputFormat: Int] = [.mp3: 256, .m4a: 256, .opus: 160, .wma: 192]
    var gifFPS = 12
    var gifWidth = 640
    var pdfDPI = 300
    /// Save results here instead of next to the original.
    var outputFolderPath: String?

    func quality(for format: OutputFormat) -> Quality { quality[format] ?? .balanced }
    func bitrate(for format: OutputFormat) -> Int { audioBitrate[format] ?? 192 }
    var outputFolder: URL? { outputFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }
}

/// The app's saved preferences.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Appearance: String, CaseIterable, Identifiable {
        case glass, solid
        var id: String { rawValue }
        var label: String { self == .glass ? "Glass" : "Solid" }
    }

    var conversion: ConversionSettings { didSet { save(conversion, "conversion") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var feedback: Bool { didSet { defaults.set(feedback, forKey: "feedback") } }
    var convertShortcut: DragShortcut { didSet { defaults.set(convertShortcut.rawValue, forKey: "convertShortcut") } }
    var toolsShortcut: DragShortcut { didSet { defaults.set(toolsShortcut.rawValue, forKey: "toolsShortcut") } }
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }

    private let defaults = UserDefaults.standard

    private init() {
        conversion = defaults.data(forKey: "conversion")
            .flatMap { try? JSONDecoder().decode(ConversionSettings.self, from: $0) } ?? ConversionSettings()
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .glass
        feedback = defaults.object(forKey: "feedback") as? Bool ?? true
        convertShortcut = defaults.string(forKey: "convertShortcut").flatMap(DragShortcut.init) ?? .shift
        toolsShortcut = defaults.string(forKey: "toolsShortcut").flatMap(DragShortcut.init) ?? .optionShift
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
