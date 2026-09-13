import XCTest
import SwiftUI
@testable import Steps4

/// `SimplexNoise2D` is the shared source of coherent randomness: contour
/// deformation, texture density fields, and composition weighting all draw on
/// it. Two properties matter — reproducible from its seed, and correlated
/// between neighbouring samples.
final class SimplexNoiseTests: XCTestCase {

    // MARK: - Stream separation

    func testDerivedStreamsWithDifferentDomainsDiverge() {
        var a = SeededRNG.derived(from: 12345, domain: "shape")
        var b = SeededRNG.derived(from: 12345, domain: "placement")
        XCTAssertNotEqual(a.next(), b.next(), "Domains must isolate streams")
    }

    func testDerivedStreamIsReproducible() {
        var a = SeededRNG.derived(from: 999, domain: "texture")
        var b = SeededRNG.derived(from: 999, domain: "texture")
        XCTAssertEqual(
            (0..<8).map { _ in a.next() },
            (0..<8).map { _ in b.next() }
        )
    }

    // MARK: - Determinism

    func testSameSeedProducesIdenticalField() {
        let a = SimplexNoise2D(seed: 0xDEADBEEF)
        let b = SimplexNoise2D(seed: 0xDEADBEEF)
        for i in 0..<200 {
            let x = Double(i) * 0.137
            let y = Double(i) * -0.211
            XCTAssertEqual(a.value(x, y), b.value(x, y), accuracy: 0)
        }
    }

    func testDifferentSeedsProduceDifferentFields() {
        let a = SimplexNoise2D(seed: 1)
        let b = SimplexNoise2D(seed: 2)
        let differences = (0..<100).filter { i in
            abs(a.value(Double(i) * 0.31, 0.5) - b.value(Double(i) * 0.31, 0.5)) > 1e-9
        }
        XCTAssertGreaterThan(differences.count, 80)
    }

    func testSeedZeroIsValid() {
        XCTAssertTrue(SimplexNoise2D(seed: 0).value(1.5, 2.5).isFinite)
    }

    // MARK: - Range
    //
    // The 70.0 scaling constant is empirical, so the field can overshoot unity
    // very slightly. 1.05 is the tolerance every caller is written against.

    func testValueStaysWithinUnitRange() {
        let noise = SimplexNoise2D(seed: 42)
        for i in 0..<5_000 {
            let x = Double(i) * 0.0173
            let y = Double(i) * 0.0291 - 40
            let v = noise.value(x, y)
            XCTAssertGreaterThanOrEqual(v, -1.05, "Out of range at \(x),\(y)")
            XCTAssertLessThanOrEqual(v, 1.05, "Out of range at \(x),\(y)")
        }
    }

    func testFbmStaysWithinUnitRange() {
        let noise = SimplexNoise2D(seed: 7)
        for i in 0..<2_000 {
            let x = Double(i) * 0.023
            let v = noise.fbm(x, x * 0.7, octaves: 2, persistence: 0.45, lacunarity: 2.0)
            XCTAssertGreaterThanOrEqual(v, -1.05)
            XCTAssertLessThanOrEqual(v, 1.05)
        }
    }

    // MARK: - Continuity

    func testNeighbouringSamplesAreCorrelated() {
        let noise = SimplexNoise2D(seed: 314)
        var maxJump = 0.0
        for i in 0..<1_000 {
            let x = Double(i) * 0.05
            maxJump = max(maxJump, abs(noise.value(x, 3.0) - noise.value(x + 0.001, 3.0)))
        }
        XCTAssertLessThan(maxJump, 0.05, "A 0.001 step must not swing the field")
    }

    func testFieldIsNotConstant() {
        let noise = SimplexNoise2D(seed: 55)
        let samples = (0..<500).map { noise.value(Double($0) * 0.19, 1.7) }
        XCTAssertGreaterThan(samples.max()! - samples.min()!, 0.8)
    }

