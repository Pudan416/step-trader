#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class HappeningSchedulerTests: XCTestCase {
    func testStartAtNonzeroBoundaryAlignsEveryFirstCycleOccurrenceToThatBoundary() throws {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        let plans = (1...5).map { makePlan(index: $0, seed: 700) }
        try scheduler.configure(plans: plans, tonalWorld: world, remixSeed: 700)
        let boundary = MusicalPosition(absoluteSubdivision: 128)

        try scheduler.start(at: boundary)

        XCTAssertEqual(Set(scheduler.metrics.nextOccurrenceByHappeningID.keys), Set(plans.map(\.happeningID)))
        XCTAssertTrue(scheduler.metrics.nextOccurrenceByHappeningID.values.allSatisfy { $0 >= boundary })
        XCTAssertTrue(scheduler.metrics.scheduledOccurrencesByHappeningID.values
            .flatMap { $0 }
            .allSatisfy { $0 >= boundary })
        scheduler.render(event(.subdivision, subdivision: 128), currentChord: world.progression[0])
        XCTAssertTrue(scheduler.metrics.attackHistory.allSatisfy { $0.position >= boundary })
    }

    func testNeutralGlitchPreservesPlannedEffectsAndVariationAddsToBaseDelay() throws {
        let harness = try makeHarness(count: 0)
        let plan = makePlan(index: 1, seed: 44)
        try harness.scheduler.add(plan, currentChord: harness.world.progression[0], playBirth: true)
        let neutral = try XCTUnwrap(harness.pool.updateRequests.last)
        XCTAssertEqual(neutral.delaySend, plan.delaySend)
        XCTAssertEqual(neutral.reverbSend, plan.reverbSend)

        harness.scheduler.applyGlitch(.init(
            role: .happening, dryGain: 1, pitchDriftCents: 2,
            wowFlutterDepth: 0, stereoSeparationAddition: 0,
            delayTimeVariation: 0.05, saturationAmount: 0,
            timingDriftMilliseconds: 0, dropoutAttenuationDecibels: 0,
            dropoutReleaseSeconds: 0, rampDurationSeconds: 0.25
        ))
        let varied = try XCTUnwrap(harness.pool.updateRequests.last)
        XCTAssertEqual(try XCTUnwrap(varied.delaySend), plan.delaySend + 0.05, accuracy: 0.000_001)
        XCTAssertEqual(varied.reverbSend, plan.reverbSend)
    }

    func testEachHappeningAttackRealizesGlitchForItsActualOccurrenceIdentity() throws {
        let harness = try makeHarness(count: 0)
        let backend = RecordingHappeningGlitchBackend()
        let processor = GlitchProcessor(backend: backend)
        backend.onApply = { harness.scheduler.applyGlitch($0) }
        let glitch = DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: 10_000,
                stepGoal: 10_000,
                countedSleepHours: 8,
                sleepGoalHours: 8,
                happeningIDs: ["happening-1"],
                spentColors: 100
            ),
            remixSeed: 44
        ).glitch
        harness.scheduler.configureGlitch(plan: glitch, processor: processor)
        let plan = makePlan(index: 1, seed: 44)

        try harness.scheduler.add(plan, currentChord: harness.world.progression[0], playBirth: true)

        let attack = try XCTUnwrap(harness.scheduler.metrics.attackHistory.last)
        let command = try XCTUnwrap(backend.commands.last { $0.role == .happening })
        let expected = try XCTUnwrap(glitch.realizedEvent(
            for: .happening,
            cycleIndex: Int(attack.position.bar),
            stepIndex: attack.position.subdivisionInBar
        ))
        XCTAssertEqual(command.pitchDriftCents, expected.pitchDriftCents, accuracy: 0.000_001)
        XCTAssertEqual(command.delayTimeVariation, expected.delayTimeVariation, accuracy: 0.000_001)
        XCTAssertEqual(command.dropoutAttenuationDecibels, expected.shouldDropOut ? -6 : 0)
        let audibleUpdate = try XCTUnwrap(harness.pool.updateRequests.last)
        XCTAssertEqual(
            try XCTUnwrap(audibleUpdate.midiNote),
            Double(attack.midiNote) + expected.pitchDriftCents / 100,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(audibleUpdate.delaySend),
            plan.delaySend + expected.delayTimeVariation,
            accuracy: 0.000_001
        )
    }

    func testCountsOneFiveAndTenRenderEveryIDInFirstCycleAndStayInsideRecurrenceBands() throws {
        for (count, band) in [(1, 2...4), (5, 6...12), (10, 12...24)] {
            let harness = try makeHarness(count: count)
            let horizonBars = band.upperBound * 4
            renderBars(horizonBars, through: harness.scheduler, chord: harness.world.progression[0])

            let history = harness.scheduler.metrics.attackHistory.filter { !$0.isBirth }
            XCTAssertEqual(
                Set(history.filter { $0.position.bar < Int64(band.upperBound) }.map(\.happeningID)),
                Set(harness.plans.map(\.happeningID)),
                "count=\(count)"
            )
            for id in harness.plans.map(\.happeningID) {
                let attacks = history.filter { $0.happeningID == id }
                XCTAssertFalse(attacks.isEmpty)
                for pair in zip(attacks, attacks.dropFirst()) {
                    let gap = Int(pair.1.position.bar - pair.0.position.bar)
                    XCTAssertTrue(band.contains(gap), "count=\(count), id=\(id), gap=\(gap)")
                }
                XCTAssertLessThanOrEqual(
                    horizonBars - Int(try XCTUnwrap(attacks.last).position.bar),
                    band.upperBound
                )
            }
            assertDensityBounds(history, count: count)
        }
    }

    func testLiveAdditionPlaysOneBirthAgainstCurrentChordAndThenRecurs() throws {
        let harness = try makeHarness(count: 1)
        render(subdivisions: 0...8, through: harness.scheduler, chord: harness.world.progression[0])
        let added = makePlan(index: 2, seed: 9_012)

        try harness.scheduler.add(added, currentChord: harness.world.progression[1], playBirth: true)
        render(subdivisions: 9...256, through: harness.scheduler, chord: harness.world.progression[1])

        let attacks = harness.scheduler.metrics.attackHistory.filter { $0.happeningID == added.happeningID }
        XCTAssertEqual(attacks.filter(\.isBirth).count, 1)
        XCTAssertFalse(attacks.filter { !$0.isBirth }.isEmpty)
        let allowed = Set(harness.world.progression[1].chordPitchClasses + harness.world.progression[1].safePassingPitchClasses)
        XCTAssertTrue(attacks.allSatisfy { allowed.contains(Int($0.midiNote) % 12) })
        assertDensityBounds(harness.scheduler.metrics.attackHistory, count: 2)
    }

    func testLiveAdditionEmitsBirthImmediatelyAtCurrentPositionWhenAvailable() throws {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        let plan = makePlan(index: 1, seed: 99)
        let chord = ChordPlan(
            modalDegree: 1,
            rootPitchClass: 1,
            chordPitchClasses: [1],
            safePassingPitchClasses: [],
            voicedMIDINotes: [61],
            durationBars: 4
        )
        try scheduler.configure(plans: [], tonalWorld: world, remixSeed: 99)
        try scheduler.start()
        scheduler.render(event(.subdivision, subdivision: 7), currentChord: world.progression[0])

        try scheduler.add(plan, currentChord: chord, playBirth: true)

        let birth = try XCTUnwrap(scheduler.metrics.attackHistory.first)
        XCTAssertTrue(birth.isBirth)
        XCTAssertEqual(birth.happeningID, plan.happeningID)
        XCTAssertEqual(birth.position.absoluteSubdivision, 7)
        XCTAssertEqual(Int(birth.midiNote) % 12, 1)
    }

    func testSoundOffAdditionHasNoBirthButIsGuaranteedAfterStart() throws {
        let bank = RecordingHappeningBank()
        let worldBank = PlaybackWorldBank(instrumentBank: bank)
        let scheduler = HappeningScheduler(worldBank: worldBank)
        let world = makeWorld()
        let plan = makePlan(index: 1, seed: 4)

        try scheduler.configure(plans: [], tonalWorld: world, remixSeed: 4)
        try scheduler.add(plan, currentChord: world.progression[0], playBirth: false)
        XCTAssertTrue(scheduler.metrics.attackHistory.isEmpty)

        try scheduler.start()
        renderBars(4, through: scheduler, chord: world.progression[0])
        XCTAssertTrue(scheduler.metrics.attackHistory.contains {
            $0.happeningID == plan.happeningID && !$0.isBirth
        })
    }

    func testRemovalCancelsFutureAttacksAndReleasesOnlyOwnedTokens() throws {
        let harness = try makeHarness(count: 2, releaseSeconds: 20)
        renderBars(4, through: harness.scheduler, chord: harness.world.progression[0])
        let removedID = harness.plans[0].happeningID
        let survivorID = harness.plans[1].happeningID
        let cutoff = harness.scheduler.metrics.attackHistory.count

        harness.scheduler.remove(id: removedID)
        XCTAssertTrue(harness.pool.noteOffRequests.allSatisfy {
            $0.instrumentID == harness.plans[0].instrumentID
        })
        renderBars(4, through: harness.scheduler, chord: harness.world.progression[0], startBar: 4)

        XCTAssertFalse(harness.scheduler.metrics.attackHistory.dropFirst(cutoff).contains { $0.happeningID == removedID })
        XCTAssertTrue(harness.pool.noteOffRequests.allSatisfy {
            $0.instrumentID == harness.plans[0].instrumentID
        })
        XCTAssertGreaterThan(harness.scheduler.metrics.activeVoiceCountByHappeningID[survivorID, default: 0], 0)
        XCTAssertEqual(harness.scheduler.metrics.activeHappeningIDs, [survivorID])
    }

    func testStructuralReplacementWaitsForBoundaryAndRetainsStableID() throws {
        let harness = try makeHarness(count: 1)
        let id = harness.plans[0].happeningID
        let replacement = makePlan(index: 1, seed: 700, family: .bell, instrumentID: .init(rawValue: "keys.bell"))

        try harness.scheduler.scheduleStructuralReplacement(
            plans: [replacement],
            tonalWorld: harness.world,
            remixSeed: 700
        )
        harness.scheduler.render(event(.subdivision, subdivision: 1), currentChord: harness.world.progression[0])
        XCTAssertEqual(harness.scheduler.metrics.planByHappeningID[id]?.family, harness.plans[0].family)

        harness.scheduler.render(event(.barBoundary, subdivision: 16), currentChord: harness.world.progression[0])
        XCTAssertEqual(harness.scheduler.metrics.activeHappeningIDs, [id])
        XCTAssertEqual(harness.scheduler.metrics.planByHappeningID[id]?.family, .bell)
        XCTAssertEqual(harness.scheduler.metrics.planByHappeningID[id]?.instrumentID, .init(rawValue: "keys.bell"))
    }

    func testDifferentHappeningInstrumentsUseTheFixedPoolWithoutGenericFallback() throws {
        let harness = try makeHarness(count: 2)
        renderBars(4, through: harness.scheduler, chord: harness.world.progression[0])

        let requestedIDs = Set(harness.pool.noteOnRequests.map(\.instrumentID))
        XCTAssertTrue(requestedIDs.contains(harness.plans[0].instrumentID))
        XCTAssertTrue(requestedIDs.contains(harness.plans[1].instrumentID))
        XCTAssertEqual(harness.bank.preparedConfigurations, [.playbackWorld])
        XCTAssertEqual(harness.bank.pools.count, PlaybackWorldBankConfiguration.PoolName.allCases.count)
    }

    func testRecurringScheduleReplenishesPastTheInitialAllocationWindowWithoutStarvation() throws {
        let harness = try makeHarness(count: 10)
        renderBars(500, through: harness.scheduler, chord: harness.world.progression[0])

        let history = harness.scheduler.metrics.attackHistory.filter { !$0.isBirth }
        for id in harness.plans.map(\.happeningID) {
            let attacks = history.filter { $0.happeningID == id }
            XCTAssertGreaterThan(try XCTUnwrap(attacks.last).position.bar, 400, "id=\(id)")
            for pair in zip(attacks, attacks.dropFirst()) {
                XCTAssertTrue((12...24).contains(Int(pair.1.position.bar - pair.0.position.bar)))
            }
        }
        assertDensityBounds(history, count: 10)
    }

    func testRemovingFromTenToOneRebuildsTheSurvivorIntoTheTwoToFourBarBand() throws {
        let harness = try makeHarness(count: 10)
        renderBars(24, through: harness.scheduler, chord: harness.world.progression[0])
        let survivor = harness.plans[0].happeningID
        for plan in harness.plans.dropFirst() { harness.scheduler.remove(id: plan.happeningID) }
        let cutoff = harness.scheduler.metrics.attackHistory.count

        renderBars(20, through: harness.scheduler, chord: harness.world.progression[0], startBar: 24)

        let attacks = Array(harness.scheduler.metrics.attackHistory.dropFirst(cutoff)).filter {
            $0.happeningID == survivor && !$0.isBirth
        }
        XCTAssertFalse(attacks.isEmpty)
        XCTAssertLessThanOrEqual(try XCTUnwrap(attacks.first).position.bar - 24, 4)
        for pair in zip(attacks, attacks.dropFirst()) {
            let gap = pair.1.position.absoluteSubdivision - pair.0.position.absoluteSubdivision
            XCTAssertTrue((32...64).contains(gap), "gap=\(gap)")
        }
    }

    func testRealTransportOrderAppliesStructuralReplacementBeforeBoundarySubdivisionAttack() throws {
        let harness = try makeHarness(count: 1)
        render(subdivisions: 0...15, through: harness.scheduler, chord: harness.world.progression[0])
        let replacement = makePlan(
            index: 1,
            seed: 999,
            family: .bell,
            instrumentID: .init(rawValue: "keys.boundary")
        )
        try harness.scheduler.scheduleStructuralReplacement(
            plans: [replacement],
            tonalWorld: harness.world,
            remixSeed: 999
        )

        harness.scheduler.render(event(.subdivision, subdivision: 16), currentChord: harness.world.progression[1])
        harness.scheduler.render(event(.beat, subdivision: 16), currentChord: harness.world.progression[1])
        harness.scheduler.render(event(.barBoundary, subdivision: 16), currentChord: harness.world.progression[1])

        XCTAssertEqual(
            harness.scheduler.metrics.planByHappeningID[replacement.happeningID]?.instrumentID,
            replacement.instrumentID
        )
        XCTAssertFalse(harness.scheduler.metrics.attackHistory.contains {
            $0.position.absoluteSubdivision >= 16 && $0.instrumentID == harness.plans[0].instrumentID
        })
    }

    func testDeferredBirthUsesChordAtActualPlaybackTime() throws {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        try scheduler.configure(plans: [], tonalWorld: world, remixSeed: 12)
        try scheduler.start()
        let first = makePlan(index: 1, seed: 12)
        let deferred = makePlan(index: 2, seed: 12)
        let additionChord = ChordPlan(modalDegree: 0, rootPitchClass: 0, chordPitchClasses: [0], safePassingPitchClasses: [], voicedMIDINotes: [60], durationBars: 4)
        let playbackChord = ChordPlan(modalDegree: 1, rootPitchClass: 1, chordPitchClasses: [1], safePassingPitchClasses: [], voicedMIDINotes: [61], durationBars: 4)

        try scheduler.add(first, currentChord: additionChord, playBirth: true)
        try scheduler.add(deferred, currentChord: additionChord, playBirth: true)
        scheduler.render(event(.subdivision, subdivision: 1), currentChord: playbackChord)
        scheduler.render(event(.subdivision, subdivision: 2), currentChord: playbackChord)

        let attack = try XCTUnwrap(scheduler.metrics.attackHistory.first {
            $0.happeningID == deferred.happeningID && $0.isBirth
        })
        XCTAssertEqual(Int(attack.midiNote) % 12, 1)
    }

    func testRapidLiveBirthsRespectDensityAndFixedSixVoiceCapacityWithoutStarvation() throws {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        try scheduler.configure(plans: [], tonalWorld: world, remixSeed: 33)
        try scheduler.start()
        let plans = (1...10).map { makePlan(index: $0, seed: 33, releaseSeconds: 2) }
        for plan in plans {
            try scheduler.add(plan, currentChord: world.progression[0], playBirth: true)
        }
        guard let pool = bank.pools[PlaybackWorldBankConfiguration.PoolName.happenings.rawValue] else {
            return XCTFail("Missing fixed Happenings pool")
        }

        for subdivision in Int64(0)...256 {
            scheduler.render(event(.subdivision, subdivision: subdivision), currentChord: world.progression[0])
            XCTAssertLessThanOrEqual(scheduler.metrics.activeVoiceCount, 6)
            XCTAssertLessThanOrEqual(pool.metrics.activeVoiceCount, 6)
            XCTAssertEqual(scheduler.metrics.activeVoiceCount, pool.metrics.activeVoiceCount)
        }

        let births = scheduler.metrics.attackHistory.filter(\.isBirth)
        XCTAssertEqual(Set(births.map(\.happeningID)), Set(plans.map(\.happeningID)))
        assertDensityBounds(scheduler.metrics.attackHistory, count: 10)
    }

    func testAttackHistoryIsBoundedAndKeepsTheMostRecentEvents() throws {
        let harness = try makeHarness(count: 10)
        renderBars(2_000, through: harness.scheduler, chord: harness.world.progression[0])

        XCTAssertLessThanOrEqual(
            harness.scheduler.metrics.attackHistory.count,
            HappeningScheduler.maximumRecordedAttackCount
        )
        XCTAssertGreaterThan(try XCTUnwrap(harness.scheduler.metrics.attackHistory.last).position.bar, 1_900)
    }

    private func assertDensityBounds(_ history: [HappeningAttackRecord], count: Int) {
        let ordered = history.sorted { $0.position < $1.position }
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1.position.absoluteSubdivision - pair.0.position.absoluteSubdivision,
                1,
                "count=\(count)"
            )
        }
        let attacksByBeat = Dictionary(grouping: ordered, by: { $0.position.absoluteBeat })
        XCTAssertTrue(attacksByBeat.values.allSatisfy { $0.count <= 2 }, "count=\(count)")
    }

    private func makeHarness(count: Int, releaseSeconds: Double = 0.5) throws -> Harness {
        let bank = RecordingHappeningBank()
        let worldBank = PlaybackWorldBank(instrumentBank: bank)
        let scheduler = HappeningScheduler(worldBank: worldBank)
        let world = makeWorld()
        let plans = count > 0
            ? (1...count).map { makePlan(index: $0, seed: 42, releaseSeconds: releaseSeconds) }
            : []
        try scheduler.configure(plans: plans, tonalWorld: world, remixSeed: 42)
        try scheduler.start()
        return Harness(
            bank: bank,
            pool: try XCTUnwrap(bank.pools[PlaybackWorldBankConfiguration.PoolName.happenings.rawValue]),
            scheduler: scheduler,
            world: world,
            plans: plans
        )
    }

    private func renderBars(
        _ count: Int,
        through scheduler: HappeningScheduler,
        chord: ChordPlan,
        startBar: Int = 0
    ) {
        let start = Int64(startBar) * MusicalPosition.subdivisionsPerBar
        let end = Int64(startBar + count) * MusicalPosition.subdivisionsPerBar
        render(subdivisions: start...end, through: scheduler, chord: chord)
    }

    private func render(
        subdivisions: ClosedRange<Int64>,
        through scheduler: HappeningScheduler,
        chord: ChordPlan
    ) {
        for subdivision in subdivisions {
            scheduler.render(event(.subdivision, subdivision: subdivision), currentChord: chord)
        }
    }

    private func event(_ kind: DayObjectsTransportEventKind, subdivision: Int64) -> DayObjectsTransportEvent {
        .init(
            kind: kind,
            position: .init(absoluteSubdivision: subdivision),
            hostTimeSeconds: Double(subdivision) * 0.125,
            tempoBPM: 120
        )
    }

    private func makeWorld() -> TonalWorldPlan {
        TonalWorldPlan(
            centerPitchClass: 0,
            mode: .dorian,
            scalePitchClasses: [0, 2, 3, 5, 7, 9, 10],
            progression: [
                .init(modalDegree: 0, rootPitchClass: 0, chordPitchClasses: [0, 3, 7], safePassingPitchClasses: [2, 5, 9, 10], voicedMIDINotes: [48, 51, 55], durationBars: 4),
                .init(modalDegree: 5, rootPitchClass: 5, chordPitchClasses: [0, 5, 9], safePassingPitchClasses: [2, 3, 7, 10], voicedMIDINotes: [53, 57, 60], durationBars: 4),
            ],
            cycleBars: 8
        )
    }

    private func makePlan(
        index: Int,
        seed: UInt64,
        family: HappeningSoundFamily = .pluck,
        instrumentID: DayObjectsInstrumentID? = nil,
        releaseSeconds: Double = 0.5
    ) -> HappeningMusicPlan {
        .init(
            happeningID: "happening-\(index)",
            family: family,
            instrumentID: instrumentID ?? .init(rawValue: index.isMultiple(of: 2) ? "keys.soft" : "pluck.air"),
            motifScaleDegrees: [0, 2, 7],
            octave: 4,
            pan: index.isMultiple(of: 2) ? 0.4 : -0.4,
            gain: 0.24,
            birthGain: 0.32,
            attackSeconds: 0.02,
            releaseSeconds: releaseSeconds,
            delaySend: 0.31,
            reverbSend: 0.58,
            recurrence: .init(scheduleSeed: seed &+ UInt64(index), alignmentRank: UInt64(index), floatingOffsetBeats: 0.25)
        )
    }

    private struct Harness {
        let bank: RecordingHappeningBank
        let pool: RecordingHappeningPool
        let scheduler: HappeningScheduler
        let world: TonalWorldPlan
        let plans: [HappeningMusicPlan]
    }
}

