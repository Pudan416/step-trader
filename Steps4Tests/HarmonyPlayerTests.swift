#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class HarmonyPlayerTests: XCTestCase {
    func testWorldBankPreallocatesTheExactFixedRoleAndDrumCapacities() throws {
        let bank = RecordingPlaybackInstrumentBank()
        let world = PlaybackWorldBank(instrumentBank: bank)

        try world.prepare()

        XCTAssertEqual(bank.preparedConfigurations, [.playbackWorld])
        XCTAssertEqual(PlaybackWorldBankConfiguration.playbackWorld.tonalPools, [
            .init(name: "drone", capacity: 2, reservesLeadVoice: false),
            .init(name: "primary-pad", capacity: 8, reservesLeadVoice: false),
            .init(name: "secondary-pad-or-keys", capacity: 6, reservesLeadVoice: false),
            .init(name: "happenings", capacity: 6, reservesLeadVoice: false),
            .init(name: "lead", capacity: 1, reservesLeadVoice: true),
        ])
        XCTAssertEqual(PlaybackWorldBankConfiguration.playbackWorld.pianoVoiceCount, 6)
        XCTAssertEqual(PlaybackWorldBankConfiguration.playbackWorld.drumOverlapCounts, [
            .kickSoft: 2, .kickFull: 2, .hatClosed: 6, .hatOpen: 3,
            .shaker: 4, .clapSoft: 3, .stick: 3, .organicHigh: 4, .organicLow: 4,
        ])
        XCTAssertEqual(world.metrics.allocatedTonalVoiceCount, 23)
        XCTAssertEqual(world.metrics.allocatedPianoVoiceCount, 6)
        XCTAssertEqual(world.metrics.allocatedDrumPlayerCount, 31)
    }

    func testInitialAndDeclaredChordChangesUseDirectorVoicingsUnchangedAndCrossfade() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.6,
            schedule: [
                entry(index: 0, startBar: 0, notes: [48, 55, 60]),
                entry(index: 1, startBar: 2, notes: [50, 57, 62]),
            ],
            crossfadeBars: 1
        )
        try harness.player.configure(plan)

        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 55, 60])
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.velocity), [0, 0, 0])

        harness.player.render(subdivision: event(.subdivision, at: 16))
        let chordGain = 0.6 / sqrt(3)
        XCTAssertEqual(harness.primary.expressions(for: [48, 55, 60]), [chordGain, chordGain, chordGain])

        harness.player.render(barBoundary: event(.barBoundary, at: 16))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 55, 60])

        harness.player.render(barBoundary: event(.barBoundary, at: 32))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 55, 60, 50, 57, 62])
        XCTAssertEqual(harness.primary.expressions(for: [48, 55, 60]), [chordGain, chordGain, chordGain])
        XCTAssertEqual(harness.primary.expressions(for: [50, 57, 62]), [0, 0, 0])
        XCTAssertEqual(harness.primary.activeTokenCount, 6, "Old and new chords overlap during the declared crossfade")
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 6)
        XCTAssertEqual(harness.player.metrics.pendingReleaseTokenCount, 3)

        harness.player.render(subdivision: event(.subdivision, at: 40))
        XCTAssertEqual(harness.primary.expressions(for: [48, 55, 60]), [chordGain / 2, chordGain / 2, chordGain / 2])
        XCTAssertEqual(harness.primary.expressions(for: [50, 57, 62]), [chordGain / 2, chordGain / 2, chordGain / 2])

        harness.player.render(subdivision: event(.subdivision, at: 48))
        XCTAssertEqual(harness.primary.activeTokenCount, 3)
        XCTAssertEqual(harness.primary.expressions(for: [50, 57, 62]), [chordGain, chordGain, chordGain])
        XCTAssertEqual(harness.player.metrics.pendingReleaseTokenCount, 0)
    }

    func testCapacityLimitedDroneStagesReplacementWithoutStealingSoundingVoices() throws {
        let harness = try makeHarness()
        let drone = try XCTUnwrap(harness.bank.pools["drone"])
        let plan = harmonyPlan(
            role: .drone,
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.5,
            schedule: [
                entry(index: 0, startBar: 0, notes: [42, 49]),
                entry(index: 1, startBar: 2, notes: [44, 51]),
            ],
            crossfadeBars: 1
        )
        try harness.player.configure(plan)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        harness.player.render(subdivision: event(.subdivision, at: 16))

        harness.player.render(barBoundary: event(.barBoundary, at: 32))
        XCTAssertEqual(drone.noteOnRequests.map(\.midiNote), [42, 49], "A full two-voice pool must not steal before its fade")
        let droneGain = 0.5 / sqrt(2)
        for subdivision in 33..<48 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
            XCTAssertGreaterThan(
                drone.aggregateExpression,
                0,
                "Sequential replacement must keep part of the drone audible at subdivision \(subdivision)"
            )
            XCTAssertEqual(drone.stolenVoiceCount, 0)
        }

        harness.player.render(subdivision: event(.subdivision, at: 48))
        XCTAssertEqual(drone.expressions(for: [44, 51]), [droneGain, droneGain])
        XCTAssertEqual(drone.activeTokenCount, 2)
        XCTAssertEqual(drone.noteOffNotes, [42, 49])
        XCTAssertEqual(drone.noteOnRequests.map(\.midiNote), [42, 49, 44, 51])
    }

    func testFeltPianoCrossfadeUsesTypedRequestsAndContinuousExpression() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            role: .pianoOrKeysAccents,
            target: .feltPiano,
            gain: 0.6,
            schedule: [
                entry(index: 0, startBar: 0, notes: [60, 64, 67]),
                entry(index: 1, startBar: 2, notes: [62, 65, 69]),
            ],
            crossfadeBars: 1
        )
        try harness.player.configure(plan)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        XCTAssertEqual(harness.bank.pianoRecorder.noteOnRequests.map(\.velocity), [0, 0, 0])
        XCTAssertTrue(harness.bank.pianoRecorder.noteOnRequests.allSatisfy {
            $0.attackSeconds == 1 && $0.releaseSeconds == 2 && $0.roomSend == 0.2 && $0.reverbSend == 0.5
        })
        harness.player.render(subdivision: event(.subdivision, at: 16))
        harness.player.render(barBoundary: event(.barBoundary, at: 32))
        XCTAssertEqual(harness.bank.pianoRecorder.activeTokenCount, 6)

        harness.player.render(subdivision: event(.subdivision, at: 40))
        let expectedMidpoint = 0.6 / sqrt(3) / 2
        XCTAssertEqual(harness.bank.pianoRecorder.expressions(for: [60, 64, 67]), [expectedMidpoint, expectedMidpoint, expectedMidpoint])
        XCTAssertEqual(harness.bank.pianoRecorder.expressions(for: [62, 65, 69]), [expectedMidpoint, expectedMidpoint, expectedMidpoint])

        harness.player.render(subdivision: event(.subdivision, at: 48))
        XCTAssertEqual(harness.bank.pianoRecorder.noteOffNotes, [60, 64, 67])
        XCTAssertEqual(harness.bank.pianoRecorder.activeTokenCount, 3)
    }

    func testContinuousUpdateCannotLeakStructuralScheduleOrInstrumentBeforeBoundary() throws {
        let harness = try makeHarness()
        let original = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.3,
            schedule: [
                entry(index: 0, startBar: 0, notes: [48]),
                entry(index: 1, startBar: 2, notes: [52]),
            ]
        )
        let replacementRole = HarmonyRolePlan(
            role: .primaryPad,
            instrumentTarget: .tonal(.init(rawValue: "pad.horizon")),
            register: 60...84,
            gain: 0.7,
            attackSeconds: 0.4,
            releaseSeconds: 0.8,
            delaySend: 0.4,
            reverbSend: 0.7,
            activation: .init(startProgress: 0.8, fullProgress: 0.9, amount: 1),
            chordSchedule: [entry(index: 9, startBar: 1, notes: [77])],
            crossfadeBars: 0.25
        )
        let mixedUpdate = HarmonyPlan(sleepProgress: 0.9, cycleBars: 2, chordCount: 1, roles: [replacementRole])
        try harness.player.configure(original)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))

        harness.player.applyContinuous(mixedUpdate)
        harness.player.render(barBoundary: event(.barBoundary, at: 16))
        harness.player.render(barBoundary: event(.barBoundary, at: 32))

        XCTAssertEqual(harness.primary.preparedInstrument, .init(rawValue: "pad.interstellar"))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 52])
        XCTAssertFalse(harness.primary.noteOnRequests.contains { $0.midiNote == 77 })
    }

    func testTonalChordUsesRoleEnvelopeEffectsAndEqualPowerAttenuation() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.6,
            schedule: [entry(index: 0, startBar: 0, notes: [48, 55, 60])]
        )
        try harness.player.configure(plan)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))

        XCTAssertTrue(harness.primary.noteOnRequests.allSatisfy {
            $0.envelopeVariant == .absolute(attackSeconds: 1, releaseSeconds: 2)
                && $0.delaySend == 0.2
                && $0.reverbSend == 0.5
        })
        harness.player.render(subdivision: event(.subdivision, at: 16))
        let expected = 0.6 / sqrt(3)
        XCTAssertEqual(harness.primary.expressions(for: [48, 55, 60]), [expected, expected, expected])
    }

    func testPadGlitchRoutesSmoothTimeVaryingWowFlutterWithoutRetrigger() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.5,
            schedule: [entry(index: 0, startBar: 0, notes: [48])]
        )
        try harness.player.configure(plan)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        let attackCount = harness.primary.noteOnRequests.count
        let updateStartIndex = harness.primary.updates.endIndex

        harness.player.applyGlitch(.init(
            role: .pad, dryGain: 1, pitchDriftCents: 4,
            wowFlutterDepth: 0.12, stereoSeparationAddition: 0.2,
            delayTimeVariation: 0, saturationAmount: 0,
            timingDriftMilliseconds: 0, dropoutAttenuationDecibels: 0,
            dropoutReleaseSeconds: 0, rampDurationSeconds: 0.25
        ))
        for subdivision: Int64 in [1, 3, 6, 9] {
            harness.player.render(subdivision: event(.subdivision, at: subdivision))
        }

        let centerMIDINote = 48.04
        let pitchUpdates = harness.primary.updates[updateStartIndex...].compactMap(\.midiNote)
        XCTAssertGreaterThan(Set(pitchUpdates.map { ($0 * 1_000_000).rounded() }).count, 2)
        XCTAssertTrue(pitchUpdates.allSatisfy {
            abs($0 - centerMIDINote) <= (0.12 * 0.08) + 0.000_001
        })
        XCTAssertEqual(harness.primary.noteOnRequests.count, attackCount)
        XCTAssertTrue(harness.primary.updates[updateStartIndex...].compactMap(\.pitchRampSeconds).allSatisfy {
            $0 > 0 && $0 <= 0.25
        })
        XCTAssertNotEqual(harness.primary.updates.last?.pan, 0, "stereo separation must reach the tonal backend")
    }

    func testPadWowFlutterIsExactlyNeutralAtZeroGlitch() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.5,
            schedule: [entry(index: 0, startBar: 0, notes: [48])]
        )
        try harness.player.configure(plan)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        harness.player.applyGlitch(.neutral(role: .pad))

        for subdivision: Int64 in [1, 3, 6, 9] {
            harness.player.render(subdivision: event(.subdivision, at: subdivision))
        }

        XCTAssertTrue(harness.primary.updates.compactMap(\.midiNote).allSatisfy { $0 == 48 })
        XCTAssertEqual(harness.primary.noteOnRequests.count, 1)
    }

    func testContinuousRoleGainRampsAcrossExactlyOneBar() throws {
        let harness = try makeHarness()
        let initial = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.2,
            schedule: [entry(index: 0, startBar: 0, notes: [48])]
        )
        let updated = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.8,
            schedule: initial.roles[0].chordSchedule
        )
        try harness.player.configure(initial)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        harness.player.render(subdivision: event(.subdivision, at: 16))

        harness.player.applyContinuous(updated)
        for subdivision in 17...24 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
        }
        XCTAssertEqual(harness.primary.latestExpression, 0.5, accuracy: 0.000_001)
        for subdivision in 25...32 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
        }
        XCTAssertEqual(harness.primary.latestExpression, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(harness.player.metrics.activeGainRampCount, 0)
    }

    func testContinuousPianoUpdateCarriesExpressionAndBothActiveEffectSends() throws {
        let harness = try makeHarness()
        let initial = harmonyPlan(
            role: .pianoOrKeysAccents,
            target: .feltPiano,
            gain: 0.4,
            schedule: [entry(index: 0, startBar: 0, notes: [60, 64])]
        )
        let role = initial.roles[0]
        let updatedRole = HarmonyRolePlan(
            role: role.role,
            instrumentTarget: role.instrumentTarget,
            register: role.register,
            gain: 0.7,
            attackSeconds: role.attackSeconds,
            releaseSeconds: role.releaseSeconds,
            delaySend: 0.65,
            reverbSend: 0.8,
            activation: role.activation,
            chordSchedule: role.chordSchedule,
            crossfadeBars: role.crossfadeBars
        )
        try harness.player.configure(initial)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        harness.player.render(subdivision: event(.subdivision, at: 16))

        harness.player.applyContinuous(.init(
            sleepProgress: 1,
            cycleBars: initial.cycleBars,
            chordCount: initial.chordCount,
            roles: [updatedRole]
        ))
        harness.player.render(subdivision: event(.subdivision, at: 24))

        XCTAssertTrue(harness.bank.pianoRecorder.updates.suffix(2).allSatisfy {
            $0.roomSend == 0.65 && $0.reverbSend == 0.8 && $0.expression == 0.55 / sqrt(2)
        })
    }

    func testDeactivatedRoleReleasesBoundedlyAndNeverStartsAnotherChord() throws {
        let harness = try makeHarness()
        let active = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.5,
            schedule: [
                entry(index: 0, startBar: 0, notes: [48, 55]),
                entry(index: 1, startBar: 1, notes: [50, 57]),
            ]
        )
        let inactive = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0,
            schedule: active.roles[0].chordSchedule
        )
        try harness.player.configure(active)
        harness.player.render(barBoundary: event(.barBoundary, at: 0))
        harness.player.render(subdivision: event(.subdivision, at: 16))
        XCTAssertEqual(harness.primary.noteOnRequests.count, 2)

        harness.player.applyContinuous(inactive)
        for subdivision in 17..<32 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
            XCTAssertGreaterThan(harness.primary.aggregateExpression, 0)
            XCTAssertEqual(harness.primary.activeTokenCount, 2)
        }
        harness.player.render(subdivision: event(.subdivision, at: 32))
        harness.player.render(barBoundary: event(.barBoundary, at: 32))

        XCTAssertEqual(harness.primary.noteOnRequests.count, 2)
        XCTAssertEqual(harness.primary.activeTokenCount, 0)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 0)
    }

    func testFeltPianoTargetRoutesOnlyToSixVoicePianoPool() throws {
        let harness = try makeHarness()
        let plan = harmonyPlan(
            role: .pianoOrKeysAccents,
            target: .feltPiano,
            gain: 0.25,
            schedule: [entry(index: 0, startBar: 0, notes: [60, 64, 67])]
        )
        try harness.player.configure(plan)

        harness.player.render(barBoundary: event(.barBoundary, at: 0))

        XCTAssertEqual(harness.bank.pianoRecorder.noteOnRequests.map(\.midiNote), [60, 64, 67])
        XCTAssertTrue(harness.primary.noteOnRequests.isEmpty)
    }

    func testMaximumSleepInnerMotionRolePreparesAndEmitsSubtleNotes() throws {
        let harness = try makeHarness()
        let directorPlan = DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: 10_000, stepGoal: 10_000,
                countedSleepHours: 8, sleepGoalHours: 8,
                happeningIDs: [], spentColors: 0
            ),
            remixSeed: 91
        )
        let inner = try XCTUnwrap(directorPlan.harmony.role(for: .innerMotion))
        try harness.player.configure(directorPlan.harmony)
        for bar in 0..<directorPlan.harmony.cycleBars {
            let position = Int64(bar) * MusicalPosition.subdivisionsPerBar
            harness.player.render(subdivision: event(.subdivision, at: position))
            harness.player.render(barBoundary: event(.barBoundary, at: position))
        }

        let pool = try XCTUnwrap(harness.bank.pools["secondary-pad-or-keys"])
        guard case let .tonal(instrumentID) = inner.instrumentTarget else {
            return XCTFail("innerMotion must be a tonal role")
        }
        XCTAssertTrue(pool.preparedInstruments.contains(instrumentID))
        let innerRequests = pool.noteOnRequests.filter { $0.instrumentID == instrumentID }
        XCTAssertFalse(innerRequests.isEmpty)
        XCTAssertTrue(innerRequests.allSatisfy { $0.velocity <= inner.gain })
    }

    func testOneThousandChordChangesKeepAllocationConstantAndReleaseEveryToken() throws {
        let harness = try makeHarness()
        let schedule: [HarmonyChordScheduleEntry] = [
            entry(index: 0, startBar: 0, notes: [48, 55, 60]),
            entry(index: 1, startBar: 1, notes: [49, 56, 61]),
            entry(index: 2, startBar: 2, notes: [50, 57, 62]),
            entry(index: 3, startBar: 3, notes: [51, 58, 63]),
        ]
        let plan = harmonyPlan(
            target: .tonal(.init(rawValue: "pad.interstellar")),
            gain: 0.5,
            schedule: schedule,
            crossfadeBars: 1
        )
        try harness.player.configure(plan)
        let baseline = harness.world.metrics

        for bar in 0..<1_000 {
            let position = Int64(bar * 16)
            harness.player.render(subdivision: event(.subdivision, at: position))
            harness.player.render(barBoundary: event(.barBoundary, at: position))
        }
        harness.player.releaseAll()

        XCTAssertEqual(harness.world.metrics.allocatedTonalVoiceCount, baseline.allocatedTonalVoiceCount)
        XCTAssertEqual(harness.world.metrics.allocatedPianoVoiceCount, baseline.allocatedPianoVoiceCount)
        XCTAssertEqual(harness.world.metrics.allocatedDrumPlayerCount, baseline.allocatedDrumPlayerCount)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.player.metrics.pendingReleaseTokenCount, 0)
        XCTAssertEqual(harness.primary.activeTokenCount, 0)
        XCTAssertEqual(harness.bank.pianoRecorder.activeTokenCount, 0)
    }

    private func makeHarness() throws -> HarmonyHarness {
        let bank = RecordingPlaybackInstrumentBank()
        let world = PlaybackWorldBank(instrumentBank: bank)
        try world.prepare()
        let primary = try XCTUnwrap(bank.pools["primary-pad"])
        return HarmonyHarness(
            bank: bank,
            world: world,
            primary: primary,
            player: HarmonyPlayer(worldBank: world)
        )
    }

    private func harmonyPlan(
        role: HarmonyRole = .primaryPad,
        target: HarmonyInstrumentTarget,
        gain: Double,
        schedule: [HarmonyChordScheduleEntry],
        crossfadeBars: Double = 1
    ) -> HarmonyPlan {
        .init(
            sleepProgress: gain > 0 ? 1 : 0,
            cycleBars: 4,
            chordCount: schedule.count,
            roles: [
                .init(
                    role: role,
                    instrumentTarget: target,
                    register: 36...84,
                    gain: gain,
                    attackSeconds: 1,
                    releaseSeconds: 2,
                    delaySend: 0.2,
                    reverbSend: 0.5,
                    activation: .init(startProgress: 0, fullProgress: 1, amount: gain > 0 ? 1 : 0),
                    chordSchedule: schedule,
                    crossfadeBars: crossfadeBars
                ),
            ]
        )
    }

    private func entry(index: Int, startBar: Int, notes: [UInt8]) -> HarmonyChordScheduleEntry {
        .init(
            chordIndex: index,
            startBar: startBar,
            durationBars: 1,
            rootPitchClass: Int(notes[0]) % 12,
            chordPitchClasses: notes.map { Int($0) % 12 },
            safePassingPitchClasses: notes.map { Int($0) % 12 },
            voicedMIDINotes: notes
        )
    }

    private func event(
        _ kind: DayObjectsTransportEventKind,
        at absoluteSubdivision: Int64
    ) -> DayObjectsTransportEvent {
        .init(
            kind: kind,
            position: .init(absoluteSubdivision: absoluteSubdivision),
            hostTimeSeconds: Double(absoluteSubdivision) / 4,
            tempoBPM: 60
        )
    }
}

