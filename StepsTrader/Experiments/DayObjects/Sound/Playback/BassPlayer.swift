#if DEBUG || INTERNAL_BUILD
import Foundation

protocol BassDuckBackend: AnyObject {
    func apply(_ command: BassDuckCommand)
}

struct BassPlaybackFrame: Equatable, Sendable {
    let position: MusicalPosition
    let attackedEventStableID: UInt64?
    let activeVoiceCount: Int
    let appliedDuckCommandCount: Int
}

struct BassPlayerMetrics: Equatable, Sendable {
    let allocatedVoiceCount: Int
    let activeVoiceCount: Int
    let attackCount: Int
    let releaseCount: Int
}

/// Owns the reserved single bass voice in one playback world. Every new bass
/// event releases the held gate before a replacement attack can be scheduled.
@MainActor
final class BassPlayer {
    private static let baseCutoffHz = 180.0
    private static let controlRampSeconds = 0.025

    private let worldBank: PlaybackWorldBank
    private let duckBackend: BassDuckBackend
    private var pool: DayObjectsTonalVoicePoolProtocol?
    private var token: DayObjectsVoiceToken?
    private var heldUntilSubdivision: Int64?
    private var lastAttackSubdivision: Int64?
    private var attackCount = 0
    private var releaseCount = 0

    var metrics: BassPlayerMetrics {
        .init(
            allocatedVoiceCount: pool?.metrics.allocatedVoiceCount ?? 0,
            activeVoiceCount: token == nil ? 0 : 1,
            attackCount: attackCount,
            releaseCount: releaseCount
        )
    }

    init(worldBank: PlaybackWorldBank, duckBackend: BassDuckBackend) {
        self.worldBank = worldBank
        self.duckBackend = duckBackend
    }

    func configure(_ plan: BassPlan?) throws {
        releaseAll()
        guard let plan else {
            pool = nil
            return
        }
        try worldBank.prepare()
        let pool = try worldBank.tonalPool(forBass: plan.instrumentID)
        try pool.prepareInstrument(plan.instrumentID)
        self.pool = pool
        heldUntilSubdivision = nil
        lastAttackSubdivision = nil
    }

    @discardableResult
    func render(
        _ transportEvent: DayObjectsTransportEvent,
        plan: BassPlan?,
        duckCommands: [BassDuckCommand]
    ) -> BassPlaybackFrame {
        for command in duckCommands { duckBackend.apply(command) }
        guard transportEvent.kind == .subdivision else {
            return frame(
                at: transportEvent.position,
                attackedEventStableID: nil,
                duckCommandCount: duckCommands.count
            )
        }

        let subdivision = transportEvent.position.absoluteSubdivision
        if let heldUntilSubdivision, subdivision >= heldUntilSubdivision {
            releaseHeldVoice()
        }
        guard let plan,
              let pool,
              lastAttackSubdivision != subdivision,
              let event = plan.events.first(where: {
                  $0.activationThreshold <= plan.stepsProgress && $0.startSubdivision == subdivision
              })
        else {
            return frame(
                at: transportEvent.position,
                attackedEventStableID: nil,
                duckCommandCount: duckCommands.count
            )
        }

        releaseHeldVoice()
        let request = DayObjectsTonalNoteRequest(
            instrumentID: plan.instrumentID,
            midiNote: event.midiNote,
            velocity: Self.unit(event.velocity),
            role: .note,
            envelopeVariant: .absolute(
                attackSeconds: Self.attackSeconds(for: plan.articulation),
                releaseSeconds: Self.releaseSeconds(for: plan.articulation)
            ),
            pan: 0,
            delaySend: 0,
            reverbSend: Self.unit(plan.reverbSend)
        )
        guard let token = pool.noteOn(request) else {
            return frame(
                at: transportEvent.position,
                attackedEventStableID: nil,
                duckCommandCount: duckCommands.count
            )
        }

        self.token = token
        heldUntilSubdivision = subdivision + max(event.durationSubdivisions, 1)
        lastAttackSubdivision = subdivision
        attackCount += 1
        pool.update(token, with: .init(
            cutoffHz: Self.cutoffHz(multiplier: plan.cutoffMultiplier),
            expression: Self.unit(event.velocity),
            reverbSend: Self.unit(plan.reverbSend),
            pitchRampSeconds: Self.glideSeconds(plan.glideMilliseconds),
            cutoffRampSeconds: Self.controlRampSeconds,
            expressionRampSeconds: Self.controlRampSeconds
        ))
        return frame(
            at: transportEvent.position,
            attackedEventStableID: event.stableID,
            duckCommandCount: duckCommands.count
        )
    }

    func releaseAll() {
        releaseHeldVoice()
        heldUntilSubdivision = nil
        lastAttackSubdivision = nil
    }

    func applyContinuous(_ plan: BassPlan?) {
        guard let plan, let token, let pool else { return }
        pool.update(token, with: .init(
            cutoffHz: Self.cutoffHz(multiplier: plan.cutoffMultiplier),
            reverbSend: Self.unit(plan.reverbSend),
            cutoffRampSeconds: Self.controlRampSeconds,
            expressionRampSeconds: Self.controlRampSeconds
        ))
    }

    private func frame(
        at position: MusicalPosition,
        attackedEventStableID: UInt64?,
        duckCommandCount: Int
    ) -> BassPlaybackFrame {
        .init(
            position: position,
            attackedEventStableID: attackedEventStableID,
            activeVoiceCount: token == nil ? 0 : 1,
            appliedDuckCommandCount: duckCommandCount
        )
    }

    private func releaseHeldVoice() {
        guard let token, let pool else { return }
        pool.noteOff(token)
        self.token = nil
        heldUntilSubdivision = nil
        releaseCount += 1
    }

    private static func attackSeconds(for articulation: BassArticulation) -> Double {
        switch articulation {
        case .pulse: return 0.012
        case .arpeggio: return 0.010
        case .sustained: return 0.025
        }
    }

    private static func releaseSeconds(for articulation: BassArticulation) -> Double {
        switch articulation {
        case .pulse: return 0.120
        case .arpeggio: return 0.140
        case .sustained: return 0.220
        }
    }

    private static func cutoffHz(multiplier: Double) -> Double {
        min(max(baseCutoffHz * (multiplier.isFinite ? multiplier : 1), DayObjectsAudioParameters.minimumCutoffHz), DayObjectsAudioParameters.maximumCutoffHz)
    }

    private static func glideSeconds(_ milliseconds: Double) -> Double {
        min(max(milliseconds.isFinite ? milliseconds / 1_000 : 0, 0), 0.160)
    }

    private static func unit(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}
#endif
