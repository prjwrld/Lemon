import SwiftUI

/// What the wheel is currently showing.
@Observable
final class WheelModel {
    var choices: [ImageFormat] = []
    var files: [URL] = []
    var hovered: Int?
    var isOpen = false

    var geometry: WheelGeometry { WheelGeometry(count: choices.count) }

    var hoveredChoice: ImageFormat? {
        hovered.flatMap { choices.indices.contains($0) ? choices[$0] : nil }
    }

    /// Short text for the middle: the file, or the action under the pointer.
    var centerTitle: String {
        if let choice = hoveredChoice { return "To \(choice.label)" }
        if files.count == 1 { return files[0].pathExtension.uppercased() }
        return "\(files.count) files"
    }

    var centerDetail: String {
        let bytes = files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : ""
    }
}

extension Color {
    static let lemon = Color(red: 1.0, green: 0.86, blue: 0.12)
}

/// The round glass wheel. Uses Apple's Liquid Glass for each slice.
struct WheelView: View {
    let model: WheelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let geometry = model.geometry

        ZStack {
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    ForEach(Array(model.choices.enumerated()), id: \.element) { index, choice in
                        slice(choice, at: index, geometry: geometry)
                    }
                }
            }

            VStack(spacing: 1) {
                Text(model.centerTitle)
                    .font(.system(size: 13, weight: .bold))
                if !model.centerDetail.isEmpty {
                    Text(model.centerDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: geometry.holeDiameter - 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
        .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.82)
        .opacity(model.isOpen ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.25), value: model.isOpen)
        // Hover changes are instant, as they should feel immediate.
        .animation(nil, value: model.hovered)
    }

    private func slice(_ choice: ImageFormat, at index: Int, geometry: WheelGeometry) -> some View {
        let isHovered = model.hovered == index
        return Text(choice.label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(isHovered ? Color.black : Color.primary)
            // A soft halo keeps the label readable over busy backgrounds.
            .shadow(color: isHovered ? .clear : Color(nsColor: .windowBackgroundColor).opacity(0.9), radius: 3)
            .offset(geometry.labelOffset(of: index))
            .frame(width: geometry.diameter, height: geometry.diameter)
            // Glass tint alone is too faint over dark backgrounds, so add a clear yellow fill.
            .background {
                if isHovered {
                    RingSlice(geometry: geometry, index: index).fill(Color.lemon.opacity(0.85))
                }
            }
            .glassEffect(
                isHovered ? .regular.tint(.lemon).interactive() : .regular.interactive(),
                in: RingSlice(geometry: geometry, index: index)
            )
    }
}

#Preview {
    let model = WheelModel()
    model.choices = [.png, .heic, .tiff]
    model.files = [URL(fileURLWithPath: "/tmp/photo.jpg")]
    model.hovered = 0
    model.isOpen = true
    return WheelView(model: model)
        .padding(40)
        .background(LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
}
