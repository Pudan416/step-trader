#if DEBUG || INTERNAL_BUILD
import Foundation

struct HarmonyPlayerMetrics: Equatable, Sendable {
    let activeVoiceCount: Int
    let pendingReleaseTokenCount: Int
    let activeGainRampCount: Int
    let scheduledChordCount: Int
}

@MainActor
final class HarmonyPlayer {
    private enum VoiceToken {
        case tonal(pool: DayObjectsTonalVoicePoolProtocol, token: DayObjectsVoiceToken)
        case piano(pool: DayObjectsPianoPoolProtocol, token: DayObjectsFeltPianoToken)

        func setExpression(_ expression: Double) {
            switch self {
            case let .tonal(pool, token):
                pool.update(token, with: .init(expression: expression))
            case let .piano(pool, token):
                pool.updateExpression(token, expression: expression)
            }
        }

        func updateEffects(delaySend: Double, reverbSend: Double) {
            if case let .tonal(pool, token) = self {
                pool.update(token, with: .init(delaySend: delaySend, reverbSend: reverbSend))
            }
        }

        func release() {
            switch self {
            case let .tonal(pool, token): pool.noteOff(token)
            case let .piano(pool, token): pool.noteOff(token)
            }
        }
    }

    private struct ActiveVoice {
        let midiNote: UInt8
        let token: VoiceToken
    }

    private struct ChordTransition {
        var oldVoices: [ActiveVoice]
        var newVoices: [ActiveVoice]
        var stagedNotes: [UInt8]
        let initiallyOpenedVoiceCount: Int
        let totalNewVoiceCount: Int
        let startSubdivision: Int64
        let endSubdivision: Int64
        var didOpenStagedVoices = false
    }

    private struct GainRamp {
        let startGain: Double
        let targetGain: Double
        let startSubdivision: Int64
        let endSubdivision: Int64
    }

    private struct RoleState {
        var plan: HarmonyRolePlan
        var currentGain: Double
        var activeVoices: [ActiveVoice] = []
        var transition: ChordTransition?
        var gainRamp: GainRamp?
        var lastScheduledAbsoluteBar: Int64?
    }

    private let worldBank: PlaybackWorldBank
    private var plan: HarmonyPlan?
    private var roles: [RoleState] = []
    private var currentSubdivision: Int64 = 0
    private var scheduledChordCount = 0

    var metrics: HarmonyPlayerMetrics {
        .init(
            activeVoiceCount: roles.reduce(0) {
                $0 + $1.activeVoices.count + ($1.transition?.oldVoices.count ?? 0)
            },
            pendingReleaseTokenCount: roles.reduce(0) {
                $0 + ($1.transition?.oldVoices.count ?? 0)
            },
            activeGainRampCount: roles.reduce(0) { $0 + ($1.gainRamp == nil ? 0 : 1) },
            scheduledChordCount: scheduledChordCount
        )
    }

    init(worldBank: PlaybackWorldBank) { self.worldBank = worldBank }

    func configure(_ plan: HarmonyPlan) throws {
        releaseAll()
        try worldBank.prepare()
        for role in plan.roles where role.role != .innerMotion {
            if case let .tonal(instrumentID) = role.instrumentTarget {
                try worldBank.tonalPool(for: role.role).prepareInstrument(instrumentID)
            }
        }
        self.plan = plan
        roles = plan.roles.map { RoleState(plan: $0, currentGain: Self.unit($0.gain)) }
        currentSubdivision = 0
        scheduledChordCount = 0
    }

    /// Patch only fields classified as continuous by DayMusicPlanDiffer.
    /// Structural target/register/schedule/cycle/crossfade remain configured.
    func applyContinuous(_ updatedPlan: HarmonyPlan) {
        guard let structuralPlan = plan else { return }
        var patchedRoles: [HarmonyRolePlan] = []
        for index in roles.indices {
            let old = roles[index].plan
            guard let update = updatedPlan.role(for: old.role) else {
                patchedRoles.append(old)
                continue
            }
            let patched = HarmonyRolePlan(
                role: old.role,
                instrumentTarget: old.instrumentTarget,
                register: old.register,
                gain: update.gain,
                attackSeconds: update.attackSeconds,
                releaseSeconds: update.releaseSeconds,
                delaySend: update.delaySend,
                reverbSend: update.reverbSend,
                activation: .init(
                    startProgress: old.activation.startProgress,
                    fullProgress: old.activation.fullProgress,
                    amount: update.activation.amount
                ),
                chordSchedule: old.chordSchedule,
                crossfadeBars: old.crossfadeBars
            )
            roles[index].plan = patched
            patchedRoles.append(patched)
            let target = Self.unit(update.gain)
            if target == 0 {
                deactivateRole(at: index)
            } else if target != roles[index].currentGain {
                roles[index].gainRamp = .init(
                    startGain: roles[index].currentGain,
                    targetGain: target,
                    startSubdivision: currentSubdivision,
                    endSubdivision: currentSubdivision + MusicalPosition.subdivisionsPerBar
                )
            }
            roles[index].activeVoices.forEach {
                $0.token.updateEffects(delaySend: patched.delaySend, reverbSend: patched.reverbSend)
            }
        }
        plan = HarmonyPlan(
            sleepProgress: updatedPlan.sleepProgress,
            cycleBars: structuralPlan.cycleBars,
            chordCount: structuralPlan.chordCount,
            roles: patchedRoles
        )
    }

