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
    /// Extra turn of the whole wheel (radians), used while it opens and closes.
    var twist: CGFloat = 0

    /// The same wheel, smaller and turned: used to animate opening and closing.
    func scaled(by scale: CGFloat, twist: CGFloat) -> WheelGeometry {
        var g = self
        g.diameter *= scale
        g.plateMargin *= scale
        g.holeDiameter *= scale
        g.gap *= scale
        g.outerCorner *= scale
        g.innerCorner *= scale
        g.twist = twist
        return g
    }

    var outerRadius: CGFloat { diameter / 2 - plateMargin }
    var innerRadius: CGFloat { holeDiameter / 2 }
    var middleRadius: CGFloat { (outerRadius + innerRadius) / 2 }
    var step: CGFloat { 2 * .pi / CGFloat(max(count, 1)) }

    /// The centre angle of a slice. Slice 0 is centred at the top; the rest go clockwise.
    /// (Radians; with y pointing down, clockwise is positive.)
    func centerAngle(of index: Int) -> CGFloat {
        -.pi / 2 + twist + step * CGFloat(index)
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
