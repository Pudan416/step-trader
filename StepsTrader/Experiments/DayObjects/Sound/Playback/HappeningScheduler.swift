import Foundation

struct HappeningAttackRecord: Equatable, Sendable {
    let happeningID: String
    let position: MusicalPosition
    let resolvedSound: ResolvedHappeningSound
    let effectCommand: HappeningEffectCommand
    let playbackPriority: HappeningPlaybackPriority
    let isBirth: Bool
}

struct HappeningSchedulerMetrics: Equatable, Sendable {
    let activeHappeningIDs: [String]
    let activeVoiceCount: Int
    let activeVoiceCountByHappeningID: [String: Int]
    let planByHappeningID: [String: HappeningMusicPlan]
    let attackHistory: [HappeningAttackRecord]
    let pendingStructuralReplacementCount: Int
    let nextOccurrenceByHappeningID: [String: MusicalPosition]
    let scheduledOccurrencesByHappeningID: [String: [MusicalPosition]]
}

@MainActor
final class HappeningScheduler {
    static let maximumRecordedAttackCount = 512
    var onAttack: ((HappeningAttackRecord) -> Void)?

    private struct PendingReplacement {
        let plans: [HappeningMusicPlan]
        let tonalWorld: TonalWorldPlan
        let remixSeed: UInt64
    }

    private static let allocationCycleCount = 16
    private static let maximumAdmissionRetryAttempts = 4
    private static let admissionRetrySpacingSubdivisions: Int64 = MusicalPosition.subdivisionsPerBeat
    private static let admissionRetryHorizonSubdivisions: Int64 = MusicalPosition.subdivisionsPerBar
    private static let birthRetryRearmSubdivisions: Int64 = MusicalPosition.subdivisionsPerBar
    private let worldBank: PlaybackWorldBank
    private var happeningPool: DayObjectsHappeningSamplePoolProtocol?
    private var reverbSendScale = 1.0
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
    private var mixGain = 1.0
    private var glitchCommand: DayObjectsGlitchCommand = .neutral(role: .happening)
    private var glitchPlan: GlitchPlan = .neutral
    private weak var glitchProcessor: GlitchProcessor?

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
            pendingStructuralReplacementCount: pendingReplacement == nil ? 0 : 1,
            nextOccurrenceByHappeningID: Dictionary(uniqueKeysWithValues: ids.map {
                ($0, states[$0]?.nextOccurrence ?? currentPosition)
            }),
            scheduledOccurrencesByHappeningID: Dictionary(uniqueKeysWithValues: ids.map {
                ($0, states[$0]?.scheduledOccurrences.map(\.position) ?? [])
            })
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
        reverbSendScale = 1
        try worldBank.prepare()
        let pool = worldBank.happenings
        let requestedPlans = Self.uniquePlans(plans)
        try pool.prepare(recipeIDs: Set(requestedPlans.map(\.recipeID)))
        let uniquePlans = requestedPlans.filter { pool.metrics.availableRecipeIDs.contains($0.recipeID) }
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

    func start(playInitialBirths: Bool = false) throws {
        try start(at: currentPosition, playInitialBirths: playInitialBirths)
    }

    func start(
        at position: MusicalPosition,
        playInitialBirths: Bool = false
    ) throws {
        guard tonalWorld != nil, happeningPool != nil else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        currentPosition = position
        isPlaying = true
        let initialBirthID = playInitialBirths ? states.keys.sorted().first : nil
        for id in states.keys {
            states[id]?.didPlaySinceStart = false
            states[id]?.isBirthPending = id == initialBirthID
            guard id == initialBirthID else { continue }
            states[id]?.birthRetryAttemptCount = 0
            states[id]?.birthNextRetryPosition = position
            states[id]?.birthRetryDeadline = .init(
                absoluteSubdivision: position.absoluteSubdivision
                    + Self.admissionRetryHorizonSubdivisions
            )
        }
        rebuildSchedules(startingAt: position)
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
        currentChord: ChordPlan,
        playBirth: Bool
    ) throws {
        guard states[plan.happeningID] == nil, states.count < 10 else { return }
        guard let happeningPool else { throw DayObjectsInstrumentBankError.notPrepared }
        try happeningPool.prepare(recipeIDs: [plan.recipeID])
        guard happeningPool.metrics.availableRecipeIDs.contains(plan.recipeID) else { return }
        states[plan.happeningID] = Self.makeState(plan: plan)
        guard isPlaying else { return }

        if playBirth {
            states[plan.happeningID]?.isBirthPending = true
            states[plan.happeningID]?.birthNextRetryPosition = currentPosition
            states[plan.happeningID]?.birthRetryDeadline = .init(
                absoluteSubdivision: currentPosition.absoluteSubdivision
                    + Self.admissionRetryHorizonSubdivisions
            )
            attemptPendingBirth(id: plan.happeningID, chord: currentChord)
        }
        rebuildSchedules(startingAt: currentPosition)
    }

