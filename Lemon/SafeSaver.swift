import Foundation

/// Puts a finished file next to the original without ever replacing anything.
/// "photo.png" is tried first, then "photo 2.png", "photo 3.png", and so on.
nonisolated enum SafeSaver {
    static func place(
        _ finished: URL,
        nextTo original: URL,
        fileExtension: String,
        suffix: String? = nil
    ) throws -> URL {
        let folder = original.deletingLastPathComponent()
        var base = original.deletingPathExtension().lastPathComponent
        if let suffix { base += " \(suffix)" }

        for number in 1...9_999 {
            let name = number == 1 ? "\(base).\(fileExtension)" : "\(base) \(number).\(fileExtension)"
            let destination = folder.appendingPathComponent(name)
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
}
