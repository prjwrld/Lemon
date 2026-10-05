import AppKit
import SwiftUI

/// The wheel's measurements, and the maths for "which slice is at this point?".
/// Shared by the drawing (SwiftUI) and the drop handling (AppKit) so they agree.
nonisolated struct WheelGeometry: Equatable, Sendable {
    var diameter: CGFloat = 250      // the dark glass plate
    var plateMargin: CGFloat = 7     // plate edge → outside of the slices
    var holeDiameter: CGFloat = 94   // the dark middle
    var gap: CGFloat = 6             // even-width space between slices
    var outerCorner: CGFloat = 13
    var innerCorner: CGFloat = 8
    var count: Int

    var outerRadius: CGFloat { diameter / 2 - plateMargin }
    var innerRadius: CGFloat { holeDiameter / 2 }
    var middleRadius: CGFloat { (outerRadius + innerRadius) / 2 }
    var step: CGFloat { 2 * .pi / CGFloat(max(count, 1)) }

    /// The centre angle of a slice. Slice 0 is centred at the top; the rest go clockwise.
    /// (Radians; with y pointing down, clockwise is positive.)
    func centerAngle(of index: Int) -> CGFloat {
        -.pi / 2 + step * CGFloat(index)
    }

    /// A slice's edges at a given distance from the centre. The gap is trimmed
    /// as a fixed width (not a fixed angle), so the gaps have straight, parallel sides.
    func angles(of index: Int, at radius: CGFloat) -> (start: CGFloat, end: CGFloat) {
        let center = centerAngle(of: index)
        let trim = asin(min(1, (gap / 2) / radius))
        return (center - step / 2 + trim, center + step / 2 - trim)
    }

    /// Where a slice's label goes, measured from the wheel's centre.
    func labelOffset(of index: Int) -> CGSize {
        let angle = centerAngle(of: index)
        return CGSize(width: cos(angle) * middleRadius, height: sin(angle) * middleRadius)
    }

    // MARK: Label layout

    /// Where a slice's label goes and how wide its text may be, so it stays inside the card.
    struct LabelPlacement: Equatable, Sendable {
        /// The label's centre, measured from the wheel's centre (y pointing down).
        var center: CGSize
        /// The widest the text line can be here; longer words shrink to fit.
        var textWidth: CGFloat
        /// True if the text sits above the icon (used on upper cards, where the outer side is wider).
        var textFirst: Bool
    }

    /// Slices are wedges, narrow near the middle and wide at the rim, and a horizontal
    /// word fits differently in each. This tries the label a little further in or out, and
    /// with the name above or below the icon, and keeps the spot where the name fits best.
    ///
    /// For a tidy wheel, names sit on the rim side of their card (above the icon on upper
    /// cards, below it elsewhere) and near the card's middle, unless another spot lets a
    /// long name be clearly larger.
    /// - Parameters:
    ///   - textHeight: height of the text line.
    ///   - neededWidth: the name's width at full size.
    ///   - iconSize: the icon's width and height, or nil for text-only labels.
    ///   - spacing: space between icon and name.
    func labelPlacement(of index: Int, textHeight: CGFloat, neededWidth: CGFloat,
                        iconSize: CGSize?, spacing: CGFloat) -> LabelPlacement {
        let angle = centerAngle(of: index)
        let blockHeight = textHeight + (iconSize.map { $0.height + spacing } ?? 0)
        let rimSideIsUp = sin(angle) < -0.25
        var best = LabelPlacement(center: labelOffset(of: index), textWidth: neededWidth, textFirst: false)
        var bestScore = -CGFloat.infinity

        for shift in stride(from: -12.0, through: 16.0, by: 2.0) {
            let radius = middleRadius + shift
            let center = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            for textFirst in iconSize == nil ? [false] : [true, false] {
                // The name is the top or bottom part of the block; the icon is the other part.
                let textY = center.y + (textFirst ? -1 : 1) * (blockHeight - textHeight) / 2
                if let icon = iconSize {
                    let iconY = center.y + (textFirst ? 1 : -1) * (blockHeight - icon.height) / 2
                    guard widestRect(at: CGPoint(x: center.x, y: iconY), height: icon.height, slice: index) >= icon.width + 2
                    else { continue }
                }
                let room = widestRect(at: CGPoint(x: center.x, y: textY), height: textHeight, slice: index)
                let size = min(room / max(neededWidth, 1), 1)              // 1 = full size, smaller = shrunk
                let tidy = iconSize == nil || textFirst == rimSideIsUp
                let score = size * 100 - abs(shift) * 0.3 + (tidy ? 4 : 0)
                if score > bestScore {
                    bestScore = score
                    best = LabelPlacement(center: CGSize(width: center.x, height: center.y),
                                          textWidth: min(room, neededWidth + 4), textFirst: textFirst)
                }
            }
        }
        return best
    }

    /// The widest rectangle of this height, centred on a point, that fits inside a slice
    /// with a little breathing room (found by halving the range a few times).
    private func widestRect(at center: CGPoint, height: CGFloat, slice index: Int) -> CGFloat {
        let padding: CGFloat = 4
        let angle = centerAngle(of: index)
        func inside(_ p: CGPoint) -> Bool {
            let r = hypot(p.x, p.y)
            // The extra 3 points keep clear of the card's rounded outer corners.
            guard r >= innerRadius + padding, r <= outerRadius - padding - 3 else { return false }
            var delta = atan2(p.y, p.x) - angle
            delta = (delta + .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if delta < 0 { delta += 2 * .pi }
            delta -= .pi
            let half = step / 2
            guard abs(delta) < half else { return false }
            return r * sin(half - abs(delta)) >= gap / 2 + padding
        }
        var low: CGFloat = 0, high: CGFloat = 120
        for _ in 0..<20 {
            let width = (low + high) / 2
            let fits = [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)].allSatisfy { sx, sy in
                inside(CGPoint(x: center.x + sx * width / 2, y: center.y + sy * height / 2))
            }
            if fits { low = width } else { high = width }
        }
        return low
    }

    /// The slice under a point (measured from the centre, y pointing down), if any.
    func slice(at point: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance >= innerRadius - 2, distance <= diameter / 2 + 16 else { return nil }
        var angle = atan2(point.y, point.x) + .pi / 2 + step / 2   // 0 = left edge of slice 0
        angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if angle < 0 { angle += 2 * .pi }
        return min(Int(angle / step), count - 1)
    }
}