@MainActor
private struct HarmonyHarness {
    let bank: RecordingPlaybackInstrumentBank
    let world: PlaybackWorldBank
    let primary: RecordingHarmonyTonalPool
    let player: HarmonyPlayer
}

@MainActor
private final class RecordingPlaybackInstrumentBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    let drumsRecorder = RecordingHarmonyDrumBank()
    let pianoRecorder = RecordingHarmonyPianoPool(capacity: 6)
    private(set) var preparedConfigurations: [DayObjectsInstrumentBankConfiguration] = []
    private(set) var pools: [String: RecordingHarmonyTonalPool] = [:]
    private var state: DayObjectsInstrumentBankState = .unprepared

    var drums: DayObjectsDrumBankProtocol { drumsRecorder }
    var piano: DayObjectsPianoPoolProtocol { pianoRecorder }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: state,
            tonalPoolCount: pools.count,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drumsRecorder.metrics,
            pianoMetrics: pianoRecorder.metrics
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        preparedConfigurations.append(configuration)
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingHarmonyTonalPool(name: $0.name, capacity: $0.capacity))
        })
        drumsRecorder.allocatedPlayerCount = configuration.drumOverlapCounts.values.reduce(0, +)
        pianoRecorder.capacity = configuration.pianoVoiceCount
        state = .prepared
    }

    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }

    func start() throws { state = .started }
    func stop() async { releaseAllIncludingSharedHappenings(); state = .prepared }
    func releaseWorldLocalVoices() {
        pools.values.forEach { $0.releaseAll() }
        drumsRecorder.releaseAll()
        pianoRecorder.releaseAll()
    }
    func releaseAllIncludingSharedHappenings() { releaseWorldLocalVoices() }
}

private final class RecordingHarmonyTonalPool: DayObjectsTonalVoicePoolProtocol {
    struct Event: Equatable {
        enum Kind: Equatable { case prepare, noteOn, update, noteOff, releaseAll }
        let kind: Kind
        let note: UInt8?
    }

    let name: String
    let capacity: Int
    private(set) var preparedInstrument: DayObjectsInstrumentID?
    private(set) var preparedInstruments: Set<DayObjectsInstrumentID> = []
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var updates: [DayObjectsVoiceUpdate] = []
    private(set) var events: [Event] = []
    private var generation: UInt64 = 0
    private var activeTokens: [DayObjectsVoiceToken: DayObjectsTonalNoteRequest] = [:]
    private var expressionByToken: [DayObjectsVoiceToken: Double] = [:]
    private(set) var stolenVoiceCount = 0

    var latestExpression: Double { updates.compactMap(\.expression).last ?? noteOnRequests.last?.velocity ?? 0 }
    var aggregateExpression: Double { expressionByToken.values.reduce(0, +) }
    var activeTokenCount: Int { activeTokens.count }
    var noteOffNotes: [UInt8] { events.compactMap { $0.kind == .noteOff ? $0.note : nil } }
    func expressions(for notes: [UInt8]) -> [Double] {
        notes.map { note in
            guard let token = activeTokens.first(where: { $0.value.midiNote == note })?.key else { return -1 }
            return expressionByToken[token] ?? activeTokens[token]?.velocity ?? -1
        }
    }
    var metrics: DayObjectsTonalPoolMetrics {
        .init(
            name: name,
            allocatedVoiceCount: capacity,
            allocatedNodeCount: capacity,
            activeVoiceCount: activeTokens.count,
            activeLeadVoiceCount: activeTokens.values.filter { $0.role == .lead }.count,
            activeChordVoiceCount: activeTokens.values.filter { $0.role == .chord }.count
        )
    }

