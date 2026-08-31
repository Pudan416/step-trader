#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import Foundation
import SoundpipeAudioKit

enum DayObjectsDrumSample: String, CaseIterable, Sendable {
    case bassDrum = "bass_drum_C1.wav"
    case closedHat = "closed_hi_hat_F#1.wav"
    case openHat = "open_hi_hat_A#1.wav"
    case clap = "clap_D#1.wav"
    case snare = "snare_D1.wav"
    case stick = "cheeb-stick.wav"
    case cheebHat = "cheeb-hat.wav"
    case cheebCh = "cheeb-ch.wav"
}

enum DayObjectsDrumSynthesisLayer: Hashable, Sendable {
    case sinePitchDrop
    case filteredNoise
}

struct DayObjectsDrumSinePitchDrop: Equatable, Sendable {
    let startFrequencyHz: Double
    let endFrequencyHz: Double
    let amplitude: Double
}

struct DayObjectsDrumVariation: Equatable, Sendable {
    let velocityRange: ClosedRange<Double>
    let pitchRateRange: ClosedRange<Double>

    static let none = DayObjectsDrumVariation(velocityRange: 1...1, pitchRateRange: 1...1)
    static let percussion = DayObjectsDrumVariation(velocityRange: 0.88...1.0, pitchRateRange: 0.98...1.02)
}

struct DayObjectsDrumRecipe: Equatable, Sendable {
    let voice: DayObjectsDrumVoice
    let primarySample: DayObjectsDrumSample?
    let fallbackSample: DayObjectsDrumSample?
    let synthesis: Set<DayObjectsDrumSynthesisLayer>
    let sinePitchDrop: DayObjectsDrumSinePitchDrop?
    let noiseAmplitude: Double?
    let overlapCount: Int
    let transientFilterCutoffHz: Double?
    let noiseFilterCutoffHz: Double?
    let variation: DayObjectsDrumVariation
    let allowsPitchDrift: Bool
    let allowsBroadbandSustainedNoise: Bool
    let usesSawOscillator: Bool
    let delayFeedback: Double?

    static func recipe(for voice: DayObjectsDrumVoice) -> DayObjectsDrumRecipe {
        switch voice {
        case .kickSoft:
            return kick(voice, overlapCount: 2)
        case .kickFull:
            return kick(voice, overlapCount: 3)
        case .hatClosed:
            return sample(voice, .closedHat, fallback: .cheebHat, overlapCount: 3, variation: .percussion)
        case .hatOpen:
            return sample(voice, .openHat, overlapCount: 2, variation: .percussion)
        case .shaker:
            return .init(
                voice: voice, primarySample: nil, fallbackSample: nil, synthesis: [.filteredNoise], sinePitchDrop: nil, noiseAmplitude: 0.22, overlapCount: 2,
                transientFilterCutoffHz: nil, noiseFilterCutoffHz: 7_200, variation: .percussion,
                allowsPitchDrift: false, allowsBroadbandSustainedNoise: false, usesSawOscillator: false, delayFeedback: nil
            )
        case .clapSoft:
            return sample(voice, .clap, overlapCount: 2, variation: .percussion)
        case .stick:
            return sample(voice, .stick, overlapCount: 2, variation: .percussion)
        case .organicHigh:
            return sample(voice, .snare, overlapCount: 2, variation: .percussion)
        case .organicLow:
            return sample(voice, .cheebCh, overlapCount: 2, variation: .percussion)
        }
    }

    private static func kick(_ voice: DayObjectsDrumVoice, overlapCount: Int) -> DayObjectsDrumRecipe {
        .init(
            voice: voice, primarySample: .bassDrum, fallbackSample: nil, synthesis: [.sinePitchDrop],
            sinePitchDrop: .init(startFrequencyHz: voice == .kickFull ? 140 : 110, endFrequencyHz: voice == .kickFull ? 46 : 52, amplitude: voice == .kickFull ? 0.8 : 0.55),
            noiseAmplitude: nil, overlapCount: overlapCount,
            transientFilterCutoffHz: 4_000, noiseFilterCutoffHz: nil, variation: .none,
            allowsPitchDrift: false, allowsBroadbandSustainedNoise: false, usesSawOscillator: false, delayFeedback: nil
        )
    }

