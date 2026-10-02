import SwiftUI

/// Arrange several pictures in a grid, with a live preview.
struct CollageEditor: View {
    let files: [URL]
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var images: [CGImage] = []
    @State private var preview: CGImage?
    @State private var layout = CollageLayout()
    @State private var background = Color.white

    var body: some View {
        GlassShell(title: "Collage", subtitle: "\(files.count) pictures", onClose: onCancel) {
            FittedImage(image: preview) { _ in EmptyView() }
                .frame(minHeight: 360)
            HStack(spacing: 16) {
                Stepper("Columns: \(layout.columns)", value: $layout.columns, in: 1...max(1, files.count))
                HStack { Text("Spacing"); Slider(value: $layout.spacing, in: 0...0.06).frame(width: 120).tint(.lemonDeep) }
                Toggle("Fill cells", isOn: $layout.fill)
                ColorPicker("Background", selection: $background)
                Spacer()
            }
        } footer: {
            EditorFooter(canApply: !images.isEmpty, onCancel: onCancel, onApply: { onApply(.collage(layout)) })
        }
        .task {
            images = await Task.detached { files.compactMap { try? ImageEngine.load($0, maxPixels: 700) } }.value
            layout.columns = Int(ceil(Double(files.count).squareRoot()))
        }
        .task(id: layout) { render() }
        .onChange(of: background) {
            let ns = NSColor(background).usingColorSpace(.sRGB) ?? .white
            layout.background = RGBA(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent)
        }
    }

    private func render() {
        guard !images.isEmpty else { return }
        preview = try? ImageTools.renderCollage(images, layout, width: 1000)
    }
}
