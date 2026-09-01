#if DEBUG || INTERNAL_BUILD
import Foundation

struct LeadPlayerMetrics: Equatable, Sendable {
    let voiceCount: Int
    let amplitudeAttackCount: Int
    let releaseCount: Int
}

struct LeadPlayerHeldState: Equatable, Sendable {
    let currentMIDINote: UInt8
    let lastGesture: LeadGestureSample
}

enum LeadPlayerGestureOwner: Equatable, Sendable {
    case none
    case source
    case destination
}

struct LeadPlayerHandoffResult: Equatable, Sendable {
    let gestureOwner: LeadPlayerGestureOwner
    let didGlide: Bool
    let didRestart: Bool

    @MainActor
    func route(
        _ gesture: LeadGestureSample,
        source: LeadPlayer,
        destination: LeadPlayer
    ) {
        switch gestureOwner {
        case .none: break
        case .source: source.update(gesture)
        case .destination: destination.update(gesture)
        }
    }
}

/// Owns the single preallocated Lead voice in a playback world. Gesture
/// updates mutate that voice; they never allocate or retrigger it.
@MainActor
final class LeadPlayer {
    private static let baseCutoffHz = 3_200.0

    private let worldBank: PlaybackWorldBank
    private var pool: DayObjectsTonalVoicePoolProtocol?
    private var token: DayObjectsVoiceToken?
    private var plan: LeadPlan?
    private var mapper: LeadGestureMapper?
    private var currentChordIndex = 0
    private var currentMIDINote: UInt8?
    private var lastGesture: LeadGestureSample?
    private var baseGain = 0.25
    private var mixTargetDecibels = -12.0
    private var glitchCommand: DayObjectsGlitchCommand = .neutral(role: .lead)
    private var amplitudeAttackCount = 0
    private var releaseCount = 0

    var metrics: LeadPlayerMetrics {
        .init(
            voiceCount: token == nil ? 0 : 1,
            amplitudeAttackCount: amplitudeAttackCount,
            releaseCount: releaseCount
        )
    }

    var heldState: LeadPlayerHeldState? {
        guard token != nil, let currentMIDINote, let lastGesture else { return nil }
        return .init(currentMIDINote: currentMIDINote, lastGesture: lastGesture)
    }

    init(worldBank: PlaybackWorldBank) {
        self.worldBank = worldBank
    }

    func configure(
        plan: LeadPlan,
        gainDecibels: Double,
        currentChordIndex: Int
    ) throws {
        end()
        try worldBank.prepare()
        let pool = try worldBank.tonalPool(named: .lead)
        try pool.prepareInstrument(plan.instrumentID)
        self.pool = pool
        self.plan = plan
        mapper = LeadGestureMapper(plan: plan)
        self.currentChordIndex = Self.safeChordIndex(currentChordIndex, plan: plan)
        mixTargetDecibels = gainDecibels
        baseGain = Self.softSaturatedGain(Self.linearGain(decibels: gainDecibels))
        currentMIDINote = nil
        lastGesture = nil
    }

    func begin(_ gesture: LeadGestureSample) {
        guard var mapper, let plan, let pool else { return }
        if token != nil {
            update(gesture)
            return
        }
        mapper.reset()
        let mapping = mapper.map(gesture, chordIndex: currentChordIndex)
        self.mapper = mapper
        let expression = expressiveGain(depth: mapping.expressionDepth)
        guard let token = pool.noteOn(.init(
            instrumentID: plan.instrumentID,
            midiNote: mapping.midiNote,
            velocity: expression,
            role: .lead,
            envelopeVariant: .absolute(
                attackSeconds: max(Self.finite(plan.attackSeconds, fallback: 0.035), 0.001),
                releaseSeconds: max(Self.finite(plan.releaseSeconds, fallback: 0.65), 0.05)
            ),
            pan: 0,
            delaySend: Self.unit(plan.delaySend),
            reverbSend: Self.unit(plan.reverbSend)
        )) else { return }
        self.token = token
        currentMIDINote = mapping.midiNote
        lastGesture = gesture
        amplitudeAttackCount += 1
        apply(mapping, to: token, pool: pool)
    }

    func update(_ gesture: LeadGestureSample) {
        guard let token, let pool, var mapper else { return }
        let mapping = mapper.map(gesture, chordIndex: currentChordIndex)
        self.mapper = mapper
        currentMIDINote = mapping.midiNote
        lastGesture = gesture
        apply(mapping, to: token, pool: pool)
    }

    /// Moves ownership of a held Lead gesture without exposing the voice pool.
    /// A common pitch keeps the existing source token alive through the tail;
    /// otherwise the old token is released before one destination attack.
    func handoff(
        to destination: LeadPlayer,
        safeCommonMIDINote: UInt8?
    ) -> LeadPlayerHandoffResult {
        guard let heldState else {
            return .init(gestureOwner: .none, didGlide: false, didRestart: false)
        }
        if let safeCommonMIDINote,
           canHold(safeCommonMIDINote),
           destination.canHold(safeCommonMIDINote) {
            glideHeldVoice(to: safeCommonMIDINote)
            return .init(gestureOwner: .source, didGlide: true, didRestart: false)
        }

        end()
        destination.begin(heldState.lastGesture)
        let restarted = destination.heldState != nil
        return .init(
            gestureOwner: restarted ? .destination : .none,
            didGlide: false,
            didRestart: restarted
        )
    }

    func setCurrentChordIndex(_ chordIndex: Int) {
        guard let plan else { return }
        currentChordIndex = Self.safeChordIndex(chordIndex, plan: plan)
        guard let currentMIDINote,
              let compatible = plan.nearestCompatibleNote(
                to: currentMIDINote,
                chordIndex: currentChordIndex
              )
        else { return }
        self.currentMIDINote = compatible
        guard let token, let pool else { return }
        pool.update(token, with: .init(
            midiNote: Double(compatible),
            pitchRampSeconds: portamentoSeconds(plan)
        ))
    }