    private static func sample(
        _ voice: DayObjectsDrumVoice,
        _ primarySample: DayObjectsDrumSample,
        fallback: DayObjectsDrumSample? = nil,
        overlapCount: Int,
        variation: DayObjectsDrumVariation
    ) -> DayObjectsDrumRecipe {
        .init(
            voice: voice, primarySample: primarySample, fallbackSample: fallback, synthesis: [], sinePitchDrop: nil, noiseAmplitude: nil, overlapCount: overlapCount,
            transientFilterCutoffHz: 9_000, noiseFilterCutoffHz: nil, variation: variation,
            allowsPitchDrift: false, allowsBroadbandSustainedNoise: false, usesSawOscillator: false, delayFeedback: nil
        )
    }
}

struct DayObjectsDrumDiagnostic: Equatable, Sendable {
    let id: String
    let voice: DayObjectsDrumVoice
}

struct DayObjectsDrumHit: Equatable, Sendable {
    let voice: DayObjectsDrumVoice
    let velocity: Double
    let pitchRate: Double
}

struct DayObjectsDrumBankMetrics: Equatable, Sendable {
    let allocatedPlayerCount: Int
    let enabledVoiceCount: Int
}

struct DayObjectsDrumGraphLayout: Equatable, Sendable {
    let samplePlayerCount: Int
    let sinePitchDropCount: Int
    let filteredNoiseCount: Int
    let transientFilterCutoffHz: Double?
    let noiseFilterCutoffHz: Double?
    let allocatedNodeCount: Int

    static let empty = DayObjectsDrumGraphLayout(
        samplePlayerCount: 0, sinePitchDropCount: 0, filteredNoiseCount: 0,
        transientFilterCutoffHz: nil, noiseFilterCutoffHz: nil, allocatedNodeCount: 0
    )
}

struct DayObjectsAudioKitDrumBankMetrics: Equatable, Sendable {
    let preloadedSampleCount: Int
    let fixedPlayerCount: Int
    let allocatedNodeCount: Int
    private let layouts: [DayObjectsDrumVoice: DayObjectsDrumGraphLayout]

    init(
        preloadedSampleCount: Int,
        fixedPlayerCount: Int,
        allocatedNodeCount: Int,
        layouts: [DayObjectsDrumVoice: DayObjectsDrumGraphLayout]
    ) {
        self.preloadedSampleCount = preloadedSampleCount
        self.fixedPlayerCount = fixedPlayerCount
        self.allocatedNodeCount = allocatedNodeCount
        self.layouts = layouts
    }

    func layout(for voice: DayObjectsDrumVoice) -> DayObjectsDrumGraphLayout {
        layouts[voice] ?? .empty
    }
}

protocol DayObjectsDrumPlayerBackend: AnyObject {
    func play(_ hit: DayObjectsDrumHit)
    func stop()
}

extension DayObjectsDrumPlayerBackend {
    func stop() {}
}

final class DayObjectsDrumBank {
    typealias ResourceResolver = (DayObjectsDrumSample) -> URL?
    typealias PlayerFactory = (DayObjectsDrumRecipe, DayObjectsDrumSample?, URL?) -> any DayObjectsDrumPlayerBackend

    private struct Slot {
        let player: any DayObjectsDrumPlayerBackend
        var hitIndex = 0
    }

    private let resolvedSamples: [DayObjectsDrumSample: URL]
    private let resolvedVoiceSamples: [DayObjectsDrumVoice: DayObjectsDrumSample]
    private let recipes: [DayObjectsDrumVoice: DayObjectsDrumRecipe]
    private var slots: [DayObjectsDrumVoice: [Slot]] = [:]
    private(set) var diagnostics: [DayObjectsDrumDiagnostic] = []

