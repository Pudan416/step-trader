#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AVFoundation
import Foundation
import SoundpipeAudioKit

enum HappeningPlaybackPriority: Int, Comparable, Sendable {
    case recurrence = 0
    case birth = 1
    case manualAudition = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct HappeningEffectCommand: Equatable, Sendable {
    let filterCutoffHz: Double
    let delayMix: Double
    let delayFeedback: Double
    let reverbMix: Double
}

enum HappeningSamplePoolError: Error, Equatable, Sendable {
    case recipeUnavailable(HappeningSoundRecipeID)
    case resourceUnavailable(String)
    case noEligibleVoice
}

struct HappeningSamplePoolMetrics: Equatable, Sendable {
    let allocatedPlayerCount: Int
    let fixedPlayerIdentities: [ObjectIdentifier]
    let activeVoiceCount: Int
    let releasingVoiceCount: Int
    let stealCount: Int
    let decodedBufferCount: Int
    let decodedByteCount: Int
    let availableRecipeIDs: Set<HappeningSoundRecipeID>
    let unavailableRecipeIDs: Set<HappeningSoundRecipeID>
    let effects: HappeningEffectCommand
    let lastEffectRampSeconds: TimeInterval

    static let inactive = HappeningSamplePoolMetrics(
        allocatedPlayerCount: 0,
        fixedPlayerIdentities: [],
        activeVoiceCount: 0,
        releasingVoiceCount: 0,
        stealCount: 0,
        decodedBufferCount: 0,
        decodedByteCount: 0,
        availableRecipeIDs: [],
        unavailableRecipeIDs: [],
        effects: .init(filterCutoffHz: 8_000, delayMix: 0, delayFeedback: 0, reverbMix: 0),
        lastEffectRampSeconds: 0
    )
}

@MainActor
protocol DayObjectsHappeningSamplePoolProtocol: AnyObject {
    var metrics: HappeningSamplePoolMetrics { get }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws
    @discardableResult
    func play(_ sound: ResolvedHappeningSound, gain: Double) throws -> Int
    @discardableResult
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority
    ) throws -> Int
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double)
    func stop(voiceID: Int)
    func releaseAll()
}

extension DayObjectsHappeningSamplePoolProtocol {
    @discardableResult
    func play(_ sound: ResolvedHappeningSound, gain: Double) throws -> Int {
        try play(sound, gain: gain, priority: .recurrence)
    }
}

struct DayObjectsHappeningDecodedBuffer {
    let buffer: AVAudioPCMBuffer
    let decodedByteCount: Int
}

@MainActor
protocol DayObjectsHappeningSampleVoiceBackend: AnyObject {
    var output: Node { get }
    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double
    )
    func release()
    func stop()
}

@MainActor
final class DayObjectsHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    typealias ResourceResolver = (String) -> URL?
    typealias BufferLoader = (URL) throws -> DayObjectsHappeningDecodedBuffer
    typealias VoiceFactory = (Int) -> DayObjectsHappeningSampleVoiceBackend

    static let voiceCount = 4
    static let maximumDecodedByteCount = 48 * 1_024 * 1_024

    let output: Mixer

    private let recipesByID: [HappeningSoundRecipeID: HappeningSoundRecipe]
    private let resourceResolver: ResourceResolver
    private let bufferLoader: BufferLoader
    private let voices: [DayObjectsHappeningSampleVoiceBackend]
    private let dryMixer: Mixer
    private let filter: LowPassFilter
    private let delay: VariableDelay
    private let reverb: CostelloReverb
    private var slots: [VoiceSlot]
    private var decodedBuffers: [String: DayObjectsHappeningDecodedBuffer] = [:]
    private var availableRecipeIDs: Set<HappeningSoundRecipeID> = []
    private var unavailableRecipeIDs: Set<HappeningSoundRecipeID> = []
    private var sequence: UInt64 = 0
    private var stealCount = 0
    private var currentEffects = HappeningEffectCommand(
        filterCutoffHz: 8_000,
        delayMix: 0.12,
        delayFeedback: 0.25,
        reverbMix: 0.12
    )
    private var lastEffectRampSeconds: TimeInterval = 0

    var metrics: HappeningSamplePoolMetrics {
        HappeningSamplePoolMetrics(
            allocatedPlayerCount: voices.count,
            fixedPlayerIdentities: voices.map(ObjectIdentifier.init),
            activeVoiceCount: slots.filter { $0.state.isActive }.count,
            releasingVoiceCount: slots.filter { $0.state.isReleased }.count,
            stealCount: stealCount,
            decodedBufferCount: decodedBuffers.count,
            decodedByteCount: decodedBuffers.values.reduce(0) { $0 + $1.decodedByteCount },
            availableRecipeIDs: availableRecipeIDs,
            unavailableRecipeIDs: unavailableRecipeIDs,
            effects: currentEffects,
            lastEffectRampSeconds: lastEffectRampSeconds
        )
    }

    convenience init(bundle: Bundle = .main) {
        self.init(
            recipes: HappeningSoundCatalog.recipes,
            resourceResolver: { resourceName in
                let path = resourceName as NSString
                return bundle.url(
                    forResource: path.deletingPathExtension,
                    withExtension: path.pathExtension
                )
            },
            bufferLoader: Self.decodeBuffer,
            voiceFactory: { DayObjectsAudioKitHappeningSampleVoice(voiceID: $0) }
        )
    }

    init(
        recipes: [HappeningSoundRecipe],
        resourceResolver: @escaping ResourceResolver,
        bufferLoader: @escaping BufferLoader,
        voiceFactory: @escaping VoiceFactory
    ) {
        recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.resourceResolver = resourceResolver
        self.bufferLoader = bufferLoader
        voices = (0..<Self.voiceCount).map(voiceFactory)
        slots = (0..<Self.voiceCount).map {
            VoiceSlot(voiceID: $0, state: .idle)
        }
        dryMixer = Mixer(voices.map(\.output), name: "Day Objects Happening voices")
        filter = LowPassFilter(dryMixer, cutoffFrequency: AUValue(currentEffects.filterCutoffHz))
        delay = VariableDelay(
            filter,
            time: 0.24,
            feedback: AUValue(currentEffects.delayFeedback),
            maximumTime: 2,
            dryWetMix: AUValue(currentEffects.delayMix)
        )
        reverb = CostelloReverb(
            delay,
            balance: AUValue(currentEffects.reverbMix),
            feedback: 0.72,
            cutoffFrequency: 8_000
        )
        output = Mixer([reverb], name: "Day Objects Happening bus")
    }

    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {
        for recipeID in recipeIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard !availableRecipeIDs.contains(recipeID) else { continue }
            guard let recipe = recipesByID[recipeID] else {
                unavailableRecipeIDs.insert(recipeID)
                continue
            }

            var pending: [String: DayObjectsHappeningDecodedBuffer] = [:]
            var didFail = false
            for source in recipe.sources {
                guard decodedBuffers[source.resourceName] == nil,
                      pending[source.resourceName] == nil else { continue }
                do {
                    guard let url = resourceResolver(source.resourceName) else {
                        throw HappeningSamplePoolError.resourceUnavailable(source.resourceName)
                    }
                    let decoded = try bufferLoader(url)
                    guard decoded.buffer.frameLength > 0,
                          decoded.decodedByteCount > 0,
                          currentDecodedByteCount + pending.values.reduce(0, { $0 + $1.decodedByteCount }) + decoded.decodedByteCount <= Self.maximumDecodedByteCount
                    else {
                        throw HappeningSamplePoolError.resourceUnavailable(source.resourceName)
                    }
                    pending[source.resourceName] = decoded
                } catch {
                    didFail = true
                    break
                }
            }

            if didFail {
                unavailableRecipeIDs.insert(recipeID)
                continue
            }
            decodedBuffers.merge(pending) { existing, _ in existing }
            availableRecipeIDs.insert(recipeID)
            unavailableRecipeIDs.remove(recipeID)
        }
    }

    @discardableResult
    func play(_ sound: ResolvedHappeningSound, gain: Double) throws -> Int {
        try play(sound, gain: gain, priority: .recurrence)
    }

    @discardableResult
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority
    ) throws -> Int {
        guard availableRecipeIDs.contains(sound.recipeID),
              let recipe = recipesByID[sound.recipeID] else {
            throw HappeningSamplePoolError.recipeUnavailable(sound.recipeID)
        }
        guard let decoded = decodedBuffers[sound.resourceName] else {
            throw HappeningSamplePoolError.resourceUnavailable(sound.resourceName)
        }
        let slotIndex = try selectSlot(for: priority)
        if slots[slotIndex].state.isActive {
            voices[slotIndex].stop()
            stealCount += 1
        } else if slots[slotIndex].state.isReleased {
            // A released envelope may still be draining; hard-stop it before
            // scheduling the next already-decoded buffer on the same player.
            voices[slotIndex].stop()
        }

        sequence &+= 1
        let requestedGain = gain.isFinite ? gain : 0
        let recipeGain = pow(10, recipe.gainDB / 20)
        let playbackGain = min(max(requestedGain * recipeGain, 0), 1)
        let rate = min(max(sound.playbackRate.isFinite ? sound.playbackRate : 1, 0.5), 2)
        if let resonantFilterHz = sound.resonantFilterHz {
            filter.cutoffFrequency = AUValue(Self.clampFilter(resonantFilterHz))
        }
        voices[slotIndex].play(
            buffer: decoded.buffer,
            playbackRate: rate,
            gain: playbackGain,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds
        )
        slots[slotIndex].state = .active(priority: priority, startOrder: sequence)
        return slots[slotIndex].voiceID
    }

    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {
        let sanitized = HappeningEffectCommand(
            filterCutoffHz: Self.clampFilter(command.filterCutoffHz),
            delayMix: Self.unit(command.delayMix),
            delayFeedback: min(
                Self.nonnegative(command.delayFeedback),
                DayObjectsAudioParameters.maximumDelayFeedback
            ),
            reverbMix: Self.unit(command.reverbMix)
        )
        let duration = min(Self.nonnegative(rampSeconds), 2)
        currentEffects = sanitized
        lastEffectRampSeconds = duration
        transition(filter.$cutoffFrequency, to: sanitized.filterCutoffHz, duration: duration)
        transition(delay.$dryWetMix, to: sanitized.delayMix, duration: duration)
        transition(delay.$feedback, to: sanitized.delayFeedback, duration: duration)
        transition(reverb.$balance, to: sanitized.reverbMix, duration: duration)
    }

    func stop(voiceID: Int) {
        guard let slotIndex = slots.firstIndex(where: { $0.voiceID == voiceID }),
              slots[slotIndex].state.isActive else { return }
        voices[slotIndex].release()
        sequence &+= 1
        slots[slotIndex].state = .released(order: sequence)
    }

    func releaseAll() {
        for index in voices.indices {
            voices[index].stop()
            sequence &+= 1
            slots[index].state = .released(order: sequence)
        }
    }

    private var currentDecodedByteCount: Int {
        decodedBuffers.values.reduce(0) { $0 + $1.decodedByteCount }
    }

    private func transition(_ parameter: NodeParameter, to value: Double, duration: TimeInterval) {
        let target = AUValue(value)
        guard duration > 0, parameter.parameter.flags.contains(.flag_CanRamp) else {
            parameter.value = target
            return
        }
        parameter.ramp(to: target, duration: Float(duration))
    }

    private func selectSlot(for priority: HappeningPlaybackPriority) throws -> Int {
        if let released = slots.indices
            .filter({ !slots[$0].state.isActive })
            .min(by: { slots[$0].state.releaseOrdering < slots[$1].state.releaseOrdering }) {
            return released
        }

        let eligible = slots.indices.filter {
            guard case let .active(existingPriority, _) = slots[$0].state else { return false }
            return existingPriority < priority
        }
        guard let selected = eligible.min(by: {
            slots[$0].state.activeOrdering < slots[$1].state.activeOrdering
        }) else {
            throw HappeningSamplePoolError.noEligibleVoice
        }
        return selected
    }

    private static func decodeBuffer(url: URL) throws -> DayObjectsHappeningDecodedBuffer {
        let file = try AVAudioFile(forReading: url)
        let frameCapacity = AVAudioFrameCount(file.length)
        guard frameCapacity > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCapacity
              ) else {
            throw HappeningSamplePoolError.resourceUnavailable(url.lastPathComponent)
        }
        try file.read(into: buffer)
        let stream = buffer.format.streamDescription.pointee
        let channelMultiplier = stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            ? 1
            : Int(buffer.format.channelCount)
        let bytes = Int(buffer.frameLength) * Int(stream.mBytesPerFrame) * channelMultiplier
        return .init(buffer: buffer, decodedByteCount: bytes)
    }

    private static func clampFilter(_ value: Double) -> Double {
        let minimum = 80.0
        let maximum = min(DayObjectsAudioParameters.maximumCutoffHz, 18_000)
        let finite = value.isFinite ? value : minimum
        return min(max(finite, minimum), maximum)
    }

    private static func unit(_ value: Double) -> Double {
        min(nonnegative(value), 1)
    }

    private static func nonnegative(_ value: Double) -> Double {
        max(value.isFinite ? value : 0, 0)
    }

    private struct VoiceSlot {
        let voiceID: Int
        var state: VoiceState
    }

    private enum VoiceState {
        case idle
        case released(order: UInt64)
        case active(priority: HappeningPlaybackPriority, startOrder: UInt64)

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }

        var isReleased: Bool {
            if case .released = self { return true }
            return false
        }

        var releaseOrdering: (Int, UInt64) {
            switch self {
            case .idle: return (0, 0)
            case let .released(order): return (1, order)
            case .active: return (.max, .max)
            }
        }

        var activeOrdering: (Int, UInt64) {
            guard case let .active(priority, startOrder) = self else { return (.max, .max) }
            return (priority.rawValue, startOrder)
        }
    }
}

