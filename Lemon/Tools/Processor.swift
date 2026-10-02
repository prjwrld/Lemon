import AppKit
import Foundation

/// Runs a wheel choice on the dropped files and saves the results safely.
nonisolated enum Processor {
    /// Returns the saved files and folders. Files that fail are listed in the job's note;
    /// the job only fails if nothing could be saved.
    static func run(
        _ action: Action, files: [URL], options: ToolOptions,
        settings: ConversionSettings, context: JobContext
    ) async throws -> [URL] {
        switch action {
        case .convert(let format):
            let todo = files.filter { !format.matches($0) }
            return try await eachFile(todo, context: context) { file, work, sub in
                [try await convert(file, to: format, settings: settings, work: work, context: sub)]
            }.saving(with: settings, context: context)

        case .tool(let tool):
            return try await runTool(tool, files: files, options: options, settings: settings, context: context)
        }
    }

    static func convert(_ file: URL, to format: OutputFormat, settings: ConversionSettings,
                        work: URL, context: JobContext) async throws -> Product {
        switch FileKind(file: file) {
        case .image, .svg: try await ImageEngine.convert(file, to: format, settings: settings, work: work)
        case .gif, .video, .audio: try await MediaEngine.convert(file, to: format, settings: settings, work: work, context: context)
        case .pdf: try await DocumentEngine.convertPDF(file, to: format, settings: settings, work: work, context: context)
        case .text: try await DocumentEngine.convertText(file, to: format, settings: settings, work: work, context: context)
        case .subtitle: try SubtitleEngine.convert(file, to: format, work: work)
        case .archive: try await ArchiveEngine.convert(file, to: format, work: work)
        case nil: throw LemonError("Lemon doesn't know this kind of file.")
        }
    }

    // MARK: Tools

    private static func runTool(_ tool: Tool, files: [URL], options: ToolOptions,
                                settings: ConversionSettings, context: JobContext) async throws -> [URL] {
        let kind = ActionCatalog.commonKind(of: files)
        let isPicture = kind == .image || kind == .svg
        let isMedia = kind == .video || kind == .audio || kind == .gif

        // Tools that combine several files into one result.
        switch tool {
        case .createPDF:
            return try await single(files, settings, context) { work in try ImageTools.createPDF(files, work: work, context: context) }
        case .collage:
            guard case .collage(let layout) = options else { return [] }
            return try await single(files, settings, context) { work in try ImageTools.collage(files, layout, work: work) }
        case .merge:
            return try await single(files, settings, context) { work in try PDFTools.merge(files, work: work) }
        case .join:
            guard files.count > 1 else { throw LemonError("Choose two or more files to join.") }
            return try await single(files, settings, context) { work in
                try await MediaTools.join(files, settings: settings, work: work, context: context)
            }
        case .readQR:
            var found: [String] = []
            for file in files { found += try ImageTools.readCodes(file) }
            guard !found.isEmpty else { throw LemonError("No QR code or barcode was found.") }
            let text = found.joined(separator: "\n")
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            context.note("Copied: \(text)")
            return []
        default:
            break
        }

        // Tools that work on each file separately.
        return try await eachFile(files, context: context) { file, work, sub in
            switch (tool, options) {
            case (.compress, _):
                if isPicture { return [try await ImageTools.compress(file, settings: settings, work: work)] }
                if kind == .pdf { return [try PDFTools.compress(file, work: work)] }
                return [try await MediaTools.compress(file, settings: settings, work: work, context: sub)]
            case (.metadata, .metadata(let edit)):
                if isPicture { return [try ImageTools.editMetadata(file, edit, work: work)] }
                if kind == .pdf { return [try PDFTools.editMetadata(file, edit, work: work)] }
                return [try await MediaTools.editMetadata(file, edit, work: work, context: sub)]
            case (.editPhoto, .photo(let adjustments)):
                return [try ImageTools.editPhoto(file, adjustments, work: work)]
            case (.annotate, .annotate(let marks)):
                return [try ImageTools.annotate(file, marks, work: work)]
            case (.background, .background(let choice)):
                return [try ImageTools.replaceBackground(file, choice, work: work)]
            case (.crop, .crop(let rect)):
                if isMedia { return [try await MediaTools.crop(file, to: rect, settings: settings, work: work, context: sub)] }
                return [try ImageTools.crop(file, to: rect, work: work)]
            case (.redact, .redact(let rects, let style)):
                if isMedia { return [try await MediaTools.redact(file, rects, style: style, settings: settings, work: work, context: sub)] }
                return [try ImageTools.redact(file, rects, style: style, work: work)]
            case (.trim, .trim(let range)):
                return [try await MediaTools.trim(file, range, settings: settings, work: work, context: sub)]
            case (.speed, .speed(let factor)):
                return [try await MediaTools.speed(file, factor: factor, settings: settings, work: work, context: sub)]
            case (.snapshots, .snapshots(let count)):
                return [try await MediaTools.snapshots(file, count: count, work: work, context: sub)]
            case (.split, .split(let points)):
                return try await MediaTools.split(file, at: points, settings: settings, work: work, context: sub)
            case (.mute, _):
                return [try await MediaTools.mute(file, work: work, context: sub)]
            case (.normalize, _):
                return [try await MediaTools.normalize(file, settings: settings, work: work, context: sub)]
            case (.channels, _):
                return [try await MediaTools.channels(file, settings: settings, work: work, context: sub)]
            case (.visualizer, _):
                return [try await MediaTools.visualizer(file, work: work, context: sub)]
            case (.bleep, .bleep(let ranges)):
                return [try await MediaTools.bleep(file, ranges, settings: settings, work: work, context: sub)]
            case (.splitPages, _):
                return [try PDFTools.splitPages(file, work: work, context: sub)]
            case (.organize, .pages(let edits)):
                return [try PDFTools.organize(file, edits, work: work)]
            case (.extract, _):
                return [try await ArchiveEngine.extract(file, work: work)]
            default:
                throw LemonError("\(tool.label) needs its editor first.")
            }
        }.saving(with: settings, context: context)
    }

    // MARK: Helpers

    /// Runs work for one combined result and saves it.
    private static func single(_ files: [URL], _ settings: ConversionSettings, _ context: JobContext,
                               _ make: (URL) async throws -> Product) async throws -> [URL] {
        let work = try SafeSaver.makeWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let product = try await make(work)
        return [try place(product, settings: settings)]
    }

    /// Runs work on each file in turn, with progress shared across them. Each file
    /// gets its own temporary folder, cleaned up once its results are saved.
    private static func eachFile(
        _ files: [URL], context: JobContext,
        _ make: (URL, URL, JobContext) async throws -> [Product]
    ) async throws -> Batch {
        var batch = Batch()
        for (index, file) in files.enumerated() {
            try context.checkCancelled()
            let work = try SafeSaver.makeWorkFolder()
            batch.workFolders.append(work)
            let share = JobContext(
                report: { context.report((Double(index) + $0) / Double(files.count)) },
                note: context.note)
            do {
                batch.products += try await make(file, work, share)
            } catch is CancellationError {
                batch.cleanUp()
                throw CancellationError()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                batch.failures.append(files.count > 1 ? "\(file.lastPathComponent): \(message)" : message)
            }
            context.report(Double(index + 1) / Double(files.count))
        }
        return batch
    }

    struct Batch {
        var products: [Product] = []
        var failures: [String] = []
        var workFolders: [URL] = []

        func cleanUp() { workFolders.forEach { try? FileManager.default.removeItem(at: $0) } }

        func saving(with settings: ConversionSettings, context: JobContext) throws -> [URL] {
            defer { cleanUp() }
            let saved = try products.map { try Processor.place($0, settings: settings) }
            if !failures.isEmpty {
                if saved.isEmpty { throw LemonError(failures.joined(separator: "\n")) }
                context.note("Some files were skipped:\n" + failures.joined(separator: "\n"))
            }
            if saved.isEmpty && failures.isEmpty { throw LemonError("Those files are already in that format.") }
            return saved
        }
    }

    static func place(_ product: Product, settings: ConversionSettings) throws -> URL {
        try SafeSaver.place(product.url, nextTo: product.source, fileExtension: product.fileExtension,
                            suffix: product.suffix, folder: settings.outputFolder)
    }
}