    func remove(id: String) {
        guard let state = states.removeValue(forKey: id) else { return }
        releaseVoices(in: state)
        if isPlaying { rebuildSchedules(startingAt: currentPosition) }
    }

    func applyMixTargetDecibels(_ decibels: Double) {
        mixGain = decibels.isFinite
            ? pow(10, min(max(decibels, -60), 0) / 20)
            : 0
        updateActiveVoices()
    }

    func applyReverbSendScale(_ value: Double) {
        let scale = DayObjectsWorldGroupCalibration(reverbSendScale: value).reverbSendScale
        guard scale != reverbSendScale else { return }
        reverbSendScale = scale
        for state in states.values {
            for voice in state.activeVoices.values {
                voice.pool.updateReverbSend(voice.handle, sendLevel: state.plan.reverbSend * scale, rampSeconds: 0.25)
            }
        }
    }

    func applyGlitch(_ command: DayObjectsGlitchCommand) {
        guard command.role == .happening else { return }
        glitchCommand = command
        updateActiveVoices()
    }

    func configureGlitch(plan: GlitchPlan, processor: GlitchProcessor) {
        glitchPlan = plan
        glitchProcessor = processor
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
        happeningPool?.performHousekeeping()
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
            attemptPendingBirth(id: id, chord: currentChord)
        }

