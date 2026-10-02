import AppKit
import CoreText
import PDFKit

/// PDF and plain-text conversions.
nonisolated enum DocumentEngine {
    // MARK: From PDF

    static func convertPDF(
        _ file: URL, to format: OutputFormat, settings: ConversionSettings, work: URL, context: JobContext
    ) async throws -> Product {
        guard let document = PDFDocument(url: file) else { throw LemonError("\(file.lastPathComponent) couldn't be opened.") }
        if document.isLocked { throw LemonError("\(file.lastPathComponent) is password-protected.") }

        switch format {
        case .txt:
            let output = work.appendingPathComponent("out.txt")
            let text = document.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LemonError("This PDF has no selectable text (it may be a scan).")
            }
            try text.write(to: output, atomically: true, encoding: .utf8)
            return Product(url: output, source: file, fileExtension: "txt")

        case .docx:
            let pages = (0..<document.pageCount).map { index -> [String] in
                let text = document.page(at: index)?.string ?? ""
                return text.components(separatedBy: .newlines)
            }
            if pages.allSatisfy({ $0.joined().trimmingCharacters(in: .whitespaces).isEmpty }) {
                throw LemonError("This PDF has no selectable text (it may be a scan).")
            }
            let output = work.appendingPathComponent("out.docx")
            try DocxWriter.write(pages: pages, to: output, work: work)
            return Product(url: output, source: file, fileExtension: "docx")

        case .jpg, .png:
            return try await renderPages(document, of: file, as: format, dpi: settings.pdfDPI,
                                         settings: settings, work: work, context: context)

        default:
            throw LemonError("PDFs can't be converted to \(format.label).")
        }
    }

    /// Saves every page as a picture. One page → one file; several → a folder.
    static func renderPages(
        _ document: PDFDocument, of file: URL, as format: OutputFormat, dpi: Int,
        settings: ConversionSettings, work: URL, context: JobContext
    ) async throws -> Product {
        let count = document.pageCount
        guard count > 0 else { throw LemonError("This PDF has no pages.") }
        let quality = settings.quality(for: format).imageQuality

        if count == 1, let page = document.page(at: 0)?.pageRef {
            let output = work.appendingPathComponent("out.\(format.fileExtension)")
            try ImageEngine.write(try render(page, dpi: dpi), to: output, format: format, quality: quality)
            return Product(url: output, source: file, fileExtension: format.fileExtension)
        }

        let folder = work.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<count {
            try context.checkCancelled()
            guard let page = document.page(at: index)?.pageRef else { continue }
            let name = "Page \(index + 1).\(format.fileExtension)"
            try ImageEngine.write(try render(page, dpi: dpi), to: folder.appendingPathComponent(name), format: format, quality: quality)
            context.report(Double(index + 1) / Double(count))
        }
        return Product(url: folder, source: file, fileExtension: nil, suffix: "Pages")
    }

    /// Draws one PDF page on white at the given dots per inch, the right way up.
    static func render(_ page: CGPDFPage, dpi: Int) throws -> CGImage {
        let box = page.getBoxRect(.cropBox)
        var size = box.size
        if page.rotationAngle % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let scale = CGFloat(dpi) / 72
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, width * height < 400_000_000,
              let context = ImageEngine.makeContext(width: width, height: height, alpha: false)
        else { throw LemonError("This page is too large to turn into a picture.") }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw LemonError("The page couldn't be drawn.") }
        return image
    }

    // MARK: From plain text

    static func convertText(
        _ file: URL, to format: OutputFormat, settings: ConversionSettings, work: URL, context: JobContext
    ) async throws -> Product {
        let text = try readText(file)
        switch format {
        case .pdf:
            let output = work.appendingPathComponent("out.pdf")
            try makePDF(from: text, to: output)
            return Product(url: output, source: file, fileExtension: "pdf")
        case .jpg, .png:
            let pdf = work.appendingPathComponent("text.pdf")
            try makePDF(from: text, to: pdf)
            guard let document = PDFDocument(url: pdf) else { throw LemonError("The text couldn't be laid out.") }
            return try await renderPages(document, of: file, as: format, dpi: 200, settings: settings, work: work, context: context)
        case .srt, .vtt:
            let output = work.appendingPathComponent("out.\(format.fileExtension)")
            let cues = SubtitleEngine.cues(fromPlainText: text)
            try SubtitleEngine.write(cues, as: format, to: output)
            return Product(url: output, source: file, fileExtension: format.fileExtension)
        default:
            throw LemonError("Text can't be converted to \(format.label).")
        }
    }

    /// Reads a text file in whatever encoding it uses.
    static func readText(_ file: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: file, usedEncoding: &encoding) { return text }
        if let text = try? String(contentsOf: file, encoding: .windowsCP1252) { return text }
        throw LemonError("\(file.lastPathComponent) couldn't be read as text.")
    }

    /// Lays text out on Letter or A4 pages (depending on the region) with 1-inch margins.
    static func makePDF(from text: String, to url: URL) throws {
        let usesLetter = Locale.current.measurementSystem == .us
        var page = CGRect(x: 0, y: 0, width: usesLetter ? 612 : 595, height: usesLetter ? 792 : 842)
        let frameRect = page.insetBy(dx: 72, dy: 72)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ])
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else {
            throw LemonError("The PDF couldn't be created.")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var index = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), CGPath(rect: frameRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame).length
            context.endPDFPage()
            if visible == 0 { break } // nothing fits (shouldn't happen); avoid an endless loop
            index += visible
        } while index < attributed.length
        context.closePDF()
    }
}
