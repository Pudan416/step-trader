import Foundation

struct RichFillGeometry: Equatable {
    let lines: [RichPolyline]
    let translucentSurfaces: [[CGPoint]]
    let highlightPoints: [CGPoint]
}

enum RichFillGeometryFactory {
    static func make(
        fill: RichFillKind,
        base: RichFigureGeometry,
        seed: UInt64,
        budget: RichRenderBudget
    ) -> RichFillGeometry {
        switch fill {
        case .luminousGradient:
            return luminousGradient(base: base, seed: seed)
        case .nestedContours:
            return nestedContours(base: base, count: budget.contourCount)
        case .orbitalLines:
            return orbitalLines(
                base: base, seed: seed, count: budget.orbitalRingCount
            )
        case .filamentField:
            return filamentField(
                base: base, seed: seed, count: budget.filamentCount
            )
        case .outlineWithCore:
            return outlineWithCore(base: base)
        case .layeredTranslucentMass:
            let count = min(5, max(3, budget.contourCount / 2))
            return layeredMass(base: base, seed: seed, count: count)
        }
    }

    private static func luminousGradient(
        base: RichFigureGeometry,
        seed: UInt64
    ) -> RichFillGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richLuminousFill")
        let angle = rng.nextDouble(in: 0...(2 * .pi))
        let extent = max(0.1, min(base.bounds.width, base.bounds.height))
        let radius = Double(extent) * rng.nextDouble(in: 0.08...0.16)
        let highlight = CGPoint(
            x: base.core.x + radius * cos(angle),
            y: base.core.y + radius * sin(angle)
        )
        return RichFillGeometry(
            lines: [], translucentSurfaces: [], highlightPoints: [highlight]
        )
    }

    private static func nestedContours(
        base: RichFigureGeometry,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base), count > 0 else {
            return empty
        }
        let lines = (0..<count).map { index in
            let progress = Double(index + 1) / Double(count + 1)
            let scale = 1 - 0.72 * progress
            return RichPolyline(
                points: transformed(
                    envelope.points, around: base.core,
                    scale: scale, rotation: 0
                ),
                isClosed: true,
                role: .accent
            )
        }
        return RichFillGeometry(
            lines: lines, translucentSurfaces: [], highlightPoints: []
        )
    }

    private static func orbitalLines(
        base: RichFigureGeometry,
        seed: UInt64,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base), count > 0 else {
            return empty
        }
        var rng = SeededRNG.derived(from: seed, domain: "richOrbitalFill")
        let baseRotation = rng.nextDouble(in: 0...Double.pi)
        var lines: [RichPolyline] = []
        lines.reserveCapacity(count)

        for index in 0..<count {
            let progress = Double(index + 1) / Double(count)
            let scale = 0.56 + 0.38 * progress
            let rotation = baseRotation
                + Double(index) * (.pi / Double(max(2, count)))
                + rng.nextDouble(in: -0.08...0.08)
            let points = transformed(
                envelope.points, around: base.core,
                scale: scale, rotation: rotation
            )
            guard points.count > 2 else { continue }

            let gapStart = rng.nextInt(in: 0...(points.count - 1))
            let gapCount = max(1, min(points.count - 2, points.count / 7))
            let visibleCount = points.count - gapCount
            let visiblePoints = (0..<visibleCount).map { offset in
                points[(gapStart + gapCount + offset) % points.count]
            }
            lines.append(RichPolyline(
                points: visiblePoints,
                isClosed: false,
                role: .orbit
            ))
        }

        return RichFillGeometry(
            lines: lines, translucentSurfaces: [], highlightPoints: []
        )
    }

    private static func filamentField(
        base: RichFigureGeometry,
        seed: UInt64,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base), count > 0 else {
            return empty
        }
        var rng = SeededRNG.derived(from: seed, domain: "richFilamentFill")
        var lines: [RichPolyline] = []
        lines.reserveCapacity(count)
        var attempt = 0

        while lines.count < count && attempt < count * 8 {
            let angle = rng.nextDouble(in: 0...Double.pi)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -sin(angle), y: cos(angle))
            let projections = envelope.points.map { dot($0, normal) }
            guard let lower = projections.min(), let upper = projections.max(),
                  upper - lower > 0.000_001 else {
                attempt += 1
                continue
            }
            let margin = (upper - lower) * 0.08
            let offset = rng.nextDouble(in: (lower + margin)...(upper - margin))
            if let chord = clippedChord(
                polygon: envelope.points,
                direction: direction,
                normal: normal,
                offset: offset
            ) {
                lines.append(RichPolyline(
                    points: chord, isClosed: false, role: .accent
                ))
            }
            attempt += 1
        }

        return RichFillGeometry(
            lines: lines, translucentSurfaces: [], highlightPoints: []
        )
    }

    private static func outlineWithCore(
        base: RichFigureGeometry
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base) else {
            return RichFillGeometry(
                lines: [], translucentSurfaces: [],
                highlightPoints: [base.core]
            )
        }
        return RichFillGeometry(
            lines: [RichPolyline(
                points: envelope.points,
                isClosed: true,
                role: .silhouette
            )],
            translucentSurfaces: [],
            highlightPoints: [base.core]
        )
    }

    private static func layeredMass(
        base: RichFigureGeometry,
        seed: UInt64,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base) else { return empty }
        var rng = SeededRNG.derived(from: seed, domain: "richLayeredMassFill")
        var surfaces: [[CGPoint]] = []
        surfaces.reserveCapacity(count)

        for index in 0..<count {
            let scale = 0.96 - 0.10 * Double(index)
            let amplitude = rng.nextDouble(in: 0.025...0.06)
            let frequency = rng.nextInt(in: 2...5)
            let phase = rng.nextDouble(in: 0...(2 * .pi))
            let points = envelope.points.map { point -> CGPoint in
                let x = Double(point.x - base.core.x)
                let y = Double(point.y - base.core.y)
                let angle = atan2(y, x)
                let deformation = 1 + amplitude
                    * sin(Double(frequency) * angle + phase)
                let factor = scale * deformation
                return CGPoint(
                    x: base.core.x + x * factor,
                    y: base.core.y + y * factor
                )
            }
            surfaces.append(points)
        }

        return RichFillGeometry(
            lines: [], translucentSurfaces: surfaces, highlightPoints: []
        )
    }

    private static func closedEnvelope(
        in base: RichFigureGeometry
    ) -> RichPolyline? {
        let closedLines = base.lines.filter {
            $0.isClosed && $0.points.count > 2
        }
        let silhouettes = closedLines.filter { $0.role == .silhouette }
        return (silhouettes.isEmpty ? closedLines : silhouettes).max {
            abs(signedArea(of: $0.points)) < abs(signedArea(of: $1.points))
        }
    }

    private static func transformed(
        _ points: [CGPoint],
        around center: CGPoint,
        scale: Double,
        rotation: Double
    ) -> [CGPoint] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return points.map { point in
            let x = Double(point.x - center.x) * scale
            let y = Double(point.y - center.y) * scale
            return CGPoint(
                x: center.x + x * cosine - y * sine,
                y: center.y + x * sine + y * cosine
            )
        }
    }

    private static func clippedChord(
        polygon: [CGPoint],
        direction: CGPoint,
        normal: CGPoint,
        offset: Double
    ) -> [CGPoint]? {
        var intersections: [Double] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let edge = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let denominator = dot(edge, normal)
            guard abs(denominator) > 0.000_000_001 else { continue }
            let progress = (offset - dot(start, normal)) / denominator
            guard progress >= 0, progress <= 1 else { continue }
            let point = CGPoint(
                x: start.x + edge.x * progress,
                y: start.y + edge.y * progress
            )
            intersections.append(dot(point, direction))
        }

        intersections.sort()
        var uniqueIntersections: [Double] = []
        for value in intersections where
            uniqueIntersections.last.map({ abs($0 - value) > 0.000_000_1 }) ?? true {
            uniqueIntersections.append(value)
        }

        var longest: (start: Double, end: Double)?
        guard uniqueIntersections.count >= 2 else { return nil }
        for index in 0..<(uniqueIntersections.count - 1) {
            let start = uniqueIntersections[index]
            let end = uniqueIntersections[index + 1]
            let midpoint = point(
                direction: direction, normal: normal,
                distance: (start + end) / 2, offset: offset
            )
            guard pointIsInside(midpoint, polygon: polygon) else { continue }
            if longest.map({ end - start > $0.end - $0.start }) ?? true {
                longest = (start, end)
            }
        }

        guard let longest else { return nil }
        return [
            point(
                direction: direction, normal: normal,
                distance: longest.start, offset: offset
            ),
            point(
                direction: direction, normal: normal,
                distance: longest.end, offset: offset
            )
        ]
    }

    private static func pointIsInside(
        _ point: CGPoint,
        polygon: [CGPoint]
    ) -> Bool {
        var isInside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let crossingX = Double(previous.x - current.x)
                    * Double(point.y - current.y)
                    / Double(previous.y - current.y)
                    + Double(current.x)
                if Double(point.x) < crossingX { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }

    private static func point(
        direction: CGPoint,
        normal: CGPoint,
        distance: Double,
        offset: Double
    ) -> CGPoint {
        CGPoint(
            x: direction.x * distance + normal.x * offset,
            y: direction.y * distance + normal.y * offset
        )
    }

    private static func dot(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        Double(lhs.x * rhs.x + lhs.y * rhs.y)
    }

    private static func signedArea(of points: [CGPoint]) -> Double {
        var area = 0.0
        for index in points.indices {
            let point = points[index]
            let next = points[(index + 1) % points.count]
            area += Double(point.x * next.y - next.x * point.y)
        }
        return area * 0.5
    }

    private static let empty = RichFillGeometry(
        lines: [], translucentSurfaces: [], highlightPoints: []
    )
}
