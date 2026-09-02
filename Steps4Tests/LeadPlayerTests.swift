#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class LeadPlayerTests: XCTestCase {
    func testLiveMixAndGlitchCommandsMutateHeldVoiceWithoutRetrigger() throws {
        let harness = try makeHarness(gainDecibels: -6)
        harness.player.begin(.init(normalizedX: 0.5, normalizedY: 0.5, speed: 0))
        let attackCount = harness.pool.noteOnRequests.count
        let baseNote = try XCTUnwrap(harness.pool.updateRequests.last?.midiNote)
        let baseCutoff = try XCTUnwrap(harness.pool.updateRequests.last?.cutoffHz)

        harness.player.applyMixTargetDecibels(-18)
        harness.player.applyGlitch(.init(
            role: .lead, dryGain: 0.8, pitchDriftCents: 12,
            wowFlutterDepth: 0, stereoSeparationAddition: 0,
            delayTimeVariation: 0, saturationAmount: 0.2,
            timingDriftMilliseconds: 0, dropoutAttenuationDecibels: 0,
            dropoutReleaseSeconds: 0, rampDurationSeconds: 0.25
        ))

        XCTAssertEqual(harness.pool.noteOnRequests.count, attackCount)
        XCTAssertEqual(try XCTUnwrap(harness.pool.updateRequests.last?.midiNote), baseNote + 0.12, accuracy: 0.000_001)
        XCTAssertLessThan(try XCTUnwrap(harness.pool.updateRequests.last?.expression), 0.2)
        XCTAssertEqual(try XCTUnwrap(harness.pool.updateRequests.last?.cutoffHz), baseCutoff, accuracy: 0.000_001)
        XCTAssertEqual(harness.pool.updateRequests.last?.saturationAmount, 0.2)
        XCTAssertEqual(harness.pool.updateRequests.last?.saturationRampSeconds, 0.25)
        XCTAssertEqual(DayObjectsTonalVoice.graphLayout.saturationCount, 1)
    }

    func testSafeRemixHandoffGlidesExistingHeldTokenWithoutRetriggerAndKeepsGestureOwner() throws {
        let source = try makeHarness()
        let destination = try makeHarness()
        let birthGesture = LeadGestureSample(normalizedX: 0.32, normalizedY: 0.64, speed: 0.2)
        source.player.begin(birthGesture)
        let heldToken = try XCTUnwrap(source.pool.activeToken)

        let handoff = source.player.handoff(
            to: destination.player,
            safeCommonMIDINote: 64
        )

        XCTAssertEqual(handoff.gestureOwner, .source)
        XCTAssertTrue(handoff.didGlide)
        XCTAssertFalse(handoff.didRestart)
        XCTAssertEqual(source.pool.activeToken, heldToken)
        XCTAssertEqual(source.pool.noteOnRequests.count, 1)
        XCTAssertEqual(destination.pool.noteOnRequests.count, 0)
        XCTAssertEqual(source.player.metrics.amplitudeAttackCount, 1)
        XCTAssertEqual(destination.player.metrics.amplitudeAttackCount, 0)
        XCTAssertEqual(source.player.heldState?.currentMIDINote, 64)
        XCTAssertEqual(source.player.heldState?.lastGesture, birthGesture)
        XCTAssertEqual(source.player.metrics.voiceCount + destination.player.metrics.voiceCount, 1)

        let moved = LeadGestureSample(normalizedX: 0.81, normalizedY: 0.18, speed: 1.4)
        handoff.route(moved, source: source.player, destination: destination.player)
        XCTAssertEqual(source.player.heldState?.lastGesture, moved)
        XCTAssertNil(destination.player.heldState)

        source.player.end()
        XCTAssertNil(source.pool.activeToken, "The old-bank token must be absent before that bank can recycle")
    }

    func testUnsafeRemixHandoffSynchronouslyReleasesOnceRestartsOnceAndRoutesGesturesToDestination() throws {
        let source = try makeHarness()
        let destination = try makeHarness()
        let birthGesture = LeadGestureSample(normalizedX: 0.45, normalizedY: 0.72, speed: 0.3)
        source.player.begin(birthGesture)

        let handoff = source.player.handoff(
            to: destination.player,
            safeCommonMIDINote: nil
        )

        XCTAssertEqual(handoff.gestureOwner, .destination)
        XCTAssertFalse(handoff.didGlide)
        XCTAssertTrue(handoff.didRestart)
        XCTAssertEqual(source.pool.noteOffCount, 1)
        XCTAssertEqual(destination.pool.noteOnRequests.count, 1)
        XCTAssertNil(source.pool.activeToken)
        XCTAssertNotNil(destination.pool.activeToken)
        XCTAssertEqual(source.player.metrics.voiceCount + destination.player.metrics.voiceCount, 1)

        let moved = LeadGestureSample(normalizedX: 0.9, normalizedY: 0.1, speed: 2)
        handoff.route(moved, source: source.player, destination: destination.player)
        XCTAssertNil(source.player.heldState)
        XCTAssertEqual(destination.player.heldState?.lastGesture, moved)
        XCTAssertEqual(source.pool.noteOffCount, 1)
        XCTAssertEqual(destination.pool.noteOnRequests.count, 1)
    }

    func testOneThousandUpdatesKeepOneReservedVoiceAndOneAmplitudeAttack() throws {
        let harness = try makeHarness()

        harness.player.begin(.init(normalizedX: 0.2, normalizedY: 0.7, speed: 0))
        for index in 0..<1_000 {
            harness.player.update(.init(
                normalizedX: Double(index % 101) / 100,
                normalizedY: Double((index * 7) % 101) / 100,
                speed: Double(index % 5)
            ))
        }

        XCTAssertEqual(harness.pool.noteOnRequests.count, 1, "Coordinate updates must never retrigger the amplitude envelope")
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 1)
        XCTAssertEqual(harness.pool.metrics.activeLeadVoiceCount, 1)
        XCTAssertEqual(harness.player.metrics.voiceCount, 1)
        XCTAssertEqual(harness.player.metrics.amplitudeAttackCount, 1)
        XCTAssertEqual(harness.pool.updateRequests.count, 1_001, "Begin establishes filter state, then every move updates the same token")
        XCTAssertTrue(harness.pool.updateRequests.allSatisfy { $0.expression.map { (0...1).contains($0) } ?? true })
    }

    func testUpdatesUsePlannedPortamentoAndIndependentSmoothingWithoutEnvelopeRetrigger() throws {
        let harness = try makeHarness(portamentoMilliseconds: 160)
        harness.player.begin(.init(normalizedX: 0, normalizedY: 1, speed: 0))
        harness.player.update(.init(normalizedX: 1, normalizedY: 0, speed: 20))

        let update = try XCTUnwrap(harness.pool.updateRequests.last)
        XCTAssertEqual(try XCTUnwrap(update.pitchRampSeconds), 0.160, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(update.cutoffRampSeconds), 0.045, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(update.expressionRampSeconds), 0.080, accuracy: 0.000_001)
        XCTAssertNotNil(update.midiNote)
        XCTAssertNotNil(update.cutoffHz)
        XCTAssertLessThanOrEqual(update.expression ?? 2, 1)
        XCTAssertEqual(harness.pool.noteOnRequests.count, 1)
    }

    func testPlanPortamentoIsClampedToSixtyThroughOneHundredSixtyMilliseconds() throws {
        let fast = try makeHarness(portamentoMilliseconds: 1)
        fast.player.begin(.init(normalizedX: 0, normalizedY: 0.5, speed: 0))
        fast.player.update(.init(normalizedX: 1, normalizedY: 0.5, speed: 0))
        XCTAssertEqual(fast.pool.updateRequests.last?.pitchRampSeconds, 0.060)

        let slow = try makeHarness(portamentoMilliseconds: 1_000)
        slow.player.begin(.init(normalizedX: 0, normalizedY: 0.5, speed: 0))
        slow.player.update(.init(normalizedX: 1, normalizedY: 0.5, speed: 0))
        XCTAssertEqual(slow.pool.updateRequests.last?.pitchRampSeconds, 0.160)
    }

    func testChordChangeGlidesHeldVoiceToNearestCompatibleNoteAndEndReleasesOnce() throws {
        let harness = try makeHarness()
        harness.player.begin(.init(normalizedX: 0.62, normalizedY: 0.5, speed: 0))
        let held = try XCTUnwrap(harness.pool.noteOnRequests.last?.midiNote)

        harness.player.setCurrentChordIndex(1)
        let expected = try XCTUnwrap(harness.plan.nearestCompatibleNote(to: held, chordIndex: 1))
        XCTAssertEqual(harness.pool.updateRequests.last?.midiNote, Double(expected))
        XCTAssertEqual(harness.pool.updateRequests.last?.pitchRampSeconds, 0.110)
        XCTAssertEqual(harness.pool.noteOnRequests.count, 1)

        harness.player.end()
        harness.player.end()
        XCTAssertEqual(harness.pool.noteOffCount, 1)
        XCTAssertEqual(harness.player.metrics.voiceCount, 0)
        XCTAssertEqual(harness.player.metrics.releaseCount, 1)
    }

    func testBeginUsesSoftGainNonzeroAttackBoundedFilterAndPlanEffects() throws {
        let harness = try makeHarness(gainDecibels: -12)
        harness.player.begin(.init(normalizedX: 0.5, normalizedY: -9, speed: .infinity))

        let attack = try XCTUnwrap(harness.pool.noteOnRequests.last)
        XCTAssertEqual(attack.role, .lead)
        XCTAssertEqual(attack.envelopeVariant, .absolute(attackSeconds: 0.035, releaseSeconds: 0.65))
        XCTAssertGreaterThan(attack.velocity, 0)
        XCTAssertLessThan(attack.velocity, 1)
        XCTAssertEqual(attack.delaySend, 0.24)
        XCTAssertEqual(attack.reverbSend, 0.38)

        let initialControl = try XCTUnwrap(harness.pool.updateRequests.first)
        XCTAssertTrue((DayObjectsAudioParameters.minimumCutoffHz...DayObjectsAudioParameters.maximumCutoffHz).contains(initialControl.cutoffHz!))
        XCTAssertLessThanOrEqual(initialControl.expression ?? 2, 1)
    }

    private func makeHarness(
        portamentoMilliseconds: Double = 110,
        gainDecibels: Double = -10
    ) throws -> (player: LeadPlayer, pool: RecordingLeadPool, plan: LeadPlan) {
        let bank = RecordingLeadInstrumentBank()
        let world = PlaybackWorldBank(instrumentBank: bank)
        let player = LeadPlayer(worldBank: world)
        let plan = makeLeadPlan(portamentoMilliseconds: portamentoMilliseconds)
        try player.configure(plan: plan, gainDecibels: gainDecibels, currentChordIndex: 0)
        return (player, try XCTUnwrap(bank.leadPool), plan)
    }

    private func makeLeadPlan(portamentoMilliseconds: Double) -> LeadPlan {
        let chordZero: [UInt8] = [57, 60, 64, 69, 72, 76, 81]
        let chordOne: [UInt8] = [59, 62, 65, 69, 74, 77, 81]
        let regions = (0..<21).map { index in
            LeadPitchRegion(
                index: index,
                normalizedRange: (Double(index) / 21)...(Double(index + 1) / 21),
                preference: index.isMultiple(of: 3) ? .chordTone : .modeTone,
                midiNotesByChord: [chordZero[index % chordZero.count], chordOne[index % chordOne.count]]
            )
        }
        return LeadPlan(
            instrumentID: .init(rawValue: "lead.verbacious"),
            maximumSimultaneousVoices: 1,
            register: 57...81,
            pitchRegions: regions,
            compatibleChordMIDINotes: [chordZero, chordOne],
            portamentoMilliseconds: portamentoMilliseconds,
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

@MainActor
private final class RecordingLeadInstrumentBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    let drumBank = RecordingLeadDrums()
    let pianoBank = RecordingLeadPiano()
    private(set) var pools: [String: RecordingLeadPool] = [:]
    var leadPool: RecordingLeadPool? { pools[PlaybackWorldBankConfiguration.PoolName.lead.rawValue] }
    var drums: DayObjectsDrumBankProtocol { drumBank }
    var piano: DayObjectsPianoPoolProtocol { pianoBank }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(state: .prepared, tonalPoolCount: pools.count, graph: nil, allocationFingerprint: nil, drumMetrics: drums.metrics, pianoMetrics: piano.metrics)
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingLeadPool(name: $0.name, capacity: $0.capacity))
        })
    }
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }
    func start() throws {}
    func stop() async { releaseAllIncludingSharedHappenings() }
    func releaseWorldLocalVoices() { pools.values.forEach { $0.releaseAll() } }
    func releaseAllIncludingSharedHappenings() { releaseWorldLocalVoices() }
}