    var metrics: DayObjectsDrumBankMetrics {
        .init(allocatedPlayerCount: slots.values.reduce(0) { $0 + $1.count }, enabledVoiceCount: slots.count)
    }

    var preloadedSampleCount: Int { resolvedSamples.count }

    init(resourceResolver: @escaping ResourceResolver, recipes: [DayObjectsDrumVoice: DayObjectsDrumRecipe]? = nil, playerFactory: PlayerFactory) {
        self.recipes = recipes ?? Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { ($0, DayObjectsDrumRecipe.recipe(for: $0)) })
        var samples: [DayObjectsDrumSample: URL] = [:]
        for sample in DayObjectsDrumSample.allCases {
            if let url = resourceResolver(sample) {
                samples[sample] = url
            } else {
                diagnostics.append(.init(
                    id: "day-objects.drum.resource-missing.\(Self.diagnosticComponent(sample))",
                    voice: Self.dependentVoice(for: sample)
                ))
            }
        }
        resolvedSamples = samples

        var voiceSamples: [DayObjectsDrumVoice: DayObjectsDrumSample] = [:]
        for voice in DayObjectsDrumVoice.allCases {
            let recipe = self.recipes[voice] ?? DayObjectsDrumRecipe.recipe(for: voice)
            guard let primary = recipe.primarySample else {
                voiceSamples[voice] = nil
                continue
            }
            if samples[primary] != nil {
                voiceSamples[voice] = primary
            } else {
                if let fallback = recipe.fallbackSample, samples[fallback] != nil {
                    voiceSamples[voice] = fallback
                } else {
                    diagnostics.append(.init(id: "day-objects.drum.voice-disabled.\(voice.rawValue)", voice: voice))
                    continue
                }
            }
            slots[voice] = (0..<recipe.overlapCount).map { _ in
                let sample = voiceSamples[voice] ?? primary
                return Slot(player: playerFactory(recipe, sample, samples[sample]))
            }
        }

        for voice in DayObjectsDrumVoice.allCases where (self.recipes[voice] ?? DayObjectsDrumRecipe.recipe(for: voice)).primarySample == nil {
            let recipe = self.recipes[voice] ?? DayObjectsDrumRecipe.recipe(for: voice)
            slots[voice] = (0..<recipe.overlapCount).map { _ in Slot(player: playerFactory(recipe, nil, nil)) }
        }
        resolvedVoiceSamples = voiceSamples
    }

    func isEnabled(_ voice: DayObjectsDrumVoice) -> Bool {
        slots[voice] != nil
    }

    func resolvedSample(for voice: DayObjectsDrumVoice) -> DayObjectsDrumSample? {
        resolvedVoiceSamples[voice]
    }

    func hit(_ voice: DayObjectsDrumVoice, velocity: Double = 0.9) {
        guard var voiceSlots = slots[voice], !voiceSlots.isEmpty else { return }
        let recipe = recipes[voice] ?? DayObjectsDrumRecipe.recipe(for: voice)
        let slotID = voiceSlots[0].hitIndex % voiceSlots.count
        let variationIndex = voiceSlots[0].hitIndex % 3
        let variationFraction = Double(variationIndex) / 2
        let variation = recipe.variation
        let boundedVelocity = min(max(velocity, 0), 1) * (variation.velocityRange.lowerBound + (variation.velocityRange.upperBound - variation.velocityRange.lowerBound) * variationFraction)
        let pitchRate = variation.pitchRateRange.lowerBound + (variation.pitchRateRange.upperBound - variation.pitchRateRange.lowerBound) * variationFraction
        voiceSlots[slotID].player.play(.init(voice: voice, velocity: boundedVelocity, pitchRate: pitchRate))
        voiceSlots[0].hitIndex &+= 1
        slots[voice] = voiceSlots
    }

    func releaseAll() {
        slots.values.flatMap { $0 }.forEach { $0.player.stop() }
    }

    private static func diagnosticComponent(_ sample: DayObjectsDrumSample) -> String {
        sample.rawValue
            .replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }

    private static func dependentVoice(for sample: DayObjectsDrumSample) -> DayObjectsDrumVoice {
        switch sample {
        case .bassDrum: return .kickSoft
        case .closedHat, .cheebHat: return .hatClosed
        case .openHat: return .hatOpen
        case .clap: return .clapSoft
        case .snare: return .organicHigh
        case .stick: return .stick
        case .cheebCh: return .organicLow
        }
    }
}

