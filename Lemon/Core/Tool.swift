import Foundation

/// The tools on the Option + Shift wheel.
nonisolated enum Tool: String, CaseIterable, Sendable, Codable {
    // Any file
    case compress, metadata
    // Images
    case editPhoto, annotate, background, crop, redact, readQR, createPDF, collage
    // Video and audio
    case trim, speed, join, snapshots, split, mute, normalize, channels, visualizer, bleep
    // PDF
    case merge, splitPages, organize
    // Archives
    case extract

    var label: String {
        switch self {
        case .compress: "Compress"
        case .metadata: "Metadata"
        case .editPhoto: "Edit"
        case .annotate: "Annotate"
        case .background: "Background"
        case .crop: "Crop"
        case .redact: "Redact"
        case .readQR: "Read QR"
        case .createPDF: "Create PDF"
        case .collage: "Collage"
        case .trim: "Trim"
        case .speed: "Speed"
        case .join: "Join"
        case .snapshots: "Snapshots"
        case .split: "Split"
        case .mute: "Mute"
        case .normalize: "Normalize"
        case .channels: "Channels"
        case .visualizer: "Visualizer"
        case .bleep: "Bleep"
        case .merge: "Merge"
        case .splitPages: "Split"
        case .organize: "Pages"
        case .extract: "Extract"
        }
    }

    /// SF Symbol shown above the label on the wheel.
    var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .metadata: "tag"
        case .editPhoto: "slider.horizontal.3"
        case .annotate: "pencil.tip.crop.circle"
        case .background: "person.crop.rectangle"
        case .crop: "crop"
        case .redact: "eye.slash"
        case .readQR: "qrcode.viewfinder"
        case .createPDF: "doc.richtext"
        case .collage: "rectangle.3.group"
        case .trim: "timeline.selection"
        case .speed: "gauge.with.dots.needle.67percent"
        case .join: "link"
        case .snapshots: "camera"
        case .split: "scissors"
        case .mute: "speaker.slash"
        case .normalize: "waveform.badge.plus"
        case .channels: "hifispeaker.2"
        case .visualizer: "waveform"
        case .bleep: "waveform.badge.exclamationmark"
        case .merge: "doc.on.doc"
        case .splitPages: "scissors"
        case .organize: "square.grid.2x2"
        case .extract: "archivebox"
        }
    }

    /// Tools that open an editing window before doing the work.
    var needsEditor: Bool {
        switch self {
        case .metadata, .editPhoto, .annotate, .background, .crop, .redact, .collage,
             .trim, .speed, .snapshots, .split, .bleep, .organize:
            true
        default:
            false
        }
    }
}

/// One choice on the wheel: convert to a format, or use a tool.
nonisolated enum Action: Hashable, Sendable {
    case convert(OutputFormat)
    case tool(Tool)

    var label: String {
        switch self {
        case .convert(let format): format.label
        case .tool(let tool): tool.label.uppercased()
        }
    }

    var symbol: String? {
        if case .tool(let tool) = self { return tool.symbol }
        return nil
    }
}
