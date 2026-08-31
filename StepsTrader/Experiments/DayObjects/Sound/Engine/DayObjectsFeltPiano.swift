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
        mechanicalNoiseGain: 0.035,
        noteTrimDB: -14,
        roomSend: 0.16,
        reverbSend: 0.12,
        maximumPolyphony: 4
    )

    let attackSeconds: Double
    let releaseSeconds: Double
    let lowPassCutoffHz: Double
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
}

struct DayObjectsFeltPianoToken: Hashable, Sendable {
    fileprivate let slotID: Int
    fileprivate let generation: UInt64
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
    func release()
    func allNotesOff()
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
        guard isEnabled,
              FeltPianoManifest.playableRange.contains(midiNote),
              let sample = FeltPianoManifest.sample(for: midiNote, in: samples) else { return nil }
        let slotID = slots.firstIndex(where: { !$0.isActive }) ?? oldestSlotID()
        guard let slotID else { return nil }
        if slots[slotID].isActive { slots[slotID].backend.release() }
        activationCounter &+= 1
        slots[slotID].generation &+= 1
        slots[slotID].activationOrder = activationCounter
        slots[slotID].isActive = true
        slots[slotID].backend.play(.init(
            midiNote: midiNote,
            velocity: min(max(velocity, 0), 1),
            sample: sample,
            pitchCents: Double(Int(midiNote) - Int(sample.rootMIDINote)) * 100
        ))
        return .init(slotID: slotID, generation: slots[slotID].generation)
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
            totalPlayerStopCount: backendMetrics.reduce(0) { $0 + $1.playerStopCount },
            lastPlayedRootMIDINote: mostRecent?.lastPlayedRootMIDINote,
            lastPlayedPitchCents: mostRecent?.lastPlayedPitchCents,
            appliedRecipe: .init(recipe: .default)
        )
    }

    init(samples: [FeltPianoSample], resourceResolver: @escaping DayObjectsFeltPiano.ResourceResolver) {
        var builtBackends: [DayObjectsAudioKitFeltPianoBackend] = []
        var nextPlaybackOrder: UInt64 = 0
        sampleCount = samples.count
        piano = DayObjectsFeltPiano(samples: samples, resourceResolver: resourceResolver) { recipe, sampleURLs in
            let backend = try DayObjectsAudioKitFeltPianoBackend(recipe: recipe, sampleURLs: sampleURLs) {
                nextPlaybackOrder &+= 1
                return nextPlaybackOrder
            }
            builtBackends.append(backend)
            return backend
        }
        if !piano.isEnabled { builtBackends = [] }
        backends = builtBackends
        let dry = Mixer(builtBackends.map(\.output), name: "Day Objects felt piano dry")
        room = Reverb(dry, dryWetMix: AUValue(DayObjectsFeltPianoRecipe.default.roomSend))
        reverb = Reverb(room, dryWetMix: AUValue(DayObjectsFeltPianoRecipe.default.reverbSend))
        output = Mixer([reverb], name: "Day Objects felt piano")
    }
}

struct DayObjectsFeltPianoAppliedRecipe: Equatable, Sendable {
    let attackSeconds: Double
    let releaseSeconds: Double
    let lowPassCutoffHz: Double
    let mechanicalOnsetGain: Double
    let noteTrimDB: Double
    let roomSend: Double
    let reverbSend: Double

    init(recipe: DayObjectsFeltPianoRecipe) {
        attackSeconds = recipe.attackSeconds
        releaseSeconds = recipe.releaseSeconds
        lowPassCutoffHz = recipe.lowPassCutoffHz
        mechanicalOnsetGain = 1 - recipe.mechanicalNoiseGain
        noteTrimDB = recipe.noteTrimDB
        roomSend = recipe.roomSend
        reverbSend = recipe.reverbSend
    }
}

