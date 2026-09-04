#if DEBUG || INTERNAL_BUILD
import AudioKit
import AVFoundation
import Foundation

enum HappeningPlaybackPriority: Int, Comparable, Sendable {
    case recurrence = 0
    case birth = 1
    case manualAudition = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct HappeningPlaybackHandle: Equatable, Hashable, Sendable {
    let voiceID: Int
    let generation: UInt64
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
    let decodedBufferIdentities: [ObjectIdentifier]
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
        decodedBufferIdentities: [],
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
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand
    ) throws -> HappeningPlaybackHandle
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double)
    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double)
    func stop(_ handle: HappeningPlaybackHandle)
    func releaseAll()
}

struct DayObjectsHappeningDecodedBuffer {
    let buffer: AVAudioPCMBuffer
    let decodedByteCount: Int
    let playbackNormalizationGain: Double

    init(buffer: AVAudioPCMBuffer, decodedByteCount: Int) {
        self.buffer = buffer
        self.decodedByteCount = decodedByteCount
        playbackNormalizationGain = Self.normalizationGain(for: buffer)
    }

    private static func normalizationGain(for buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0,
              buffer.format.channelCount > 0 else { return 1 }
        let frameCount = min(
            Int(buffer.frameLength),
            max(1, Int((buffer.format.sampleRate * 0.25).rounded()))
        )
        let channelCount = Int(buffer.format.channelCount)
        var sumOfSquares = 0.0
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = Double(channels[channel][frame])
                sumOfSquares += sample * sample
            }
        }
        let rms = sqrt(sumOfSquares / Double(frameCount * channelCount))
        guard rms.isFinite, rms > 0 else { return 1 }
        let targetRMS = pow(10, -25.0 / 20)
        return min(targetRMS / rms, 1)
    }
}

