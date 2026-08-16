import Foundation

struct RichPolyline: Equatable {
    enum Role: Equatable {
        case silhouette, structure, orbit, accent
    }

    let points: [CGPoint]
    let isClosed: Bool
    let role: Role
}

struct RichFigureGeometry: Equatable {
    let lines: [RichPolyline]
    let core: CGPoint
    let bounds: CGRect

    var allPoints: [CGPoint] { lines.flatMap(\.points) }
}

enum RichFigureGeometryFactory {
    static func make(
        family: RichFigureFamily,
        seed: UInt64,
        detailTier: RichFigureDetailTier,
        canonicalTime: Double,
        budget: RichRenderBudget
    ) -> RichFigureGeometry {
        switch family {
        case .circle:
            return circle(seed: seed)
        case .luminousOrganic:
            return luminousOrganic(seed: seed)
        case .crystallineStar:
            return crystallineStar(seed: seed, canonicalTime: canonicalTime)
        case .rays:
            return rays(seed: seed)
        case .orbitalSpirograph:
            return orbitalSpirograph(
                seed: seed,
                detailTier: detailTier,
                budget: budget
            )
        }
    }

    private static func circle(seed: UInt64) -> RichFigureGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richCircleGeometry")
        var lines = [RichPolyline(
            points: polarPoints(count: 96, radius: { _ in 1 }),
            isClosed: true,
            role: .silhouette
        )]

        for _ in 0..<2 {
            let center = CGPoint(
                x: rng.nextCGFloat(in: -0.12...0.12),
                y: rng.nextCGFloat(in: -0.12...0.12)
            )
            let majorRadius = rng.nextCGFloat(in: 0.58...0.76)
            let minorRadius = rng.nextCGFloat(in: 0.30...0.50)
            let rotation = rng.nextDouble(in: 0...(2 * .pi))
            lines.append(ellipse(
                center: center,
                radiusX: majorRadius,
                radiusY: minorRadius,
                rotation: rotation,
                sampleCount: 64,
                role: .structure
            ))
        }

