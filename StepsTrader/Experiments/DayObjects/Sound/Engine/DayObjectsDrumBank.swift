#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
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
    let highPassCutoffHz: Double
    let outputTrimDecibels: Double
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
                transientFilterCutoffHz: nil, noiseFilterCutoffHz: 7_200, highPassCutoffHz: 110, outputTrimDecibels: 0, variation: .percussion,
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
            transientFilterCutoffHz: 4_000, noiseFilterCutoffHz: nil, highPassCutoffHz: 28, outputTrimDecibels: 0, variation: .none,
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
            transientFilterCutoffHz: 9_000, noiseFilterCutoffHz: nil, highPassCutoffHz: 110, outputTrimDecibels: 0, variation: variation,
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
    let scheduledHostTimeSeconds: TimeInterval
    let microtimingMilliseconds: Double
    let roomSend: Double
    let stereoOffset: Double
}

struct DayObjectsScheduledDrumHit: Equatable, Sendable {
    let voice: DayObjectsDrumVoice
    let velocity: Double
    let scheduledHostTimeSeconds: TimeInterval
    let microtimingMilliseconds: Double
    let roomSend: Double
    let stereoOffset: Double
    let pitchDriftCents: Double
}

struct DayObjectsDrumBankMetrics: Equatable, Sendable {
    let allocatedPlayerCount: Int
    let enabledVoiceCount: Int
    let activePlayerCount: Int

    init(allocatedPlayerCount: Int, enabledVoiceCount: Int, activePlayerCount: Int = 0) {
        self.allocatedPlayerCount = allocatedPlayerCount
        self.enabledVoiceCount = enabledVoiceCount
        self.activePlayerCount = activePlayerCount
    }
}

enum DayObjectsDrumGraphStage: Equatable, Sendable {
    case source
    case highPass
    case pan
    case preRoomTrim
    case room
    case unityOutput
}

struct DayObjectsDrumGraphLayout: Equatable, Sendable {
    let samplePlayerCount: Int
    let sinePitchDropCount: Int
    let filteredNoiseCount: Int
    let transientFilterCutoffHz: Double?
    let noiseFilterCutoffHz: Double?
    let highPassCutoffHz: Double?
    let outputTrimDecibels: Double
    let finalOutputGain: Double
    let signalPath: [DayObjectsDrumGraphStage]
    let allocatedNodeCount: Int

    static let empty = DayObjectsDrumGraphLayout(
        samplePlayerCount: 0, sinePitchDropCount: 0, filteredNoiseCount: 0,
        transientFilterCutoffHz: nil, noiseFilterCutoffHz: nil,
        highPassCutoffHz: nil, outputTrimDecibels: 0, finalOutputGain: 1,
        signalPath: [], allocatedNodeCount: 0
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
    var isActive: Bool { get }
    func play(_ hit: DayObjectsDrumHit)
    func stop()
}

extension DayObjectsDrumPlayerBackend {
    var isActive: Bool { false }
    func stop() {}
}

enum DayObjectsDrumScheduledLayer: Hashable, Sendable {
    // Kept as diagnostic labels so tests can prove hit velocity never reaches
    // the post-room output stage.
    case outputGainLeft
    case outputGainRight
    case preRoomGainLeft
    case preRoomGainRight
    case stereo
    case roomSend
    case samplePitch
    case sampleTransient
    case sineAmplitude
    case sinePitchDrop
    case sineEnvelope
    case noiseAmplitude
    case noiseEnvelope
}

struct DayObjectsDrumLayerScheduleEvent: Equatable, Sendable {
    let layer: DayObjectsDrumScheduledLayer
    let hostTimeSeconds: TimeInterval
    let value: Double?

    init(layer: DayObjectsDrumScheduledLayer, hostTimeSeconds: TimeInterval, value: Double? = nil) {
        self.layer = layer
        self.hostTimeSeconds = hostTimeSeconds
        self.value = value
    }
}

protocol DayObjectsDrumLayerScheduling: AnyObject {
    func isReady(output: Node) -> Bool
    func scheduleSample(
        _ player: AudioPlayer,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    )
    func scheduleGate(
        _ envelope: AmplitudeEnvelope,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    )
    func scheduleParameter(
        _ parameter: NodeParameter,
        value: AUValue,
        rampDuration: TimeInterval,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    )
    func scheduleAUParameter(
        _ node: Node,
        address: AUParameterAddress,
        value: AUValue,
        range: ClosedRange<AUValue>,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    )
    func stop(_ player: AudioPlayer?)
    func closeGate(_ envelope: AmplitudeEnvelope?)
}

enum DayObjectsDrumLayerDelivery: Equatable, Sendable {
    case immediate
    case scheduled(sampleOffset: UInt64)
}

final class DayObjectsAudioKitDrumLayerScheduler: DayObjectsDrumLayerScheduling {
    typealias HostTimeProvider = () -> TimeInterval
    typealias SampleRateProvider = () -> Double

