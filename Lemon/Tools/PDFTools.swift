import PDFKit

/// PDF tools: merge, split, organise pages, compress, metadata.
nonisolated enum PDFTools {
    static func open(_ file: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: file) else { throw LemonError("\(file.lastPathComponent) couldn't be opened.") }
        if document.isLocked { throw LemonError("\(file.lastPathComponent) is password-protected.") }
        return document
    }

    static func merge(_ files: [URL], work: URL) throws -> Product {
        let merged = try open(files[0])
        for file in files.dropFirst() {
            let other = try open(file)
            for index in 0..<other.pageCount {
                if let page = other.page(at: index)?.copy() as? PDFPage { merged.insert(page, at: merged.pageCount) }
            }
        }
        return try save(merged, source: files[0], suffix: "Merged", work: work)
    }

    /// Each page becomes its own PDF, in a "name Pages" folder.
    static func splitPages(_ file: URL, work: URL, context: JobContext) throws -> Product {
        let document = try open(file)
        guard document.pageCount > 1 else { throw LemonError("This PDF has only one page.") }
        let folder = work.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<document.pageCount {
            try context.checkCancelled()
            let single = PDFDocument()
            if let page = document.page(at: index)?.copy() as? PDFPage { single.insert(page, at: 0) }
            guard single.write(to: folder.appendingPathComponent("Page \(index + 1).pdf")) else {
                throw LemonError("Page \(index + 1) couldn't be saved.")
            }
            context.report(Double(index + 1) / Double(document.pageCount))
        }
        return Product(url: folder, source: file, fileExtension: nil, suffix: "Pages")
    }

    /// Rebuilds the PDF in the order the organiser chose, with turned, copied or removed pages.
    static func organize(_ file: URL, _ edits: [PageEdit], work: URL) throws -> Product {
        let document = try open(file)
        guard !edits.isEmpty else { throw LemonError("At least one page must stay.") }
        let result = PDFDocument()
        for edit in edits {
            guard let page = document.page(at: edit.sourceIndex)?.copy() as? PDFPage else { continue }
            page.rotation = (page.rotation + edit.rotation + 360) % 360
            result.insert(page, at: result.pageCount)
        }
        return try save(result, source: file, suffix: "Organized", work: work)
    }

    static func compress(_ file: URL, work: URL) throws -> Product {
        let document = try open(file)
        let output = work.appendingPathComponent("out.pdf")
        let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        guard document.write(to: output, withOptions: options) else { throw LemonError("The smaller PDF couldn't be saved.") }
        try ImageTools.requireSmaller(output, than: file)
        return Product(url: output, source: file, fileExtension: "pdf", suffix: "Compressed")
    }

    static func editMetadata(_ file: URL, _ edit: MetadataEdit, work: URL) throws -> Product {
        let document = try open(file)
        var attributes = edit.removeAll ? [:] : (document.documentAttributes ?? [:])
        if let title = edit.title { attributes[PDFDocumentAttribute.titleAttribute] = title }
        if let author = edit.author { attributes[PDFDocumentAttribute.authorAttribute] = author }
        if let comment = edit.comment { attributes[PDFDocumentAttribute.subjectAttribute] = comment }
        if edit.removeAll {
            attributes[PDFDocumentAttribute.creatorAttribute] = ""
            attributes[PDFDocumentAttribute.producerAttribute] = ""
        }
        document.documentAttributes = attributes
        return try save(document, source: file, suffix: edit.removeAll ? "Clean" : "Edited", work: work)
    }

    static func describeMetadata(_ file: URL) -> [(String, String)] {
        guard let document = PDFDocument(url: file) else { return [] }
        var rows = [("Pages", "\(document.pageCount)")]
        for (key, value) in document.documentAttributes ?? [:] {
            rows.append(("\(key)".replacingOccurrences(of: "Attribute", with: ""), "\(value)"))
        }
        return rows
    }

    private static func save(_ document: PDFDocument, source: URL, suffix: String, work: URL) throws -> Product {
        let output = work.appendingPathComponent("out.pdf")
        guard document.write(to: output) else { throw LemonError("The PDF couldn't be saved.") }
        return Product(url: output, source: source, fileExtension: "pdf", suffix: suffix)
    }
}
