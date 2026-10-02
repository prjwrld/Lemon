import Foundation

/// Lemon's bundled FFmpeg (an LGPL build, see scripts/build-ffmpeg.sh).
nonisolated enum FFmpeg {
    /// Facts about a media file, read from FFmpeg's description of it.
    struct Info: Sendable {
        var duration: Double?
        var width: Int?
        var height: Int?
        var hasVideo = false
        var hasAudio = false
        var audioChannels: Int?
        var frameRate: Double?
    }

    static var executable: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg"),
            ProcessInfo.processInfo.environment["LEMON_FFMPEG"].map { URL(fileURLWithPath: $0) },
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func requireExecutable() throws -> URL {
        guard let executable else {
            throw LemonError("Lemon's media helper is missing. Please reinstall Lemon.")
        }
        return executable
    }

    /// Runs FFmpeg. Progress (0…1) is worked out from `duration` when it's known.
    static func run(_ arguments: [String], duration: Double?, context: JobContext?) async throws {
        let base = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
        let result = try await ProcessRunner.run(try requireExecutable(), base + arguments) { line in
            guard let context, let duration, duration > 0,
                  line.hasPrefix("out_time_us="),
                  let micros = Double(line.dropFirst("out_time_us=".count))
            else { return }
            context.report(micros / 1_000_000 / duration)
        }
        guard result.status == 0 else {
            let reason = result.errors
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .last { !$0.isEmpty } ?? "unknown problem"
            throw LemonError("The media helper couldn't finish: \(reason)")
        }
    }

    /// Reads duration, size and streams of a media file.
    static func probe(_ file: URL) async throws -> Info {
        // With no output file FFmpeg prints the description and exits with an error; that's expected.
        let result = try await ProcessRunner.run(try requireExecutable(), ["-hide_banner", "-nostdin", "-i", file.path])
        return parse(result.errors)
    }

    static func parse(_ text: String) -> Info {
        var info = Info()
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Duration:"), let value = line.split(separator: ",").first?
                .replacingOccurrences(of: "Duration:", with: "").trimmingCharacters(in: .whitespaces) {
                info.duration = seconds(from: value)
            }
            guard line.hasPrefix("Stream #") else { continue }
            if line.contains("Video:"), !line.contains("attached pic"), !info.hasVideo {
                info.hasVideo = true
                if let match = line.firstMatch(of: #/, (\d{2,5})x(\d{2,5})/#) {
                    info.width = Int(match.1); info.height = Int(match.2)
                }
                if let match = line.firstMatch(of: #/([\d.]+) fps/#) { info.frameRate = Double(match.1) }
            } else if line.contains("Audio:"), !info.hasAudio {
                info.hasAudio = true
                if line.contains(" mono") { info.audioChannels = 1 }
                else if line.contains(" stereo") { info.audioChannels = 2 }
                else if let match = line.firstMatch(of: #/(\d+) channels/#) { info.audioChannels = Int(match.1) }
            }
        }
        return info
    }

    /// "00:01:02.50" → 62.5
    static func seconds(from timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// 62.5 → "62.500" (FFmpeg's seconds format).
    static func time(_ seconds: Double) -> String { String(format: "%.3f", max(0, seconds)) }
}
