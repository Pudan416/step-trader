#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import Foundation
import SoundpipeAudioKit

struct DayObjectsFeltPianoRecipe: Equatable, Sendable {
    static let `default` = DayObjectsFeltPianoRecipe(
        attackSeconds: 0.012,
        releaseSeconds: 0.42,
        lowPassCutoffHz: 7_200,
        mechanicalOnsetHighPassHz: 5_200,
        mechanicalNoiseGain: 0.035,
        noteTrimDB: -14,
        roomSend: 0.16,
        reverbSend: 0.12,
        maximumPolyphony: 4
    )

    let attackSeconds: Double
    let releaseSeconds: Double
    let lowPassCutoffHz: Double
    let mechanicalOnsetHighPassHz: Double
    let mechanicalNoiseGain: Double
    let noteTrimDB: Double
    let roomSend: Double
    let reverbSend: Double
    let maximumPolyphony: Int
}

struct DayObjectsFeltPianoNote: Equatable, Sendable {
    let midiNote: UInt8
    let velocity: Double
    let sample: FeltPianoSample
    let pitchCents: Double
    let attackSeconds: Double
    let releaseSeconds: Double

    init(
        midiNote: UInt8,
        velocity: Double,
        sample: FeltPianoSample,
        pitchCents: Double,
        attackSeconds: Double = DayObjectsFeltPianoRecipe.default.attackSeconds,
        releaseSeconds: Double = DayObjectsFeltPianoRecipe.default.releaseSeconds
    ) {
        self.midiNote = midiNote
        self.velocity = velocity
        self.sample = sample
        self.pitchCents = pitchCents
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
    }
}

struct DayObjectsPianoNoteRequest: Equatable, Sendable {
    let midiNote: UInt8
    let velocity: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let roomSend: Double
    let reverbSend: Double
}

struct DayObjectsFeltPianoToken: Hashable, Sendable {
    fileprivate let slotID: Int
    fileprivate let generation: UInt64

    /// Internal test and playback-adapter construction; production tokens
    /// remain allocated exclusively by the felt-piano pool.
    init(slotID: Int, generation: UInt64) {
        self.slotID = slotID
        self.generation = generation
    }
}

struct DayObjectsFeltPianoMetrics: Equatable, Sendable {
    let allocatedPlayerCount: Int
    let activeNoteCount: Int
    let maximumPolyphony: Int
}

struct DayObjectsFeltPianoDiagnostic: Equatable, Sendable {
    let id: String
    let role: DayObjectsInstrumentCategory
}

enum DayObjectsFeltPianoBackendPreparationError: Error {
    case resourcePreloadFailed(FeltPianoSample)
}

protocol DayObjectsFeltPianoBackend: AnyObject {
    func play(_ note: DayObjectsFeltPianoNote)
    func setExpression(_ expression: Double)
    func release()
    func allNotesOff()
}

extension DayObjectsFeltPianoBackend {
    func setExpression(_ expression: Double) {}
}

final class DayObjectsFeltPiano {
    typealias ResourceResolver = (FeltPianoSample) -> URL?
    typealias PlayerFactory = (DayObjectsFeltPianoRecipe, [FeltPianoSample: URL]) throws -> any DayObjectsFeltPianoBackend

    private struct Slot {
        let backend: any DayObjectsFeltPianoBackend
        var generation: UInt64 = 0
        var activationOrder: UInt64 = 0
        var isActive = false
    }

    let recipe: DayObjectsFeltPianoRecipe
    private(set) var diagnostics: [DayObjectsFeltPianoDiagnostic] = []
    private(set) var isEnabled = false
    private(set) var preloadedSampleCount = 0
    var metrics: DayObjectsFeltPianoMetrics {
        .init(allocatedPlayerCount: slots.count, activeNoteCount: slots.filter(\.isActive).count, maximumPolyphony: recipe.maximumPolyphony)
    }

    private let samples: [FeltPianoSample]
    private var slots: [Slot] = []
    private var activationCounter: UInt64 = 0

