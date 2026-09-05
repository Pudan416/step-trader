import XCTest
@testable import Steps4

final class HarmonyPlannerTests: XCTestCase {
    func testActivePianoAccentPublishesTheFeltPianoPlaybackTargetWithTheRealCatalog() throws {
        let plan = makePlan(
            sleepProgress: 1,
            descriptors: DayObjectsInstrumentManifest.defaultDescriptors
        )
        let accents = try XCTUnwrap(plan.role(for: .pianoOrKeysAccents))

        XCTAssertGreaterThan(accents.gain, 0)
        XCTAssertEqual(accents.instrumentTarget, .feltPiano)
    }

    func testEveryRolePublishesTheApprovedActivationWindowAndZeroSleepKeepsAnAudibleOpenFifth() throws {
        let plan = makePlan(sleepProgress: 0)
        let expected: [(HarmonyRole, Double, Double)] = [
            (.drone, 0.00, 0.20),
            (.primaryPad, 0.20, 0.55),
            (.secondaryPadOrKeys, 0.58, 0.88),
            (.pianoOrKeysAccents, 0.72, 1.00),
            (.innerMotion, 0.82, 1.00)
        ]

        XCTAssertEqual(plan.roles.map(\.role), expected.map(\.0))
        for (role, start, full) in expected {
            let rolePlan = try XCTUnwrap(plan.role(for: role))
            XCTAssertEqual(rolePlan.activation.startProgress, start)
            XCTAssertEqual(rolePlan.activation.fullProgress, full)
        }

        let drone = try XCTUnwrap(plan.role(for: .drone))
        XCTAssertGreaterThan(drone.gain, 0)
        let foundation = try XCTUnwrap(drone.chordSchedule.first)
        XCTAssertEqual(foundation.voicedMIDINotes.count, 2)
        XCTAssertEqual(
            Set(foundation.voicedMIDINotes.map { Int($0) % 12 }),
            Set([foundation.rootPitchClass, (foundation.rootPitchClass + 7) % 12])
        )
    }

    func testSleepMatrixNeverReducesChordCountActiveRolesOrHarmonicInformation() {
        let sleepValues = [0.0, 0.35, 0.70, 0.99, 1.0]
        var previousChordCount = -1
        var previousActiveRoleCount = -1
        var previousInformation = -Double.infinity

        for sleep in sleepValues {
            let plan = makePlan(sleepProgress: sleep)
            XCTAssertGreaterThanOrEqual(plan.chordCount, previousChordCount, "Chord count at \(sleep)")
            XCTAssertGreaterThanOrEqual(plan.activeRoleCount, previousActiveRoleCount, "Active roles at \(sleep)")
            XCTAssertGreaterThanOrEqual(
                plan.harmonicInformationScore,
                previousInformation,
                "Harmonic information at \(sleep)"
            )
            previousChordCount = plan.chordCount
            previousActiveRoleCount = plan.activeRoleCount
            previousInformation = plan.harmonicInformationScore
        }
    }

    func testInstrumentSelectionUsesOnlyCompatibleDescriptorsAndAvoidsPrimarySecondaryDuplication() throws {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let plan = makePlan(sleepProgress: 1, descriptors: descriptors)
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let compatibleCategories: [HarmonyRole: Set<DayObjectsInstrumentCategory>] = [
            .drone: [.pad, .keys],
            .primaryPad: [.pad],
            .secondaryPadOrKeys: [.pad, .keys],
            .innerMotion: [.keys],
        ]

        for rolePlan in plan.roles {
            switch rolePlan.instrumentTarget {
            case let .tonal(instrumentID):
                let descriptor = try XCTUnwrap(descriptorByID[instrumentID])
                XCTAssertTrue(try XCTUnwrap(compatibleCategories[rolePlan.role]).contains(descriptor.category))
            case .feltPiano:
                XCTAssertEqual(rolePlan.role, .pianoOrKeysAccents)
            }
        }

        let primary = try XCTUnwrap(plan.role(for: .primaryPad))
        let secondary = try XCTUnwrap(plan.role(for: .secondaryPadOrKeys))
        XCTAssertNotEqual(primary.instrumentTarget, secondary.instrumentTarget)
    }

    func testSelectionAndCompletePlanAreStableForSeedAndDescriptorOrder() {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let forward = makePlan(sleepProgress: 0.86, descriptors: descriptors, remixSeed: 0xABCD)
        let reversed = makePlan(
            sleepProgress: 0.86,
            descriptors: Array(descriptors.reversed()),
            remixSeed: 0xABCD
        )

        XCTAssertEqual(forward, reversed)
    }

