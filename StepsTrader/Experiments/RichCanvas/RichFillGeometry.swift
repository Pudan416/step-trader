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
            return luminousGradient(
                base: base, seed: seed, contourCount: budget.contourCount
            )
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
        seed: UInt64,
        contourCount: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base) else { return empty }
        var rng = SeededRNG.derived(from: seed, domain: "richLuminousFill")
        let anchor = interiorAnchor(of: envelope.points)
        let angle = rng.nextDouble(in: 0...(2 * .pi))
        let extent = max(0.1, min(base.bounds.width, base.bounds.height))
        let radius = Double(extent) * rng.nextDouble(in: 0.08...0.16)
        let candidate = CGPoint(
            x: anchor.x + radius * cos(angle),
            y: anchor.y + radius * sin(angle)
        )
        let highlight = contractedPoint(
            candidate, toward: anchor, polygon: envelope.points
        )
        let contourLines = nestedContours(
            base: base,
            count: max(0, contourCount)
        ).lines
        return RichFillGeometry(
            lines: contourLines,
            translucentSurfaces: bodySurfaces(
                envelope: envelope,
                anchor: anchor,
                scales: [0.98, 0.78, 0.58]
            ),
            highlightPoints: [highlight]
        )
    }

    private static func nestedContours(
        base: RichFigureGeometry,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base), count > 0 else {
            return empty
        }
        let anchor = interiorAnchor(of: envelope.points)
        let lines = (0..<count).map { index in
            let progress = Double(index + 1) / Double(count + 1)
            let scale = 1 - 0.72 * progress
            let points = transformed(
                envelope.points, around: anchor,
                scale: scale, rotation: 0
            )
            return RichPolyline(
                points: contractedUntilContained(
                    points, toward: anchor, polygon: envelope.points,
                    closed: true, strictly: true
                ),
                isClosed: true,
                role: .accent
            )
        }
        return RichFillGeometry(
            lines: lines,
            translucentSurfaces: bodySurfaces(
                envelope: envelope,
                anchor: anchor,
                scales: [0.96, 0.80, 0.64]
            ),
            highlightPoints: []
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
        let anchor = interiorAnchor(of: envelope.points)
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
                envelope.points, around: anchor,
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
                points: contractedUntilContained(
                    visiblePoints, toward: anchor, polygon: envelope.points,
                    closed: false, strictly: false
                ),
                isClosed: false,
                role: .orbit
            ))
        }

        return RichFillGeometry(
            lines: lines,
            translucentSurfaces: bodySurfaces(
                envelope: envelope,
                anchor: anchor,
                scales: [0.96, 0.80, 0.64]
            ),
            highlightPoints: []
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
        let anchor = interiorAnchor(of: envelope.points)
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
            lines: lines,
            translucentSurfaces: bodySurfaces(
                envelope: envelope,
                anchor: anchor,
                scales: [0.96, 0.80, 0.64]
            ),
            highlightPoints: []
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
        let anchor = interiorAnchor(of: envelope.points)
        let highlight = pointIsInsideOrOnBoundary(
            base.core, polygon: envelope.points
        ) && isNormalized(base.core) ? base.core : anchor
        return RichFillGeometry(
            lines: [RichPolyline(
                points: envelope.points,
                isClosed: true,
                role: .silhouette
            )],
            translucentSurfaces: bodySurfaces(
                envelope: envelope,
                anchor: anchor,
                scales: [0.96, 0.80, 0.64]
            ),
            highlightPoints: [highlight]
        )
    }

    private static func layeredMass(
        base: RichFigureGeometry,
        seed: UInt64,
        count: Int
    ) -> RichFillGeometry {
        guard let envelope = closedEnvelope(in: base) else { return empty }
        var rng = SeededRNG.derived(from: seed, domain: "richLayeredMassFill")
        let anchor = interiorAnchor(of: envelope.points)
        var surfaces: [[CGPoint]] = []
        surfaces.reserveCapacity(count)

        for index in 0..<count {
            let scale = 0.96 - 0.10 * Double(index)
            let amplitude = rng.nextDouble(in: 0.025...0.06)
            let frequency = rng.nextInt(in: 2...5)
            let phase = rng.nextDouble(in: 0...(2 * .pi))
            let points = envelope.points.map { point -> CGPoint in
                let x = Double(point.x - anchor.x)
                let y = Double(point.y - anchor.y)
                let angle = atan2(y, x)
                let deformation = 1 - amplitude
                    * (0.5 + 0.5 * sin(Double(frequency) * angle + phase))
                let factor = scale * deformation
                return CGPoint(
                    x: anchor.x + x * factor,
                    y: anchor.y + y * factor
                )
            }
            surfaces.append(contractedUntilContained(
                points, toward: anchor, polygon: envelope.points,
                closed: true, strictly: true
            ))
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

    private static func bodySurfaces(
        envelope: RichPolyline,
        anchor: CGPoint,
        scales: [Double]
    ) -> [[CGPoint]] {
        scales.map { scale in
            contractedUntilContained(
                transformed(
                    envelope.points,
                    around: anchor,
                    scale: scale,
                    rotation: 0
                ),
                toward: anchor,
                polygon: envelope.points,
                closed: true,
                strictly: scale < 1
            )
        }
    }

    private static func contractedPoint(
        _ point: CGPoint,
        toward anchor: CGPoint,
        polygon: [CGPoint]
    ) -> CGPoint {
        var candidate = point
        for _ in 0..<32 {
            if isNormalized(candidate),
               pointIsInside(candidate, polygon: polygon),
               minimumDistance(candidate, to: polygon) > 0.000_001 {
                return candidate
            }
            candidate = interpolated(from: anchor, to: candidate, progress: 0.75)
        }
        return anchor
    }

    private static func contractedUntilContained(
        _ points: [CGPoint],
        toward anchor: CGPoint,
        polygon: [CGPoint],
        closed: Bool,
        strictly: Bool
    ) -> [CGPoint] {
        var candidates = points
        for _ in 0..<32 {
            let hasStrictInset = !strictly || candidates.allSatisfy {
                pointIsInside($0, polygon: polygon)
                    && minimumDistance($0, to: polygon) > 0.000_001
            }
            if hasStrictInset,
               candidates.allSatisfy(isNormalized),
               pathIsContained(candidates, closed: closed, polygon: polygon) {
                return candidates
            }
            candidates = candidates.map {
                interpolated(from: anchor, to: $0, progress: 0.75)
            }
        }
        return candidates
    }

    private static func interiorAnchor(of polygon: [CGPoint]) -> CGPoint {
        let area = signedArea(of: polygon)
        if abs(area) > 0.000_000_001 {
            var x = 0.0
            var y = 0.0
            for index in polygon.indices {
                let point = polygon[index]
                let next = polygon[(index + 1) % polygon.count]
                let cross = Double(point.x * next.y - next.x * point.y)
                x += Double(point.x + next.x) * cross
                y += Double(point.y + next.y) * cross
            }
            let centroid = CGPoint(
                x: x / (6 * area),
                y: y / (6 * area)
            )
            if pointIsInside(centroid, polygon: polygon),
               minimumDistance(centroid, to: polygon) > 0.000_001 {
                return centroid
            }
        }

        let bounds = polygonBounds(polygon)
        var best = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestDistance = -Double.infinity
        for yIndex in 1..<16 {
            for xIndex in 1..<16 {
                let point = CGPoint(
                    x: bounds.minX + bounds.width * Double(xIndex) / 16,
                    y: bounds.minY + bounds.height * Double(yIndex) / 16
                )
                guard pointIsInside(point, polygon: polygon) else { continue }
                let distance = minimumDistance(point, to: polygon)
                if distance > bestDistance {
                    best = point
                    bestDistance = distance
                }
            }
        }
        return best
    }

    private static func pathIsContained(
        _ points: [CGPoint],
        closed: Bool,
        polygon: [CGPoint]
    ) -> Bool {
        guard points.allSatisfy({
            isNormalized($0) && pointIsInsideOrOnBoundary($0, polygon: polygon)
        }) else { return false }
        guard points.count > 1 else { return true }
        let segmentCount = closed ? points.count : points.count - 1
        return (0..<segmentCount).allSatisfy { index in
            segmentIsContained(
                from: points[index],
                to: points[(index + 1) % points.count],
                polygon: polygon
            )
        }
    }

    private static func segmentIsContained(
        from start: CGPoint,
        to end: CGPoint,
        polygon: [CGPoint]
    ) -> Bool {
        var parameters = [0.0, 1.0]
        let direction = CGPoint(x: end.x - start.x, y: end.y - start.y)
        for index in polygon.indices {
            let edgeStart = polygon[index]
            let edgeEnd = polygon[(index + 1) % polygon.count]
            let edge = CGPoint(
                x: edgeEnd.x - edgeStart.x,
                y: edgeEnd.y - edgeStart.y
            )
            let denominator = cross(direction, edge)
            guard abs(denominator) > 0.000_000_001 else { continue }
            let delta = CGPoint(
                x: edgeStart.x - start.x,
                y: edgeStart.y - start.y
            )
            let progress = cross(delta, edge) / denominator
            let edgeProgress = cross(delta, direction) / denominator
            if progress >= 0, progress <= 1,
               edgeProgress >= 0, edgeProgress <= 1 {
                parameters.append(progress)
            }
        }
        parameters.sort()
        var unique: [Double] = []
        for value in parameters where
            unique.last.map({ abs($0 - value) > 0.000_000_1 }) ?? true {
            unique.append(value)
        }
        for index in 0..<(unique.count - 1) {
            let midpoint = interpolated(
                from: start, to: end,
                progress: (unique[index] + unique[index + 1]) / 2
            )
            if !pointIsInsideOrOnBoundary(midpoint, polygon: polygon) {
                return false
            }
        }
        return true
    }

    private static func pointIsInsideOrOnBoundary(
        _ point: CGPoint,
        polygon: [CGPoint]
    ) -> Bool {
        minimumDistance(point, to: polygon) <= 0.000_001
            || pointIsInside(point, polygon: polygon)
    }

    private static func minimumDistance(
        _ point: CGPoint,
        to polygon: [CGPoint]
    ) -> Double {
        polygon.indices.map { index in
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let x = Double(end.x - start.x)
            let y = Double(end.y - start.y)
            let lengthSquared = x * x + y * y
            guard lengthSquared > 0 else {
                return hypot(
                    Double(point.x - start.x), Double(point.y - start.y)
                )
            }
            let progress = max(0, min(1,
                (Double(point.x - start.x) * x
                    + Double(point.y - start.y) * y) / lengthSquared
            ))
            let nearestX = Double(start.x) + progress * x
            let nearestY = Double(start.y) + progress * y
            return hypot(Double(point.x) - nearestX, Double(point.y) - nearestY)
        }.min() ?? .infinity
    }

    private static func polygonBounds(_ polygon: [CGPoint]) -> CGRect {
        polygon.dropFirst().reduce(
            CGRect(origin: polygon[0], size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
    }

    private static func interpolated(
        from start: CGPoint,
        to end: CGPoint,
        progress: Double
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private static func isNormalized(_ point: CGPoint) -> Bool {
        (-1.0...1.0).contains(point.x) && (-1.0...1.0).contains(point.y)
    }

    private static func cross(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        Double(lhs.x * rhs.y - lhs.y * rhs.x)
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
