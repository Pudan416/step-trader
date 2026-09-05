#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class HappeningSchedulerTests: XCTestCase {
    func testAttackObserverPublishesOnlySuccessfullyStartedHappening() throws {
        let harness = try makeHarness(count: 0)
        let plan = makePlan(index: 1, seed: 202)
        let sound = resolvedSound(
            recipeID: plan.recipeID,
            chord: chord(pitchClass: 0),
            world: harness.world
        )
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: sound.recipeID))
        try harness.pool.prepare(recipeIDs: [plan.recipeID])
        let manualHandles = try (0..<4).map { _ in
            try harness.pool.play(
                sound,
                gain: 1,
                priority: .manualAudition,
                effects: effectCommand(for: recipe)
            )
        }
        var observed = [HappeningAttackRecord]()
        harness.scheduler.onAttack = { observed.append($0) }

        try harness.scheduler.add(
            plan,
            currentChord: chord(pitchClass: 0),
            playBirth: true
        )
        XCTAssertTrue(observed.isEmpty)

        harness.pool.stop(manualHandles[0])
        renderBars(2, through: harness.scheduler, chord: chord(pitchClass: 0))

        let attack = try XCTUnwrap(observed.first)
        XCTAssertEqual(attack.happeningID, plan.happeningID)
        XCTAssertTrue(attack.isBirth)
        XCTAssertEqual(observed, harness.scheduler.metrics.attackHistory)
    }

    func testStartingWithExistingHappeningsIntroducesThemAsBirthSounds() throws {
        let harness = try makeHarness(count: 10, playInitialBirths: true)

        render(
            subdivisions: 0...MusicalPosition.subdivisionsPerBar,
            through: harness.scheduler,
            chord: harness.world.progression[0]
        )

        let firstAttack = try XCTUnwrap(harness.scheduler.metrics.attackHistory.first)
        XCTAssertTrue(firstAttack.isBirth)
        XCTAssertEqual(firstAttack.position, MusicalPosition(absoluteSubdivision: 0))
        XCTAssertEqual(
            harness.scheduler.metrics.attackHistory.filter(\.isBirth).count,
            1,
            "Existing happenings must not fire as a ten-sound cluster when Sound starts"
        )

        renderBars(15, through: harness.scheduler, chord: harness.world.progression[0], startBar: 1)
        XCTAssertLessThanOrEqual(
            harness.scheduler.metrics.attackHistory.filter { !$0.isBirth }.count,
            1,
            "The automatic voices must enter gradually instead of forming a startup queue"
        )
    }

    func testMixedAvailableAndUnavailablePlansKeepValidHappeningsAudible() throws {
        let unavailable = recipeID(2)
        let bank = RecordingHappeningBank(unavailableRecipeIDs: [unavailable])
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        let valid = makePlan(index: 1, seed: 42)
        let invalid = makePlan(index: 2, seed: 42, recipeID: unavailable)

        try scheduler.configure(plans: [valid, invalid], tonalWorld: world, remixSeed: 42)
        try scheduler.start()
        renderBars(41, through: scheduler, chord: world.progression[0])

        XCTAssertEqual(scheduler.metrics.activeHappeningIDs, [valid.happeningID])
        XCTAssertTrue(scheduler.metrics.attackHistory.contains { $0.happeningID == valid.happeningID })
        XCTAssertFalse(scheduler.metrics.attackHistory.contains { $0.happeningID == invalid.happeningID })
    }

    func testProlongedManualPressureUsesBoundedSpacedRetriesWithoutCommittingRejectedGlitchOrEffects() throws {
        let harness = try makeHarness(count: 1)
        let sound = resolvedSound(recipeID: harness.plans[0].recipeID, chord: chord(pitchClass: 0), world: harness.world)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: sound.recipeID))
        for _ in 0..<4 {
            _ = try harness.pool.play(
                sound,
                gain: 1,
                priority: .manualAudition,
                effects: effectCommand(for: recipe)
            )
        }
        let glitchBackend = RecordingHappeningGlitchBackend()
        let glitchProcessor = GlitchProcessor(backend: glitchBackend)
        harness.scheduler.configureGlitch(plan: .neutral, processor: glitchProcessor)
        let explicitEffectCount = harness.pool.explicitGlobalEffectCalls.count

        withExtendedLifetime(glitchProcessor) {
            renderBars(40, through: harness.scheduler, chord: chord(pitchClass: 0))
        }

        let failedAutomatic = harness.pool.playAttempts.filter { $0.priority == .recurrence }
        XCTAssertGreaterThan(failedAutomatic.count, 0)
        XCTAssertLessThanOrEqual(failedAutomatic.count, 80)
        XCTAssertTrue(harness.scheduler.metrics.attackHistory.isEmpty)
        XCTAssertEqual(harness.pool.explicitGlobalEffectCalls.count, explicitEffectCount)
        XCTAssertTrue(glitchBackend.commands.isEmpty)
    }

    func testPendingBirthRemainsEligibleWithBoundedRetriesAndPlaysAfterPressureClears() throws {
        let harness = try makeHarness(count: 0)
        let plan = makePlan(index: 1, seed: 99)
        let sound = resolvedSound(recipeID: plan.recipeID, chord: chord(pitchClass: 0), world: harness.world)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: sound.recipeID))
        try harness.pool.prepare(recipeIDs: [plan.recipeID])
        var manualHandles: [HappeningPlaybackHandle] = []
        for _ in 0..<4 {
            manualHandles.append(try harness.pool.play(
                sound,
                gain: 1,
                priority: .manualAudition,
                effects: effectCommand(for: recipe)
            ))
        }

        try harness.scheduler.add(plan, currentChord: chord(pitchClass: 0), playBirth: true)
        renderBars(12, through: harness.scheduler, chord: chord(pitchClass: 0))
        let blockedAttempts = harness.pool.playAttempts.filter { $0.priority == .birth }.count
        // Four one-beat attempts per one-bar admission window, with a one-bar
        // cool-down before the pending birth rearms.
        XCTAssertLessThanOrEqual(blockedAttempts, 32)
        XCTAssertTrue(harness.scheduler.metrics.attackHistory.isEmpty)

        harness.pool.stop(manualHandles[0])
        renderBars(4, through: harness.scheduler, chord: chord(pitchClass: 5), startBar: 12)

        let birth = try XCTUnwrap(harness.scheduler.metrics.attackHistory.first { $0.isBirth })
        XCTAssertEqual(birth.resolvedSound.targetMIDI.map { Int($0) % 12 }, 5)
    }

    func testMixAndPitchWearUpdateOwnedHandleFromStableBaseValues() throws {
        let harness = try makeHarness(count: 0)
        let plan = makePlan(index: 1, seed: 101)
        try harness.scheduler.add(plan, currentChord: chord(pitchClass: 0), playBirth: true)
        let play = try XCTUnwrap(harness.pool.successfulPlayCalls.last)

        harness.scheduler.applyMixTargetDecibels(-6)
        harness.scheduler.applyGlitch(.neutral(role: .happening).replacing(
            dryGain: 0.5,
            pitchDriftCents: 10
        ))

        let update = try XCTUnwrap(harness.pool.updateCalls.last)
        XCTAssertEqual(update.handle, play.handle)
        XCTAssertEqual(update.gain, plan.birthGain * pow(10, -6.0 / 20) * 0.5, accuracy: 1e-12)
        XCTAssertEqual(update.playbackRate, play.sound.playbackRate * pow(2, 10.0 / 1_200), accuracy: 1e-12)

        harness.scheduler.applyGlitch(.neutral(role: .happening).replacing(pitchDriftCents: -10))
        XCTAssertEqual(
            try XCTUnwrap(harness.pool.updateCalls.last).playbackRate,
            play.sound.playbackRate * pow(2, -10.0 / 1_200),
            accuracy: 1e-12
        )
    }

    func testDeadlineRemovalAndReplacementCannotStopNewerManualVoiceThatStoleSchedulerHandle() throws {
        let harness = try makeHarness(count: 1)
        let plan = harness.plans[0]
        for subdivision in Int64(0)...MusicalPosition.subdivisionsPerBar * 40 {
            harness.scheduler.render(event(.subdivision, subdivision: subdivision), currentChord: chord(pitchClass: 0))
            if harness.scheduler.metrics.attackHistory.isEmpty == false { break }
        }
        let automatic = try XCTUnwrap(harness.pool.successfulPlayCalls.last)
        XCTAssertEqual(automatic.priority, .recurrence)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID))
        for _ in 0..<3 {
            _ = try harness.pool.play(
                automatic.sound,
                gain: 1,
                priority: .birth,
                effects: effectCommand(for: recipe)
            )
        }
        let manual = try harness.pool.play(
            automatic.sound,
            gain: 1,
            priority: .manualAudition,
            effects: effectCommand(for: recipe)
        )
        XCTAssertEqual(manual.voiceID, automatic.handle.voiceID)

        let deadlineStart = harness.scheduler.metrics.attackHistory.last?.position.bar ?? 0
        renderBars(2, through: harness.scheduler, chord: chord(pitchClass: 0), startBar: Int(deadlineStart))
        harness.scheduler.remove(id: plan.happeningID)
        try harness.scheduler.scheduleStructuralReplacement(plans: [], tonalWorld: harness.world, remixSeed: 103)
        harness.scheduler.render(event(.barBoundary, subdivision: 32), currentChord: chord(pitchClass: 0))

        XCTAssertTrue(harness.pool.activeHandles.contains(manual))
        XCTAssertFalse(harness.pool.stopCalls.contains { $0.handle == manual })
    }

    func testConfigurePreparesRecipesOnSharedSamplePoolWithoutUsingATonalHappeningPool() throws {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let plans = [makePlan(index: 1, seed: 42), makePlan(index: 2, seed: 42)]

        try scheduler.configure(plans: plans, tonalWorld: makeWorld(), remixSeed: 42)

        XCTAssertEqual(bank.samplePool.preparedRecipeIDs, Set(plans.map(\.recipeID)))
        XCTAssertEqual(bank.tonalPools.count, PlaybackWorldBankConfiguration.PoolName.allCases.count)
        XCTAssertTrue(bank.tonalPools.values.allSatisfy { $0.noteOnRequests.isEmpty })
    }

    func testBirthAndRecurrenceResolveAtAttackTimeThroughSameRecipeAndEffectPath() throws {
        let harness = try makeHarness(count: 0)
        let plan = makePlan(index: 1, seed: 44)
        let birthChord = chord(pitchClass: 1)
        let recurrenceChord = chord(pitchClass: 5)
        harness.scheduler.render(event(.subdivision, subdivision: 7), currentChord: harness.world.progression[0])

        try harness.scheduler.add(plan, currentChord: birthChord, playBirth: true)
        render(subdivisions: 8...512, through: harness.scheduler, chord: recurrenceChord)

        let calls = harness.pool.successfulPlayCalls.filter { $0.sound.recipeID == plan.recipeID }
        let birth = try XCTUnwrap(calls.first { $0.priority == .birth })
        let recurrence = try XCTUnwrap(calls.first { $0.priority == .recurrence })
        XCTAssertEqual(birth.sound.targetMIDI, 73)
        XCTAssertEqual(recurrence.sound.targetMIDI, 77)
        XCTAssertEqual(birth.sound.recipeID, recurrence.sound.recipeID)
        XCTAssertEqual(birth.pan, plan.pan, accuracy: 1e-12)
        XCTAssertEqual(recurrence.pan, plan.pan, accuracy: 1e-12)

        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID))
        let expectedEffects = HappeningEffectCommand(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: recipe.delayMix,
            delayFeedback: recipe.delayFeedback,
            reverbMix: recipe.reverbMix
        )
        XCTAssertTrue(calls.allSatisfy { $0.effects == expectedEffects })

        let attacks = harness.scheduler.metrics.attackHistory.filter { $0.happeningID == plan.happeningID }
        XCTAssertEqual(attacks.first(where: \.isBirth)?.resolvedSound, birth.sound)
        XCTAssertEqual(attacks.first(where: { !$0.isBirth })?.resolvedSound, recurrence.sound)
        XCTAssertEqual(attacks.first(where: \.isBirth)?.effectCommand, expectedEffects)
        XCTAssertEqual(attacks.first(where: { !$0.isBirth })?.effectCommand, expectedEffects)
    }

    func testDeferredBirthUsesCurrentChordWhenItActuallyGetsAVoice() throws {
        let harness = try makeHarness(count: 0)
        let first = makePlan(index: 1, seed: 12)
        let deferred = makePlan(index: 2, seed: 12)

        try harness.scheduler.add(first, currentChord: chord(pitchClass: 0), playBirth: true)
        try harness.scheduler.add(deferred, currentChord: chord(pitchClass: 0), playBirth: true)
        harness.scheduler.render(event(.subdivision, subdivision: 4), currentChord: chord(pitchClass: 1))

        let attack = try XCTUnwrap(harness.scheduler.metrics.attackHistory.first {
            $0.happeningID == deferred.happeningID && $0.isBirth
        })
        XCTAssertEqual(attack.resolvedSound.targetMIDI.map { Int($0) % 12 }, 1)
        XCTAssertEqual(attack.playbackPriority, .birth)
    }

    func testBirthStealsRecurrenceButCannotStealManualAuditionAtFourVoicePressure() throws {
        let harness = try makeHarness(count: 0)
        let recurringSound = resolvedSound(recipeID: recipeID(1), chord: chord(pitchClass: 0), world: harness.world)
        try harness.pool.prepare(recipeIDs: [recurringSound.recipeID])
        let recurringRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recurringSound.recipeID))
        for _ in 0..<4 {
            _ = try harness.pool.play(recurringSound, gain: 1, priority: .recurrence, effects: effectCommand(for: recurringRecipe))
        }

        let birthPlan = makePlan(index: 2, seed: 90)
        try harness.scheduler.add(birthPlan, currentChord: chord(pitchClass: 1), playBirth: true)

        XCTAssertEqual(harness.pool.successfulPlayCalls.last?.priority, .birth)
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 4)
        XCTAssertTrue(harness.scheduler.metrics.attackHistory.contains {
            $0.happeningID == birthPlan.happeningID && $0.playbackPriority == .birth
        })

        harness.pool.releaseAll()
        for _ in 0..<4 {
            _ = try harness.pool.play(recurringSound, gain: 1, priority: .manualAudition, effects: effectCommand(for: recurringRecipe))
        }
        let blockedPlan = makePlan(index: 3, seed: 90)
        try harness.scheduler.add(blockedPlan, currentChord: chord(pitchClass: 2), playBirth: true)

        XCTAssertFalse(harness.scheduler.metrics.attackHistory.contains {
            $0.happeningID == blockedPlan.happeningID
        })
        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 4)
        XCTAssertTrue(harness.pool.currentPriorities.allSatisfy { $0 == .manualAudition })
    }

    func testBlockedRecurrenceRetriesAfterManualPressureClearsInsteadOfBeingUnscheduled() throws {
        let harness = try makeHarness(count: 1)
        let sound = resolvedSound(recipeID: harness.plans[0].recipeID, chord: chord(pitchClass: 0), world: harness.world)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: sound.recipeID))
        let manualVoiceIDs = try (0..<4).map { _ in
            try harness.pool.play(sound, gain: 1, priority: .manualAudition, effects: effectCommand(for: recipe))
        }

        var blockedAt: Int64?
        for subdivision in Int64(0)...Int64(40 * MusicalPosition.subdivisionsPerBar) {
            harness.scheduler.render(
                event(.subdivision, subdivision: subdivision),
                currentChord: chord(pitchClass: 0)
            )
            if harness.pool.playAttempts.contains(where: { $0.priority == .recurrence }) {
                blockedAt = subdivision
                break
            }
        }
        let retryOrigin = try XCTUnwrap(blockedAt)
        XCTAssertTrue(harness.scheduler.metrics.attackHistory.isEmpty)

        harness.pool.stop(manualVoiceIDs[0])
        render(
            subdivisions: (retryOrigin + 1)...(retryOrigin + MusicalPosition.subdivisionsPerBar),
            through: harness.scheduler,
            chord: chord(pitchClass: 0)
        )

        let recurrence = try XCTUnwrap(harness.scheduler.metrics.attackHistory.first)
        XCTAssertFalse(recurrence.isBirth)
        XCTAssertEqual(recurrence.playbackPriority, .recurrence)
        XCTAssertLessThanOrEqual(
            recurrence.position.absoluteSubdivision - retryOrigin,
            MusicalPosition.subdivisionsPerBar
        )
    }

    func testCountsOneFiveAndTenStayInsideRecurrenceBandsAndDensityCaps() throws {
        for (count, band) in [(1, 24...40), (5, 56...96), (10, 112...192)] {
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

    func testLiveAdditionBirthsOnceThenRecursWithSameRecipe() throws {
        let harness = try makeHarness(count: 1)
        render(subdivisions: 0...8, through: harness.scheduler, chord: harness.world.progression[0])
        let added = makePlan(index: 2, seed: 9_012)

        try harness.scheduler.add(added, currentChord: harness.world.progression[1], playBirth: true)
        render(subdivisions: 9...512, through: harness.scheduler, chord: harness.world.progression[1])

        let attacks = harness.scheduler.metrics.attackHistory.filter { $0.happeningID == added.happeningID }
        XCTAssertEqual(attacks.filter(\.isBirth).count, 1)
        XCTAssertFalse(attacks.filter { !$0.isBirth }.isEmpty)
        XCTAssertTrue(attacks.allSatisfy { $0.resolvedSound.recipeID == added.recipeID })
        assertDensityBounds(harness.scheduler.metrics.attackHistory, count: 2)
    }

    func testStructuralReplacementWaitsForBoundaryAndSwitchesRecipe() throws {
        let harness = try makeHarness(count: 1)
        let original = harness.plans[0]
        let replacement = makePlan(index: 1, seed: 700, recipeID: recipeID(13))

        try harness.scheduler.scheduleStructuralReplacement(
            plans: [replacement], tonalWorld: harness.world, remixSeed: 700
        )
        harness.scheduler.render(event(.subdivision, subdivision: 1), currentChord: harness.world.progression[0])
        XCTAssertEqual(harness.scheduler.metrics.planByHappeningID[original.happeningID]?.recipeID, original.recipeID)

        harness.scheduler.render(event(.barBoundary, subdivision: 16), currentChord: harness.world.progression[0])
        XCTAssertEqual(harness.scheduler.metrics.planByHappeningID[replacement.happeningID]?.recipeID, replacement.recipeID)
        XCTAssertTrue(harness.pool.preparedRecipeIDs.contains(replacement.recipeID))
    }

    func testRemovalCancelsFutureAttacksAndStopsOnlyOwnedSampleVoices() throws {
        let harness = try makeHarness(count: 2)
        var firstAttack: HappeningAttackRecord?
        for subdivision in Int64(0)...Int64(40 * MusicalPosition.subdivisionsPerBar) {
            harness.scheduler.render(
                event(.subdivision, subdivision: subdivision),
                currentChord: harness.world.progression[0]
            )
            if let attack = harness.scheduler.metrics.attackHistory.first {
                firstAttack = attack
                break
            }
        }
        let attack = try XCTUnwrap(firstAttack)
        let removalPosition = attack.position
        let removed = try XCTUnwrap(
            harness.plans.first { $0.happeningID == attack.happeningID }
        )
        let cutoff = harness.scheduler.metrics.attackHistory.count

        harness.scheduler.remove(id: removed.happeningID)
        render(
            subdivisions: (removalPosition.absoluteSubdivision + 1)...(
                removalPosition.absoluteSubdivision + Int64(10 * MusicalPosition.subdivisionsPerBar)
            ),
            through: harness.scheduler,
            chord: harness.world.progression[0]
        )

        XCTAssertTrue(harness.pool.stopCalls.contains { $0.play.sound.recipeID == removed.recipeID })
        XCTAssertFalse(harness.scheduler.metrics.attackHistory.dropFirst(cutoff).contains {
            $0.happeningID == removed.happeningID
        })
        XCTAssertFalse(harness.scheduler.metrics.activeHappeningIDs.contains(removed.happeningID))
    }

    func testAttackHistoryIsBoundedAndKeepsMostRecentResolvedEvents() throws {
        let harness = try makeHarness(count: 10)
        renderBars(2_000, through: harness.scheduler, chord: harness.world.progression[0])

        let history = harness.scheduler.metrics.attackHistory
        XCTAssertLessThanOrEqual(history.count, HappeningScheduler.maximumRecordedAttackCount)
        XCTAssertGreaterThan(try XCTUnwrap(history.last).position.bar, 1_900)
        XCTAssertTrue(history.allSatisfy { HappeningSoundCatalog.recipe(for: $0.resolvedSound.recipeID) != nil })
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

    private func makeHarness(
        count: Int,
        playInitialBirths: Bool = false
    ) throws -> Harness {
        let bank = RecordingHappeningBank()
        let scheduler = HappeningScheduler(worldBank: PlaybackWorldBank(instrumentBank: bank))
        let world = makeWorld()
        let plans = count > 0 ? (1...count).map { makePlan(index: $0, seed: 42) } : []
        try scheduler.configure(plans: plans, tonalWorld: world, remixSeed: 42)
        try scheduler.start(playInitialBirths: playInitialBirths)
        return Harness(bank: bank, pool: bank.samplePool, scheduler: scheduler, world: world, plans: plans)
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
                chord(pitchClass: 0),
                chord(pitchClass: 5),
            ],
            cycleBars: 8
        )
    }

    private func chord(pitchClass: Int) -> ChordPlan {
        .init(
            modalDegree: pitchClass,
            rootPitchClass: pitchClass,
            chordPitchClasses: [pitchClass],
            safePassingPitchClasses: [],
            voicedMIDINotes: [UInt8(60 + pitchClass)],
            durationBars: 4
        )
    }

    private func makePlan(
        index: Int,
        seed: UInt64,
        recipeID: HappeningSoundRecipeID? = nil
    ) -> HappeningMusicPlan {
        let selectedID = recipeID ?? self.recipeID(((index - 1) % 30) + 1)
        let recipe = HappeningSoundCatalog.recipe(for: selectedID)!
        return .init(
            happeningID: "happening-\(index)",
            family: soundFamily(for: recipe.family),
            recipeID: selectedID,
            pan: index.isMultiple(of: 2) ? 0.4 : -0.4,
            gain: 0.24,
            birthGain: 0.32,
            attackSeconds: 0.02,
            releaseSeconds: 0.5,
            delaySend: 0.99,
            reverbSend: 0.99,
            recurrence: .init(
                scheduleSeed: seed &+ UInt64(index),
                alignmentRank: UInt64(index),
                floatingOffsetBeats: 0.25
            )
        )
    }

    private func resolvedSound(
        recipeID: HappeningSoundRecipeID,
        chord: ChordPlan,
        world: TonalWorldPlan
    ) -> ResolvedHappeningSound {
        HappeningPitchResolver.resolve(
            recipe: HappeningSoundCatalog.recipe(for: recipeID)!,
            chord: chord,
            tonalWorld: world
        )
    }

    private func recipeID(_ rawValue: Int) -> HappeningSoundRecipeID {
        HappeningSoundRecipeID(rawValue: rawValue)!
    }

    private func effectCommand(for recipe: HappeningSoundRecipe) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: recipe.delayMix,
            delayFeedback: recipe.delayFeedback,
            reverbMix: recipe.reverbMix
        )
    }

    private func soundFamily(for family: HappeningRecipeFamily) -> HappeningSoundFamily {
        switch family {
        case .synthPluck: return .pluck
        case .acousticMallet: return .mallet
        case .acousticBell: return .bell
        case .softOneShot: return .softOneShot
        case .texture: return .texture
        }
    }

    private struct Harness {
        let bank: RecordingHappeningBank
        let pool: RecordingHappeningSamplePool
        let scheduler: HappeningScheduler
        let world: TonalWorldPlan
        let plans: [HappeningMusicPlan]
    }
}

