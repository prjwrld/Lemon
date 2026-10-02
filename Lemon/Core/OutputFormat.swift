import Foundation

/// Every format Lemon can save to.
nonisolated enum OutputFormat: String, CaseIterable, Sendable, Codable {
    // Images (and documents made from images)
    case png, jpg, webp, heic, tiff, avif, bmp, pdf, docx
    // Audio
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma
    // Video
    case mp4, mov, mkv, webm, avi, wmv, gif
    // Text and subtitles
    case txt, srt, vtt
    // Archives
    case zip, tar, gzip

    var label: String { self == .gzip ? "GZIP" : rawValue.uppercased() }

    var fileExtension: String { self == .gzip ? "tar.gz" : rawValue }

    /// Other spellings of the same format, so "photo.jpeg" counts as JPG.
    private var aliases: Set<String> {
        switch self {
        case .jpg: ["jpg", "jpeg", "jpe"]
        case .tiff: ["tiff", "tif"]
        case .heic: ["heic", "heif"]
        case .aiff: ["aiff", "aif", "aifc"]
        case .ogg: ["ogg", "oga"]
        case .mp4: ["mp4", "m4v"]
        case .gzip: ["gz", "tgz"]
        default: [rawValue]
        }
    }

    /// True if this file is already in this format.
    func matches(_ file: URL) -> Bool {
        aliases.contains(file.pathExtension.lowercased())
    }

    var kind: Kind {
        switch self {
        case .png, .jpg, .webp, .heic, .tiff, .avif, .bmp: .image
        case .pdf, .docx, .txt: .document
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma: .audio
        case .mp4, .mov, .mkv, .webm, .avi, .wmv, .gif: .video
        case .srt, .vtt: .subtitle
        case .zip, .tar, .gzip: .archive
        }
    }

    enum Kind: String { case image, document, audio, video, subtitle, archive }
}
