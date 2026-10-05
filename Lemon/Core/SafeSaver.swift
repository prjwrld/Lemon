import Foundation

/// Puts a finished file or folder in place without ever replacing anything.
/// "photo.png" is tried first, then "photo 2.png", "photo 3.png", and so on.
nonisolated enum SafeSaver {
    /// - Parameters:
    ///   - finished: the temporary result (a file or a folder).
    ///   - original: the file it was made from; the result goes next to it unless `folder` is set.
    ///   - fileExtension: the result's extension, or nil for a folder.
    ///   - suffix: words added to the name, e.g. "Cropped" → "photo Cropped.jpg".
    ///   - folder: where to save instead of next to the original (from Settings → Folders).
    static func place(
        _ finished: URL,
        nextTo original: URL,
        fileExtension: String?,
        suffix: String? = nil,
        folder: URL? = nil
    ) throws -> URL {
        let destinationFolder = folder ?? original.deletingLastPathComponent()
        var base = baseName(of: original)
        if let suffix { base += " \(suffix)" }

        for number in 1...9_999 {
            let stem = number == 1 ? base : "\(base) \(number)"
            let name = fileExtension.map { "\(stem).\($0)" } ?? stem
            let destination = destinationFolder.appendingPathComponent(name, isDirectory: fileExtension == nil)
            do {
                // moveItem refuses to overwrite, so an existing file is never lost,
                // even if another app creates the same name at the same moment.
                try FileManager.default.moveItem(at: finished, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// "photo.jpg" → "photo", and "backup.tar.gz" → "backup".
    static func baseName(of file: URL) -> String {
        var base = file.deletingPathExtension().lastPathComponent
        if base.lowercased().hasSuffix(".tar") { base = String(base.dropLast(4)) }
        return base
    }

    /// Deletes temporary files Lemon left behind if it quit mid-job (work folders and
    /// editor previews). Called at launch, when nothing is running yet.
    static func removeLeftovers() {
        let temp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        for name in names where name.hasPrefix("Lemon-") || name.hasPrefix("lemon-") {
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(name))
        }
    }

    /// A fresh, empty temporary folder for one job.
    static func makeWorkFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lemon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
