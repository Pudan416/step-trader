import XCTest
@testable import Steps4

/// The generator behind the ray fan. The picture is judged by eye; what has
/// to hold by argument is that a day is reproducible, that the forbidden
/// combinations never ship, and that the space is actually explored rather
/// than collapsing onto a few favourites.
final class DayRayCompositionTests: XCTestCase {

    private func days(_ count: Int) -> [String] {
        (0..<count).map { String(format: "2026-%02d-%02d", ($0 / 28) % 12 + 1, $0 % 28 + 1) }
    }

    // MARK: - Determinism

    func testCompositionIsReproducibleFromTheDay() {
        let a = DayRayComposition.forDay(dayKey: "2026-08-19")
        let b = DayRayComposition.forDay(dayKey: "2026-08-19")
        XCTAssertEqual(a, b)
    }

    func testIdentityChangesTheDay() {
        // Two people on the same date must not get the same picture.
        let a = DayRayComposition.forDay(dayKey: "2026-08-19", identity: "person-a")
        let b = DayRayComposition.forDay(dayKey: "2026-08-19", identity: "person-b")
        XCTAssertNotEqual(a, b)
    }

    func testBladesAreReproducible() {
        let c = DayRayComposition.forDay(dayKey: "2026-08-19")
        XCTAssertEqual(
            c.blades(happeningCount: 4, dayKey: "2026-08-19"),
            c.blades(happeningCount: 4, dayKey: "2026-08-19")
        )
    }

    // MARK: - Forbidden combinations

    func testForbiddenCombinationsNeverSurvive() {
        for key in days(400) {
            let c = DayRayComposition.forDay(dayKey: key)

            if c.motion == .swirl {
                XCTAssertNotEqual(c.anchor, .band, "swirl on a detached ring at \(key)")
            }
            if c.center == .offscreen {
                XCTAssertNotEqual(c.symmetry, .rotational,
                                  "rotational symmetry off-screen at \(key)")
                // Otherwise the fan sits entirely outside the frame and the
                // day renders as an empty background.
                XCTAssertEqual(c.scale, .overflow, "unreachable fan at \(key)")
            }
            if c.motion == .still {
                XCTAssertNotEqual(c.shape, .comet, "frozen comet at \(key)")
            }
            if c.layers == 2 {
                XCTAssertNotEqual(c.density, .dense, "two dense fans at \(key)")
            }
        }
    }

    // MARK: - Coverage

    func testEveryCoarseAxisValueIsReachable() {
        var centers = Set<RayFanCenter>()
        var scales = Set<RayFanScale>()
        var densities = Set<RayFanDensity>()
        var keys = Set<RayTonalKey>()
        var shapes = Set<RayBladeShape>()
        var anchors = Set<RayFanAnchor>()
        var motions = Set<RayMotion>()

        for key in days(400) {
            let c = DayRayComposition.forDay(dayKey: key)
            centers.insert(c.center)
            scales.insert(c.scale)
            densities.insert(c.density)
            keys.insert(c.key)
            shapes.insert(c.shape)
            anchors.insert(c.anchor)
            motions.insert(c.motion)
        }

        XCTAssertEqual(centers.count, RayFanCenter.allCases.count)
        XCTAssertEqual(scales.count, RayFanScale.allCases.count)
        XCTAssertEqual(densities.count, RayFanDensity.allCases.count)
        XCTAssertEqual(keys.count, RayTonalKey.allCases.count)
        XCTAssertEqual(shapes.count, RayBladeShape.allCases.count)
        XCTAssertEqual(anchors.count, RayFanAnchor.allCases.count)
        XCTAssertEqual(motions.count, RayMotion.allCases.count)
    }

    func testNoSingleFrameDominatesTheYear() {
        // A generator that technically reaches every value but lands on one
        // combination a third of the time is not a generative system.
        var counts: [String: Int] = [:]
        let sample = days(365)
        for key in sample {
            let c = DayRayComposition.forDay(dayKey: key)
            let frame = "\(c.center)|\(c.scale)|\(c.density)|\(c.key)|\(c.symmetry)"
            counts[frame, default: 0] += 1
        }
        let worst = counts.values.max() ?? 0
        XCTAssertLessThan(Double(worst) / Double(sample.count), 0.10,
                          "one frame covers \(worst) of \(sample.count) days")
        XCTAssertGreaterThan(counts.count, 40, "only \(counts.count) distinct frames in a year")
    }

    // MARK: - Blades

    func testBladeCountMatchesDensity() {
        for key in days(200) {
            let c = DayRayComposition.forDay(dayKey: key)
            XCTAssertTrue(c.density.range.contains(c.bladeCount))
            XCTAssertEqual(c.blades(happeningCount: 5, dayKey: key).count, c.bladeCount)
        }
    }

    func testBladeCountIgnoresHowMuchWasLogged() {
        // How diligently someone journals must not decide how full the frame
        // looks — happenings group the blades, they do not create them.
        let c = DayRayComposition.forDay(dayKey: "2026-08-19")
        for count in 0...10 {
            XCTAssertEqual(c.blades(happeningCount: count, dayKey: "2026-08-19").count, c.bladeCount)
        }
    }

    func testBladeGeometryIsUsable() {
        for key in days(120) {
            let c = DayRayComposition.forDay(dayKey: key)
            for blade in c.blades(happeningCount: 3, dayKey: key) {
                XCTAssertTrue(blade.angle.isFinite)
                XCTAssertGreaterThan(blade.length, 0)
                XCTAssertGreaterThan(blade.halfWidthInner, 0)
                XCTAssertGreaterThan(blade.halfWidthOuter, 0)
                XCTAssertGreaterThanOrEqual(blade.innerRadius, 0)
                XCTAssertTrue(blade.softness > 0 && blade.softness <= 1)
                XCTAssertTrue((0..<1).contains(blade.hue), "hue out of range: \(blade.hue)")
            }
        }
    }

    func testDarkShareFollowsTheTonalKey() {
        for key in days(200) {
            let c = DayRayComposition.forDay(dayKey: key)
            switch c.key {
            case .light: XCTAssertGreaterThan(c.darkShare, 0.5)
            case .dark:  XCTAssertLessThanOrEqual(c.darkShare, 0.35)
            }
        }
    }

    // MARK: - Packing

    func testPackingStrideMatchesTheShader() {
        let c = DayRayComposition.forDay(dayKey: "2026-08-19")
        let blades = c.blades(happeningCount: 4, dayKey: "2026-08-19")
        let packed = DayRaysView.pack(blades)
        // 12 floats per blade — `kRayStride` in DayRaysShader.metal.
        XCTAssertEqual(packed.count, blades.count * 12)
        XCTAssertTrue(packed.allSatisfy { $0.isFinite })
    }

    func testHsbConversionMatchesKnownColours() {
        let red = DayRaysView.hsbToRgb(h: 0, s: 1, b: 1)
        XCTAssertEqual(red.r, 1, accuracy: 0.001)
        XCTAssertEqual(red.g, 0, accuracy: 0.001)

        let cyan = DayRaysView.hsbToRgb(h: 0.5, s: 1, b: 1)
        XCTAssertEqual(cyan.r, 0, accuracy: 0.001)
        XCTAssertEqual(cyan.b, 1, accuracy: 0.001)

        let grey = DayRaysView.hsbToRgb(h: 0.3, s: 0, b: 0.5)
        XCTAssertEqual(grey.r, 0.5, accuracy: 0.001)
        XCTAssertEqual(grey.g, 0.5, accuracy: 0.001)
    }
}
