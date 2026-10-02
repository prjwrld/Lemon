import SwiftUI

/// Draw boxes over things to hide; works on pictures and on a video frame.
struct RedactEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var image: CGImage?
    @State private var boxes: [CGRect] = []
    @State private var drawing: CGRect?
    @State private var start: CGPoint?
    @State private var style = RedactStyle.black

    private var isVideo: Bool { FileKind(file: file) != .image && FileKind(file: file) != .svg }

    var body: some View {
        GlassShell(title: "Redact", subtitle: isVideo ? "\(file.lastPathComponent) — boxes apply to the whole video" : file.lastPathComponent,
                   onClose: onCancel) {
            FittedImage(image: image) { frame in overlay(frame) }
                .frame(minHeight: 360)
            HStack {
                Picker("Style", selection: $style) {
                    ForEach(RedactStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                Text("Drag to cover an area. Click a box to remove it.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        } footer: {
            EditorFooter(canApply: !boxes.isEmpty, onCancel: onCancel, onApply: { onApply(.redact(boxes, style)) }) {
                Button("Clear") { boxes.removeAll() }.buttonStyle(.glass).disabled(boxes.isEmpty)
            }
        }
        .task { image = await MediaPreview.frame(of: file, at: 0.5, maxPixels: 1600) }
    }

    private func overlay(_ frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let a = normalized(value.startLocation, frame), b = normalized(value.location, frame)
                        drawing = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                    }
                    .onEnded { _ in
                        if let box = drawing, box.width > 0.005, box.height > 0.005 { boxes.append(box) }
                        drawing = nil
                    })
            ForEach(Array((boxes + (drawing.map { [$0] } ?? [])).enumerated()), id: \.offset) { index, box in
                let rect = CGRect(x: frame.minX + box.minX * frame.width, y: frame.minY + box.minY * frame.height,
                                  width: box.width * frame.width, height: box.height * frame.height)
                sample
                    .frame(width: rect.width, height: rect.height)
                    .overlay(Rectangle().stroke(Color.lemon, lineWidth: 1.5))
                    .offset(x: rect.minX, y: rect.minY)
                    .onTapGesture { if index < boxes.count { boxes.remove(at: index) } }
            }
        }
    }

    @ViewBuilder private var sample: some View {
        switch style {
        case .black: Color.black
        case .pixelate: Rectangle().fill(.gray.opacity(0.6)).overlay(Image(systemName: "square.grid.3x3.fill").foregroundStyle(.white.opacity(0.6)))
        case .blur: Rectangle().fill(.ultraThinMaterial)
        }
    }

    private func normalized(_ point: CGPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - frame.minX) / frame.width, 0), 1),
                y: min(max((point.y - frame.minY) / frame.height, 0), 1))
    }
}
