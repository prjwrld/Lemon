import Foundation

/// Runs a command-line helper (FFmpeg, bsdtar…) without blocking, and stops it on Cancel.
nonisolated enum ProcessRunner {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var errors: String
    }

    /// - Parameter onLine: called for each line the helper prints (used for progress).
    static func run(
        _ executable: URL,
        _ arguments: [String],
        in folder: URL? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let folder { process.currentDirectoryURL = folder }
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let collected = Collected()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            collected.appendOutput(data, onLine: onLine)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            collected.appendErrors(handle.availableData)
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        // Pick up anything printed just before the helper quit.
        collected.appendOutput(outPipe.fileHandleForReading.readDataToEndOfFile(), onLine: onLine)
        collected.appendErrors(errPipe.fileHandleForReading.readDataToEndOfFile())

        try Task.checkCancellation()
        return Result(status: status, output: collected.output, errors: collected.errors)
    }

    /// Thread-safe text collected from the helper's output.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data(), partialLine = ""

        func appendOutput(_ data: Data, onLine: (@Sendable (String) -> Void)?) {
            guard !data.isEmpty else { return }
            lock.lock()
            out.append(data)
            partialLine += String(decoding: data, as: UTF8.self)
            var lines = partialLine.components(separatedBy: "\n")
            partialLine = lines.removeLast()
            lock.unlock()
            if let onLine { lines.forEach(onLine) }
        }

        func appendErrors(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock(); err.append(data); lock.unlock()
        }

        var output: String { lock.lock(); defer { lock.unlock() }; return String(decoding: out, as: UTF8.self) }
        var errors: String { lock.lock(); defer { lock.unlock() }; return String(decoding: err, as: UTF8.self) }
    }
}