    private let hostTimeProvider: HostTimeProvider
    private let sampleRateProvider: SampleRateProvider

    init(
        hostTimeProvider: @escaping HostTimeProvider = {
            TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        },
        sampleRateProvider: @escaping SampleRateProvider = { Settings.sampleRate }
    ) {
        self.hostTimeProvider = hostTimeProvider
        self.sampleRateProvider = sampleRateProvider
    }

    func isReady(output: Node) -> Bool {
        output.avAudioNode.engine?.isRunning == true
    }

    func delivery(atHostTime hostTimeSeconds: TimeInterval) -> DayObjectsDrumLayerDelivery {
        let delta = hostTimeSeconds - hostTimeProvider()
        guard hostTimeSeconds > 0, delta > 0 else { return .immediate }
        return .scheduled(sampleOffset: UInt64((delta * sampleRateProvider()).rounded()))
    }

    func scheduleSample(
        _ player: AudioPlayer,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        switch delivery(atHostTime: hostTimeSeconds) {
        case .immediate:
            player.play()
        case .scheduled:
            player.play(at: AVAudioTime.secondsToAudioTime(hostTime: 0, time: hostTimeSeconds))
        }
    }

    func scheduleGate(
        _ envelope: AmplitudeEnvelope,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        switch delivery(atHostTime: hostTimeSeconds) {
        case .immediate:
            envelope.openGate()
        case let .scheduled(sampleOffset):
            envelope.scheduleMIDIEvent(
                event: MIDIEvent(noteOn: 64, velocity: 127, channel: 0),
                offset: sampleOffset
            )
        }
    }

    func scheduleParameter(
        _ parameter: NodeParameter,
        value: AUValue,
        rampDuration: TimeInterval,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        switch delivery(atHostTime: hostTimeSeconds) {
        case .immediate:
            if rampDuration > 0 {
                parameter.ramp(to: value, duration: Float(rampDuration))
            } else {
                parameter.value = value
            }
        case let .scheduled(sampleOffset):
            let boundedValue = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
            parameter.avAudioNode.auAudioUnit.scheduleParameterBlock(
                AUEventSampleTimeImmediate + AUEventSampleTime(sampleOffset),
                AUAudioFrameCount(max(0, rampDuration) * sampleRateProvider()),
                parameter.parameter.address,
                boundedValue
            )
        }
    }

    func scheduleAUParameter(
        _ node: Node,
        address: AUParameterAddress,
        value: AUValue,
        range: ClosedRange<AUValue>,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        let boundedValue = min(max(value, range.lowerBound), range.upperBound)
        switch delivery(atHostTime: hostTimeSeconds) {
        case .immediate:
            node.avAudioNode.auAudioUnit.scheduleParameterBlock(
                AUEventSampleTimeImmediate,
                0,
                address,
                boundedValue
            )
        case let .scheduled(sampleOffset):
            node.avAudioNode.auAudioUnit.scheduleParameterBlock(
                AUEventSampleTimeImmediate + AUEventSampleTime(sampleOffset),
                0,
                address,
                boundedValue
            )
        }
    }

    func stop(_ player: AudioPlayer?) { player?.stop() }
    func closeGate(_ envelope: AmplitudeEnvelope?) { envelope?.closeGate() }
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
        .init(
            allocatedPlayerCount: slots.values.reduce(0) { $0 + $1.count },
            enabledVoiceCount: slots.count,
            activePlayerCount: slots.values.flatMap { $0 }.filter { $0.player.isActive }.count
        )
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
        voiceSlots[slotID].player.play(.init(
            voice: voice,
            velocity: boundedVelocity,
            pitchRate: pitchRate,
            scheduledHostTimeSeconds: 0,
            microtimingMilliseconds: 0,
            roomSend: 0,
            stereoOffset: 0
        ))
        voiceSlots[0].hitIndex &+= 1
        slots[voice] = voiceSlots
    }

