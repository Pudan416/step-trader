#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsTonalPoolSpecification: Equatable, Sendable {
    static let manualAudition = DayObjectsTonalPoolSpecification(
        name: "audition",
        capacity: DayObjectsAudioParameters.defaultAuditionVoiceCapacity,
        reservesLeadVoice: true
    )

    let name: String
    let capacity: Int
    let reservesLeadVoice: Bool

    init(name: String, capacity: Int, reservesLeadVoice: Bool) {
        precondition(!name.isEmpty, "A tonal pool requires a stable name")
        precondition(capacity > 0, "A tonal pool requires at least one voice")
        self.name = name
        self.capacity = capacity
        self.reservesLeadVoice = reservesLeadVoice
    }
}

struct DayObjectsVoiceToken: Hashable, Sendable {
    fileprivate let poolID: UUID
    fileprivate let slotID: Int
    fileprivate let generation: UInt64

    /// Internal test and adapter construction; production tokens remain
    /// allocated exclusively by the tonal pool.
    init(poolID: UUID = UUID(), slotID: Int = 0, generation: UInt64 = 1) {
        self.poolID = poolID
        self.slotID = slotID
        self.generation = generation
    }
}

struct DayObjectsTonalPoolMetrics: Equatable, Sendable {
    let name: String
    let allocatedVoiceCount: Int
    let allocatedNodeCount: Int
    let activeVoiceCount: Int
    let activeLeadVoiceCount: Int
    let activeChordVoiceCount: Int
    let releasingVoiceCount: Int
    let occupiedVoiceCount: Int

    init(
        name: String,
        allocatedVoiceCount: Int,
        allocatedNodeCount: Int,
        activeVoiceCount: Int,
        activeLeadVoiceCount: Int,
        activeChordVoiceCount: Int,
        releasingVoiceCount: Int = 0,
        occupiedVoiceCount: Int? = nil
    ) {
        self.name = name
        self.allocatedVoiceCount = allocatedVoiceCount
        self.allocatedNodeCount = allocatedNodeCount
        self.activeVoiceCount = activeVoiceCount
        self.activeLeadVoiceCount = activeLeadVoiceCount
        self.activeChordVoiceCount = activeChordVoiceCount
        self.releasingVoiceCount = releasingVoiceCount
        self.occupiedVoiceCount = occupiedVoiceCount ?? activeVoiceCount + releasingVoiceCount
    }
}

protocol DayObjectsTonalVoiceBackend: AnyObject {
    var allocatedNodeCount: Int { get }

    func replacePreset(
        _ preset: NormalizedSynthVoice,
        instrumentID: DayObjectsInstrumentID,
        transitionDuration: TimeInterval
    )
    func noteOn(_ request: DayObjectsTonalNoteRequest)
    func update(_ update: DayObjectsVoiceUpdate)
    func noteOff()
    func noteOff(releaseSeconds: TimeInterval?)
}

extension DayObjectsTonalVoiceBackend {
    func noteOff(releaseSeconds: TimeInterval?) { noteOff() }
}

final class DayObjectsTonalVoicePool {
    typealias InstrumentProvider = (DayObjectsInstrumentID) throws -> NormalizedSynthVoice
    typealias VoiceFactory = () -> any DayObjectsTonalVoiceBackend
    typealias MonotonicTime = () -> TimeInterval

    let specification: DayObjectsTonalPoolSpecification

    var metrics: DayObjectsTonalPoolMetrics {
        let now = monotonicTime()
        let releasingCount = slots.reduce(0) { partial, slot in
            partial + ((slot.releasingUntil ?? 0) > now ? 1 : 0)
        }
        let activeCount = slots.reduce(0) { $0 + ($1.role == nil ? 0 : 1) }
        return DayObjectsTonalPoolMetrics(
            name: specification.name,
            allocatedVoiceCount: slots.count,
            allocatedNodeCount: slots.reduce(0) { $0 + $1.backend.allocatedNodeCount },
            activeVoiceCount: activeCount,
            activeLeadVoiceCount: slots.reduce(0) { $0 + ($1.role == .lead ? 1 : 0) },
            activeChordVoiceCount: slots.reduce(0) { $0 + ($1.role == .chord ? 1 : 0) },
            releasingVoiceCount: releasingCount,
            occupiedVoiceCount: activeCount + releasingCount
        )
    }

    private struct Slot {
        let backend: any DayObjectsTonalVoiceBackend
        var generation: UInt64 = 0
        var activationOrder: UInt64 = 0
        var role: DayObjectsTonalVoiceRole?
        var midiNote = 60.0
        var releaseSeconds: TimeInterval?
        var instrumentID: DayObjectsInstrumentID?
        var releasingUntil: TimeInterval?
    }

    private let poolID = UUID()
    private let instrumentProvider: InstrumentProvider
    private let monotonicTime: MonotonicTime
    private var slots: [Slot]
    private var preparedInstrumentID: DayObjectsInstrumentID?
    private var preparedInstrumentPresets: [DayObjectsInstrumentID: NormalizedSynthVoice] = [:]
    private var preservesPreparedSetTails = false
    private var activationCounter: UInt64 = 0

