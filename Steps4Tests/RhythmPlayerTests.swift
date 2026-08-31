#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class RhythmPlayerTests: XCTestCase {
    func testSubdivisionRendersDirectorEventsWithPlannedDetailsAndThreeAttackCap() {
        let drums = RecordingRhythmDrumBank(allocatedPlayerCount: 31)
        let player = RhythmPlayer(drumBank: drums)
        let plan = rhythmPlan(voiceCount: 4, timingAnchorIndex: 1)

        let frame = player.render(
            transportEvent(at: 0, hostTime: 12),
            rhythmPlan: plan,
            glitchPlan: .neutral
        )

        XCTAssertEqual(frame.hits.count, 3)
        XCTAssertEqual(drums.scheduledHits.count, 3)
        XCTAssertEqual(frame.hits.map(\.drumVoice), drums.scheduledHits.map(\.voice))
        XCTAssertTrue(frame.hits.allSatisfy { (0.4...0.8).contains($0.velocity) })
        XCTAssertEqual(Set(frame.hits.map(\.roomSend)), Set([0.1, 0.2, 0.3]))
        XCTAssertTrue(frame.hits.allSatisfy { abs($0.microtimingMilliseconds) <= 12 })
        XCTAssertTrue(frame.hits.allSatisfy {
            abs($0.scheduledHostTimeSeconds - (12 + $0.microtimingMilliseconds / 1_000)) < 0.000_000_001
        })
        XCTAssertEqual(player.metrics.allocatedDrumPlayerCount, 31)
        XCTAssertEqual(player.metrics.renderedLogicalHitCount, 3)
    }

    func testMaximumGlitchCannotMoveDropDelayOrDuplicateTimingAnchorKick() throws {
        let drums = RecordingRhythmDrumBank(allocatedPlayerCount: 31)
        let player = RhythmPlayer(drumBank: drums)
        let plan = rhythmPlan(voiceCount: 1, timingAnchorIndex: 0)
        let glitch = GlitchPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: 1,
                sleepProgress: 1,
                happeningIDs: [],
                glitchProgress: 1,
                motionEnergy: 1,
                visualClarity: 0.9,
                diagnostics: []
            ),
            remixSeed: 0xF00D
        )

        let frame = player.render(
            transportEvent(at: 0, hostTime: 20),
            rhythmPlan: plan,
            glitchPlan: glitch
        )
        let kick = try XCTUnwrap(frame.hits.first)

        XCTAssertEqual(drums.scheduledHits.count, 1, "The sample transient and sine body are one semantic bank hit")
        XCTAssertTrue(kick.isTimingAnchor)
        XCTAssertFalse(kick.shouldDropOut)
        XCTAssertEqual(kick.pitchDriftCents, 0)
        XCTAssertEqual(kick.delayTimeVariation, 0)
        XCTAssertEqual(kick.stereoOffset, 0)
        XCTAssertEqual(kick.microtimingMilliseconds, 0)
        XCTAssertEqual(kick.scheduledHostTimeSeconds, 20)
        XCTAssertEqual(drums.scheduledHits.first, .init(
            voice: .organicLow,
            velocity: kick.velocity,
            scheduledHostTimeSeconds: 20,
            microtimingMilliseconds: 0,
            roomSend: 0.1,
            stereoOffset: 0,
            pitchDriftCents: 0
        ))
    }

    func testNonAnchorGlitchUsesOnlyBoundedPlanDerivedTexture() throws {
        let drums = RecordingRhythmDrumBank(allocatedPlayerCount: 31)
        let player = RhythmPlayer(drumBank: drums)
        let plan = rhythmPlan(voiceCount: 1, timingAnchorIndex: nil)
        let glitch = GlitchPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: 1,
                sleepProgress: 1,
                happeningIDs: [],
                glitchProgress: 1,
                motionEnergy: 1,
                visualClarity: 0.9,
                diagnostics: []
            ),
            remixSeed: 0xBEEF
        )

        let hit = try XCTUnwrap(player.render(
            transportEvent(at: 0),
            rhythmPlan: plan,
            glitchPlan: glitch
        ).hits.first)

        XCTAssertLessThanOrEqual(abs(hit.pitchDriftCents), 3)
        XCTAssertLessThanOrEqual(abs(hit.stereoOffset), glitch.stereoSeparationAddition)
        XCTAssertLessThanOrEqual(abs(hit.microtimingMilliseconds), plan.maximumMicrotimingMilliseconds)
        XCTAssertFalse(hit.shouldDropOut, "Percussion texture must not punch holes in the rhythm")
        XCTAssertEqual(hit.delayTimeVariation, 0, "Percussion never inherits unstable delay")
        XCTAssertEqual(drums.scheduledHits.first?.velocity, hit.velocity)
        XCTAssertEqual(drums.scheduledHits.first?.scheduledHostTimeSeconds, hit.scheduledHostTimeSeconds)
        XCTAssertEqual(drums.scheduledHits.first?.microtimingMilliseconds, hit.microtimingMilliseconds)
        XCTAssertEqual(drums.scheduledHits.first?.roomSend, hit.roomSend)
        XCTAssertEqual(drums.scheduledHits.first?.stereoOffset, hit.stereoOffset)
        XCTAssertEqual(drums.scheduledHits.first?.pitchDriftCents, hit.pitchDriftCents)
    }

    func testDuckingIsSilentAtLowStepsAndNeverExceedsTwoPointFiveDecibels() {
        let drums = RecordingRhythmDrumBank(allocatedPlayerCount: 31)
        let player = RhythmPlayer(drumBank: drums)
        let low = rhythmPlan(voiceCount: 1, timingAnchorIndex: 0, stepsProgress: 0.5)
        let high = rhythmPlan(voiceCount: 1, timingAnchorIndex: 0, stepsProgress: 1)

        XCTAssertEqual(player.render(transportEvent(at: 0), rhythmPlan: low, glitchPlan: .neutral).harmonyDuckingDecibels, 0)
        XCTAssertEqual(player.render(transportEvent(at: 0), rhythmPlan: high, glitchPlan: .neutral).harmonyDuckingDecibels, 2.5)
    }

    func testTenThousandSubdivisionsKeepAllocationConstantAndReleaseEverything() {
        let drums = RecordingRhythmDrumBank(allocatedPlayerCount: 31)
        let player = RhythmPlayer(drumBank: drums)
        let plan = rhythmPlan(voiceCount: 4, timingAnchorIndex: 1)
        let baseline = player.metrics.allocatedDrumPlayerCount

        for subdivision in 0..<10_000 {
            _ = player.render(
                transportEvent(at: Int64(subdivision)),
                rhythmPlan: plan,
                glitchPlan: .neutral
            )
        }
        player.releaseAll()

        XCTAssertEqual(player.metrics.allocatedDrumPlayerCount, baseline)
        XCTAssertEqual(player.metrics.activeLogicalHitCount, 0)
        XCTAssertEqual(drums.releaseAllCount, 1)
    }

    private func rhythmPlan(
        voiceCount: Int,
        timingAnchorIndex: Int?,
        stepsProgress: Double = 1
    ) -> RhythmPlan {
        let roles = Array(RhythmRole.allCases.prefix(voiceCount))
        let drumVoices: [DayObjectsDrumVoice] = [.organicLow, .kickFull, .hatClosed, .shaker]
        return RhythmPlan(
            baseTempoBPM: 60,
            tempoBPM: 80,
            stepsProgress: stepsProgress,
            family: .grounded,
            patternOffsetSteps: 0,
            humanizationProfile: .loose,
            realization: .init(
                patternSeed: 1,
                humanizationSeed: 2,
                cycleKey: 3,
                counterMapping: .roleCycleStepParameterV1
            ),
            voices: roles.enumerated().map { index, role in
                RhythmVoicePlan(
                    role: role,
                    drumVoice: drumVoices[index],
                    stepProbabilities: [1] + Array(repeating: 0, count: 15),
                    velocityRange: (0.4 + Double(index) * 0.1)...(0.5 + Double(index) * 0.1),
                    microtimingMilliseconds: -12...12,
                    roomSend: Double(index + 1) / 10,
                    activation: .init(startProgress: 0, fullProgress: 1, amount: 1),
                    isTimingAnchor: timingAnchorIndex == index,
                    isGlitchEligible: timingAnchorIndex != index
                )
            },
            maximumSimultaneousAttacks: 3,
            maximumFillsPerWindow: 1,
            fillWindowBars: 8,
            maximumMicrotimingMilliseconds: 18,
            velocityHumanizationRange: -0.08...0.08,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }

    private func transportEvent(
        at absoluteSubdivision: Int64,
        hostTime: TimeInterval = 0
    ) -> DayObjectsTransportEvent {
        .init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: absoluteSubdivision),
            hostTimeSeconds: hostTime,
            tempoBPM: 80
        )
    }
}

private final class RecordingRhythmDrumBank: DayObjectsDrumBankProtocol {
    let metrics: DayObjectsDrumBankMetrics
    private(set) var scheduledHits: [DayObjectsScheduledDrumHit] = []
    private(set) var releaseAllCount = 0

    init(allocatedPlayerCount: Int) {
        metrics = .init(allocatedPlayerCount: allocatedPlayerCount, enabledVoiceCount: DayObjectsDrumVoice.allCases.count)
    }

    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {
        XCTFail("Rhythm playback must use the typed scheduled-hit path")
    }

    func schedule(_ hit: DayObjectsScheduledDrumHit) {
        scheduledHits.append(hit)
    }

    func releaseAll() {
        releaseAllCount += 1
    }
}
#endif
