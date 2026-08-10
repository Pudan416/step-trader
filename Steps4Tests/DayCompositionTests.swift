import XCTest
@testable import Steps4

/// One composition per day, derived from the day. Everything an element does
/// — where it lands, how big it is, which colour, which fill — follows from
/// this, so a canvas reads as one work and two days read as different works.
final class DayCompositionTests: XCTestCase {

    // MARK: - Determinism

    func testCompositionIsReproducibleFromTheDayKey() {
        let a = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
        let b = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
        XCTAssertEqual(a, b)
    }

    func testDifferentDaysGetDifferentCompositions() {
        let keys = (1...28).map { String(format: "2026-08-%02d", $0) }
        let archetypes = keys.map {
            DayComposition.forDay(dayKey: $0, happeningCount: 5).archetype
        }
        XCTAssertGreaterThan(Set(archetypes).count, 3,
                             "A month should not collapse to one archetype")
    }

    /// Adding a happening must not reshuffle the day's identity — the picture
    /// grows, it does not restart.
    func testArchetypeAndPaletteAreStableAsTheDayFills() {
        let first = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 1)
        for count in 2...10 {
            let later = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: count)
            XCTAssertEqual(later.archetype, first.archetype, "at \(count)")
            XCTAssertEqual(later.palette, first.palette, "at \(count)")
            XCTAssertEqual(later.contrastKey, first.contrastKey, "at \(count)")
        }
    }

    func testAllArchetypesAreReachable() {
        var seen = Set<CompositionArchetype>()
        for day in 1...200 {
            seen.insert(DayComposition.forDay(
                dayKey: "2026-\(day % 12 + 1)-\(day % 28 + 1)",
                happeningCount: 5).archetype)
        }
        XCTAssertEqual(seen.count, CompositionArchetype.allCases.count,
                       "Unreachable archetypes: \(Set(CompositionArchetype.allCases).subtracting(seen))")
    }

    // MARK: - Weight fields

    func testEveryArchetypeProducesAUsableField() {
        for archetype in CompositionArchetype.allCases {
            var maxWeight = 0.0
            var minWeight = 1.0
            for xStep in 0...10 {
                for yStep in 0...10 {
                    let p = CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)
                    let w = archetype.weight(at: p)
                    XCTAssertTrue((0...1).contains(w),
                                  "\(archetype) weight \(w) out of range at \(p)")
                    maxWeight = max(maxWeight, w)
                    minWeight = min(minWeight, w)
                }
            }
            XCTAssertGreaterThan(maxWeight, 0.6, "\(archetype) has no high ground")
        }
    }

    /// Constellation is the only even field. Every other archetype must
    /// actually concentrate mass somewhere — that is what makes it a
    /// composition rather than a scatter.
    func testNonConstellationArchetypesConcentrateMass() {
        for archetype in CompositionArchetype.allCases where archetype != .constellation {
            var weights = [Double]()
            for xStep in 0...10 {
                for yStep in 0...10 {
                    weights.append(archetype.weight(
                        at: CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)))
                }
            }
            let spread = (weights.max() ?? 0) - (weights.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.5, "\(archetype) field is too flat")
        }
    }

    func testConstellationIsEven() {
        var weights = [Double]()
        for xStep in 0...10 {
            for yStep in 0...10 {
                weights.append(CompositionArchetype.constellation.weight(
                    at: CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)))
            }
        }
        XCTAssertLessThan((weights.max() ?? 0) - (weights.min() ?? 0), 0.2)
    }

    func testWeightFieldsAreDeterministic() {
        for archetype in CompositionArchetype.allCases {
            let p = CGPoint(x: 0.37, y: 0.62)
            XCTAssertEqual(archetype.weight(at: p), archetype.weight(at: p))
        }
    }

    // MARK: - Size hierarchy

    func testSizeMultipliersStayInRange() {
        for archetype in CompositionArchetype.allCases {
            for count in 1...15 {
                for rank in 0..<count {
                    let m = archetype.sizeMultiplier(rank: rank, count: count)
                    XCTAssertTrue((0.4...2.0).contains(m),
                                  "\(archetype) rank \(rank)/\(count) → \(m)")
                }
            }
        }
    }

    /// Centred mass means one dominant form; constellation means peers. The
    /// two must not produce the same size curve, or every canvas ends up with
    /// the same skeleton.
    func testArchetypesDifferInSizeCurve() {
        let centred = (0..<8).map {
            CompositionArchetype.centeredMass.sizeMultiplier(rank: $0, count: 8)
        }
        let constellation = (0..<8).map {
            CompositionArchetype.constellation.sizeMultiplier(rank: $0, count: 8)
        }
        func spread(_ v: [Double]) -> Double { (v.max() ?? 0) - (v.min() ?? 0) }
        XCTAssertGreaterThan(spread(centred), spread(constellation))
    }

    // MARK: - Palette

    func testPaletteIsSmallAndOnPalette() {
        for day in 1...60 {
            let composition = DayComposition.forDay(
                dayKey: "2026-03-\(day % 28 + 1)", happeningCount: 8)
            XCTAssertTrue((3...5).contains(composition.palette.count),
                          "Palette size \(composition.palette.count)")
            for hex in composition.palette {
                XCTAssertTrue(CanvasColorPalette.paletteHex.contains(hex),
                              "\(hex) is off-palette")
            }
            XCTAssertEqual(Set(composition.palette).count, composition.palette.count,
                           "Palette has duplicates")
        }
    }

    func testColourForRankCyclesThroughThePalette() {
        let composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 10)
        let used = Set((0..<10).map { composition.color(forRank: $0) })
        XCTAssertGreaterThan(used.count, 1, "A day must use more than one colour")
        for hex in used {
            XCTAssertTrue(composition.palette.contains(hex))
        }
    }

    // MARK: - Contrast

    func testContrastKeyShapesTheOpacityRange() {
        func range(_ key: ContrastKey) -> ClosedRange<Double> {
            var composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
            composition.contrastKey = key
            return composition.opacityRange(forRank: 0)
        }
        XCTAssertLessThan(range(.low).upperBound - range(.low).lowerBound,
                          range(.high).upperBound - range(.high).lowerBound)
    }

    func testOpacityRangesStayRenderable() {
        for key in ContrastKey.allCases {
            var composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
            composition.contrastKey = key
            for rank in 0..<12 {
                let range = composition.opacityRange(forRank: rank)
                XCTAssertGreaterThanOrEqual(range.lowerBound, 0.08)
                XCTAssertLessThanOrEqual(range.upperBound, 0.9)
                XCTAssertLessThan(range.lowerBound, range.upperBound)
            }
        }
    }

    // MARK: - Texture policy

    func testTexturePolicyMixesDominantAndAccent() {
        let policy = TexturePolicy(dominant: .gradient, accent: .hatch, accentShare: 0.3)
        let kinds = (0..<20).map { policy.kind(forRank: $0) }
        XCTAssertTrue(kinds.contains(.gradient))
        XCTAssertTrue(kinds.contains(.hatch))
        XCTAssertGreaterThan(kinds.filter { $0 == .gradient }.count,
                             kinds.filter { $0 == .hatch }.count,
                             "Dominant must dominate")
    }

    func testTexturePolicyIsDeterministic() {
        let policy = TexturePolicy(dominant: .stipple, accent: .flat, accentShare: 0.4)
        XCTAssertEqual((0..<20).map { policy.kind(forRank: $0) },
                       (0..<20).map { policy.kind(forRank: $0) })
    }

    func testDayPoliciesVaryAcrossTheMonth() {
        let policies = (1...28).map {
            DayComposition.forDay(dayKey: String(format: "2026-08-%02d", $0),
                                  happeningCount: 6).texturePolicy
        }
        XCTAssertGreaterThan(Set(policies.map(\.dominant)).count, 2,
                             "A month should not use one dominant fill")
    }

    func testAccentIsNeverTheDominant() {
        for day in 1...100 {
            let policy = DayComposition.forDay(
                dayKey: "2026-05-\(day % 28 + 1)", happeningCount: 6).texturePolicy
            XCTAssertNotEqual(policy.dominant, policy.accent)
        }
    }

    // MARK: - Codable

    func testCompositionRoundTrips() throws {
        let composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 7)
        let data = try JSONEncoder().encode(composition)
        XCTAssertEqual(try JSONDecoder().decode(DayComposition.self, from: data),
                       composition)
    }
}
