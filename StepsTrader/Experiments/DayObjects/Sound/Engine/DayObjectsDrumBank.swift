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
                voice: voice, primarySample: nil, fallbackSample: nil, synthesis: [.filteredNoise], overlapCount: 2,
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
            voice: voice, primarySample: .bassDrum, fallbackSample: nil, synthesis: [.sinePitchDrop], overlapCount: overlapCount,
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
            voice: voice, primarySample: primarySample, fallbackSample: fallback, synthesis: [], overlapCount: overlapCount,
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

protocol DayObjectsDrumPlayerBackend: AnyObject {
    func play(_ hit: DayObjectsDrumHit)
}

final class DayObjectsDrumBank {
    typealias ResourceResolver = (DayObjectsDrumSample) -> URL?
    typealias PlayerFactory = (DayObjectsDrumRecipe, URL?) -> any DayObjectsDrumPlayerBackend

    private struct Slot {
        let player: any DayObjectsDrumPlayerBackend
        var hitIndex = 0
    }

    private let resolvedSamples: [DayObjectsDrumSample: URL]
    private let resolvedVoiceSamples: [DayObjectsDrumVoice: DayObjectsDrumSample]
    private var slots: [DayObjectsDrumVoice: [Slot]] = [:]
    private(set) var diagnostics: [DayObjectsDrumDiagnostic] = []

    var metrics: DayObjectsDrumBankMetrics {
        .init(allocatedPlayerCount: slots.values.reduce(0) { $0 + $1.count }, enabledVoiceCount: slots.count)
    }

    var preloadedSampleCount: Int { resolvedSamples.count }

    init(resourceResolver: @escaping ResourceResolver, playerFactory: PlayerFactory) {
        var samples: [DayObjectsDrumSample: URL] = [:]
        for sample in DayObjectsDrumSample.allCases {
            if let url = resourceResolver(sample) {
                samples[sample] = url
            }
        }
        resolvedSamples = samples

        var voiceSamples: [DayObjectsDrumVoice: DayObjectsDrumSample] = [:]
        for voice in DayObjectsDrumVoice.allCases {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)
            guard let primary = recipe.primarySample else {
                voiceSamples[voice] = nil
                continue
            }
            if samples[primary] != nil {
                voiceSamples[voice] = primary
            } else {
                diagnostics.append(.init(id: "day-objects.drum.resource-missing.\(Self.diagnosticComponent(primary))", voice: voice))
                if let fallback = recipe.fallbackSample, samples[fallback] != nil {
                    voiceSamples[voice] = fallback
                } else {
                    diagnostics.append(.init(id: "day-objects.drum.voice-disabled.\(voice.rawValue)", voice: voice))
                    continue
                }
            }
            slots[voice] = (0..<recipe.overlapCount).map { _ in
                Slot(player: playerFactory(recipe, samples[voiceSamples[voice] ?? primary]))
            }
        }

        for voice in DayObjectsDrumVoice.allCases where DayObjectsDrumRecipe.recipe(for: voice).primarySample == nil {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)
            slots[voice] = (0..<recipe.overlapCount).map { _ in Slot(player: playerFactory(recipe, nil)) }
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
        let recipe = DayObjectsDrumRecipe.recipe(for: voice)
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

    private static func diagnosticComponent(_ sample: DayObjectsDrumSample) -> String {
        sample.rawValue
            .replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }
}

final class DayObjectsAudioKitDrumBank {
    let bank: DayObjectsDrumBank
    let output: Mixer

    private let players: [DayObjectsAudioKitDrumPlayer]
    private let preloadedSamples: [DayObjectsDrumSample: AudioPlayer]

    init(resourceResolver: @escaping DayObjectsDrumBank.ResourceResolver) {
        var builtPlayers: [DayObjectsAudioKitDrumPlayer] = []
        var loadedSamples: [DayObjectsDrumSample: AudioPlayer] = [:]
        let preload: DayObjectsDrumBank.ResourceResolver = { sample in
            guard let url = resourceResolver(sample), let player = AudioPlayer(url: url, buffered: true) else { return nil }
            loadedSamples[sample] = player
            return url
        }
        bank = DayObjectsDrumBank(resourceResolver: preload) { recipe, sampleURL in
            let player = DayObjectsAudioKitDrumPlayer(recipe: recipe, sampleURL: sampleURL)
            builtPlayers.append(player)
            return player
        }
        players = builtPlayers
        preloadedSamples = loadedSamples
        output = Mixer(builtPlayers.map(\.output), name: "Day Objects drums")
    }
}

private final class DayObjectsAudioKitDrumPlayer: DayObjectsDrumPlayerBackend {
    let output: Fader

    private let samplePlayer: AudioPlayer?
    private let sampleTimePitch: TimePitch?
    private let sampleTransient: LowPassFilter?
    private let sine = Oscillator(waveform: Table(.sine), frequency: 130, amplitude: 0)
    private let sineEnvelope: AmplitudeEnvelope
    private let noise = WhiteNoise(amplitude: 0)
    private let noiseFilter: LowPassFilter
    private let noiseEnvelope: AmplitudeEnvelope

    init(recipe: DayObjectsDrumRecipe, sampleURL: URL?) {
        if let sampleURL, let player = AudioPlayer(url: sampleURL, buffered: true) {
            samplePlayer = player
            let timePitch = TimePitch(player)
            sampleTimePitch = timePitch
            sampleTransient = LowPassFilter(timePitch, cutoffFrequency: AUValue(recipe.transientFilterCutoffHz ?? 22_050))
        } else {
            samplePlayer = nil
            sampleTimePitch = nil
            sampleTransient = nil
        }
        sineEnvelope = AmplitudeEnvelope(sine, attackDuration: 0.001, decayDuration: 0.09, sustainLevel: 0, releaseDuration: 0.02)
        noiseFilter = LowPassFilter(noise, cutoffFrequency: 7_200)
        noiseEnvelope = AmplitudeEnvelope(noiseFilter, attackDuration: 0.001, decayDuration: 0.045, sustainLevel: 0, releaseDuration: 0.01)
        var inputs: [Node] = [sineEnvelope, noiseEnvelope]
        if let sampleTransient {
            inputs.append(sampleTransient)
        }
        output = Fader(Mixer(inputs), gain: 0)
        sine.start()
        noise.start()
    }

    func play(_ hit: DayObjectsDrumHit) {
        output.gain = AUValue(hit.velocity)
        samplePlayer?.stop()
        samplePlayer?.volume = AUValue(hit.velocity)
        sampleTimePitch?.rate = AUValue(hit.pitchRate)
        samplePlayer?.play()
        switch hit.voice {
        case .kickSoft, .kickFull:
            sine.amplitude = hit.voice == .kickFull ? 0.8 : 0.55
            sine.frequency = hit.voice == .kickFull ? 140 : 110
            sine.$frequency.ramp(to: hit.voice == .kickFull ? 46 : 52, duration: 0.09)
            sineEnvelope.openGate()
        case .shaker:
            noise.amplitude = 0.22
            noiseFilter.cutoffFrequency = 7_200
            noiseEnvelope.openGate()
        default:
            break
        }
    }
}
#endif
