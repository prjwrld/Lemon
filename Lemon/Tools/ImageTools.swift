import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import PDFKit
import Vision

/// The picture tools.
nonisolated enum ImageTools {
    // MARK: Compress

    static func compress(_ file: URL, settings: ConversionSettings, work: URL) async throws -> Product {
        let format = ImageEngine.format(of: file)
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        let strong = settings.compression == .strong

        switch format {
        case .jpg, .heic, .avif:
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw unreadable(file) }
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else {
                throw LemonError("\(format.label) pictures can't be made on this Mac.")
            }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: strong ? 0.45 : 0.68]
            CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw LemonError("The smaller copy couldn't be saved.") }
        case .webp:
            try await ImageEngine.writeWebP(try ImageEngine.load(file), to: output, quality: strong ? 0.5 : 0.7, work: work)
        case .png:
            // Reduce to a 256- (or 128-) colour palette, like pngquant. Keeps transparency.
            let colors = strong ? 128 : 256
            try await FFmpeg.run(
                ["-i", file.path, "-filter_complex",
                 "[0:v]split[a][b];[a]palettegen=max_colors=\(colors):reserve_transparent=1:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a",
                 "-pred", "mixed", "-frames:v", "1", output.path],
                duration: nil, context: nil)
        case .tiff:
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil)
            else { throw unreadable(file) }
            let options: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] // LZW
            CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw LemonError("The smaller copy couldn't be saved.") }
        default:
            throw LemonError("\(format.label) pictures can't be compressed. Convert to PNG or JPG first.")
        }
        try requireSmaller(output, than: file)
        return Product(url: output, source: file, fileExtension: format.fileExtension, suffix: "Compressed")
    }

    /// Don't save a "compressed" copy that's bigger than the original.
    static func requireSmaller(_ output: URL, than original: URL) throws {
        let new = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let old = (try? original.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        if new == 0 || new >= old {
            throw LemonError("\(original.lastPathComponent) is already as small as Lemon can make it.")
        }
    }

    // MARK: Metadata

    static func editMetadata(_ file: URL, _ edit: MetadataEdit, work: URL) throws -> Product {
        let format = ImageEngine.format(of: file)
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw unreadable(file) }

        // kCFNull removes a section; the rotation is kept so the picture stays upright.
        var options: [CFString: Any] = [:]
        if edit.removeAll {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyMakerAppleDictionary] {
                options[key] = kCFNull
            }
            options[kCGImageMetadataShouldExcludeXMP] = true
            options[kCGImagePropertyOrientation] = props[kCGImagePropertyOrientation] ?? 1
        } else if edit.removeLocation {
            options[kCGImagePropertyGPSDictionary] = kCFNull
        }
        if !edit.removeAll {
            var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            var iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
            if let title = edit.title { tiff[kCGImagePropertyTIFFImageDescription] = title; iptc[kCGImagePropertyIPTCObjectName] = title }
            if let author = edit.author { tiff[kCGImagePropertyTIFFArtist] = author; iptc[kCGImagePropertyIPTCByline] = [author] }
            if let copyright = edit.copyright { tiff[kCGImagePropertyTIFFCopyright] = copyright; iptc[kCGImagePropertyIPTCCopyrightNotice] = copyright }
            if let comment = edit.comment { iptc[kCGImagePropertyIPTCCaptionAbstract] = comment }
            options[kCGImagePropertyTIFFDictionary] = tiff
            options[kCGImagePropertyIPTCDictionary] = iptc
        }
        if ImageEngine.isLossy(format) { options[kCGImageDestinationLossyCompressionQuality] = 1.0 }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LemonError("The updated picture couldn't be saved.") }
        return Product(url: output, source: file, fileExtension: format.fileExtension, suffix: edit.removeAll ? "Clean" : "Edited")
    }

    /// Readable list of a picture's details, for the Metadata editor.
    static func describeMetadata(_ file: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [] }
        var rows: [(String, String)] = []
        func walk(_ dict: [String: Any], prefix: String) {
            for key in dict.keys.sorted() {
                let value = dict[key]!
                if let nested = value as? [String: Any] {
                    walk(nested, prefix: key.trimmingCharacters(in: CharacterSet(charactersIn: "{}")) + " › ")
                } else {
                    rows.append((prefix + key, String(describing: value).replacingOccurrences(of: "\n", with: " ")))
                }
            }
        }
        walk(props, prefix: "")
        return rows
    }

    // MARK: Photo edit, annotate, crop, redact, background

    static func editPhoto(_ file: URL, _ adjustments: PhotoAdjustments, work: URL) throws -> Product {
        let image = try ImageEngine.load(file)
        let edited = PhotoFilter.apply(adjustments, to: CIImage(cgImage: image))
        guard let result = PhotoFilter.context.createCGImage(edited, from: edited.extent) else {
            throw LemonError("The edited photo couldn't be made.")
        }
        return try save(result, like: file, suffix: "Edited", work: work)
    }

    static func annotate(_ file: URL, _ marks: [AnnotationMark], work: URL) throws -> Product {
        let image = try ImageEngine.load(file)
        let result = try drawMarks(marks, on: image)
        return try save(result, like: file, suffix: "Annotated", work: work)
    }

    /// Draws arrows, shapes, pen lines and text on a picture.
    static func drawMarks(_ marks: [AnnotationMark], on image: CGImage) throws -> CGImage {
        let width = image.width, height = image.height
        guard let context = ImageEngine.makeContext(width: width, height: height, alpha: true) else {
            throw LemonError("Not enough memory to draw on this picture.")
        }
        let size = CGSize(width: width, height: height)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        // Marks use a top-left origin; flip so y runs downwards.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

        for mark in marks {
            let lineWidth = mark.lineWidth * size.width
            context.setStrokeColor(mark.color.cgColor)
            context.setFillColor(mark.color.cgColor)
            context.setLineWidth(mark.kind == .highlighter ? lineWidth * 4 : lineWidth)
            let pts = mark.points.map(point)
            guard let first = pts.first else { continue }
            switch mark.kind {
            case .pen, .highlighter:
                context.saveGState()
                if mark.kind == .highlighter { context.setAlpha(0.4); context.setBlendMode(.multiply) }
                context.beginPath(); context.move(to: first)
                pts.dropFirst().forEach { context.addLine(to: $0) }
                context.strokePath()
                context.restoreGState()
            case .arrow:
                guard let last = pts.last, last != first else { continue }
                context.beginPath(); context.move(to: first); context.addLine(to: last); context.strokePath()
                let angle = atan2(last.y - first.y, last.x - first.x)
                let head = max(lineWidth * 4, 12)
                context.beginPath()
                context.move(to: last)
                context.addLine(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
                context.addLine(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
                context.closePath(); context.fillPath()
            case .rectangle, .ellipse:
                guard let last = pts.last else { continue }
                let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
                mark.kind == .rectangle ? context.stroke(rect) : context.strokeEllipse(in: rect)
            case .text:
                guard !mark.text.isEmpty else { continue }
                let fontSize = max(lineWidth * 7, 14)
                let attributed = NSAttributedString(string: mark.text, attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor(cgColor: mark.color.cgColor) ?? .red,
                ])
                let line = CTLineCreateWithAttributedString(attributed)
                context.saveGState()
                // Text draws upside down in a flipped context, so flip it back around its baseline.
                context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                context.textPosition = CGPoint(x: first.x, y: first.y + fontSize)
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }
        guard let result = context.makeImage() else { throw LemonError("The drawing couldn't be finished.") }
        return result
    }

    static func crop(_ file: URL, to rect: CGRect, work: URL) throws -> Product {
        let image = try ImageEngine.load(file)
        let pixels = pixelRect(rect, width: image.width, height: image.height)
        guard let cropped = image.cropping(to: pixels) else { throw LemonError("That crop is outside the picture.") }
        return try save(cropped, like: file, suffix: "Cropped", work: work)
    }

    /// 0…1 rectangle → whole pixels inside the picture.
    static func pixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        let r = CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height),
                       width: rect.width * CGFloat(width), height: rect.height * CGFloat(height)).integral
        return r.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func redact(_ file: URL, _ rects: [CGRect], style: RedactStyle, work: URL) throws -> Product {
        let image = try ImageEngine.load(file)
        let result = try redact(image, rects, style: style)
        return try save(result, like: file, suffix: "Redacted", work: work)
    }

    static func redact(_ image: CGImage, _ rects: [CGRect], style: RedactStyle) throws -> CGImage {
        var output = CIImage(cgImage: image)
        let extent = output.extent
        for rect in rects {
            // Core Image counts y from the bottom.
            var area = pixelRect(rect, width: image.width, height: image.height)
            area.origin.y = extent.height - area.maxY
            guard !area.isEmpty else { continue }
            let patch: CIImage
            switch style {
            case .black:
                patch = CIImage(color: .black).cropped(to: area)
            case .pixelate:
                let f = CIFilter.pixellate()
                f.inputImage = output.clampedToExtent(); f.scale = Float(max(area.width, area.height) / 8); f.center = area.origin
                patch = (f.outputImage ?? output).cropped(to: area)
            case .blur:
                let f = CIFilter.gaussianBlur()
                f.inputImage = output.clampedToExtent(); f.radius = Float(max(area.width, area.height) / 6)
                patch = (f.outputImage ?? output).cropped(to: area)
            }
            output = patch.composited(over: output)
        }
        guard let result = PhotoFilter.context.createCGImage(output, from: extent) else {
            throw LemonError("The hidden areas couldn't be applied.")
        }
        return result
    }

    /// Separates the subject from the background with Vision, then fills the background.
    static func replaceBackground(_ file: URL, _ choice: BackgroundChoice, work: URL) throws -> Product {
        let image = try ImageEngine.load(file)
        let cutout = try removeBackground(image)
        var result = cutout
        switch choice {
        case .transparent:
            break
        case .color(let color):
            result = cutout.composited(over: CIImage(color: CIColor(cgColor: color.cgColor)).cropped(to: cutout.extent))
        case .blur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = CIImage(cgImage: image).clampedToExtent(); f.radius = Float(max(image.width, image.height) / 40)
            result = cutout.composited(over: (f.outputImage ?? CIImage(cgImage: image)).cropped(to: cutout.extent))
        }
        guard let cg = PhotoFilter.context.createCGImage(result, from: cutout.extent) else {
            throw LemonError("The new background couldn't be applied.")
        }
        if choice == .transparent {
            let output = work.appendingPathComponent("out.png")
            try ImageEngine.write(cg, to: output, format: .png, quality: 1)
            return Product(url: output, source: file, fileExtension: "png", suffix: "No Background")
        }
        return try save(cg, like: file, suffix: "New Background", work: work)
    }

    static func removeBackground(_ image: CGImage) throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw LemonError("No clear subject was found in this picture.")
        }
        let masked = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        return CIImage(cvPixelBuffer: masked)
    }

    // MARK: QR codes

    static func readCodes(_ file: URL) throws -> [String] {
        let image = try ImageEngine.load(file)
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    // MARK: Several pictures

    /// One page per picture, each page the picture's size.
    static func createPDF(_ files: [URL], work: URL, context: JobContext) throws -> Product {
        let document = PDFDocument()
        for (index, file) in files.enumerated() {
            try context.checkCancelled()
            let image = try ImageEngine.load(file)
            let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let options: [PDFPage.ImageInitializationOption: Any] = [
                .mediaBox: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                .compressionQuality: 0.85,
            ]
            guard let page = PDFPage(image: picture, options: options) else {
                throw LemonError("\(file.lastPathComponent) couldn't be added to the PDF.")
            }
            document.insert(page, at: document.pageCount)
            context.report(Double(index + 1) / Double(files.count))
        }
        let output = work.appendingPathComponent("out.pdf")
        guard document.write(to: output) else { throw LemonError("The PDF couldn't be saved.") }
        return Product(url: output, source: files[0], fileExtension: "pdf", suffix: "Images")
    }

    /// Arranges pictures in a grid on one canvas.
    static func collage(_ files: [URL], _ layout: CollageLayout, work: URL) throws -> Product {
        let images = try files.map { try ImageEngine.load($0, maxPixels: 2400) }
        let canvas = try renderCollage(images, layout)
        let output = work.appendingPathComponent("out.jpg")
        try ImageEngine.write(canvas, to: output, format: .jpg, quality: 0.9)
        return Product(url: output, source: files[0], fileExtension: "jpg", suffix: "Collage")
    }

    static func renderCollage(_ images: [CGImage], _ layout: CollageLayout, width: CGFloat = 2400) throws -> CGImage {
        let columns = max(1, min(layout.columns, images.count))
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let gap = width * layout.spacing
        let cell = (width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        // Cells take the average shape of the pictures.
        let aspect = images.map { CGFloat($0.height) / CGFloat($0.width) }.reduce(0, +) / CGFloat(images.count)
        let cellHeight = cell * aspect
        let height = gap * CGFloat(rows + 1) + cellHeight * CGFloat(rows)
        guard let context = ImageEngine.makeContext(width: Int(width), height: Int(height), alpha: false) else {
            throw LemonError("The collage is too large.")
        }
        context.setFillColor(layout.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        for (index, image) in images.enumerated() {
            let col = index % columns, row = index / columns
            let frame = CGRect(x: gap + CGFloat(col) * (cell + gap),
                               y: height - gap - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap,
                               width: cell, height: cellHeight)
            let size = CGSize(width: image.width, height: image.height)
            let scale = layout.fill ? max(frame.width / size.width, frame.height / size.height)
                                    : min(frame.width / size.width, frame.height / size.height)
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            context.saveGState()
            context.clip(to: frame)
            context.draw(image, in: CGRect(x: frame.midX - drawn.width / 2, y: frame.midY - drawn.height / 2,
                                           width: drawn.width, height: drawn.height))
            context.restoreGState()
        }
        guard let result = context.makeImage() else { throw LemonError("The collage couldn't be made.") }
        return result
    }

    // MARK: Helpers

    /// Saves in the same format as the original (keeping its details), with a suffix.
    static func save(_ image: CGImage, like file: URL, suffix: String, work: URL) throws -> Product {
        var format = ImageEngine.format(of: file)
        if format == .webp || FileKind(file: file) == .svg { format = .png } // keep it simple and lossless
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        try ImageEngine.write(image, to: output, format: format, quality: 0.92, properties: ImageEngine.metadata(of: file))
        return Product(url: output, source: file, fileExtension: format.fileExtension, suffix: suffix)
    }

    private static func unreadable(_ file: URL) -> LemonError {
        LemonError("\(file.lastPathComponent) couldn't be read as a picture.")
    }
}
