import ImageIO
import UniformTypeIdentifiers

/// The image formats Lemon can save to. This is the one shared list of
/// choices: the wheel, the converter and (later) settings all read it.
nonisolated enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpg, heic, tiff

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var type: UTType {
        switch self {
        case .png: .png
        case .jpg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    /// Lossy formats get a quality setting.
    var isLossy: Bool { self == .jpg || self == .heic }

    /// JPG can't store see-through pixels, so we put them on white.
    var supportsTransparency: Bool { self != .jpg }

    /// The formats this Mac can actually write (HEIC needs supporting hardware).
    static var writable: [ImageFormat] {
        let ids = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return allCases.filter { ids.contains($0.type.identifier) }
    }

    /// Which of our formats a file already is, if any.
    init?(file: URL) {
        guard let type = UTType(filenameExtension: file.pathExtension) else { return nil }
        guard let match = Self.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = match
    }

    /// True if the Mac can read this file as an image.
    static func canRead(_ file: URL) -> Bool {
        guard let type = UTType(filenameExtension: file.pathExtension),
              type.conforms(to: .image) else { return false }
        let readable = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return readable.contains(type.identifier)
    }

    /// The choices to show for the dragged files. A format is left out when
    /// every file is already in it (e.g. no "JPG" slice for a single JPG).
    static func choices(for files: [URL]) -> [ImageFormat] {
        guard !files.isEmpty, files.allSatisfy(canRead) else { return [] }
        return writable.filter { format in
            files.contains { ImageFormat(file: $0) != format }
        }
    }
}
