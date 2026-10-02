import CoreGraphics
import Foundation

/// Video, audio and GIF tools, done with FFmpeg filters.
nonisolated enum MediaTools {
    /// How a tool's result is written: same container as the source when Lemon can write it.
    private struct Target {
        var format: OutputFormat
        var isGIF: Bool { format == .gif }
        var isAudioOnly: Bool { format.kind == .audio }
    }

    private static func target(for file: URL, info: FFmpeg.Info) -> Target {
        if FileKind(file: file) == .gif { return Target(format: .gif) }
        if let same = MediaEngine.sameFormat(as: file) { return Target(format: same) }
        return Target(format: info.hasVideo ? .mp4 : .m4a)
    }

    /// Encoding arguments for a target, with optional extra video filters (crop, speed…).
    private static func encode(_ target: Target, info: FFmpeg.Info, settings: ConversionSettings,
                               quality: Quality? = nil, videoFilters: [String] = []) -> [String] {
        if target.isGIF { return MediaEngine.gifArguments(settings: settings, info: info, extraFilters: videoFilters) }
        if target.isAudioOnly { return ["-vn"] + MediaEngine.audioCodec(target.format, settings: settings) }
        return MediaEngine.videoArguments(target.format, settings: settings, info: info,
                                          quality: quality ?? settings.quality(for: target.format), extraFilters: videoFilters)
    }

    private static func output(_ work: URL, _ target: Target, _ name: String = "out") -> URL {
        work.appendingPathComponent("\(name).\(target.format.fileExtension)")
    }

    // MARK: Trim and split

    static func trim(_ file: URL, _ range: TimeRange, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let target = target(for: file, info: info)
        let out = output(work, target)
        try await FFmpeg.run(["-ss", FFmpeg.time(range.start), "-i", file.path, "-t", FFmpeg.time(range.length)]
                             + encode(target, info: info, settings: settings) + [out.path],
                             duration: range.length, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Trimmed")
    }

    static func split(_ file: URL, at points: [Double], settings: ConversionSettings, work: URL, context: JobContext) async throws -> [Product] {
        let info = try await FFmpeg.probe(file)
        guard let duration = info.duration else { throw LemonError("The length of this file couldn't be read.") }
        let cuts = ([0] + points.filter { $0 > 0.1 && $0 < duration - 0.1 }.sorted() + [duration])
        guard cuts.count > 2 else { throw LemonError("Choose where to split, away from the very start and end.") }
        let target = target(for: file, info: info)
        var products: [Product] = []
        for index in 0..<(cuts.count - 1) {
            try context.checkCancelled()
            let range = TimeRange(start: cuts[index], end: cuts[index + 1])
            let out = output(work, target, "part\(index + 1)")
            try await FFmpeg.run(["-ss", FFmpeg.time(range.start), "-i", file.path, "-t", FFmpeg.time(range.length)]
                                 + encode(target, info: info, settings: settings) + [out.path],
                                 duration: nil, context: nil)
            context.report(Double(index + 1) / Double(cuts.count - 1))
            products.append(Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Part \(index + 1)"))
        }
        return products
    }

    // MARK: Picture changes

    static func crop(_ file: URL, to rect: CGRect, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        guard let width = info.width, let height = info.height else { throw LemonError("The picture size couldn't be read.") }
        let r = evenPixels(rect, width: width, height: height)
        let target = target(for: file, info: info)
        let out = output(work, target)
        try await FFmpeg.run(["-i", file.path] + encode(target, info: info, settings: settings,
                             videoFilters: ["crop=\(Int(r.width)):\(Int(r.height)):\(Int(r.minX)):\(Int(r.minY))"]) + [out.path],
                             duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Cropped")
    }

    static func redact(_ file: URL, _ rects: [CGRect], style: RedactStyle, settings: ConversionSettings,
                       work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        guard let width = info.width, let height = info.height else { throw LemonError("The picture size couldn't be read.") }
        let target = target(for: file, info: info)
        let out = output(work, target)

        // Build a filter graph: each area is covered, blurred or pixelated, then laid back on top.
        var graph: [String] = []
        var current = "[0:v]"
        for (index, rect) in rects.enumerated() {
            let r = evenPixels(rect, width: width, height: height)
            let (w, h, x, y) = (Int(r.width), Int(r.height), Int(r.minX), Int(r.minY))
            guard w > 1, h > 1 else { continue }
            let next = "[v\(index)]"
            switch style {
            case .black:
                graph.append("\(current)drawbox=x=\(x):y=\(y):w=\(w):h=\(h):color=black:t=fill\(next)")
            case .blur, .pixelate:
                let effect = style == .blur
                    ? "gblur=sigma=\(max(w, h) / 6)"
                    : "scale=max(1\\,iw/\(max(2, w / 12))):max(1\\,ih/\(max(2, h / 12))):flags=neighbor,scale=\(w):\(h):flags=neighbor"
                graph.append("\(current)split[base\(index)][src\(index)]")
                graph.append("[src\(index)]crop=\(w):\(h):\(x):\(y),\(effect)[patch\(index)]")
                graph.append("[base\(index)][patch\(index)]overlay=\(x):\(y)\(next)")
            }
            current = next
        }
        guard !graph.isEmpty else { throw LemonError("Draw at least one area to hide.") }
        graph.append("\(current)scale=trunc(iw/2)*2:trunc(ih/2)*2[vout]")

        var args = ["-i", file.path, "-filter_complex", graph.joined(separator: ";"), "-map", "[vout]", "-map", "0:a?"]
        // The encoder settings without their own "-vf" (the graph already did the filtering).
        var enc = encode(target, info: info, settings: settings)
        if let vf = enc.firstIndex(of: "-vf") { enc.removeSubrange(vf...(vf + 1)) }
        args += enc + [out.path]
        try await FFmpeg.run(args, duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Redacted")
    }

    /// 0…1 rectangle → even pixel values (video codecs need even sizes).
    private static func evenPixels(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        func even(_ v: CGFloat) -> CGFloat { CGFloat(Int(v) / 2 * 2) }
        let x = even(rect.minX * CGFloat(width)), y = even(rect.minY * CGFloat(height))
        let w = even(min(rect.width * CGFloat(width), CGFloat(width) - x))
        let h = even(min(rect.height * CGFloat(height), CGFloat(height) - y))
        return CGRect(x: x, y: y, width: max(2, w), height: max(2, h))
    }

    // MARK: Speed, mute, snapshots

    static func speed(_ file: URL, factor: Double, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let target = target(for: file, info: info)
        let out = output(work, target)
        var args = ["-i", file.path]
        let label = factor == factor.rounded() ? String(Int(factor)) : String(factor)
        if target.isGIF || (info.hasVideo && !info.hasAudio) {
            args += encode(target, info: info, settings: settings, videoFilters: ["setpts=PTS/\(factor)"])
        } else if target.isAudioOnly {
            args += ["-filter:a", atempo(factor)] + encode(target, info: info, settings: settings)
        } else {
            var enc = encode(target, info: info, settings: settings, videoFilters: ["setpts=PTS/\(factor)"])
            if let vf = enc.firstIndex(of: "-vf") {
                let filters = enc[vf + 1]
                enc.removeSubrange(vf...(vf + 1))
                args += ["-filter_complex", "[0:v]\(filters)[v];[0:a]\(atempo(factor))[a]", "-map", "[v]", "-map", "[a]"] + enc
            }
        }
        try await FFmpeg.run(args + [out.path], duration: info.duration.map { $0 / factor }, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Speed \(label)x")
    }

    /// atempo only accepts 0.5…2, so bigger changes are chained (e.g. 4× = 2×·2×).
    private static func atempo(_ factor: Double) -> String {
        var remaining = factor, parts: [String] = []
        while remaining > 2 { parts.append("atempo=2"); remaining /= 2 }
        while remaining < 0.5 { parts.append("atempo=0.5"); remaining /= 0.5 }
        parts.append("atempo=\(remaining)")
        return parts.joined(separator: ",")
    }

    static func mute(_ file: URL, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        guard info.hasAudio else { throw LemonError("\(file.lastPathComponent) already has no sound.") }
        let ext = MediaEngine.sameFormat(as: file)?.fileExtension ?? "mp4"
        let out = work.appendingPathComponent("out.\(ext)")
        try await FFmpeg.run(["-i", file.path, "-map", "0:v", "-c", "copy", "-an", out.path], duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: ext, suffix: "Muted")
    }

    static func snapshots(_ file: URL, count: Int, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        guard let duration = info.duration, duration > 0 else { throw LemonError("The length of this video couldn't be read.") }
        let folder = work.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await FFmpeg.run(["-i", file.path, "-vf", "fps=\(count)/\(duration)", "-frames:v", "\(count)", "-q:v", "2",
                              folder.appendingPathComponent("Snapshot %02d.jpg").path],
                             duration: duration, context: context)
        return Product(url: folder, source: file, fileExtension: nil, suffix: "Snapshots")
    }

    // MARK: Join

    static func join(_ files: [URL], settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        var infos: [FFmpeg.Info] = []
        for file in files { infos.append(try await FFmpeg.probe(file)) }
        let first = infos[0]
        let target = target(for: files[0], info: first)
        let out = output(work, target)
        let total = infos.compactMap(\.duration).reduce(0, +)
        var args: [String] = files.flatMap { ["-i", $0.path] }

        if target.isAudioOnly || !first.hasVideo {
            let inputs = files.indices.map { "[\($0):a]aresample=44100,aformat=channel_layouts=stereo[a\($0)]" }
            let chain = files.indices.map { "[a\($0)]" }.joined()
            args += ["-filter_complex", (inputs + ["\(chain)concat=n=\(files.count):v=0:a=1[a]"]).joined(separator: ";"),
                     "-map", "[a]"] + MediaEngine.audioCodec(target.format, settings: settings)
        } else {
            // Every clip is fitted to the first clip's size, and given silence if it has no sound.
            let w = (first.width ?? 1280) / 2 * 2, h = (first.height ?? 720) / 2 * 2
            let withAudio = infos.allSatisfy(\.hasAudio)
            var parts: [String] = []
            for index in files.indices {
                parts.append("[\(index):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(index)]")
                if withAudio { parts.append("[\(index):a]aresample=48000,aformat=channel_layouts=stereo[a\(index)]") }
            }
            let chain = files.indices.map { withAudio ? "[v\($0)][a\($0)]" : "[v\($0)]" }.joined()
            parts.append("\(chain)concat=n=\(files.count):v=1:a=\(withAudio ? 1 : 0)\(withAudio ? "[v][a]" : "[v]")")
            args += ["-filter_complex", parts.joined(separator: ";"), "-map", "[v]"] + (withAudio ? ["-map", "[a]"] : [])
            var enc = encode(target, info: first, settings: settings)
            if let vf = enc.firstIndex(of: "-vf") { enc.removeSubrange(vf...(vf + 1)) }
            args += enc
        }
        try await FFmpeg.run(args + [out.path], duration: total, context: context)
        return Product(url: out, source: files[0], fileExtension: target.format.fileExtension, suffix: "Joined")
    }

    // MARK: Audio

    static func normalize(_ file: URL, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        guard info.hasAudio else { throw LemonError("\(file.lastPathComponent) has no sound.") }
        let target = target(for: file, info: info)
        let out = output(work, target)
        var args = ["-i", file.path]
        if info.hasVideo && !target.isAudioOnly {
            args += ["-c:v", "copy", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac_at", "-b:a", "192k"]
        } else {
            args += ["-vn", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000"] + MediaEngine.audioCodec(target.format, settings: settings)
        }
        try await FFmpeg.run(args + [out.path], duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Normalized")
    }

    static func channels(_ file: URL, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let toStereo = (info.audioChannels ?? 2) == 1
        let target = target(for: file, info: info)
        let out = output(work, target)
        try await FFmpeg.run(["-i", file.path, "-vn", "-ac", toStereo ? "2" : "1"] + MediaEngine.audioCodec(target.format, settings: settings) + [out.path],
                             duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: toStereo ? "Stereo" : "Mono")
    }

    /// A video of the sound's waveform, in Lemon yellow on black.
    static func visualizer(_ file: URL, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let out = work.appendingPathComponent("out.mp4")
        try await FFmpeg.run(
            ["-i", file.path, "-filter_complex",
             "[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0xFFDB1F|0xFAB30D:scale=sqrt,format=yuv420p[v]",
             "-map", "[v]", "-map", "0:a", "-c:v", "h264_videotoolbox", "-q:v", "60", "-allow_sw", "1",
             "-c:a", "aac_at", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out.path],
            duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: "mp4", suffix: "Visualizer")
    }

    /// Silences the chosen moments and plays a 1 kHz beep over them.
    static func bleep(_ file: URL, _ ranges: [TimeRange], settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        guard !ranges.isEmpty else { throw LemonError("Mark at least one moment to bleep.") }
        let info = try await FFmpeg.probe(file)
        let target = target(for: file, info: info)
        let out = output(work, target)
        let when = ranges.map { "between(t\\,\(FFmpeg.time($0.start))\\,\(FFmpeg.time($0.end)))" }.joined(separator: "+")
        let duration = FFmpeg.time(info.duration ?? (ranges.map(\.end).max() ?? 0) + 1)
        let graph = "[0:a]volume=0:enable='\(when)'[quiet];"
            + "sine=frequency=1000:sample_rate=48000:duration=\(duration),volume=0.3,volume=0:enable='not(\(when))'[beep];"
            + "[quiet][beep]amix=inputs=2:duration=first:normalize=0[a]"
        var args = ["-i", file.path, "-filter_complex", graph, "-map", "[a]"]
        if info.hasVideo && !target.isAudioOnly {
            args += ["-map", "0:v", "-c:v", "copy", "-c:a", "aac_at", "-b:a", "192k"]
        } else {
            args += MediaEngine.audioCodec(target.format, settings: settings)
        }
        try await FFmpeg.run(args + [out.path], duration: info.duration, context: context)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Bleeped")
    }

    // MARK: Compress and metadata

    static func compress(_ file: URL, settings: ConversionSettings, work: URL, context: JobContext) async throws -> Product {
        let info = try await FFmpeg.probe(file)
        let target = target(for: file, info: info)
        let strong = settings.compression == .strong
        let out = output(work, target)
        var smaller = settings
        var args = ["-i", file.path]

        if target.isGIF {
            smaller.gifFPS = strong ? 8 : 10
            smaller.gifWidth = min(settings.gifWidth, strong ? 360 : 480)
            args += MediaEngine.gifArguments(settings: smaller, info: info)
        } else if target.isAudioOnly {
            guard [.mp3, .m4a, .ogg, .opus, .wma].contains(target.format) else {
                throw LemonError("\(target.format.label) is uncompressed or lossless. Convert it to M4A or MP3 to make it smaller.")
            }
            smaller.audioBitrate = [.mp3: strong ? 96 : 128, .m4a: strong ? 96 : 128, .opus: strong ? 48 : 64, .wma: strong ? 96 : 128]
            smaller.quality[.ogg] = .smaller
            args += ["-vn"] + MediaEngine.audioCodec(target.format, settings: smaller)
        } else {
            if strong, (info.height ?? 0) > 720 { smaller.videoHeight = 720 }
            args += MediaEngine.videoArguments(target.format, settings: smaller, info: info, quality: .smaller)
            if strong, let q = args.firstIndex(of: "-q:v"), target.format != .avi, target.format != .wmv { args[q + 1] = "35" }
        }
        try await FFmpeg.run(args + [out.path], duration: info.duration, context: context)
        try ImageTools.requireSmaller(out, than: file)
        return Product(url: out, source: file, fileExtension: target.format.fileExtension, suffix: "Compressed")
    }

    static func editMetadata(_ file: URL, _ edit: MetadataEdit, work: URL, context: JobContext) async throws -> Product {
        let ext = file.pathExtension.lowercased()
        let out = work.appendingPathComponent("out.\(ext)")
        var args = ["-i", file.path, "-map", "0", "-c", "copy"]
        if edit.removeAll { args += ["-map_metadata", "-1"] }
        if let title = edit.title { args += ["-metadata", "title=\(title)"] }
        if let author = edit.author { args += ["-metadata", "artist=\(author)"] }
        if let copyright = edit.copyright { args += ["-metadata", "copyright=\(copyright)"] }
        if let comment = edit.comment { args += ["-metadata", "comment=\(comment)"] }
        if edit.removeLocation { args += ["-metadata", "location=", "-metadata", "location-eng="] }
        try await FFmpeg.run(args + [out.path], duration: nil, context: context)
        return Product(url: out, source: file, fileExtension: ext, suffix: edit.removeAll ? "Clean" : "Edited")
    }

    /// Readable metadata for the Metadata editor, from FFmpeg's description.
    static func describeMetadata(_ file: URL) async -> [(String, String)] {
        guard let exe = FFmpeg.executable,
              let result = try? await ProcessRunner.run(exe, ["-hide_banner", "-nostdin", "-i", file.path])
        else { return [] }
        var rows: [(String, String)] = []
        for line in result.errors.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Duration:") || trimmed.hasPrefix("Stream #") {
                rows.append((trimmed.hasPrefix("Duration") ? "Duration" : "Stream", String(trimmed.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)))
            } else if let colon = trimmed.firstIndex(of: ":"), line.hasPrefix("      "), !trimmed.hasPrefix("Metadata") {
                rows.append((String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces),
                             String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            }
        }
        return rows
    }
}
