import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What kind of file something is. Decides which formats and tools the wheel offers.
nonisolated enum FileKind: String, Sendable, CaseIterable {
    case image, svg, gif, video, audio, pdf, text, subtitle, archive

    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "mts"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aif", "aiff", "aifc", "wma", "aac", "caf"]
    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "tbz", "tbz2", "xz", "txz"]
    static let subtitleExtensions: Set<String> = ["srt", "vtt"]
    static let textExtensions: Set<String> = ["txt", "text"]

    init?(file: URL) {
        guard !file.hasDirectoryPath else { return nil }
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "gif": self = .gif
        case "svg": self = .svg
        case "pdf": self = .pdf
        case _ where Self.subtitleExtensions.contains(ext): self = .subtitle
        case _ where Self.textExtensions.contains(ext): self = .text
        case _ where Self.videoExtensions.contains(ext): self = .video
        case _ where Self.audioExtensions.contains(ext): self = .audio
        case _ where Self.archiveExtensions.contains(ext): self = .archive
        case _ where Self.isReadableImage(ext): self = .image
        default: return nil
        }
    }

    /// True if ImageIO can read this kind of picture (JPG, PNG, HEIC, WebP, AVIF, TIFF, BMP…).
    static func isReadableImage(_ ext: String) -> Bool {
        guard let type = UTType(filenameExtension: ext), type.conforms(to: .image) else { return false }
        return readableImageTypes.contains(type.identifier)
    }

    private static let readableImageTypes: Set<String> =
        Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])

    var label: String {
        switch self {
        case .image: "image"
        case .svg: "SVG"
        case .gif: "GIF"
        case .video: "video"
        case .audio: "audio"
        case .pdf: "PDF"
        case .text: "text"
        case .subtitle: "subtitle"
        case .archive: "archive"
        }
    }
}