@MainActor
private final class RecordingHappeningGlitchBackend: DayObjectsGlitchBackend {
    private(set) var commands: [DayObjectsGlitchCommand] = []
    var onApply: ((DayObjectsGlitchCommand) -> Void)?
    func apply(_ command: DayObjectsGlitchCommand) {
        commands.append(command)
        onApply?(command)
    }
}

@MainActor
private final class RecordingHappeningBank: DayObjectsInstrumentBankProtocol {
    let descriptors: [DayObjectsInstrumentDescriptor] = []
    private(set) var preparedConfigurations: [DayObjectsInstrumentBankConfiguration] = []
    private(set) var pools: [String: RecordingHappeningPool] = [:]
    let drumsRecorder = RecordingHappeningDrums()
    let pianoRecorder = RecordingHappeningPiano()

    var drums: DayObjectsDrumBankProtocol { drumsRecorder }
    var piano: DayObjectsPianoPoolProtocol { pianoRecorder }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(state: .prepared, tonalPoolCount: pools.count, graph: nil, allocationFingerprint: nil, drumMetrics: drums.metrics, pianoMetrics: piano.metrics)
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        preparedConfigurations.append(configuration)
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingHappeningPool(name: $0.name, capacity: $0.capacity))
        })
    }
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }
    func start() throws {}
    func stop() async {}
    func releaseAll() { pools.values.forEach { $0.releaseAll() } }
}

