import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Pictures: reading, writing and converting with Apple's ImageIO.
/// WebP is written with FFmpeg's libwebp, and Word files with DocxWriter.
nonisolated enum ImageEngine {
    static func convert(
        _ file: URL, to format: OutputFormat, settings: ConversionSettings, work: URL
    ) async throws -> Product {
        let output = work.appendingPathComponent("out.\(format.fileExtension)")
        let quality = settings.quality(for: format).imageQuality

        switch format {
        case .webp:
            let image = try load(file, maxPixels: settings.maxImageSize)
            try await writeWebP(image, to: output, quality: quality, work: work)
        case .docx:
            let image = try load(file, maxPixels: settings.maxImageSize)
            try DocxWriter.write(images: [image], to: output, work: work)
        default:
            // Fast path: copy the picture with all its details (rotation, camera info…) intact.
            if FileKind(file: file) == .image, settings.keepMetadata, settings.maxImageSize == nil,
               let source = CGImageSourceCreateWithURL(file as CFURL, nil),
               !(hasAlpha(source) && !supportsTransparency(format)) {
                try copy(source, to: output, format: format, quality: quality)
            } else {
                let image = try load(file, maxPixels: settings.maxImageSize)
                let details = settings.keepMetadata ? metadata(of: file) : [:]
                try write(image, to: output, format: format, quality: quality, properties: details)
            }
        }
        return Product(url: output, source: file, fileExtension: format.fileExtension)
    }

    // MARK: Reading

    /// Loads a picture upright (rotation applied), optionally no larger than `maxPixels`.
    static func load(_ file: URL, maxPixels: Int? = nil) throws -> CGImage {
        if FileKind(file: file) == .svg { return try renderSVG(file, maxPixels: maxPixels) }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw LemonError("\(file.lastPathComponent) couldn't be read as a picture.") }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels ?? longest, longest),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LemonError("\(file.lastPathComponent) couldn't be read as a picture.")
        }
        return image
    }

    /// Draws an SVG at twice its own size (at least 1024 pixels on the long side).
    private static func renderSVG(_ file: URL, maxPixels: Int?) throws -> CGImage {
        guard let svg = NSImage(contentsOf: file), svg.size.width > 0, svg.size.height > 0 else {
            throw LemonError("\(file.lastPathComponent) couldn't be read as an SVG drawing.")
        }
        var scale = max(2, 1024 / max(svg.size.width, svg.size.height))
        if let maxPixels { scale = min(scale, CGFloat(maxPixels) / max(svg.size.width, svg.size.height)) }
        let size = CGSize(width: (svg.size.width * scale).rounded(), height: (svg.size.height * scale).rounded())
        guard let context = makeContext(width: Int(size.width), height: Int(size.height), alpha: true) else {
            throw LemonError("Not enough memory to draw \(file.lastPathComponent).")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        svg.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw LemonError("Couldn't draw \(file.lastPathComponent).") }
        return image
    }

    /// The details stored inside a picture that are worth keeping (camera info, location, copyright…).
    static func metadata(of file: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        var kept: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            kept[key] = props[key]
        }
        // The pixels are already turned upright, so the rotation tag must say "upright".
        if var tiff = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            kept[kCGImagePropertyTIFFDictionary] = tiff
        }
        kept[kCGImagePropertyOrientation] = 1
        return kept
    }

    static func hasAlpha(_ source: CGImageSource) -> Bool {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return props?[kCGImagePropertyHasAlpha] as? Bool ?? false
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst: false
        default: true
        }
    }

    /// JPG and PDF pages can't be see-through, so transparent areas become white.
    static func supportsTransparency(_ format: OutputFormat) -> Bool {
        format != .jpg && format != .pdf
    }

    // MARK: Writing

    private static func copy(_ source: CGImageSource, to url: URL, format: OutputFormat, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw LemonError("\(format.label) pictures can't be made on this Mac.")
        }
        var options: [CFString: Any] = [:]
        if isLossy(format) { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LemonError("The new \(format.label) couldn't be saved.") }
    }

    /// Saves a picture in any format ImageIO can write (and WebP via FFmpeg when async is possible).
    static func write(
        _ image: CGImage, to url: URL, format: OutputFormat, quality: Double, properties: [CFString: Any] = [:]
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw LemonError("\(format.label) pictures can't be made on this Mac.")
        }
        var options = properties
        if isLossy(format) { options[kCGImageDestinationLossyCompressionQuality] = quality }
        let picture = (hasAlpha(image) && !supportsTransparency(format)) ? (flattenOnWhite(image) ?? image) : image
        CGImageDestinationAddImage(destination, picture, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw LemonError("The new \(format.label) couldn't be saved.") }
    }

    /// WebP needs libwebp, which lives in Lemon's FFmpeg. We hand it a lossless PNG.
    static func writeWebP(_ image: CGImage, to url: URL, quality: Double, work: URL) async throws {
        let png = work.appendingPathComponent("webp-source-\(UUID().uuidString).png")
        try write(image, to: png, format: .png, quality: 1)
        defer { try? FileManager.default.removeItem(at: png) }
        try await FFmpeg.run(
            ["-i", png.path, "-c:v", "libwebp", "-quality", String(Int(quality * 100)),
             "-compression_level", "4", "-frames:v", "1", url.path],
            duration: nil, context: nil)
    }

    /// Writes in the right format, using FFmpeg only when needed.
    static func save(_ image: CGImage, to url: URL, format: OutputFormat, quality: Double,
                     properties: [CFString: Any] = [:], work: URL) async throws {
        if format == .webp {
            try await writeWebP(image, to: url, quality: quality, work: work)
        } else {
            try write(image, to: url, format: format, quality: quality, properties: properties)
        }
    }

    static func isLossy(_ format: OutputFormat) -> Bool { [.jpg, .heic, .avif, .webp].contains(format) }

    static func makeContext(width: Int, height: Int, alpha: Bool) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = makeContext(width: image.width, height: image.height, alpha: false) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// The output format that matches a picture file (for tools that keep the format).
    static func format(of file: URL) -> OutputFormat {
        OutputFormat.allCases.first { $0.kind == .image && $0.matches(file) } ?? .png
    }
}

extension OutputFormat {
    /// The system type identifier, used by ImageIO.
    nonisolated var type: UTType {
        switch self {
        case .png: .png
        case .jpg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .avif: UTType("public.avif") ?? .image
        case .bmp: .bmp
        case .gif: .gif
        case .pdf: .pdf
        case .webp: .webP
        default: UTType(filenameExtension: fileExtension) ?? .data
        }
    }
}
