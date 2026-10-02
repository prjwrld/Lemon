import CoreImage
import SwiftUI

/// Remove or replace a photo's background (subject found by Apple's Vision).
struct BackgroundEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    enum Fill: String, CaseIterable, Identifiable {
        case transparent = "Transparent", white = "White", black = "Black", color = "Color", blur = "Blur"
        var id: String { rawValue }
    }

    @State private var original: CGImage?
    @State private var cutout: CGImage?
    @State private var problem: String?
    @State private var fill = Fill.transparent
    @State private var custom = Color.lemon

    var body: some View {
        GlassShell(title: "Background", subtitle: file.lastPathComponent, onClose: onCancel) {
            ZStack {
                if let problem {
                    ContentUnavailableView("No subject found", systemImage: "person.crop.rectangle", description: Text(problem))
                } else {
                    FittedImage(image: cutout ?? original) { frame in
                        background.frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false)
                    }
                    if cutout == nil { ProgressView("Finding the subject…").padding().glassEffect() }
                }
            }
            .frame(minHeight: 360)

            HStack {
                Picker("Background", selection: $fill) {
                    ForEach(Fill.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if fill == .color { ColorPicker("", selection: $custom).labelsHidden() }
                Spacer()
            }
        } footer: {
            EditorFooter(canApply: cutout != nil, onCancel: onCancel, onApply: { onApply(.background(choice)) })
        }
        .task { await prepare() }
    }

    /// The background sits under the cut-out picture.
    @ViewBuilder private var background: some View {
        ZStack {
            switch fill {
            case .transparent: Checkerboard()
            case .white: Color.white
            case .black: Color.black
            case .color: custom
            case .blur:
                if let original { Image(decorative: original, scale: 1).resizable().blur(radius: 18).clipped() }
            }
            if let cutout { Image(decorative: cutout, scale: 1).resizable() }
        }
    }

    private var choice: BackgroundChoice {
        switch fill {
        case .transparent: return .transparent
        case .white: return .color(.white)
        case .black: return .color(.black)
        case .blur: return .blur
        case .color:
            let ns = NSColor(custom).usingColorSpace(.sRGB) ?? .white
            return .color(RGBA(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent))
        }
    }

    private func prepare() async {
        guard let image = await MediaPreview.frame(of: file, maxPixels: 1400) else { return }
        original = image
        do {
            cutout = try await Task.detached {
                let masked = try ImageTools.removeBackground(image)
                return PhotoFilter.context.createCGImage(masked, from: masked.extent)
            }.value
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