@MainActor
private final class RecordingHappeningBank: DayObjectsInstrumentBankProtocol {
    let descriptors: [DayObjectsInstrumentDescriptor] = []
    let samplePool: RecordingHappeningSamplePool
    private(set) var preparedConfigurations: [DayObjectsInstrumentBankConfiguration] = []
    private(set) var tonalPools: [String: RecordingHappeningTonalPool] = [:]
    let drumsRecorder = RecordingHappeningDrums()
    let pianoRecorder = RecordingHappeningPiano()

    init(unavailableRecipeIDs: Set<HappeningSoundRecipeID> = []) {
        samplePool = RecordingHappeningSamplePool(unavailableRecipeIDs: unavailableRecipeIDs)
    }

    var drums: DayObjectsDrumBankProtocol { drumsRecorder }
    var piano: DayObjectsPianoPoolProtocol { pianoRecorder }
    var happenings: DayObjectsHappeningSamplePoolProtocol { samplePool }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: .prepared,
            tonalPoolCount: tonalPools.count,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics,
            happeningMetrics: samplePool.metrics
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        preparedConfigurations.append(configuration)
        tonalPools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingHappeningTonalPool(name: $0.name, capacity: $0.capacity))
        })
    }

    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = tonalPools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }

    func start() throws {}
    func stop() async {}
    func releaseWorldLocalVoices() {
        tonalPools.values.forEach { $0.releaseAll() }
    }
    func releaseAllIncludingSharedHappenings() {
        releaseWorldLocalVoices()
        samplePool.releaseAll()
    }
}