@MainActor
private final class DayObjectsAudioKitHappeningSampleVoice: DayObjectsHappeningSampleVoiceBackend {
    var output: Node { outputFader }
    private let outputFader: Fader
    private let player = AudioPlayer()
    private let timePitch: TimePitch
    private let envelope: AmplitudeEnvelope

    init(voiceID: Int) {
        timePitch = TimePitch(player)
        envelope = AmplitudeEnvelope(
            timePitch,
            attackDuration: 0.01,
            decayDuration: 0.01,
            sustainLevel: 1,
            releaseDuration: 0.2
        )
        outputFader = Fader(envelope, gain: 1)
    }

    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double
    ) {
        player.buffer = buffer
        timePitch.rate = AUValue(playbackRate)
        envelope.attackDuration = AUValue(attackSeconds)
        envelope.releaseDuration = AUValue(releaseSeconds)
        outputFader.gain = AUValue(gain)
        guard outputFader.avAudioNode.engine?.isRunning == true else { return }
        player.play()
        envelope.openGate()
    }

    func release() { envelope.closeGate() }

    func stop() {
        envelope.closeGate()
        player.stop()
    }
}

@MainActor
final class DayObjectsInactiveHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    var metrics: HappeningSamplePoolMetrics { .inactive }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {}
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority
    ) throws -> Int {
        throw HappeningSamplePoolError.recipeUnavailable(sound.recipeID)
    }
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {}
    func stop(voiceID: Int) {}
    func releaseAll() {}
}
#endif