@MainActor
protocol DayObjectsHappeningSampleVoiceBackend: AnyObject {
    var output: Node { get }
    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double,
        resonantFilterHz: Double?
    )
    func update(gain: Double, playbackRate: Double, rampSeconds: Double)
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
    private let clock: () -> TimeInterval
    private let dryMixer: Mixer
    private let filter: LowPassFilter
    private let delay: Delay
    private let directGain: DayObjectsAppleGainNode
    private let reverb: Reverb
    private let reverbWet: DayObjectsAppleGainNode
    private var slots: [VoiceSlot]
    private var decodedBuffers: [String: DayObjectsHappeningDecodedBuffer] = [:]
    private var availableRecipeIDs: Set<HappeningSoundRecipeID> = []
    private var unavailableRecipeIDs: Set<HappeningSoundRecipeID> = []
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0
    private var stealCount = 0
    private static let defaultEffects = HappeningEffectCommand(
        filterCutoffHz: 7_200,
        delayMix: 0.04,
        delayFeedback: 0.12,
        reverbMix: 0.84
    )
    private static let ambientHeadroomGain = pow(10, -4.5 / 20)
    private var currentEffects = defaultEffects
    private var lastEffectRampSeconds: TimeInterval = 0

    var metrics: HappeningSamplePoolMetrics {
        refreshReleasedSlots()
        return HappeningSamplePoolMetrics(
            allocatedPlayerCount: voices.count,
            fixedPlayerIdentities: voices.map(ObjectIdentifier.init),
            activeVoiceCount: slots.filter { $0.state.isActive }.count,
            releasingVoiceCount: slots.filter { $0.state.isReleased }.count,
            stealCount: stealCount,
            decodedBufferCount: decodedBuffers.count,
            decodedBufferIdentities: decodedBuffers.keys.sorted().compactMap {
                decodedBuffers[$0].map { ObjectIdentifier($0.buffer) }
            },
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
        voiceFactory: @escaping VoiceFactory,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.resourceResolver = resourceResolver
        self.bufferLoader = bufferLoader
        self.clock = clock
        voices = (0..<Self.voiceCount).map(voiceFactory)
        slots = (0..<Self.voiceCount).map {
            VoiceSlot(voiceID: $0, state: .idle)
        }
        dryMixer = Mixer(voices.map(\.output), name: "Day Objects Happening voices")
        filter = LowPassFilter(dryMixer, cutoffFrequency: AUValue(currentEffects.filterCutoffHz))
        delay = Delay(
            filter,
            time: 0.24,
            feedback: AUValue(currentEffects.delayFeedback * 100),
            lowPassCutoff: 18_000,
            dryWetMix: AUValue(currentEffects.delayMix * 100)
        )
        directGain = DayObjectsAppleGainNode(
            input: delay,
            gain: Self.directPresence(for: currentEffects.reverbMix)
        )
        reverb = Reverb(delay, dryWetMix: 1)
        reverb.loadFactoryPreset(.cathedral)
        reverbWet = DayObjectsAppleGainNode(input: reverb, gain: currentEffects.reverbMix)
        output = Mixer([directGain, reverbWet], name: "Day Objects Happening bus")
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
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand
    ) throws -> HappeningPlaybackHandle {
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
        generation &+= 1
        let handle = HappeningPlaybackHandle(
            voiceID: slots[slotIndex].voiceID,
            generation: generation
        )
        let requestedGain = gain.isFinite ? gain : 0
        // The bank's full-event RMS is intentionally diverse, but its short
        // attacks need one common ceiling so switching recipes never jumps in
        // perceived loudness. Quiet sources are never boosted.
        let playbackGainScale = decoded.playbackNormalizationGain * Self.ambientHeadroomGain
        let playbackGain = min(max(requestedGain * playbackGainScale, 0), 1)
        let rate = min(max(sound.playbackRate.isFinite ? sound.playbackRate : 1, 0.5), 2)
        slots[slotIndex].state = .active(
            handle: handle,
            priority: priority,
            startOrder: sequence,
            releaseSeconds: recipe.releaseSeconds,
            effects: Self.sanitizedEffects(effects),
            playbackGainScale: playbackGainScale
        )
        recomputeRecipeEffects()
        voices[slotIndex].play(
            buffer: decoded.buffer,
            playbackRate: rate,
            gain: playbackGain,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds,
            resonantFilterHz: sound.resonantFilterHz
        )
        return handle
    }

    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {
        let sanitized = Self.sanitizedEffects(command)
        let duration = min(Self.nonnegative(rampSeconds), 2)
        applyEffectsToBus(sanitized, duration: duration)
    }

    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {
        guard let slotIndex = slotIndex(matching: handle),
              case let .active(_, _, _, _, _, playbackGainScale) = slots[slotIndex].state else { return }
        let requestedGain = gain.isFinite ? gain : 0
        let boundedGain = min(max(requestedGain * playbackGainScale, 0), 1)
        let boundedRate = min(max(playbackRate.isFinite ? playbackRate : 1, 0.5), 2)
        voices[slotIndex].update(
            gain: boundedGain,
            playbackRate: boundedRate,
            rampSeconds: 0.08
        )
    }

    func stop(_ handle: HappeningPlaybackHandle) {
        guard let slotIndex = slotIndex(matching: handle),
              case let .active(_, _, _, releaseSeconds, effects, _) = slots[slotIndex].state else { return }
        voices[slotIndex].release()
        sequence &+= 1
        slots[slotIndex].state = .released(
            order: sequence,
            deadline: clock() + releaseSeconds,
            effects: effects
        )
        recomputeRecipeEffects()
        refreshReleasedSlots()
    }

    private func applyEffectsToBus(_ sanitized: HappeningEffectCommand, duration: Double) {
        currentEffects = sanitized
        lastEffectRampSeconds = duration
        transition(filter.$cutoffFrequency, to: sanitized.filterCutoffHz, duration: duration)
        transition(delay.$dryWetMix, to: sanitized.delayMix * 100, duration: duration)
        transition(delay.$feedback, to: sanitized.delayFeedback * 100, duration: duration)
        directGain.setLinearGain(Self.directPresence(for: sanitized.reverbMix), rampSeconds: duration)
        reverbWet.setLinearGain(sanitized.reverbMix, rampSeconds: duration)
    }

    private static func directPresence(for reverbMix: Double) -> Double {
        let boundedMix = min(max(reverbMix, 0), 1)
        return max(pow(1 - boundedMix, 1.6), 0.06)
    }

    func releaseAll() {
        for index in voices.indices {
            voices[index].stop()
            slots[index].state = .idle
        }
        recomputeRecipeEffects()
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
        refreshReleasedSlots()
        if let released = slots.indices
            .filter({ !slots[$0].state.isActive })
            .min(by: { slots[$0].state.releaseOrdering < slots[$1].state.releaseOrdering }) {
            return released
        }

        let eligible = slots.indices.filter {
            guard case let .active(_, existingPriority, _, _, _, _) = slots[$0].state else { return false }
            return existingPriority < priority
        }
        guard let selected = eligible.min(by: {
            slots[$0].state.activeOrdering < slots[$1].state.activeOrdering
        }) else {
            throw HappeningSamplePoolError.noEligibleVoice
        }
        return selected
    }

    private func slotIndex(matching handle: HappeningPlaybackHandle) -> Int? {
        slots.firstIndex { slot in
            guard case let .active(activeHandle, _, _, _, _, _) = slot.state else { return false }
            return activeHandle == handle
        }
    }

    private func recomputeRecipeEffects() {
        let contributions = slots.compactMap { slot -> HappeningEffectCommand? in
            switch slot.state {
            case let .active(_, _, _, _, effects, _),
                 let .released(_, _, effects):
                return effects
            case .idle:
                return nil
            }
        }.sorted(by: Self.effectOrdering)
        guard contributions.isEmpty == false else {
            applyEffectsToBus(Self.defaultEffects, duration: 0)
            return
        }
        let divisor = Double(contributions.count)
        let aggregate = HappeningEffectCommand(
            filterCutoffHz: contributions.reduce(0) { $0 + $1.filterCutoffHz } / divisor,
            delayMix: contributions.reduce(0) { $0 + $1.delayMix } / divisor,
            delayFeedback: contributions.reduce(0) { $0 + $1.delayFeedback } / divisor,
            reverbMix: contributions.reduce(0) { $0 + $1.reverbMix } / divisor
        )
        applyEffectsToBus(aggregate, duration: 0)
    }

    private static func sanitizedEffects(_ command: HappeningEffectCommand) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: clampFilter(command.filterCutoffHz),
            delayMix: unit(command.delayMix),
            delayFeedback: min(
                nonnegative(command.delayFeedback),
                DayObjectsAudioParameters.maximumDelayFeedback
            ),
            reverbMix: unit(command.reverbMix)
        )
    }

    private static func effectOrdering(_ lhs: HappeningEffectCommand, _ rhs: HappeningEffectCommand) -> Bool {
        if lhs.filterCutoffHz != rhs.filterCutoffHz { return lhs.filterCutoffHz < rhs.filterCutoffHz }
        if lhs.delayMix != rhs.delayMix { return lhs.delayMix < rhs.delayMix }
        if lhs.delayFeedback != rhs.delayFeedback { return lhs.delayFeedback < rhs.delayFeedback }
        return lhs.reverbMix < rhs.reverbMix
    }

    private func refreshReleasedSlots() {
        let now = clock()
        var didExpireEffectContribution = false
        for index in slots.indices {
            guard case let .released(_, deadline, _) = slots[index].state,
                  deadline <= now else { continue }
            voices[index].stop()
            slots[index].state = .idle
            didExpireEffectContribution = true
        }
        if didExpireEffectContribution { recomputeRecipeEffects() }
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
        case released(
            order: UInt64,
            deadline: TimeInterval,
            effects: HappeningEffectCommand
        )
        case active(
            handle: HappeningPlaybackHandle,
            priority: HappeningPlaybackPriority,
            startOrder: UInt64,
            releaseSeconds: TimeInterval,
            effects: HappeningEffectCommand,
            playbackGainScale: Double
        )

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
            case let .released(order, _, _): return (0, order)
            case .idle: return (1, 0)
            case .active: return (.max, .max)
            }
        }

        var activeOrdering: (Int, UInt64) {
            guard case let .active(_, priority, startOrder, _, _, _) = self else { return (.max, .max) }
            return (priority.rawValue, startOrder)
        }
    }
}