    init(
        samples: [FeltPianoSample],
        recipe: DayObjectsFeltPianoRecipe = .default,
        resourceResolver: @escaping ResourceResolver,
        playerFactory: PlayerFactory
    ) {
        self.samples = samples
        self.recipe = recipe
        var resolvedURLs: [FeltPianoSample: URL] = [:]
        var unresolved: [FeltPianoSample] = []
        for sample in samples {
            if let url = resourceResolver(sample) { resolvedURLs[sample] = url }
            else { unresolved.append(sample) }
        }
        preloadedSampleCount = 0
        if !unresolved.isEmpty {
            diagnostics = unresolved.map {
                .init(id: "day-objects.piano.resource-missing.\(Self.diagnosticComponent($0.filename))", role: .piano)
            }
            return
        }
        guard samples.count == 12, recipe.maximumPolyphony > 0 else { return }
        do {
            slots = try (0..<recipe.maximumPolyphony).map { _ in
                Slot(backend: try playerFactory(recipe, resolvedURLs))
            }
            preloadedSampleCount = samples.count
            isEnabled = true
        } catch let error as DayObjectsFeltPianoBackendPreparationError {
            slots = []
            preloadedSampleCount = 0
            switch error {
            case let .resourcePreloadFailed(sample):
                diagnostics = [.init(id: "day-objects.piano.resource-preload-failed.\(Self.diagnosticComponent(sample.filename))", role: .piano)]
            }
        } catch {
            slots = []
            preloadedSampleCount = 0
            diagnostics = [.init(id: "day-objects.piano.backend-preload-failed", role: .piano)]
        }
    }

    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? {
        noteOn(.init(
            midiNote: midiNote,
            velocity: velocity,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds,
            roomSend: recipe.roomSend,
            reverbSend: recipe.reverbSend
        ))
    }

    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken? {
        guard isEnabled,
              FeltPianoManifest.playableRange.contains(request.midiNote),
              let sample = FeltPianoManifest.sample(for: request.midiNote, in: samples) else { return nil }
        let slotID = slots.firstIndex(where: { !$0.isActive }) ?? oldestSlotID()
        guard let slotID else { return nil }
        if slots[slotID].isActive { slots[slotID].backend.release() }
        activationCounter &+= 1
        slots[slotID].generation &+= 1
        slots[slotID].activationOrder = activationCounter
        slots[slotID].isActive = true
        slots[slotID].backend.play(.init(
            midiNote: request.midiNote,
            velocity: min(max(request.velocity, 0), 1),
            sample: sample,
            pitchCents: Double(Int(request.midiNote) - Int(sample.rootMIDINote)) * 100,
            attackSeconds: min(max(request.attackSeconds, 0), 30),
            releaseSeconds: min(max(request.releaseSeconds, 0), 30)
        ))
        return .init(slotID: slotID, generation: slots[slotID].generation)
    }

    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {
        guard slots.indices.contains(token.slotID),
              slots[token.slotID].isActive,
              slots[token.slotID].generation == token.generation
        else { return }
        slots[token.slotID].backend.setExpression(min(max(expression, 0), 1))
    }

    @discardableResult
    func noteOff(_ token: DayObjectsFeltPianoToken) -> Bool {
        guard slots.indices.contains(token.slotID), slots[token.slotID].isActive, slots[token.slotID].generation == token.generation else { return false }
        slots[token.slotID].backend.release()
        slots[token.slotID].isActive = false
        return true
    }

    func stop() {
        for index in slots.indices {
            slots[index].backend.allNotesOff()
            slots[index].isActive = false
        }
    }

    private func oldestSlotID() -> Int? {
        slots.indices.min { slots[$0].activationOrder < slots[$1].activationOrder }
    }