    func end() {
        guard let token, let pool else { return }
        pool.noteOff(token)
        self.token = nil
        currentMIDINote = nil
        lastGesture = nil
        releaseCount += 1
    }

    func applyMixTargetDecibels(_ decibels: Double) {
        mixTargetDecibels = decibels
        baseGain = Self.softSaturatedGain(Self.linearGain(decibels: decibels))
        reapplyHeldGesture()
    }

    /// Applies only Director fields classified as continuous; identity,
    /// register and pitch topology stay owned by the configured world.
    func applyContinuous(_ update: LeadPlan) {
        guard let structural = plan else { return }
        plan = LeadPlan(
            instrumentID: structural.instrumentID,
            maximumSimultaneousVoices: structural.maximumSimultaneousVoices,
            register: structural.register,
            pitchRegions: structural.pitchRegions,
            compatibleChordMIDINotes: structural.compatibleChordMIDINotes,
            portamentoMilliseconds: structural.portamentoMilliseconds,
            attackSeconds: structural.attackSeconds,
            releaseSeconds: structural.releaseSeconds,
            cutoffMultiplierRange: update.cutoffMultiplierRange,
            pitchSmoothingMilliseconds: update.pitchSmoothingMilliseconds,
            expressionSmoothingMilliseconds: update.expressionSmoothingMilliseconds,
            maximumExpressionDepth: update.maximumExpressionDepth,
            delaySend: update.delaySend,
            reverbSend: update.reverbSend
        )
        if let plan { mapper = LeadGestureMapper(plan: plan) }
        reapplyHeldGesture()
    }

    func applyGlitch(_ command: DayObjectsGlitchCommand) {
        guard command.role == .lead else { return }
        glitchCommand = command
        reapplyHeldGesture()
    }

    private func reapplyHeldGesture() {
        guard let gesture = lastGesture, let token, let pool, var mapper else { return }
        let mapping = mapper.map(gesture, chordIndex: currentChordIndex)
        self.mapper = mapper
        apply(mapping, to: token, pool: pool)
    }

    private func glideHeldVoice(to midiNote: UInt8) {
        guard let token, let pool, let plan else { return }
        currentMIDINote = midiNote
        pool.update(token, with: .init(
            midiNote: Double(midiNote),
            pitchRampSeconds: portamentoSeconds(plan)
        ))
    }

    private func canHold(_ midiNote: UInt8) -> Bool {
        guard let plan,
              plan.compatibleChordMIDINotes.indices.contains(currentChordIndex)
        else { return false }
        return plan.compatibleChordMIDINotes[currentChordIndex].contains(midiNote)
    }

    private func apply(
        _ mapping: LeadGestureMapping,
        to token: DayObjectsVoiceToken,
        pool: DayObjectsTonalVoicePoolProtocol
    ) {
        guard let plan else { return }
        let cutoff = min(max(
            Self.baseCutoffHz * mapping.cutoffMultiplier
                * (1 + 0.15 * Self.unit(glitchCommand.saturationAmount)),
            DayObjectsAudioParameters.minimumCutoffHz
        ), DayObjectsAudioParameters.maximumCutoffHz)
        pool.update(token, with: .init(
            midiNote: Double(mapping.midiNote) + glitchCommand.pitchDriftCents / 100,
            cutoffHz: cutoff,
            expression: expressiveGain(depth: mapping.expressionDepth) * Self.unit(glitchCommand.dryGain),
            delaySend: Self.unit(plan.delaySend),
            reverbSend: Self.unit(plan.reverbSend),
            pitchRampSeconds: portamentoSeconds(plan),
            cutoffRampSeconds: smoothingSeconds(
                plan.pitchSmoothingMilliseconds,
                fallbackMilliseconds: 45
            ),
            expressionRampSeconds: smoothingSeconds(
                plan.expressionSmoothingMilliseconds,
                fallbackMilliseconds: 80
            )
        ))
    }

    private func expressiveGain(depth: Double) -> Double {
        let boundedDepth = min(max(Self.finite(depth, fallback: 0), 0), 0.25)
        return Self.softSaturatedGain(baseGain * (1 + boundedDepth))
    }

    private func portamentoSeconds(_ plan: LeadPlan) -> Double {
        let milliseconds = min(max(
            Self.finite(plan.portamentoMilliseconds, fallback: 110),
            60
        ), 160)
        return milliseconds / 1_000
    }

    private func smoothingSeconds(_ milliseconds: Double, fallbackMilliseconds: Double) -> Double {
        min(max(Self.finite(milliseconds, fallback: fallbackMilliseconds), 10), 250) / 1_000
    }

    private static func safeChordIndex(_ index: Int, plan: LeadPlan) -> Int {
        guard !plan.compatibleChordMIDINotes.isEmpty else { return 0 }
        return min(max(index, 0), plan.compatibleChordMIDINotes.count - 1)
    }

    private static func linearGain(decibels: Double) -> Double {
        let bounded = min(max(finite(decibels, fallback: -12), -60), 0)
        return pow(10, bounded / 20)
    }

    /// A gentle static transfer curve keeps fast gestures from producing the
    /// hard edge of an unrestricted linear gain increase.
    private static func softSaturatedGain(_ value: Double) -> Double {
        let bounded = min(max(finite(value, fallback: 0), 0), 1.25)
        return min(max(bounded / sqrt(1 + 0.35 * bounded * bounded), 0), 1)
    }

    private static func unit(_ value: Double) -> Double {
        min(max(finite(value, fallback: 0), 0), 1)
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}
#endif