private final class DayObjectsAppleResonanceNode: Node {
    let input: Node
    var connections: [Node] { [input] }
    let avAudioNode: AVAudioNode
    private let gainUnit = AVAudioUnitEQ(numberOfBands: 1)

    init(input: Node) {
        self.input = input
        avAudioNode = gainUnit
        let resonantBand = gainUnit.bands[0]
        resonantBand.filterType = .parametric
        resonantBand.frequency = 1_000
        resonantBand.bandwidth = 0.35
        resonantBand.gain = 0
        resonantBand.bypass = true
    }

    func setResonance(_ frequency: Double?) {
        let resonantBand = gainUnit.bands[0]
        guard let frequency, frequency.isFinite else {
            resonantBand.bypass = true
            resonantBand.frequency = 1_000
            resonantBand.gain = 0
            return
        }
        resonantBand.frequency = Float(min(max(frequency, 80), 18_000))
        resonantBand.bandwidth = 0.35
        resonantBand.gain = 20
        resonantBand.bypass = false
    }

}

private final class DayObjectsAppleGainNode: Node {
    let input: Node
    var connections: [Node] { [input] }
    let avAudioNode: AVAudioNode
    private let mixer = AVAudioMixerNode()

    init(input: Node, gain: Double) {
        self.input = input
        avAudioNode = mixer
        mixer.outputVolume = Self.bounded(gain)
    }

