import CoreGraphics
import Foundation

/// Makes simple Word (.docx) files: pictures, or pages of text.
/// A .docx is a ZIP of a few XML files, so we write those and zip them with bsdtar.
nonisolated enum DocxWriter {
    private static let emuPerPixel = 9525                // at 96 pixels per inch
    private static let maxWidthEMU = 5_943_600           // 6.5 inches: a Letter page minus margins

    /// One picture per page, scaled to fit the page width.
    static func write(images: [CGImage], to url: URL, work: URL) throws {
        let folder = try makePackage(in: work)
        var body = ""
        var relationships = ""
        for (index, image) in images.enumerated() {
            let number = index + 1
            let media = folder.appendingPathComponent("word/media/image\(number).png")
            try ImageEngine.write(image, to: media, format: .png, quality: 1)
            relationships += #"<Relationship Id="rIdImage\#(number)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image\#(number).png"/>"#
            var cx = image.width * emuPerPixel, cy = image.height * emuPerPixel
            if cx > maxWidthEMU { cy = cy * maxWidthEMU / cx; cx = maxWidthEMU }
            if index > 0 { body += pageBreak }
            body += picture(number: number, cx: cx, cy: cy)
        }
        try finish(folder, body: body, relationships: relationships, to: url)
    }

    /// Text pages; each string in a page becomes a paragraph.
    static func write(pages: [[String]], to url: URL, work: URL) throws {
        let folder = try makePackage(in: work)
        var body = ""
        for (index, paragraphs) in pages.enumerated() {
            if index > 0 { body += pageBreak }
            for paragraph in paragraphs {
                body += #"<w:p><w:r><w:t xml:space="preserve">\#(escape(paragraph))</w:t></w:r></w:p>"#
            }
        }
        try finish(folder, body: body, relationships: "", to: url)
    }

    // MARK: Package parts

    private static func makePackage(in work: URL) throws -> URL {
        let folder = work.appendingPathComponent("docx-\(UUID().uuidString)", isDirectory: true)
        for sub in ["_rels", "word/_rels", "word/media"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return folder
    }

    private static func finish(_ folder: URL, body: String, relationships: String, to url: URL) throws {
        let files: [String: String] = [
            "[Content_Types].xml": """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
                <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
                <Default Extension="xml" ContentType="application/xml"/>\
                <Default Extension="png" ContentType="image/png"/>\
                <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
                </Types>
                """,
            "_rels/.rels": """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
                </Relationships>
                """,
            "word/_rels/document.xml.rels": """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
                """,
            "word/document.xml": """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
                xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
                xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
                xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
                <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>\
                <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>\
                </w:sectPr></w:body></w:document>
                """,
        ]
        for (path, text) in files {
            try text.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        // [Content_Types].xml must come first in the ZIP.
        try zip(folder, entries: ["[Content_Types].xml", "_rels", "word"], to: url)
        try? FileManager.default.removeItem(at: folder)
    }

    private static func zip(_ folder: URL, entries: [String], to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["--format", "zip", "-cf", url.path, "-C", folder.path] + entries
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LemonError("The Word document couldn't be packed.") }
    }

    private static let pageBreak = #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"#

    private static func picture(number: Int, cx: Int, cy: Int) -> String {
        """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(number)" name="Picture \(number)"/>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic><pic:nvPicPr><pic:cNvPr id="\(number)" name="image\(number).png"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="rIdImage\(number)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" }.map(String.init).joined()
    }
}
