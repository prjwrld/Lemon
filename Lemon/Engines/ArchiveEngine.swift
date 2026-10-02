import Foundation

/// ZIP, TAR, GZIP and RAR, using macOS's built-in bsdtar (libarchive).
/// bsdtar refuses entries with ".." or absolute paths, so nothing is written outside the folder.
nonisolated enum ArchiveEngine {
    private static let bsdtar = URL(fileURLWithPath: "/usr/bin/bsdtar")

    /// Unpacks into a "name Extracted" folder.
    static func extract(_ file: URL, work: URL) async throws -> Product {
        let folder = work.appendingPathComponent("extracted", isDirectory: true)
        try await unpack(file, into: folder)
        return Product(url: folder, source: file, fileExtension: nil, suffix: "Extracted")
    }

    /// Re-packs an archive's contents as ZIP, TAR or TAR.GZ.
    static func convert(_ file: URL, to format: OutputFormat, work: URL) async throws -> Product {
        let folder = work.appendingPathComponent("contents", isDirectory: true)
        try await unpack(file, into: folder)
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        guard !entries.isEmpty else { throw LemonError("\(file.lastPathComponent) is empty.") }

        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        let formatArgs: [String] = switch format {
        case .zip: ["--format", "zip"]
        case .tar: ["--format", "ustar"]
        default: ["--format", "ustar", "-z"]   // .tar.gz
        }
        let result = try await ProcessRunner.run(bsdtar, formatArgs + ["-cf", output.path, "-C", folder.path] + entries)
        guard result.status == 0 else { throw LemonError("The new archive couldn't be made: \(lastLine(result.errors))") }
        return Product(url: output, source: file, fileExtension: format.fileExtension)
    }

    private static func unpack(_ file: URL, into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = file.pathExtension.lowercased()
        let isTar = SafeSaver.baseName(of: file) != file.deletingPathExtension().lastPathComponent

        // A single gzip/bzip2 file (not a .tar inside) just needs decompressing.
        if (ext == "gz" || ext == "bz2") && !isTar {
            let copy = folder.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: copy)
            let tool = ext == "gz" ? "/usr/bin/gunzip" : "/usr/bin/bunzip2"
            let result = try await ProcessRunner.run(URL(fileURLWithPath: tool), [copy.path])
            guard result.status == 0 else { throw LemonError("\(file.lastPathComponent) couldn't be decompressed.") }
            return
        }

        let result = try await ProcessRunner.run(bsdtar, ["-xf", file.path, "-C", folder.path])
        guard result.status == 0 else {
            throw LemonError("\(file.lastPathComponent) couldn't be opened: \(lastLine(result.errors))")
        }
    }

    private static func lastLine(_ text: String) -> String {
        text.split(separator: "\n").last.map(String.init) ?? "unknown problem"
    }
}