    func testNegativeCoordinatesBehave() {
        let noise = SimplexNoise2D(seed: 88)
        for i in 1...500 {
            let v = noise.value(Double(-i) * 0.37, Double(-i) * 0.11)
            XCTAssertTrue(v.isFinite)
            XCTAssertGreaterThanOrEqual(v, -1.05)
            XCTAssertLessThanOrEqual(v, 1.05)
        }
    }
}

// MARK: - Organic blob contour

final class OrganicBlobContourTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 0, width: 200, height: 200)

    func testRadiiAreReproducibleFromSeed() {
        let a = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 4242, complexity: 0.5, symmetry: 1, time: 0)
        let b = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 4242, complexity: 0.5, symmetry: 1, time: 0)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsGiveDifferentContours() {
        let a = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 1, complexity: 0.5, symmetry: 1, time: 0)
        let b = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 2, complexity: 0.5, symmetry: 1, time: 0)
        XCTAssertNotEqual(a, b)
    }

    /// The star-shaped guarantee. While every radius stays positive the contour
    /// cannot self-intersect, which is why no clean-up pass is needed — and why
    /// textures can safely clip to it.
    func testRadiiStayPositiveAcrossTheParameterSpace() {
        for seed in stride(from: UInt64(0), to: 400, by: 7) {
            for complexityStep in 0...10 {
                let complexity = Double(complexityStep) / 10.0
                let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                    seed: seed, complexity: complexity, symmetry: 1, time: 0)
                XCTAssertGreaterThan(radii.min() ?? 0, 0.5,
                                     "seed \(seed) complexity \(complexity)")
                XCTAssertLessThan(radii.max() ?? 99, 1.5)
            }
        }
    }

    /// The regression this task exists to fix. The old sine-sum generator drew
    /// a fresh random phase per point, so adjacent radii could differ by the
    /// full amplitude — around 1.0. 0.25 is comfortably below that and
    /// comfortably above what a correctly sampled ring produces.
    func testAdjacentRadiiAreCorrelated() {
        for seed in stride(from: UInt64(0), to: 200, by: 11) {
            let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: seed, complexity: 1.0, symmetry: 1, time: 0)
            for i in radii.indices {
                XCTAssertLessThan(
                    abs(radii[i] - radii[(i + 1) % radii.count]), 0.25,
                    "Discontinuity at point \(i) of seed \(seed)")
            }
        }
    }

    func testContourIsSeamlessAtTheWrapPoint() {
        for seed in stride(from: UInt64(0), to: 200, by: 11) {
            let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: seed, complexity: 0.8, symmetry: 1, time: 0)
            XCTAssertLessThan(abs(radii.first! - radii.last!), 0.25,
                              "Seam at seed \(seed)")
        }
    }

    func testTimeMorphsTheContourGraduallyNotAbruptly() {
        let t0 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 0)
        let t1 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 1)
        let t100 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 100)

        let oneSecond = zip(t0, t1).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(oneSecond, 0, "The contour must actually animate")
        XCTAssertLessThan(oneSecond, 0.05, "One second must not jump the shape")

        let longRun = zip(t0, t100).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(longRun, 0.05, "Over 100s it must visibly morph")
    }

    /// Averaged over seeds: a single seed can pair a quiet patch of the field
    /// with the higher amplitude and invert the comparison.
    func testComplexityIncreasesDeviationFromACircle() {
        func deviation(_ complexity: Double) -> Double {
            let perSeed = stride(from: UInt64(0), to: 300, by: 13).map { seed -> Double in
                let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                    seed: seed, complexity: complexity, symmetry: 1, time: 0)
                return radii.map { abs($0 - 1.0) }.reduce(0, +) / Double(radii.count)
            }
            return perSeed.reduce(0, +) / Double(perSeed.count)
        }
        XCTAssertLessThan(deviation(0.0), deviation(1.0))
    }

    func testPointCountStaysWithinThePerformanceBudget() {
        // CanvasLab-Spec §16: no shape may exceed 200 points, and the organic
        // blob renderer stacks 4 layers per element.
        let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 1, complexity: 1.0, symmetry: 1, time: 0)
        XCTAssertLessThanOrEqual(radii.count * 4, 200)
    }

    func testPathIsNonEmptyAndBounded() {
        let path = ProceduralShapeGenerator.organicBlobPath(
            seed: 909, complexity: 0.5, symmetry: 1, time: 0, in: rect)
        XCTAssertFalse(path.isEmpty)
        // Max radius factor 1.32 around a centre of 100 with radius 100.
        XCTAssertTrue(rect.insetBy(dx: -40, dy: -40).contains(path.boundingRect))
    }

    func testSymmetryFoldingStillMirrors() {
        let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 606, complexity: 0.7, symmetry: 6, time: 0)
        let sector = radii.count / 6
        for i in 0..<sector {
            XCTAssertEqual(radii[i], radii[i + sector], accuracy: 1e-9,
                           "Sector \(i) did not mirror")
        }
    }
}

