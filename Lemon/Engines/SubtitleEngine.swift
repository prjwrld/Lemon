import Foundation

/// Reads and writes SRT and WebVTT subtitles, keeping timing and line breaks.
nonisolated enum SubtitleEngine {
    struct Cue: Equatable, Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    static func convert(_ file: URL, to format: OutputFormat, work: URL) throws -> Product {
        let cues = try parse(DocumentEngine.readText(file))
        guard !cues.isEmpty else { throw LemonError("No subtitles were found in \(file.lastPathComponent).") }
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        try write(cues, as: format, to: output)
        return Product(url: output, source: file, fileExtension: format.fileExtension)
    }

    // MARK: Reading

    /// Understands both SRT and WebVTT.
    static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[timeIndex].components(separatedBy: "-->")
            guard sides.count == 2,
                  let start = time(sides[0]),
                  let end = time(sides[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
            else { continue }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !body.isEmpty { cues.append(Cue(start: start, end: end, text: body)) }
        }
        return cues
    }

    /// "00:01:02,500", "00:01:02.500" or "01:02.500" → seconds.
    static func time(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap(Double.init)
        guard numbers.count == parts.count else { return nil }
        return numbers.count == 3 ? numbers[0] * 3600 + numbers[1] * 60 + numbers[2] : numbers[0] * 60 + numbers[1]
    }

    /// Plain text → subtitles: one cue per line, timed by how long it takes to read.
    static func cues(fromPlainText text: String) -> [Cue] {
        var clock = 0.0
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                let words = Double(line.split(separator: " ").count)
                let length = min(max(1 + words * 0.35, 1.5), 7)
                defer { clock += length }
                return Cue(start: clock, end: clock + length, text: line)
            }
    }

    // MARK: Writing

    static func write(_ cues: [Cue], as format: OutputFormat, to url: URL) throws {
        let text: String
        switch format {
        case .srt:
            text = cues.enumerated().map { index, cue in
                "\(index + 1)\n\(stamp(cue.start, separator: ",")) --> \(stamp(cue.end, separator: ","))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .vtt:
            text = "WEBVTT\n\n" + cues.map { cue in
                "\(stamp(cue.start, separator: ".")) --> \(stamp(cue.end, separator: "."))\n\(cue.text)\n"
            }.joined(separator: "\n")
        case .txt:
            text = cues.map { stripTags($0.text) }.joined(separator: "\n") + "\n"
        default:
            throw LemonError("Subtitles can't be saved as \(format.label).")
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 62.5 → "00:01:02,500"
    static func stamp(_ seconds: Double, separator: String) -> String {
        let millis = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, separator, millis % 1000)
    }

    /// Removes styling like <i>…</i> for plain text.
    static func stripTags(_ text: String) -> String {
        text.replacing(#/<[^>]+>/#, with: "")
    }
}
