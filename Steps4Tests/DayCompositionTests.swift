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

    /// Spread alone doesn't catch a peak in the wrong place — this pins the
    /// high ground to the actual corner, which is what the archetype's name
    /// promises.
    func testCornerWeightActuallyFavoursItsCornerOverTheCentre() {
        let corner = CompositionArchetype.cornerWeight.weight(at: CGPoint(x: 0.15, y: 0.15))
        let centre = CompositionArchetype.cornerWeight.weight(at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertGreaterThan(corner, centre * 1.5,
                             "cornerWeight's high ground drifted to the middle")
    }

    func testCenteredMassPeaksAtTheCentre() {
        let centre = CompositionArchetype.centeredMass.weight(at: CGPoint(x: 0.5, y: 0.5))
        for point in [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
                      CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.9, y: 0.9)] {
            XCTAssertGreaterThan(centre, CompositionArchetype.centeredMass.weight(at: point))
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

    /// Pins the fix for the NaN this method used to produce: `spawn` always
    /// passes `DayComposition.nominalDayCount` as `count`, so `rank` routinely
    /// exceeds `count - 1` once a day has more than `nominalDayCount`
    /// elements — before the clamp, that pushed `position` past 1, and
    /// `cornerWeight`'s `pow(1 - position, 2.2)` on a negative base returned
    /// NaN, silently poisoning `size` (`min`/`max` against NaN pass NaN
    /// through). Every archetype, well past the nominal count, must still
    /// return a finite multiplier.
    func testSizeMultiplierIsFiniteBeyondTheNominalCount() {
        for archetype in CompositionArchetype.allCases {
            for rank in 0..<20 {
                let m = archetype.sizeMultiplier(rank: rank, count: DayComposition.nominalDayCount)
                XCTAssertTrue(m.isFinite, "\(archetype) rank \(rank) → \(m)")
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

    /// The guard `testArchetypesDifferInSizeCurve` didn't provide: every pair
    /// of archetypes, not just the one pair guaranteed to differ, must have a
    /// distinct size curve — otherwise two archetypes can share a skeleton
    /// unnoticed.
    ///
    /// This is a magnitude floor, not a shape check: two straight lines with
    /// different slopes clear it easily. `testCornerWeightDecaysRatherThanRamping`
    /// guards the shape property directly.
    func testEveryArchetypePairHasADistinctSizeCurve() {
        let count = 8
        let curves = CompositionArchetype.allCases.map { archetype in
            (archetype, (0..<count).map { archetype.sizeMultiplier(rank: $0, count: count) })
        }
        for i in curves.indices {
            for j in (i + 1)..<curves.count {
                let maxDiff = zip(curves[i].1, curves[j].1).map { abs($0 - $1) }.max() ?? 0
                XCTAssertGreaterThan(
                    maxDiff, 0.18,
                    "\(curves[i].0) and \(curves[j].0) share a size skeleton")
            }
        }
    }

    /// The magnitude test above is a floor, not a shape check — two straight lines
    /// with different slopes clear it easily, which is exactly the bug that once
    /// let `cornerWeight` and `diagonalSweep` share a skeleton. Curvature is what
    /// actually distinguishes them: a straight ramp has zero second difference,
    /// a decay does not.
    func testCornerWeightDecaysRatherThanRamping() {
        func curvature(_ archetype: CompositionArchetype) -> Double {
            let c = (0..<8).map { archetype.sizeMultiplier(rank: $0, count: 8) }
            var total = 0.0
            for i in 1..<(c.count - 1) {
                total += abs(c[i - 1] - 2 * c[i] + c[i + 1])
            }
            return total / Double(c.count - 2)
        }

        // diagonalSweep is deliberately a straight ramp.
        XCTAssertLessThan(curvature(.diagonalSweep), 0.01,
                          "diagonalSweep is meant to be linear")
        // cornerWeight must not be. It was a second straight ramp once, and that
        // made two of six archetypes produce the same composition skeleton.
        XCTAssertGreaterThan(curvature(.cornerWeight), 0.02,
                             "cornerWeight collapsed back into a linear ramp")
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

// MARK: - Spawn under a composition

final class ComposedSpawnTests: XCTestCase {

    private let dayKey = "2026-08-10"

    private func composition(_ count: Int = 0) -> DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: count)
    }

    private func spawn(
        optionId: String = "happening_walk",
        existing: [CanvasElement] = [],
        shapes: [CanvasShapeType] = [.organicBlob]
    ) -> CanvasElement {
        CanvasElement.spawn(
            optionId: optionId,
            label: "Walk",
            existingElements: existing,
            allowedShapeTypes: shapes,
            dayKey: dayKey,
            composition: composition(existing.count)
        )
    }

    // MARK: Determinism

    /// The point of the change: given the same day, option and index, the whole
    /// element is reproducible. Before this, only the contour was — size,
    /// position, colour and motion all came from the global RNG.
    func testSpawnIsFullyReproducible() {
        let a = spawn()
        let b = spawn()
        XCTAssertEqual(a.shapeSeed, b.shapeSeed)
        XCTAssertEqual(a.frozenShapeType, b.frozenShapeType)
        XCTAssertEqual(a.basePosition, b.basePosition)
        XCTAssertEqual(a.size, b.size)
        XCTAssertEqual(a.hexColor, b.hexColor)
        XCTAssertEqual(a.opacity, b.opacity)
        XCTAssertEqual(a.phaseOffset, b.phaseOffset)
        XCTAssertEqual(a.driftSpeed, b.driftSpeed)
    }

    func testShapeChoiceIsSeededNotRandom() {
        let shapes: [CanvasShapeType] = [.circle, .snowflake, .rays, .organicBlob]
        let picks = (0..<12).map { _ in spawn(shapes: shapes).frozenShapeType }
        XCTAssertEqual(Set(picks).count, 1)
    }

    func testEmptyAllowedListFallsBackToCircle() {
        XCTAssertEqual(spawn(shapes: []).frozenShapeType, .circle)
    }

    // MARK: Colour comes from the day's palette

    func testElementColoursComeFromTheDayPalette() {
        let dayPalette = Set(composition().palette)
        var existing: [CanvasElement] = []
        for i in 0..<10 {
            let element = spawn(optionId: "happening_\(i)", existing: existing)
            XCTAssertTrue(dayPalette.contains(element.hexColor),
                          "\(element.hexColor) is off the day's palette")
            existing.append(element)
        }
    }

    func testACanvasUsesMoreThanOneColour() {
        var existing: [CanvasElement] = []
        for i in 0..<6 {
            existing.append(spawn(optionId: "happening_\(i)", existing: existing))
        }
        XCTAssertGreaterThan(Set(existing.map(\.hexColor)).count, 1)
    }

    /// `spawn`'s "secondColour" stream picks two-colour ~60% of the time and
    /// single-colour ~40% of the time. Across enough ranks both must actually
    /// occur — this pins the fix that had `hexColor2` always set (spawn ignored
    /// its own computed local and fell back to `composition.color(forRank:
    /// rank + 1)` unconditionally), which made every element a gradient
    /// regardless of what the ~40% single-colour branch computed.
    func testACanvasHasBothSingleAndTwoColourElements() {
        var existing: [CanvasElement] = []
        for i in 0..<40 {
            existing.append(spawn(optionId: "happening_\(i)", existing: existing))
        }
        let hasSingleColour = existing.contains { $0.hexColor2 == nil }
        let hasTwoColour = existing.contains { $0.hexColor2 != nil }
        XCTAssertTrue(hasSingleColour, "No single-colour elements across 40 ranks")
        XCTAssertTrue(hasTwoColour, "No two-colour elements across 40 ranks")
    }

    // MARK: Placement follows the archetype

    func testSpawnStaysInsideTheMargin() {
        var existing: [CanvasElement] = []
        for i in 0..<15 {
            let element = spawn(optionId: "happening_\(i)", existing: existing)
            XCTAssertTrue(CanvasElement.spawnBounds.contains(element.basePosition),
                          "Element \(i) at \(element.basePosition) broke the margin")
            existing.append(element)
        }
    }

    /// Placement must actually follow the day's field, not ignore it. This
    /// exercised only one archetype via a hard-coded day key — if that key
    /// ever resolved to `constellation`, whose field is uniform by design
    /// (see `DayCompositionTests.testConstellationIsEven`), the test would
    /// fail outright with no way to distinguish "placement is broken" from
    /// "this archetype has no high ground to favour". Iterate day keys until
    /// several distinct non-constellation archetypes have each been checked.
    func testPlacementFavoursHighWeightRegions() {
        let archetypesToCover = Set(CompositionArchetype.allCases).subtracting([.constellation])
        var covered = Set<CompositionArchetype>()

        var dayIndex = 0
        while covered != archetypesToCover {
            dayIndex += 1
            XCTAssertLessThan(dayIndex, 1000, "Ran out of day keys before covering every archetype")
            guard dayIndex < 1000 else { break }

            let key = String(format: "2026-%02d-%02d", dayIndex % 12 + 1, dayIndex % 28 + 1)
            let dayComposition = DayComposition.forDay(dayKey: key, happeningCount: 0)
            let archetype = dayComposition.archetype
            // Constellation's field is uniform, so a weighted sampler cannot
            // outscore a uniform one there — skip it rather than fail on it.
            guard archetype != .constellation, !covered.contains(archetype) else { continue }
            covered.insert(archetype)

            var existing: [CanvasElement] = []
            for i in 0..<12 {
                existing.append(CanvasElement.spawn(
                    optionId: "happening_\(i)",
                    label: "Walk",
                    existingElements: existing,
                    allowedShapeTypes: [.organicBlob],
                    dayKey: key,
                    composition: DayComposition.forDay(dayKey: key, happeningCount: existing.count)
                ))
            }
            let meanWeight = existing
                .map { archetype.weight(at: $0.basePosition) }
                .reduce(0, +) / Double(existing.count)

            // A uniform scatter over the bounds would average the field's mean;
            // a weighted one must beat it.
            var uniformSum = 0.0
            var samples = 0
            for xStep in 0...20 {
                for yStep in 0...20 {
                    let p = CGPoint(
                        x: CanvasElement.spawnBounds.minX
                            + CanvasElement.spawnBounds.width * Double(xStep) / 20,
                        y: CanvasElement.spawnBounds.minY
                            + CanvasElement.spawnBounds.height * Double(yStep) / 20)
                    uniformSum += archetype.weight(at: p)
                    samples += 1
                }
            }
            XCTAssertGreaterThan(meanWeight, uniformSum / Double(samples),
                                 "\(archetype) placement ignored its own field")
        }

        XCTAssertEqual(covered, archetypesToCover,
                       "Did not find day keys covering every non-constellation archetype")
    }

    func testSpacingRelaxesAsTheCanvasFills() {
        XCTAssertGreaterThan(CanvasElement.spawnMinDistance(existingCount: 0),
                             CanvasElement.spawnMinDistance(existingCount: 10))
        XCTAssertGreaterThanOrEqual(
            CanvasElement.spawnMinDistance(existingCount: 30), 0.09)
    }

    // MARK: Size follows the archetype

    /// `spawn` clamps `size` to `0.04...0.48` unconditionally (see
    /// `min(0.48, max(0.04, base * multiplier))`), so asserting those bounds
    /// cannot fail regardless of whether the archetype's curve is wired up at
    /// all. Assert something the wiring can actually break instead: that the
    /// archetype's size curve produces more than one distinct size across a
    /// day's elements, i.e. `sizeMultiplier` is actually being consulted.
    func testSizeVariesAcrossTheArchetypesCurve() {
        var existing: [CanvasElement] = []
        for i in 0..<15 {
            existing.append(spawn(optionId: "happening_\(i)", existing: existing))
        }
        let sizes = existing.map(\.size)
        XCTAssertGreaterThan(Set(sizes).count, 1,
                             "Every element had the same size — the archetype's size curve had no effect")
    }

    // MARK: Texture follows the policy

    func testTextureSpecFollowsTheDayPolicy() {
        let day = composition()
        for rank in 0..<12 {
            let spec = CanvasElement.textureSpec(rank: rank, dayKey: dayKey, composition: day)
            XCTAssertEqual(spec.kind, day.texturePolicy.kind(forRank: rank))
        }
    }

    /// A same-process double-call comparison (the test this replaces) is blind
    /// by construction to a `hashValue`-derived seed: `String.hashValue` is
    /// randomised once per process, not once per call, so two calls in the same
    /// test run would agree with each other and still disagree with the next
    /// launch. These constants were captured from one real run of
    /// `CanvasElement.textureSpec(rank: 3, dayKey: "2026-08-10", composition:)`
    /// (via `makeSeed` → FNV-1a → `SeededRNG.derived(domain: "texture")`, none
    /// of which touch `String.hashValue`) and must reproduce on every run, on
    /// every launch, in every process — that cross-process stability is the
    /// entire point of the fix this test guards.
    func testTextureSpecIsDeterministic() {
        let day = composition()
        let spec = CanvasElement.textureSpec(rank: 3, dayKey: dayKey, composition: day)
        XCTAssertEqual(spec.density, 0.61565509146580877, accuracy: 1e-12)
        XCTAssertEqual(spec.uniformity, 0.35133926126910608, accuracy: 1e-12)
        XCTAssertEqual(spec.angle, 2.0681452615172895, accuracy: 1e-12)
    }

    // MARK: Reroll

    func testRerollChangesTheSeed() {
        var element = spawn()
        let before = element.shapeSeed
        element.reroll(rank: 0, composition: composition())
        XCTAssertNotEqual(element.shapeSeed, before)
    }

    func testRerollKeepsTheColourOnTheDayPalette() {
        var element = spawn()
        for _ in 0..<20 {
            element.reroll(rank: 2, composition: composition())
            XCTAssertTrue(composition().palette.contains(element.hexColor))
        }
    }

    func testRerollClearsTheUserSizeOverride() {
        var element = spawn()
        element.userSize = 0.4
        element.reroll(rank: 1, composition: composition())
        XCTAssertNil(element.userSize)
    }
}