    func testRolePlansAreDeclarativeFiniteAndSchedulesCoverTheirDeclaredCycle() {
        let plan = makePlan(sleepProgress: 1)

        XCTAssertTrue([8, 12, 16].contains(plan.cycleBars))
        XCTAssertEqual(plan.roles.count, HarmonyRole.allCases.count)
        for role in plan.roles {
            XCTAssertLessThanOrEqual(role.register.lowerBound, role.register.upperBound)
            XCTAssertTrue(role.gain.isFinite && (0...1).contains(role.gain))
            XCTAssertTrue(role.attackSeconds.isFinite && role.attackSeconds > 0)
            XCTAssertTrue(role.releaseSeconds.isFinite && role.releaseSeconds > 0)
            XCTAssertTrue(role.delaySend.isFinite && (0...1).contains(role.delaySend))
            XCTAssertTrue(role.reverbSend.isFinite && (0...1).contains(role.reverbSend))
            XCTAssertTrue(role.crossfadeBars.isFinite && role.crossfadeBars > 0)
            XCTAssertFalse(role.chordSchedule.isEmpty)
            XCTAssertTrue(role.chordSchedule.allSatisfy {
                $0.startBar >= 0 && $0.durationBars > 0 &&
                $0.startBar + $0.durationBars <= plan.cycleBars &&
                !$0.voicedMIDINotes.isEmpty &&
                $0.voicedMIDINotes.allSatisfy(role.register.contains)
            })
        }
    }

    func testAccentsRespectApprovedOnsetAndStayBehindPadsAtFullSleep() throws {
        let atStart = try XCTUnwrap(makePlan(sleepProgress: 0.72).role(for: .pianoOrKeysAccents))
        let aboveStart = try XCTUnwrap(makePlan(sleepProgress: 0.720_001).role(for: .pianoOrKeysAccents))
        let full = makePlan(sleepProgress: 1)
        let accents = try XCTUnwrap(full.role(for: .pianoOrKeysAccents))
        let primary = try XCTUnwrap(full.role(for: .primaryPad))
        let secondary = try XCTUnwrap(full.role(for: .secondaryPadOrKeys))

        XCTAssertEqual(atStart.gain, 0)
        XCTAssertGreaterThan(aboveStart.gain, 0)
        XCTAssertLessThan(accents.gain, primary.gain)
        XCTAssertLessThan(accents.gain, secondary.gain)
        XCTAssertLessThan(accents.chordSchedule.count, full.chordCount)
    }

    func testSleepChangesHarmonyWithoutChangingFixedStepsRhythmPlan() {
        let sleepValues = [0.0, 0.35, 0.70, 0.99, 1.0]
        let plans = sleepValues.map { sleep -> (RhythmPlan, HarmonyPlan) in
            let input = input(stepsProgress: 0.61, sleepProgress: sleep)
            let world = TonalWorldPlanner.makePlan(input: input, remixSeed: remixSeed)
            return (
                RhythmPlanner.makePlan(input: input, remixSeed: remixSeed),
                HarmonyPlanner.makePlan(
                    input: input,
                    tonalWorld: world,
                    instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors,
                    remixSeed: remixSeed
                )
            )
        }

        XCTAssertTrue(plans.dropFirst().allSatisfy { $0.0 == plans[0].0 })
        XCTAssertGreaterThan(Set(plans.map { $0.1.chordCount }).count, 1)
        XCTAssertGreaterThan(Set(plans.map { $0.1.activeRoleCount }).count, 1)
    }

    func testPlannerDefensivelyNormalizesSleepAndHandlesMissingCompatibleDescriptors() {
        let below = makePlan(sleepProgress: -1)
        let zero = makePlan(sleepProgress: 0)
        let above = makePlan(sleepProgress: 2)
        let one = makePlan(sleepProgress: 1)
        let nonFinite = makePlan(sleepProgress: .infinity)
        let empty = makePlan(sleepProgress: 1, descriptors: [])

        XCTAssertEqual(below, zero)
        XCTAssertEqual(above, one)
        XCTAssertEqual(nonFinite.sleepProgress, 0)
        XCTAssertEqual(nonFinite.roles.map(\.gain), zero.roles.map(\.gain))
        XCTAssertEqual(empty.roles.map(\.role), [.pianoOrKeysAccents])
        XCTAssertEqual(empty.roles.map(\.instrumentTarget), [.feltPiano])
        XCTAssertEqual(empty.activeRoleCount, 1)
        XCTAssertTrue(empty.harmonicInformationScore.isFinite)
    }

    private let remixSeed: UInt64 = 0xD4A0_B1EC_75ED_0001

    private func makePlan(
        sleepProgress: Double,
        descriptors: [DayObjectsInstrumentDescriptor] = DayObjectsInstrumentManifest.defaultDescriptors,
        remixSeed: UInt64? = nil
    ) -> HarmonyPlan {
        let input = input(stepsProgress: 0.61, sleepProgress: sleepProgress)
        let seed = remixSeed ?? self.remixSeed
        return HarmonyPlanner.makePlan(
            input: input,
            tonalWorld: TonalWorldPlanner.makePlan(input: input, remixSeed: seed),
            instrumentDescriptors: Array(descriptors),
            remixSeed: seed
        )
    }

    private func input(stepsProgress: Double, sleepProgress: Double) -> NormalizedDayMusicInput {
        NormalizedDayMusicInput(
            stepsProgress: stepsProgress,
            sleepProgress: sleepProgress,
            happeningIDs: [],
            glitchProgress: 0.31,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            diagnostics: []
        )
    }
}