    /// Playback-plan path. All expressive values are authoritative and are
    /// applied exactly once; audition-only recipe variation is not added.
    func schedule(_ request: DayObjectsScheduledDrumHit) {
        guard var voiceSlots = slots[request.voice], !voiceSlots.isEmpty else { return }
        let slotID = voiceSlots[0].hitIndex % voiceSlots.count
        voiceSlots[slotID].player.play(.init(
            voice: request.voice,
            velocity: min(max(request.velocity, 0), 1),
            pitchRate: pow(2, min(max(request.pitchDriftCents, -3), 3) / 1_200),
            scheduledHostTimeSeconds: max(0, request.scheduledHostTimeSeconds),
            microtimingMilliseconds: request.microtimingMilliseconds,
            roomSend: min(max(request.roomSend, 0), 1),
            stereoOffset: min(max(request.stereoOffset, -1), 1)
        ))
        voiceSlots[0].hitIndex &+= 1
        slots[request.voice] = voiceSlots
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
            (voice, players.first { $0.voice == voice }?.graphLayout ?? .empty)
        })
        return .init(
            preloadedSampleCount: preparedSampleCount,
            fixedPlayerCount: players.count,
            allocatedNodeCount: preloadedSamples.count + players.reduce(0) { $0 + $1.graphLayout.allocatedNodeCount },
            layouts: layouts
        )
    }

    init(
        resourceResolver: @escaping DayObjectsDrumBank.ResourceResolver,
        recipes: [DayObjectsDrumVoice: DayObjectsDrumRecipe]? = nil,
        hostTimeProvider: @escaping DayObjectsAudioKitDrumPlayer.HostTimeProvider = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        var builtPlayers: [DayObjectsAudioKitDrumPlayer] = []
        var loadedSamples: [DayObjectsDrumSample: AudioPlayer] = [:]
        var loadedSampleCount = 0
        let layerScheduler = DayObjectsAudioKitDrumLayerScheduler(
            hostTimeProvider: hostTimeProvider
        )
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
                preloadedSamplePlayer: preloadedSamplePlayer,
                layerScheduler: layerScheduler,
                hostTimeProvider: hostTimeProvider
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

final class DayObjectsAudioKitDrumPlayer: DayObjectsDrumPlayerBackend {
    typealias HostTimeProvider = () -> TimeInterval

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
    private let highPass: HighPassFilter
    private let trim: Fader
    private let outputTrimGain: AUValue
    private let recipe: DayObjectsDrumRecipe
    private let panner: Panner
    private let room: Reverb
    private let layerScheduler: any DayObjectsDrumLayerScheduling
    private let hostTimeProvider: HostTimeProvider
    private var activeUntilHostTimeSeconds = -Double.infinity
    var isActive: Bool {
        // AudioPlayer updates this state from its data-played-back callback, so
        // sample-backed Rhythm voices leave the meter count when their one-shot
        // really completes instead of remaining sticky until transport stop.
        samplePlayer?.isPlaying == true || hostTimeProvider() < activeUntilHostTimeSeconds
    }

    init(
        recipe: DayObjectsDrumRecipe,
        sampleURL: URL?,
        preloadedSamplePlayer: AudioPlayer?,
        layerScheduler: any DayObjectsDrumLayerScheduling = DayObjectsAudioKitDrumLayerScheduler(),
        hostTimeProvider: @escaping HostTimeProvider = { ProcessInfo.processInfo.systemUptime }
    ) {
        precondition(recipe.synthesis.contains(.sinePitchDrop) == (recipe.sinePitchDrop != nil))
        precondition(
            recipe.synthesis.contains(.filteredNoise) ==
                (recipe.noiseFilterCutoffHz != nil && recipe.noiseAmplitude != nil)
        )
        self.recipe = recipe
        self.layerScheduler = layerScheduler
        self.hostTimeProvider = hostTimeProvider
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
        highPass = HighPassFilter(Mixer(inputs), cutoffFrequency: AUValue(recipe.highPassCutoffHz), resonance: 0)
        panner = Panner(highPass, pan: 0)
        outputTrimGain = AUValue(pow(10, recipe.outputTrimDecibels / 20))
        trim = Fader(panner, gain: 0)
        room = Reverb(trim, dryWetMix: 0)
        output = Fader(room, gain: 1)
        sine?.start()
        noise?.start()
        graphLayout = .init(
            samplePlayerCount: samplePlayer == nil ? 0 : 1,
            sinePitchDropCount: sine == nil ? 0 : 1,
            filteredNoiseCount: noise == nil ? 0 : 1,
            transientFilterCutoffHz: sampleTransient == nil ? nil : recipe.transientFilterCutoffHz,
            noiseFilterCutoffHz: noiseFilter == nil ? nil : recipe.noiseFilterCutoffHz,
            highPassCutoffHz: recipe.highPassCutoffHz,
            outputTrimDecibels: recipe.outputTrimDecibels,
            finalOutputGain: 1,
            signalPath: [.source, .highPass, .pan, .preRoomTrim, .room, .unityOutput],
            allocatedNodeCount: (samplePlayer == nil ? 0 : 3) + (sine == nil ? 0 : 2) + (noise == nil ? 0 : 3) + 6
        )
    }

    func play(_ hit: DayObjectsDrumHit) {
        guard layerScheduler.isReady(output: output) else { return }
        let hostTime = hit.scheduledHostTimeSeconds
        let now = hostTimeProvider()
        let activeStart = hostTime > now ? hostTime : now
        let sampleDuration = (samplePlayer?.duration ?? 0) / max(hit.pitchRate, 1.0 / 32.0)
        let synthesisDuration = recipe.synthesis.contains(.sinePitchDrop) ? 0.12
            : (recipe.synthesis.contains(.filteredNoise) ? 0.08 : 0)
        activeUntilHostTimeSeconds = max(
            activeUntilHostTimeSeconds,
            activeStart + max(sampleDuration, synthesisDuration)
        )
        let preRoomGain = AUValue(hit.velocity) * outputTrimGain
        layerScheduler.scheduleParameter(trim.$leftGain, value: preRoomGain, rampDuration: 0, layer: .preRoomGainLeft, atHostTime: hostTime)
        layerScheduler.scheduleParameter(trim.$rightGain, value: preRoomGain, rampDuration: 0, layer: .preRoomGainRight, atHostTime: hostTime)
        layerScheduler.scheduleParameter(panner.$pan, value: AUValue(hit.stereoOffset), rampDuration: 0, layer: .stereo, atHostTime: hostTime)
        // Apple's reverb exposes wet/dry mix at Audio Unit parameter address 0.
        layerScheduler.scheduleAUParameter(room, address: 0, value: AUValue(hit.roomSend * 100), range: 0...100, layer: .roomSend, atHostTime: hostTime)
        layerScheduler.stop(samplePlayer)
        samplePlayer?.volume = 1
        if let sampleTimePitch {
            layerScheduler.scheduleAUParameter(sampleTimePitch, address: AUParameterAddress(kNewTimePitchParam_Rate), value: AUValue(hit.pitchRate), range: 1.0 / 32.0...32, layer: .samplePitch, atHostTime: hostTime)
        }
        if let samplePlayer {
            layerScheduler.scheduleSample(samplePlayer, layer: .sampleTransient, atHostTime: hostTime)
        }
        if let pitchDrop = recipe.sinePitchDrop, let sine, let sineEnvelope {
            layerScheduler.scheduleParameter(sine.$amplitude, value: AUValue(pitchDrop.amplitude), rampDuration: 0, layer: .sineAmplitude, atHostTime: hostTime)
            layerScheduler.scheduleParameter(sine.$frequency, value: AUValue(pitchDrop.startFrequencyHz * hit.pitchRate), rampDuration: 0, layer: .sinePitchDrop, atHostTime: hostTime)
            layerScheduler.scheduleParameter(sine.$frequency, value: AUValue(pitchDrop.endFrequencyHz * hit.pitchRate), rampDuration: 0.09, layer: .sinePitchDrop, atHostTime: hostTime)
            layerScheduler.scheduleGate(sineEnvelope, layer: .sineEnvelope, atHostTime: hostTime)
        }
        if let noise, let noiseEnvelope, let noiseAmplitude = recipe.noiseAmplitude {
            layerScheduler.scheduleParameter(noise.$amplitude, value: AUValue(noiseAmplitude), rampDuration: 0, layer: .noiseAmplitude, atHostTime: hostTime)
            layerScheduler.scheduleGate(noiseEnvelope, layer: .noiseEnvelope, atHostTime: hostTime)
        }
    }

    func stop() {
        activeUntilHostTimeSeconds = -.infinity
        // Keep the post-room output at unity so stopping a new source cannot
        // cut any tail already draining through the room.
        output.gain = 1
        trim.gain = 0
        layerScheduler.stop(samplePlayer)
        sine?.amplitude = 0
        layerScheduler.closeGate(sineEnvelope)
        noise?.amplitude = 0
        layerScheduler.closeGate(noiseEnvelope)
    }
}
#endif