    init(name: String, capacity: Int) {
        self.name = name
        self.capacity = capacity
    }

    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {
        XCTAssertTrue(activeTokens.isEmpty, "A sounding pool must not be represet in place")
        preparedInstrument = id
        preparedInstruments.insert(id)
        events.append(.init(kind: .prepare, note: nil))
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard preparedInstruments.contains(request.instrumentID) else { return nil }
        if activeTokens.count >= capacity, let oldest = activeTokens.keys.first {
            activeTokens.removeValue(forKey: oldest)
            expressionByToken.removeValue(forKey: oldest)
            stolenVoiceCount += 1
        }
        generation += 1
        let token = DayObjectsVoiceToken(slotID: Int(generation % UInt64(max(1, capacity))), generation: generation)
        activeTokens[token] = request
        expressionByToken[token] = request.velocity
        noteOnRequests.append(request)
        events.append(.init(kind: .noteOn, note: request.midiNote))
        return token
    }

    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {
        guard activeTokens[token] != nil else { return }
        updates.append(update)
        if let expression = update.expression { expressionByToken[token] = expression }
        events.append(.init(kind: .update, note: activeTokens[token]?.midiNote))
    }

    func noteOff(_ token: DayObjectsVoiceToken) {
        guard let request = activeTokens.removeValue(forKey: token) else { return }
        expressionByToken.removeValue(forKey: token)
        events.append(.init(kind: .noteOff, note: request.midiNote))
    }

    func releaseAll() {
        activeTokens.removeAll(keepingCapacity: true)
        expressionByToken.removeAll(keepingCapacity: true)
        events.append(.init(kind: .releaseAll, note: nil))
    }
}

private final class RecordingHarmonyDrumBank: DayObjectsDrumBankProtocol {
    var allocatedPlayerCount = 0
    var metrics: DayObjectsDrumBankMetrics {
        .init(allocatedPlayerCount: allocatedPlayerCount, enabledVoiceCount: DayObjectsDrumVoice.allCases.count)
    }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingHarmonyPianoPool: DayObjectsPianoPoolProtocol {
    var capacity: Int
    private(set) var noteOnRequests: [DayObjectsPianoNoteRequest] = []
    private(set) var noteOffNotes: [UInt8] = []
    private(set) var updates: [DayObjectsPianoVoiceUpdate] = []
    private var generation: UInt64 = 0
    private var activeTokens: [DayObjectsFeltPianoToken: DayObjectsPianoNoteRequest] = [:]
    private var expressionByToken: [DayObjectsFeltPianoToken: Double] = [:]

    var activeTokenCount: Int { activeTokens.count }
    func expressions(for notes: [UInt8]) -> [Double] {
        notes.map { note in
            guard let token = activeTokens.first(where: { $0.value.midiNote == note })?.key else { return -1 }
            return expressionByToken[token] ?? -1
        }
    }
    var metrics: DayObjectsFeltPianoMetrics {
        .init(allocatedPlayerCount: capacity, activeNoteCount: activeTokens.count, maximumPolyphony: capacity)
    }

    init(capacity: Int) { self.capacity = capacity }

    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? {
        noteOn(.init(
            midiNote: midiNote,
            velocity: velocity,
            attackSeconds: 0.012,
            releaseSeconds: 0.42,
            roomSend: 0.16,
            reverbSend: 0.12
        ))
    }

    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken? {
        generation += 1
        let token = DayObjectsFeltPianoToken(slotID: Int(generation % UInt64(max(1, capacity))), generation: generation)
        activeTokens[token] = request
        expressionByToken[token] = request.velocity
        noteOnRequests.append(request)
        return token
    }

    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {
        guard activeTokens[token] != nil else { return }
        expressionByToken[token] = expression
    }
    func update(_ token: DayObjectsFeltPianoToken, with update: DayObjectsPianoVoiceUpdate) {
        guard activeTokens[token] != nil else { return }
        updates.append(update)
        if let expression = update.expression { expressionByToken[token] = expression }
    }
    func noteOff(_ token: DayObjectsFeltPianoToken) {
        if let request = activeTokens.removeValue(forKey: token) { noteOffNotes.append(request.midiNote) }
        expressionByToken.removeValue(forKey: token)
    }
    func releaseAll() {
        activeTokens.removeAll(keepingCapacity: true)
        expressionByToken.removeAll(keepingCapacity: true)
    }
}
#endif
