import CoreImage
import SwiftUI

/// "Edit Photo": 22 adjustments with a live preview.
struct PhotoEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var source: CGImage?
    @State private var preview: CGImage?
    @State private var adjustments = PhotoAdjustments()
    @State private var showOriginal = false
    @State private var zoom: CGFloat = 1

    private struct Control: Identifiable {
        let title: String
        let key: WritableKeyPath<PhotoAdjustments, Double>
        var range: ClosedRange<Double> = -1...1
        var unit = ""
        var id: String { title }
    }

    private let groups: [(String, [Control])] = [
        ("Light", [
            Control(title: "Exposure", key: \.exposure, range: -3...3, unit: " EV"),
            Control(title: "Brightness", key: \.brightness), Control(title: "Contrast", key: \.contrast),
            Control(title: "Highlights", key: \.highlights), Control(title: "Shadows", key: \.shadows),
            Control(title: "Whites", key: \.whites), Control(title: "Blacks", key: \.blacks),
            Control(title: "Gamma", key: \.gamma),
        ]),
        ("Color", [
            Control(title: "Temperature", key: \.temperature), Control(title: "Tint", key: \.tint),
            Control(title: "Saturation", key: \.saturation), Control(title: "Vibrance", key: \.vibrance),
            Control(title: "Hue", key: \.hue),
        ]),
        ("Detail", [
            Control(title: "Clarity", key: \.clarity), Control(title: "Texture", key: \.texture),
            Control(title: "Sharpness", key: \.sharpness, range: 0...1),
            Control(title: "Noise Reduction", key: \.noiseReduction, range: 0...1),
            Control(title: "Blur", key: \.blur, range: 0...1),
        ]),
        ("Effects", [
            Control(title: "Dehaze", key: \.dehaze), Control(title: "Fade", key: \.fade),
            Control(title: "Vignette", key: \.vignette, range: 0...1), Control(title: "Grain", key: \.grain, range: 0...1),
        ]),
    ]

    var body: some View {
        GlassShell(title: "Edit Photo", subtitle: file.lastPathComponent, onClose: onCancel) {
            HStack(spacing: 14) {
                ScrollView([.horizontal, .vertical]) {
                    let shown = showOriginal ? source : (preview ?? source)
                    FittedImage(image: shown) { _ in EmptyView() }
                        .frame(width: 560 * zoom, height: 460 * zoom)
                }
                .frame(minWidth: 420, minHeight: 360)
                .background(.black.opacity(0.15), in: .rect(cornerRadius: 14))

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.0) { group in
                            Text(group.0.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(group.1) { control in slider(control) }
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(width: 250)
            }
        } footer: {
            EditorFooter(canApply: !adjustments.isUnchanged, onCancel: onCancel,
                         onApply: { onApply(.photo(adjustments)) }) {
                Toggle("Original", isOn: $showOriginal).toggleStyle(.button).buttonStyle(.glass)
                Button("Reset") { adjustments = PhotoAdjustments() }.buttonStyle(.glass)
                    .disabled(adjustments.isUnchanged)
                Picker("Zoom", selection: $zoom) {
                    Text("Fit").tag(CGFloat(1)); Text("150%").tag(CGFloat(1.5)); Text("200%").tag(CGFloat(2))
                }
                .labelsHidden().frame(width: 90)
            }
        }
        .task { source = await MediaPreview.frame(of: file, maxPixels: 1400) }
        .task(id: adjustments) { await render() }
    }

    private func slider(_ control: Control) -> some View {
        let value = Binding(get: { adjustments[keyPath: control.key] },
                            set: { adjustments[keyPath: control.key] = $0 })
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(control.title).font(.callout)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue) + control.unit)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: control.range)
                .tint(.lemonDeep)
                .controlSize(.small)
                .onTapGesture(count: 2) { value.wrappedValue = 0 }
        }
    }

    /// Renders the preview off the main thread; a newer change cancels an older render.
    private func render() async {
        guard let source else { return }
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else { return }
        let current = adjustments
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let output = PhotoFilter.apply(current, to: CIImage(cgImage: source))
            return PhotoFilter.context.createCGImage(output, from: output.extent)
        }.value
        if !Task.isCancelled { preview = image }
    }
}
