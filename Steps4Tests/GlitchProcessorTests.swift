import XCTest
@testable import Steps4

@MainActor
final class GlitchProcessorTests: XCTestCase {
    func testZeroPlanBypassesEveryRoleAndLeavesDryPathUnchanged() {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)

        processor.apply(.neutral)

        XCTAssertEqual(backend.commands.map(\.role), GlitchRole.allCases)
        XCTAssertEqual(backend.commands.count, GlitchRole.allCases.count)
        for command in backend.commands {
            XCTAssertTrue(command.isBypassed)
            XCTAssertEqual(command.dryGain, 1, accuracy: 1e-12)
            XCTAssertEqual(command.pitchDriftCents, 0, accuracy: 1e-12)
            XCTAssertEqual(command.wowFlutterDepth, 0, accuracy: 1e-12)
            XCTAssertEqual(command.stereoSeparationAddition, 0, accuracy: 1e-12)
            XCTAssertEqual(command.delayTimeVariation, 0, accuracy: 1e-12)
            XCTAssertEqual(command.saturationAmount, 0, accuracy: 1e-12)
            XCTAssertEqual(command.timingDriftMilliseconds, 0, accuracy: 1e-12)
            XCTAssertEqual(command.dropoutAttenuationDecibels, 0, accuracy: 1e-12)
            XCTAssertEqual(command.dropoutReleaseSeconds, 0, accuracy: 1e-12)
            XCTAssertEqual(command.rampDurationSeconds, 0.25, accuracy: 1e-12)
        }
    }

    func testZeroProgressOverridesMalformedNonzeroRoleValues() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let malformedZero = GlitchPlan(
            progress: 0,
            roles: [
                .init(
                    role: .pad,
                    isTimingAnchor: false,
                    isGlitchEligible: true,
                    pitchDriftCents: 14,
                    dropoutProbability: 1,
                    delayTimeInstability: 0.08
                ),
            ],
            wowFlutterDepth: 0.18,
            stereoSeparationAddition: 0.22,
            realization: .init(
                dropoutSeed: 1,
                variationSeed: 2,
                cycleKey: 3,
                counterMapping: .roleCycleStepParameterV1
            )
        )

        processor.apply(malformedZero)
        _ = processor.applyRealizedEvent(
            plan: malformedZero,
            role: .pad,
            cycleIndex: 0,
            stepIndex: 0
        )

        let padCommands = backend.commands.filter { $0.role == .pad }
        XCTAssertEqual(padCommands.count, 2)
        XCTAssertTrue(padCommands.allSatisfy(\.isBypassed))
        XCTAssertTrue(padCommands.allSatisfy { $0.dryGain == 1 })
        XCTAssertTrue(padCommands.allSatisfy { command in
            command.pitchDriftCents == 0
                && command.wowFlutterDepth == 0
                && command.stereoSeparationAddition == 0
                && command.delayTimeVariation == 0
        })
    }

    func testOneFiveAndTenPercentSpentColorsPassExactDirectorValuesWithoutThreshold() throws {
        let fixtures: [(spentColors: Int, progress: Double)] = [
            (1, 0.0001),
            (5, 0.0025),
            (10, 0.01),
        ]

        for fixture in fixtures {
            let backend = RecordingGlitchBackend()
            let processor = GlitchProcessor(backend: backend)
            let plan = makePlan(spentColors: fixture.spentColors)

            processor.apply(plan)

            let pad = try command(.pad, in: backend)
            XCTAssertEqual(pad.pitchDriftCents, 14 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(pad.wowFlutterDepth, 0.18 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(pad.stereoSeparationAddition, 0.22 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(pad.delayTimeVariation, 0.08 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(pad.rampDurationSeconds, 0.25, accuracy: 1e-12)

            let happening = try command(.happening, in: backend)
            XCTAssertEqual(happening.pitchDriftCents, 10 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(happening.delayTimeVariation, 0.08 * fixture.progress, accuracy: 1e-12)

            let lead = try command(.lead, in: backend)
            XCTAssertEqual(lead.pitchDriftCents, 8 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(lead.saturationAmount, fixture.progress, accuracy: 1e-12)

            let percussion = try command(.percussion, in: backend)
            XCTAssertEqual(percussion.pitchDriftCents, 3 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(percussion.stereoSeparationAddition, 0.22 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(percussion.timingDriftMilliseconds, 0.32 * fixture.progress, accuracy: 1e-12)

            XCTAssertFalse(pad.isBypassed)
            XCTAssertFalse(happening.isBypassed)
            XCTAssertFalse(lead.isBypassed)
            XCTAssertFalse(percussion.isBypassed)
            XCTAssertTrue(try command(.timingAnchorKick, in: backend).isBypassed)
        }
    }

    func testRoleSpecificParametersDoNotLeakIntoOtherRoutes() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)

        processor.apply(makePlan(spentColors: 100))

        let pad = try command(.pad, in: backend)
        XCTAssertEqual(pad.saturationAmount, 0)
        XCTAssertEqual(pad.timingDriftMilliseconds, 0)
        XCTAssertEqual(pad.dropoutAttenuationDecibels, 0)

        let happening = try command(.happening, in: backend)
        XCTAssertEqual(happening.wowFlutterDepth, 0)
        XCTAssertEqual(happening.saturationAmount, 0)
        XCTAssertEqual(happening.timingDriftMilliseconds, 0)

        let lead = try command(.lead, in: backend)
        XCTAssertEqual(lead.wowFlutterDepth, 0)
        XCTAssertEqual(lead.delayTimeVariation, 0)
        XCTAssertEqual(lead.timingDriftMilliseconds, 0)
        XCTAssertEqual(lead.dropoutAttenuationDecibels, 0)

        let percussion = try command(.percussion, in: backend)
        XCTAssertEqual(percussion.wowFlutterDepth, 0)
        XCTAssertEqual(percussion.delayTimeVariation, 0)
        XCTAssertEqual(percussion.saturationAmount, 0)
        XCTAssertEqual(percussion.dropoutAttenuationDecibels, 0)
    }

    func testHappeningDropoutUsesThePlanRealizedEventAndSoftAttenuation() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let plan = planWithCertainHappeningDropout()
        let expected = try XCTUnwrap(plan.realizedEvent(for: .happening, cycleIndex: 2, stepIndex: 7))
        XCTAssertTrue(expected.shouldDropOut)

        let realized = processor.applyRealizedEvent(
            plan: plan,
            role: .happening,
            cycleIndex: 2,
            stepIndex: 7
        )

        XCTAssertEqual(realized, expected)
        let command = try XCTUnwrap(backend.commands.last)
        XCTAssertEqual(command.role, .happening)
        XCTAssertEqual(command.pitchDriftCents, expected.pitchDriftCents, accuracy: 1e-12)
        XCTAssertEqual(command.delayTimeVariation, expected.delayTimeVariation, accuracy: 1e-12)
        XCTAssertEqual(command.dropoutAttenuationDecibels, -6, accuracy: 1e-12)
        XCTAssertEqual(command.dropoutReleaseSeconds, 0.12, accuracy: 1e-12)
        XCTAssertGreaterThan(command.dryGain, 0)
        XCTAssertEqual(command.rampDurationSeconds, 0.25, accuracy: 1e-12)
    }

    func testMalformedTimingAnchorRejectsEveryForbiddenParameter() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let malformed = malformedTimingAnchorPlan()

        processor.apply(malformed)
        _ = processor.applyRealizedEvent(
            plan: malformed,
            role: .timingAnchorKick,
            cycleIndex: 0,
            stepIndex: 0
        )

        let commands = backend.commands.filter { $0.role == .timingAnchorKick }
        XCTAssertEqual(commands.count, 2)
        for command in commands {
            XCTAssertTrue(command.isBypassed)
            XCTAssertEqual(command.pitchDriftCents, 0)
            XCTAssertEqual(command.delayTimeVariation, 0)
            XCTAssertEqual(command.timingDriftMilliseconds, 0)
            XCTAssertEqual(command.dropoutAttenuationDecibels, 0)
            XCTAssertEqual(command.dropoutReleaseSeconds, 0)
            XCTAssertEqual(command.wowFlutterDepth, 0)
            XCTAssertEqual(command.stereoSeparationAddition, 0)
            XCTAssertEqual(command.saturationAmount, 0)
            XCTAssertEqual(command.dryGain, 1)
        }
    }

    func testNonFiniteContinuousValuesBecomeNeutralFiniteCommands() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let malformed = GlitchPlan(
            progress: .nan,
            roles: [
                .init(
                    role: .pad,
                    isTimingAnchor: false,
                    isGlitchEligible: true,
                    pitchDriftCents: .infinity,
                    dropoutProbability: .nan,
                    delayTimeInstability: -.infinity
                ),
            ],
            wowFlutterDepth: .nan,
            stereoSeparationAddition: .infinity,
            realization: .neutral
        )

        processor.apply(malformed)

        let pad = try command(.pad, in: backend)
        XCTAssertTrue(pad.isBypassed)
        XCTAssertTrue(pad.finiteValues.allSatisfy(\.isFinite))
        XCTAssertEqual(pad.dryGain, 1)
    }

    private func makePlan(spentColors: Int) -> GlitchPlan {
        let input = DayMusicInput(
            countedSteps: 0,
            stepGoal: 10_000,
            countedSleepHours: 0,
            sleepGoalHours: 8,
            happeningIDs: [],
            spentColors: spentColors
        ).normalized()
        return GlitchPlanner.makePlan(input: input, remixSeed: 0xA11CE)
    }

    private func planWithCertainHappeningDropout() -> GlitchPlan {
        GlitchPlan(
            progress: 1,
            roles: [
                .init(
                    role: .happening,
                    isTimingAnchor: false,
                    isGlitchEligible: true,
                    pitchDriftCents: 10,
                    dropoutProbability: 1,
                    delayTimeInstability: 0.08
                ),
            ],
            wowFlutterDepth: 0.18,
            stereoSeparationAddition: 0.22,
            realization: .init(
                dropoutSeed: 11,
                variationSeed: 22,
                cycleKey: 33,
                counterMapping: .roleCycleStepParameterV1
            )
        )
    }

    private func malformedTimingAnchorPlan() -> GlitchPlan {
        GlitchPlan(
            progress: 1,
            roles: [
                .init(
                    role: .timingAnchorKick,
                    isTimingAnchor: false,
                    isGlitchEligible: true,
                    pitchDriftCents: .infinity,
                    dropoutProbability: 1,
                    delayTimeInstability: .nan
                ),
            ],
            wowFlutterDepth: 1,
            stereoSeparationAddition: 1,
            realization: .init(
                dropoutSeed: 1,
                variationSeed: 2,
                cycleKey: 3,
                counterMapping: .roleCycleStepParameterV1
            )
        )
    }

    private func command(_ role: GlitchRole, in backend: RecordingGlitchBackend) throws -> DayObjectsGlitchCommand {
        try XCTUnwrap(backend.commands.last { $0.role == role })
    }
}

@MainActor
private final class RecordingGlitchBackend: DayObjectsGlitchBackend {
    var commands: [DayObjectsGlitchCommand] = []

    func apply(_ command: DayObjectsGlitchCommand) {
        commands.append(command)
    }
}

private extension DayObjectsGlitchCommand {
    var finiteValues: [Double] {
        [
            dryGain,
            pitchDriftCents,
            wowFlutterDepth,
            stereoSeparationAddition,
            delayTimeVariation,
            saturationAmount,
            timingDriftMilliseconds,
            dropoutAttenuationDecibels,
            dropoutReleaseSeconds,
            rampDurationSeconds,
        ]
    }
}
