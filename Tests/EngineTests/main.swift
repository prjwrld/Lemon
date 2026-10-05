// Engine tests: makes sample files of every kind, then runs every conversion route
// and every tool on them, checking each result can be opened.
// Run with: ./scripts/test-engines.sh
import AppKit
import CoreImage
import PDFKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let samples = root.appendingPathComponent("samples", isDirectory: true)
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)

var passed = 0, failed: [String] = []
func check(_ ok: Bool, _ name: String, _ detail: String = "") {
    if ok { passed += 1; print("  ✓ \(name) \(detail)") } else { failed.append(name); print("  ✗ \(name) \(detail)") }
}

// MARK: - Sample files

func ffmpeg(_ args: [String]) async throws {
    try await FFmpeg.run(args, duration: nil, context: nil)
}

let photo = samples.appendingPathComponent("photo.jpg")
let gradient = CIFilter(name: "CILinearGradient", parameters: [
    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 640, y: 480),
    "inputColor0": CIColor(red: 1, green: 0.8, blue: 0.1), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.9),
])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
let gradientCG = CIContext().createCGImage(gradient, from: gradient.extent)!
try ImageEngine.write(gradientCG, to: photo, format: .jpg, quality: 0.9, properties: [
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.97, kCGImagePropertyGPSLatitudeRef: "N"],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Lemon Test"],
])

let png = samples.appendingPathComponent("alpha.png")
let ctx = ImageEngine.makeContext(width: 320, height: 240, alpha: true)!
ctx.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1); ctx.fillEllipse(in: CGRect(x: 60, y: 40, width: 200, height: 160))
try ImageEngine.write(ctx.makeImage()!, to: png, format: .png, quality: 1)

let qr = samples.appendingPathComponent("qr.png")
let qrFilter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://lemon.app".utf8)])!
let qrImage = qrFilter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
try ImageEngine.write(CIContext().createCGImage(qrImage, from: qrImage.extent)!, to: qr, format: .png, quality: 1)

let svg = samples.appendingPathComponent("drawing.svg")
try ##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120"><rect width="200" height="120" fill="#ffd21f"/><circle cx="100" cy="60" r="40" fill="#333"/></svg>"##
    .write(to: svg, atomically: true, encoding: .utf8)

