import XCTest
@testable import Steps4

final class DayObjectsTonalVoicePoolTests: XCTestCase {
    private let firstID = DayObjectsInstrumentID(rawValue: "pad.first")
    private let secondID = DayObjectsInstrumentID(rawValue: "lead.second")

    func testPreparedPresetRemainsPendingUntilTheFixedGraphCanSynchronize() {
        var lifecycle = DayObjectsTonalVoiceGraphLifecycle()

        lifecycle.preparePreset()

        XCTAssertTrue(lifecycle.hasPendingPreset)
        XCTAssertFalse(lifecycle.synchronizeIfAttached(false))
        XCTAssertTrue(lifecycle.hasPendingPreset)
        XCTAssertTrue(lifecycle.synchronizeIfAttached(true))
        XCTAssertFalse(lifecycle.hasPendingPreset)
        XCTAssertEqual(lifecycle.configurationRevision, 1)
    }

    func testFilterEnvelopePlanModulatesTheActualCutoffRange() {
        let plan = DayObjectsTonalVoiceModulationPlan(
            preset: Self.voice(filterEnvelopeAmount: 0.75)
        )

        XCTAssertEqual(plan.filterEnvelope.startCutoffHz, 4_000)
        XCTAssertGreaterThan(plan.filterEnvelope.peakCutoffHz, plan.filterEnvelope.startCutoffHz)
        XCTAssertGreaterThan(
            plan.filterCutoff(envelopeLevel: 1, lfoPhase: 0),
            plan.filterCutoff(envelopeLevel: 0, lfoPhase: 0)
        )
    }

    func testFilterLFOPlanModulatesCutoffWithoutRoutingAmplitude() {
        let plan = DayObjectsTonalVoiceModulationPlan(
            preset: Self.voice(lfoTarget: .filter, lfoWaveform: .square, lfoDepth: 0.4)
        )

        XCTAssertEqual(plan.lfo.target, .filter)
        XCTAssertEqual(plan.lfo.waveform, .square)
        XCTAssertGreaterThan(
            plan.filterCutoff(envelopeLevel: 0, lfoPhase: 0.25),
            plan.filterCutoff(envelopeLevel: 0, lfoPhase: 0.75)
        )
        XCTAssertEqual(plan.amplitudeDepth, 0)
    }

    func testPitchLFOPlanPreservesEveryNormalizedWaveform() {
        let expectedOffsets: [(NormalizedSynthVoice.LFOWaveform, Double)] = [
            (.sine, 1),
            (.square, 1),
            (.sawtooth, -0.5),
            (.reverseSawtooth, 0.5),
        ]

        for (waveform, expectedOffset) in expectedOffsets {
            let plan = DayObjectsTonalVoiceModulationPlan(
                preset: Self.voice(lfoTarget: .pitch, lfoWaveform: waveform, lfoDepth: 0.5)
            )

            XCTAssertEqual(plan.lfo.waveform, waveform)
            XCTAssertEqual(plan.pitchSemitoneOffset(phase: 0.25), expectedOffset, accuracy: 0.000_001)
        }
    }

    func testLiveCutoffUpdateBecomesTheModulationBase() {
        var state = DayObjectsTonalVoiceModulationState(preset: Self.voice())

        state.updateBaseCutoffHz(1_250)

        XCTAssertEqual(state.baseCutoffHz, 1_250)
        XCTAssertEqual(state.filterCutoff(envelopeLevel: 0, lfoPhase: 0), 1_250)
        XCTAssertGreaterThan(state.filterCutoff(envelopeLevel: 1, lfoPhase: 0), 1_250)
    }

    func testDetachedNoteOffStopsModulationBeforeReturning() {
        var lifecycle = DayObjectsTonalVoiceModulationLifecycle()
        lifecycle.start()

        lifecycle.noteOff(isGraphAttached: false)

        XCTAssertFalse(lifecycle.isTimerActive)
    }

