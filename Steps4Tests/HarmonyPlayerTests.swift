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
            .kickSoft: 4, .kickFull: 4, .hatClosed: 6, .hatOpen: 3,
            .shaker: 4, .clapSoft: 3, .stick: 3, .organicHigh: 4, .organicLow: 4,
        ])
        XCTAssertEqual(world.metrics.allocatedTonalVoiceCount, 23)
        XCTAssertEqual(world.metrics.allocatedPianoVoiceCount, 6)
        XCTAssertEqual(world.metrics.allocatedDrumPlayerCount, 35)
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

        harness.player.render(barBoundary: event(.barBoundary, at: 16))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 55, 60])

        harness.player.render(barBoundary: event(.barBoundary, at: 32))
        XCTAssertEqual(harness.primary.noteOnRequests.map(\.midiNote), [48, 55, 60, 50, 57, 62])
        XCTAssertEqual(harness.primary.activeTokenCount, 6, "Old and new chords overlap during the declared crossfade")
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 6)
        XCTAssertEqual(harness.player.metrics.pendingReleaseTokenCount, 3)

        harness.player.render(subdivision: event(.subdivision, at: 48))
        XCTAssertEqual(harness.primary.activeTokenCount, 3)
        XCTAssertEqual(harness.player.metrics.pendingReleaseTokenCount, 0)
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

        harness.player.applyContinuous(updated)
        for subdivision in 1...8 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
        }
        XCTAssertEqual(harness.primary.latestExpression, 0.5, accuracy: 0.000_001)
        for subdivision in 9...16 {
            harness.player.render(subdivision: event(.subdivision, at: Int64(subdivision)))
        }
        XCTAssertEqual(harness.primary.latestExpression, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(harness.player.metrics.activeGainRampCount, 0)
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
        XCTAssertEqual(harness.primary.noteOnRequests.count, 2)

        harness.player.applyContinuous(inactive)
        harness.player.render(subdivision: event(.subdivision, at: 1))
        harness.player.render(barBoundary: event(.barBoundary, at: 16))

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
    func stop() async { releaseAll(); state = .prepared }
    func releaseAll() {
        pools.values.forEach { $0.releaseAll() }
        drumsRecorder.releaseAll()
        pianoRecorder.releaseAll()
    }
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
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var updates: [DayObjectsVoiceUpdate] = []
    private(set) var events: [Event] = []
    private var generation: UInt64 = 0
    private var activeTokens: [DayObjectsVoiceToken: DayObjectsTonalNoteRequest] = [:]

    var latestExpression: Double { updates.compactMap(\.expression).last ?? noteOnRequests.last?.velocity ?? 0 }
    var activeTokenCount: Int { activeTokens.count }
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
        events.append(.init(kind: .prepare, note: nil))
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard request.instrumentID == preparedInstrument else { return nil }
        if activeTokens.count >= capacity, let oldest = activeTokens.keys.first {
            activeTokens.removeValue(forKey: oldest)
        }
        generation += 1
        let token = DayObjectsVoiceToken(slotID: Int(generation % UInt64(max(1, capacity))), generation: generation)
        activeTokens[token] = request
        noteOnRequests.append(request)
        events.append(.init(kind: .noteOn, note: request.midiNote))
        return token
    }

    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {
        guard activeTokens[token] != nil else { return }
        updates.append(update)
        events.append(.init(kind: .update, note: activeTokens[token]?.midiNote))
    }

    func noteOff(_ token: DayObjectsVoiceToken) {
        guard let request = activeTokens.removeValue(forKey: token) else { return }
        events.append(.init(kind: .noteOff, note: request.midiNote))
    }

    func releaseAll() {
        activeTokens.removeAll(keepingCapacity: true)
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
    struct Request: Equatable { let midiNote: UInt8; let velocity: Double }
    var capacity: Int
    private(set) var noteOnRequests: [Request] = []
    private var generation: UInt64 = 0
    private var activeTokens = Set<DayObjectsFeltPianoToken>()

    var activeTokenCount: Int { activeTokens.count }
    var metrics: DayObjectsFeltPianoMetrics {
        .init(allocatedPlayerCount: capacity, activeNoteCount: activeTokens.count, maximumPolyphony: capacity)
    }

    init(capacity: Int) { self.capacity = capacity }

    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? {
        generation += 1
        let token = DayObjectsFeltPianoToken(slotID: Int(generation % UInt64(max(1, capacity))), generation: generation)
        activeTokens.insert(token)
        noteOnRequests.append(.init(midiNote: midiNote, velocity: velocity))
        return token
    }

    func noteOff(_ token: DayObjectsFeltPianoToken) { activeTokens.remove(token) }
    func releaseAll() { activeTokens.removeAll(keepingCapacity: true) }
}
#endif