let video = samples.appendingPathComponent("clip.mp4")
try await ffmpeg(["-f", "lavfi", "-i", "testsrc=size=640x360:rate=25:duration=3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                  "-c:v", "h264_videotoolbox", "-c:a", "aac_at", "-shortest", video.path])
let gif = samples.appendingPathComponent("motion.gif")
try await ffmpeg(["-f", "lavfi", "-i", "testsrc=size=320x240:rate=10:duration=2", gif.path])
let wav = samples.appendingPathComponent("tone.wav")
try await ffmpeg(["-f", "lavfi", "-i", "sine=frequency=440:duration=3", "-ac", "2", wav.path])

let text = samples.appendingPathComponent("notes.txt")
try (1...80).map { "Line \($0): Lemon converts files with a Shift-drag." }.joined(separator: "\n")
    .write(to: text, atomically: true, encoding: .utf8)
let pdf = samples.appendingPathComponent("document.pdf")
try DocumentEngine.makePDF(from: try String(contentsOf: text, encoding: .utf8), to: pdf)

let srt = samples.appendingPathComponent("captions.srt")
try "1\n00:00:01,000 --> 00:00:02,500\nHello <i>there</i>\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond line\nwith a break\n"
    .write(to: srt, atomically: true, encoding: .utf8)
let vtt = samples.appendingPathComponent("captions.vtt")
try "WEBVTT\n\n00:01.000 --> 00:02.500 align:start\nHello there\n\n00:03.000 --> 00:04.000\nSecond line\n"
    .write(to: vtt, atomically: true, encoding: .utf8)

let zip = samples.appendingPathComponent("archive.zip")
let zipSource = root.appendingPathComponent("zip-src", isDirectory: true)
try FileManager.default.createDirectory(at: zipSource, withIntermediateDirectories: true)
try FileManager.default.copyItem(at: text, to: zipSource.appendingPathComponent("notes.txt"))
_ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["--format", "zip", "-cf", zip.path, "-C", zipSource.path, "notes.txt"])
let tgz = samples.appendingPathComponent("archive.tar.gz")
_ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-czf", tgz.path, "-C", zipSource.path, "notes.txt"])

let allSamples = [photo, png, svg, gif, video, wav, pdf, text, srt, vtt, zip, tgz]
let originals = Dictionary(uniqueKeysWithValues: allSamples.map { ($0, try! Data(contentsOf: $0)) })
let quiet = JobContext(report: { _ in }, note: { print("    note: \($0)") })
var settings = ConversionSettings()

// MARK: - Checking results

func validate(_ url: URL) async -> (Bool, String) {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return (false, "missing") }
    if isDir.boolValue {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return (!items.isEmpty, "\(items.count) items")
    }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size > 0 else { return (false, "empty") }
    let ext = url.pathExtension.lowercased()
    switch FileKind(file: url) {
    case .image, .svg:
        guard let image = try? ImageEngine.load(url) else { return (false, "unreadable image") }
        return (true, "\(image.width)×\(image.height)")
    case .pdf:
        guard let doc = PDFDocument(url: url) else { return (false, "bad pdf") }
        return (doc.pageCount > 0, "\(doc.pageCount) pages")
    case .video, .audio, .gif:
        guard let info = try? await FFmpeg.probe(url), let d = info.duration, d > 0 else { return (false, "unreadable media") }
        return (true, String(format: "%.1fs%@", d, info.hasVideo ? " \(info.width ?? 0)×\(info.height ?? 0)" : ""))
    case .subtitle:
        let cues = SubtitleEngine.parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        return (!cues.isEmpty, "\(cues.count) cues")
    case .archive:
        let r = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-tf", url.path])
        return (r?.status == 0, "\(r?.output.split(separator: "\n").count ?? 0) entries")
    default:
        if ext == "docx" {
            let r = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/bsdtar"), ["-tf", url.path])
            return (r?.output.contains("word/document.xml") == true, "word package")
        }
        return (true, "\(size) bytes")
    }
}