    func render(subdivision event: DayObjectsTransportEvent) {
        guard event.kind == .subdivision else { return }
        currentSubdivision = event.position.absoluteSubdivision
        advanceGainRamps(at: currentSubdivision)
        advanceChordTransitions(at: currentSubdivision)
    }

    func render(barBoundary event: DayObjectsTransportEvent) {
        guard event.kind == .barBoundary, let plan else { return }
        currentSubdivision = event.position.absoluteSubdivision
        advanceGainRamps(at: currentSubdivision)
        advanceChordTransitions(at: currentSubdivision)
        let cycleBar = Int(event.position.bar % Int64(max(1, plan.cycleBars)))
        for index in roles.indices {
            guard roles[index].currentGain > 0,
                  roles[index].plan.role != .innerMotion,
                  roles[index].lastScheduledAbsoluteBar != event.position.bar,
                  let chord = roles[index].plan.chordSchedule.first(where: { $0.startBar == cycleBar })
            else { continue }
            schedule(chord: chord, forRoleAt: index, at: currentSubdivision)
            roles[index].lastScheduledAbsoluteBar = event.position.bar
        }
    }

    func releaseAll() {
        for index in roles.indices {
            roles[index].activeVoices.forEach { $0.token.release() }
            roles[index].transition?.oldVoices.forEach { $0.token.release() }
            roles[index].activeVoices.removeAll(keepingCapacity: true)
            roles[index].transition = nil
            roles[index].gainRamp = nil
        }
        worldBank.releaseAll()
    }

    private func schedule(
        chord: HarmonyChordScheduleEntry,
        forRoleAt index: Int,
        at subdivision: Int64
    ) {
        completeInterruptedTransition(at: index)
        let role = roles[index].plan
        let oldVoices = roles[index].activeVoices
        let capacity = voiceCapacity(for: role)
        let available = max(0, capacity - oldVoices.count)
        let notesToOpen = Array(chord.voicedMIDINotes.prefix(available))
        let stagedNotes = Array(
            chord.voicedMIDINotes.dropFirst(notesToOpen.count).prefix(capacity - notesToOpen.count)
        )
        let newVoices = openVoices(notesToOpen, for: role, expression: 0)
        let duration = max(
            1,
            Int64((role.crossfadeBars * Double(MusicalPosition.subdivisionsPerBar)).rounded())
        )
        roles[index].activeVoices = newVoices
        roles[index].transition = .init(
            oldVoices: oldVoices,
            newVoices: newVoices,
            stagedNotes: stagedNotes,
            initiallyOpenedVoiceCount: newVoices.count,
            totalNewVoiceCount: min(chord.voicedMIDINotes.count, capacity),
            startSubdivision: subdivision,
            endSubdivision: subdivision + duration
        )
        if !newVoices.isEmpty || !stagedNotes.isEmpty { scheduledChordCount += 1 }
    }

    private func advanceChordTransitions(at subdivision: Int64) {
        for index in roles.indices {
            guard var transition = roles[index].transition else { continue }
            let duration = max(1, transition.endSubdivision - transition.startSubdivision)
            let progress = min(
                max(Double(subdivision - transition.startSubdivision) / Double(duration), 0),
                1
            )
            let target = Self.chordVoiceGain(
                roleGain: roles[index].currentGain,
                voiceCount: transition.totalNewVoiceCount
            )
            if !transition.stagedNotes.isEmpty {
                transition.oldVoices.forEach {
                    $0.token.setExpression(target * max(0, 1 - (2 * progress)))
                }
                transition.newVoices.prefix(transition.initiallyOpenedVoiceCount).forEach {
                    $0.token.setExpression(target * progress)
                }
                if progress >= 0.5, !transition.didOpenStagedVoices {
                    transition.oldVoices.forEach { $0.token.release() }
                    transition.oldVoices.removeAll(keepingCapacity: true)
                    let staged = openVoices(
                        transition.stagedNotes,
                        for: roles[index].plan,
                        expression: 0
                    )
                    transition.newVoices.append(contentsOf: staged)
                    roles[index].activeVoices.append(contentsOf: staged)
                    transition.stagedNotes.removeAll(keepingCapacity: true)
                    transition.didOpenStagedVoices = true
                }
            } else {
                transition.oldVoices.forEach { $0.token.setExpression(target * (1 - progress)) }
                transition.newVoices.forEach { $0.token.setExpression(target * progress) }
            }
            if transition.didOpenStagedVoices {
                let stagedFactor = max(0, min(1, (2 * progress) - 1))
                transition.newVoices.dropFirst(transition.initiallyOpenedVoiceCount).forEach {
                    $0.token.setExpression(target * stagedFactor)
                }
            }
            if progress >= 1 {
                transition.oldVoices.forEach { $0.token.release() }
                transition.newVoices.forEach { $0.token.setExpression(target) }
                roles[index].activeVoices = transition.newVoices
                roles[index].transition = nil
            } else {
                roles[index].transition = transition
            }
        }
    }