    func testVoiceControlExecutorSerializesSynchronousCallersOnItsQueue() {
        let executor = DayObjectsTonalVoiceControlExecutor(label: "DayObjectsTonalVoicePoolTests")
        let completion = expectation(description: "serialized control work")
        XCTAssertFalse(executor.isCurrentExecutor)

        DispatchQueue.global().async {
            executor.sync {
                XCTAssertTrue(executor.isCurrentExecutor)
                completion.fulfill()
            }
        }

        wait(for: [completion], timeout: 1)
    }

    func testDefaultAuditionPoolAllocatesExactlySixVoicesBeforePlayback() {
        let harness = makeHarness()

        XCTAssertEqual(harness.pool.specification, .manualAudition)
        XCTAssertEqual(harness.pool.metrics.allocatedVoiceCount, 6)
        XCTAssertEqual(harness.pool.metrics.allocatedNodeCount, 6 * FakeTonalVoice.allocatedNodesPerVoice)
        XCTAssertEqual(harness.voices.count, 6)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
    }

    func testCustomNamedPoolCapacityIsAFixedPreparationInput() {
        let specification = DayObjectsTonalPoolSpecification(
            name: "foreground-pad",
            capacity: 3,
            reservesLeadVoice: false
        )
        let harness = makeHarness(specification: specification)

        XCTAssertEqual(harness.pool.specification, specification)
        XCTAssertEqual(harness.pool.metrics.allocatedVoiceCount, 3)
        XCTAssertEqual(harness.voices.count, 3)
    }