        for id in states.keys.sorted() {
            guard var state = states[id] else { continue }
            while state.nextOccurrenceIndex < state.scheduledOccurrences.count,
                  state.scheduledOccurrences[state.nextOccurrenceIndex].position <= event.position {
                var occurrence = state.scheduledOccurrences[state.nextOccurrenceIndex]
                guard occurrence.nextRetryPosition <= event.position else { break }
                states[id] = state
                let didEmit = canAttack(at: event.position)
                    && emitAttack(
                        id: id,
                        chord: currentChord,
                        isBirth: false,
                        motifStepIndex: occurrence.motifStepIndex
                    )
                state = states[id] ?? state
                if didEmit {
                    state.nextOccurrenceIndex += 1
                } else {
                    occurrence.retryAttemptCount += 1
                    if occurrence.retryAttemptCount >= Self.maximumAdmissionRetryAttempts
                        || event.position >= occurrence.retryDeadline {
                        state.nextOccurrenceIndex += 1
                    } else {
                        occurrence.nextRetryPosition = .init(
                            absoluteSubdivision: event.position.absoluteSubdivision
                                + Self.admissionRetrySpacingSubdivisions
                        )
                        state.scheduledOccurrences[state.nextOccurrenceIndex] = occurrence
                    }
                }
                state.nextOccurrence = state.nextOccurrenceIndex < state.scheduledOccurrences.count
                    ? state.scheduledOccurrences[state.nextOccurrenceIndex].position
                    : occurrence.position
                break
            }
            states[id] = state
        }
    }

    private func applyStructuralReplacement(_ replacement: PendingReplacement) {
        guard let happeningPool else { return }
        let oldStates = states
        let requestedPlans = Self.uniquePlans(replacement.plans)
        do {
            try happeningPool.prepare(recipeIDs: Set(requestedPlans.map(\.recipeID)))
        } catch {
            return
        }
        let newPlans = requestedPlans.filter {
            happeningPool.metrics.availableRecipeIDs.contains($0.recipeID)
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
                    motifStepIndex: event.motifStepIndex,
                    position: .init(
                        absoluteSubdivision: origin.absoluteSubdivision
                            + Int64((event.startBeat * Double(MusicalPosition.subdivisionsPerBeat)).rounded())
                    ),
                    intervalBars: event.intervalBars,
                    retryAttemptCount: 0,
                    nextRetryPosition: .init(
                        absoluteSubdivision: origin.absoluteSubdivision
                            + Int64((event.startBeat * Double(MusicalPosition.subdivisionsPerBeat)).rounded())
                    ),
                    retryDeadline: .init(
                        absoluteSubdivision: origin.absoluteSubdivision
                            + Int64((event.startBeat * Double(MusicalPosition.subdivisionsPerBeat)).rounded())
                            + Self.admissionRetryHorizonSubdivisions
                    )
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
        motifStepIndex: Int = 0
    ) -> Bool {
        guard let pool = happeningPool,
              let world = tonalWorld,
              var state = states[id],
              let recipe = HappeningSoundCatalog.recipe(for: state.plan.recipeID)
        else { return false }
        let activeVoiceCount = states.values.reduce(0) { $0 + $1.activeVoices.count }
        // Legacy plans retain the pool's existing priority/stealing policy.
        if state.plan.recurrence.maximumConcurrentVoices < 4,
           activeVoiceCount >= state.plan.recurrence.maximumConcurrentVoices { return false }
        let eventGlitch = glitchProcessor?.previewRealizedEvent(
            plan: glitchPlan,
            role: .happening,
            cycleIndex: Int(currentPosition.bar),
            stepIndex: currentPosition.subdivisionInBar
        ) ?? glitchCommand
        let resolvedSound = HappeningPitchResolver.resolve(
            recipe: recipe,
            chord: chord,
            tonalWorld: world,
            degreeOffset: state.plan.motif.degreeOffsets.indices.contains(motifStepIndex)
                ? state.plan.motif.degreeOffsets[motifStepIndex]
                : 0
        )
        let baseGain = isBirth ? state.plan.birthGain : state.plan.gain
        let gain = baseGain * mixGain * eventGlitch.dryGain
        let playbackRate = resolvedSound.playbackRate * Self.pitchMultiplier(for: eventGlitch)
        let realizedSound = ResolvedHappeningSound(
            recipeID: resolvedSound.recipeID,
            resourceName: resolvedSound.resourceName,
            sourceRootMIDI: resolvedSound.sourceRootMIDI,
            targetMIDI: resolvedSound.targetMIDI,
            playbackRate: playbackRate,
            resonantFilterHz: resolvedSound.resonantFilterHz
        )
        let priority: HappeningPlaybackPriority = isBirth ? .birth : .recurrence
        let effectCommand = effectCommand(for: state.plan, recipe: recipe, glitch: eventGlitch)
        let handle: HappeningPlaybackHandle
        do {
            handle = try pool.play(
                realizedSound,
                gain: gain,
                priority: priority,
                effects: effectCommand,
                attackSeconds: state.plan.attackSeconds,
                releaseSeconds: state.plan.releaseSeconds,
                pan: state.plan.pan
            )
        } catch {
            return false
        }

        removeStaleOwnership(of: handle.voiceID)
        state = states[id] ?? state

        nextVoiceID &+= 1
        let releaseSubdivisions = max(
            1,
            Int64(ceil(state.plan.releaseSeconds * currentTempoBPM / 60 * Double(MusicalPosition.subdivisionsPerBeat)))
        )
        state.activeVoiceIDs.insert(nextVoiceID)
        state.activeVoices[nextVoiceID] = .init(
            pool: pool,
            handle: handle,
            resolvedSound: realizedSound,
            effectCommand: effectCommand,
            baseGain: baseGain,
            basePlaybackRate: resolvedSound.playbackRate,
            releaseAt: .init(absoluteSubdivision: currentPosition.absoluteSubdivision + releaseSubdivisions)
        )
        state.didPlaySinceStart = true
        state.lastAttackPosition = currentPosition
        states[id] = state
        if let glitchProcessor { glitchProcessor.commitRealizedEvent(eventGlitch) }
        attacksPerBeat[currentPosition.absoluteBeat, default: 0] += 1
        lastGlobalAttackPosition = currentPosition
        let attack = HappeningAttackRecord(
            happeningID: id,
            position: currentPosition,
            resolvedSound: realizedSound,
            effectCommand: effectCommand,
            playbackPriority: priority,
            isBirth: isBirth
        )
        attackHistory.append(attack)
        if attackHistory.count > Self.maximumRecordedAttackCount {
            attackHistory.removeFirst(attackHistory.count - Self.maximumRecordedAttackCount)
        }
        onAttack?(attack)
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
                voice.pool.stop(voice.handle)
                state.activeVoiceIDs.remove(voiceID)
                state.activeVoices.removeValue(forKey: voiceID)
            }
            states[id] = state
        }
        let oldestRelevantBeat = max(0, position.absoluteBeat - 1)
        attacksPerBeat = attacksPerBeat.filter { $0.key >= oldestRelevantBeat }
    }

    private func releaseVoices(in state: ActiveHappeningState) {
        state.activeVoices.values.forEach { $0.pool.stop($0.handle) }
    }

    private func releaseAllOwnedVoices() {
        states.values.forEach(releaseVoices)
        for id in states.keys {
            states[id]?.activeVoiceIDs.removeAll(keepingCapacity: true)
            states[id]?.activeVoices.removeAll(keepingCapacity: true)
        }
    }

    private func updateActiveVoices() {
        for voice in states.values.flatMap({ $0.activeVoices.values }) {
            voice.pool.update(
                voice.handle,
                gain: voice.baseGain * mixGain * glitchCommand.dryGain,
                playbackRate: voice.basePlaybackRate * Self.pitchMultiplier(for: glitchCommand)
            )
        }
    }

    private func effectCommand(
        for plan: HappeningMusicPlan,
        recipe: HappeningSoundRecipe,
        glitch: DayObjectsGlitchCommand
    ) -> HappeningEffectCommand {
        let original = HappeningEffectCommand(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: min(max(plan.delaySend + glitch.delayTimeVariation, 0), 1),
            delayFeedback: recipe.delayFeedback,
            reverbMix: plan.reverbSend
        )
        // Preserve the existing direct-level curve while reducing only wet gain.
        return original.withReverbSend(original.reverbSend * reverbSendScale)
    }

    private func removeStaleOwnership(of poolVoiceID: Int) {
        for id in states.keys {
            guard var state = states[id] else { continue }
            let staleVoiceIDs = state.activeVoices.compactMap { voiceID, voice in
                voice.handle.voiceID == poolVoiceID ? voiceID : nil
            }
            for voiceID in staleVoiceIDs {
                state.activeVoiceIDs.remove(voiceID)
                state.activeVoices.removeValue(forKey: voiceID)
            }
            states[id] = state
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
            isBirthPending: false,
            birthRetryAttemptCount: 0,
            birthNextRetryPosition: .init(absoluteSubdivision: 0),
            birthRetryDeadline: .init(absoluteSubdivision: 0)
        )
    }

    private func attemptPendingBirth(id: String, chord: ChordPlan) {
        guard var state = states[id], state.isBirthPending,
              state.birthNextRetryPosition <= currentPosition else { return }
        let didEmit = canAttack(at: currentPosition)
            && emitAttack(id: id, chord: chord, isBirth: true)
        state = states[id] ?? state
        if didEmit {
            state.isBirthPending = false
            state.birthRetryAttemptCount = 0
        } else {
            state.birthRetryAttemptCount += 1
            if state.birthRetryAttemptCount >= Self.maximumAdmissionRetryAttempts
                || currentPosition >= state.birthRetryDeadline {
                state.birthRetryAttemptCount = 0
                state.birthNextRetryPosition = .init(
                    absoluteSubdivision: currentPosition.absoluteSubdivision
                        + Self.birthRetryRearmSubdivisions
                )
                state.birthRetryDeadline = .init(
                    absoluteSubdivision: state.birthNextRetryPosition.absoluteSubdivision
                        + Self.admissionRetryHorizonSubdivisions
                )
            } else {
                state.birthNextRetryPosition = .init(
                    absoluteSubdivision: currentPosition.absoluteSubdivision
                        + Self.admissionRetrySpacingSubdivisions
                )
            }
        }
        states[id] = state
    }

    private static func pitchMultiplier(for command: DayObjectsGlitchCommand) -> Double {
        let cents = command.pitchDriftCents.isFinite
            ? min(max(command.pitchDriftCents, -GlitchRole.happening.safeLimits.pitchDriftCents), GlitchRole.happening.safeLimits.pitchDriftCents)
            : 0
        return pow(2, cents / 1_200)
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
