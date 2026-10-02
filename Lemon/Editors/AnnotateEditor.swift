import SwiftUI

/// Draw on a picture: pen, highlighter, arrow, box, oval and text.
struct AnnotateEditor: View {
    let file: URL
    let onCancel: () -> Void
    let onApply: (ToolOptions) -> Void

    @State private var image: CGImage?
    @State private var marks: [AnnotationMark] = []
    @State private var drawing: AnnotationMark?
    @State private var tool = AnnotationMark.Kind.arrow
    @State private var color = RGBA.red
    @State private var width = 0.006
    @State private var text = "Text"

    private let palette: [RGBA] = [.red, .lemon, RGBA(r: 0.2, g: 0.78, b: 0.35), RGBA(r: 0.1, g: 0.5, b: 1), .white, .black]

    var body: some View {
        GlassShell(title: "Annotate", subtitle: file.lastPathComponent, onClose: onCancel) {
            HStack(spacing: 8) {
                Picker("Tool", selection: $tool) {
                    ForEach(AnnotationMark.Kind.allCases, id: \.self) { kind in
                        Image(systemName: symbol(kind)).help(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)

                ForEach(palette, id: \.self) { swatch in
                    Circle().fill(Color(cgColor: swatch.cgColor))
                        .overlay(Circle().stroke(.white, lineWidth: swatch == color ? 2.5 : 0.5))
                        .frame(width: 20, height: 20)
                        .onTapGesture { color = swatch }
                }
                Slider(value: $width, in: 0.002...0.02).frame(width: 100).tint(.lemonDeep)
                if tool == .text {
                    TextField("Text", text: $text).textFieldStyle(.roundedBorder).frame(width: 120)
                }
                Spacer()
            }
            FittedImage(image: image) { frame in canvas(frame) }
                .frame(minHeight: 360)
        } footer: {
            EditorFooter(canApply: !marks.isEmpty, onCancel: onCancel, onApply: { onApply(.annotate(marks)) }) {
                Button("Undo") { _ = marks.popLast() }.buttonStyle(.glass).disabled(marks.isEmpty)
                    .keyboardShortcut("z")
                Button("Clear") { marks.removeAll() }.buttonStyle(.glass).disabled(marks.isEmpty)
            }
        }
        .task { image = await MediaPreview.frame(of: file, maxPixels: 1600) }
    }

    private func symbol(_ kind: AnnotationMark.Kind) -> String {
        switch kind {
        case .pen: "pencil"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        }
    }

    private func canvas(_ frame: CGRect) -> some View {
        Canvas { context, _ in
            for mark in marks + (drawing.map { [$0] } ?? []) {
                draw(mark, in: frame, context: &context)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let p = normalized(value.location, frame)
                    if drawing == nil {
                        drawing = AnnotationMark(kind: tool, points: [p], color: color, lineWidth: width, text: text)
                    } else if tool == .pen || tool == .highlighter {
                        drawing?.points.append(p)
                    } else if tool != .text {
                        drawing?.points = [drawing!.points[0], p]
                    }
                }
                .onEnded { _ in
                    if let mark = drawing { marks.append(mark) }
                    drawing = nil
                }
        )
    }

    private func normalized(_ point: CGPoint, _ frame: CGRect) -> CGPoint {
        CGPoint(x: min(max((point.x - frame.minX) / frame.width, 0), 1),
                y: min(max((point.y - frame.minY) / frame.height, 0), 1))
    }

    /// Mirrors ImageTools.drawMarks so the preview matches the saved picture.
    private func draw(_ mark: AnnotationMark, in frame: CGRect, context: inout GraphicsContext) {
        let pts = mark.points.map { CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height) }
        guard let first = pts.first else { return }
        let line = mark.lineWidth * frame.width
        let shading = GraphicsContext.Shading.color(Color(cgColor: mark.color.cgColor))
        let style = StrokeStyle(lineWidth: mark.kind == .highlighter ? line * 4 : line, lineCap: .round, lineJoin: .round)
        switch mark.kind {
        case .pen, .highlighter:
            var path = Path(); path.move(to: first); pts.dropFirst().forEach { path.addLine(to: $0) }
            var layer = context
            if mark.kind == .highlighter { layer.opacity = 0.4; layer.blendMode = .multiply }
            layer.stroke(path, with: shading, style: style)
        case .arrow:
            guard let last = pts.last, last != first else { return }
            var path = Path(); path.move(to: first); path.addLine(to: last)
            context.stroke(path, with: shading, style: style)
            let angle = atan2(last.y - first.y, last.x - first.x), head = max(line * 4, 12 * frame.width / 1600)
            var tip = Path()
            tip.move(to: last)
            tip.addLine(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
            tip.addLine(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
            tip.closeSubpath()
            context.fill(tip, with: shading)
        case .rectangle, .ellipse:
            guard let last = pts.last else { return }
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
            context.stroke(mark.kind == .rectangle ? Path(rect) : Path(ellipseIn: rect), with: shading, style: style)
        case .text:
            let size = max(line * 7, 14 * frame.width / 1600)
            context.draw(Text(mark.text).font(.system(size: size, weight: .semibold)).foregroundStyle(Color(cgColor: mark.color.cgColor)),
                         at: first, anchor: .topLeading)
        }
    }
}