    func testScheduledNoteForwardsTheHostTimeToTheAllocatedBackendWithoutAddingAVoice() throws {
        let harness = makeHarness(specification: .init(
            name: "scheduled-bass",
            capacity: 1,
            reservesLeadVoice: false
        ))
        try harness.pool.prepareInstrument(firstID)
        let allocationBefore = harness.pool.metrics.allocatedVoiceCount

        let token = harness.pool.noteOn(
            request(note: 43, role: .note),
            atHostTime: 42
        )

        XCTAssertNotNil(token)
        XCTAssertEqual(harness.voices.only?.scheduledGateHostTimes, [42])
        XCTAssertEqual(harness.voices.only?.noteOnCallCount, 1)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 1)
        XCTAssertEqual(harness.pool.metrics.allocatedVoiceCount, allocationBefore)
    }

    func testAuditionPoolReservesTheSixthVoiceForLeadAndStealsTheOldestNonLead() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)

        let originalTokens = (0..<5).compactMap { offset in
            harness.pool.noteOn(request(note: 48 + UInt8(offset), role: .note))
        }
        XCTAssertEqual(originalTokens.count, 5)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5)

        let replacement = harness.pool.noteOn(request(note: 72, role: .note))

        XCTAssertNotNil(replacement)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5)
        harness.pool.noteOff(originalTokens[0])
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5, "The oldest token must be stale after stealing")
        harness.pool.noteOff(originalTokens[1])
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 4, "A newer non-Lead voice must remain allocated")

        let lead = harness.pool.noteOn(request(note: 76, role: .lead))
        XCTAssertNotNil(lead)
        XCTAssertEqual(harness.pool.metrics.activeLeadVoiceCount, 1)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5)
    }

    func testLeadTokenIsProtectedWhenAFullPoolStealsAnotherVoice() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)

        let nonLead = (0..<5).compactMap { offset in
            harness.pool.noteOn(request(note: 48 + UInt8(offset), role: .note))
        }
        let lead = try XCTUnwrap(harness.pool.noteOn(request(note: 72, role: .lead)))
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 6)

        XCTAssertNotNil(harness.pool.noteOn(request(note: 84, role: .note)))
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 6)
        harness.pool.noteOff(lead)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5, "The Lead token must still own its voice")
        harness.pool.noteOff(nonLead[0])
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5, "The oldest non-Lead token must have been stolen")
    }

    func testLeadIsMonophonicAndReplacingItDoesNotConsumeAnotherVoice() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)

        let firstLead = try XCTUnwrap(harness.pool.noteOn(request(note: 60, role: .lead)))
        let secondLead = try XCTUnwrap(harness.pool.noteOn(request(note: 62, role: .lead)))

        XCTAssertNotEqual(firstLead, secondLead)
        XCTAssertEqual(harness.pool.metrics.activeLeadVoiceCount, 1)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 1)
        harness.pool.noteOff(firstLead)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 1)
        harness.pool.noteOff(secondLead)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
    }

    func testChordRoleUsesAtMostFourVoices() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)

        let chord = (0..<4).compactMap { offset in
            harness.pool.noteOn(request(note: 48 + UInt8(offset * 3), role: .chord))
        }

        XCTAssertEqual(chord.count, 4)
        XCTAssertEqual(harness.pool.metrics.activeChordVoiceCount, 4)
        XCTAssertNil(harness.pool.noteOn(request(note: 72, role: .chord)))
        XCTAssertEqual(harness.pool.metrics.activeChordVoiceCount, 4)
    }

    func testPresetSwitchReleasesAllGatesBeforeA120MillisecondReplacement() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        XCTAssertNotNil(harness.pool.noteOn(request(note: 60, role: .note)))

        try harness.pool.prepareInstrument(secondID)

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertTrue(harness.voices.allSatisfy { !$0.isGateOpen })
        XCTAssertEqual(harness.voices.flatMap(\.presetTransitions), Array(repeating: 0.120, count: 12))
        XCTAssertTrue(harness.voices.allSatisfy { $0.preparedInstrumentID == secondID })
    }

    func testReleaseIsIdempotentForTokenAndWholePool() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        let first = try XCTUnwrap(harness.pool.noteOn(request(note: 60, role: .note)))
        let second = try XCTUnwrap(harness.pool.noteOn(request(note: 64, role: .note)))

        harness.pool.noteOff(first)
        harness.pool.noteOff(first)
        harness.pool.releaseAll()
        harness.pool.releaseAll()
        harness.pool.noteOff(second)

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.voices.reduce(0) { $0 + $1.noteOffCallCount }, 2)
    }

    func testPoolPassesTheNotesAbsoluteRoleReleaseToTheRealVoiceBackend() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        let token = try XCTUnwrap(harness.pool.noteOn(.init(
            instrumentID: firstID,
            midiNote: 60,
            velocity: 0.5,
            role: .note,
            envelopeVariant: .absolute(attackSeconds: 1.25, releaseSeconds: 2.75),
            pan: 0,
            delaySend: 0.2,
            reverbSend: 0.5
        )))

        harness.pool.noteOff(token)

        XCTAssertEqual(harness.voices.flatMap(\.receivedReleaseSeconds), [2.75])
    }

    func testOneHundredPresetSwitchesNeverLeaveAStaleGate() throws {
        let harness = makeHarness(instrumentProvider: { _ in Self.safeVoice })
        try harness.pool.prepareInstrument(firstID)
        var currentID = firstID

        for index in 0..<100 {
            XCTAssertNotNil(
                harness.pool.noteOn(
                    request(
                        note: UInt8(48 + index % 24),
                        role: index.isMultiple(of: 7) ? .lead : .note,
                        instrumentID: currentID
                    )
                )
            )
            let nextID = DayObjectsInstrumentID(rawValue: "preset.\(index)")
            try harness.pool.prepareInstrument(nextID)
            currentID = nextID
            XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
            XCTAssertTrue(harness.voices.allSatisfy { !$0.isGateOpen })
        }

        XCTAssertEqual(harness.voices.reduce(0) { $0 + $1.noteOnCallCount }, 100)
        XCTAssertEqual(harness.voices.reduce(0) { $0 + $1.noteOffCallCount }, 100)
    }

    func testRepeatedStartReleaseCyclesPreserveAllocationMetrics() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        let baseline = harness.pool.metrics

        for index in 0..<1_000 {
            XCTAssertNotNil(harness.pool.noteOn(request(note: UInt8(36 + index % 48), role: .note)))
            harness.pool.releaseAll()
        }

        XCTAssertEqual(harness.pool.metrics, baseline)
        XCTAssertEqual(harness.voices.count, 6)
    }

    func testTypedTokenCannotReleaseAnotherPoolsVoice() throws {
        let first = makeHarness()
        let second = makeHarness()
        try first.pool.prepareInstrument(firstID)
        try second.pool.prepareInstrument(firstID)
        let foreignToken = try XCTUnwrap(first.pool.noteOn(request(note: 60, role: .note)))
        XCTAssertNotNil(second.pool.noteOn(request(note: 64, role: .note)))

        second.pool.noteOff(foreignToken)

        XCTAssertEqual(second.pool.metrics.activeVoiceCount, 1)
    }

    func testEngineBoundaryClampsNonfinitePresetWithoutReinterpretingDetuneHertz() throws {
        let unsafe = Self.voice(
            oscillator1DetuneHz: -500,
            oscillator2DetuneHz: 500,
            delayFeedback: .infinity,
            reverbFeedback: .nan,
            outputTrimDB: 12
        )
        let harness = makeHarness(instrumentProvider: { _ in unsafe })

        try harness.pool.prepareInstrument(firstID)

        let preset = try XCTUnwrap(harness.voices.first?.lastPreset)
        XCTAssertEqual(preset.oscillator1.detuneHz, -4)
        XCTAssertEqual(preset.oscillator2.detuneHz, 4)
        XCTAssertEqual(preset.delay.feedback, DayObjectsAudioParameters.maximumDelayFeedback)
        XCTAssertLessThan(preset.delay.feedback, DayObjectsAudioParameters.delayFeedbackSafetyLimit)
        XCTAssertEqual(preset.reverb.feedback, DayObjectsAudioParameters.defaultReverbFeedback)
        XCTAssertLessThan(preset.reverb.feedback, DayObjectsAudioParameters.reverbFeedbackSafetyLimit)
        XCTAssertEqual(preset.outputTrimDB, DayObjectsAudioParameters.maximumOutputTrimDB)
        XCTAssertTrue(Self.scalarValues(in: preset).allSatisfy(\.isFinite))
    }

    func testEveryBundledPresetRemainsBelowEngineFeedbackSafetyLimits() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let byID = Dictionary(uniqueKeysWithValues: zip(
            DayObjectsInstrumentManifest.defaultDescriptors.map(\.id),
            records.map { SynthOnePresetAdapter.convert($0).voice }
        ))
        let harness = makeHarness { id in
            guard let voice = byID[id] else { throw TestError.missingInstrument }
            return voice
        }

        for descriptor in DayObjectsInstrumentManifest.defaultDescriptors {
            try harness.pool.prepareInstrument(descriptor.id)
        }

        let presets = harness.voices.flatMap(\.receivedPresets)
        XCTAssertEqual(presets.count, 16 * 6)
        XCTAssertTrue(presets.allSatisfy { $0.delay.feedback < DayObjectsAudioParameters.delayFeedbackSafetyLimit })
        XCTAssertTrue(presets.allSatisfy { $0.reverb.feedback < DayObjectsAudioParameters.reverbFeedbackSafetyLimit })
    }

    func testNoteAndUpdateValuesAreClampedBeforeTheyReachBackend() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        let token = try XCTUnwrap(
            harness.pool.noteOn(
                .init(
                    instrumentID: firstID,
                    midiNote: 60,
                    velocity: .infinity,
                    role: .note,
                    envelopeVariant: .init(attackScale: -4, releaseScale: .nan),
                    pan: 8,
                    delaySend: -2,
                    reverbSend: 9
                )
            )
        )

        harness.pool.update(
            token,
            with: .init(
                midiNote: .infinity,
                cutoffHz: -1,
                expression: 4,
                pan: -8,
                delaySend: .nan,
                reverbSend: 3
            )
        )

        let start = try XCTUnwrap(harness.voices.compactMap(\.lastStart).first)
        XCTAssertEqual(start.velocity, 1)
        XCTAssertEqual(start.envelopeVariant, .init(attackScale: 0.25, releaseScale: 1))
        XCTAssertEqual(start.pan, 1)
        XCTAssertEqual(start.delaySend, 0)
        XCTAssertEqual(start.reverbSend, 1)

        let update = try XCTUnwrap(harness.voices.compactMap(\.lastUpdate).first)
        XCTAssertEqual(update.midiNote, 60)
        XCTAssertEqual(update.cutoffHz, 20)
        XCTAssertEqual(update.expression, 1)
        XCTAssertEqual(update.pan, -1)
        XCTAssertEqual(update.delaySend, 0)
        XCTAssertEqual(update.reverbSend, 1)
    }

    func testRequestForUnpreparedInstrumentIsRejectedWithoutOpeningAGate() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)

        XCTAssertNil(harness.pool.noteOn(request(note: 60, role: .note, instrumentID: secondID)))
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertTrue(harness.voices.allSatisfy { !$0.isGateOpen })
    }

    func testPreparedInstrumentSetUsesDifferentPresetsAcrossFixedIdleVoices() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstruments([firstID, secondID])

        let first = harness.pool.noteOn(request(note: 60, role: .note, instrumentID: firstID))
        let second = harness.pool.noteOn(request(note: 64, role: .note, instrumentID: secondID))

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 2)
        XCTAssertEqual(Set(harness.voices.compactMap(\.preparedInstrumentID)), [firstID, secondID])
        XCTAssertEqual(harness.voices.reduce(0) { $0 + $1.noteOnCallCount }, 2)
    }

    func testSinglePresetPreparationAfterASetRestoresExclusivePoolSemantics() throws {
        let harness = makeHarness()
        try harness.pool.prepareInstrument(firstID)
        try harness.pool.prepareInstruments([firstID, secondID])
        XCTAssertNotNil(harness.pool.noteOn(request(note: 64, role: .note, instrumentID: secondID)))

        try harness.pool.prepareInstrument(firstID)

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertNil(harness.pool.noteOn(request(note: 64, role: .note, instrumentID: secondID)))
        XCTAssertNotNil(harness.pool.noteOn(request(note: 60, role: .note, instrumentID: firstID)))
    }

    func testMixedInstrumentModeNeverRetunesOrStealsSixSoundingReleaseTails() throws {
        let clock = ManualMonotonicClock()
        let harness = makeHarness(
            specification: .init(name: "happenings", capacity: 6, reservesLeadVoice: false),
            monotonicTime: { clock.now },
            instrumentProvider: { _ in Self.safeVoice }
        )
        let ids = (0..<7).map { DayObjectsInstrumentID(rawValue: "happening.\($0)") }
        try harness.pool.prepareInstruments(ids)
        let tokens = ids.prefix(6).enumerated().compactMap { index, id in
            harness.pool.noteOn(request(
                note: UInt8(60 + index),
                role: .note,
                instrumentID: id,
                releaseSeconds: 4
            ))
        }
        let presetIDsBefore = harness.voices.compactMap(\.preparedInstrumentID)
        let transitionCountsBefore = harness.voices.map(\.presetTransitions.count)

        XCTAssertEqual(tokens.count, 6)
        XCTAssertNil(harness.pool.noteOn(request(note: 72, role: .note, instrumentID: ids[6])))
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 6)
        XCTAssertEqual(harness.voices.compactMap(\.preparedInstrumentID), presetIDsBefore)
        XCTAssertEqual(harness.voices.map(\.presetTransitions.count), transitionCountsBefore)

        harness.pool.noteOff(tokens[2])
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 5)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 1)
        XCTAssertEqual(harness.pool.metrics.occupiedVoiceCount, 6)
        XCTAssertNil(harness.pool.noteOn(request(note: 72, role: .note, instrumentID: ids[6])))
        XCTAssertEqual(harness.voices.compactMap(\.preparedInstrumentID), presetIDsBefore)
        XCTAssertEqual(harness.voices.map(\.presetTransitions.count), transitionCountsBefore)

        clock.now = 3.999
        XCTAssertNil(harness.pool.noteOn(request(note: 72, role: .note, instrumentID: ids[6])))
        XCTAssertEqual(harness.voices.map(\.presetTransitions.count), transitionCountsBefore)

        clock.now = 4
        XCTAssertNotNil(harness.pool.noteOn(request(note: 72, role: .note, instrumentID: ids[6])))
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 6)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        XCTAssertEqual(harness.pool.metrics.occupiedVoiceCount, 6)
        XCTAssertTrue(harness.voices.contains { $0.preparedInstrumentID == ids[6] })
        XCTAssertEqual(
            harness.voices.map(\.presetTransitions.count).reduce(0, +),
            transitionCountsBefore.reduce(0, +) + 1
        )
    }

    private func request(
        note: UInt8,
        role: DayObjectsTonalVoiceRole,
        instrumentID: DayObjectsInstrumentID? = nil,
        releaseSeconds: TimeInterval? = nil
    ) -> DayObjectsTonalNoteRequest {
        .init(
            instrumentID: instrumentID ?? firstID,
            midiNote: note,
            velocity: 0.8,
            role: role,
            envelopeVariant: releaseSeconds.map {
                .absolute(attackSeconds: 0.01, releaseSeconds: $0)
            },
            pan: 0,
            delaySend: 1,
            reverbSend: 1
        )
    }

    private func makeHarness(
        specification: DayObjectsTonalPoolSpecification = .manualAudition
    ) -> Harness {
        makeHarness(specification: specification) { id in
            guard id == DayObjectsInstrumentID(rawValue: "pad.first") || id == DayObjectsInstrumentID(rawValue: "lead.second") else {
                throw TestError.missingInstrument
            }
            return Self.safeVoice
        }
    }

    private func makeHarness(
        instrumentProvider: @escaping (DayObjectsInstrumentID) throws -> NormalizedSynthVoice
    ) -> Harness {
        makeHarness(specification: .manualAudition, instrumentProvider: instrumentProvider)
    }

    private func makeHarness(
        specification: DayObjectsTonalPoolSpecification,
        monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        instrumentProvider: @escaping (DayObjectsInstrumentID) throws -> NormalizedSynthVoice
    ) -> Harness {
        var voices: [FakeTonalVoice] = []
        let pool = DayObjectsTonalVoicePool(
            specification: specification,
            instrumentProvider: instrumentProvider,
            voiceFactory: {
                let voice = FakeTonalVoice()
                voices.append(voice)
                return voice
            },
            monotonicTime: monotonicTime
        )
        return Harness(pool: pool, voices: voices)
    }

    private struct Harness {
        let pool: DayObjectsTonalVoicePool
        let voices: [FakeTonalVoice]
    }

    private enum TestError: Error {
        case missingInstrument
    }

    private final class ManualMonotonicClock {
        var now: TimeInterval = 0
    }

    private final class FakeTonalVoice: DayObjectsTonalVoiceBackend {
        static let allocatedNodesPerVoice = 23

        let allocatedNodeCount = allocatedNodesPerVoice
        private(set) var isGateOpen = false
        private(set) var preparedInstrumentID: DayObjectsInstrumentID?
        private(set) var receivedPresets: [NormalizedSynthVoice] = []
        private(set) var presetTransitions: [TimeInterval] = []
        private(set) var noteOnCallCount = 0
        private(set) var noteOffCallCount = 0
        private(set) var receivedReleaseSeconds: [TimeInterval] = []
        private(set) var scheduledGateHostTimes: [TimeInterval] = []
        private(set) var lastStart: DayObjectsTonalNoteRequest?
        private(set) var lastUpdate: DayObjectsVoiceUpdate?

        var lastPreset: NormalizedSynthVoice? { receivedPresets.last }

        func replacePreset(
            _ preset: NormalizedSynthVoice,
            instrumentID: DayObjectsInstrumentID,
            transitionDuration: TimeInterval
        ) {
            receivedPresets.append(preset)
            preparedInstrumentID = instrumentID
            presetTransitions.append(transitionDuration)
        }

        func noteOn(_ request: DayObjectsTonalNoteRequest) {
            isGateOpen = true
            noteOnCallCount += 1
            lastStart = request
        }

        func noteOn(_ request: DayObjectsTonalNoteRequest, atHostTime hostTime: TimeInterval) {
            scheduledGateHostTimes.append(hostTime)
            noteOn(request)
        }

        func update(_ update: DayObjectsVoiceUpdate) {
            lastUpdate = update
        }

        func noteOff() {
            guard isGateOpen else { return }
            isGateOpen = false
            noteOffCallCount += 1
        }

        func noteOff(releaseSeconds: TimeInterval?) {
            if let releaseSeconds { receivedReleaseSeconds.append(releaseSeconds) }
            noteOff()
        }
    }

    private static let safeVoice = voice()

    private static func voice(
        oscillator1DetuneHz: Double = 0,
        oscillator2DetuneHz: Double = 2,
        delayFeedback: Double = 0.4,
        reverbFeedback: Double = 0.8,
        outputTrimDB: Double = -18,
        filterEnvelopeAmount: Double = 0.4,
        lfoTarget: NormalizedSynthVoice.LFOTarget = .filter,
        lfoWaveform: NormalizedSynthVoice.LFOWaveform = .sine,
        lfoDepth: Double = 0.2
    ) -> NormalizedSynthVoice {
        .init(
            oscillator1: .init(wavePosition: 0.25, level: 0.6, semitoneOffset: 0, detuneHz: oscillator1DetuneHz),
            oscillator2: .init(wavePosition: 0.75, level: 0.4, semitoneOffset: 12, detuneHz: oscillator2DetuneHz),
            oscillatorBalance: 0.5,
            subOscillator: .init(level: 0.2, waveform: .sine, octaveOffset: -1),
            noiseLevel: 0.1,
            amplitudeEnvelope: .init(attackSeconds: 0.05, decaySeconds: 0.2, sustainLevel: 0.8, releaseSeconds: 0.4),
            filter: .init(
                kind: .lowPass,
                cutoffHz: 4_000,
                resonance: 0.3,
                envelope: .init(attackSeconds: 0.02, decaySeconds: 0.3, sustainLevel: 0.5, releaseSeconds: 0.5),
                envelopeAmount: filterEnvelopeAmount
            ),
            glideSeconds: 0.05,
            isMonophonic: false,
            lfo: .init(target: lfoTarget, rateHz: 0.5, depth: lfoDepth, waveform: lfoWaveform),
            delay: .init(isEnabled: true, timeSeconds: 0.25, feedback: delayFeedback, mix: 0.2),
            reverb: .init(isEnabled: true, feedback: reverbFeedback, highPassHz: 80, mix: 0.3),
            phaser: .init(rateHz: 0.4, feedback: 0.2, mix: 0.2, notchWidthHz: 800),
            autoPan: .init(rateHz: 0.25, depth: 0.2, stereoWidth: 0.5),
            outputTrimDB: outputTrimDB,
            referenceMIDI: 60,
            auditionChord: [48, 55, 62, 67]
        )
    }

    private static func scalarValues(in voice: NormalizedSynthVoice) -> [Double] {
        [
            voice.oscillator1.wavePosition, voice.oscillator1.level, voice.oscillator1.detuneHz,
            voice.oscillator2.wavePosition, voice.oscillator2.level, voice.oscillator2.detuneHz,
            voice.oscillatorBalance, voice.subOscillator.level, voice.noiseLevel,
            voice.amplitudeEnvelope.attackSeconds, voice.amplitudeEnvelope.decaySeconds,
            voice.amplitudeEnvelope.sustainLevel, voice.amplitudeEnvelope.releaseSeconds,
            voice.filter.cutoffHz, voice.filter.resonance, voice.filter.envelope.attackSeconds,
            voice.filter.envelope.decaySeconds, voice.filter.envelope.sustainLevel,
            voice.filter.envelope.releaseSeconds, voice.filter.envelopeAmount,
            voice.glideSeconds, voice.lfo.rateHz, voice.lfo.depth,
            voice.delay.timeSeconds, voice.delay.feedback, voice.delay.mix,
            voice.reverb.feedback, voice.reverb.highPassHz, voice.reverb.mix,
            voice.phaser.rateHz, voice.phaser.feedback, voice.phaser.mix, voice.phaser.notchWidthHz,
            voice.autoPan.rateHz, voice.autoPan.depth, voice.autoPan.stereoWidth,
            voice.outputTrimDB,
        ]
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