func run(_ action: Action, _ files: [URL], _ options: ToolOptions = .none, name: String) async {
    do {
        let saved = try await Processor.run(action, files: files, options: options, settings: settings, context: quiet)
        if saved.isEmpty { check(true, name, "(no file)"); return }
        for url in saved {
            let (ok, detail) = await validate(url)
            check(ok, name, "→ \(url.lastPathComponent) \(detail)")
        }
    } catch {
        check(false, name, "error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
    }
}

// MARK: - Every conversion route

print("\nConversions")
var routes = 0
for sample in allSamples {
    for action in ActionCatalog.actions(for: [sample], mode: .convert) {
        routes += 1
        await run(action, [sample], name: "\(sample.lastPathComponent) → \(action.label)")
    }
}
print("  (\(routes) routes tried)")

// MARK: - Repeat conversion gets a numbered name
print("\nSafe names")
let again = try await Processor.run(.convert(.png), files: [photo], options: .none, settings: settings, context: quiet)
check(again.first?.lastPathComponent == "photo 2.png", "repeat conversion numbered", again.first?.lastPathComponent ?? "")

// MARK: - Tools

print("\nTools")
await run(.tool(.compress), [photo], name: "image compress")
await run(.tool(.compress), [png], name: "png compress")
await run(.tool(.metadata), [photo], .metadata(MetadataEdit(removeAll: true)), name: "image metadata remove")
await run(.tool(.metadata), [photo], .metadata(MetadataEdit(removeLocation: true, title: "Sunset")), name: "image metadata edit")
var adj = PhotoAdjustments(); adj.exposure = 1; adj.vignette = 0.5; adj.grain = 0.3; adj.temperature = 0.4
await run(.tool(.editPhoto), [photo], .photo(adj), name: "edit photo")
await run(.tool(.annotate), [photo], .annotate([
    AnnotationMark(kind: .arrow, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)], color: .red),
    AnnotationMark(kind: .text, points: [CGPoint(x: 0.2, y: 0.7)], color: .white, text: "Hello"),
]), name: "annotate")
await run(.tool(.background), [png], .background(.color(.white)), name: "background")
await run(.tool(.crop), [photo], .crop(CGRect(x: 0.125, y: 0, width: 0.75, height: 1)), name: "crop image (1:1)")
await run(.tool(.redact), [photo], .redact([CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)], .pixelate), name: "redact image")
await run(.tool(.readQR), [qr], name: "read QR")
await run(.tool(.createPDF), [photo, png], name: "images → one PDF")
await run(.tool(.collage), [photo, png, qr], .collage(CollageLayout()), name: "collage")
await run(.tool(.trim), [video], .trim(TimeRange(start: 0.5, end: 1.5)), name: "trim video")
await run(.tool(.trim), [wav], .trim(TimeRange(start: 1, end: 2)), name: "trim audio")
await run(.tool(.crop), [video], .crop(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), name: "crop video")
await run(.tool(.speed), [video], .speed(2), name: "speed video 2x")
await run(.tool(.speed), [gif], .speed(0.5), name: "speed gif 0.5x")
await run(.tool(.snapshots), [video], .snapshots(4), name: "snapshots")
await run(.tool(.split), [video], .split([1.5]), name: "split video")
await run(.tool(.mute), [video], name: "mute")
await run(.tool(.redact), [video], .redact([CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)], .blur), name: "redact video")
await run(.tool(.compress), [video], name: "compress video")
await run(.tool(.metadata), [video], .metadata(MetadataEdit(title: "Clip")), name: "video metadata")
await run(.tool(.join), [video, video], name: "join videos")
await run(.tool(.normalize), [wav], name: "normalize")
await run(.tool(.channels), [wav], name: "mono/stereo")
await run(.tool(.visualizer), [wav], name: "visualizer")
await run(.tool(.bleep), [wav], .bleep([TimeRange(start: 1, end: 1.5)]), name: "bleep")
await run(.tool(.join), [wav, wav], name: "join audio")
await run(.tool(.organize), [pdf], .pages([PageEdit(sourceIndex: 1, rotation: 90), PageEdit(sourceIndex: 0)]), name: "organize pages")
await run(.tool(.splitPages), [pdf], name: "split pdf")
await run(.tool(.merge), [pdf, pdf], name: "merge pdfs")
await run(.tool(.metadata), [pdf], .metadata(MetadataEdit(title: "Notes")), name: "pdf metadata")
await run(.tool(.extract), [zip], name: "extract zip")
await run(.tool(.extract), [tgz], name: "extract tar.gz")

// MARK: - Portrait phone video (stored sideways with a rotation note)
print("\nPortrait video")
let portrait = samples.appendingPathComponent("portrait.mp4")
try await ffmpeg(["-display_rotation", "90", "-i", video.path, "-c", "copy", portrait.path])
let portraitInfo = try await FFmpeg.probe(portrait)
check(portraitInfo.width == 360 && portraitInfo.height == 640, "portrait size read upright",
      "\(portraitInfo.width ?? 0)×\(portraitInfo.height ?? 0)")
if let cropped = try? await Processor.run(.tool(.crop), files: [portrait], options: .crop(CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
                                          settings: settings, context: quiet).first,
   let info = try? await FFmpeg.probe(cropped) {
    check(info.width == 180 && info.height == 640, "portrait crop (right half)", "\(info.width ?? 0)×\(info.height ?? 0)")
} else {
    check(false, "portrait crop (right half)", "failed")
}

// MARK: - Originals untouched
print("\nOriginals")
for (url, data) in originals {
    check((try? Data(contentsOf: url)) == data, "unchanged: \(url.lastPathComponent)")
}

print("\n\(passed) passed, \(failed.count) failed")
if !failed.isEmpty { print("Failed:\n  " + failed.joined(separator: "\n  ")); exit(1) }
