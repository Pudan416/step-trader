#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsRemixCoordinatorTests: XCTestCase {
    func testOneHundredProductionCoordinatorRemixesRecycleBothWorldsAndPreservePhysicalGraphAcrossRestarts() async throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        var plan = productionCyclePlan(seed: 10_000)
        try runtime.prepare(plan: plan)
        try runtime.startAudio()
        try runtime.startPreparedWorldForTesting()
        try runtime.fadeMaster(to: plan)

        let baselineTopology = runtime.engineTopologyForTesting
        let baselineAllocation = runtime.allocationSnapshotForTesting
        XCTAssertFalse(baselineTopology.avAudioEngineAttachedNodeIdentities.isEmpty)
        XCTAssertFalse(baselineTopology.avAudioEngineConnections.isEmpty)
        XCTAssertEqual(baselineTopology.meterTapNodeIdentities.count, 7)
        XCTAssertEqual(baselineTopology.meterTapInstallationCount, 1)

        for cycle in 1...100 {
            let start = Int64(cycle * 48 - 32)
            plan = productionCyclePlan(seed: UInt64(10_000 + cycle))
            runtime.scheduleStructuralPlan(plan)
            runtime.renderForTesting(productionEvent(position: start))
            XCTAssertEqual(runtime.remixResultForTesting, .transitioned(seed: plan.seed), "cycle \(cycle)")
            runtime.renderForTesting(productionEvent(position: start + 32))

            if cycle.isMultiple(of: 10) {
                let topology = runtime.engineTopologyForTesting
                XCTAssertEqual(topology.avAudioEngineAttachedNodeIdentities, baselineTopology.avAudioEngineAttachedNodeIdentities, "cycle \(cycle)")
                XCTAssertEqual(topology.avAudioEngineConnections, baselineTopology.avAudioEngineConnections, "cycle \(cycle)")
                XCTAssertEqual(topology.meterTapNodeIdentities, baselineTopology.meterTapNodeIdentities, "cycle \(cycle)")
                XCTAssertEqual(topology.meterTapInstallationCount, 1, "cycle \(cycle)")
                XCTAssertEqual(runtime.allocationSnapshotForTesting, baselineAllocation, "cycle \(cycle)")
            }

            if cycle.isMultiple(of: 20) {
                await runtime.stopAudio()
                try runtime.prepare(plan: plan)
                try runtime.startAudio()
                try runtime.startPreparedWorldForTesting()
                try runtime.fadeMaster(to: plan)
            }
        }

        XCTAssertEqual(runtime.worldRecycleCountsForTesting, [50, 50])
        XCTAssertEqual(runtime.allocationSnapshotForTesting, baselineAllocation)

        runtime.beginLead(.init(normalizedX: 0.45, normalizedY: 0.75, speed: 0))
        for kind in [
            DayObjectsTransportEventKind.subdivision,
            .beat,
            .barBoundary,
            .harmonicCycleBoundary,
        ] {
            runtime.renderForTesting(.init(
                kind: kind,
                position: .init(absoluteSubdivision: 0),
                hostTimeSeconds: 0,
                tempoBPM: plan.rhythm.tempoBPM
            ))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        let restartedTopology = runtime.engineTopologyForTesting
        let restartedMeters = runtime.playbackPairMetricsForTesting
        XCTAssertEqual(restartedTopology.avAudioEngineAttachedNodeIdentities, baselineTopology.avAudioEngineAttachedNodeIdentities)
        XCTAssertEqual(restartedTopology.avAudioEngineConnections, baselineTopology.avAudioEngineConnections)
        XCTAssertEqual(restartedTopology.meterTapNodeIdentities, baselineTopology.meterTapNodeIdentities)
        XCTAssertEqual(restartedTopology.meterTapInstallationCount, 1)
        XCTAssertEqual(Set(restartedMeters.meterTapCapturedScalarSampleCounts.keys), [
            "rhythm", "bass", "harmony", "happenings", "lead", "preLimiter", "finalOutput",
        ])
        XCTAssertTrue(restartedMeters.meterTapCapturedScalarSampleCounts.values.allSatisfy { $0 > 0 })
        for role in DayObjectsRoleBus.allCases {
            XCTAssertGreaterThan(restartedMeters.roleBusMetrics.metrics(for: role).peakDBFS, -120, "\(role)")
        }
        XCTAssertGreaterThan(restartedMeters.masterMetrics.peakDBFS, -120)

        runtime.endLead()
        await runtime.stopAudio()
    }

    func testCancelPendingRemixLeavesCurrentWorldRunningAndClearsOnlyQueuedPlan() throws {
        let harness = try makeHarness(initialSeed: 700)
        harness.runtime.resetLog()
        harness.coordinator.schedule(makePlan(seed: 701))

        harness.coordinator.cancelPending()

        XCTAssertNil(harness.coordinator.pendingPlan)
        XCTAssertEqual(harness.coordinator.currentPlan?.seed, 700)
        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0)
        XCTAssertTrue(harness.runtime.log.isEmpty)
    }

    func testInitRejectsTwoWorldWrappersAroundSameUnderlyingInstrumentBank() {
        let sharedBank = RecordingRemixInstrumentBank()
        XCTAssertThrowsError(try DayObjectsRemixCoordinator(
            bankA: PlaybackWorldBank(instrumentBank: sharedBank),
            bankB: PlaybackWorldBank(instrumentBank: sharedBank),
            runtime: RecordingRemixRuntime()
        )) { error in
            XCTAssertEqual(error as? DayObjectsRemixCoordinatorError, .duplicateInstrumentBank)
        }
    }

    func testPrepareCanRetryAfterSecondBankFailsWithoutRepreparingFirstBank() throws {
        let runtime = RecordingRemixRuntime()
        let instrumentA = RecordingRemixInstrumentBank()
        let instrumentB = RecordingRemixInstrumentBank()
        instrumentB.failPrepare = true
        let worldA = PlaybackWorldBank(instrumentBank: instrumentA)
        let worldB = PlaybackWorldBank(instrumentBank: instrumentB)
        let coordinator = try DayObjectsRemixCoordinator(
            bankA: worldA,
            bankB: worldB,
            runtime: runtime
        )
        let initialPlan = makePlan(seed: 880)

        XCTAssertThrowsError(try coordinator.prepare(initialPlan: initialPlan))
        XCTAssertEqual(instrumentA.prepareCount, 1)
        XCTAssertEqual(instrumentB.prepareAttemptCount, 1)
        XCTAssertTrue(runtime.configuredPlans.isEmpty)
        XCTAssertEqual(runtime.preparedAggregateCount, 1)
        XCTAssertNil(coordinator.currentPlan)

        instrumentB.failPrepare = false
        try coordinator.prepare(initialPlan: initialPlan)
        XCTAssertEqual(instrumentA.prepareCount, 1)
        XCTAssertEqual(instrumentB.prepareCount, 1)
        XCTAssertEqual(instrumentB.prepareAttemptCount, 2)
        XCTAssertEqual(runtime.preparedAggregateCount, 2)
        XCTAssertEqual(coordinator.currentPlan, initialPlan)
    }

    func testPrepareCanRetryAfterInitialRuntimeConfigureFailureCoherently() throws {
        let runtime = RecordingRemixRuntime()
        runtime.failureStage = .configure
        let instrumentA = RecordingRemixInstrumentBank()
        let instrumentB = RecordingRemixInstrumentBank()
        let worldA = PlaybackWorldBank(instrumentBank: instrumentA)
        let worldB = PlaybackWorldBank(instrumentBank: instrumentB)
        let coordinator = try DayObjectsRemixCoordinator(
            bankA: worldA,
            bankB: worldB,
            runtime: runtime
        )
        let initialPlan = makePlan(seed: 881)

        XCTAssertThrowsError(try coordinator.prepare(initialPlan: initialPlan))
        XCTAssertNil(coordinator.currentPlan)
        XCTAssertTrue(runtime.configuredPlans.isEmpty)
        XCTAssertEqual(runtime.preparedAggregateCount, 2)
        XCTAssertNil(runtime.configuredSeed(for: worldA))
        XCTAssertFalse(runtime.isScheduling(worldA))
        XCTAssertTrue(runtime.isSilenced(worldA))

        runtime.failureStage = nil
        try coordinator.prepare(initialPlan: initialPlan)
        XCTAssertEqual(coordinator.currentPlan, initialPlan)
        XCTAssertEqual(runtime.configuredPlans.map(\.seed), [881])
        XCTAssertEqual(instrumentA.prepareCount, 1)
        XCTAssertEqual(instrumentB.prepareCount, 1)
        XCTAssertEqual(runtime.preparedAggregateCount, 2)
    }

    func testCrossfadeAdvancesEqualPowerGainsAcrossExactlyTwoBars() throws {
        let harness = try makeHarness(initialSeed: 900)
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 901))

        harness.coordinator.render(boundary(position: 16, hostTime: 10))
        assertEqualPower(
            harness.coordinator.metrics.crossfadeState,
            progress: 0,
            oldGain: 1,
            newGain: 0
        )

        harness.coordinator.render(event(.beat, position: 32, hostTime: 12))
        let midpoint = sqrt(0.5)
        assertEqualPower(
            harness.coordinator.metrics.crossfadeState,
            progress: 0.5,
            oldGain: midpoint,
            newGain: midpoint
        )

        harness.coordinator.render(boundary(position: 48, hostTime: 14))
        assertEqualPower(
            harness.coordinator.metrics.crossfadeState,
            progress: 1,
            oldGain: 0,
            newGain: 1
        )
        XCTAssertEqual(harness.banks[0].outputGainMetrics.targetLinearGain, 0, accuracy: 1e-12)
        XCTAssertEqual(harness.banks[1].outputGainMetrics.targetLinearGain, 1, accuracy: 1e-12)
        XCTAssertEqual(harness.coordinator.metrics.crossfadeState!.oldGain * harness.coordinator.metrics.crossfadeState!.oldGain
            + harness.coordinator.metrics.crossfadeState!.newGain * harness.coordinator.metrics.crossfadeState!.newGain, 1, accuracy: 1e-12)

        let oldCommands = harness.banks[0].outputGainAutomationCommands
        let newCommands = harness.banks[1].outputGainAutomationCommands
        XCTAssertEqual(oldCommands.count, 5)
        XCTAssertEqual(newCommands.count, 5)
        assertAutomationPair(oldCommands[0], newCommands[0], progress: 0, start: 10, end: 10)
        assertAutomationPair(
            oldCommands[1],
            newCommands[1],
            progress: 1.0 / 32.0,
            start: 10,
            end: 10 + 15.0 / 72.0
        )
        assertAutomationPair(oldCommands[2], newCommands[2], progress: 0.5, start: 12, end: 12)
        assertAutomationPair(
            oldCommands[3],
            newCommands[3],
            progress: 17.0 / 32.0,
            start: 12,
            end: 12 + 15.0 / 72.0
        )
        assertAutomationPair(oldCommands[4], newCommands[4], progress: 1, start: 14, end: 14)

        for position in 49...80 {
            harness.coordinator.render(event(
                .subdivision,
                position: Int64(position),
                hostTime: 14 + Double(position - 48) * 15.0 / 72.0
            ))
        }
        XCTAssertEqual(harness.banks[0].outputGainAutomationCommands.count, 5)
        XCTAssertEqual(harness.banks[1].outputGainAutomationCommands.count, 5)
    }

    func testTempoRampCrossfadeEndpointsUseTransportEmittedLookaheadAtMidpointAndFinal() async throws {
        let clock = ManualDayObjectsTransportClock()
        let recorder = RemixTransportSubdivisionRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            if event.kind == .subdivision { await recorder.append(event) }
        }

        await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        clock.advance(to: 1.5)
        try await waitForTransport(position: 6, transport: transport)
        await transport.setTempoBPM(100)
        clock.advance(to: 20)
        try await waitForTransport(position: 49, transport: transport)
        await transport.stop()

        let events = await recorder.events
        XCTAssertGreaterThan(events.count, 48)
        let harness = try makeHarness(initialSeed: 902)
        harness.runtime.drained = false
        for event in events where event.position.absoluteSubdivision < 16 {
            harness.coordinator.render(event)
        }
        harness.coordinator.schedule(makePlan(seed: 903))
        for event in events where (16...48).contains(event.position.absoluteSubdivision) {
            harness.coordinator.render(event)
        }

        let oldCommands = harness.banks[0].outputGainAutomationCommands
        let newCommands = harness.banks[1].outputGainAutomationCommands
        XCTAssertEqual(oldCommands.count, 33)
        XCTAssertEqual(newCommands.count, 33)
        XCTAssertEqual(oldCommands[16].requestedEndHostTimeSeconds, events[32].hostTimeSeconds, accuracy: 1e-12)
        XCTAssertEqual(newCommands[16].requestedEndHostTimeSeconds, events[32].hostTimeSeconds, accuracy: 1e-12)
        XCTAssertEqual(oldCommands[32].requestedEndHostTimeSeconds, events[48].hostTimeSeconds, accuracy: 1e-12)
        XCTAssertEqual(newCommands[32].requestedEndHostTimeSeconds, events[48].hostTimeSeconds, accuracy: 1e-12)
        XCTAssertEqual(events[31].nextSubdivisionHostTimeSeconds, events[32].hostTimeSeconds, accuracy: 1e-12)
        XCTAssertEqual(events[47].nextSubdivisionHostTimeSeconds, events[48].hostTimeSeconds, accuracy: 1e-12)
    }

    func testNewestPendingPlanWinsAndPreservesSubmittedDayInput() throws {
        let harness = try makeHarness(initialSeed: 1)
        let planA = makePlan(seed: 2, steps: 1_500, sleep: 2, ids: ["a"], spent: 10)
        let planB = makePlan(seed: 3, steps: 5_000, sleep: 5, ids: ["a", "b"], spent: 40)
        let planC = makePlan(seed: 4, steps: 8_750, sleep: 7.5, ids: ["a", "b", "c"], spent: 73)

        harness.coordinator.schedule(planA)
        harness.coordinator.schedule(planB)
        harness.coordinator.schedule(planC)

        XCTAssertEqual(harness.coordinator.metrics.allocatedBankCount, 2)
        XCTAssertEqual(harness.coordinator.metrics.preparedBankCount, 2)
        XCTAssertEqual(harness.coordinator.metrics.allocatedTonalVoiceCount, 18)
        XCTAssertEqual(harness.coordinator.metrics.allocatedPianoVoiceCount, 12)
        XCTAssertEqual(harness.coordinator.metrics.allocatedDrumPlayerCount, 62)
        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 1)
        XCTAssertEqual(harness.coordinator.pendingPlan, planC)

        harness.coordinator.render(boundary(position: 16, hostTime: 42.25))

        XCTAssertEqual(harness.coordinator.currentPlan, planC)
        XCTAssertEqual(harness.coordinator.currentPlan?.input, planC.input)
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [1, 4])
        XCTAssertFalse(harness.runtime.configuredPlans.contains { $0.seed == 2 || $0.seed == 3 })
        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0)
    }

    func testSleepStructuralChangeWaitsForHarmonicCycleWhileSeedRemixUsesBar() throws {
        let sleepHarness = try makeHarness(initialSeed: 910)
        let sleepUpdate = makePlan(seed: 910, sleep: 8)
        let sleepTarget = DayMusicPlan(
            seed: sleepUpdate.seed,
            input: sleepUpdate.input,
            world: sleepUpdate.world,
            rhythm: sleepUpdate.rhythm,
            groove: sleepUpdate.groove,
            bass: sleepUpdate.bass,
            harmony: .init(
                sleepProgress: sleepUpdate.harmony.sleepProgress,
                cycleBars: sleepUpdate.harmony.cycleBars + 4,
                chordCount: sleepUpdate.harmony.chordCount,
                roles: sleepUpdate.harmony.roles
            ),
            happenings: sleepUpdate.happenings,
            lead: sleepUpdate.lead,
            glitch: sleepUpdate.glitch,
            mix: sleepUpdate.mix
        )
        sleepHarness.coordinator.schedule(sleepTarget)

        sleepHarness.coordinator.render(boundary(position: 16, hostTime: 1))
        XCTAssertEqual(sleepHarness.coordinator.pendingPlan, sleepTarget)
        XCTAssertEqual(sleepHarness.coordinator.currentPlan?.seed, 910)
        XCTAssertEqual(sleepHarness.runtime.configuredPlans.count, 1)

        sleepHarness.coordinator.render(event(
            .subdivision,
            position: Int64(sleepHarness.coordinator.currentPlan!.world.cycleBars)
                * MusicalPosition.subdivisionsPerBar,
            hostTime: 4
        ))
        XCTAssertEqual(sleepHarness.coordinator.currentPlan, sleepTarget)
        XCTAssertEqual(sleepHarness.runtime.configuredPlans.count, 2)

        let remixHarness = try makeHarness(initialSeed: 920)
        remixHarness.coordinator.schedule(makePlan(seed: 921))
        remixHarness.coordinator.render(boundary(position: 16, hostTime: 1))
        XCTAssertEqual(remixHarness.coordinator.currentPlan?.seed, 921)

        let happeningHarness = try makeHarness(initialSeed: 930)
        let happeningTarget = makePlan(seed: 930, ids: ["a", "b", "c"])
        happeningHarness.coordinator.schedule(happeningTarget)
        happeningHarness.coordinator.render(boundary(position: 16, hostTime: 1))
        XCTAssertEqual(happeningHarness.coordinator.currentPlan, happeningTarget)
    }

    func testHappeningHandoffReportsRetainedRemovedAddedAndEveryNewFirstCycleID() throws {
        let harness = try makeHarness(initialSeed: 905)
        harness.coordinator.schedule(makePlan(seed: 906, ids: ["b", "c", "d"]))

        harness.coordinator.render(boundary(position: 16, hostTime: 11))

        XCTAssertEqual(harness.coordinator.metrics.happeningHandoffState, .init(
            retainedAndReplacedIDs: ["b"],
            removedAndCanceledIDs: ["a"],
            addedIDs: ["c", "d"],
            firstCycleScheduledIDs: ["b", "c", "d"]
        ))
    }

    func testBoundaryOperationsHaveExactOrderAndSamePositionIsDeduplicated() throws {
        let harness = try makeHarness(initialSeed: 10)
        harness.runtime.resetLog()
        harness.runtime.compatibility = .safeCommonPitch(64)
        let target = makePlan(seed: 11, ids: ["a", "new"])
        harness.coordinator.schedule(target)

        harness.coordinator.render(event(.subdivision, position: 16, hostTime: 91.125))
        harness.coordinator.render(event(.barBoundary, position: 16, hostTime: 91.125))

        XCTAssertEqual(harness.runtime.log, [
            "stop-attacks@16",
            "release@16",
            "configure:11",
            "rhythm:11@91.125",
            "crossfade:2",
            "happenings:a,b->a,new@16",
            "lead-glide:64",
        ])
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 1)
        XCTAssertEqual(harness.runtime.startedRhythmHostTimes, [91.125])
        XCTAssertEqual(harness.banks.map { $0.outputGainMetrics.rampCount }, [3, 3], "Duplicate event kinds at one transport position must not restart output ramps")
        XCTAssertEqual(harness.banks.map { $0.outputGainAutomationCommands.count }, [2, 2])
    }

    func testOldBankRecyclesOnlyAfterTwoBarsAndRuntimeTailsDrain() throws {
        let harness = try makeHarness(initialSeed: 20)
        harness.runtime.resetLog()
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 21))
        harness.coordinator.render(boundary(position: 16, hostTime: 10))

        harness.coordinator.render(event(.subdivision, position: 47, hostTime: 20))
        XCTAssertEqual(harness.runtime.recycleCount, 0)
        harness.coordinator.render(boundary(position: 48, hostTime: 21))
        XCTAssertEqual(harness.runtime.recycleCount, 0, "Two elapsed bars cannot cut audible tails")

        harness.runtime.drained = true
        harness.coordinator.render(event(.subdivision, position: 49, hostTime: 21.1))
        XCTAssertEqual(harness.runtime.recycleCount, 1)
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0)
    }

    func testRemixDuringTransitionWaitsAndOnlyNewestStartsWhenBankBecomesAvailable() throws {
        let harness = try makeHarness(initialSeed: 30)
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 31))
        harness.coordinator.render(boundary(position: 16, hostTime: 1))
        harness.coordinator.schedule(makePlan(seed: 32))
        harness.coordinator.schedule(makePlan(seed: 33))

        XCTAssertFalse(harness.coordinator.metrics.inactiveBankIsAvailable)

        harness.coordinator.render(boundary(position: 32, hostTime: 2))
        harness.coordinator.render(boundary(position: 48, hostTime: 3))
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [30, 31])
        XCTAssertEqual(harness.coordinator.pendingPlan?.seed, 33)

        harness.runtime.drained = true
        harness.coordinator.render(event(.subdivision, position: 49, hostTime: 3.1))
        XCTAssertTrue(harness.coordinator.metrics.inactiveBankIsAvailable)
        harness.coordinator.render(boundary(position: 64, hostTime: 4))
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [30, 31, 33])
        XCTAssertFalse(harness.runtime.configuredPlans.contains { $0.seed == 32 })
    }

    func testUnsafeHeldLeadUsesOneReleaseRestartPath() throws {
        let harness = try makeHarness(initialSeed: 40)
        harness.runtime.resetLog()
        harness.runtime.compatibility = .requiresRestart
        harness.runtime.leadTokenCount = 1
        harness.coordinator.schedule(makePlan(seed: 41))

        harness.coordinator.render(boundary(position: 16, hostTime: 5))

        XCTAssertEqual(harness.runtime.releaseRestartCount, 1)
        XCTAssertEqual(harness.runtime.glideCount, 0)
        XCTAssertLessThanOrEqual(harness.runtime.metrics.leadTokenCount, 1)
    }

    func testSafeHeldLeadBlocksOldBankRecycleUntilItsTokenIsReleased() throws {
        let harness = try makeHarness(initialSeed: 42)
        harness.runtime.compatibility = .safeCommonPitch(64)
        harness.runtime.leadTokenCount = 1
        harness.runtime.drained = true
        harness.coordinator.schedule(makePlan(seed: 43))
        harness.coordinator.render(boundary(position: 16, hostTime: 5))

        harness.coordinator.render(boundary(position: 48, hostTime: 7))
        XCTAssertEqual(harness.runtime.recycleCount, 0)

        harness.runtime.releaseHeldLead(in: harness.worldBanks[0])
        harness.coordinator.render(event(.subdivision, position: 49, hostTime: 7.1))
        XCTAssertEqual(harness.runtime.recycleCount, 1)
        XCTAssertEqual(harness.runtime.recycleWithHeldTokenViolationCount, 0)
    }

    func testConfigureAndStartFailuresRollbackWithoutClaimingFailedPlanActive() throws {
        for stage in [RecordingRemixRuntime.FailureStage.configure, .startRhythm] {
            let harness = try makeHarness(initialSeed: 50)
            let baseline = harness.coordinator.metrics
            harness.runtime.failureStage = stage
            harness.coordinator.schedule(makePlan(seed: 51))

            harness.coordinator.render(boundary(position: 16, hostTime: 6))

            XCTAssertEqual(harness.coordinator.currentPlan?.seed, 50, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.activeBank, .a, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0, "failed \(stage)")
            XCTAssertEqual(harness.runtime.rollbackCount, 1, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.allocatedBankCount, baseline.allocatedBankCount)
            XCTAssertEqual(harness.coordinator.metrics.runtime, baseline.runtime)
            XCTAssertEqual(harness.runtime.configuredSeed(for: harness.worldBanks[0]), 50)
            XCTAssertTrue(harness.runtime.isScheduling(harness.worldBanks[0]))
            XCTAssertFalse(harness.runtime.isSilenced(harness.worldBanks[0]))
            XCTAssertNil(harness.runtime.configuredSeed(for: harness.worldBanks[1]))
            XCTAssertFalse(harness.runtime.isScheduling(harness.worldBanks[1]))
            XCTAssertTrue(harness.runtime.isSilenced(harness.worldBanks[1]))
            guard case .failed = harness.coordinator.result else {
                return XCTFail("failure must be observable for \(stage)")
            }

            harness.runtime.failureStage = nil
            harness.coordinator.schedule(makePlan(seed: 52))
            harness.coordinator.render(boundary(position: 32, hostTime: 7))
            XCTAssertEqual(harness.coordinator.currentPlan?.seed, 52)
            XCTAssertEqual(harness.coordinator.metrics.activeBank, .b)
        }
    }

    func testStalePositionAndHostTimeCannotConsumePendingPlanAfterRecycle() throws {
        let harness = try makeHarness(initialSeed: 70)
        harness.runtime.drained = true
        harness.coordinator.schedule(makePlan(seed: 71))
        harness.coordinator.render(boundary(position: 16, hostTime: 1))
        harness.coordinator.render(boundary(position: 48, hostTime: 3))
        harness.coordinator.schedule(makePlan(seed: 72))

        harness.coordinator.render(boundary(position: 32, hostTime: 4))
        harness.coordinator.render(boundary(position: 64, hostTime: 2))

        XCTAssertEqual(harness.coordinator.currentPlan?.seed, 71)
        XCTAssertEqual(harness.coordinator.pendingPlan?.seed, 72)
        XCTAssertFalse(harness.runtime.configuredPlans.contains { $0.seed == 72 })

        harness.coordinator.render(boundary(position: 64, hostTime: 5))
        XCTAssertEqual(harness.coordinator.currentPlan?.seed, 72)
    }

    func testStopClearsPendingAndTransitionAndReleasesBothBanks() throws {
        let harness = try makeHarness(initialSeed: 60)
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 61))
        harness.coordinator.render(boundary(position: 16, hostTime: 7))
        harness.coordinator.schedule(makePlan(seed: 62))

        harness.coordinator.stop()

        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0)
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0)
        XCTAssertNil(harness.coordinator.currentPlan)
        XCTAssertEqual(harness.runtime.stopCount, 2)
        XCTAssertEqual(harness.banks.map(\.worldLocalReleaseCount), [1, 1])
        XCTAssertEqual(harness.banks.map(\.sharedInclusiveReleaseCount), [1, 0])
        XCTAssertEqual(harness.sharedHappenings.releaseAllCount, 1)
    }

    func testWholeRuntimeStopClearsAllSharedHappeningContributionsExactlyOnce() throws {
        let harness = try makeHarness(initialSeed: 63)
        let recipes = Array(HappeningSoundCatalog.recipes.prefix(4))
        try harness.sharedHappenings.prepare(recipeIDs: Set(recipes.map(\.id)))
        for (index, recipe) in recipes.enumerated() {
            _ = try harness.sharedHappenings.play(
                resolvedSound(recipe: recipe),
                gain: 0.5,
                priority: .manualAudition,
                effects: .init(
                    filterCutoffHz: 4_000 + Double(index) * 1_000,
                    delayMix: 0.1 + Double(index) * 0.05,
                    delayFeedback: 0.2,
                    reverbMix: 0.25
                )
            )
        }
        XCTAssertEqual(harness.sharedHappenings.metrics.activeVoiceCount, 4)
        XCTAssertNotEqual(harness.sharedHappenings.metrics.effects, RecordingRemixHappeningPool.neutralEffects)

        harness.coordinator.stop()

        XCTAssertEqual(harness.sharedHappenings.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.sharedHappenings.metrics.effects, RecordingRemixHappeningPool.neutralEffects)
        XCTAssertEqual(harness.sharedHappenings.releaseAllCount, 1)
        XCTAssertEqual(harness.banks.map(\.worldLocalReleaseCount), [1, 1])
        XCTAssertEqual(harness.banks.map(\.sharedInclusiveReleaseCount), [1, 0])
    }

    func testRepeatedStopIsNoOpUntilPrepareBeginsANewLifecycleEpoch() throws {
        let harness = try makeHarness(initialSeed: 64)

        harness.coordinator.stop()
        harness.coordinator.stop()
        harness.coordinator.stop()

        XCTAssertEqual(harness.runtime.stopCount, 2)
        XCTAssertEqual(harness.banks.map(\.worldLocalReleaseCount), [1, 1])
        XCTAssertEqual(harness.banks.map(\.sharedInclusiveReleaseCount), [1, 0])
        XCTAssertEqual(harness.sharedHappenings.releaseAllCount, 1)

        try harness.coordinator.prepare(initialPlan: makePlan(seed: 65))
        harness.coordinator.stop()
        harness.coordinator.stop()

        XCTAssertEqual(harness.runtime.stopCount, 4)
        XCTAssertEqual(harness.banks.map(\.worldLocalReleaseCount), [2, 2])
        XCTAssertEqual(harness.banks.map(\.sharedInclusiveReleaseCount), [2, 0])
        XCTAssertEqual(harness.sharedHappenings.releaseAllCount, 2)
    }

    func testFailedReconfigureRetainsActiveEpochCleanupOwnership() throws {
        let harness = try makeHarness(initialSeed: 66)
        harness.runtime.failureStage = .configure

        XCTAssertThrowsError(try harness.coordinator.prepare(initialPlan: makePlan(seed: 67)))
        harness.coordinator.stop()
        harness.coordinator.stop()

        XCTAssertEqual(harness.runtime.stopCount, 2)
        XCTAssertEqual(harness.banks.map(\.worldLocalReleaseCount), [1, 1])
        XCTAssertEqual(harness.banks.map(\.sharedInclusiveReleaseCount), [1, 0])
        XCTAssertEqual(harness.sharedHappenings.releaseAllCount, 1)
    }

    func testOneHundredRemixesKeepBanksPoolsNodesTasksAndTransportConstant() throws {
        let harness = try makeHarness(initialSeed: 100)
        let baseline = harness.coordinator.metrics
        for index in 1...100 {
            let start = Int64(index * 48 - 32)
            harness.runtime.drained = false
            harness.coordinator.schedule(makePlan(seed: UInt64(100 + index)))
            harness.coordinator.render(event(.subdivision, position: start, hostTime: Double(index)))
            harness.runtime.drained = true
            harness.coordinator.render(event(.subdivision, position: start + 32, hostTime: Double(index) + 0.5))
        }

        let final = harness.coordinator.metrics
        XCTAssertEqual(final.allocatedBankCount, 2)
        XCTAssertEqual(final.preparedBankCount, 2)
        XCTAssertEqual(final.allocatedTonalVoiceCount, baseline.allocatedTonalVoiceCount)
        XCTAssertEqual(final.allocatedPianoVoiceCount, baseline.allocatedPianoVoiceCount)
        XCTAssertEqual(final.allocatedDrumPlayerCount, baseline.allocatedDrumPlayerCount)
        XCTAssertEqual(final.runtime.nodeCount, baseline.runtime.nodeCount)
        XCTAssertEqual(final.runtime.poolCount, baseline.runtime.poolCount)
        XCTAssertEqual(final.runtime.taskCount, 0)
        XCTAssertEqual(final.runtime.transportCount, 1)
        XCTAssertEqual(final.runtime.leadTokenCount, 0)
        XCTAssertEqual(final.runtime.happeningTokenCount, 0)
        XCTAssertEqual(harness.banks.map(\.prepareCount), [1, 1])
        XCTAssertEqual(harness.runtime.recycleCount, 100)
        XCTAssertEqual(harness.runtime.oldAttackCountAfterCutoff, 0)
    }

    func testStressEvidenceDetectsOldAttacksIfRuntimeIgnoresCutoff() throws {
        let harness = try makeHarness(initialSeed: 810)
        harness.runtime.ignoreStopAttackScheduling = true
        harness.coordinator.schedule(makePlan(seed: 811))

        harness.coordinator.render(boundary(position: 16, hostTime: 1))

        XCTAssertGreaterThan(harness.runtime.oldAttackCountAfterCutoff, 0)
    }

    private func makeHarness(initialSeed: UInt64) throws -> (
        coordinator: DayObjectsRemixCoordinator,
        runtime: RecordingRemixRuntime,
        banks: [RecordingRemixInstrumentBank],
        worldBanks: [PlaybackWorldBank],
        sharedHappenings: RecordingRemixHappeningPool
    ) {
        let runtime = RecordingRemixRuntime()
        let sharedHappenings = RecordingRemixHappeningPool()
        let bankA = RecordingRemixInstrumentBank(happenings: sharedHappenings)
        let bankB = RecordingRemixInstrumentBank(happenings: sharedHappenings)
        let worldA = PlaybackWorldBank(instrumentBank: bankA)
        let worldB = PlaybackWorldBank(instrumentBank: bankB)
        let coordinator = try DayObjectsRemixCoordinator(
            bankA: worldA,
            bankB: worldB,
            runtime: runtime
        )
        try coordinator.prepare(initialPlan: makePlan(seed: initialSeed))
        return (coordinator, runtime, [bankA, bankB], [worldA, worldB], sharedHappenings)
    }

    private func resolvedSound(recipe: HappeningSoundRecipe) -> ResolvedHappeningSound {
        .init(
            recipeID: recipe.id,
            resourceName: recipe.sources[0].resourceName,
            sourceRootMIDI: recipe.sources[0].rootMIDI,
            targetMIDI: recipe.sources[0].rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )
    }

    private func productionCyclePlan(seed: UInt64) -> DayMusicPlan {
        let base = makePlan(seed: seed)
        let bass = BassPlan(
            mode: .bassPulse,
            instrumentID: .init(rawValue: "bass.analog-boom"),
            register: 29...52,
            articulation: .pulse,
            stepsProgress: 1,
            cutoffMultiplier: 0.88,
            glideMilliseconds: 40,
            reverbSend: 0.05,
            ducking: .init(
                maximumAttenuationDecibels: 5,
                attackSeconds: 0.005,
                holdSeconds: 0.045,
                releaseSeconds: 0.180
            ),
            events: [.init(
                stableID: seed,
                chordIndex: 0,
                startSubdivision: 0,
                durationSubdivisions: 8,
                midiNote: 36,
                velocity: 0.7,
                activationThreshold: 0,
                allowedPitchClasses: [0, 4, 7]
            )]
        )
        return .init(
            seed: base.seed,
            input: base.input,
            world: base.world,
            rhythm: base.rhythm,
            groove: base.groove,
            bass: bass,
            harmony: base.harmony,
            happenings: base.happenings,
            lead: base.lead,
            glitch: base.glitch,
            mix: base.mix
        )
    }

    private func productionEvent(position: Int64) -> DayObjectsTransportEvent {
        .init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: position),
            hostTimeSeconds: Double(position) * 0.001,
            tempoBPM: 72
        )
    }

    private func makePlan(
        seed: UInt64,
        steps: Double = 6_000,
        sleep: Double = 6,
        ids: [String] = ["a", "b"],
        spent: Int = 25
    ) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: steps,
                stepGoal: 10_000,
                countedSleepHours: sleep,
                sleepGoalHours: 8,
                happeningIDs: ids,
                spentColors: spent
            ),
            remixSeed: seed
        )
    }

    private func assertEqualPower(
        _ state: DayObjectsEqualPowerCrossfadeState?,
        progress: Double,
        oldGain: Double,
        newGain: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let state else {
            XCTFail("Missing equal-power crossfade state", file: file, line: line)
            return
        }
        XCTAssertEqual(state.progress, progress, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(state.oldGain, oldGain, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(state.newGain, newGain, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(state.oldGain * state.oldGain + state.newGain * state.newGain, 1, accuracy: 1e-12, file: file, line: line)
    }

    private func assertAutomationPair(
        _ old: DayObjectsBankOutputGainAutomation,
        _ new: DayObjectsBankOutputGainAutomation,
        progress: Double,
        start: TimeInterval,
        end: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let state = DayObjectsEqualPowerCrossfadeState(progress: progress)
        XCTAssertEqual(old.targetLinearGain, state.oldGain, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(new.targetLinearGain, state.newGain, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(old.requestedStartHostTimeSeconds, start, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(new.requestedStartHostTimeSeconds, start, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(old.requestedEndHostTimeSeconds, end, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(new.requestedEndHostTimeSeconds, end, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(old.targetLinearGain * old.targetLinearGain
            + new.targetLinearGain * new.targetLinearGain, 1, accuracy: 1e-12, file: file, line: line)
    }

    private func boundary(position: Int64, hostTime: TimeInterval) -> DayObjectsTransportEvent {
        event(.subdivision, position: position, hostTime: hostTime)
    }

    private func waitForTransport(
        position: Int64,
        transport: DayObjectsTransport,
        maximumYields: Int = 30_000
    ) async throws {
        for _ in 0..<maximumYields {
            if await transport.snapshot.position.absoluteSubdivision >= position { return }
            await Task.yield()
        }
        XCTFail("Transport did not reach subdivision \(position)")
    }

    private func event(
        _ kind: DayObjectsTransportEventKind,
        position: Int64,
        hostTime: TimeInterval
    ) -> DayObjectsTransportEvent {
        .init(
            kind: kind,
            position: .init(absoluteSubdivision: position),
            hostTimeSeconds: hostTime,
            tempoBPM: 72
        )
    }
}

private actor RemixTransportSubdivisionRecorder {
    private(set) var events: [DayObjectsTransportEvent] = []
    func append(_ event: DayObjectsTransportEvent) { events.append(event) }
}

@MainActor
private final class RecordingRemixRuntime: DayObjectsRemixRuntime {
    enum FailureStage: CustomStringConvertible { case configure, startRhythm
        var description: String { self == .configure ? "configure" : "start-rhythm" }
    }

    private final class Aggregate {
        var plan: DayMusicPlan?
        var schedulingEnabled = false
        var isSilenced = true
        var cutoffSubdivision: Int64?
        var leadTokenCount = 0
        var happeningTokenCount = 0
        var scheduledAttackCount = 0
        var activeHappeningIDs: Set<String> = []
    }

    private var aggregates: [ObjectIdentifier: Aggregate] = [:]
    private var preparationOrder: [ObjectIdentifier] = []
    private(set) var configuredPlans: [DayMusicPlan] = []
    private(set) var log: [String] = []
    private(set) var startedRhythmHostTimes: [TimeInterval] = []
    private(set) var recycleCount = 0
    private(set) var rollbackCount = 0
    private(set) var stopCount = 0
    private(set) var glideCount = 0
    private(set) var releaseRestartCount = 0
    private(set) var oldAttackCountAfterCutoff = 0
    private(set) var recycleWithHeldTokenViolationCount = 0
    var drained = true
    var ignoreStopAttackScheduling = false
    var compatibility: DayObjectsRemixLeadCompatibility = .notHeld
    var leadTokenCount: Int {
        get { aggregates.values.reduce(0) { $0 + $1.leadTokenCount } }
        set { mutationAggregate?.leadTokenCount = newValue }
    }
    var happeningTokenCount: Int {
        get { aggregates.values.reduce(0) { $0 + $1.happeningTokenCount } }
        set { mutationAggregate?.happeningTokenCount = newValue }
    }
    var failureStage: FailureStage?

    var metrics: DayObjectsRemixRuntimeMetrics {
        .init(
            nodeCount: aggregates.count * 100,
            poolCount: aggregates.count * 6,
            taskCount: 0,
            transportCount: aggregates.isEmpty ? 0 : 1,
            leadTokenCount: leadTokenCount,
            happeningTokenCount: happeningTokenCount
        )
    }

    func prepare(bank: PlaybackWorldBank) throws {
        let id = ObjectIdentifier(bank)
        guard aggregates[id] == nil else { return }
        aggregates[id] = Aggregate()
        preparationOrder.append(id)
    }

    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws {
        let aggregate = aggregate(for: bank)
        let hasOtherConfiguredBank = aggregates.contains { $0.key != ObjectIdentifier(bank) && $0.value.plan != nil }
        aggregate.plan = plan
        aggregate.activeHappeningIDs = Set(plan.happenings.map(\.happeningID))
        aggregate.isSilenced = hasOtherConfiguredBank
        aggregate.schedulingEnabled = !hasOtherConfiguredBank
        aggregate.cutoffSubdivision = nil
        if failureStage == .configure { throw DayObjectsAudioError("configure") }
        configuredPlans.append(plan)
        log.append("configure:\(plan.seed)")
    }

    func rollbackInitialConfiguration(in bank: PlaybackWorldBank) {
        let aggregate = aggregate(for: bank)
        aggregate.plan = nil
        aggregate.schedulingEnabled = false
        aggregate.isSilenced = true
        aggregate.cutoffSubdivision = nil
        aggregate.leadTokenCount = 0
        aggregate.happeningTokenCount = 0
        aggregate.activeHappeningIDs = []
    }

    func renderTransport(
        _ event: DayObjectsTransportEvent,
        activeBank: PlaybackWorldBank,
        releasingBank: PlaybackWorldBank?
    ) {
        var ids = [ObjectIdentifier(activeBank)]
        if let releasingBank { ids.append(ObjectIdentifier(releasingBank)) }
        for id in Set(ids) {
            guard let aggregate = aggregates[id], aggregate.schedulingEnabled else { continue }
            aggregate.scheduledAttackCount += 1
            if let cutoff = aggregate.cutoffSubdivision,
               event.position.absoluteSubdivision >= cutoff {
                oldAttackCountAfterCutoff += 1
            }
        }
    }

    func stopAttackScheduling(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) {
        let aggregate = aggregate(for: bank)
        aggregate.cutoffSubdivision = event.position.absoluteSubdivision
        if !ignoreStopAttackScheduling { aggregate.schedulingEnabled = false }
        log.append("stop-attacks@\(event.position.absoluteSubdivision)")
    }
    func beginRelease(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) { log.append("release@\(event.position.absoluteSubdivision)") }
    func startRhythm(in bank: PlaybackWorldBank, plan: DayMusicPlan, at event: DayObjectsTransportEvent) throws {
        let aggregate = aggregate(for: bank)
        aggregate.isSilenced = false
        aggregate.schedulingEnabled = true
        if failureStage == .startRhythm { throw DayObjectsAudioError("rhythm") }
        startedRhythmHostTimes.append(event.hostTimeSeconds)
        log.append("rhythm:\(plan.seed)@\(event.hostTimeSeconds)")
    }
    func beginEqualPowerCrossfade(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, plan: DayMusicPlan, startingAt event: DayObjectsTransportEvent, durationBars: Int) { log.append("crossfade:\(durationBars)") }
    func replaceHappeningsAndScheduleFirstCycle(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, oldPlan: DayMusicPlan, newPlan: DayMusicPlan, at event: DayObjectsTransportEvent) throws -> DayObjectsHappeningHandoffState {
        log.append("happenings:\(oldPlan.happenings.map(\.happeningID).joined(separator: ","))->\(newPlan.happenings.map(\.happeningID).joined(separator: ","))@\(event.position.absoluteSubdivision)")
        let oldIDs = Set(oldPlan.happenings.map(\.happeningID))
        let newIDs = Set(newPlan.happenings.map(\.happeningID))
        aggregate(for: newBank).activeHappeningIDs = newIDs
        return .init(
            retainedAndReplacedIDs: oldIDs.intersection(newIDs).sorted(),
            removedAndCanceledIDs: oldIDs.subtracting(newIDs).sorted(),
            addedIDs: newIDs.subtracting(oldIDs).sorted(),
            firstCycleScheduledIDs: newIDs.sorted()
        )
    }
    func leadCompatibility(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, oldPlan: DayMusicPlan, newPlan: DayMusicPlan) -> DayObjectsRemixLeadCompatibility { compatibility }
    func glideHeldLead(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, midiNote: UInt8, newPlan: DayMusicPlan) { glideCount += 1; log.append("lead-glide:\(midiNote)") }
    func releaseAndRestartHeldLead(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, newPlan: DayMusicPlan) {
        releaseRestartCount += 1
        aggregate(for: oldBank).leadTokenCount = 0
        aggregate(for: newBank).leadTokenCount = 1
        log.append("lead-restart")
    }
    func isDrained(_ bank: PlaybackWorldBank) -> Bool {
        let aggregate = aggregate(for: bank)
        return drained && aggregate.leadTokenCount == 0 && aggregate.happeningTokenCount == 0
    }
    func recycle(_ bank: PlaybackWorldBank) {
        recycleCount += 1
        let aggregate = aggregate(for: bank)
        if aggregate.leadTokenCount > 0 { recycleWithHeldTokenViolationCount += 1 }
        aggregate.plan = nil
        aggregate.schedulingEnabled = false
        aggregate.isSilenced = true
        aggregate.cutoffSubdivision = nil
        aggregate.leadTokenCount = 0
        aggregate.happeningTokenCount = 0
        aggregate.activeHappeningIDs = []
        log.append("recycle")
    }
    func rollbackFailedTransition(newBank: PlaybackWorldBank, restoring oldBank: PlaybackWorldBank, currentPlan: DayMusicPlan, at event: DayObjectsTransportEvent) {
        rollbackCount += 1
        let failed = aggregate(for: newBank)
        failed.plan = nil
        failed.schedulingEnabled = false
        failed.isSilenced = true
        failed.cutoffSubdivision = nil
        failed.leadTokenCount = 0
        failed.happeningTokenCount = 0
        failed.activeHappeningIDs = []
        let restored = aggregate(for: oldBank)
        restored.plan = currentPlan
        restored.schedulingEnabled = true
        restored.isSilenced = false
        restored.cutoffSubdivision = nil
        log.append("rollback")
    }
    func stop(_ bank: PlaybackWorldBank) {
        stopCount += 1
        let aggregate = aggregate(for: bank)
        aggregate.schedulingEnabled = false
        aggregate.isSilenced = true
        aggregate.leadTokenCount = 0
        aggregate.happeningTokenCount = 0
    }

    func configuredSeed(for bank: PlaybackWorldBank) -> UInt64? { aggregate(for: bank).plan?.seed }
    func isScheduling(_ bank: PlaybackWorldBank) -> Bool { aggregate(for: bank).schedulingEnabled }
    func isSilenced(_ bank: PlaybackWorldBank) -> Bool { aggregate(for: bank).isSilenced }
    func releaseHeldLead(in bank: PlaybackWorldBank) { aggregate(for: bank).leadTokenCount = 0 }
    var preparedAggregateCount: Int { aggregates.count }

    func resetLog() { log.removeAll(); startedRhythmHostTimes.removeAll() }

    private var mutationAggregate: Aggregate? {
        aggregates.values.first(where: { $0.schedulingEnabled })
            ?? preparationOrder.last.flatMap { aggregates[$0] }
    }

    private func aggregate(for bank: PlaybackWorldBank) -> Aggregate {
        let id = ObjectIdentifier(bank)
        guard let aggregate = aggregates[id] else {
            preconditionFailure("Runtime bank must be prepared before use")
        }
        return aggregate
    }
}

@MainActor
private final class RecordingRemixInstrumentBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    private var configuration: DayObjectsInstrumentBankConfiguration?
    private var pools: [String: RecordingRemixPool] = [:]
    private let drumBank = RecordingRemixDrums()
    private let pianoBank = RecordingRemixPiano()
    private let happeningPool: RecordingRemixHappeningPool
    private(set) var prepareCount = 0
    private(set) var prepareAttemptCount = 0
    private(set) var worldLocalReleaseCount = 0
    private(set) var sharedInclusiveReleaseCount = 0
    var failPrepare = false
    private var outputGainTarget = 1.0
    private var outputGainRampDuration: TimeInterval = 0
    private var outputGainRampCount = 0
    private(set) var outputGainAutomationCommands: [DayObjectsBankOutputGainAutomation] = []

    init(happenings: RecordingRemixHappeningPool? = nil) {
        happeningPool = happenings ?? RecordingRemixHappeningPool()
    }

    var drums: DayObjectsDrumBankProtocol { drumBank }
    var piano: DayObjectsPianoPoolProtocol { pianoBank }
    var happenings: DayObjectsHappeningSamplePoolProtocol { happeningPool }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics {
        .init(
            isSupported: true,
            targetLinearGain: outputGainTarget,
            lastRampDurationSeconds: outputGainRampDuration,
            rampCount: outputGainRampCount,
            lastScheduledAutomation: outputGainAutomationCommands.last
        )
    }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: configuration == nil ? .unprepared : .prepared,
            tonalPoolCount: pools.count,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        guard self.configuration == nil else { return }
        prepareAttemptCount += 1
        if failPrepare { throw DayObjectsAudioError("prepare") }
        prepareCount += 1
        self.configuration = configuration
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingRemixPool(name: $0.name, capacity: $0.capacity))
        })
    }

    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }

    func start() throws {}
    func stop() async { releaseAllIncludingSharedHappenings() }
    func releaseWorldLocalVoices() {
        worldLocalReleaseCount += 1
        pools.values.forEach { $0.releaseAll() }
        drums.releaseAll()
        piano.releaseAll()
    }
    func releaseAllIncludingSharedHappenings() {
        sharedInclusiveReleaseCount += 1
        releaseWorldLocalVoices()
        happenings.releaseAll()
    }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {
        outputGainTarget = linearGain
        outputGainRampDuration = rampDurationSeconds
        outputGainRampCount += 1
    }
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        let command = DayObjectsBankOutputGainAutomation(
            targetLinearGain: linearGain,
            requestedStartHostTimeSeconds: startHostTime,
            requestedEndHostTimeSeconds: endHostTime,
            effectiveStartHostTimeSeconds: startHostTime,
            effectiveEndHostTimeSeconds: endHostTime,
            wasForcedImmediate: startHostTime == endHostTime
        )
        outputGainTarget = linearGain
        outputGainRampDuration = max(endHostTime - startHostTime, 0)
        outputGainRampCount += 1
        outputGainAutomationCommands.append(command)
    }
}

@MainActor
private final class RecordingRemixHappeningPool: DayObjectsHappeningSamplePoolProtocol {
    static let neutralEffects = HappeningEffectCommand(
        filterCutoffHz: 8_000,
        delayMix: 0,
        delayFeedback: 0,
        reverbMix: 0
    )

    private struct ActiveVoice {
        let handle: HappeningPlaybackHandle
        let effects: HappeningEffectCommand
    }

    private var preparedRecipeIDs: Set<HappeningSoundRecipeID> = []
    private var active: [Int: ActiveVoice] = [:]
    private var generation: UInt64 = 0
    private(set) var releaseAllCount = 0

    var metrics: HappeningSamplePoolMetrics {
        .init(
            allocatedPlayerCount: 4,
            fixedPlayerIdentities: [],
            activeVoiceCount: active.count,
            releasingVoiceCount: 0,
            stealCount: 0,
            decodedBufferCount: preparedRecipeIDs.count,
            decodedBufferIdentities: [],
            decodedByteCount: preparedRecipeIDs.count,
            availableRecipeIDs: preparedRecipeIDs,
            unavailableRecipeIDs: [],
            effects: aggregateEffects,
            lastEffectRampSeconds: 0
        )
    }

    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {
        preparedRecipeIDs.formUnion(recipeIDs)
    }

    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand,
        pan: Double
    ) throws -> HappeningPlaybackHandle {
        guard preparedRecipeIDs.contains(sound.recipeID) else {
            throw HappeningSamplePoolError.recipeUnavailable(sound.recipeID)
        }
        guard let voiceID = (0..<4).first(where: { active[$0] == nil }) else {
            throw HappeningSamplePoolError.noEligibleVoice
        }
        generation &+= 1
        let handle = HappeningPlaybackHandle(voiceID: voiceID, generation: generation)
        active[voiceID] = .init(handle: handle, effects: effects)
        return handle
    }

    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {}

    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {}

    func stop(_ handle: HappeningPlaybackHandle) {
        guard active[handle.voiceID]?.handle == handle else { return }
        active[handle.voiceID] = nil
    }

    func releaseAll() {
        releaseAllCount += 1
        active.removeAll()
    }

    private var aggregateEffects: HappeningEffectCommand {
        let commands = active.values.map(\.effects)
        guard commands.isEmpty == false else { return Self.neutralEffects }
        let divisor = Double(commands.count)
        return .init(
            filterCutoffHz: commands.reduce(0) { $0 + $1.filterCutoffHz } / divisor,
            delayMix: commands.reduce(0) { $0 + $1.delayMix } / divisor,
            delayFeedback: commands.reduce(0) { $0 + $1.delayFeedback } / divisor,
            reverbMix: commands.reduce(0) { $0 + $1.reverbMix } / divisor
        )
    }
}

private final class RecordingRemixPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    var metrics: DayObjectsTonalPoolMetrics {
        .init(name: name, allocatedVoiceCount: capacity, allocatedNodeCount: capacity, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0)
    }
    init(name: String, capacity: Int) { self.name = name; self.capacity = capacity }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { nil }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() {}
}

private final class RecordingRemixDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 31, enabledVoiceCount: 9) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingRemixPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 6, activeNoteCount: 0, maximumPolyphony: 6) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {}
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