struct DayObjectsAudioKitFeltPianoBackendMetrics: Equatable, Sendable {
    let loadedPlayerCount: Int
    let playerStopCount: Int
    let lastPlayedRootMIDINote: UInt8?
    let lastPlayedPitchCents: Double?
    let lastPlayOrder: UInt64
}

struct DayObjectsAudioKitFeltPianoMetrics: Equatable, Sendable {
    let preloadedSampleCount: Int
    let fixedBackendCount: Int
    let loadedPlayerCount: Int
    let totalPlayerStopCount: Int
    let lastPlayedRootMIDINote: UInt8?
    let lastPlayedPitchCents: Double?
    let appliedRecipe: DayObjectsFeltPianoAppliedRecipe
}

private final class DayObjectsAudioKitFeltPianoBackend: DayObjectsFeltPianoBackend {
    let output: Fader
    private let envelope: AmplitudeEnvelope
    private let players: [UInt8: (AudioPlayer, TimePitch)]
    private(set) var playerStopCount = 0
    private(set) var lastPlayedRootMIDINote: UInt8?
    private(set) var lastPlayedPitchCents: Double?
    private(set) var lastPlayOrder: UInt64 = 0
    private let nextPlaybackOrder: () -> UInt64

    var metrics: DayObjectsAudioKitFeltPianoBackendMetrics {
        .init(loadedPlayerCount: players.count, playerStopCount: playerStopCount, lastPlayedRootMIDINote: lastPlayedRootMIDINote, lastPlayedPitchCents: lastPlayedPitchCents, lastPlayOrder: lastPlayOrder)
    }

    init(recipe: DayObjectsFeltPianoRecipe, sampleURLs: [FeltPianoSample: URL], nextPlaybackOrder: @escaping () -> UInt64) throws {
        var builtPlayers: [UInt8: (AudioPlayer, TimePitch)] = [:]
        for sample in sampleURLs.keys.sorted(by: { $0.rootMIDINote < $1.rootMIDINote }) {
            guard let url = sampleURLs[sample], let player = AudioPlayer(url: url, buffered: true) else {
                throw DayObjectsFeltPianoBackendPreparationError.resourcePreloadFailed(sample)
            }
            builtPlayers[sample.rootMIDINote] = (player, TimePitch(player))
        }
        players = builtPlayers
        self.nextPlaybackOrder = nextPlaybackOrder
        let source = Mixer(builtPlayers.values.map { $0.1 })
        let filtered = LowPassFilter(source, cutoffFrequency: AUValue(recipe.lowPassCutoffHz))
        let reducedMechanicalOnset = Fader(filtered, gain: AUValue(1 - recipe.mechanicalNoiseGain))
        envelope = AmplitudeEnvelope(reducedMechanicalOnset, attackDuration: AUValue(recipe.attackSeconds), decayDuration: 0.08, sustainLevel: 1, releaseDuration: AUValue(recipe.releaseSeconds))
        output = Fader(envelope, gain: AUValue(pow(10, recipe.noteTrimDB / 20)))
    }

    func play(_ note: DayObjectsFeltPianoNote) {
        guard let (player, pitch) = players[note.sample.rootMIDINote] else { return }
        stopEveryRootPlayer()
        pitch.rate = 1
        pitch.pitch = AUValue(note.pitchCents)
        player.volume = AUValue(note.velocity)
        lastPlayedRootMIDINote = note.sample.rootMIDINote
        lastPlayedPitchCents = note.pitchCents
        lastPlayOrder = nextPlaybackOrder()
        guard output.avAudioNode.engine?.isRunning == true else { return }
        player.play()
        envelope.openGate()
    }

    func release() {
        stopEveryRootPlayer()
        envelope.closeGate()
    }
    func allNotesOff() {
        stopEveryRootPlayer()
        envelope.closeGate()
    }

    private func stopEveryRootPlayer() {
        players.values.forEach { $0.0.stop() }
        playerStopCount += players.count
    }
}
#endif
