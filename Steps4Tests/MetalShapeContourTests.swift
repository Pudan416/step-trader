import XCTest
import simd
@testable import Steps4

final class MetalShapeContourTests: XCTestCase {
    func testCuratedGenomesAreFiniteClosedAndSmoothEnoughForMetal() throws {
        for preset in MetalShapeGenomeCatalog.presets where preset.source == .genome {
            let start = try MetalShapeContour.point(for: preset, angle: 0)
            let end = try MetalShapeContour.point(for: preset, angle: .pi * 2)
            XCTAssertLessThan(simd_distance(start, end), 0.0001, preset.id)

            let points = try MetalShapeContour.sample(preset: preset, count: 2_048)
            XCTAssertEqual(points.count, 2_048)
            XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, preset.id)
            let radii = points.map(simd_length)
            let minimumRadius: Float = preset.morphology == .superform ? 0.40 : 0.68
            XCTAssertGreaterThanOrEqual(radii.min() ?? 0, minimumRadius, preset.id)
            XCTAssertLessThanOrEqual(radii.max() ?? 2, 1.34, preset.id)
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                XCTAssertLessThan(simd_distance(points[index], next), 0.16, preset.id)
            }
            XCTAssertEqual(points, try MetalShapeContour.sample(preset: preset, count: 2_048))
        }
    }

    func testCuratedGenomesDoNotSelfIntersect() throws {
        for preset in MetalShapeGenomeCatalog.presets where preset.source == .genome {
            let points = try MetalShapeContour.sample(preset: preset, count: 512)
            XCTAssertFalse(hasSelfIntersection(points), preset.id)
        }
    }

    func testSuperformExamplesHaveDeepSharpValleysAndDifferentPetalRhythms() throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "genome.superform" })
        for seed in [UInt64(42), 314, 2_718] {
            let points = try MetalShapeContour.sample(preset: preset, count: 2_048, seed: seed)
            let radii = points.map(simd_length)
            XCTAssertLessThan((radii.min() ?? 1) / (radii.max() ?? 1), 0.62, "seed \(seed)")
            XCTAssertFalse(hasSelfIntersection(points), "seed \(seed)")
        }
        XCTAssertNotEqual(
            try MetalShapeContour.sample(preset: preset, count: 512, seed: 42),
            try MetalShapeContour.sample(preset: preset, count: 512, seed: 314)
        )
    }

    func testInvalidSamplingRequestsAreRejected() {
        let preset = MetalShapeGenomeCatalog.presets[0]
        XCTAssertThrowsError(try MetalShapeContour.sample(preset: preset, count: 2))
        let legacy = MetalShapeGenomeCatalog.presets.first { $0.source == .legacy }!
        XCTAssertThrowsError(try MetalShapeContour.sample(preset: legacy, count: 64))
    }

    private func hasSelfIntersection(_ points: [SIMD2<Float>]) -> Bool {
        guard points.count > 3 else { return false }
        for first in points.indices {
            let a = points[first]
            let b = points[(first + 1) % points.count]
            guard first + 2 < points.count else { continue }
            for second in (first + 2)..<points.count {
                if first == 0 && second == points.count - 1 { continue }
                let c = points[second]
                let d = points[(second + 1) % points.count]
                if intersects(a, b, c, d) { return true }
            }
        }
        return false
    }

    private func intersects(
        _ a: SIMD2<Float>, _ b: SIMD2<Float>,
        _ c: SIMD2<Float>, _ d: SIMD2<Float>
    ) -> Bool {
        func cross(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Float {
            let u = q - p
            let v = r - p
            return u.x * v.y - u.y * v.x
        }
        let abC = cross(a, b, c)
        let abD = cross(a, b, d)
        let cdA = cross(c, d, a)
        let cdB = cross(c, d, b)
        return abC * abD < -0.000_001 && cdA * cdB < -0.000_001
    }
}
