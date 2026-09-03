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
            delayFeedback: 0.4,
            reverbFeedback: 0.7,
            rampDurationSeconds: 0.5
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertEqual(state.rhythmTargetDecibels, -6, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyTargetDecibels, -10.25, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyPerVoiceTargetDecibels, -10.25, accuracy: 1e-12)
        XCTAssertEqual(state.happeningAggregateTargetDecibels, -2, accuracy: 1e-12)
        XCTAssertEqual(state.happeningPerVoiceTargetDecibels, -2, accuracy: 1e-12)
        XCTAssertEqual(state.leadTargetDecibels, -12, accuracy: 1e-12)
        XCTAssertEqual(state.masterTargetDecibelsBeforeLimiter, -2, accuracy: 1e-12)
        XCTAssertEqual(state.harmonyDuckingDecibels, 1.25, accuracy: 1e-12)
        XCTAssertEqual(state.delayFeedback, 0.4, accuracy: 1e-12)
        XCTAssertEqual(state.reverbFeedback, 0.7, accuracy: 1e-12)
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
                delayFeedback: 0,
                reverbFeedback: 0,
                rampDurationSeconds: 0.25
            )
        }

        for state in backend.states {
            XCTAssertEqual(state.harmonyPerVoiceTargetDecibels, state.harmonyTargetDecibels)
            XCTAssertEqual(
                state.happeningPerVoiceTargetDecibels,
                state.happeningAggregateTargetDecibels
            )
        }
    }

    func testMasterDuckingAndFeedbackAreCappedAtTheSafetyBoundary() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let malformed = LayerMixPlan(
            rhythmTargetDecibels: 6,
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
            delayFeedback: 1,
            reverbFeedback: 1,
            rampDurationSeconds: 2
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertLessThanOrEqual(state.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertEqual(state.harmonyDuckingDecibels, 2.5)
        XCTAssertLessThan(state.delayFeedback, DayObjectsAudioParameters.delayFeedbackSafetyLimit)
        XCTAssertLessThan(state.reverbFeedback, DayObjectsAudioParameters.reverbFeedbackSafetyLimit)
        XCTAssertLessThan(state.delayFeedback, 1)
        XCTAssertLessThan(state.reverbFeedback, 1)
        XCTAssertLessThanOrEqual(state.happeningPerVoiceTargetDecibels, 0)
    }

    func testNonFiniteInputsFallBackToConservativeFiniteTargets() throws {
        let backend = RecordingMixBackend()
        let controller = DayObjectsMixController(backend: backend)
        let malformed = LayerMixPlan(
            rhythmTargetDecibels: .nan,
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
            delayFeedback: .nan,
            reverbFeedback: .infinity,
            rampDurationSeconds: .nan
        )

        let state = try XCTUnwrap(backend.states.last)
        XCTAssertTrue(state.finiteValues.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(state.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertLessThanOrEqual(state.harmonyDuckingDecibels, 2.5)
        XCTAssertLessThan(state.delayFeedback, DayObjectsAudioParameters.delayFeedbackSafetyLimit)
        XCTAssertLessThan(state.reverbFeedback, DayObjectsAudioParameters.reverbFeedbackSafetyLimit)
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
                delayFeedback: 0.4,
                reverbFeedback: 0.8,
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
            harmonyTargetDecibels,
            harmonyPerVoiceTargetDecibels,
            happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels,
            leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter,
            harmonyDuckingDecibels,
            delayFeedback,
            reverbFeedback,
            rampDurationSeconds,
        ]
    }
}
