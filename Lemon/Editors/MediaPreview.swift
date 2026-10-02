import AVFoundation
import AppKit
import SwiftUI

/// Preview material for the editors: still frames, playable copies, thumbnails, waveforms.
nonisolated enum MediaPreview {
    /// A picture of the file: the image itself, or a video frame at `seconds`.
    static func frame(of file: URL, at seconds: Double = 0, maxPixels: Int = 1600) async -> CGImage? {
        switch FileKind(file: file) {
        case .image, .svg:
            return try? ImageEngine.load(file, maxPixels: maxPixels)
        case .video, .gif:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                return image
            }
            // Formats AVFoundation can't read (MKV, WebM, AVI, WMV): ask FFmpeg for the frame.
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("lemon-frame-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: out) }
            try? await FFmpeg.run(["-ss", FFmpeg.time(seconds), "-i", file.path, "-frames:v", "1",
                                   "-vf", "scale='min(\(maxPixels),iw)':-2", out.path], duration: nil, context: nil)
            return try? ImageEngine.load(out)
        default:
            return nil
        }
    }

    /// A file AVPlayer can play: the original, or a quick MP4/M4A copy for other formats.
    static func playable(_ file: URL) async throws -> URL {
        let asset = AVURLAsset(url: file)
        if (try? await asset.load(.isPlayable)) == true,
           FileKind(file: file) != .gif {
            return file
        }
        let info = try await FFmpeg.probe(file)
        let ext = info.hasVideo ? "mp4" : "m4a"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("lemon-preview-\(UUID().uuidString).\(ext)")
        var args = ["-i", file.path]
        if info.hasVideo {
            args += ["-vf", "scale='min(1280,iw)':-2,scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "h264_videotoolbox",
                     "-q:v", "50", "-allow_sw", "1", "-pix_fmt", "yuv420p"]
        }
        args += info.hasAudio ? ["-c:a", "aac_at", "-b:a", "128k"] : ["-an"]
        try await FFmpeg.run(args + [out.path], duration: info.duration, context: nil)
        return out
    }

    /// Evenly spaced small frames for the trim strip.
    static func thumbnails(of file: URL, count: Int, duration: Double) async -> [CGImage] {
        var images: [CGImage] = []
        for index in 0..<count {
            let time = duration * (Double(index) + 0.5) / Double(count)
            if let image = await frame(of: file, at: time, maxPixels: 220) { images.append(image) }
        }
        return images
    }

    /// Loudness peaks (0…1) for drawing a waveform with `bars` bars.
    static func waveform(of file: URL, bars: Int) async -> [Float] {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("lemon-wave-\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: raw) }
        guard (try? await FFmpeg.run(["-i", file.path, "-vn", "-ac", "1", "-ar", "4000", "-f", "f32le", raw.path],
                                      duration: nil, context: nil)) != nil,
              let data = try? Data(contentsOf: raw), !data.isEmpty
        else { return [] }
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let size = max(1, samples.count / bars)
        var peaks: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(index + size, samples.count)
            peaks.append(samples[index..<end].map(abs).max() ?? 0)
            index = end
        }
        let top = max(peaks.max() ?? 1, 0.0001)
        return peaks.map { $0 / top }
    }
}

/// Lays an image out to fit, and tells overlays where the picture actually is.
struct FittedImage<Overlay: View>: View {
    let image: CGImage?
    @ViewBuilder var overlay: (CGRect) -> Overlay

    var body: some View {
        GeometryReader { proxy in
            let rect = fittedRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    overlay(rect)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        guard let image, image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

/// Seconds as "1:02.5".
func timeLabel(_ seconds: Double) -> String {
    let total = max(0, seconds)
    let minutes = Int(total) / 60
    let rest = total - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, rest)
}
