import SwiftUI

/// What the wheel is currently showing.
@Observable
final class WheelModel {
    var choices: [ImageFormat] = []
    var files: [URL] = [] {
        didSet { summarizeFiles() }
    }
    var hovered: Int?
    var isOpen = false

    /// e.g. "2 MIXED FILES" — empty for a single file.
    private(set) var fileCountText = ""
    /// e.g. "6 KB".
    private(set) var sizeText = ""

    var geometry: WheelGeometry { WheelGeometry(count: choices.count) }

    var hoveredChoice: ImageFormat? {
        hovered.flatMap { choices.indices.contains($0) ? choices[$0] : nil }
    }

    private func summarizeFiles() {
        let bytes = files.reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        sizeText = bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : ""

        let kinds = Set(files.map { $0.pathExtension.lowercased() })
        fileCountText = files.count < 2 ? "" : "\(files.count) \(kinds.count > 1 ? "MIXED " : "")FILES"
    }
}

extension Color {
    static let lemon = Color(red: 1.0, green: 0.86, blue: 0.12)
    static let lemonDeep = Color(red: 0.98, green: 0.70, blue: 0.05)
}

/// The round glass wheel, built from Apple's Liquid Glass.
///
/// Following Apple's guidance for `Glass.clear`, each clear glass shape sits on a
/// tinted layer that keeps labels readable:
/// - the plate: clear glass over a dark layer (you see the desktop through it, bent at the rim)
/// - the slices: clear, interactive glass over a light layer, in one container
/// - the middle: a dark well with a small regular-glass capsule
struct WheelView: View {
    let model: WheelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let geometry = model.geometry

        ZStack {
            plate(geometry)

            // Spacing 0 keeps the slices apart; a larger value would blend them together.
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    ForEach(Array(model.choices.enumerated()), id: \.element) { index, choice in
                        slice(choice, at: index, geometry: geometry)
                    }
                }
            }

            centerLabel
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
        // The wheel always uses the dark glass look, like a HUD.
        .environment(\.colorScheme, .dark)
        .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.86)
        .opacity(model.isOpen ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.22), value: model.isOpen)
        // Hover changes are instant, as they should feel immediate.
        .animation(nil, value: model.hovered)
    }

    /// A thin highlight along glass edges, brighter at the top as if lit from above.
    private static let edgeLight = LinearGradient(
        colors: [.white.opacity(0.38), .white.opacity(0.08), .white.opacity(0.18)],
        startPoint: .top, endPoint: .bottom
    )

    /// With Reduce Transparency on, the glass is replaced by solid colours.
    private var clearGlass: Glass { reduceTransparency ? .identity : .clear }

    /// The dark glass disc behind the slices, with its dark middle.
    private func plate(_ geometry: WheelGeometry) -> some View {
        ZStack {
            Color.clear
                .glassEffect(clearGlass, in: .circle)
                .background(Circle().fill(.black.opacity(reduceTransparency ? 0.92 : 0.55)))
                .overlay(Circle().strokeBorder(Self.edgeLight, lineWidth: 1))

            Circle()
                .fill(.black.opacity(reduceTransparency ? 0.95 : 0.38))
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1.5))
                .frame(width: geometry.holeDiameter - 10, height: geometry.holeDiameter - 10)
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
    }

    private func slice(_ choice: ImageFormat, at index: Int, geometry: WheelGeometry) -> some View {
        let isHovered = model.hovered == index
        let shape = RingSlice(geometry: geometry, index: index)
        return Text(choice.label)
            .font(.system(size: 12.5, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(isHovered ? Color.black.opacity(0.85) : Color.white)
            .shadow(color: .black.opacity(isHovered ? 0 : 0.4), radius: 2, y: 1)
            .offset(geometry.labelOffset(of: index))
            .frame(width: geometry.diameter, height: geometry.diameter)
            .overlay(shape.stroke(Self.edgeLight, lineWidth: 1))
            .glassEffect(isHovered ? clearGlass.tint(.lemon).interactive() : clearGlass.interactive(), in: shape)
            .background {
                if isHovered {
                    shape.fill(LinearGradient(colors: [.lemonDeep, .lemon], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(.white.opacity(reduceTransparency ? 0.22 : 0.10))
                }
            }
    }

    /// The small glass capsule in the middle: file size, or the format under the pointer.
    private var centerLabel: some View {
        VStack(spacing: 1) {
            if let choice = model.hoveredChoice {
                Text(choice.label)
            } else {
                if !model.fileCountText.isEmpty { Text(model.fileCountText) }
                if !model.sizeText.isEmpty {
                    Text(model.sizeText)
                } else if model.fileCountText.isEmpty, let file = model.files.first {
                    Text(file.pathExtension.uppercased())
                }
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minWidth: 76, maxWidth: model.geometry.holeDiameter - 12)
        .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
    }
}

#Preview {
    let model = WheelModel()
    model.choices = [.png, .heic, .tiff, .avif, .bmp, .gif, .pdf]
    model.files = [URL(fileURLWithPath: "/tmp/photo.jpg")]
    model.hovered = 0
    model.isOpen = true
    return WheelView(model: model)
        .padding(40)
        .background(LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
}