/// One rounded ring slice, drawn to fill the whole wheel-sized frame.
nonisolated struct RingSlice: Shape {
    var geometry: WheelGeometry
    var index: Int

    func path(in rect: CGRect) -> Path {
        let g = geometry
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r1 = g.innerRadius, r2 = g.outerRadius
        let (o0, o1) = g.angles(of: index, at: r2)
        let (i0, i1) = g.angles(of: index, at: r1)
        let cOut = min(g.outerCorner, (r2 - r1) / 2)
        let cIn = min(g.innerCorner, (r2 - r1) / 2, (i1 - i0) * r1 / 2)

        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }

        // Corners are joined with addArc(tangent1End:...), which treats the curved
        // edge as nearly straight near the corner. At this size it looks right.
        var path = Path()
        path.move(to: CGPoint(x: (point(r1, i0).x + point(r2, o0).x) / 2,
                              y: (point(r1, i0).y + point(r2, o0).y) / 2))
        path.addArc(tangent1End: point(r2, o0), tangent2End: point(r2, o0 + 2 * cOut / r2), radius: cOut)
        path.addArc(center: center, radius: r2,
                    startAngle: .radians(o0 + cOut / r2), endAngle: .radians(o1 - cOut / r2),
                    clockwise: false)
        path.addArc(tangent1End: point(r2, o1), tangent2End: point(r1, i1), radius: cOut)
        path.addArc(tangent1End: point(r1, i1), tangent2End: point(r1, i1 - 2 * cIn / r1), radius: cIn)
        path.addArc(center: center, radius: r1,
                    startAngle: .radians(i1 - cIn / r1), endAngle: .radians(i0 + cIn / r1),
                    clockwise: true)
        path.addArc(tangent1End: point(r1, i0), tangent2End: point(r2, o0), radius: cIn)
        path.closeSubpath()
        return path
    }
}

// MARK: - Label style

extension WheelGeometry {
    /// Label fonts and sizes, shared by the layout, the drawing and the tests.
    enum LabelStyle {
        static let formatFontSize: CGFloat = 13.5
        static let formatTracking: CGFloat = 0.3
        static let formatTextHeight: CGFloat = 17
        static let toolFontSize: CGFloat = 9.5
        static let toolTracking: CGFloat = 0.2
        static let toolTextHeight: CGFloat = 12
        static let iconSize = CGSize(width: 24, height: 20)
        static let iconSpacing: CGFloat = 3
        /// Names may shrink to this share of their size to fit (the tests check none need more).
        static let minimumScale: CGFloat = 0.6
    }

    /// Where every choice's label goes on a wheel of these choices.
    static func labelPlacements(for choices: [Action]) -> [LabelPlacement] {
        let geometry = WheelGeometry(count: choices.count)
        return choices.indices.map { index in
            let choice = choices[index]
            let isTool = choice.symbol != nil
            return geometry.labelPlacement(
                of: index,
                textHeight: isTool ? LabelStyle.toolTextHeight : LabelStyle.formatTextHeight,
                neededWidth: textWidth(of: choice),
                iconSize: isTool ? LabelStyle.iconSize : nil,
                spacing: LabelStyle.iconSpacing)
        }
    }

    /// A label's width at full size, measured in the wheel's font.
    static func textWidth(of choice: Action) -> CGFloat {
        let isTool = choice.symbol != nil
        let font = NSFont.systemFont(ofSize: isTool ? LabelStyle.toolFontSize : LabelStyle.formatFontSize, weight: .bold)
        let tracking = isTool ? LabelStyle.toolTracking : LabelStyle.formatTracking
        return ceil((choice.label as NSString).size(withAttributes: [.font: font, .kern: tracking]).width) + 2
    }
}