final class DayObjectsAudioKitDrumBank {
    let bank: DayObjectsDrumBank
    let output: Mixer

    private let players: [DayObjectsAudioKitDrumPlayer]
    private let preloadedSamples: [DayObjectsDrumSample: AudioPlayer]
    private let preparedSampleCount: Int

    var metrics: DayObjectsAudioKitDrumBankMetrics {
        let layouts = Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { voice in
            (voice, players.first(where: { $0.voice == voice })?.graphLayout ?? .empty)
        })
        return .init(
            preloadedSampleCount: preparedSampleCount,
            fixedPlayerCount: players.count,
            allocatedNodeCount: preloadedSamples.count + players.reduce(0) { $0 + $1.graphLayout.allocatedNodeCount },
            layouts: layouts
        )
    }

    init(resourceResolver: @escaping DayObjectsDrumBank.ResourceResolver, recipes: [DayObjectsDrumVoice: DayObjectsDrumRecipe]? = nil) {
        var builtPlayers: [DayObjectsAudioKitDrumPlayer] = []
        var loadedSamples: [DayObjectsDrumSample: AudioPlayer] = [:]
        var loadedSampleCount = 0
        let preload: DayObjectsDrumBank.ResourceResolver = { sample in
            guard let url = resourceResolver(sample), let player = AudioPlayer(url: url, buffered: true) else { return nil }
            loadedSamples[sample] = player
            loadedSampleCount += 1
            return url
        }
        let builtBank = DayObjectsDrumBank(resourceResolver: preload, recipes: recipes) { recipe, sample, sampleURL in
            let preloadedSamplePlayer = sample.flatMap { loadedSamples.removeValue(forKey: $0) }
            let player = DayObjectsAudioKitDrumPlayer(
                recipe: recipe,
                sampleURL: sampleURL,
                preloadedSamplePlayer: preloadedSamplePlayer
            )
            builtPlayers.append(player)
            return player
        }
        bank = builtBank
        players = builtPlayers
        preloadedSamples = loadedSamples
        preparedSampleCount = loadedSampleCount
        output = Mixer(builtPlayers.map(\.output), name: "Day Objects drums")
    }

    func releaseAll() { bank.releaseAll() }
}

private final class DayObjectsAudioKitDrumPlayer: DayObjectsDrumPlayerBackend {
    let output: Fader
    let voice: DayObjectsDrumVoice
    let graphLayout: DayObjectsDrumGraphLayout

    private let samplePlayer: AudioPlayer?
    private let sampleTimePitch: TimePitch?
    private let sampleTransient: LowPassFilter?
    private let sine: Oscillator?
    private let sineEnvelope: AmplitudeEnvelope?
    private let noise: WhiteNoise?
    private let noiseFilter: LowPassFilter?
    private let noiseEnvelope: AmplitudeEnvelope?
    private let recipe: DayObjectsDrumRecipe