// MARK: - Snowflake texture profile

final class SnowflakeTextureProfileTests: XCTestCase {
    private let rect = CGRect(x: 20, y: 40, width: 200, height: 200)

    private func curveEndpoints(in path: Path) -> [CGPoint] {
        var endpoints = [CGPoint]()
        path.forEach { element in
            if case let .quadCurve(endpoint, _) = element {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    func testFrameExposesNormalisedPositiveProfile() {
        let frame = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        XCTAssertEqual(frame.textureProfile.radii.count, 64)
        XCTAssertLessThanOrEqual(frame.textureProfile.radii.max() ?? 0, 1)
        XCTAssertTrue(frame.textureProfile.radii.allSatisfy { $0.isFinite && $0 > 0 })
        XCTAssertGreaterThan(frame.textureProfile.outerRadius, 0)
    }

    func testProfileIsDeterministic() {
        let first = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        let second = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        XCTAssertEqual(first.textureProfile, second.textureProfile)
    }

    func testProfileMovesContinuouslyAcrossSmallTimeStep() {
        let first = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        let second = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3.01, in: rect)
        let meanDelta = zip(first.textureProfile.radii, second.textureProfile.radii)
            .map { abs($0 - $1) }
            .reduce(0, +) / 64
        XCTAssertGreaterThan(meanDelta, 0)
        XCTAssertLessThan(meanDelta, 0.02)
    }

    func testEveryTextureKindBuildsSnowflakeGeometry() {
        let frame = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        for kind in TextureKind.allCases {
            let spec = TextureSpec(
                kind: kind, density: 0.7, uniformity: 0.4, angle: 1)
            let geometry = ProceduralTexture.geometry(
                spec: spec, radii: frame.textureProfile.radii, seed: 42)
            switch kind {
            case .flat, .gradient, .outline:
                XCTAssertEqual(geometry, TextureGeometry())
            case .rings:
                XCTAssertFalse(geometry.rings.isEmpty)
            case .hatch:
                XCTAssertFalse(geometry.lines.isEmpty)
            }
        }
    }

    func testFramePathPreservesLegacySnowflakeCurveGeometry() {
        let frame = ProceduralShapeGenerator.rectMorphFrame(
            seed: 42, time: 3, in: rect)
        let endpoints = curveEndpoints(in: frame.path)

        XCTAssertEqual(endpoints.count, 64)
        // Golden from the pre-Task-2 path. This is an actual point on the
        // smoothed quadratic curve (the wrap segment's endpoint), not a
        // control point interpreted as a radial contour sample.
        XCTAssertEqual(endpoints.last?.x ?? 0, 156.24492645, accuracy: 1e-4)
        XCTAssertEqual(endpoints.last?.y ?? 0, 166.10271454, accuracy: 1e-4)
    }
}
