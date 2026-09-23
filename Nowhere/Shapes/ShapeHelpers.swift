import SwiftUI

/// Pure-function shape generators for the three canvas element families.
/// Each returns a `Path` drawn within a given rect, seeded deterministically
/// so the same seed always produces the same shape.
///
/// Split across multiple files as extensions — shared helpers live here.
enum ProceduralShapeGenerator {

    static func smoothClosedPath(through points: [CGPoint]) -> Path {
        guard points.count >= 3 else {
            var p = Path()
            if let first = points.first { p.move(to: first) }
            for pt in points.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            return p
        }

        var path = Path()
        let n = points.count

        let mid0 = CGPoint(
            x: (points[0].x + points[n - 1].x) / 2,
            y: (points[0].y + points[n - 1].y) / 2
        )
        path.move(to: mid0)

        for i in 0..<n {
            let current = points[i]
            let next = points[(i + 1) % n]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }

        path.closeSubpath()
        return path
    }

    static func interpolateSpine(_ controls: [CGPoint], segments: Int) -> [CGPoint] {
        guard controls.count >= 2 else { return controls }

        var result = [CGPoint]()
        result.reserveCapacity(segments + 1)

        for s in 0...segments {
            let t = CGFloat(s) / CGFloat(segments)
            let point = catmullRomPoint(t: t, controls: controls)
            result.append(point)
        }
        return result
    }

    static func catmullRomPoint(t: CGFloat, controls: [CGPoint]) -> CGPoint {
        let n = controls.count
        let scaled = t * CGFloat(n - 1)
        let segment = min(Int(scaled), n - 2)
        let localT = scaled - CGFloat(segment)

        let p0 = controls[max(0, segment - 1)]
        let p1 = controls[segment]
        let p2 = controls[min(n - 1, segment + 1)]
        let p3 = controls[min(n - 1, segment + 2)]

        let tt = localT * localT
        let ttt = tt * localT

        let x = 0.5 * ((2 * p1.x) +
                        (-p0.x + p2.x) * localT +
                        (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * tt +
                        (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * ttt)
        let y = 0.5 * ((2 * p1.y) +
                        (-p0.y + p2.y) * localT +
                        (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * tt +
                        (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * ttt)

        return CGPoint(x: x, y: y)
    }

    static func unitVector(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / len, y: dy / len)
    }
}
