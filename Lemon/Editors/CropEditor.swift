import SwiftUI

/// Crop for pictures, videos and GIFs: aspect presets, pixel size, eight handles.
struct CropEditor: View {
    let file: URL
    let fileCount: Int
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    enum Aspect: String, CaseIterable, Identifiable {
        case free = "Free", square = "1:1", wide = "16:9", tall = "9:16", classic = "4:3", portrait = "3:4"
        var id: String { rawValue }
        var ratio: CGFloat? {
            switch self {
            case .free: nil
            case .square: 1
            case .wide: 16 / 9
            case .tall: 9 / 16
            case .classic: 4 / 3
            case .portrait: 3 / 4
            }
        }
    }

    @State private var image: CGImage?
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)   // 0…1, top-left origin
    @State private var aspect = Aspect.free
    @State private var dragStart: CGRect?

    /// The file's real size; the preview image is often scaled down.
    @State private var realSize: CGSize?

    private var pixelSize: CGSize { realSize ?? CGSize(width: image?.width ?? 1, height: image?.height ?? 1) }

    /// True while the crop still covers the whole picture (cropping would change nothing).
    private var isWholePicture: Bool {
        rect.width * pixelSize.width > pixelSize.width - 1 && rect.height * pixelSize.height > pixelSize.height - 1
    }

    var body: some View {
        GlassShell(title: "Crop", subtitle: subtitle, onClose: onCancel) {
            FittedImage(image: image) { frame in cropOverlay(frame) }
                .frame(minHeight: 320)
            HStack(spacing: 12) {
                Picker("Aspect", selection: $aspect) {
                    ForEach(Aspect.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: aspect) { applyAspect() }

                Spacer()
                sizeField("W", value: Int((rect.width * pixelSize.width).rounded())) { setWidth($0) }
                Text("×").foregroundStyle(.secondary)
                sizeField("H", value: Int((rect.height * pixelSize.height).rounded())) { setHeight($0) }
                Text("px").foregroundStyle(.secondary)
            }
        } footer: {
            EditorFooter(canApply: image != nil && !isWholePicture, onCancel: onCancel, onApply: { onApply(.crop(rect)) }) {
                Button("Reset") { aspect = .free; rect = CGRect(x: 0, y: 0, width: 1, height: 1) }.buttonStyle(.glass)
            }
        }
        .task {
            realSize = await MediaPreview.pixelSize(of: file)
            image = await MediaPreview.frame(of: file, at: 0.5)
        }
    }

    private var subtitle: String {
        fileCount > 1 ? "\(file.lastPathComponent) — the same crop is used for all \(fileCount) files" : file.lastPathComponent
    }

    private func sizeField(_ label: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        TextField(label, value: Binding(get: { value }, set: { set($0) }), format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .multilineTextAlignment(.trailing)
    }

    // MARK: Overlay

    private func cropOverlay(_ frame: CGRect) -> some View {
        let box = CGRect(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height,
                         width: rect.width * frame.width, height: rect.height * frame.height)
        return ZStack(alignment: .topLeading) {
            // Darken everything outside the crop.
            Path { path in
                path.addRect(frame)
                path.addRect(box)
            }
            .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(.white, lineWidth: 1.5)
                .overlay(thirdsGrid)
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
                .contentShape(Rectangle())
                .gesture(dragGesture(frame: frame, edges: [.move]))

            ForEach(Handle.all, id: \.self) { handle in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.3)))
                    .frame(width: 13, height: 13)
                    .position(x: box.minX + box.width * handle.x, y: box.minY + box.height * handle.y)
                    .gesture(dragGesture(frame: frame, edges: handle.edges))
            }
        }
    }

    private var thirdsGrid: some View {
        GeometryReader { proxy in
            Path { path in
                for i in 1...2 {
                    let x = proxy.size.width * CGFloat(i) / 3, y = proxy.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    enum Edge { case left, right, top, bottom, move }

    struct Handle: Hashable {
        let x: CGFloat, y: CGFloat
        var edges: Set<Edge> {
            var set: Set<Edge> = []
            if x == 0 { set.insert(.left) }
            if x == 1 { set.insert(.right) }
            if y == 0 { set.insert(.top) }
            if y == 1 { set.insert(.bottom) }
            return set
        }
        static let all = [Handle(x: 0, y: 0), Handle(x: 0.5, y: 0), Handle(x: 1, y: 0), Handle(x: 1, y: 0.5),
                          Handle(x: 1, y: 1), Handle(x: 0.5, y: 1), Handle(x: 0, y: 1), Handle(x: 0, y: 0.5)]
    }

    private func dragGesture(frame: CGRect, edges: Set<Edge>) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? rect
                if dragStart == nil { dragStart = rect }
                let dx = value.translation.width / frame.width, dy = value.translation.height / frame.height
                var r = start
                let minSize: CGFloat = 0.03
                if edges.contains(.move) {
                    r.origin.x = min(max(start.minX + dx, 0), 1 - start.width)
                    r.origin.y = min(max(start.minY + dy, 0), 1 - start.height)
                } else {
                    var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
                    if edges.contains(.left) { minX = min(max(0, start.minX + dx), maxX - minSize) }
                    if edges.contains(.right) { maxX = max(min(1, start.maxX + dx), minX + minSize) }
                    if edges.contains(.top) { minY = min(max(0, start.minY + dy), maxY - minSize) }
                    if edges.contains(.bottom) { maxY = max(min(1, start.maxY + dy), minY + minSize) }
                    r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    if let ratio = aspect.ratio {
                        // Keep the shape: height follows width (in real pixels).
                        r.size.height = r.width * pixelSize.width / pixelSize.height / ratio
                        if edges.contains(.top) { r.origin.y = start.maxY - r.height }
                        r = clampInside(r)
                    }
                }
                rect = r
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: Aspect and size

    private func applyAspect() {
        guard let ratio = aspect.ratio else { return }
        // The largest centred rectangle with this shape.
        let imageRatio = pixelSize.width / pixelSize.height
        var w: CGFloat = 1, h: CGFloat = 1
        if ratio > imageRatio { h = imageRatio / ratio } else { w = ratio / imageRatio }
        rect = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    private func setWidth(_ pixels: Int) {
        let w = min(max(CGFloat(pixels) / pixelSize.width, 0.01), 1)
        var r = rect
        r.origin.x = rect.midX - w / 2
        r.size.width = w
        if let ratio = aspect.ratio { r.size.height = w * pixelSize.width / pixelSize.height / ratio; r.origin.y = rect.midY - r.height / 2 }
        rect = clampInside(r)
    }

    private func setHeight(_ pixels: Int) {
        let h = min(max(CGFloat(pixels) / pixelSize.height, 0.01), 1)
        var r = rect
        r.origin.y = rect.midY - h / 2
        r.size.height = h
        if let ratio = aspect.ratio { r.size.width = h * pixelSize.height * ratio / pixelSize.width; r.origin.x = rect.midX - r.width / 2 }
        rect = clampInside(r)
    }

    private func clampInside(_ r: CGRect) -> CGRect {
        var r = r
        r.size.width = min(r.width, 1)
        r.size.height = min(r.height, 1)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        return r
    }
}