private final class RecordingHappeningPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    private(set) var preparedIDs: Set<DayObjectsInstrumentID> = []
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var noteOffRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var updateRequests: [DayObjectsVoiceUpdate] = []
    private var active: [DayObjectsVoiceToken: DayObjectsTonalNoteRequest] = [:]
    private var nextGeneration: UInt64 = 0
    var metrics: DayObjectsTonalPoolMetrics {
        .init(name: name, allocatedVoiceCount: capacity, allocatedNodeCount: capacity, activeVoiceCount: active.count, activeLeadVoiceCount: 0, activeChordVoiceCount: 0)
    }

    init(name: String, capacity: Int) { self.name = name; self.capacity = capacity }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws { preparedIDs.insert(id) }
    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws { preparedIDs.formUnion(ids) }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard preparedIDs.contains(request.instrumentID) else { return nil }
        guard active.count < capacity else { return nil }
        nextGeneration += 1
        let token = DayObjectsVoiceToken(slotID: Int(nextGeneration), generation: nextGeneration)
        active[token] = request
        noteOnRequests.append(request)
        return token
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {
        guard active[token] != nil else { return }
        updateRequests.append(update)
    }
    func noteOff(_ token: DayObjectsVoiceToken) {
        if let request = active.removeValue(forKey: token) { noteOffRequests.append(request) }
    }
    func releaseAll() { active.removeAll() }
}

private final class RecordingHappeningDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingHappeningPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