private final class RecordingLeadPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    private(set) var preparedInstrument: DayObjectsInstrumentID?
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var updateRequests: [DayObjectsVoiceUpdate] = []
    private(set) var noteOffCount = 0
    private var token: DayObjectsVoiceToken?
    var activeToken: DayObjectsVoiceToken? { token }
    var metrics: DayObjectsTonalPoolMetrics {
        .init(
            name: name,
            allocatedVoiceCount: capacity,
            allocatedNodeCount: capacity,
            activeVoiceCount: token == nil ? 0 : 1,
            activeLeadVoiceCount: token == nil ? 0 : 1,
            activeChordVoiceCount: 0
        )
    }

    init(name: String, capacity: Int) {
        self.name = name
        self.capacity = capacity
    }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws { preparedInstrument = id }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard request.instrumentID == preparedInstrument else { return nil }
        let token = DayObjectsVoiceToken(slotID: 0, generation: UInt64(noteOnRequests.count + 1))
        self.token = token
        noteOnRequests.append(request)
        return token
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {
        guard self.token == token else { return }
        updateRequests.append(DayObjectsAudioParameters.clamped(update, fallbackMIDINote: 60))
    }
    func noteOff(_ token: DayObjectsVoiceToken) {
        guard self.token == token else { return }
        self.token = nil
        noteOffCount += 1
    }
    func releaseAll() { token = nil }
}

private final class RecordingLeadDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingLeadPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {}
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
