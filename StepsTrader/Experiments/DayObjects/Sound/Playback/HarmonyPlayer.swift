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
            if case let .tonal(pool, token) = self {
                pool.update(token, with: .init(expression: expression))
            }
        }

        func release() {
            switch self {
            case let .tonal(pool, token):
                pool.noteOff(token)
            case let .piano(pool, token):
                pool.noteOff(token)
            }
        }
    }

    private struct PendingRelease {
        let token: VoiceToken
        let deadlineSubdivision: Int64
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
        var activeTokens: [VoiceToken] = []
        var pendingReleases: [PendingRelease] = []
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
                $0 + $1.activeTokens.count + $1.pendingReleases.count
            },
            pendingReleaseTokenCount: roles.reduce(0) { $0 + $1.pendingReleases.count },
            activeGainRampCount: roles.reduce(0) { $0 + ($1.gainRamp == nil ? 0 : 1) },
            scheduledChordCount: scheduledChordCount
        )
    }

    init(worldBank: PlaybackWorldBank) {
        self.worldBank = worldBank
    }

    func configure(_ plan: HarmonyPlan) throws {
        releaseAll()
        try worldBank.prepare()

        for role in plan.roles where role.role != .innerMotion {
            if case let .tonal(instrumentID) = role.instrumentTarget {
                try worldBank.tonalPool(for: role.role).prepareInstrument(instrumentID)
            }
        }
        self.plan = plan
        roles = plan.roles.map {
            RoleState(plan: $0, currentGain: Self.unit($0.gain))
        }
        currentSubdivision = 0
        scheduledChordCount = 0
    }

    func applyContinuous(_ updatedPlan: HarmonyPlan) {
        guard plan != nil else { return }
        plan = updatedPlan
        for index in roles.indices {
            guard let updatedRole = updatedPlan.role(for: roles[index].plan.role) else {
                deactivateRole(at: index)
                continue
            }
            roles[index].plan = updatedRole
            let target = Self.unit(updatedRole.gain)
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
        }
    }

    func render(subdivision event: DayObjectsTransportEvent) {
        guard event.kind == .subdivision else { return }
        currentSubdivision = event.position.absoluteSubdivision
        retireExpiredTokens(at: currentSubdivision)
        advanceGainRamps(at: currentSubdivision)
    }

    func render(barBoundary event: DayObjectsTransportEvent) {
        guard event.kind == .barBoundary, let plan else { return }
        currentSubdivision = event.position.absoluteSubdivision
        retireExpiredTokens(at: currentSubdivision)
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
            roles[index].activeTokens.forEach { $0.release() }
            roles[index].pendingReleases.forEach { $0.token.release() }
            roles[index].activeTokens.removeAll(keepingCapacity: true)
            roles[index].pendingReleases.removeAll(keepingCapacity: true)
            roles[index].gainRamp = nil
        }
        worldBank.releaseAll()
    }

    private func schedule(
        chord: HarmonyChordScheduleEntry,
        forRoleAt index: Int,
        at subdivision: Int64
    ) {
        let role = roles[index].plan
        let newTokens: [VoiceToken]
        switch role.instrumentTarget {
        case let .tonal(instrumentID):
            guard let pool = try? worldBank.tonalPool(for: role.role) else { return }
            newTokens = chord.voicedMIDINotes.compactMap { note in
                pool.noteOn(.init(
                    instrumentID: instrumentID,
                    midiNote: note,
                    velocity: roles[index].currentGain,
                    role: .note,
                    envelopeVariant: nil,
                    pan: 0,
                    delaySend: role.delaySend,
                    reverbSend: role.reverbSend
                )).map { .tonal(pool: pool, token: $0) }
            }
        case .feltPiano:
            let piano = worldBank.piano
            newTokens = chord.voicedMIDINotes.compactMap { note in
                piano.noteOn(note, velocity: roles[index].currentGain)
                    .map { .piano(pool: piano, token: $0) }
            }
        }

        let oldTokens = roles[index].activeTokens
        newTokens.forEach { $0.setExpression(roles[index].currentGain) }
        oldTokens.forEach { $0.setExpression(0) }
        let crossfadeSubdivisions = max(
            1,
            Int64((role.crossfadeBars * Double(MusicalPosition.subdivisionsPerBar)).rounded())
        )
        roles[index].pendingReleases.append(contentsOf: oldTokens.map {
            .init(token: $0, deadlineSubdivision: subdivision + crossfadeSubdivisions)
        })
        roles[index].activeTokens = newTokens
        if !newTokens.isEmpty { scheduledChordCount += 1 }
    }

    private func deactivateRole(at index: Int) {
        roles[index].activeTokens.forEach { $0.setExpression(0); $0.release() }
        roles[index].pendingReleases.forEach { $0.token.release() }
        roles[index].activeTokens.removeAll(keepingCapacity: true)
        roles[index].pendingReleases.removeAll(keepingCapacity: true)
        roles[index].gainRamp = nil
        roles[index].currentGain = 0
    }

    private func retireExpiredTokens(at subdivision: Int64) {
        for index in roles.indices {
            let expired = roles[index].pendingReleases.filter {
                $0.deadlineSubdivision <= subdivision
            }
            expired.forEach { $0.token.release() }
            roles[index].pendingReleases.removeAll {
                $0.deadlineSubdivision <= subdivision
            }
        }
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
            roles[index].activeTokens.forEach { $0.setExpression(gain) }
            if progress >= 1 { roles[index].gainRamp = nil }
        }
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif
