import XCTest
@testable import Steps4

/// Replaces `CanvasElement.findOpenPosition`, which used rejection sampling
/// against the global RNG: it clumped on busy canvases and gave a different
/// layout on every run. The weight closure additionally lets a composition
/// archetype bias where mass lands.
final class PoissonDiscSamplerTests: XCTestCase {

    private let bounds = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    // MARK: - Determinism

    func testSameSeedGivesSamePoint() {
        var rngA = SeededRNG(seed: 1234)
        var rngB = SeededRNG(seed: 1234)
        let existing = [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.6)]

        let a = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.2,
            weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.2,
            weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    /// Callers pass `dayCanvas.elements.map(\.basePosition)`, whose order can
    /// vary after a sync merge. Layout must not depend on it.
    func testResultIsIndependentOfInputOrder() {
        let existing = [
            CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.35, y: 0.65),
        ]
        var rngA = SeededRNG(seed: 99)
        var rngB = SeededRNG(seed: 99)

        let a = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.18,
            weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: existing.reversed(), bounds: bounds, minDistance: 0.18,
            weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsGiveDifferentPoints() {
        var rngA = SeededRNG(seed: 1)
        var rngB = SeededRNG(seed: 2)
        let a = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 1 }, using: &rngB)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Bounds

    func testFirstPointLandsInsideBounds() {
        for seed in UInt64(0)..<50 {
            var rng = SeededRNG(seed: seed)
            let p = PoissonDiscSampler.nextPoint(
                existing: [], bounds: bounds, minDistance: 0.25,
                weight: { _ in 1 }, using: &rng)
            XCTAssertTrue(bounds.contains(p), "First point \(p) escaped")
        }
    }

    func testEveryPointLandsInsideBounds() {
        var rng = SeededRNG(seed: 7)
        var placed: [CGPoint] = []
        for _ in 0..<25 {
            let p = PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds, minDistance: 0.2,
                weight: { _ in 1 }, using: &rng)
            XCTAssertTrue(bounds.contains(p), "Point \(p) escaped")
            placed.append(p)
        }
    }

    // MARK: - Spacing

    func testSpacingIsRespectedWhileThereIsRoom() {
        var rng = SeededRNG(seed: 3)
        var placed: [CGPoint] = []
        let minDistance = 0.16

        // Five points fit comfortably in a 0.76-square at this spacing, so the
        // sampler should never need a relaxed round.
        for _ in 0..<5 {
            let p = PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds,
                minDistance: minDistance, weight: { _ in 1 }, using: &rng)
            for other in placed {
                XCTAssertGreaterThanOrEqual(
                    distance(p, other), minDistance * 0.99,
                    "\(p) landed too close to \(other)")
            }
            placed.append(p)
        }
    }

    /// The property that motivates the change: rejection sampling clumps
    /// because a rejected candidate is retried at random; Bridson grows
    /// outward from what is already placed.
    func testDistributionIsMoreEvenThanUniformRandom() {
        var rng = SeededRNG(seed: 11)
        var poisson: [CGPoint] = []
        for _ in 0..<12 {
            poisson.append(PoissonDiscSampler.nextPoint(
                existing: poisson, bounds: bounds, minDistance: 0.2,
                weight: { _ in 1 }, using: &rng))
        }

        var uniformRng = SeededRNG(seed: 11)
        let uniform = (0..<12).map { _ in
            CGPoint(x: uniformRng.nextCGFloat(in: bounds.minX...bounds.maxX),
                    y: uniformRng.nextCGFloat(in: bounds.minY...bounds.maxY))
        }

        func smallestGap(_ points: [CGPoint]) -> Double {
            var smallest = Double.infinity
            for i in points.indices {
                for j in (i + 1)..<points.count {
                    smallest = min(smallest, distance(points[i], points[j]))
                }
            }
            return smallest
        }

        XCTAssertGreaterThan(smallestGap(poisson), smallestGap(uniform))
    }

    // MARK: - Weighting

    /// The archetype hook. A field that favours the left half must actually
    /// pull the layout left.
    func testWeightBiasesPlacement() {
        var rng = SeededRNG(seed: 17)
        var placed: [CGPoint] = []
        for _ in 0..<10 {
            placed.append(PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds, minDistance: 0.14,
                weight: { $0.x < 0.5 ? 1.0 : 0.05 }, using: &rng))
        }
        let leftCount = placed.filter { $0.x < 0.5 }.count
        XCTAssertGreaterThan(leftCount, 6, "Weight did not bias placement: \(placed)")
    }

    func testZeroWeightEverywhereStillReturnsAnInBoundsPoint() {
        var rng = SeededRNG(seed: 23)
        let p = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 0 }, using: &rng)
        XCTAssertTrue(bounds.contains(p))
    }

    // MARK: - Saturation

    func testSaturatedCanvasStillReturnsAnInBoundsPoint() {
        var placed: [CGPoint] = []
        for row in 0..<6 {
            for col in 0..<6 {
                placed.append(CGPoint(
                    x: bounds.minX + bounds.width * (Double(col) + 0.5) / 6,
                    y: bounds.minY + bounds.height * (Double(row) + 0.5) / 6))
            }
        }
        var rng = SeededRNG(seed: 5)
        let p = PoissonDiscSampler.nextPoint(
            existing: placed, bounds: bounds, minDistance: 0.3,
            weight: { _ in 1 }, using: &rng)
        XCTAssertTrue(bounds.contains(p))
    }

    func testSaturatedFallbackPicksTheRoomiestSpot() {
        let placed = (0..<10).map { i in
            CGPoint(x: 0.15 + Double(i % 3) * 0.02, y: 0.15 + Double(i / 3) * 0.02)
        }
        let clusterCentre = CGPoint(
            x: placed.map(\.x).reduce(0, +) / CGFloat(placed.count),
            y: placed.map(\.y).reduce(0, +) / CGFloat(placed.count))

        var rng = SeededRNG(seed: 21)
        let p = PoissonDiscSampler.nextPoint(
            existing: placed, bounds: bounds, minDistance: 0.5,
            weight: { _ in 1 }, using: &rng)

        XCTAssertGreaterThan(distance(p, clusterCentre), 0.3,
                             "Fallback \(p) hugged the cluster")
    }

    // MARK: - Bulk fill (stipple)

    func testFillRespectsMaxPoints() {
        var rng = SeededRNG(seed: 31)
        let points = PoissonDiscSampler.fill(
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            minDistance: 0.05, maxPoints: 40,
            weight: { _ in 1 }, using: &rng)
        XCTAssertLessThanOrEqual(points.count, 40)
        XCTAssertGreaterThan(points.count, 10, "Should find plenty of room")
    }

    func testFillIsReproducible() {
        var rngA = SeededRNG(seed: 41)
        var rngB = SeededRNG(seed: 41)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let a = PoissonDiscSampler.fill(bounds: unit, minDistance: 0.08,
                                        maxPoints: 30, weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.fill(bounds: unit, minDistance: 0.08,
                                        maxPoints: 30, weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    func testFillRespectsSpacing() {
        var rng = SeededRNG(seed: 51)
        let points = PoissonDiscSampler.fill(
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            minDistance: 0.1, maxPoints: 50, weight: { _ in 1 }, using: &rng)
        for i in points.indices {
            for j in (i + 1)..<points.count {
                XCTAssertGreaterThanOrEqual(distance(points[i], points[j]), 0.09)
            }
        }
    }
}
