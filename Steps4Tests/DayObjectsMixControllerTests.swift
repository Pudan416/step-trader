import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMixControllerTests: XCTestCase {
    func testAppliesExactLayerTargetsRampsChordAttenuationAndDucking() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let plan = LayerMixPlanner.makePlan(happeningCount: 5)

        controller.apply(
            plan,
            activeChordVoiceCount: 4,
            harmonyDuckingDecibels: 1.25,
            spatial: testSpatial,
            rampDurationSeconds: 0.5
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertEqual(state.rhythmTargetDecibels, 0, accuracy: 1e-12)
        XCTAssertEqual(state.bassTargetDecibels, 0, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyTargetDecibels, -1.25, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyPerVoiceTargetDecibels, -1.25, accuracy: 1e-12)
        XCTAssertEqual(state.happeningAggregateTargetDecibels, -3.3, accuracy: 1e-12)
        XCTAssertEqual(state.happeningPerVoiceTargetDecibels, -9.3, accuracy: 1e-12)
        XCTAssertEqual(state.leadTargetDecibels, -3.1, accuracy: 1e-12)
        XCTAssertEqual(state.masterTargetDecibelsBeforeLimiter, -6, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyDuckingDecibels, 1.25, accuracy: 1e-12)
        XCTAssertEqual(state.buses.rhythm.sendLevel, 0.1, accuracy: 1e-12)
        XCTAssertEqual(state.buses.bass.sendLevel, 0.2, accuracy: 1e-12)
        XCTAssertEqual(state.buses.harmony.sendLevel, 0.3, accuracy: 1e-12)
        XCTAssertEqual(state.buses.happenings.sendLevel, 0.4, accuracy: 1e-12)
        XCTAssertEqual(state.buses.lead.sendLevel, 0.5, accuracy: 1e-12)
        XCTAssertEqual(state.buses.happenings.decay, 0.8, accuracy: 1e-12)
        XCTAssertEqual(state.rampDurationSeconds, 0.5, accuracy: 1e-12)
    }

    func testSparseHappeningsAndInternallyCompensatedHarmonyAreNotAttenuatedTwice() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)

        for count in [1, 2, 5, 10] {
            controller.apply(
                LayerMixPlanner.makePlan(happeningCount: count),
                activeChordVoiceCount: count,
                harmonyDuckingDecibels: 0,
                spatial: .dry,
                rampDurationSeconds: 0.25
            )
        }

        for state in backend.states {
            XCTAssertEqual(state.harmonyPerVoiceTargetDecibels, state.harmonyTargetDecibels)
            XCTAssertLessThanOrEqual(state.happeningPerVoiceTargetDecibels, state.happeningAggregateTargetDecibels)
        }
    }

    func testMasterDuckingAndRoleSpatialControlsAreCappedAtTheSafetyBoundary() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let malformed = LayerMixPlan(
            rhythmTargetDecibels: 6,
            bassTargetDecibels: 6,
            harmonyTargetDecibels: 6,
            happeningAggregateTargetDecibels: 6,
            happeningPerVoiceTargetDecibels: 6,
            happeningCount: 10,
            leadTargetDecibels: 6,
            masterTargetDecibelsBeforeLimiter: 12,
            maximumHarmonyDuckingDecibels: 99
        )

        controller.apply(
            malformed,
            activeChordVoiceCount: 4,
            harmonyDuckingDecibels: 99,
            spatial: .init(repeating: .init(sendLevel: 1, decay: 1)),
            rampDurationSeconds: 2
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertLessThanOrEqual(state.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertEqual(state.harmonyDuckingDecibels, 2.5)
        XCTAssertTrue(state.buses.all.allSatisfy {
            $0.sendLevel < DayObjectsAudioParameters.reverbFeedbackSafetyLimit
                && $0.decay < DayObjectsAudioParameters.reverbFeedbackSafetyLimit
        })
        XCTAssertLessThanOrEqual(state.happeningPerVoiceTargetDecibels, 0)
    }

    func testLeadDelayAndReverbRemainIndependentAndUseTheirOwnSafetyCaps() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)

        controller.apply(
            LayerMixPlanner.makePlan(happeningCount: 1),
            activeChordVoiceCount: 1,
            harmonyDuckingDecibels: 0,
            spatial: .init(
                rhythm: .init(sendLevel: 0, decay: 0),
                bass: .init(sendLevel: 0, decay: 0),
                harmony: .init(sendLevel: 0, decay: 0),
                happenings: .init(sendLevel: 0, decay: 0),
                lead: .init(
                    sendLevel: 0.37,
                    decay: 0.93,
                    secondarySendLevel: 0.81,
                    secondaryDecay: 0.99
                )
            ),
            rampDurationSeconds: 0
        )

        let lead = try XCTUnwrap(backend.states.last).buses.lead
        XCTAssertEqual(lead.sendLevel, 0.37)
        XCTAssertEqual(lead.decay, 0.93)
        XCTAssertEqual(lead.secondarySendLevel, 0.81)
        XCTAssertEqual(lead.secondaryDecay, 0.90)
    }

    func testNonFiniteInputsFallBackToConservativeFiniteTargets() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let malformed = LayerMixPlan(
            rhythmTargetDecibels: .nan,
            bassTargetDecibels: .infinity,
            harmonyTargetDecibels: .infinity,
            happeningAggregateTargetDecibels: -.infinity,
            happeningPerVoiceTargetDecibels: .nan,
            happeningCount: Int.max,
            leadTargetDecibels: .infinity,
            masterTargetDecibelsBeforeLimiter: .nan,
            maximumHarmonyDuckingDecibels: .infinity
        )

        controller.apply(
            malformed,
            activeChordVoiceCount: Int.max,
            harmonyDuckingDecibels: .nan,
            spatial: .init(repeating: .init(sendLevel: .nan, decay: .infinity)),
            rampDurationSeconds: .nan
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertTrue(state.finiteValues.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(state.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertLessThanOrEqual(state.harmonyDuckingDecibels, 2.5)
        XCTAssertTrue(state.buses.all.allSatisfy {
            $0.sendLevel < DayObjectsAudioParameters.reverbFeedbackSafetyLimit
                && $0.decay < DayObjectsAudioParameters.reverbFeedbackSafetyLimit
        })
        XCTAssertGreaterThanOrEqual(state.rampDurationSeconds, 0)
    }

    func testRepeatedUpdatesOnlyEmitBoundedTypedCommands() {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let plan = LayerMixPlanner.makePlan(happeningCount: 10)

        for index in 0..<1_000 {
            controller.apply(
                plan,
                activeChordVoiceCount: (index % 4) + 1,
                harmonyDuckingDecibels: Double(index % 5),
                spatial: testSpatial,
                rampDurationSeconds: 0.25
            )
        }

        XCTAssertEqual(backend.states.count, 1_000)
        XCTAssertTrue(backend.states.allSatisfy { $0.finiteValues.allSatisfy(\.isFinite) })
    }
}

@MainActor
private final class RecordingMixBackend: DayObjectsMixBackend {
    var states: [DayObjectsMixState] = []

    func apply(_ state: DayObjectsMixState) {
        states.append(state)
    }
}

private extension DayObjectsMixState {
    var finiteValues: [Double] {
        [
            rhythmTargetDecibels,
            bassTargetDecibels,
            harmonyTargetDecibels,
            harmonyPerVoiceTargetDecibels,
            happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels,
            leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter,
            harmonyDuckingDecibels,
            rampDurationSeconds,
        ] + buses.all.flatMap { [$0.directTargetDecibels, $0.sendLevel, $0.decay] }
    }
}

private let testSpatial = DayObjectsFiveRoleBusSpatialParameters(
    rhythm: .init(sendLevel: 0.1, decay: 0.2),
    bass: .init(sendLevel: 0.2, decay: 0.4),
    harmony: .init(sendLevel: 0.3, decay: 0.6),
    happenings: .init(sendLevel: 0.4, decay: 0.8),
    lead: .init(sendLevel: 0.5, decay: 0.7)
)
