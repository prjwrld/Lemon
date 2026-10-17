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
        // A point inside the slice, to tell which side of each edge is inside.
        let inside = point((r1 + r2) / 2, (o0 + o1 + i0 + i1) / 4)
        let startSide = (inner: point(r1, i0), outer: point(r2, o0))
        let endSide = (inner: point(r1, i1), outer: point(r2, o1))

        // The four rounded corners, each exactly tangent to its straight side and to its circle,
        // so the outline runs on smoothly with no kinks where a corner meets a curved edge.
        let a = Self.fillet(side: startSide, toward: inside, circleRadius: r2, outer: true, radius: cOut, center: center)
        let b = Self.fillet(side: endSide, toward: inside, circleRadius: r2, outer: true, radius: cOut, center: center)
        let c = Self.fillet(side: endSide, toward: inside, circleRadius: r1, outer: false, radius: cIn, center: center)
        let d = Self.fillet(side: startSide, toward: inside, circleRadius: r1, outer: false, radius: cIn, center: center)

        var path = Path()
        path.move(to: a.onSide)
        path.addArc(tangent1End: a.corner, tangent2End: a.onCircle, radius: cOut)
        let outerStart = Self.angle(of: a.onCircle, from: center)
        path.addArc(center: center, radius: r2, startAngle: .radians(outerStart),
                    endAngle: .radians(outerStart + Self.turn(Self.angle(of: b.onCircle, from: center) - outerStart)),
                    clockwise: false)
        path.addArc(tangent1End: b.corner, tangent2End: b.onSide, radius: cOut)
        path.addLine(to: c.onSide)
        path.addArc(tangent1End: c.corner, tangent2End: c.onCircle, radius: cIn)
        let innerStart = Self.angle(of: c.onCircle, from: center)
        path.addArc(center: center, radius: r1, startAngle: .radians(innerStart),
                    endAngle: .radians(innerStart - Self.turn(innerStart - Self.angle(of: d.onCircle, from: center))),
                    clockwise: true)
        path.addArc(tangent1End: d.corner, tangent2End: d.onSide, radius: cIn)
        path.closeSubpath()
        return path
    }

    /// Where a rounded corner of radius `radius` touches a slice's straight side and one of its circles, and the
    /// point where those two edges' tangents meet (what `addArc(tangent1End:tangent2End:radius:)` needs).
    private struct Fillet { var onSide: CGPoint; var onCircle: CGPoint; var corner: CGPoint }

    private static func fillet(side: (inner: CGPoint, outer: CGPoint), toward inside: CGPoint, circleRadius: CGFloat,
                               outer: Bool, radius: CGFloat, center: CGPoint) -> Fillet {
        let a = side.inner
        var u = CGVector(dx: side.outer.x - a.x, dy: side.outer.y - a.y)
        let length = max(hypot(u.dx, u.dy), 0.0001)
        u = CGVector(dx: u.dx / length, dy: u.dy / length)
        // The side's normal, pointing into the slice.
        var n = CGVector(dx: -u.dy, dy: u.dx)
        if n.dx * (inside.x - a.x) + n.dy * (inside.y - a.y) < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }

        // The corner circle's centre: `radius` in from the side, and touching the slice's circle
        // (inside the outer circle, outside the inner one).
        let distance = outer ? circleRadius - radius : circleRadius + radius
        let p = CGPoint(x: a.x + n.dx * radius - center.x, y: a.y + n.dy * radius - center.y)
        let pu = p.x * u.dx + p.y * u.dy
        let root = (pu * pu - (p.x * p.x + p.y * p.y - distance * distance)).squareRoot()
        let end = outer ? side.outer : side.inner
        let candidates = [-pu + root, -pu - root].map { t in
            CGPoint(x: a.x + n.dx * radius + u.dx * t, y: a.y + n.dy * radius + u.dy * t)
        }
        let f = candidates.min { hypot($0.x - end.x, $0.y - end.y) < hypot($1.x - end.x, $1.y - end.y) }!

        let onSide = CGPoint(x: f.x - n.dx * radius, y: f.y - n.dy * radius)
        let scale = circleRadius / distance
        let onCircle = CGPoint(x: center.x + (f.x - center.x) * scale, y: center.y + (f.y - center.y) * scale)
        // Where the side meets the circle's tangent at `onCircle`.
        let v = CGVector(dx: -(onCircle.y - center.y), dy: onCircle.x - center.x)
        let det = u.dx * v.dy - u.dy * v.dx
        let s = abs(det) < 0.0001 ? 0 : ((onCircle.x - a.x) * v.dy - (onCircle.y - a.y) * v.dx) / det
        return Fillet(onSide: onSide, onCircle: onCircle, corner: CGPoint(x: a.x + u.dx * s, y: a.y + u.dy * s))
    }

    private static func angle(of point: CGPoint, from center: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    /// An angle brought into 0..<2π, so arcs always go the short way round in the right direction.
    private static func turn(_ angle: CGFloat) -> CGFloat {
        let full = 2 * CGFloat.pi
        let wrapped = angle.truncatingRemainder(dividingBy: full)
        return wrapped < 0 ? wrapped + full : wrapped
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
