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
