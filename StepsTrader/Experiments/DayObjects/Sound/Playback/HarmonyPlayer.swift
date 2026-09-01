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
            update(expression: expression, delaySend: nil, reverbSend: nil)
        }

        func update(expression: Double?, delaySend: Double?, reverbSend: Double?) {
            switch self {
            case let .tonal(pool, token):
                pool.update(token, with: .init(
                    expression: expression,
                    delaySend: delaySend,
                    reverbSend: reverbSend
                ))
            case let .piano(pool, token):
                pool.update(token, with: .init(
                    expression: expression,
                    roomSend: delaySend,
                    reverbSend: reverbSend
                ))
            }
        }

        func updateEffects(delaySend: Double, reverbSend: Double) {
            update(expression: nil, delaySend: delaySend, reverbSend: reverbSend)
        }

        func applyGlitch(
            baseMIDINote: UInt8,
            expression: Double,
            delaySend: Double,
            reverbSend: Double,
            command: DayObjectsGlitchCommand
        ) {
            switch self {
            case let .tonal(pool, token):
                let direction = baseMIDINote.isMultiple(of: 2) ? 1.0 : -1.0
                pool.update(token, with: .init(
                    midiNote: Double(baseMIDINote)
                        + command.pitchDriftCents / 100
                        + direction * command.wowFlutterDepth * 0.08,
                    expression: expression,
                    pan: direction * command.stereoSeparationAddition,
                    delaySend: delaySend,
                    reverbSend: reverbSend,
                    pitchRampSeconds: command.rampDurationSeconds,
                    expressionRampSeconds: command.rampDurationSeconds
                ))
            case let .piano(pool, token):
                pool.update(token, with: .init(
                    expression: expression,
                    roomSend: delaySend,
                    reverbSend: reverbSend
                ))
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
        let totalStagedVoiceCount: Int
        var completedStagedVoiceCount = 0
        var isCurrentStagedVoiceOpened = false
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
    private var mixGain = 1.0
    private var glitchCommand: DayObjectsGlitchCommand = .neutral(role: .pad)

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
        var tonalTargets: [ObjectIdentifier: (
            pool: DayObjectsTonalVoicePoolProtocol,
            ids: [DayObjectsInstrumentID]
        )] = [:]
        for role in plan.roles {
            if case let .tonal(instrumentID) = role.instrumentTarget {
                let pool = try worldBank.tonalPool(for: role.role)
                let key = ObjectIdentifier(pool)
                var target = tonalTargets[key] ?? (pool, [])
                if !target.ids.contains(instrumentID) { target.ids.append(instrumentID) }
                tonalTargets[key] = target
            }
        }
        for target in tonalTargets.values {
            try target.pool.prepareInstruments(target.ids)
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
            if target != roles[index].currentGain {
                if target == 0 { flattenTransitionForDeactivation(at: index) }
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

    func applyMixTargetDecibels(_ decibels: Double) {
        mixGain = decibels.isFinite ? pow(10, min(max(decibels, -60), 0) / 20) : 0
        refreshActiveVoiceControls()
    }

    func applyGlitch(_ command: DayObjectsGlitchCommand) {
        guard command.role == .pad else { return }
        glitchCommand = command
        refreshActiveVoiceControls()
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
                  Self.unit(roles[index].plan.gain) > 0,
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
            endSubdivision: subdivision + duration,
            totalStagedVoiceCount: stagedNotes.count
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
            ) * mixGain * glitchCommand.dryGain
            if transition.totalStagedVoiceCount > 0 {
                transition.newVoices.prefix(transition.initiallyOpenedVoiceCount).forEach {
                    $0.token.setExpression(target * progress)
                }
                let scaledProgress = progress * Double(transition.totalStagedVoiceCount)
                let completedTarget = min(
                    Int(floor(scaledProgress)),
                    transition.totalStagedVoiceCount
                )
                while transition.completedStagedVoiceCount < completedTarget {
                    if !transition.isCurrentStagedVoiceOpened {
                        openNextStagedVoice(in: &transition, forRoleAt: index)
                    }
                    transition.newVoices.last?.token.setExpression(target)
                    transition.completedStagedVoiceCount += 1
                    transition.isCurrentStagedVoiceOpened = false
                }
                if transition.completedStagedVoiceCount < transition.totalStagedVoiceCount {
                    let localProgress = scaledProgress - Double(transition.completedStagedVoiceCount)
                    transition.oldVoices.dropFirst().forEach { $0.token.setExpression(target) }
                    if localProgress < 0.5 {
                        transition.oldVoices.first?.token.setExpression(target * (1 - (2 * localProgress)))
                    } else {
                        if !transition.isCurrentStagedVoiceOpened {
                            openNextStagedVoice(in: &transition, forRoleAt: index)
                        }
                        transition.newVoices.last?.token.setExpression(target * ((2 * localProgress) - 1))
                    }
                }
            } else {
                transition.oldVoices.forEach { $0.token.setExpression(target * (1 - progress)) }
                transition.newVoices.forEach { $0.token.setExpression(target * progress) }
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

    private func openNextStagedVoice(in transition: inout ChordTransition, forRoleAt index: Int) {
        guard let old = transition.oldVoices.first,
              let note = transition.stagedNotes.first
        else { return }
        old.token.release()
        transition.oldVoices.removeFirst()
        transition.stagedNotes.removeFirst()
        let opened = openVoices([note], for: roles[index].plan, expression: 0)
        transition.newVoices.append(contentsOf: opened)
        roles[index].activeVoices.append(contentsOf: opened)
        transition.isCurrentStagedVoiceOpened = !opened.isEmpty
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
                guard let token = pool.noteOn(.init(
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
                )) else { return nil }
                let voice = ActiveVoice(midiNote: note, token: .tonal(pool: pool, token: token))
                voice.token.applyGlitch(
                    baseMIDINote: note,
                    expression: expression,
                    delaySend: min(max(role.delaySend + glitchCommand.delayTimeVariation, 0), 1),
                    reverbSend: role.reverbSend,
                    command: glitchCommand
                )
                return voice
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
                ) * mixGain * glitchCommand.dryGain
            ))
        }
        roles[index].activeVoices = voices
        roles[index].transition = nil
    }

    private func flattenTransitionForDeactivation(at index: Int) {
        guard let transition = roles[index].transition else { return }
        roles[index].activeVoices = transition.oldVoices + transition.newVoices
        roles[index].transition = nil
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
                ) * mixGain * glitchCommand.dryGain
                roles[index].activeVoices.forEach {
                    $0.token.update(
                        expression: voiceGain,
                        delaySend: roles[index].plan.delaySend,
                        reverbSend: roles[index].plan.reverbSend
                    )
                }
            }
            if progress >= 1 {
                roles[index].gainRamp = nil
                if ramp.targetGain == 0 {
                    roles[index].activeVoices.forEach { $0.token.release() }
                    roles[index].activeVoices.removeAll(keepingCapacity: true)
                }
            }
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

    private func refreshActiveVoiceControls() {
        for state in roles {
            let voices = state.activeVoices + (state.transition?.oldVoices ?? [])
            let expression = Self.chordVoiceGain(
                roleGain: state.currentGain,
                voiceCount: max(voices.count, 1)
            ) * mixGain * glitchCommand.dryGain
            for voice in voices {
                voice.token.applyGlitch(
                    baseMIDINote: voice.midiNote,
                    expression: expression,
                    delaySend: min(max(state.plan.delaySend + glitchCommand.delayTimeVariation, 0), 1),
                    reverbSend: state.plan.reverbSend,
                    command: glitchCommand
                )
            }
        }
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif
