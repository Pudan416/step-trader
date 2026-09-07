import XCTest
@testable import Steps4

final class LeadPlannerTests: XCTestCase {
    func testNativeWorldLeadsChooseFourDistinctCuratedMoodSources() {
        for mood in DayObjectsSoundMood.allCases {
            let plans = DayObjectsSoundWorld.allCases.map { WorldArrangementFixture.plan($0, mood) }
            XCTAssertEqual(Set(plans.map { $0.lead.instrumentID }).count, 4)
            for plan in plans {
                XCTAssertTrue(WorldArrangementFixture.runtimeIDs(
                    WorldArrangementFixture.group(plan.soundWorld, mood).leadRecipeIDs, mood: mood
                ).contains(plan.lead.instrumentID))
                XCTAssertEqual(plan.lead.maximumSimultaneousVoices, 1)
            }
        }
    }

    func testGuestAdmissionUsesOnlyLeadAndPreservesEightyPercentNativePalette() throws {
        for seed in UInt64(0)..<1024 {
            let world = DayObjectsSoundWorld.allCases[Int(seed % 4)]
            let mood = DayObjectsSoundMood.allCases[Int(seed % 3)]
            let plan = WorldArrangementFixture.plan(world, mood, seed: seed, allowGuest: true)
            let selection = DayObjectsWorldSelector.makeSelection(remixSeed: seed, forcedWorld: world, forcedMood: mood)
            XCTAssertEqual(plan.guestWorld, selection.guestWorld)
            XCTAssertFalse(plan.bassIsGuest)
            XCTAssertFalse(plan.primaryHarmonyIsGuest)
            XCTAssertLessThanOrEqual(plan.guestInstrumentIDs.count, 1)
            if selection.guestWorld != nil && plan.activeLayerRoleCount >= 5 {
                XCTAssertEqual(plan.guestInstrumentIDs, [plan.lead.instrumentID])
            } else {
                XCTAssertTrue(plan.guestInstrumentIDs.isEmpty)
            }
            XCTAssertGreaterThanOrEqual(1 - Double(plan.guestInstrumentIDs.count) / Double(plan.activeLayerRoleCount), 0.8)
        }
    }

    func testMissingGuestFallsBackToNativeLeadAndLowHealthDoesNotAdmitGuest() throws {
        let seed = try XCTUnwrap((UInt64(0)..<512).first {
            DayObjectsWorldSelector.makeSelection(remixSeed: $0, forcedWorld: .electricDream, forcedMood: .moving).guestWorld != nil
        })
        let guest = WorldArrangementFixture.plan(.electricDream, .moving, seed: seed, allowGuest: true)
        let fallback = WorldArrangementFixture.plan(.electricDream, .moving, seed: seed, allowGuest: true,
            descriptors: WorldArrangementFixture.catalog.descriptors.filter { !guest.guestInstrumentIDs.contains($0.id) })
        XCTAssertEqual(guest.guestWorld, fallback.guestWorld)
        XCTAssertTrue(fallback.guestInstrumentIDs.isEmpty)
        XCTAssertTrue(WorldArrangementFixture.runtimeIDs(WorldArrangementFixture.group(.electricDream, .moving).leadRecipeIDs, mood: .moving).contains(fallback.lead.instrumentID))
        let low = WorldArrangementFixture.plan(.electricDream, .moving, seed: seed, steps: 0, sleep: 0, allowGuest: true)
        XCTAssertNotNil(low.guestWorld)
        XCTAssertTrue(low.guestInstrumentIDs.isEmpty)
    }
    func testPlanPublishesOneApprovedLeadAndTwentyOneTonalChordAwareRegions() throws {
        let world = try XCTUnwrap(
            TonalWorldPlanner.makePlan(
                centerPitchClass: 0,
                mode: .dorian,
                progressionLength: 4,
                cycleBars: 8
            )
        )
        let plan = try XCTUnwrap(makePlan(world: world))
        let approvedIDs = Set([
            "lead.verbacious",
            "lead.jec-softwah-2",
            "lead.bb-silver-screen"
        ])

        XCTAssertTrue(approvedIDs.contains(plan.instrumentID.rawValue))
        XCTAssertEqual(plan.maximumSimultaneousVoices, 1)
        XCTAssertEqual(plan.pitchRegions.count, 21)
        XCTAssertEqual(plan.pitchRegions.first?.normalizedRange.lowerBound, 0)
        XCTAssertEqual(plan.pitchRegions.last?.normalizedRange.upperBound, 1)

        for (index, region) in plan.pitchRegions.enumerated() {
            XCTAssertEqual(region.index, index)
            XCTAssertEqual(region.midiNotesByChord.count, world.progression.count)
            XCTAssertTrue(region.normalizedRange.lowerBound.isFinite)
            XCTAssertTrue(region.normalizedRange.upperBound.isFinite)
            XCTAssertLessThan(region.normalizedRange.lowerBound, region.normalizedRange.upperBound)
            if index > 0 {
                XCTAssertEqual(
                    region.normalizedRange.lowerBound,
                    plan.pitchRegions[index - 1].normalizedRange.upperBound,
                    accuracy: 1e-12
                )
            }

            for (chordIndex, note) in region.midiNotesByChord.enumerated() {
                XCTAssertTrue(plan.register.contains(note))
                XCTAssertTrue(world.scalePitchClasses.contains(Int(note) % 12))
                if region.preference == .chordTone {
                    XCTAssertTrue(world.progression[chordIndex].chordPitchClasses.contains(Int(note) % 12))
                }
            }
        }

        XCTAssertEqual(plan.pitchRegions.filter { $0.preference == .chordTone }.count, 7)
        XCTAssertEqual(plan.compatibleChordMIDINotes.count, world.progression.count)
    }

    func testNearestCompatibleNoteUsesCurrentChordAcrossEveryChange() throws {
        let world = try XCTUnwrap(
            TonalWorldPlanner.makePlan(
                centerPitchClass: 0,
                mode: .dorian,
                progressionLength: 4,
                cycleBars: 8
            )
        )
        let plan = try XCTUnwrap(makePlan(world: world))
        let expectedFromMIDI70: [UInt8] = [72, 70, 70, 69]

        for (chordIndex, expected) in expectedFromMIDI70.enumerated() {
            let note = try XCTUnwrap(plan.nearestCompatibleNote(to: 70, chordIndex: chordIndex))
            XCTAssertEqual(note, expected)
            XCTAssertTrue(plan.register.contains(note))
            XCTAssertTrue(world.progression[chordIndex].chordPitchClasses.contains(Int(note) % 12))
        }

        XCTAssertNil(plan.nearestCompatibleNote(to: 70, chordIndex: -1))
        XCTAssertNil(plan.nearestCompatibleNote(to: 70, chordIndex: world.progression.count))
    }

    func testRegionIndexClampsInputAndOwnsExactBoundariesOnTheRight() throws {
        let plan = try XCTUnwrap(makePlan())
        let lastIndex = plan.pitchRegions.count - 1

        XCTAssertEqual(plan.regionIndex(forNormalizedX: -.infinity), 0)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: -0.1), 0)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: 0), 0)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: .nan), 0)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: 1), lastIndex)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: 1.1), lastIndex)
        XCTAssertEqual(plan.regionIndex(forNormalizedX: .infinity), lastIndex)

        for index in 1..<plan.pitchRegions.count {
            let boundary = plan.pitchRegions[index].normalizedRange.lowerBound
            XCTAssertEqual(
                plan.regionIndex(forNormalizedX: boundary.nextDown),
                index - 1,
                "The value immediately below boundary \(index) must stay in the preceding region"
            )
            XCTAssertEqual(
                plan.regionIndex(forNormalizedX: boundary),
                index,
                "Exact boundary \(index) must belong to the region on its right"
            )
        }

        XCTAssertEqual(plan.regionIndex(forNormalizedX: Double(1).nextDown), lastIndex)
    }

    func testExpressionEnvelopeFilterAndGestureValuesAreFiniteAndPlaybackSafe() throws {
        let plan = try XCTUnwrap(makePlan())

        XCTAssertTrue((60...160).contains(plan.portamentoMilliseconds))
        XCTAssertTrue(plan.attackSeconds.isFinite && plan.attackSeconds > 0)
        XCTAssertTrue(plan.releaseSeconds.isFinite && plan.releaseSeconds > 0)
        XCTAssertTrue(plan.cutoffMultiplierRange.lowerBound.isFinite)
        XCTAssertTrue(plan.cutoffMultiplierRange.upperBound.isFinite)
        XCTAssertGreaterThan(plan.cutoffMultiplierRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(plan.cutoffMultiplierRange.upperBound, 2)
        XCTAssertGreaterThan(plan.cutoffMultiplierRange.upperBound, plan.cutoffMultiplierRange.lowerBound)
        XCTAssertTrue(plan.pitchSmoothingMilliseconds.isFinite && plan.pitchSmoothingMilliseconds > 0)
        XCTAssertTrue(plan.expressionSmoothingMilliseconds.isFinite && plan.expressionSmoothingMilliseconds > 0)
        XCTAssertTrue(plan.maximumExpressionDepth.isFinite && (0...0.25).contains(plan.maximumExpressionDepth))
        XCTAssertTrue(plan.delaySend.isFinite && (0...1).contains(plan.delaySend))
        XCTAssertTrue(plan.reverbSend.isFinite && (0...1).contains(plan.reverbSend))
    }

    func testSelectionIsStableForSeedAndDescriptorOrderAndRejectsMissingLeadCatalog() throws {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let forward = try XCTUnwrap(makePlan(descriptors: descriptors))
        let reversed = try XCTUnwrap(makePlan(descriptors: Array(descriptors.reversed())))

        XCTAssertEqual(forward, reversed)
        XCTAssertNil(makePlan(descriptors: descriptors.filter { $0.category != .lead }))
    }

    private func makePlan(
        world: TonalWorldPlan? = nil,
        descriptors: [DayObjectsInstrumentDescriptor] = DayObjectsInstrumentManifest.defaultDescriptors
    ) -> LeadPlan? {
        let resolvedWorld = world ?? TonalWorldPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: 0.61,
                sleepProgress: 0.74,
                happeningIDs: [],
                glitchProgress: 0.31,
                motionEnergy: 0.625,
                visualClarity: 0.625,
                diagnostics: []
            ),
            remixSeed: 0xD4A0_B1EC_75ED_0001
        )
        return LeadPlanner.makePlan(
            tonalWorld: resolvedWorld,
            instrumentDescriptors: descriptors,
            remixSeed: 0xD4A0_B1EC_75ED_0001
        )
    }
}
