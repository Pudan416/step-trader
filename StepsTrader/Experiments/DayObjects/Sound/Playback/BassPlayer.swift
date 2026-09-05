#if DEBUG || INTERNAL_BUILD
import Foundation

@MainActor
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
    let schedulingOriginSubdivision: Int64?
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
    private var heldStableID: UInt64?
    private var heldUntilGlobalSubdivision: Int64?
    private var lastAttackGlobalSubdivision: Int64?
    private var schedulingOriginSubdivision: Int64?
    private var cycleLengthSubdivisions = MusicalPosition.subdivisionsPerBar
    private var acceptsAttacks = true
    private var attackCount = 0
    private var releaseCount = 0
    private var mixGain = 1.0
    private var diagnosticToken: DayObjectsVoiceToken?
    private var diagnosticPool: DayObjectsTonalVoicePoolProtocol?
    private var diagnosticReleaseTask: Task<Void, Never>?
    private var diagnosticRestorationPlan: BassPlan?
    private(set) var lastDiagnosticHostTimeSeconds: TimeInterval?

    var metrics: BassPlayerMetrics {
        .init(
            allocatedVoiceCount: pool?.metrics.allocatedVoiceCount ?? 0,
            activeVoiceCount: token == nil && diagnosticToken == nil ? 0 : 1,
            attackCount: attackCount,
            releaseCount: releaseCount,
            schedulingOriginSubdivision: schedulingOriginSubdivision
        )
    }

    init(worldBank: PlaybackWorldBank, duckBackend: BassDuckBackend) {
        self.worldBank = worldBank
        self.duckBackend = duckBackend
    }

    func configure(
        _ plan: BassPlan?,
        cycleLengthSubdivisions: Int64 = MusicalPosition.subdivisionsPerBar
    ) throws {
        releaseAll()
        schedulingOriginSubdivision = nil
        self.cycleLengthSubdivisions = max(cycleLengthSubdivisions, 1)
        acceptsAttacks = true
        guard let plan else {
            pool = nil
            return
        }
        try worldBank.prepare()
        let pool = try worldBank.tonalPool(forBass: plan.instrumentID)
        try pool.prepareInstrument(plan.instrumentID)
        self.pool = pool
        heldStableID = nil
        heldUntilGlobalSubdivision = nil
        lastAttackGlobalSubdivision = nil
    }

    func startScheduling(at position: MusicalPosition? = nil) {
        acceptsAttacks = true
        if let position { schedulingOriginSubdivision = position.absoluteSubdivision }
    }

    func stopAttacks() {
        acceptsAttacks = false
        releaseAll()
    }

    /// Compatibility entry point for callers that still collect commands. The
    /// transport path uses the optional overload below so it never allocates a
    /// per-subdivision command array.
    @discardableResult
    func render(
        _ transportEvent: DayObjectsTransportEvent,
        plan: BassPlan?,
        duckCommands: [BassDuckCommand]
    ) -> BassPlaybackFrame {
        let first = duckCommands.first
        let rendered = render(
            transportEvent,
            plan: plan,
            duckCommand: first
        )
        for command in duckCommands.dropFirst() { duckBackend.apply(command) }
        guard duckCommands.count > 1 else { return rendered }
        return .init(
            position: rendered.position,
            attackedEventStableID: rendered.attackedEventStableID,
            activeVoiceCount: rendered.activeVoiceCount,
            appliedDuckCommandCount: duckCommands.count
        )
    }

    @discardableResult
    func render(
        _ transportEvent: DayObjectsTransportEvent,
        plan: BassPlan?,
        duckCommand: BassDuckCommand?
    ) -> BassPlaybackFrame {
        if let duckCommand { duckBackend.apply(duckCommand) }
        guard transportEvent.kind == .subdivision else {
            return frame(
                at: transportEvent.position,
                attackedEventStableID: nil,
                duckCommandCount: duckCommand == nil ? 0 : 1
            )
        }

        let globalSubdivision = transportEvent.position.absoluteSubdivision
        if schedulingOriginSubdivision == nil { schedulingOriginSubdivision = globalSubdivision }
        if let heldUntilGlobalSubdivision, globalSubdivision >= heldUntilGlobalSubdivision {
            releaseHeldVoice()
        }
        let relativeSubdivision = relativeSubdivision(for: globalSubdivision)
        guard let plan,
              let pool,
              acceptsAttacks,
              lastAttackGlobalSubdivision != globalSubdivision,
              let event = plan.activeEvents.first(where: {
                  $0.startSubdivision == relativeSubdivision
              })
        else {
            return frame(
                at: transportEvent.position,
                attackedEventStableID: nil,
                duckCommandCount: duckCommand == nil ? 0 : 1
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
                duckCommandCount: duckCommand == nil ? 0 : 1
            )
        }

        self.token = token
        heldStableID = event.stableID
        heldUntilGlobalSubdivision = globalSubdivision + max(event.durationSubdivisions, 1)
        lastAttackGlobalSubdivision = globalSubdivision
        attackCount += 1
        pool.update(token, with: .init(
            cutoffHz: Self.cutoffHz(multiplier: plan.cutoffMultiplier),
            expression: Self.unit(event.velocity * mixGain),
            reverbSend: Self.unit(plan.reverbSend),
            pitchRampSeconds: Self.glideSeconds(plan.glideMilliseconds),
            cutoffRampSeconds: Self.controlRampSeconds,
            expressionRampSeconds: Self.controlRampSeconds
        ))
        return frame(
            at: transportEvent.position,
            attackedEventStableID: event.stableID,
            duckCommandCount: duckCommand == nil ? 0 : 1
        )
    }

    func releaseAll() {
        releaseHeldVoice()
        heldStableID = nil
        heldUntilGlobalSubdivision = nil
        lastAttackGlobalSubdivision = nil
        schedulingOriginSubdivision = nil
    }

    func applyContinuous(_ plan: BassPlan?) {
        guard let plan, let token, let pool, let heldStableID else { return }
        guard let event = plan.activeEvents.first(where: {
            $0.stableID == heldStableID
        }) else {
            releaseHeldVoice()
            return
        }
        pool.update(token, with: .init(
            cutoffHz: Self.cutoffHz(multiplier: plan.cutoffMultiplier),
            expression: Self.unit(event.velocity * mixGain),
            reverbSend: Self.unit(plan.reverbSend),
            cutoffRampSeconds: Self.controlRampSeconds,
            expressionRampSeconds: Self.controlRampSeconds
        ))
    }

    func applyMixTargetDecibels(_ decibels: Double) {
        let bounded = min(max(decibels.isFinite ? decibels : -60, -60), 0)
        mixGain = pow(10, bounded / 20)
    }

    /// Schedules one diagnostic note through the capacity-one production Bass
    /// pool. Any transport gate is released before the diagnostic token takes
    /// ownership; restoration later reprepares the composition preset.
    @discardableResult
    func audition(
        instrumentID: DayObjectsInstrumentID,
        midiNote: UInt8,
        velocity: Double,
        hostTime: TimeInterval,
        restorationPlan: BassPlan?
    ) throws -> Bool {
        guard acceptsAttacks, hostTime.isFinite else { return false }
        releaseDiagnosticAudition(restoring: nil)
        releaseHeldVoice()
        try worldBank.prepare()
        let pool = try worldBank.tonalPool(forBass: instrumentID)
        try pool.prepareInstrument(instrumentID)
        guard let token = pool.noteOn(.init(
            instrumentID: instrumentID,
            midiNote: midiNote,
            velocity: Self.unit(velocity),
            role: .note,
            envelopeVariant: .absolute(attackSeconds: 0.012, releaseSeconds: 0.180),
            pan: 0,
            delaySend: 0,
            reverbSend: 0.08
        ), atHostTime: hostTime) else { return false }
        diagnosticPool = pool
        diagnosticToken = token
        diagnosticRestorationPlan = restorationPlan
        lastDiagnosticHostTimeSeconds = hostTime
        diagnosticReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self?.releaseDiagnosticAudition(restoring: self?.diagnosticRestorationPlan)
        }
        attackCount += 1
        return true
    }

    func releaseDiagnosticAudition(restoring plan: BassPlan?) {
        diagnosticReleaseTask?.cancel()
        diagnosticReleaseTask = nil
        if let diagnosticToken, let diagnosticPool { diagnosticPool.noteOff(diagnosticToken) }
        diagnosticToken = nil
        diagnosticPool = nil
        diagnosticRestorationPlan = nil
        lastDiagnosticHostTimeSeconds = nil
        guard let plan else { return }
        let resumeAt = schedulingOriginSubdivision
        releaseHeldVoice()
        try? configure(plan, cycleLengthSubdivisions: cycleLengthSubdivisions)
        acceptsAttacks = true
        if let resumeAt { startScheduling(at: .init(absoluteSubdivision: resumeAt)) }
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
        heldStableID = nil
        heldUntilGlobalSubdivision = nil
        releaseCount += 1
    }

    private func relativeSubdivision(for globalSubdivision: Int64) -> Int64 {
        let origin = schedulingOriginSubdivision ?? globalSubdivision
        let offset = (globalSubdivision - origin) % cycleLengthSubdivisions
        return offset >= 0 ? offset : offset + cycleLengthSubdivisions
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
