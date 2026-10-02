import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts images with Apple's ImageIO. Never touches the original file:
/// it writes a temporary file first, then SafeSaver puts it next to the original.
nonisolated enum ImageConverter {
    struct Outcome: Sendable {
        var saved: [URL] = []
        var failures: [String] = []
    }

    enum Failure: LocalizedError {
        case unreadable
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .unreadable: "The image couldn't be read."
            case .cannotWrite: "The new image couldn't be created."
            }
        }
    }

    /// Lossy quality for JPG and HEIC (0 = smallest, 1 = best).
    static let quality = 0.9

    static func convert(_ files: [URL], to format: ImageFormat) -> Outcome {
        var outcome = Outcome()
        for file in files where ImageFormat(file: file) != format {
            do {
                outcome.saved.append(try convert(file, to: format))
            } catch {
                outcome.failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    static func convert(_ file: URL, to format: ImageFormat) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw Failure.unreadable }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: temp) }

        guard let destination = CGImageDestinationCreateWithURL(
            temp as CFURL, format.type.identifier as CFString, 1, nil
        ) else { throw Failure.cannotWrite }

        var options: [CFString: Any] = [:]
        if format.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false

        if hasAlpha && !format.supportsTransparency {
            // Draw onto white, and copy over the useful details (rotation, camera info…).
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let flat = flattenOnWhite(image)
            else { throw Failure.unreadable }
            let kept: [CFString] = [
                kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
                kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
            ]
            for key in kept { options[key] = properties[key] }
            CGImageDestinationAddImage(destination, flat, options as CFDictionary)
        } else {
            // Copies the picture and its details (rotation, camera info…) as they are.
            CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotWrite }
        return try SafeSaver.place(temp, nextTo: file, fileExtension: format.fileExtension)
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
