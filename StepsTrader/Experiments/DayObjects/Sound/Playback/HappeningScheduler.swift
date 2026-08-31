#if DEBUG || INTERNAL_BUILD
import Foundation

struct HappeningAttackRecord: Equatable, Sendable {
    let happeningID: String
    let position: MusicalPosition
    let midiNote: UInt8
    let family: HappeningSoundFamily
    let instrumentID: DayObjectsInstrumentID
    let isBirth: Bool
}

struct HappeningSchedulerMetrics: Equatable, Sendable {
    let activeHappeningIDs: [String]
    let activeVoiceCount: Int
    let activeVoiceCountByHappeningID: [String: Int]
    let planByHappeningID: [String: HappeningMusicPlan]
    let attackHistory: [HappeningAttackRecord]
    let pendingStructuralReplacementCount: Int
}

@MainActor
final class HappeningScheduler {
    static let maximumRecordedAttackCount = 512
    private struct PendingReplacement {
        let plans: [HappeningMusicPlan]
        let tonalWorld: TonalWorldPlan
        let remixSeed: UInt64
    }

    private static let allocationCycleCount = 16
    private let worldBank: PlaybackWorldBank
    private var happeningPool: DayObjectsTonalVoicePoolProtocol?
    private var states: [String: ActiveHappeningState] = [:]
    private var tonalWorld: TonalWorldPlan?
    private var remixSeed: UInt64 = 0
    private var isPlaying = false
    private var currentPosition = MusicalPosition(absoluteSubdivision: 0)
    private var currentTempoBPM = 120.0
    private var nextVoiceID = 0
    private var attacksPerBeat: [Int64: Int] = [:]
    private var lastGlobalAttackPosition: MusicalPosition?
    private var attackHistory: [HappeningAttackRecord] = []
    private var pendingReplacement: PendingReplacement?
    private var scheduleWindowEndSubdivision: Int64?

    var metrics: HappeningSchedulerMetrics {
        let ids = states.keys.sorted()
        return .init(
            activeHappeningIDs: ids,
            activeVoiceCount: states.values.reduce(0) { $0 + $1.activeVoices.count },
            activeVoiceCountByHappeningID: Dictionary(uniqueKeysWithValues: ids.map {
                ($0, states[$0]?.activeVoices.count ?? 0)
            }),
            planByHappeningID: Dictionary(uniqueKeysWithValues: ids.compactMap { id in
                states[id].map { (id, $0.plan) }
            }),
            attackHistory: attackHistory,
            pendingStructuralReplacementCount: pendingReplacement == nil ? 0 : 1
        )
    }

    init(worldBank: PlaybackWorldBank) {
        self.worldBank = worldBank
    }

    func configure(
        plans: [HappeningMusicPlan],
        tonalWorld: TonalWorldPlan,
        remixSeed: UInt64
    ) throws {
        releaseAllOwnedVoices()
        try worldBank.prepare()
        let pool = try worldBank.tonalPool(named: .happenings)
        let uniquePlans = Self.uniquePlans(plans)
        try pool.prepareInstruments(uniquePlans.map(\.instrumentID))
        happeningPool = pool
        self.tonalWorld = tonalWorld
        self.remixSeed = remixSeed
        states = Dictionary(uniqueKeysWithValues: uniquePlans.map { plan in
            (plan.happeningID, Self.makeState(plan: plan))
        })
        isPlaying = false
        currentPosition = .init(absoluteSubdivision: 0)
        currentTempoBPM = 120
        attacksPerBeat.removeAll(keepingCapacity: true)
        lastGlobalAttackPosition = nil
        attackHistory.removeAll(keepingCapacity: true)
        pendingReplacement = nil
        scheduleWindowEndSubdivision = nil
    }

    func start() throws {
        guard tonalWorld != nil, happeningPool != nil else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        isPlaying = true
        states.keys.forEach { states[$0]?.didPlaySinceStart = false }
        rebuildSchedules(startingAt: currentPosition)
    }

    func stop() {
        isPlaying = false
        pendingReplacement = nil
        releaseAllOwnedVoices()
        for id in states.keys {
            states[id]?.scheduledOccurrences.removeAll(keepingCapacity: true)
            states[id]?.nextOccurrenceIndex = 0
            states[id]?.isBirthPending = false
        }
    }

    func add(
        _ plan: HappeningMusicPlan,
        currentChord _: ChordPlan,
        playBirth: Bool
    ) throws {
        guard states[plan.happeningID] == nil, states.count < 10 else { return }
        guard let happeningPool else { throw DayObjectsInstrumentBankError.notPrepared }
        try happeningPool.prepareInstruments([plan.instrumentID])
        states[plan.happeningID] = Self.makeState(plan: plan)
        guard isPlaying else { return }

        if playBirth {
            states[plan.happeningID]?.isBirthPending = true
        }
        rebuildSchedules(startingAt: currentPosition)
    }

