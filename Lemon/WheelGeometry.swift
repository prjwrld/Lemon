import SwiftUI

/// The wheel's measurements, and the maths for "which slice is at this point?".
/// Shared by the drawing (SwiftUI) and the drop handling (AppKit) so they agree.
nonisolated struct WheelGeometry: Equatable, Sendable {
    var diameter: CGFloat = 250
    var holeDiameter: CGFloat = 92
    var gap: CGFloat = 9          // space between slices, in points
    var cornerRadius: CGFloat = 10
    var count: Int

    var outerRadius: CGFloat { diameter / 2 }
    var innerRadius: CGFloat { holeDiameter / 2 }
    var middleRadius: CGFloat { (outerRadius + innerRadius) / 2 }

    /// Each slice's start and end angle. Slice 0 starts at the top and they go clockwise.
    /// (Angles are in radians; with y pointing down, clockwise is positive.)
    func angles(of index: Int) -> (start: CGFloat, end: CGFloat) {
        let step = 2 * .pi / CGFloat(max(count, 1))
        let halfGap = (gap / 2) / middleRadius
        let start = -.pi / 2 + step * CGFloat(index)
        return (start + halfGap, start + step - halfGap)
    }

    /// Where a slice's label goes, measured from the wheel's centre.
    func labelOffset(of index: Int) -> CGSize {
        let (start, end) = angles(of: index)
        let middle = (start + end) / 2
        return CGSize(width: cos(middle) * middleRadius, height: sin(middle) * middleRadius)
    }

    /// The slice under a point (measured from the centre, y pointing down), if any.
    func slice(at point: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let distance = hypot(point.x, point.y)
        guard distance >= innerRadius - 2, distance <= outerRadius + 16 else { return nil }
        var angle = atan2(point.y, point.x) + .pi / 2   // 0 = top
        if angle < 0 { angle += 2 * .pi }
        return min(Int(angle / (2 * .pi / CGFloat(count))), count - 1)
    }
}

/// One rounded ring slice, drawn to fill the whole wheel-sized frame.
nonisolated struct RingSlice: Shape {
    var geometry: WheelGeometry
    var index: Int

    func path(in rect: CGRect) -> Path {
        let g = geometry
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let (a0, a1) = g.angles(of: index)
        let r1 = g.innerRadius, r2 = g.outerRadius
        let corner = min(g.cornerRadius, (r2 - r1) / 2)

        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }

        // Small corner arcs are joined with addArc(tangent1End:...), which treats
        // the curved edge as nearly straight near the corner. At this size it looks right.
        var path = Path()
        path.move(to: point((r1 + r2) / 2, a0))
        path.addArc(tangent1End: point(r2, a0), tangent2End: point(r2, a0 + corner / r2 * 2), radius: corner)
        path.addArc(center: center, radius: r2,
                    startAngle: .radians(a0 + corner / r2), endAngle: .radians(a1 - corner / r2),
                    clockwise: false)
        path.addArc(tangent1End: point(r2, a1), tangent2End: point(r1, a1), radius: corner)
        path.addArc(tangent1End: point(r1, a1), tangent2End: point(r1, a1 - corner / r1 * 2), radius: corner)
        path.addArc(center: center, radius: r1,
                    startAngle: .radians(a1 - corner / r1), endAngle: .radians(a0 + corner / r1),
                    clockwise: true)
        path.addArc(tangent1End: point(r1, a0), tangent2End: point(r2, a0), radius: corner)
        path.closeSubpath()
        return path
    }
}
