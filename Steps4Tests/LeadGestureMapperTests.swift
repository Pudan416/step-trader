#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class LeadGestureMapperTests: XCTestCase {
    func testMapperUsesLeadPlanBoundaryOwnershipForAllTwentyOneRegions() {
        let plan = makeLeadPlan()
        var mapper = LeadGestureMapper(plan: plan)

        for index in plan.pitchRegions.indices {
            let x = plan.pitchRegions[index].normalizedRange.lowerBound
            let mapping = mapper.map(
                .init(normalizedX: x, normalizedY: 0.5, speed: 0),
                chordIndex: 0
            )

            XCTAssertEqual(mapping.regionIndex, plan.regionIndex(forNormalizedX: x))
            XCTAssertEqual(mapping.midiNote, plan.pitchRegions[mapping.regionIndex].midiNotesByChord[0])
        }
        XCTAssertEqual(mapper.map(.init(normalizedX: 1, normalizedY: 0.5, speed: 0), chordIndex: 0).regionIndex, 20)
    }

    func testMapperClampsCoordinatesSpeedAndKeepsEveryOutputFiniteAndBounded() {
        let plan = makeLeadPlan()
        var mapper = LeadGestureMapper(plan: plan)

        let low = mapper.map(
            .init(normalizedX: -.infinity, normalizedY: .infinity, speed: -.infinity),
            chordIndex: -100
        )
        let high = mapper.map(
            .init(normalizedX: 9, normalizedY: -8, speed: 90),
            chordIndex: 100
        )
        let invalid = mapper.map(
            .init(normalizedX: .nan, normalizedY: .nan, speed: .nan),
            chordIndex: 0
        )

        for mapping in [low, high, invalid] {
            XCTAssertTrue(mapping.cutoffMultiplier.isFinite)
            XCTAssertTrue(mapping.expressionDepth.isFinite)
            XCTAssertTrue(plan.cutoffMultiplierRange.contains(mapping.cutoffMultiplier))
            XCTAssertTrue((0...plan.maximumExpressionDepth).contains(mapping.expressionDepth))
            XCTAssertTrue(plan.register.contains(mapping.midiNote))
        }
        XCTAssertEqual(high.regionIndex, 20)
        XCTAssertLessThanOrEqual(high.expressionDepth, 0.25)
    }

    func testStationaryTouchIsStableAndSuccessiveCutoffAndExpressionChangesAreSmoothed() {
        let plan = makeLeadPlan()
        var mapper = LeadGestureMapper(plan: plan)
        let stationary = LeadGestureSample(normalizedX: 0.5, normalizedY: 0.5, speed: 0)

        let first = mapper.map(stationary, chordIndex: 0)
        let second = mapper.map(stationary, chordIndex: 0)
        XCTAssertEqual(second, first)

        let moved = mapper.map(
            .init(normalizedX: 0.5, normalizedY: 0, speed: 3),
            chordIndex: 0
        )
        XCTAssertGreaterThan(moved.cutoffMultiplier, first.cutoffMultiplier)
        XCTAssertLessThan(moved.cutoffMultiplier, plan.cutoffMultiplierRange.upperBound)
        XCTAssertGreaterThan(moved.expressionDepth, 0)
        XCTAssertLessThan(moved.expressionDepth, plan.maximumExpressionDepth)

        let held = mapper.map(
            .init(normalizedX: 0.5, normalizedY: 0, speed: 0),
            chordIndex: 0
        )
        XCTAssertEqual(held.regionIndex, moved.regionIndex)
        XCTAssertLessThan(held.expressionDepth, moved.expressionDepth)
        XCTAssertGreaterThanOrEqual(held.expressionDepth, 0)
    }

    private func makeLeadPlan() -> LeadPlan {
        let lowerBounds = (0..<21).map { index in
            index == 10 ? 0.39 : Double(index) / 21
        }
        let regions = lowerBounds.enumerated().map { index, lower in
            LeadPitchRegion(
                index: index,
                normalizedRange: lower...min(1, lower + 0.12),
                preference: index.isMultiple(of: 3) ? .chordTone : .modeTone,
                midiNotesByChord: [UInt8(57 + index), UInt8(58 + index)]
            )
        }
        return LeadPlan(
            instrumentID: .init(rawValue: "lead.verbacious"),
            maximumSimultaneousVoices: 1,
            register: 57...81,
            pitchRegions: regions,
            compatibleChordMIDINotes: [[57, 60, 64, 69], [59, 62, 65, 71]],
            portamentoMilliseconds: 110,
            attackSeconds: 0.035,
            releaseSeconds: 0.65,
            cutoffMultiplierRange: 0.55...1.35,
            pitchSmoothingMilliseconds: 45,
            expressionSmoothingMilliseconds: 80,
            maximumExpressionDepth: 0.25,
            delaySend: 0.24,
            reverbSend: 0.38
        )
    }
}
#endif
