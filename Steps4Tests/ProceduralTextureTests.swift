import XCTest
import SwiftUI
@testable import Steps4

/// Fills are the axis of visual variety: same contours, different interiors.
/// Everything here is geometry in unit space — colour and scale are applied at
/// draw time, so one cached texture serves every size.
final class ProceduralTextureTests: XCTestCase {

    private func radii(seed: UInt64 = 1) -> [Double] {
        ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: seed, complexity: 0.5, symmetry: 1, time: 0)
    }

    // MARK: - Determinism

    func testGeometryIsReproducibleFromSeed() {
        for kind in TextureKind.allCases {
            let spec = TextureSpec.seeded(kind: kind, seed: 77)
            let a = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 77)
            let b = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 77)
            XCTAssertEqual(a, b, "\(kind) is not reproducible")
        }
    }

    func testDifferentSeedsGiveDifferentGeometry() {
        for kind: TextureKind in [.rings, .hatch, .stipple] {
            let a = ProceduralTexture.geometry(
                spec: .seeded(kind: kind, seed: 1), radii: radii(), seed: 1)
            let b = ProceduralTexture.geometry(
                spec: .seeded(kind: kind, seed: 2), radii: radii(), seed: 2)
            XCTAssertNotEqual(a, b, "\(kind) ignored its seed")
        }
    }

    func testSpecIsCodableRoundTrip() throws {
        for kind in TextureKind.allCases {
            let spec = TextureSpec.seeded(kind: kind, seed: 909)
            let data = try JSONEncoder().encode(spec)
            let decoded = try JSONDecoder().decode(TextureSpec.self, from: data)
            XCTAssertEqual(spec, decoded)
        }
    }

    /// `init(from:)` is hand-written specifically so a decoded spec still
    /// clamps — a synthesised `Decodable` would assign the raw JSON Doubles
    /// straight to the stored properties and skip the constructor entirely.
    func testSpecDecodingClampsOutOfRangeValues() throws {
        let json = """
        {"kind":"hatch","density":1.7,"uniformity":-0.4,"angle":-1.0}
        """
        let decoded = try JSONDecoder().decode(TextureSpec.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.density, 1.0)
        XCTAssertEqual(decoded.uniformity, 0.0)
        XCTAssertEqual(decoded.angle, 2 * .pi - 1.0, accuracy: 1e-9)
    }

    /// `TextureSpec` is a cache key, so near-identical Doubles must not miss.
    func testSpecHashingIsQuantised() {
        let a = TextureSpec(kind: .hatch, density: 0.5, uniformity: 0.5, angle: 1.0)
        let b = TextureSpec(kind: .hatch, density: 0.50000001,
                            uniformity: 0.5, angle: 1.0)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - Per-kind content

    func testFlatProducesNoSubGeometry() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .flat, seed: 1), radii: radii(), seed: 1)
        XCTAssertTrue(g.rings.isEmpty)
        XCTAssertTrue(g.lines.isEmpty)
        XCTAssertTrue(g.dots.isEmpty)
    }

    func testGradientProducesNoSubGeometry() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .gradient, seed: 1), radii: radii(), seed: 1)
        XCTAssertTrue(g.rings.isEmpty)
        XCTAssertTrue(g.lines.isEmpty)
        XCTAssertTrue(g.dots.isEmpty)
    }

    func testRingsNestInwardWithoutCrossing() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .rings, seed: 5), radii: radii(), seed: 5)
        XCTAssertGreaterThanOrEqual(g.rings.count, 3)

        for ring in g.rings {
            XCTAssertEqual(ring.count, radii().count, "Ring point count must match")
            XCTAssertGreaterThan(ring.min() ?? 0, 0, "A ring collapsed through zero")
        }
        // Each ring sits strictly inside the previous one.
        for i in 1..<g.rings.count {
            for j in g.rings[i].indices {
                XCTAssertLessThan(g.rings[i][j], g.rings[i - 1][j],
                                  "Ring \(i) crossed ring \(i - 1) at \(j)")
            }
        }
    }

    func testHatchLinesShareOneAngle() {
        let spec = TextureSpec.seeded(kind: .hatch, seed: 13)
        let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 13)
        XCTAssertGreaterThanOrEqual(g.lines.count, 4)

        let angles = g.lines.map { atan2($0.end.y - $0.start.y, $0.end.x - $0.start.x) }
        let reference = angles[0]
        for angle in angles {
            // Parallel up to direction, so compare modulo π.
            let delta = abs((angle - reference)
                .truncatingRemainder(dividingBy: .pi))
            XCTAssertTrue(delta < 1e-6 || abs(delta - .pi) < 1e-6,
                          "Hatch line off-angle by \(delta)")
        }
    }

    func testHatchLinesStayInsideTheUnitDisc() {
        let contour = radii()
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .hatch, seed: 19), radii: contour, seed: 19)
        // hatchGeometry's chords are constructed on the inscribed circle of
        // radius `contour.min() * 0.95`, so every endpoint's distance from
        // the origin is exactly that bound (up to float error) — not the
        // 1.4 the contour's own outer radius could reach.
        let bound = (contour.min() ?? 1) * 0.95
        for line in g.lines {
            XCTAssertLessThanOrEqual(hypot(line.start.x, line.start.y), bound + 1e-9)
            XCTAssertLessThanOrEqual(hypot(line.end.x, line.end.y), bound + 1e-9)
        }
    }

    func testStippleDotsStayInsideTheContour() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .stipple, seed: 23), radii: radii(), seed: 23)
        XCTAssertGreaterThan(g.dots.count, 10)

        let contour = radii()
        for dot in g.dots {
            let angle = atan2(Double(dot.center.y), Double(dot.center.x))
            let normalised = angle < 0 ? angle + 2 * .pi : angle
            let index = Int(normalised / (2 * .pi) * Double(contour.count))
                % contour.count
            XCTAssertLessThanOrEqual(
                Double(hypot(dot.center.x, dot.center.y)), contour[index] + 0.01,
                "Dot at \(dot.center) escaped the contour")
        }
    }

    func testStippleDotRadiiArePositive() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .stipple, seed: 29), radii: radii(), seed: 29)
        for dot in g.dots { XCTAssertGreaterThan(dot.radius, 0) }
    }

    // MARK: - Uniformity
    //
    // "Однородные и нет": the same fill must be able to read as even or as
    // strongly graded across the form.

    func testUniformStippleIsEvenlySpread() {
        let spec = TextureSpec(kind: .stipple, density: 0.7, uniformity: 1.0, angle: 0)
        let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 33)
        let left = g.dots.filter { $0.center.x < 0 }.count
        let right = g.dots.count - left
        XCTAssertLessThan(abs(left - right), max(4, g.dots.count / 3),
                          "Uniform stipple should not favour a side")
    }

    func testGradedStippleIsLopsided() {
        // Averaged over seeds: one field can happen to be flat.
        var lopsidedCount = 0
        var trials = 0
        for seed in stride(from: UInt64(0), to: 300, by: 17) {
            let spec = TextureSpec(kind: .stipple, density: 0.7,
                                   uniformity: 0.0, angle: 0)
            let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: seed)
            guard g.dots.count > 12 else { continue }
            trials += 1
            let left = g.dots.filter { $0.center.x < 0 }.count
            let imbalance = abs(Double(left) - Double(g.dots.count) / 2)
            if imbalance > Double(g.dots.count) / 6 { lopsidedCount += 1 }
        }
        XCTAssertGreaterThan(trials, 5)
        XCTAssertGreaterThan(lopsidedCount, trials / 3,
                             "Graded stipple never developed a density gradient")
    }

    func testDensityDrivesCount() {
        func dotCount(_ density: Double) -> Int {
            let spec = TextureSpec(kind: .stipple, density: density,
                                   uniformity: 1.0, angle: 0)
            return ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 61)
                .dots.count
        }
        XCTAssertLessThan(dotCount(0.2), dotCount(0.9))
    }

    func testHatchDensityDrivesLineCount() {
        func lineCount(_ density: Double) -> Int {
            let spec = TextureSpec(kind: .hatch, density: density,
                                   uniformity: 1.0, angle: 0.7)
            return ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 67)
                .lines.count
        }
        XCTAssertLessThan(lineCount(0.2), lineCount(0.9))
    }

    // MARK: - Budget
    //
    // Sub-geometry is cached, but it still has to be drawn every frame.

    func testSubGeometryStaysWithinBudget() {
        for kind in TextureKind.allCases {
            for seed in stride(from: UInt64(0), to: 200, by: 13) {
                let spec = TextureSpec(kind: kind, density: 1.0,
                                       uniformity: 0.0, angle: 1.2)
                let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: seed)
                XCTAssertLessThanOrEqual(g.dots.count, 90, "\(kind) dots")
                XCTAssertLessThanOrEqual(g.lines.count, 40, "\(kind) lines")
                XCTAssertLessThanOrEqual(g.rings.count, 8, "\(kind) rings")
            }
        }
    }

    // MARK: - Seeded specs

    func testSeededSpecStaysInRange() {
        for kind in TextureKind.allCases {
            for seed in UInt64(0)..<50 {
                let spec = TextureSpec.seeded(kind: kind, seed: seed)
                XCTAssertEqual(spec.kind, kind)
                XCTAssertTrue((0...1).contains(spec.density))
                XCTAssertTrue((0...1).contains(spec.uniformity))
                XCTAssertTrue((0...(2 * Double.pi)).contains(spec.angle))
            }
        }
    }
}