    init(
        specification: DayObjectsTonalPoolSpecification = .manualAudition,
        instrumentProvider: @escaping InstrumentProvider,
        voiceFactory: VoiceFactory,
        monotonicTime: @escaping MonotonicTime = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.specification = specification
        self.instrumentProvider = instrumentProvider
        self.monotonicTime = monotonicTime
        slots = (0..<specification.capacity).map { _ in Slot(backend: voiceFactory()) }
    }

    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {
        guard preparedInstrumentID != id || preparedInstrumentPresets.count != 1 else { return }
        let preset = DayObjectsAudioParameters.clamped(try instrumentProvider(id))

        releaseAll(preservingTails: false)
        for slotID in slots.indices {
            slots[slotID].backend.replacePreset(
                preset,
                instrumentID: id,
                transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
            )
            slots[slotID].instrumentID = id
        }
        preparedInstrumentID = id
        preparedInstrumentPresets = [id: preset]
        preservesPreparedSetTails = false
    }

    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws {
        for id in ids where preparedInstrumentPresets[id] == nil {
            preparedInstrumentPresets[id] = DayObjectsAudioParameters.clamped(try instrumentProvider(id))
        }
        preservesPreparedSetTails = true
    }

    func noteOn(_ rawRequest: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard let preset = preparedInstrumentPresets[rawRequest.instrumentID] else { return nil }
        let request = DayObjectsAudioParameters.clamped(rawRequest)
        let now = monotonicTime()
        guard let slotID = slotForAllocation(
            role: request.role,
            allowsStealing: !preservesPreparedSetTails,
            at: now
        ) else { return nil }

        if slots[slotID].role != nil {
            release(slotID: slotID)
        }
        if slots[slotID].instrumentID != request.instrumentID {
            slots[slotID].backend.replacePreset(
                preset,
                instrumentID: request.instrumentID,
                transitionDuration: 0
            )
            slots[slotID].instrumentID = request.instrumentID
        }

        activationCounter &+= 1
        slots[slotID].generation &+= 1
        slots[slotID].activationOrder = activationCounter
        slots[slotID].role = request.role
        slots[slotID].releasingUntil = nil
        slots[slotID].midiNote = Double(request.midiNote)
        slots[slotID].releaseSeconds = request.envelopeVariant?.absoluteReleaseSeconds
        slots[slotID].backend.noteOn(request)

        return DayObjectsVoiceToken(
            poolID: poolID,
            slotID: slotID,
            generation: slots[slotID].generation
        )
    }

    func update(_ token: DayObjectsVoiceToken, with rawUpdate: DayObjectsVoiceUpdate) {
        guard let slotID = activeSlotID(for: token) else { return }
        let update = DayObjectsAudioParameters.clamped(
            rawUpdate,
            fallbackMIDINote: slots[slotID].midiNote
        )
        if let midiNote = update.midiNote {
            slots[slotID].midiNote = midiNote
        }
        slots[slotID].backend.update(update)
    }

    func noteOff(_ token: DayObjectsVoiceToken) {
        guard let slotID = activeSlotID(for: token) else { return }
        release(slotID: slotID)
    }

    func releaseAll() {
        releaseAll(preservingTails: preservesPreparedSetTails)
    }

    private func releaseAll(preservingTails: Bool) {
        for slotID in slots.indices where slots[slotID].role != nil {
            release(slotID: slotID, preservingTail: preservingTails)
        }
    }

    private func slotForAllocation(
        role: DayObjectsTonalVoiceRole,
        allowsStealing: Bool = true,
        at now: TimeInterval
    ) -> Int? {
        if role == .lead {
            if let currentLead = slots.firstIndex(where: { $0.role == .lead }) {
                return currentLead
            }
            return slots.firstIndex(where: { isAllocatable($0, at: now) })
                ?? (allowsStealing ? oldestNonLeadSlotID() : nil)
        }

        if role == .chord, metrics.activeChordVoiceCount >= DayObjectsAudioParameters.maximumChordVoiceCount {
            return nil
        }

        let reservedCount = specification.reservesLeadVoice ? 1 : 0
        let nonLeadLimit = max(0, specification.capacity - reservedCount)
        let activeNonLeadCount = slots.reduce(0) { partial, slot in
            partial + (slot.role != nil && slot.role != .lead ? 1 : 0)
        }
        if activeNonLeadCount >= nonLeadLimit {
            return allowsStealing ? oldestNonLeadSlotID() : nil
        }
        return slots.firstIndex(where: { isAllocatable($0, at: now) })
            ?? (allowsStealing ? oldestNonLeadSlotID() : nil)
    }

    private func isAllocatable(_ slot: Slot, at now: TimeInterval) -> Bool {
        slot.role == nil && (slot.releasingUntil ?? 0) <= now
    }

    private func oldestNonLeadSlotID() -> Int? {
        var oldest: (slotID: Int, order: UInt64)?
        for slotID in slots.indices {
            guard let role = slots[slotID].role, role != .lead else { continue }
            if oldest == nil || slots[slotID].activationOrder < oldest!.order {
                oldest = (slotID, slots[slotID].activationOrder)
            }
        }
        return oldest?.slotID
    }

    private func activeSlotID(for token: DayObjectsVoiceToken) -> Int? {
        guard token.poolID == poolID, slots.indices.contains(token.slotID) else { return nil }
        let slot = slots[token.slotID]
        guard slot.role != nil, slot.generation == token.generation else { return nil }
        return token.slotID
    }

    private func release(slotID: Int, preservingTail: Bool? = nil) {
        guard slots[slotID].role != nil else { return }
        let releaseSeconds = slots[slotID].releaseSeconds
        slots[slotID].backend.noteOff(releaseSeconds: releaseSeconds)
        slots[slotID].role = nil
        slots[slotID].releaseSeconds = nil
        let shouldPreserveTail = preservingTail ?? preservesPreparedSetTails
        if shouldPreserveTail, let releaseSeconds, releaseSeconds > 0 {
            slots[slotID].releasingUntil = monotonicTime() + releaseSeconds
        } else {
            slots[slotID].releasingUntil = nil
        }
    }
}
#endif
