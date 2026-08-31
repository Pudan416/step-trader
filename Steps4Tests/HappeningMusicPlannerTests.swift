import XCTest
@testable import Steps4

final class HappeningMusicPlannerTests: XCTestCase {
    func testEveryFamilyProducesABoundedCatalogBackedStableIdentity() throws {
        let ids = (0..<200).map { "event-\($0)" }
        let world = tonalWorld(ids: [])
        let plans = ids.compactMap { makePlans(ids: [$0], tonalWorld: world).first }
        let descriptorByID = Dictionary(
            uniqueKeysWithValues: DayObjectsInstrumentManifest.defaultDescriptors.map { ($0.id, $0) }
        )

        XCTAssertEqual(Set(plans.map(\.family)), Set(HappeningSoundFamily.allCases))
        XCTAssertEqual(plans.count, ids.count)
        for plan in plans {
            let descriptor = try XCTUnwrap(descriptorByID[plan.instrumentID])
            XCTAssertTrue(plan.family.compatibleCategories.contains(descriptor.category))
            XCTAssertTrue((1...3).contains(plan.motifScaleDegrees.count))
            XCTAssertTrue(plan.motifScaleDegrees.allSatisfy(world.mode.scaleIntervals.contains))
            XCTAssertTrue((3...6).contains(plan.octave))
            XCTAssertTrue(plan.pan.isFinite && (-0.85...0.85).contains(plan.pan))
            XCTAssertTrue(plan.gain.isFinite && (HappeningMusicPlan.minimumAudibleGain...0.30).contains(plan.gain))
            XCTAssertTrue(plan.birthGain.isFinite && (plan.gain...0.38).contains(plan.birthGain))
            XCTAssertTrue(plan.attackSeconds.isFinite && plan.attackSeconds > 0)
            XCTAssertTrue(plan.releaseSeconds.isFinite && plan.releaseSeconds > plan.attackSeconds)
            XCTAssertTrue(plan.delaySend.isFinite && (0...0.60).contains(plan.delaySend))
            XCTAssertTrue(plan.reverbSend.isFinite && (0...0.75).contains(plan.reverbSend))
            XCTAssertNotEqual(plan.recurrence.scheduleSeed, 0)
            XCTAssertTrue(plan.recurrence.floatingOffsetBeats.isFinite)
            XCTAssertTrue((0.25...0.50).contains(abs(plan.recurrence.floatingOffsetBeats)))
        }
    }

    func testAddingRemovingOrReorderingIDsLeavesEverySurvivingPlanEqual() throws {
        let survivors = ["walk", "event.7/alpha", "read", "call-mom"]
        let original = makePlans(ids: survivors)
        let changed = makePlans(ids: ["new-first", "read", "walk", "call-mom", "event.7/alpha"])

        for id in survivors {
            XCTAssertEqual(
                try XCTUnwrap(original.first { $0.happeningID == id }),
                try XCTUnwrap(changed.first { $0.happeningID == id })
            )
        }
    }

    func testDescriptorOrderDoesNotChangeInstrumentOrEffects() {
        let ids = (0..<10).map { "stable-\($0)" }
        let forward = makePlans(ids: ids)
        let reversed = makePlans(
            ids: ids,
            descriptors: Array(DayObjectsInstrumentManifest.defaultDescriptors.reversed())
        )

        XCTAssertEqual(forward, reversed)
    }

    func testTenVoicesKeepAudiblePerEventGainsWithoutSummingTenFullLevelVoices() {
        let plans = makePlans(ids: (0..<10).map { "event-\($0)" })

        XCTAssertEqual(plans.count, 10)
        XCTAssertTrue(plans.allSatisfy {
            $0.gain >= HappeningMusicPlan.minimumAudibleGain &&
            $0.birthGain >= HappeningMusicPlan.minimumAudibleGain &&
            $0.gain.isFinite && $0.birthGain.isFinite
        })
        XCTAssertLessThan(plans.reduce(0) { $0 + $1.gain }, 3)
        XCTAssertLessThan(plans.reduce(0) { $0 + $1.birthGain }, 4)
    }

    func testMissingCompatibleCatalogEntriesOmitOnlyAffectedFamiliesWithoutInventingIDs() {
        let ids = (0..<60).map { "event-\($0)" }
        let plucksOnly = DayObjectsInstrumentManifest.descriptors(in: .pluck)
        let plans = ids.compactMap { makePlans(ids: [$0], descriptors: plucksOnly).first }

        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { [.pluck, .softOneShot].contains($0.family) })
        XCTAssertTrue(plans.allSatisfy { plan in
            plucksOnly.contains { $0.id == plan.instrumentID }
        })
        XCTAssertTrue(makePlans(ids: ids, descriptors: []).isEmpty)
    }

    private let remixSeed: UInt64 = 0xD4A0_B1EC_75ED_0001

    private func makePlans(
        ids: [String],
        descriptors: [DayObjectsInstrumentDescriptor] = DayObjectsInstrumentManifest.defaultDescriptors,
        tonalWorld: TonalWorldPlan? = nil
    ) -> [HappeningMusicPlan] {
        let world = tonalWorld ?? self.tonalWorld(ids: ids)
        return HappeningMusicPlanner.makePlans(
            input: input(ids: ids),
            tonalWorld: world,
            instrumentDescriptors: descriptors,
            remixSeed: remixSeed
        )
    }

    private func tonalWorld(ids: [String]) -> TonalWorldPlan {
        TonalWorldPlanner.makePlan(input: input(ids: ids), remixSeed: remixSeed)
    }

    private func input(ids: [String]) -> NormalizedDayMusicInput {
        NormalizedDayMusicInput(
            stepsProgress: 0.61,
            sleepProgress: 0.74,
            happeningIDs: ids,
            glitchProgress: 0.31,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            diagnostics: []
        )
    }
}