        return geometry(lines: lines, core: .zero)
    }

    private static func luminousOrganic(seed: UInt64) -> RichFigureGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richOrganicGeometry")
        let frequencies = [2, 3, 5]
        let harmonics = frequencies.map { frequency in
            Harmonic(
                amplitude: rng.nextDouble(in: 0.04...0.07),
                frequency: frequency,
                phase: rng.nextDouble(in: 0...(2 * .pi))
            )
        }
        let points = polarPoints(count: 96) { angle in
            let modulation = harmonics.reduce(0.0) { result, harmonic in
                result + harmonic.amplitude * sin(
                    Double(harmonic.frequency) * angle + harmonic.phase
                )
            }
            return CGFloat((0.82 + modulation).clamped(to: 0.62...1.0))
        }

        return geometry(lines: [RichPolyline(
            points: points,
            isClosed: true,
            role: .silhouette
        )], core: .zero)
    }

    private static func crystallineStar(
        seed: UInt64,
        canonicalTime: Double
    ) -> RichFigureGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richStarGeometry")
        let axisCount = rng.nextInt(in: 8...12)
        let angleStep = 2 * Double.pi / Double(axisCount)
        let rotation = rng.nextDouble(in: 0...(2 * .pi))
        let time = canonicalTime.isFinite ? canonicalTime : 0
        var silhouette: [CGPoint] = []
        var outerPoints: [CGPoint] = []
        silhouette.reserveCapacity(axisCount * 2)
        outerPoints.reserveCapacity(axisCount)

        for index in 0..<axisCount {
            let angle = rotation + Double(index) * angleStep
            let baseOuterRadius = rng.nextDouble(in: 0.82...1.0)
            let phase = rng.nextDouble(in: 0...(2 * .pi))
            let timeDelta = 0.035 * (
                sin(time * 0.65 + phase) - sin(phase)
            )
            let outerRadius = baseOuterRadius * (1 + timeDelta)
            let innerRadius = rng.nextDouble(in: 0.22...0.38)
            let outerPoint = point(radius: outerRadius, angle: angle)
            outerPoints.append(outerPoint)
            silhouette.append(outerPoint)
            silhouette.append(point(
                radius: innerRadius,
                angle: angle + angleStep * 0.5
            ))
        }

        let outline = RichPolyline(
            points: silhouette,
            isClosed: true,
            role: .silhouette
        )
        let rays = outerPoints.map { tip in
            RichPolyline(points: [.zero, tip], isClosed: false, role: .structure)
        }
        let crystallinePlanes = outerPoints.indices.map { index in
            RichPolyline(
                points: [
                    outerPoints[index],
                    outerPoints[(index + 2) % axisCount],
                    outerPoints[(index + axisCount / 2) % axisCount]
                ],
                isClosed: true,
                role: .structure
            )
        }
        return geometry(
            lines: [outline] + rays + crystallinePlanes,
            core: .zero
        )
    }

    private static func rays(seed: UInt64) -> RichFigureGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richRayGeometry")
        let rayCount = rng.nextInt(in: 18...24)
        let origin = CGPoint(
            x: rng.nextCGFloat(in: -0.82 ... -0.70),
            y: rng.nextCGFloat(in: 0.48...0.62)
        )
        let startAngle = rng.nextDouble(in: -0.92 ... -0.80)
        let angleSpan = rng.nextDouble(in: 0.96...1.04)
        let arcRadius = rng.nextDouble(in: 1.48...1.62)
        let endpoints = (0..<rayCount).map { index in
            let progress = Double(index) / Double(rayCount - 1)
            let angle = startAngle + angleSpan * progress
            let offset = point(radius: arcRadius, angle: angle)
            return CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
        }

        let envelope = RichPolyline(
            points: [origin] + endpoints,
            isClosed: true,
            role: .silhouette
        )
        let rayLines = endpoints.map { endpoint in
            RichPolyline(
                points: [origin, endpoint],
                isClosed: false,
                role: .structure
            )
        }
        return geometry(lines: [envelope] + rayLines, core: origin)
    }

    private static func orbitalSpirograph(
        seed: UInt64,
        detailTier: RichFigureDetailTier,
        budget: RichRenderBudget
    ) -> RichFigureGeometry {
        var rng = SeededRNG.derived(from: seed, domain: "richSpirographGeometry")
        let seededOrbitCount = rng.nextInt(in: 4...6)
        let orbitCount = min(seededOrbitCount, max(4, budget.orbitalRingCount))
        let baseRotation = rng.nextDouble(in: 0...Double.pi)
        var lines: [RichPolyline] = []
        lines.reserveCapacity(orbitCount + 1)

        for index in 0..<orbitCount {
            let progress = Double(index) / Double(orbitCount)
            let majorRadius = rng.nextCGFloat(in: 0.78...0.96)
            let minorRadius = rng.nextCGFloat(in: 0.34...0.58)
            let rotation = baseRotation + progress * Double.pi
            lines.append(ellipse(
                center: .zero,
                radiusX: majorRadius,
                radiusY: minorRadius,
                rotation: rotation,
                sampleCount: ellipseSampleCount(for: detailTier),
                role: .orbit
            ))
        }

        let rollingRadius = rng.nextInt(in: 2...3)
        let penDistance = rng.nextDouble(in: 0.8...1.6)
        lines.append(hypotrochoid(
            rollingRadius: rollingRadius,
            penDistance: penDistance,
            sampleCount: hypotrochoidSampleCount(for: detailTier)
        ))
        return geometry(lines: lines, core: .zero)
    }

    private static func ellipse(
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: Double,
        sampleCount: Int,
        role: RichPolyline.Role
    ) -> RichPolyline {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let points = (0..<sampleCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sampleCount)
            let localX = Double(radiusX) * cos(angle)
            let localY = Double(radiusY) * sin(angle)
            return CGPoint(
                x: center.x + CGFloat(localX * cosine - localY * sine),
                y: center.y + CGFloat(localX * sine + localY * cosine)
            )
        }
        return RichPolyline(points: points, isClosed: true, role: role)
    }

    private static func hypotrochoid(
        rollingRadius: Int,
        penDistance: Double,
        sampleCount: Int
    ) -> RichPolyline {
        let fixedRadius = 5.0
        let rolling = Double(rollingRadius)
        let difference = fixedRadius - rolling
        let normalizer = difference + penDistance
        let endAngle = 2 * Double.pi * rolling
        let points = (0..<sampleCount).map { index in
            let angle = endAngle * Double(index) / Double(sampleCount)
            let x = difference * cos(angle)
                + penDistance * cos(difference / rolling * angle)
            let y = difference * sin(angle)
                - penDistance * sin(difference / rolling * angle)
            return CGPoint(x: 0.82 * x / normalizer, y: 0.82 * y / normalizer)
        }
        return RichPolyline(points: points, isClosed: true, role: .structure)
    }

    private static func polarPoints(
        count: Int,
        radius: (Double) -> CGFloat
    ) -> [CGPoint] {
        (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return point(radius: Double(radius(angle)), angle: angle)
        }
    }

    private static func point(radius: Double, angle: Double) -> CGPoint {
        CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    private static func geometry(
        lines: [RichPolyline],
        core: CGPoint
    ) -> RichFigureGeometry {
        let points = lines.flatMap(\.points)
        guard let first = points.first else {
            return RichFigureGeometry(lines: lines, core: core, bounds: .zero)
        }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return RichFigureGeometry(
            lines: lines,
            core: core,
            bounds: CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        )
    }

    private static func ellipseSampleCount(for detailTier: RichFigureDetailTier) -> Int {
        switch detailTier {
        case .accent: 48
        case .medium: 64
        case .large: 80
        }
    }

    private static func hypotrochoidSampleCount(for detailTier: RichFigureDetailTier) -> Int {
        switch detailTier {
        case .accent: 96
        case .medium: 144
        case .large: 192
        }
    }
}

private struct Harmonic {
    let amplitude: Double
    let frequency: Int
    let phase: Double
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