@MainActor
private final class RecordingHappeningGlitchBackend: DayObjectsGlitchBackend {
    private(set) var commands: [DayObjectsGlitchCommand] = []
    func apply(_ command: DayObjectsGlitchCommand) { commands.append(command) }
}

@MainActor
private final class RecordingHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    struct PlayCall: Equatable {
        let handle: HappeningPlaybackHandle
        let sound: ResolvedHappeningSound
        let gain: Double
        let priority: HappeningPlaybackPriority
        let effects: HappeningEffectCommand
        let pan: Double
    }

    struct PlayAttempt: Equatable {
        let sound: ResolvedHappeningSound
        let gain: Double
        let priority: HappeningPlaybackPriority
        let effects: HappeningEffectCommand
        let pan: Double
    }

    struct GlobalEffectCall: Equatable {
        let command: HappeningEffectCommand
        let rampSeconds: Double
    }

    struct StopCall {
        let handle: HappeningPlaybackHandle
        let play: PlayCall
    }

    private var active: [Int: PlayCall] = [:]
    private let unavailableRecipeIDs: Set<HappeningSoundRecipeID>
    private(set) var preparedRecipeIDs: Set<HappeningSoundRecipeID> = []
    private(set) var playAttempts: [PlayAttempt] = []
    private(set) var successfulPlayCalls: [PlayCall] = []
    private(set) var explicitGlobalEffectCalls: [GlobalEffectCall] = []
    private(set) var updateCalls: [(handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double)] = []
    private(set) var stopCalls: [StopCall] = []
    private var stealCount = 0
    private var generation: UInt64 = 0

    init(unavailableRecipeIDs: Set<HappeningSoundRecipeID> = []) {
        self.unavailableRecipeIDs = unavailableRecipeIDs
    }

    var activeHandles: Set<HappeningPlaybackHandle> {
        Set(active.values.map(\.handle))
    }

    var currentPriorities: [HappeningPlaybackPriority] {
        active.keys.sorted().compactMap { active[$0]?.priority }
    }

    var metrics: HappeningSamplePoolMetrics {
        .init(
            allocatedPlayerCount: 4,
            fixedPlayerIdentities: [],
            activeVoiceCount: active.count,
            releasingVoiceCount: 0,
            stealCount: stealCount,
            decodedBufferCount: preparedRecipeIDs.count,
            decodedBufferIdentities: [],
            decodedByteCount: preparedRecipeIDs.count * 1_024,
            availableRecipeIDs: preparedRecipeIDs,
            unavailableRecipeIDs: unavailableRecipeIDs,
            effects: aggregateEffects,
            lastEffectRampSeconds: explicitGlobalEffectCalls.last?.rampSeconds ?? 0
        )
    }

    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {
        preparedRecipeIDs.formUnion(recipeIDs.subtracting(unavailableRecipeIDs))
    }

    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand,
        pan: Double = 0
    ) throws -> HappeningPlaybackHandle {
        guard preparedRecipeIDs.contains(sound.recipeID) else {
            throw HappeningSamplePoolError.recipeUnavailable(sound.recipeID)
        }
        let attempt = PlayAttempt(sound: sound, gain: gain, priority: priority, effects: effects, pan: pan)
        playAttempts.append(attempt)
        let voiceID: Int
        if let idle = (0..<4).first(where: { active[$0] == nil }) {
            voiceID = idle
        } else if let eligible = active
            .filter({ $0.value.priority < priority })
            .map(\.key)
            .min() {
            voiceID = eligible
            stealCount += 1
        } else {
            throw HappeningSamplePoolError.noEligibleVoice
        }
        generation &+= 1
        let handle = HappeningPlaybackHandle(voiceID: voiceID, generation: generation)
        let call = PlayCall(handle: handle, sound: sound, gain: gain, priority: priority, effects: effects, pan: pan)
        active[voiceID] = call
        successfulPlayCalls.append(call)
        return handle
    }

    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {
        explicitGlobalEffectCalls.append(.init(command: command, rampSeconds: rampSeconds))
    }

    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {
        guard active[handle.voiceID]?.handle == handle else { return }
        updateCalls.append((handle, gain, playbackRate))
    }

    func stop(_ handle: HappeningPlaybackHandle) {
        guard let play = active[handle.voiceID], play.handle == handle else { return }
        active[handle.voiceID] = nil
        stopCalls.append(.init(handle: handle, play: play))
    }

    func releaseAll() { active.removeAll() }

    private var aggregateEffects: HappeningEffectCommand {
        let values = active.values.map(\.effects)
        guard values.isEmpty == false else {
            return .init(filterCutoffHz: 8_000, delayMix: 0, delayFeedback: 0, reverbMix: 0)
        }
        let count = Double(values.count)
        return .init(
            filterCutoffHz: values.reduce(0) { $0 + $1.filterCutoffHz } / count,
            delayMix: values.reduce(0) { $0 + $1.delayMix } / count,
            delayFeedback: values.reduce(0) { $0 + $1.delayFeedback } / count,
            reverbMix: values.reduce(0) { $0 + $1.reverbMix } / count
        )
    }
}

private final class RecordingHappeningTonalPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    var metrics: DayObjectsTonalPoolMetrics {
        .init(
            name: name,
            allocatedVoiceCount: capacity,
            allocatedNodeCount: capacity,
            activeVoiceCount: 0,
            activeLeadVoiceCount: 0,
            activeChordVoiceCount: 0
        )
    }

    init(name: String, capacity: Int) {
        self.name = name
        self.capacity = capacity
    }

    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        noteOnRequests.append(request)
        return nil
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() {}
}

private final class RecordingHappeningDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics {
        .init(allocatedPlayerCount: 0, enabledVoiceCount: 0)
    }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingHappeningPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics {
        .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0)
    }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