// MARK: - Render cache

/// `RenderCache.textureGeometry` is the plan's single most important
/// constraint made real: texture geometry is generated once per bucket, not
/// per frame. These tests cover the caching mechanism itself, not the fill
/// algorithms above — a hit that skips regeneration, a miss that doesn't
/// (complexity, which pins the shape/scale distinction `TextureCacheKey`
/// exists to capture), the prune keeping the dictionary bounded, and the
/// per-seed phase that keeps 15 elements' buckets from flipping on the same
/// frame. `RenderCache` is `@MainActor`, so this class is too.
@MainActor
final class RenderCacheTextureTests: XCTestCase {

    private func radii(seed: UInt64 = 1, complexity: Double = 0.5) -> [Double] {
        ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: seed, complexity: complexity, symmetry: 1, time: 0)
    }

    /// A call within the same bucket must hit the cache. Proven by passing
    /// *different* radii on the second call: a real regeneration would pick
    /// them up and change the result, so an unchanged result means the
    /// second call never reached `ProceduralTexture.geometry` at all.
    func testRepeatCallWithinOneBucketIsCached() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .stipple, density: 0.7, uniformity: 0.3, angle: 0)

        let first = cache.textureGeometry(
            seed: 5, spec: spec, radii: radii(seed: 1), complexity: 0.5, time: 0.2)
        let second = cache.textureGeometry(
            seed: 5, spec: spec, radii: radii(seed: 99), complexity: 0.5, time: 0.9)

        XCTAssertEqual(first, second,
                       "A call within the same bucket must hit the cache, not regenerate")
    }

    /// Pins Important 2: `complexity` changes `organicBlobRadiusFactor`'s
    /// amplitude and ringRadius — the contour's shape — so two calls that
    /// differ only in complexity (and the radii that follow from it) must
    /// land in different cache entries. Before the fix, this collided on
    /// seed/spec/timeBucket alone and the second call silently returned the
    /// first (stale) geometry.
    func testDifferentComplexityMissesTheCache() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)

        let low = cache.textureGeometry(
            seed: 5, spec: spec, radii: radii(complexity: 0.1), complexity: 0.1, time: 0)
        let high = cache.textureGeometry(
            seed: 5, spec: spec, radii: radii(complexity: 0.9), complexity: 0.9, time: 0)

        XCTAssertNotEqual(low, high, "Complexity change must miss the cache and regenerate")
    }

    /// Pins the prune: repeatedly advancing the bucket must not let the
    /// dictionary grow with every bucket ever visited.
    func testCacheStaysBoundedAcrossManyBuckets() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .stipple, density: 0.5, uniformity: 0.5, angle: 0)

        for i in 0..<50 {
            let time = Double(i) * RenderCache.textureBucketSeconds
            _ = cache.textureGeometry(
                seed: 7, spec: spec, radii: radii(), complexity: 0.5, time: time)
        }

        XCTAssertLessThanOrEqual(cache.textureCache.count, 3,
                                 "Prune should keep the cache bounded to the current and previous bucket")
    }

    func testTextureBucketMapsTimeAsIntended() {
        XCTAssertEqual(RenderCache.textureBucket(for: 0), 0)
        XCTAssertEqual(RenderCache.textureBucket(for: 1.49), 0)
        XCTAssertEqual(RenderCache.textureBucket(for: 1.5), 1)
        XCTAssertEqual(RenderCache.textureBucket(for: 2.9), 1)
        XCTAssertEqual(RenderCache.textureBucket(for: 3.0), 2)
        XCTAssertEqual(RenderCache.textureBucket(for: -0.1), -1)
    }

    /// Pins Important 1's mechanism: different seeds must land at different
    /// phases, and the phase must stay within one bucket's width (so any two
    /// seeds are at most one bucket apart at a given instant — the property
    /// the prune's `bucket - 1` window relies on).
    func testPhaseStaggersDifferentSeeds() {
        XCTAssertNotEqual(RenderCache.texturePhase(for: 0), RenderCache.texturePhase(for: 75))
        for seed: UInt64 in [0, 1, 75, 149, 150, 12_345] {
            let phase = RenderCache.texturePhase(for: seed)
            XCTAssertTrue((0..<RenderCache.textureBucketSeconds).contains(phase),
                          "Phase \(phase) for seed \(seed) exceeds one bucket width")
        }
    }

    /// Pins the prune-safety half of Important 1: inserting a phased-ahead
    /// seed's entry must not evict a phased-behind seed's still-current one.
    /// seed 0 has phase 0, seed 75 has phase 0.75 — at real time 0.8 that
    /// puts them one bucket apart (buckets 0 and 1), the maximum spread
    /// `texturePhase` can produce.
    func testStaggeredPhasesDoNotEvictEachOtherPrematurely() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.5, uniformity: 0.5, angle: 0)
        let seedBehind: UInt64 = 0
        let seedAhead: UInt64 = 75
        let t = 0.8

        let firstBehind = cache.textureGeometry(
            seed: seedBehind, spec: spec, radii: radii(), complexity: 0.5, time: t)
        // Inserting the ahead seed's entry (a later bucket) is what triggers
        // the prune.
        _ = cache.textureGeometry(
            seed: seedAhead, spec: spec, radii: radii(), complexity: 0.5, time: t)

        // Different radii on the re-query: an eviction would show up as a
        // freshly regenerated (and therefore different) result.
        let secondBehind = cache.textureGeometry(
            seed: seedBehind, spec: spec, radii: radii(complexity: 0.9), complexity: 0.5, time: t)

        XCTAssertEqual(firstBehind, secondBehind,
                       "The phased-behind seed's entry must survive the phased-ahead seed's prune")
    }
}