    func setLinearGain(_ gain: Double, rampSeconds: TimeInterval) {
        let target = Self.bounded(gain)
        let duration = max(rampSeconds.isFinite ? rampSeconds : 0, 0)
        guard duration > 0,
              let parameter = mixer.auAudioUnit.parameterTree?.allParameters
                .filter({ $0.displayName == "Gain" && $0.flags.contains(.flag_CanRamp) })
                .max(by: { $0.address < $1.address }) else {
            mixer.outputVolume = target
            return
        }
        mixer.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate,
            AUAudioFrameCount(min(duration * Settings.sampleRate, Double(AUAudioFrameCount.max))),
            parameter.address,
            target
        )
    }

    private static func bounded(_ gain: Double) -> AUValue {
        AUValue(min(max(gain.isFinite ? gain : 0, 0), 1))
    }
}

@MainActor
private final class DayObjectsAudioKitHappeningSampleVoice: DayObjectsHappeningSampleVoiceBackend {
    var output: Node { gainNode }
    private let player = AudioPlayer()
    private let variSpeed: VariSpeed
    private let resonanceNode: DayObjectsAppleResonanceNode
    private let gainNode: DayObjectsAppleGainNode
    private var releaseSeconds: TimeInterval = 0

    init(voiceID: Int) {
        let seedFormat = AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 1
        )!
        let seedBuffer = AVAudioPCMBuffer(pcmFormat: seedFormat, frameCapacity: 1)!
        seedBuffer.frameLength = 1
        player.buffer = seedBuffer
        variSpeed = VariSpeed(player)
        resonanceNode = DayObjectsAppleResonanceNode(input: variSpeed)
        gainNode = DayObjectsAppleGainNode(input: resonanceNode, gain: 0)
    }

    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double,
        resonantFilterHz: Double?
    ) {
        player.buffer = buffer
        variSpeed.rate = AUValue(playbackRate)
        resonanceNode.setResonance(resonantFilterHz)
        self.releaseSeconds = releaseSeconds
        setLinearGain(gain, rampSeconds: attackSeconds)
        guard gainNode.avAudioNode.engine?.isRunning == true else { return }
        player.play()
    }

    func release() { setLinearGain(0, rampSeconds: releaseSeconds) }

    func update(gain: Double, playbackRate: Double, rampSeconds: Double) {
        setPlaybackRate(playbackRate, rampSeconds: rampSeconds)
        setLinearGain(gain, rampSeconds: rampSeconds)
    }

    func stop() {
        setLinearGain(0, rampSeconds: 0)
        player.stop()
    }

    private func setLinearGain(_ gain: Double, rampSeconds: TimeInterval) {
        gainNode.setLinearGain(gain, rampSeconds: rampSeconds)
    }

    private func setPlaybackRate(_ playbackRate: Double, rampSeconds: TimeInterval) {
        let target = AUValue(min(max(playbackRate.isFinite ? playbackRate : 1, 0.5), 2))
        let duration = max(rampSeconds.isFinite ? rampSeconds : 0, 0)
        guard duration > 0,
              let parameter = variSpeed.avAudioNode.auAudioUnit.parameterTree?.allParameters
                .first(where: { $0.displayName == "Rate" && $0.flags.contains(.flag_CanRamp) }) else {
            variSpeed.rate = target
            return
        }
        variSpeed.avAudioNode.auAudioUnit.scheduleParameterBlock(
            AUEventSampleTimeImmediate,
            AUAudioFrameCount(min(duration * Settings.sampleRate, Double(AUAudioFrameCount.max))),
            parameter.address,
            target
        )
    }
}

@MainActor
final class DayObjectsInactiveHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    var metrics: HappeningSamplePoolMetrics { .inactive }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {}
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand
    ) throws -> HappeningPlaybackHandle {
        throw HappeningSamplePoolError.recipeUnavailable(sound.recipeID)
    }
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {}
    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {}
    func stop(_ handle: HappeningPlaybackHandle) {}
    func releaseAll() {}
}
#endif
