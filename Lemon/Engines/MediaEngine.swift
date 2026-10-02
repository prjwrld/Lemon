import Foundation

/// A finished result waiting to be saved next to its original.
nonisolated struct Product: Sendable {
    var url: URL                // temporary file or folder
    var source: URL             // the file it was made from
    var fileExtension: String?  // nil for a folder
    var suffix: String?         // e.g. "Trimmed"
}

/// Audio and video conversions, done by FFmpeg.
nonisolated enum MediaEngine {
    static func convert(
        _ file: URL, to format: OutputFormat, settings: ConversionSettings,
        work: URL, context: JobContext
    ) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        var args = ["-i", file.path]

        switch format.kind {
        case .audio:
            guard info.hasAudio else { throw LemonError("This file has no sound to convert.") }
            args += ["-vn", "-map_metadata", "0"] + audioCodec(format, settings: settings)
        case .video where format == .gif:
            args += gifArguments(settings: settings, info: info)
        case .video:
            guard info.hasVideo else { throw LemonError("This file has no picture to convert.") }
            args += videoArguments(format, settings: settings, info: info, quality: settings.quality(for: format))
        default:
            throw LemonError("\(format.label) isn't a media format.")
        }

        try await FFmpeg.run(args + [output.path], duration: info.duration, context: context)
        return Product(url: output, source: file, fileExtension: format.fileExtension)
    }

    // MARK: Codec choices (all LGPL-friendly)

    static func audioCodec(_ format: OutputFormat, settings: ConversionSettings) -> [String] {
        let kbps = "\(settings.bitrate(for: format))k"
        switch format {
        case .mp3: return ["-c:a", "libmp3lame", "-b:a", kbps]
        case .m4a: return ["-c:a", "aac_at", "-b:a", kbps]
        case .wav: return ["-c:a", "pcm_s16le"]
        case .flac: return ["-c:a", "flac"]
        case .ogg:
            let q = ["smaller": "3", "balanced": "5", "higher": "7"][settings.quality(for: .ogg).rawValue] ?? "5"
            return ["-c:a", "libvorbis", "-q:a", q]
        case .opus: return ["-c:a", "libopus", "-b:a", kbps]
        case .aiff: return ["-c:a", "pcm_s16be"]
        case .wma: return ["-c:a", "wmav2", "-b:a", kbps]
        default: return []
        }
    }

    /// Video codec, matching sound codec, and size, for each container.
    static func videoArguments(
        _ format: OutputFormat, settings: ConversionSettings, info: FFmpeg.Info,
        quality: Quality, extraFilters: [String] = []
    ) -> [String] {
        var filters = extraFilters
        if let height = settings.videoHeight, let source = info.height, source > height {
            filters.append("scale=-2:\(height)")
        }
        // Most codecs need even width and height.
        filters.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")

        var args = ["-vf", filters.joined(separator: ","), "-map_metadata", "0"]
        switch format {
        case .mp4, .mov, .mkv:
            let q = ["smaller": "45", "balanced": "58", "higher": "70"][quality.rawValue]!
            args += ["-c:v", "h264_videotoolbox", "-q:v", q, "-allow_sw", "1", "-pix_fmt", "yuv420p"]
            args += ["-c:a", "aac_at", "-b:a", "192k"]
            if format != .mkv { args += ["-movflags", "+faststart", "-tag:v", "avc1"] }
        case .webm:
            let crf = ["smaller": "38", "balanced": "32", "higher": "26"][quality.rawValue]!
            args += ["-c:v", "libvpx-vp9", "-crf", crf, "-b:v", "0", "-row-mt", "1",
                     "-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p",
                     "-c:a", "libopus", "-b:a", "128k"]
        case .avi:
            let q = ["smaller": "8", "balanced": "5", "higher": "3"][quality.rawValue]!
            args += ["-c:v", "mpeg4", "-q:v", q, "-c:a", "libmp3lame", "-b:a", "192k"]
        case .wmv:
            let q = ["smaller": "8", "balanced": "5", "higher": "3"][quality.rawValue]!
            args += ["-c:v", "wmv2", "-q:v", q, "-c:a", "wmav2", "-b:a", "192k"]
        default:
            break
        }
        return args
    }

    /// Video → animated GIF with a custom colour palette (much better colours than the default).
    static func gifArguments(settings: ConversionSettings, info: FFmpeg.Info, extraFilters: [String] = []) -> [String] {
        let pre = (extraFilters + ["fps=\(settings.gifFPS)", "scale='min(\(settings.gifWidth),iw)':-1:flags=lanczos"])
            .joined(separator: ",")
        return ["-an", "-filter_complex", "[0:v]\(pre),split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4", "-loop", "0"]
    }

    /// The same container and codecs as the source, for tools that change a file but keep its format.
    static func sameFormat(as file: URL) -> OutputFormat? {
        OutputFormat.allCases.first { ($0.kind == .video || $0.kind == .audio) && $0.matches(file) }
    }
}