    init(recipe: DayObjectsDrumRecipe, sampleURL: URL?, preloadedSamplePlayer: AudioPlayer?) {
        precondition(recipe.synthesis.contains(.sinePitchDrop) == (recipe.sinePitchDrop != nil))
        precondition(
            recipe.synthesis.contains(.filteredNoise) ==
                (recipe.noiseFilterCutoffHz != nil && recipe.noiseAmplitude != nil)
        )
        self.recipe = recipe
        voice = recipe.voice
        if let player = preloadedSamplePlayer ?? sampleURL.flatMap({ AudioPlayer(url: $0, buffered: true) }) {
            samplePlayer = player
            let timePitch = TimePitch(player)
            sampleTimePitch = timePitch
            sampleTransient = LowPassFilter(timePitch, cutoffFrequency: AUValue(recipe.transientFilterCutoffHz ?? 22_050))
        } else {
            samplePlayer = nil
            sampleTimePitch = nil
            sampleTransient = nil
        }
        if recipe.synthesis.contains(.sinePitchDrop), let pitchDrop = recipe.sinePitchDrop {
            let sine = Oscillator(waveform: Table(.sine), frequency: AUValue(pitchDrop.startFrequencyHz), amplitude: 0)
            self.sine = sine
            sineEnvelope = AmplitudeEnvelope(sine, attackDuration: 0.001, decayDuration: 0.09, sustainLevel: 0, releaseDuration: 0.02)
        } else {
            sine = nil
            sineEnvelope = nil
        }
        if recipe.synthesis.contains(.filteredNoise), let noiseFilterCutoffHz = recipe.noiseFilterCutoffHz {
            let noise = WhiteNoise(amplitude: 0)
            self.noise = noise
            let filter = LowPassFilter(noise, cutoffFrequency: AUValue(noiseFilterCutoffHz))
            noiseFilter = filter
            noiseEnvelope = AmplitudeEnvelope(filter, attackDuration: 0.001, decayDuration: 0.045, sustainLevel: 0, releaseDuration: 0.01)
        } else {
            noise = nil
            noiseFilter = nil
            noiseEnvelope = nil
        }
        var inputs: [Node] = []
        if let sineEnvelope { inputs.append(sineEnvelope) }
        if let noiseEnvelope { inputs.append(noiseEnvelope) }
        if let sampleTransient {
            inputs.append(sampleTransient)
        }
        output = Fader(Mixer(inputs), gain: 0)
        sine?.start()
        noise?.start()
        graphLayout = .init(
            samplePlayerCount: samplePlayer == nil ? 0 : 1,
            sinePitchDropCount: sine == nil ? 0 : 1,
            filteredNoiseCount: noise == nil ? 0 : 1,
            transientFilterCutoffHz: sampleTransient == nil ? nil : recipe.transientFilterCutoffHz,
            noiseFilterCutoffHz: noiseFilter == nil ? nil : recipe.noiseFilterCutoffHz,
            allocatedNodeCount: (samplePlayer == nil ? 0 : 3) + (sine == nil ? 0 : 2) + (noise == nil ? 0 : 3) + 2
        )
    }

    func play(_ hit: DayObjectsDrumHit) {
        guard output.avAudioNode.engine?.isRunning == true else { return }
        output.gain = AUValue(hit.velocity)
        samplePlayer?.stop()
        samplePlayer?.volume = AUValue(hit.velocity)
        sampleTimePitch?.rate = AUValue(hit.pitchRate)
        samplePlayer?.play()
        if let pitchDrop = recipe.sinePitchDrop, let sine, let sineEnvelope {
            sine.amplitude = AUValue(pitchDrop.amplitude)
            sine.frequency = AUValue(pitchDrop.startFrequencyHz)
            sine.$frequency.ramp(to: AUValue(pitchDrop.endFrequencyHz), duration: 0.09)
            sineEnvelope.openGate()
        }
        if let noise, let noiseEnvelope, let noiseAmplitude = recipe.noiseAmplitude {
            noise.amplitude = AUValue(noiseAmplitude)
            noiseEnvelope.openGate()
        }
    }

    func stop() {
        output.gain = 0
        samplePlayer?.stop()
        sine?.amplitude = 0
        sineEnvelope?.closeGate()
        noise?.amplitude = 0
        noiseEnvelope?.closeGate()
    }
}
#endif