    private static func diagnosticComponent(_ filename: String) -> String {
        filename.replacingOccurrences(of: ".caf", with: "").replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

/// Detached AudioKit graph. It owns no engine or audio session and is safe to prepare before playback.
final class DayObjectsAudioKitFeltPiano {
    typealias BufferedPlayerLoader = (URL) -> AudioPlayer?

    let piano: DayObjectsFeltPiano
    let output: Mixer
    let room: Reverb
    let reverb: Reverb
    private let backends: [DayObjectsAudioKitFeltPianoBackend]
    private let sampleCount: Int

    var metrics: DayObjectsAudioKitFeltPianoMetrics {
        let backendMetrics = backends.map(\.metrics)
        let mostRecent = backendMetrics.max { $0.lastPlayOrder < $1.lastPlayOrder }
        return .init(
            preloadedSampleCount: piano.isEnabled ? sampleCount : 0,
            fixedBackendCount: backends.count,
            loadedPlayerCount: backendMetrics.reduce(0) { $0 + $1.loadedPlayerCount },
            totalHardStoppedVoiceCount: backendMetrics.reduce(0) { $0 + $1.hardStoppedVoiceCount },
            selectedRootMIDINotes: backendMetrics.compactMap(\.selectedRootMIDINote),
            releaseTailBackendCount: backendMetrics.filter(\.isReleasing).count,
            lastPlayedRootMIDINote: mostRecent?.lastPlayedRootMIDINote,
            lastPlayedPitchCents: mostRecent?.lastPlayedPitchCents,
            appliedRecipe: .init(
                backend: backends.first,
                room: room,
                reverb: reverb
            )
        )
    }

    init(
        samples: [FeltPianoSample],
        recipe: DayObjectsFeltPianoRecipe = .default,
        resourceResolver: @escaping DayObjectsFeltPiano.ResourceResolver,
        bufferedPlayerLoader: @escaping BufferedPlayerLoader = { AudioPlayer(url: $0, buffered: true) }
    ) {
        var builtBackends: [DayObjectsAudioKitFeltPianoBackend] = []
        var nextPlaybackOrder: UInt64 = 0
        sampleCount = samples.count
        piano = DayObjectsFeltPiano(samples: samples, recipe: recipe, resourceResolver: resourceResolver) { recipe, sampleURLs in
            let backend = try DayObjectsAudioKitFeltPianoBackend(recipe: recipe, sampleURLs: sampleURLs, bufferedPlayerLoader: bufferedPlayerLoader) {
                nextPlaybackOrder &+= 1
                return nextPlaybackOrder
            }
            builtBackends.append(backend)
            return backend
        }
        if !piano.isEnabled { builtBackends = [] }
        backends = builtBackends
        let dry = Mixer(builtBackends.map(\.output), name: "Day Objects felt piano dry")
        room = Reverb(dry, dryWetMix: AUValue(piano.recipe.roomSend))
        reverb = Reverb(room, dryWetMix: AUValue(piano.recipe.reverbSend))
        output = Mixer([reverb], name: "Day Objects felt piano")
    }
}

struct DayObjectsFeltPianoAppliedRecipe: Equatable, Sendable {
    let attackSeconds: Double
    let releaseSeconds: Double
    let lowPassCutoffHz: Double
    let mechanicalOnsetHighPassHz: Double
    let mechanicalOnsetGain: Double
    let mechanicalOnsetBranchInputCount: Int
    let noteTrimDB: Double
    let roomSend: Double
    let reverbSend: Double

    fileprivate init(backend: DayObjectsAudioKitFeltPianoBackend?, room: Reverb, reverb: Reverb) {
        attackSeconds = Double(backend?.attackSeconds ?? 0)
        releaseSeconds = Double(backend?.releaseSeconds ?? 0)
        lowPassCutoffHz = Double(backend?.bodyLowPassCutoffHz ?? 0)
        mechanicalOnsetHighPassHz = Double(backend?.mechanicalOnsetHighPassHz ?? 0)
        mechanicalOnsetGain = Double(backend?.mechanicalOnsetGain ?? 0)
        mechanicalOnsetBranchInputCount = backend?.mechanicalOnsetBranchInputCount ?? 0
        noteTrimDB = Double(backend?.noteTrimDB ?? 0)
        roomSend = Double(room.dryWetMix)
        reverbSend = Double(reverb.dryWetMix)
    }
}

struct DayObjectsAudioKitFeltPianoBackendMetrics: Equatable, Sendable {
    let loadedPlayerCount: Int
    let hardStoppedVoiceCount: Int
    let selectedRootMIDINote: UInt8?
    let isReleasing: Bool
    let lastPlayedRootMIDINote: UInt8?
    let lastPlayedPitchCents: Double?
    let lastPlayOrder: UInt64
}

struct DayObjectsAudioKitFeltPianoMetrics: Equatable, Sendable {
    let preloadedSampleCount: Int
    let fixedBackendCount: Int
    let loadedPlayerCount: Int
    let totalHardStoppedVoiceCount: Int
    let selectedRootMIDINotes: [UInt8]
    let releaseTailBackendCount: Int
    let lastPlayedRootMIDINote: UInt8?
    let lastPlayedPitchCents: Double?
    let appliedRecipe: DayObjectsFeltPianoAppliedRecipe
}

private final class DayObjectsAudioKitFeltPianoBackend: DayObjectsFeltPianoBackend {
    let output: Fader
    private let envelope: AmplitudeEnvelope
    private let bodyLowPass: LowPassFilter
    private let mechanicalOnsetHighPass: HighPassFilter
    private let mechanicalOnset: Fader
    private let shapedSource: Mixer
    private let players: [UInt8: (AudioPlayer, TimePitch)]
    private(set) var hardStoppedVoiceCount = 0
    private(set) var selectedRootMIDINote: UInt8?
    private(set) var isReleasing = false
    private(set) var lastPlayedRootMIDINote: UInt8?
    private(set) var lastPlayedPitchCents: Double?
    private(set) var lastPlayOrder: UInt64 = 0
    private let nextPlaybackOrder: () -> UInt64
    private let noteTrimLinear: AUValue

    var attackSeconds: AUValue { envelope.attackDuration }
    var releaseSeconds: AUValue { envelope.releaseDuration }
    var bodyLowPassCutoffHz: AUValue { bodyLowPass.cutoffFrequency }
    var mechanicalOnsetHighPassHz: AUValue { mechanicalOnsetHighPass.cutoffFrequency }
    var mechanicalOnsetGain: AUValue { mechanicalOnset.leftGain }
    var mechanicalOnsetBranchInputCount: Int { shapedSource.connections.count }
    var noteTrimDB: AUValue { 20 * log10(output.leftGain) }

    var metrics: DayObjectsAudioKitFeltPianoBackendMetrics {
        .init(
            loadedPlayerCount: players.values.filter { Self.hasUsableBufferedPCM($0.0) }.count,
            hardStoppedVoiceCount: hardStoppedVoiceCount,
            selectedRootMIDINote: selectedRootMIDINote,
            isReleasing: isReleasing,
            lastPlayedRootMIDINote: lastPlayedRootMIDINote,
            lastPlayedPitchCents: lastPlayedPitchCents,
            lastPlayOrder: lastPlayOrder
        )
    }

    init(
        recipe: DayObjectsFeltPianoRecipe,
        sampleURLs: [FeltPianoSample: URL],
        bufferedPlayerLoader: @escaping DayObjectsAudioKitFeltPiano.BufferedPlayerLoader,
        nextPlaybackOrder: @escaping () -> UInt64
    ) throws {
        var builtPlayers: [UInt8: (AudioPlayer, TimePitch)] = [:]
        for sample in sampleURLs.keys.sorted(by: { $0.rootMIDINote < $1.rootMIDINote }) {
            guard let url = sampleURLs[sample],
                  let player = bufferedPlayerLoader(url),
                  Self.hasUsableBufferedPCM(player)
            else {
                throw DayObjectsFeltPianoBackendPreparationError.resourcePreloadFailed(sample)
            }
            builtPlayers[sample.rootMIDINote] = (player, TimePitch(player))
        }
        players = builtPlayers
        self.nextPlaybackOrder = nextPlaybackOrder
        let source = Mixer(builtPlayers.values.map { $0.1 })
        bodyLowPass = LowPassFilter(source, cutoffFrequency: AUValue(recipe.lowPassCutoffHz))
        mechanicalOnsetHighPass = HighPassFilter(source, cutoffFrequency: AUValue(recipe.mechanicalOnsetHighPassHz))
        mechanicalOnset = Fader(mechanicalOnsetHighPass, gain: AUValue(recipe.mechanicalNoiseGain))
        shapedSource = Mixer([bodyLowPass, mechanicalOnset], name: "Day Objects felt piano body and mechanical onset")
        envelope = AmplitudeEnvelope(shapedSource, attackDuration: AUValue(recipe.attackSeconds), decayDuration: 0.08, sustainLevel: 1, releaseDuration: AUValue(recipe.releaseSeconds))
        noteTrimLinear = AUValue(pow(10, recipe.noteTrimDB / 20))
        output = Fader(envelope, gain: noteTrimLinear)
    }

    func play(_ note: DayObjectsFeltPianoNote) {
        guard let (player, pitch) = players[note.sample.rootMIDINote] else { return }
        if selectedRootMIDINote != nil { hardStopEveryRootPlayer() }
        pitch.rate = 1
        pitch.pitch = AUValue(note.pitchCents)
        player.volume = 1
        envelope.attackDuration = AUValue(note.attackSeconds)
        envelope.releaseDuration = AUValue(note.releaseSeconds)
        setExpression(note.velocity)
        selectedRootMIDINote = note.sample.rootMIDINote
        isReleasing = false
        lastPlayedRootMIDINote = note.sample.rootMIDINote
        lastPlayedPitchCents = note.pitchCents
        lastPlayOrder = nextPlaybackOrder()
        guard output.avAudioNode.engine?.isRunning == true else { return }
        player.play()
        envelope.openGate()
    }

    func setExpression(_ expression: Double) {
        let target = noteTrimLinear * AUValue(min(max(expression, 0), 1))
        output.$leftGain.ramp(to: target, duration: Float(DayObjectsAudioParameters.controlRampDuration))
        output.$rightGain.ramp(to: target, duration: Float(DayObjectsAudioParameters.controlRampDuration))
    }

    func release() {
        guard selectedRootMIDINote != nil else { return }
        isReleasing = true
        envelope.closeGate()
    }

    func allNotesOff() {
        hardStopEveryRootPlayer()
        selectedRootMIDINote = nil
        isReleasing = false
        envelope.closeGate()
    }

    private static func hasUsableBufferedPCM(_ player: AudioPlayer) -> Bool {
        guard let buffer = player.buffer else { return false }
        return buffer.frameLength > 0
    }

    private func hardStopEveryRootPlayer() {
        guard selectedRootMIDINote != nil else {
            players.values.forEach { $0.0.stop() }
            return
        }
        players.values.forEach { $0.0.stop() }
        hardStoppedVoiceCount += 1
    }
}
#endif
