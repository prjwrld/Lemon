import Foundation

/// Which wheel the user asked for.
nonisolated enum WheelMode: String, Sendable {
    case convert, tools
}

/// The one place that decides which choices fit the dragged files.
/// The wheel, the Compatibility settings tab and the tests all read it.
nonisolated enum ActionCatalog {
    /// Output formats for each kind of file, in clockwise wheel order (first one at the top).
    static func outputs(for kind: FileKind) -> [OutputFormat] {
        switch kind {
        case .image, .svg: [.png, .jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf, .docx]
        case .gif: [.mp4, .mov, .mkv, .webm, .avi, .wmv]
        case .video: [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]
        case .audio: [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
        case .pdf: [.docx, .jpg, .png, .txt]
        case .text: [.pdf, .jpg, .png, .srt, .vtt]
        case .subtitle: [.srt, .vtt, .txt]
        case .archive: [.zip, .tar, .gzip]
        }
    }

    /// Tools for one file, or for several files of the same kind.
    /// Order matters on crowded wheels: the cards just left and right of the top one are the
    /// narrowest, so they get short names (the engine tests check every name fits).
    static func tools(for kind: FileKind, multiple: Bool) -> [Tool] {
        switch (kind, multiple) {
        case (.image, false): [.compress, .metadata, .editPhoto, .annotate, .background, .crop, .redact, .readQR]
        case (.image, true), (.svg, true): [.compress, .crop, .createPDF, .collage]
        case (.svg, false): [.createPDF]
        case (.gif, false): [.trim, .crop, .speed, .compress]
        case (.gif, true): [.compress]
        case (.video, false): [.trim, .crop, .speed, .snapshots, .split, .redact, .compress, .metadata, .mute]
        case (.video, true): [.join, .mute, .compress]
        case (.audio, false): [.trim, .normalize, .visualizer, .channels, .bleep, .compress, .metadata]
        case (.audio, true): [.join, .normalize, .compress]
        case (.pdf, false): [.organize, .splitPages, .compress, .metadata]
        case (.pdf, true): [.merge, .compress]
        case (.archive, _): [.extract]
        case (.text, _), (.subtitle, _): []
        }
    }

    /// The kind shared by all the files, if they can be handled together.
    /// Pictures and SVGs count as one group.
    static func commonKind(of files: [URL]) -> FileKind? {
        let kinds = files.map(FileKind.init(file:))
        guard !kinds.isEmpty, !kinds.contains(where: { $0 == nil }) else { return nil }
        let set = Set(kinds.compactMap { $0 })
        if set.count == 1 { return set.first }
        if set.isSubset(of: [.image, .svg]) { return .image }
        return nil
    }

    static func actions(for files: [URL], mode: WheelMode) -> [Action] {
        guard let kind = commonKind(of: files) else { return [] }
        switch mode {
        case .convert:
            return outputs(for: kind)
                .filter { format in
                    // Word documents are made from JPG/PNG pictures only (as in the public format list).
                    if kind == .image || kind == .svg, format == .docx {
                        return files.allSatisfy { OutputFormat.jpg.matches($0) || OutputFormat.png.matches($0) }
                    }
                    return true
                }
                // Leave out a format only when every file is already in it.
                .filter { format in files.contains { !format.matches($0) } }
                .map(Action.convert)
        case .tools:
            return tools(for: kind, multiple: files.count > 1).map(Action.tool)
        }
    }
}