    private func openVoices(
        _ notes: [UInt8],
        for role: HarmonyRolePlan,
        expression: Double
    ) -> [ActiveVoice] {
        switch role.instrumentTarget {
        case let .tonal(instrumentID):
            guard let pool = try? worldBank.tonalPool(for: role.role) else { return [] }
            return notes.compactMap { note in
                pool.noteOn(.init(
                    instrumentID: instrumentID,
                    midiNote: note,
                    velocity: expression,
                    role: .note,
                    envelopeVariant: .absolute(
                        attackSeconds: role.attackSeconds,
                        releaseSeconds: role.releaseSeconds
                    ),
                    pan: 0,
                    delaySend: role.delaySend,
                    reverbSend: role.reverbSend
                )).map { ActiveVoice(midiNote: note, token: .tonal(pool: pool, token: $0)) }
            }
        case .feltPiano:
            let piano = worldBank.piano
            return notes.compactMap { note in
                piano.noteOn(.init(
                    midiNote: note,
                    velocity: expression,
                    attackSeconds: role.attackSeconds,
                    releaseSeconds: role.releaseSeconds,
                    roomSend: role.delaySend,
                    reverbSend: role.reverbSend
                )).map { ActiveVoice(midiNote: note, token: .piano(pool: piano, token: $0)) }
            }
        }
    }

    private func completeInterruptedTransition(at index: Int) {
        guard let transition = roles[index].transition else { return }
        transition.oldVoices.forEach { $0.token.release() }
        var voices = transition.newVoices
        if !transition.stagedNotes.isEmpty {
            voices.append(contentsOf: openVoices(
                transition.stagedNotes,
                for: roles[index].plan,
                expression: Self.chordVoiceGain(
                    roleGain: roles[index].currentGain,
                    voiceCount: transition.totalNewVoiceCount
                )
            ))
        }
        roles[index].activeVoices = voices
        roles[index].transition = nil
    }

    private func deactivateRole(at index: Int) {
        roles[index].activeVoices.forEach { $0.token.setExpression(0); $0.token.release() }
        roles[index].transition?.oldVoices.forEach { $0.token.setExpression(0); $0.token.release() }
        roles[index].activeVoices.removeAll(keepingCapacity: true)
        roles[index].transition = nil
        roles[index].gainRamp = nil
        roles[index].currentGain = 0
    }

    private func advanceGainRamps(at subdivision: Int64) {
        for index in roles.indices {
            guard let ramp = roles[index].gainRamp else { continue }
            let duration = max(1, ramp.endSubdivision - ramp.startSubdivision)
            let progress = min(
                max(Double(subdivision - ramp.startSubdivision) / Double(duration), 0),
                1
            )
            let gain = ramp.startGain + ((ramp.targetGain - ramp.startGain) * progress)
            roles[index].currentGain = gain
            if roles[index].transition == nil {
                let voiceGain = Self.chordVoiceGain(
                    roleGain: gain,
                    voiceCount: roles[index].activeVoices.count
                )
                roles[index].activeVoices.forEach { $0.token.setExpression(voiceGain) }
            }
            if progress >= 1 { roles[index].gainRamp = nil }
        }
    }

    private func voiceCapacity(for role: HarmonyRolePlan) -> Int {
        switch role.instrumentTarget {
        case .feltPiano: return worldBank.piano.metrics.allocatedPlayerCount
        case .tonal:
            return (try? worldBank.tonalPool(for: role.role).metrics.allocatedVoiceCount) ?? 0
        }
    }

    private static func chordVoiceGain(roleGain: Double, voiceCount: Int) -> Double {
        guard voiceCount > 0 else { return 0 }
        return unit(roleGain) / sqrt(Double(voiceCount))
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif
