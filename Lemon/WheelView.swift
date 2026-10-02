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
        colors: [.white.opacity(0.65), .white.opacity(0.12), .white.opacity(0.30)],
        startPoint: .top, endPoint: .bottom
    )

    /// A soft diagonal shine across each piece of glass, like light catching its surface.
    private static let sheen = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.24), location: 0),
            .init(color: .white.opacity(0.05), location: 0.4),
            .init(color: .clear, location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// With Reduce Transparency on, the glass is replaced by solid colours.
    private var clearGlass: Glass { reduceTransparency ? .identity : .clear }

    /// The glass used for the cards (slices and middle pill). Try the others with
    /// `defaults write com.prajwal.Lemon LemonCardGlass frosted` (or `stained`, `clear`).
    private var cardGlass: Glass {
        if reduceTransparency { return .identity }
        switch UserDefaults.standard.string(forKey: "LemonCardGlass") {
        case "frosted": return .regular                       // blurs what's behind
        case "stained": return .clear.tint(.white.opacity(0.22)) // clear glass, lightly coloured
        default: return .clear                                // most see-through
        }
    }

    /// Clear glass gets a light grey layer underneath, so cards read as grey glass
    /// (lighter than the ring around them) and labels stay readable. The others don't need it.
    private var cardFrost: Double {
        if reduceTransparency { return 0.22 }
        let style = UserDefaults.standard.string(forKey: "LemonCardGlass") ?? "clear"
        return style == "clear" ? 0.10 : 0
    }

    /// The see-through glass disc behind the slices.
    private func plate(_ geometry: WheelGeometry) -> some View {
        ZStack {
            dropShadow(geometry)

            Color.clear
                .glassEffect(clearGlass, in: .circle)
                .background(Circle().fill(plateDimming(geometry)))
                .overlay(Circle().strokeBorder(Self.edgeLight, lineWidth: 1.2))

        }
        .frame(width: geometry.diameter, height: geometry.diameter)
    }

    /// A soft shadow around (never under) the plate, so the wheel floats like system glass.
    private func dropShadow(_ geometry: WheelGeometry) -> some View {
        Circle()
            .fill(.black.opacity(reduceTransparency ? 0 : 0.35))
            .blur(radius: 14)
            .offset(y: 6)
            .mask {
                Rectangle()
                    .frame(width: geometry.diameter + 60, height: geometry.diameter + 60)
                    .overlay(Circle().frame(width: geometry.diameter - 2, height: geometry.diameter - 2).blendMode(.destinationOut))
                    .compositingGroup()
            }
    }

    /// The whole plate stays almost fully see-through, so the glass bends what's behind it.
    private func plateDimming(_ geometry: WheelGeometry) -> RadialGradient {
        if reduceTransparency {
            return RadialGradient(colors: [.black.opacity(0.92)], center: .center, startRadius: 0, endRadius: 1)
        }
        return RadialGradient(
            colors: [.black.opacity(0.10), .black.opacity(0.04)],
            center: .center, startRadius: 0, endRadius: geometry.diameter / 2
        )
    }

    private func slice(_ choice: ImageFormat, at index: Int, geometry: WheelGeometry) -> some View {
        let isHovered = model.hovered == index
        let shape = RingSlice(geometry: geometry, index: index)
        return Text(choice.label)
            .font(.system(size: 13.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(isHovered ? Color.black.opacity(0.85) : Color.white)
            .shadow(color: .black.opacity(isHovered ? 0 : 0.25), radius: 1, y: 0.5)
            .offset(geometry.labelOffset(of: index))
            .frame(width: geometry.diameter, height: geometry.diameter)
            .background(shape.fill(Self.sheen))
            .overlay(bevel(shape))
            .overlay(shape.stroke(Self.edgeLight, lineWidth: 1))
            .glassEffect(isHovered ? cardGlass.tint(.lemon).interactive() : cardGlass.interactive(), in: shape)
            .background {
                if isHovered {
                    shape.fill(LinearGradient(colors: [.lemonDeep, .lemon], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(.white.opacity(cardFrost))
                }
            }
    }

    /// A soft dark edge inside the bottom of a card, so it looks like a thick piece of glass.
    private func bevel(_ shape: RingSlice) -> some View {
        shape
            .stroke(LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
            .blur(radius: 2)
            .clipShape(shape)
            .opacity(reduceTransparency ? 0 : 1)
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
        // Two lines ("2 MIXED FILES" + size) use smaller text so the pill keeps its shape.
        .font(.system(size: isTwoLines ? 8 : 11.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        // A short, chunky pill with space around it, as in the reference.
        .frame(width: 66, height: 30)
        // Same glass as the slices, so the pill looks like one of them.
        .background(Capsule().fill(Self.sheen))
        .overlay(Capsule().stroke(Self.edgeLight, lineWidth: 1))
        .glassEffect(cardGlass, in: .capsule)
        .background(Capsule().fill(.white.opacity(cardFrost)))
    }

    private var isTwoLines: Bool {
        model.hoveredChoice == nil && !model.fileCountText.isEmpty && !model.sizeText.isEmpty
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
