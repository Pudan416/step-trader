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
    let playbackRate: Double
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

protocol DayObjectsFeltPianoBackend: AnyObject {
    func play(_ note: DayObjectsFeltPianoNote)
    func release()
    func allNotesOff()
}

final class DayObjectsFeltPiano {
    typealias ResourceResolver = (FeltPianoSample) -> URL?
    typealias PlayerFactory = (DayObjectsFeltPianoRecipe) -> any DayObjectsFeltPianoBackend

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
        let unresolved = samples.filter { resourceResolver($0) == nil }
        preloadedSampleCount = samples.count - unresolved.count
        if !unresolved.isEmpty {
            diagnostics = unresolved.map {
                .init(id: "day-objects.piano.resource-missing.\(Self.diagnosticComponent($0.filename))", role: .piano)
            }
            return
        }
        guard samples.count == 12, recipe.maximumPolyphony > 0 else { return }
        slots = (0..<recipe.maximumPolyphony).map { _ in Slot(backend: playerFactory(recipe)) }
        isEnabled = true
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
            playbackRate: pow(2, Double(Int(midiNote) - Int(sample.rootMIDINote)) / 12)
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

    init(samples: [FeltPianoSample], resourceResolver: @escaping DayObjectsFeltPiano.ResourceResolver) {
        let urls = Dictionary(uniqueKeysWithValues: samples.compactMap { sample in resourceResolver(sample).map { (sample, $0) } })
        var builtBackends: [DayObjectsAudioKitFeltPianoBackend] = []
        piano = DayObjectsFeltPiano(samples: samples, resourceResolver: { urls[$0] }) { recipe in
            let backend = DayObjectsAudioKitFeltPianoBackend(recipe: recipe, sampleURLs: urls)
            builtBackends.append(backend)
            return backend
        }
        let dry = Mixer(builtBackends.map(\.output), name: "Day Objects felt piano dry")
        room = Reverb(dry, dryWetMix: AUValue(DayObjectsFeltPianoRecipe.default.roomSend))
        reverb = Reverb(room, dryWetMix: AUValue(DayObjectsFeltPianoRecipe.default.reverbSend))
        output = Mixer([reverb], name: "Day Objects felt piano")
    }
}

private final class DayObjectsAudioKitFeltPianoBackend: DayObjectsFeltPianoBackend {
    let output: Fader
    private let envelope: AmplitudeEnvelope
    private let players: [UInt8: (AudioPlayer, TimePitch)]

    init(recipe: DayObjectsFeltPianoRecipe, sampleURLs: [FeltPianoSample: URL]) {
        var builtPlayers: [UInt8: (AudioPlayer, TimePitch)] = [:]
        for (sample, url) in sampleURLs {
            guard let player = AudioPlayer(url: url, buffered: true) else { continue }
            builtPlayers[sample.rootMIDINote] = (player, TimePitch(player))
        }
        players = builtPlayers
        let source = Mixer(builtPlayers.values.map { $0.1 })
        let filtered = LowPassFilter(source, cutoffFrequency: AUValue(recipe.lowPassCutoffHz))
        envelope = AmplitudeEnvelope(filtered, attackDuration: AUValue(recipe.attackSeconds), decayDuration: 0.08, sustainLevel: 1, releaseDuration: AUValue(recipe.releaseSeconds))
        output = Fader(envelope, gain: AUValue(pow(10, recipe.noteTrimDB / 20)))
    }

    func play(_ note: DayObjectsFeltPianoNote) {
        guard let (player, pitch) = players[note.sample.rootMIDINote] else { return }
        player.stop()
        pitch.rate = AUValue(note.playbackRate)
        player.volume = AUValue(note.velocity)
        player.play()
        envelope.openGate()
    }

    func release() { envelope.closeGate() }
    func allNotesOff() {
        players.values.forEach { $0.0.stop() }
        envelope.closeGate()
    }
}
#endif