    func remove(id: String) {
        guard let state = states.removeValue(forKey: id) else { return }
        releaseVoices(in: state)
        if isPlaying { rebuildSchedules(startingAt: currentPosition) }
    }

    func scheduleStructuralReplacement(
        plans: [HappeningMusicPlan],
        tonalWorld: TonalWorldPlan,
        remixSeed: UInt64
    ) throws {
        guard happeningPool != nil else { throw DayObjectsInstrumentBankError.notPrepared }
        pendingReplacement = .init(
            plans: Self.uniquePlans(plans),
            tonalWorld: tonalWorld,
            remixSeed: remixSeed
        )
    }

    func render(_ event: DayObjectsTransportEvent, currentChord: ChordPlan) {
        currentPosition = event.position
        currentTempoBPM = event.tempoBPM.isFinite ? max(1, event.tempoBPM) : 120

        if let replacement = pendingReplacement,
           (event.kind == .barBoundary
                || (event.kind == .subdivision && event.position.subdivisionInBar == 0)) {
            applyStructuralReplacement(replacement)
        }
        releaseExpiredVoices(at: event.position)
        guard event.kind == .subdivision, isPlaying else { return }
        while let end = scheduleWindowEndSubdivision,
              event.position.absoluteSubdivision >= end - 1 {
            appendScheduleWindow(startingAt: .init(absoluteSubdivision: end))
            if scheduleWindowEndSubdivision == end { break }
        }

        for id in states.keys.sorted() where states[id]?.isBirthPending == true {
            guard canAttack(at: event.position) else { continue }
            if emitAttack(id: id, chord: currentChord, isBirth: true) {
                states[id]?.isBirthPending = false
            }
        }

        for id in states.keys.sorted() {
            guard var state = states[id] else { continue }
            while state.nextOccurrenceIndex < state.scheduledOccurrences.count,
                  state.scheduledOccurrences[state.nextOccurrenceIndex].position <= event.position {
                let occurrence = state.scheduledOccurrences[state.nextOccurrenceIndex]
                states[id] = state
                guard canAttack(at: event.position),
                      emitAttack(id: id, chord: currentChord, isBirth: false, sequenceIndex: occurrence.sequenceIndex)
                else { break }
                state = states[id] ?? state
                state.nextOccurrenceIndex += 1
                state.nextOccurrence = state.nextOccurrenceIndex < state.scheduledOccurrences.count
                    ? state.scheduledOccurrences[state.nextOccurrenceIndex].position
                    : occurrence.position
            }
            states[id] = state
        }
    }

    private func applyStructuralReplacement(_ replacement: PendingReplacement) {
        guard let happeningPool else { return }
        let oldStates = states
        let newPlans = Self.uniquePlans(replacement.plans)
        do {
            try happeningPool.prepareInstruments(newPlans.map(\.instrumentID))
        } catch {
            return
        }
        var replaced: [String: ActiveHappeningState] = [:]
        for plan in newPlans {
            if let old = oldStates[plan.happeningID] { releaseVoices(in: old) }
            replaced[plan.happeningID] = Self.makeState(plan: plan)
        }
        for (id, old) in oldStates where replaced[id] == nil { releaseVoices(in: old) }
        states = replaced
        tonalWorld = replacement.tonalWorld
        remixSeed = replacement.remixSeed
        pendingReplacement = nil
        rebuildSchedules(startingAt: currentPosition)
    }

    private func rebuildSchedules(startingAt origin: MusicalPosition) {
        for id in states.keys {
            states[id]?.scheduledOccurrences.removeAll(keepingCapacity: true)
            states[id]?.nextOccurrenceIndex = 0
        }
        scheduleWindowEndSubdivision = nil
        appendScheduleWindow(startingAt: origin)
    }

    private func appendScheduleWindow(startingAt origin: MusicalPosition) {
        let allocation = HappeningScheduleAllocator.allocate(
            plans: states.values.map(\.plan),
            remixSeed: remixSeed,
            cycleCount: Self.allocationCycleCount
        )
        guard allocation.horizonBars > 0 else {
            scheduleWindowEndSubdivision = nil
            return
        }
        let eventsByID = Dictionary(grouping: allocation.events, by: \.happeningID)
        for id in states.keys {
            guard var state = states[id] else { continue }
            if state.nextOccurrenceIndex > 0 {
                state.scheduledOccurrences.removeFirst(state.nextOccurrenceIndex)
                state.nextOccurrenceIndex = 0
            }
            let sequenceOffset = (state.scheduledOccurrences.last?.sequenceIndex ?? -1) + 1
            let occurrences = eventsByID[id, default: []].map { event in
                HappeningScheduledOccurrence(
                    sequenceIndex: sequenceOffset + event.sequenceIndex,
                    position: .init(
                        absoluteSubdivision: origin.absoluteSubdivision
                            + Int64((event.startBeat * Double(MusicalPosition.subdivisionsPerBeat)).rounded())
                    ),
                    intervalBars: event.intervalBars
                )
            }
            state.scheduledOccurrences.append(contentsOf: occurrences)
            state.nextOccurrence = state.scheduledOccurrences.first?.position ?? origin
            states[id] = state
        }
        scheduleWindowEndSubdivision = origin.absoluteSubdivision
            + Int64(allocation.horizonBars) * MusicalPosition.subdivisionsPerBar
    }

