import XCTest
@testable import Steps4

@MainActor
final class GlitchProcessorTests: XCTestCase {
    func testRealizedEventPreviewIsPureUntilExplicitCommit() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let plan = planWithCertainHappeningDropout()
        let occurrence = try firstHappeningDropout(in: plan)

        let preview = processor.previewRealizedEvent(
            plan: plan,
            role: .happening,
            cycleIndex: occurrence.cycleIndex,
            stepIndex: occurrence.stepIndex
        )

        XCTAssertTrue(backend.commands.isEmpty)
        processor.commitRealizedEvent(preview)
        XCTAssertEqual(backend.commands, [preview])
    }

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
            XCTAssertEqual(command.outputCompensationGain, 1, accuracy: 1e-12)
            XCTAssertEqual(command.timingDriftMilliseconds, 0, accuracy: 1e-12)
            XCTAssertEqual(command.dropoutAttenuationDecibels, 0, accuracy: 1e-12)
            XCTAssertEqual(command.dropoutReleaseSeconds, 0, accuracy: 1e-12)
            XCTAssertEqual(command.rampDurationSeconds, 0.25, accuracy: 1e-12)
        }
    }

    func testLeadSaturationPublishesMonotonicOutputCompensation() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        processor.apply(makePlan(spentColors: 100))

        let lead = try command(.lead, in: backend)
        XCTAssertEqual(lead.outputCompensationGain, pow(10, (-4 * 0.18) / 20), accuracy: 1e-12)
        XCTAssertLessThan(lead.outputCompensationGain, 1)
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
            XCTAssertEqual(happening.delayTimeVariation, 0.04 * fixture.progress, accuracy: 1e-12)

            let lead = try command(.lead, in: backend)
            XCTAssertEqual(lead.pitchDriftCents, 8 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(lead.saturationAmount, 0.18 * fixture.progress, accuracy: 1e-12)

            let percussion = try command(.percussion, in: backend)
            XCTAssertTrue(percussion.isBypassed)
            XCTAssertEqual(percussion.pitchDriftCents, 0)
            XCTAssertEqual(percussion.stereoSeparationAddition, 0)
            XCTAssertEqual(percussion.timingDriftMilliseconds, 0)

            XCTAssertFalse(pad.isBypassed)
            XCTAssertFalse(happening.isBypassed)
            XCTAssertFalse(lead.isBypassed)
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
        let occurrence = try firstHappeningDropout(in: plan)
        let expected = occurrence.event
        XCTAssertTrue(expected.shouldDropOut)

        let realized = processor.applyRealizedEvent(
            plan: plan,
            role: .happening,
            cycleIndex: occurrence.cycleIndex,
            stepIndex: occurrence.stepIndex
        )

        let applied = try XCTUnwrap(realized)
        let command = try XCTUnwrap(backend.commands.last)
        XCTAssertEqual(applied, command)
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
        let applied = processor.applyRealizedEvent(
            plan: malformed,
            role: .timingAnchorKick,
            cycleIndex: 0,
            stepIndex: 0
        )
        XCTAssertNil(applied)

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

    func testEventPathFailsClosedForMissingDuplicateZeroInvalidCoordinateAndContradictoryFlags() throws {
        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let valid = makePlan(spentColors: 100)
        processor.apply(valid)
        XCTAssertFalse(try command(.pad, in: backend).isBypassed)

        let pad = try XCTUnwrap(valid.role(for: .pad))
        let fixtures: [(GlitchPlan, GlitchRole, Int, Int, Bool)] = [
            (plan(replacingRoles: [], from: valid), .pad, 0, 0, true),
            (plan(replacingRoles: [pad, pad], from: valid), .pad, 0, 0, true),
            (plan(replacingProgress: 0, from: valid), .pad, 0, 0, true),
            (valid, .pad, -1, 0, false),
            (valid, .pad, 0, 16, false),
            (plan(replacingRoles: [rolePlan(.pad, isTimingAnchor: true, isGlitchEligible: true)], from: valid), .pad, 0, 0, true),
            (plan(replacingRoles: [rolePlan(.pad, isTimingAnchor: false, isGlitchEligible: false)], from: valid), .pad, 0, 0, true),
            (plan(replacingRoles: [rolePlan(.timingAnchorKick, isTimingAnchor: false, isGlitchEligible: true)], from: valid), .timingAnchorKick, 0, 0, true),
        ]

        for (fixture, role, cycle, step, continuousShouldBeNeutral) in fixtures {
            processor.apply(fixture)
            let continuousNeutral = try command(role, in: backend)
            XCTAssertEqual(continuousNeutral.isBypassed, continuousShouldBeNeutral)
            if continuousShouldBeNeutral {
                XCTAssertEqual(continuousNeutral.dryGain, 1)
            }

            let applied = processor.applyRealizedEvent(
                plan: fixture,
                role: role,
                cycleIndex: cycle,
                stepIndex: step
            )
            XCTAssertNil(applied)
            let neutral = try XCTUnwrap(backend.commands.last)
            XCTAssertEqual(neutral.role, role)
            XCTAssertTrue(neutral.isBypassed)
            XCTAssertEqual(neutral.dryGain, 1)
            XCTAssertTrue(neutral.finiteValues.allSatisfy(\.isFinite))
        }
    }

    func testExtremeFiniteRoleValuesClampToDirectorOwnedBoundsForEveryRole() throws {
        for role in GlitchRole.allCases {
            for raw in [-1_000.0, 1_000.0] {
                let backend = RecordingGlitchBackend()
                let processor = GlitchProcessor(backend: backend)
                let rawRole = GlitchRolePlan(
                    role: role,
                    isTimingAnchor: role == .timingAnchorKick,
                    isGlitchEligible: role != .timingAnchorKick,
                    pitchDriftCents: raw,
                    dropoutProbability: raw,
                    delayTimeInstability: raw,
                    saturationAmount: raw,
                    timingDriftMilliseconds: raw
                )
                let fixture = GlitchPlan(
                    progress: 1,
                    roles: [rawRole],
                    wowFlutterDepth: raw,
                    stereoSeparationAddition: raw,
                    realization: .init(
                        dropoutSeed: 1,
                        variationSeed: 2,
                        cycleKey: 3,
                        counterMapping: .roleCycleStepParameterV1
                    )
                )

                processor.apply(fixture)
                let continuous = try command(role, in: backend)
                let limits = role.safeLimits
                XCTAssertLessThanOrEqual(abs(continuous.pitchDriftCents), limits.pitchDriftCents)
                XCTAssertLessThanOrEqual(abs(continuous.delayTimeVariation), limits.delayTimeInstability)
                XCTAssertLessThanOrEqual(continuous.saturationAmount, limits.saturationAmount)
                XCTAssertTrue(continuous.outputCompensationGain.isFinite)
                XCTAssertGreaterThan(continuous.outputCompensationGain, 0)
                XCTAssertLessThanOrEqual(continuous.outputCompensationGain, 1)
                XCTAssertLessThanOrEqual(abs(continuous.timingDriftMilliseconds), limits.timingDriftMilliseconds)
                XCTAssertLessThanOrEqual(continuous.wowFlutterDepth, GlitchPlan.maximumWowFlutterDepth)
                XCTAssertLessThanOrEqual(continuous.stereoSeparationAddition, GlitchPlan.maximumStereoSeparationAddition)

                let eventCommand = processor.applyRealizedEvent(
                    plan: fixture,
                    role: role,
                    cycleIndex: 0,
                    stepIndex: 0
                )
                if role == .percussion || role == .timingAnchorKick {
                    XCTAssertNil(eventCommand)
                    XCTAssertTrue(try XCTUnwrap(backend.commands.last).isBypassed)
                } else {
                    let eventCommand = try XCTUnwrap(eventCommand)
                    XCTAssertLessThanOrEqual(abs(eventCommand.pitchDriftCents), limits.pitchDriftCents)
                    XCTAssertLessThanOrEqual(abs(eventCommand.delayTimeVariation), limits.delayTimeInstability)
                    XCTAssertTrue(eventCommand.outputCompensationGain.isFinite)
                    XCTAssertGreaterThan(eventCommand.outputCompensationGain, 0)
                    XCTAssertLessThanOrEqual(eventCommand.outputCompensationGain, 1)
                }
            }
        }
    }

    func testDryGainParticipatesInBypassAndNextEventRestoresUnity() throws {
        let attenuatedOnly = DayObjectsGlitchCommand(
            role: .happening,
            dryGain: 0.5,
            pitchDriftCents: 0,
            wowFlutterDepth: 0,
            stereoSeparationAddition: 0,
            delayTimeVariation: 0,
            saturationAmount: 0,
            timingDriftMilliseconds: 0,
            dropoutAttenuationDecibels: 0,
            dropoutReleaseSeconds: 0,
            rampDurationSeconds: 0.25
        )
        XCTAssertFalse(attenuatedOnly.isBypassed)

        let backend = RecordingGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        let dropoutPlan = planWithCertainHappeningDropout()
        let occurrence = try firstHappeningDropout(in: dropoutPlan)
        _ = processor.applyRealizedEvent(
            plan: dropoutPlan,
            role: .happening,
            cycleIndex: occurrence.cycleIndex,
            stepIndex: occurrence.stepIndex
        )
        XCTAssertLessThan(try XCTUnwrap(backend.commands.last).dryGain, 1)

        let restoration = planWithNoHappeningDropout()
        _ = processor.applyRealizedEvent(
            plan: restoration,
            role: .happening,
            cycleIndex: occurrence.cycleIndex,
            stepIndex: occurrence.stepIndex
        )
        XCTAssertEqual(try XCTUnwrap(backend.commands.last).dryGain, 1)
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
                    dropoutProbability: 0.06,
                    delayTimeInstability: 0.04,
                    saturationAmount: 0,
                    timingDriftMilliseconds: 0
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

    private func planWithNoHappeningDropout() -> GlitchPlan {
        GlitchPlan(
            progress: 1,
            roles: [
                .init(
                    role: .happening,
                    isTimingAnchor: false,
                    isGlitchEligible: true,
                    pitchDriftCents: 0,
                    dropoutProbability: 0,
                    delayTimeInstability: 0,
                    saturationAmount: 0,
                    timingDriftMilliseconds: 0
                ),
            ],
            wowFlutterDepth: 0,
            stereoSeparationAddition: 0,
            realization: .init(
                dropoutSeed: 11,
                variationSeed: 22,
                cycleKey: 33,
                counterMapping: .roleCycleStepParameterV1
            )
        )
    }

    private func firstHappeningDropout(
        in plan: GlitchPlan
    ) throws -> (cycleIndex: Int, stepIndex: Int, event: GlitchRealizedEvent) {
        for cycleIndex in 0..<256 {
            for stepIndex in 0..<16 {
                if let event = plan.realizedEvent(
                    for: .happening,
                    cycleIndex: cycleIndex,
                    stepIndex: stepIndex
                ), event.shouldDropOut {
                    return (cycleIndex, stepIndex, event)
                }
            }
        }
        throw NSError(
            domain: "GlitchProcessorTests.MissingDeterministicDropout",
            code: 1
        )
    }

    private func plan(replacingRoles roles: [GlitchRolePlan], from plan: GlitchPlan) -> GlitchPlan {
        GlitchPlan(
            progress: plan.progress,
            roles: roles,
            wowFlutterDepth: plan.wowFlutterDepth,
            stereoSeparationAddition: plan.stereoSeparationAddition,
            realization: plan.realization
        )
    }

    private func plan(replacingProgress progress: Double, from plan: GlitchPlan) -> GlitchPlan {
        GlitchPlan(
            progress: progress,
            roles: plan.roles,
            wowFlutterDepth: plan.wowFlutterDepth,
            stereoSeparationAddition: plan.stereoSeparationAddition,
            realization: plan.realization
        )
    }

    private func rolePlan(
        _ role: GlitchRole,
        isTimingAnchor: Bool,
        isGlitchEligible: Bool
    ) -> GlitchRolePlan {
        .init(
            role: role,
            isTimingAnchor: isTimingAnchor,
            isGlitchEligible: isGlitchEligible,
            pitchDriftCents: 1,
            dropoutProbability: 0,
            delayTimeInstability: 0,
            saturationAmount: 0,
            timingDriftMilliseconds: 0
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
                    delayTimeInstability: .nan,
                    saturationAmount: .infinity,
                    timingDriftMilliseconds: .infinity
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
            outputCompensationGain,
            timingDriftMilliseconds,
            dropoutAttenuationDecibels,
            dropoutReleaseSeconds,
            rampDurationSeconds,
        ]
    }
}