    @discardableResult
    private func emitAttack(
        id: String,
        chord: ChordPlan,
        isBirth: Bool,
        sequenceIndex: Int = 0
    ) -> Bool {
        guard let pool = happeningPool,
              let world = tonalWorld,
              var state = states[id],
              !state.plan.motifScaleDegrees.isEmpty
        else { return false }
        let motifIndex = isBirth ? 0 : sequenceIndex % state.plan.motifScaleDegrees.count
        guard let note = HappeningPitchResolver.resolve(
            motifScaleDegree: state.plan.motifScaleDegrees[motifIndex],
            octave: state.plan.octave,
            tonalWorld: world,
            chord: chord
        ) else { return false }
        let gain = isBirth ? state.plan.birthGain : state.plan.gain
        guard let token = pool.noteOn(.init(
            instrumentID: state.plan.instrumentID,
            midiNote: note,
            velocity: gain,
            role: .note,
            envelopeVariant: .absolute(
                attackSeconds: state.plan.attackSeconds,
                releaseSeconds: state.plan.releaseSeconds
            ),
            pan: state.plan.pan,
            delaySend: state.plan.delaySend,
            reverbSend: state.plan.reverbSend
        )) else { return false }

        nextVoiceID &+= 1
        let releaseSubdivisions = max(
            1,
            Int64(ceil(state.plan.releaseSeconds * currentTempoBPM / 60 * Double(MusicalPosition.subdivisionsPerBeat)))
        )
        state.activeVoiceIDs.insert(nextVoiceID)
        state.activeVoices[nextVoiceID] = .init(
            pool: pool,
            token: token,
            releaseAt: .init(absoluteSubdivision: currentPosition.absoluteSubdivision + releaseSubdivisions)
        )
        state.didPlaySinceStart = true
        state.lastAttackPosition = currentPosition
        states[id] = state
        attacksPerBeat[currentPosition.absoluteBeat, default: 0] += 1
        lastGlobalAttackPosition = currentPosition
        attackHistory.append(.init(
            happeningID: id,
            position: currentPosition,
            midiNote: note,
            family: state.plan.family,
            instrumentID: state.plan.instrumentID,
            isBirth: isBirth
        ))
        if attackHistory.count > Self.maximumRecordedAttackCount {
            attackHistory.removeFirst(attackHistory.count - Self.maximumRecordedAttackCount)
        }
        return true
    }

    private func canAttack(at position: MusicalPosition) -> Bool {
        guard attacksPerBeat[position.absoluteBeat, default: 0] < 2 else { return false }
        guard let lastGlobalAttackPosition else { return true }
        return position.absoluteSubdivision - lastGlobalAttackPosition.absoluteSubdivision >= 1
    }

    private func releaseExpiredVoices(at position: MusicalPosition) {
        for id in states.keys {
            guard var state = states[id] else { continue }
            let expired = state.activeVoices.filter { $0.value.releaseAt <= position }
            for (voiceID, voice) in expired {
                voice.pool.noteOff(voice.token)
                state.activeVoiceIDs.remove(voiceID)
                state.activeVoices.removeValue(forKey: voiceID)
            }
            states[id] = state
        }
        let oldestRelevantBeat = max(0, position.absoluteBeat - 1)
        attacksPerBeat = attacksPerBeat.filter { $0.key >= oldestRelevantBeat }
    }

    private func releaseVoices(in state: ActiveHappeningState) {
        state.activeVoices.values.forEach { $0.pool.noteOff($0.token) }
    }

    private func releaseAllOwnedVoices() {
        states.values.forEach(releaseVoices)
        for id in states.keys {
            states[id]?.activeVoiceIDs.removeAll(keepingCapacity: true)
            states[id]?.activeVoices.removeAll(keepingCapacity: true)
        }
    }

    private static func makeState(plan: HappeningMusicPlan) -> ActiveHappeningState {
        .init(
            plan: plan,
            nextOccurrence: .init(absoluteSubdivision: 0),
            didPlaySinceStart: false,
            activeVoiceIDs: [],
            scheduledOccurrences: [],
            nextOccurrenceIndex: 0,
            activeVoices: [:],
            lastAttackPosition: nil,
            isBirthPending: false
        )
    }

    private static func uniquePlans(_ plans: [HappeningMusicPlan]) -> [HappeningMusicPlan] {
        var seen: Set<String> = []
        var result: [HappeningMusicPlan] = []
        for plan in plans where seen.insert(plan.happeningID).inserted {
            result.append(plan)
            if result.count == 10 { break }
        }
        return result
    }
}
#endif
