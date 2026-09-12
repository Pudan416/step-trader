#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import Foundation
import SoundpipeAudioKit

struct DayObjectsTonalVoiceGraphLayout: Equatable, Sendable {
    let morphingOscillatorCount: Int
    let subOscillatorCount: Int
    let noiseGeneratorCount: Int
    let filterBranchCount: Int
    let envelopeCount: Int
    let normalizedLFORouteCount: Int
    let phaserCount: Int
    let saturationCount: Int
    let autoPanCount: Int
    let delaySendCount: Int
    let reverbSendCount: Int
    let outputTrimCount: Int
    let allocatedNodeCount: Int
}

enum DayObjectsTonalPoolPreparationError: Error, Equatable {
    case missingInstrument(DayObjectsInstrumentID)
}

struct DayObjectsTonalVoiceGraphLifecycle: Equatable, Sendable {
    private(set) var hasPendingPreset = false
    private(set) var configurationRevision = 0

    mutating func preparePreset() {
        hasPendingPreset = true
    }

    @discardableResult
    mutating func synchronizeIfAttached(_ isAttached: Bool) -> Bool {
        guard isAttached, hasPendingPreset else { return false }
        hasPendingPreset = false
        configurationRevision += 1
        return true
    }
}

struct DayObjectsTonalVoiceModulationPlan: Equatable, Sendable {
    struct FilterEnvelope: Equatable, Sendable {
        let startCutoffHz: Double
        let peakCutoffHz: Double
        let sustainCutoffHz: Double
        let attackSeconds: Double
        let decaySeconds: Double
        let sustainLevel: Double
        let releaseSeconds: Double
    }

    let lfo: NormalizedSynthVoice.LFO
    let filterEnvelope: FilterEnvelope
    let filterEnvelopeMultiplier: Double
    let amplitudeDepth: Double

    init(preset: NormalizedSynthVoice) {
        lfo = preset.lfo
        let envelope = preset.filter.envelope
        let base = preset.filter.cutoffHz
        let multiplier = pow(2, preset.filter.envelopeAmount * 4)
        filterEnvelopeMultiplier = multiplier
        let peak = Self.clampCutoff(base * multiplier)
        filterEnvelope = .init(
            startCutoffHz: base,
            peakCutoffHz: peak,
            sustainCutoffHz: Self.interpolate(base, peak, envelope.sustainLevel),
            attackSeconds: envelope.attackSeconds,
            decaySeconds: envelope.decaySeconds,
            sustainLevel: envelope.sustainLevel,
            releaseSeconds: envelope.releaseSeconds
        )
        amplitudeDepth = preset.lfo.target == .amplitude ? preset.lfo.depth : 0
    }

    func filterCutoff(envelopeLevel: Double, lfoPhase: Double) -> Double {
        filterCutoff(
            baseCutoffHz: filterEnvelope.startCutoffHz,
            envelopeLevel: envelopeLevel,
            lfoPhase: lfoPhase
        )
    }

    func filterCutoff(baseCutoffHz: Double, envelopeLevel: Double, lfoPhase: Double) -> Double {
        let peakCutoffHz = Self.clampCutoff(baseCutoffHz * filterEnvelopeMultiplier)
        let enveloped = Self.interpolate(
            baseCutoffHz,
            peakCutoffHz,
            envelopeLevel
        )
        guard lfo.target == .filter else { return Self.clampCutoff(enveloped) }
        return Self.clampCutoff(enveloped * pow(2, lfo.depth * 2 * lfoValue(phase: lfoPhase)))
    }

    func pitchSemitoneOffset(phase: Double) -> Double {
        guard lfo.target == .pitch else { return 0 }
        return lfo.depth * 2 * lfoValue(phase: phase)
    }

    private func lfoValue(phase: Double) -> Double {
        let normalized = phase - floor(phase)
        switch lfo.waveform {
        case .sine:
            return sin(normalized * 2 * .pi)
        case .square:
            return normalized < 0.5 ? 1 : -1
        case .sawtooth:
            return normalized * 2 - 1
        case .reverseSawtooth:
            return 1 - normalized * 2
        }
    }

    private static func interpolate(_ start: Double, _ end: Double, _ level: Double) -> Double {
        start + (end - start) * min(max(level, 0), 1)
    }

    private static func clampCutoff(_ cutoff: Double) -> Double {
        min(max(cutoff, DayObjectsAudioParameters.minimumCutoffHz), DayObjectsAudioParameters.maximumCutoffHz)
    }

}

struct DayObjectsTonalVoiceModulationState: Equatable, Sendable {
    let plan: DayObjectsTonalVoiceModulationPlan
    private(set) var baseCutoffHz: Double

    init(preset: NormalizedSynthVoice) {
        plan = DayObjectsTonalVoiceModulationPlan(preset: preset)
        baseCutoffHz = preset.filter.cutoffHz
    }

    mutating func updateBaseCutoffHz(_ cutoffHz: Double) {
        baseCutoffHz = min(
            max(cutoffHz, DayObjectsAudioParameters.minimumCutoffHz),
            DayObjectsAudioParameters.maximumCutoffHz
        )
    }

    func filterCutoff(envelopeLevel: Double, lfoPhase: Double) -> Double {
        plan.filterCutoff(
            baseCutoffHz: baseCutoffHz,
            envelopeLevel: envelopeLevel,
            lfoPhase: lfoPhase
        )
    }
}

struct DayObjectsTonalVoiceModulationLifecycle: Equatable, Sendable {
    private(set) var isTimerActive = false

    mutating func start() {
        isTimerActive = true
    }

    mutating func stop() {
        isTimerActive = false
    }

    @discardableResult
    mutating func noteOff(isGraphAttached: Bool) -> Bool {
        guard !isGraphAttached else { return false }
        stop()
        return true
    }
}

final class DayObjectsTonalVoiceControlExecutor {
    private let queue: DispatchQueue
    private let queueIdentity = UUID().uuidString
    private let queueIdentityKey = DispatchSpecificKey<String>()

    init(label: String) {
        queue = DispatchQueue(label: label)
        queue.setSpecific(key: queueIdentityKey, value: queueIdentity)
    }

    var isCurrentExecutor: Bool {
        DispatchQueue.getSpecific(key: queueIdentityKey) == queueIdentity
    }

    func sync<T>(_ operation: () throws -> T) rethrows -> T {
        if isCurrentExecutor {
            return try operation()
        }
        return try queue.sync(execute: operation)
    }

    func makeRepeatingTimer(interval: TimeInterval, handler: @escaping () -> Void) -> DispatchSourceTimer {
        precondition(isCurrentExecutor, "Timers must be created on the voice control executor")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }
}

enum DayObjectsTonalGateDelivery: Equatable, Sendable {
    case immediate
    case scheduled(sampleOffset: UInt64)
}

protocol DayObjectsTonalGate: AnyObject {
    func openImmediately()
    func closeImmediately()
    func scheduleOpen(atHostTime hostTime: TimeInterval, sampleOffset: UInt64)
    func cancelScheduledOpen()
}

extension AmplitudeEnvelope: DayObjectsTonalGate {
    func openImmediately() { openGate() }
    func closeImmediately() { closeGate() }

    func scheduleOpen(atHostTime _: TimeInterval, sampleOffset: UInt64) {
        scheduleMIDIEvent(
            event: MIDIEvent(noteOn: 64, velocity: 127, channel: 0),
            offset: sampleOffset
        )
    }

    func cancelScheduledOpen() { avAudioNode.auAudioUnit.reset() }
}

final class DayObjectsTonalGateScheduler {
    typealias HostTimeProvider = () -> TimeInterval
    typealias SampleRateProvider = () -> Double

    private let hostTimeProvider: HostTimeProvider
    private let sampleRateProvider: SampleRateProvider
    private var pendingOpen: (gateID: ObjectIdentifier, hostTimeSeconds: TimeInterval)?

    init(
        hostTimeProvider: @escaping HostTimeProvider = {
            ProcessInfo.processInfo.systemUptime
        },
        sampleRateProvider: @escaping SampleRateProvider = { Settings.sampleRate }
    ) {
        self.hostTimeProvider = hostTimeProvider
        self.sampleRateProvider = sampleRateProvider
    }

    func delivery(atHostTime hostTime: TimeInterval) -> DayObjectsTonalGateDelivery {
        let delta = hostTime - hostTimeProvider()
        guard hostTime.isFinite, hostTime > 0, delta > 0 else { return .immediate }
        let samples = delta * max(sampleRateProvider(), 1)
        return .scheduled(sampleOffset: UInt64(min(samples.rounded(), Double(UInt64.max))))
    }

    func open(_ gate: any DayObjectsTonalGate, atHostTime hostTime: TimeInterval) {
        if pendingOpen != nil { close(gate) }
        switch delivery(atHostTime: hostTime) {
        case .immediate:
            gate.openImmediately()
        case let .scheduled(sampleOffset):
            gate.scheduleOpen(atHostTime: hostTime, sampleOffset: sampleOffset)
            pendingOpen = (
                gateID: ObjectIdentifier(gate),
                hostTimeSeconds: hostTime
            )
        }
    }

    func close(_ gate: any DayObjectsTonalGate) {
        if let pendingOpen,
           pendingOpen.gateID == ObjectIdentifier(gate) {
            let now = hostTimeProvider()
            if !now.isFinite || now < pendingOpen.hostTimeSeconds {
                // Resetting the envelope Audio Unit clears its queued MIDI
                // event before closing, so released ownership cannot reopen at
                // the old diagnostic deadline.
                gate.cancelScheduledOpen()
            }
        }
        pendingOpen = nil
        gate.closeImmediately()
    }
}

enum DayObjectsTonalVoiceProfile: Equatable, Sendable {
    case fullFidelity
    case mobileRealtime
}

private protocol DayObjectsAudioKitVoice: DayObjectsTonalVoiceBackend {
    var output: Fader { get }
    var nodeIdentities: [ObjectIdentifier] { get }
    func synchronizeGraphIfAttached()
    func advanceOfflineModulation()
}

final class DayObjectsAudioKitTonalPool {
    let pool: DayObjectsTonalVoicePool
    let output: Mixer
    let name: String

    var voiceNodeIdentities: [ObjectIdentifier] {
        voices.flatMap(\.nodeIdentities)
    }

    func synchronizeGraphIfAttached() {
        voices.forEach { $0.synchronizeGraphIfAttached() }
    }

    func advanceOfflineModulation() {
        voices.forEach { $0.advanceOfflineModulation() }
    }

    private let voices: [any DayObjectsAudioKitVoice]

    init(
        specification: DayObjectsTonalPoolSpecification,
        instruments: [DayObjectsInstrumentID: NormalizedSynthVoice],
        voiceProfile: DayObjectsTonalVoiceProfile = .fullFidelity,
        hostTimeProvider: @escaping DayObjectsTonalGateScheduler.HostTimeProvider = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        name = specification.name
        let builtVoices: [any DayObjectsAudioKitVoice] = (0..<specification.capacity).map { _ in
            switch voiceProfile {
            case .fullFidelity:
                DayObjectsTonalVoice(gateScheduler: .init(hostTimeProvider: hostTimeProvider))
            case .mobileRealtime:
                DayObjectsMobileTonalVoice(gateScheduler: .init(hostTimeProvider: hostTimeProvider))
            }
        }
        voices = builtVoices
        output = Mixer(builtVoices.map(\.output), name: "Day Objects tonal pool \(specification.name)")

        var nextVoice = 0
        pool = DayObjectsTonalVoicePool(
            specification: specification,
            instrumentProvider: { id in
                guard let voice = instruments[id] else {
                    throw DayObjectsTonalPoolPreparationError.missingInstrument(id)
                }
                return voice
            },
            voiceFactory: {
                defer { nextVoice += 1 }
                return builtVoices[nextVoice]
            },
            monotonicTime: hostTimeProvider
        )
    }
}

final class DayObjectsTonalVoice: DayObjectsAudioKitVoice {
    static let graphLayout = DayObjectsTonalVoiceGraphLayout(
        morphingOscillatorCount: 2,
        subOscillatorCount: 1,
        noiseGeneratorCount: 1,
        filterBranchCount: 3,
        envelopeCount: 2,
        normalizedLFORouteCount: 1,
        phaserCount: 1,
        saturationCount: 1,
        autoPanCount: 1,
        delaySendCount: 1,
        reverbSendCount: 1,
        outputTrimCount: 1,
        allocatedNodeCount: 25
    )

    let output: Fader
    let allocatedNodeCount = graphLayout.allocatedNodeCount

    var nodeIdentities: [ObjectIdentifier] {
        nodes.map(ObjectIdentifier.init)
    }

    private let oscillator1: MorphingOscillator
    private let oscillator2: MorphingOscillator
    private let subOscillator: MorphingOscillator
    private let noise: WhiteNoise
    private let sourceMixer: Mixer

    private let lowPass: LowPassFilter
    private let bandPass: BandPassFilter
    private let highPass: HighPassFilter
    private let lowPassFader: Fader
    private let bandPassFader: Fader
    private let highPassFader: Fader
    private let filterMixer: Mixer

    private let amplitudeEnvelope: AmplitudeEnvelope
    private let amplitudeTremolo: Tremolo

    private let phaser: Phaser
    private let saturation: TanhDistortion
    private let autoPanner: AutoPanner
    private let dryFader: Fader
    private let delaySendFader: Fader
    private let delay: Delay
    private let reverbSendFader: Fader
    private let reverbHighPass: HighPassFilter
    private let reverb: CostelloReverb
    private let effectsMixer: Mixer
    private let controlExecutor = DayObjectsTonalVoiceControlExecutor(label: "DayObjectsTonalVoice.control")
    private let gateScheduler: DayObjectsTonalGateScheduler

    private var currentPreset: NormalizedSynthVoice?
    private var currentMIDINote = 60.0
    private var baseOutputGain = 0.0
    private var expression = 1.0
    private var pan = 0.0
    private var delayMix = 0.0
    private var reverbMix = 0.0
    private var delaySend = 1.0
    private var reverbSend = 1.0
    private var saturationAmount = 0.0
    private var isGateOpen = false
    private var graphLifecycle = DayObjectsTonalVoiceGraphLifecycle()
    private var modulationState: DayObjectsTonalVoiceModulationState?
    private var modulationLifecycle = DayObjectsTonalVoiceModulationLifecycle()
    private var modulationTimer: DispatchSourceTimer?
    private var noteStartedAt: TimeInterval?
    private var releaseStartedAt: TimeInterval?
    private var releaseStartEnvelopeLevel = 0.0
    private var currentFilterEnvelopeLevel = 0.0
    private var currentModulationPhase = 0.0
    private var pitchRampEndsAt: TimeInterval?
    private var cutoffRampEndsAt: TimeInterval?

    // The very same envelopes/LFO run from the engine sample clock in manual
    // mode. Live playback retains its wall-clock timer and time origin.
    private var modulationTime: TimeInterval {
        if let engine = output.avAudioNode.engine, engine.isInManualRenderingMode {
            return Double(engine.manualRenderingSampleTime) / engine.manualRenderingFormat.sampleRate
        }
        return Date.timeIntervalSinceReferenceDate
    }

    func advanceOfflineModulation() {
        controlExecutor.sync {
            guard output.avAudioNode.engine?.isInManualRenderingMode == true,
                  modulationLifecycle.isTimerActive else { return }
            applyModulation(at: modulationTime)
        }
    }

    init(gateScheduler: DayObjectsTonalGateScheduler = .init()) {
        self.gateScheduler = gateScheduler
        let morphTables = [Table(.sine), Table(.triangle), Table(.square), Table(.sawtooth)]
        oscillator1 = MorphingOscillator(waveformArray: morphTables, amplitude: 0)
        oscillator2 = MorphingOscillator(waveformArray: morphTables, amplitude: 0)
        subOscillator = MorphingOscillator(
            waveformArray: [Table(.sine), Table(.square), Table(.sine), Table(.square)],
            amplitude: 0
        )
        noise = WhiteNoise(amplitude: 0)
        sourceMixer = Mixer(oscillator1, oscillator2, subOscillator, noise)

        lowPass = LowPassFilter(sourceMixer, cutoffFrequency: 12_000, resonance: 0)
        bandPass = BandPassFilter(sourceMixer, centerFrequency: 12_000, bandwidth: 6_000)
        highPass = HighPassFilter(sourceMixer, cutoffFrequency: 12_000, resonance: 0)
        lowPassFader = Fader(lowPass, gain: 1)
        bandPassFader = Fader(bandPass, gain: 0)
        highPassFader = Fader(highPass, gain: 0)
        filterMixer = Mixer(lowPassFader, bandPassFader, highPassFader)

        amplitudeEnvelope = AmplitudeEnvelope(filterMixer, sustainLevel: 0)
        amplitudeTremolo = Tremolo(amplitudeEnvelope, frequency: 1, depth: 0)

        phaser = Phaser(amplitudeTremolo, dryWetMix: 0)
        saturation = TanhDistortion(phaser, pregain: 1, postgain: 1, dryWetMix: 0)
        autoPanner = AutoPanner(saturation, frequency: 0.25, depth: 0)
        dryFader = Fader(autoPanner, gain: 1)
        delaySendFader = Fader(autoPanner, gain: 0)
        delay = Delay(delaySendFader, time: 0.25, feedback: 0, dryWetMix: 100)
        reverbSendFader = Fader(autoPanner, gain: 0)
        reverbHighPass = HighPassFilter(reverbSendFader, cutoffFrequency: 80, resonance: 0)
        reverb = CostelloReverb(reverbHighPass, balance: 1, feedback: 0.8, cutoffFrequency: 8_000)
        effectsMixer = Mixer(dryFader, delay, reverb)
        output = Fader(effectsMixer, gain: 0)
    }

    deinit {
        modulationTimer?.setEventHandler {}
        modulationTimer?.cancel()
    }

    func replacePreset(
        _ rawPreset: NormalizedSynthVoice,
        instrumentID _: DayObjectsInstrumentID,
        transitionDuration: TimeInterval
    ) {
        controlExecutor.sync {
            replacePresetOnControlExecutor(rawPreset, transitionDuration: transitionDuration)
        }
    }

    private func replacePresetOnControlExecutor(
        _ rawPreset: NormalizedSynthVoice,
        transitionDuration: TimeInterval
    ) {
        assertOnControlExecutor()
        noteOffOnControlExecutor()
        stopModulation()
        let preset = DayObjectsAudioParameters.clamped(rawPreset)
        currentPreset = preset
        modulationState = DayObjectsTonalVoiceModulationState(preset: preset)
        baseOutputGain = DayObjectsAudioParameters.linearGain(decibels: preset.outputTrimDB)
        delayMix = preset.delay.isEnabled ? preset.delay.mix : 0
        reverbMix = preset.reverb.isEnabled ? preset.reverb.mix : 0
        graphLifecycle.preparePreset()
        synchronizeGraphIfAttachedOnControlExecutor(transitionDuration: transitionDuration)
    }

    func synchronizeGraphIfAttached() {
        controlExecutor.sync {
            synchronizeGraphIfAttachedOnControlExecutor(
                transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
            )
        }
    }

    private func synchronizeGraphIfAttachedOnControlExecutor(transitionDuration: TimeInterval) {
        assertOnControlExecutor()
        guard let preset = currentPreset, graphLifecycle.synchronizeIfAttached(isGraphAttached) else { return }

        oscillator1.start()
        oscillator2.start()
        subOscillator.start()
        noise.start()

        let duration = Float(max(0, transitionDuration))
        ramp(oscillator1.$index, to: preset.oscillator1.wavePosition * 3, duration: duration)
        ramp(oscillator2.$index, to: preset.oscillator2.wavePosition * 3, duration: duration)
        ramp(
            oscillator1.$amplitude,
            to: preset.oscillator1.level * (1 - preset.oscillatorBalance),
            duration: duration
        )
        ramp(
            oscillator2.$amplitude,
            to: preset.oscillator2.level * preset.oscillatorBalance,
            duration: duration
        )
        ramp(oscillator1.$detuningOffset, to: preset.oscillator1.detuneHz, duration: duration)
        ramp(oscillator2.$detuningOffset, to: preset.oscillator2.detuneHz, duration: duration)
        ramp(
            subOscillator.$index,
            to: preset.subOscillator.waveform == .square ? 1 : 0,
            duration: duration
        )
        ramp(subOscillator.$amplitude, to: preset.subOscillator.level, duration: duration)
        ramp(noise.$amplitude, to: preset.noiseLevel, duration: duration)

        applyFilter(preset.filter, duration: duration)
        applyEnvelopes(preset, duration: duration)
        applyLFO(preset.lfo, duration: duration)
        applyMotionAndEffects(preset, duration: duration)
        rampOutput(expression: 0, pan: pan, duration: duration)
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) {
        controlExecutor.sync {
            noteOnOnControlExecutor(request, scheduledHostTime: nil)
        }
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest, atHostTime hostTime: TimeInterval) {
        controlExecutor.sync {
            noteOnOnControlExecutor(request, scheduledHostTime: hostTime)
        }
    }

    private func noteOnOnControlExecutor(
        _ request: DayObjectsTonalNoteRequest,
        scheduledHostTime: TimeInterval?
    ) {
        assertOnControlExecutor()
        guard let preset = currentPreset else { return }
        currentMIDINote = Double(request.midiNote)
        expression = request.velocity * (request.role == .chord ? 0.72 : 1)
        pan = request.pan
        delaySend = request.delaySend
        reverbSend = request.reverbSend

        guard isGraphAttached else {
            isGateOpen = true
            return
        }

        synchronizeGraphIfAttachedOnControlExecutor(
            transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
        )

        let envelope = request.envelopeVariant
        amplitudeEnvelope.attackDuration = value(
            envelope?.absoluteAttackSeconds
                ?? preset.amplitudeEnvelope.attackSeconds * (envelope?.attackScale ?? 1)
        )
        amplitudeEnvelope.releaseDuration = value(
            envelope?.absoluteReleaseSeconds
                ?? preset.amplitudeEnvelope.releaseSeconds * (envelope?.releaseScale ?? 1)
        )
        setFrequencies(midiNote: currentMIDINote, pitchSemitoneOffset: 0, duration: Float(preset.glideSeconds))
        rampEffects(duration: Float(DayObjectsAudioParameters.controlRampDuration))
        rampOutput(
            expression: expression,
            pan: pan,
            duration: Float(DayObjectsAudioParameters.controlRampDuration)
        )
        if let scheduledHostTime {
            gateScheduler.open(amplitudeEnvelope, atHostTime: scheduledHostTime)
        } else {
            amplitudeEnvelope.openGate()
        }
        isGateOpen = true
        startModulation()
    }

    func update(_ update: DayObjectsVoiceUpdate) {
        controlExecutor.sync {
            updateOnControlExecutor(update)
        }
    }

    private func updateOnControlExecutor(_ update: DayObjectsVoiceUpdate) {
        assertOnControlExecutor()
        guard currentPreset != nil else { return }
        let controlDuration = Float(DayObjectsAudioParameters.controlRampDuration)
        let pitchDuration = Float(update.pitchRampSeconds ?? DayObjectsAudioParameters.controlRampDuration)
        let cutoffDuration = Float(update.cutoffRampSeconds ?? DayObjectsAudioParameters.controlRampDuration)
        let expressionDuration = Float(update.expressionRampSeconds ?? DayObjectsAudioParameters.controlRampDuration)
        if let midiNote = update.midiNote {
            currentMIDINote = midiNote
        }
        if let expression = update.expression {
            self.expression = expression
        }
        if let pan = update.pan {
            self.pan = pan
        }
        if let delaySend = update.delaySend {
            self.delaySend = delaySend
        }
        if let reverbSend = update.reverbSend {
            self.reverbSend = reverbSend
        }
        if let saturationAmount = update.saturationAmount {
            self.saturationAmount = saturationAmount
        }
        if let cutoffHz = update.cutoffHz {
            modulationState?.updateBaseCutoffHz(cutoffHz)
        }

        guard isGraphAttached else { return }

        synchronizeGraphIfAttachedOnControlExecutor(
            transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
        )

        if let midiNote = update.midiNote {
            setFrequencies(midiNote: midiNote, pitchSemitoneOffset: 0, duration: pitchDuration)
            pitchRampEndsAt = modulationTime + Double(pitchDuration)
        }
        if let cutoffHz = update.cutoffHz {
            let currentCutoff = modulationState?.filterCutoff(
                envelopeLevel: currentFilterEnvelopeLevel,
                lfoPhase: currentModulationPhase
            ) ?? cutoffHz
            setFilterCutoff(currentCutoff, duration: cutoffDuration)
            cutoffRampEndsAt = modulationTime + Double(cutoffDuration)
        }
        rampEffects(duration: controlDuration)
        rampSaturation(duration: Float(
            update.saturationRampSeconds ?? DayObjectsAudioParameters.controlRampDuration
        ))
        rampOutput(expression: expression, pan: pan, duration: expressionDuration)
    }

    func noteOff() {
        noteOff(releaseSeconds: nil)
    }

    func noteOff(releaseSeconds: TimeInterval?) {
        controlExecutor.sync {
            noteOffOnControlExecutor(releaseSeconds: releaseSeconds)
        }
    }

    private func noteOffOnControlExecutor(releaseSeconds requestedReleaseSeconds: TimeInterval? = nil) {
        assertOnControlExecutor()
        if modulationLifecycle.noteOff(isGraphAttached: isGraphAttached) {
            gateScheduler.close(amplitudeEnvelope)
            stopModulation()
            isGateOpen = false
            return
        }
        guard isGateOpen else { return }
        defer { isGateOpen = false }
        let release = min(max(
            requestedReleaseSeconds
                ?? Double(amplitudeEnvelope.releaseDuration),
            0
        ), 30)
        amplitudeEnvelope.releaseDuration = value(release)
        gateScheduler.close(amplitudeEnvelope)
        rampOutput(expression: 0, pan: pan, duration: Float(release))
        releaseStartedAt = modulationTime
        releaseStartEnvelopeLevel = currentFilterEnvelopeLevel
    }

    private func assertOnControlExecutor() {
        precondition(controlExecutor.isCurrentExecutor, "Voice state must be accessed through its control executor")
    }

    private var isGraphAttached: Bool {
        output.avAudioNode.engine != nil
    }

    private var nodes: [any Node] {
        [
            oscillator1, oscillator2, subOscillator, noise, sourceMixer,
            lowPass, bandPass, highPass, lowPassFader, bandPassFader, highPassFader, filterMixer,
            amplitudeEnvelope, amplitudeTremolo, phaser, saturation, autoPanner, dryFader,
            delaySendFader, delay, reverbSendFader, reverbHighPass, reverb, effectsMixer, output,
        ]
    }

    private func applyFilter(_ filter: NormalizedSynthVoice.Filter, duration: Float) {
        setFilterCutoff(modulationState?.baseCutoffHz ?? filter.cutoffHz, duration: duration)
        let resonanceDB = filter.resonance * 40
        ramp(lowPass.$resonance, to: resonanceDB, duration: duration)
        ramp(highPass.$resonance, to: resonanceDB, duration: duration)
        ramp(bandPass.$bandwidth, to: 12_000 - filter.resonance * 11_900, duration: duration)
        ramp(lowPassFader, to: filter.kind == .lowPass ? 1 : 0, duration: duration)
        ramp(bandPassFader, to: filter.kind == .bandPass ? 1 : 0, duration: duration)
        ramp(highPassFader, to: filter.kind == .highPass ? 1 : 0, duration: duration)

    }

    private func applyEnvelopes(_ preset: NormalizedSynthVoice, duration: Float) {
        let amplitude = preset.amplitudeEnvelope
        ramp(amplitudeEnvelope.$attackDuration, to: amplitude.attackSeconds, duration: duration)
        ramp(amplitudeEnvelope.$decayDuration, to: amplitude.decaySeconds, duration: duration)
        ramp(amplitudeEnvelope.$sustainLevel, to: amplitude.sustainLevel, duration: duration)
        ramp(amplitudeEnvelope.$releaseDuration, to: amplitude.releaseSeconds, duration: duration)
    }

    private func applyLFO(_ lfo: NormalizedSynthVoice.LFO, duration: Float) {
        amplitudeTremolo.setWaveform(Self.lfoTable(lfo.waveform))
        ramp(amplitudeTremolo.$frequency, to: lfo.rateHz, duration: duration)
        ramp(
            amplitudeTremolo.$depth,
            to: lfo.target == .amplitude ? lfo.depth : 0,
            duration: duration
        )
    }

    private func applyMotionAndEffects(_ preset: NormalizedSynthVoice, duration: Float) {
        ramp(phaser.$notchWidth, to: preset.phaser.notchWidthHz, duration: duration)
        ramp(phaser.$feedback, to: abs(preset.phaser.feedback), duration: duration)
        ramp(phaser.$inverted, to: preset.phaser.feedback < 0 ? 1 : 0, duration: duration)
        ramp(phaser.$lfoBPM, to: min(max(preset.phaser.rateHz * 60, 24), 360), duration: duration)
        ramp(phaser.$dryWetMix, to: preset.phaser.mix, duration: duration)
        saturationAmount = 0
        rampSaturation(duration: duration)

        ramp(autoPanner.$frequency, to: preset.autoPan.rateHz, duration: duration)
        ramp(
            autoPanner.$depth,
            to: preset.autoPan.depth * preset.autoPan.stereoWidth,
            duration: duration
        )
        ramp(delay.$time, to: preset.delay.timeSeconds, duration: duration)
        ramp(delay.$feedback, to: preset.delay.feedback * 100, duration: duration)
        ramp(reverbHighPass.$cutoffFrequency, to: preset.reverb.highPassHz, duration: duration)
        ramp(reverb.$feedback, to: preset.reverb.feedback, duration: duration)
        rampEffects(duration: duration)
    }

    private func setFrequencies(midiNote: Double, pitchSemitoneOffset: Double, duration: Float) {
        guard let preset = currentPreset else { return }
        ramp(
            oscillator1.$frequency,
            to: Self.frequency(midiNote + Double(preset.oscillator1.semitoneOffset) + pitchSemitoneOffset),
            duration: duration
        )
        ramp(
            oscillator2.$frequency,
            to: Self.frequency(midiNote + Double(preset.oscillator2.semitoneOffset) + pitchSemitoneOffset),
            duration: duration
        )
        ramp(
            subOscillator.$frequency,
            to: Self.frequency(midiNote + Double(preset.subOscillator.octaveOffset * 12) + pitchSemitoneOffset),
            duration: duration
        )
    }

    private func setFilterCutoff(_ cutoffHz: Double, duration: Float) {
        let bounded = min(max(cutoffHz, DayObjectsAudioParameters.minimumCutoffHz), DayObjectsAudioParameters.maximumCutoffHz)
        ramp(lowPass.$cutoffFrequency, to: bounded, duration: duration)
        ramp(bandPass.$centerFrequency, to: bounded, duration: duration)
        ramp(highPass.$cutoffFrequency, to: bounded, duration: duration)
    }

    private func startModulation() {
        assertOnControlExecutor()
        stopModulation()
        let now = modulationTime
        noteStartedAt = now
        releaseStartedAt = nil
        currentFilterEnvelopeLevel = 0
        currentModulationPhase = 0
        applyModulation(at: now)
        modulationLifecycle.start()
        guard output.avAudioNode.engine?.isInManualRenderingMode != true else { return }
        modulationTimer = controlExecutor.makeRepeatingTimer(interval: 1.0 / 120) { [weak self] in
            self?.applyModulation(at: Date.timeIntervalSinceReferenceDate)
        }
    }

    private func applyModulation(at now: TimeInterval) {
        assertOnControlExecutor()
        guard let modulationState, let noteStartedAt else {
            stopModulation()
            return
        }
        guard isGraphAttached else {
            stopModulation()
            return
        }
        let plan = modulationState.plan

        let envelopeLevel: Double
        if let releaseStartedAt {
            let elapsed = now - releaseStartedAt
            let release = max(plan.filterEnvelope.releaseSeconds, 0.000_001)
            envelopeLevel = max(0, releaseStartEnvelopeLevel * (1 - elapsed / release))
            if elapsed >= release {
                stopModulation()
            }
        } else {
            envelopeLevel = filterEnvelopeLevel(at: now - noteStartedAt, plan: plan)
        }
        currentFilterEnvelopeLevel = envelopeLevel

        let phase = (now - noteStartedAt) * plan.lfo.rateHz
        currentModulationPhase = phase
        let pitchDuration = remainingRampDuration(
            endingAt: &pitchRampEndsAt,
            now: now
        )
        let cutoffDuration = remainingRampDuration(
            endingAt: &cutoffRampEndsAt,
            now: now
        )
        setFrequencies(
            midiNote: currentMIDINote,
            pitchSemitoneOffset: plan.pitchSemitoneOffset(phase: phase),
            duration: pitchDuration
        )
        setFilterCutoff(
            modulationState.filterCutoff(envelopeLevel: envelopeLevel, lfoPhase: phase),
            duration: cutoffDuration
        )
    }

    private func stopModulation() {
        assertOnControlExecutor()
        modulationTimer?.setEventHandler {}
        modulationTimer?.cancel()
        modulationTimer = nil
        modulationLifecycle.stop()
        noteStartedAt = nil
        releaseStartedAt = nil
        pitchRampEndsAt = nil
        cutoffRampEndsAt = nil
    }

    private func remainingRampDuration(
        endingAt: inout TimeInterval?,
        now: TimeInterval
    ) -> Float {
        guard let end = endingAt, end > now else {
            endingAt = nil
            return Float(DayObjectsAudioParameters.controlRampDuration)
        }
        return Float(end - now)
    }

    private func filterEnvelopeLevel(at elapsed: TimeInterval, plan: DayObjectsTonalVoiceModulationPlan) -> Double {
        let envelope = plan.filterEnvelope
        if elapsed < envelope.attackSeconds {
            return elapsed / max(envelope.attackSeconds, 0.000_001)
        }
        let decayElapsed = elapsed - envelope.attackSeconds
        if decayElapsed < envelope.decaySeconds {
            let progress = decayElapsed / max(envelope.decaySeconds, 0.000_001)
            return 1 - (1 - envelope.sustainLevel) * progress
        }
        return envelope.sustainLevel
    }

    private func rampEffects(duration: Float) {
        ramp(delaySendFader, to: delayMix * delaySend, duration: duration)
        ramp(reverbSendFader, to: reverbMix * reverbSend, duration: duration)
    }

    private func rampSaturation(duration: Float) {
        let amount = min(max(saturationAmount, 0), 1)
        let pregain = 1 + (6 * amount)
        let postgain = 1 / sqrt(pregain)
        let wetMix = min(amount * 2.5, 0.45)
        ramp(saturation.$pregain, to: pregain, duration: duration)
        ramp(saturation.$postgain, to: postgain, duration: duration)
        ramp(saturation.$dryWetMix, to: wetMix, duration: duration)
    }

    private func rampOutput(expression: Double, pan: Double, duration: Float) {
        let gain = baseOutputGain * expression
        let left = gain * (pan > 0 ? 1 - pan : 1)
        let right = gain * (pan < 0 ? 1 + pan : 1)
        ramp(output.$leftGain, to: left, duration: duration)
        ramp(output.$rightGain, to: right, duration: duration)
    }

    private func ramp(_ parameter: NodeParameter, to target: Double, duration: Float) {
        let targetValue = value(target)
        guard parameter.parameter.flags.contains(.flag_CanRamp) else {
            parameter.value = targetValue
            return
        }
        parameter.ramp(to: targetValue, duration: max(0, duration))
    }

    private func ramp(_ fader: Fader, to target: Double, duration: Float) {
        ramp(fader.$leftGain, to: target, duration: duration)
        ramp(fader.$rightGain, to: target, duration: duration)
    }

    private func value(_ value: Double) -> AUValue {
        AUValue(value)
    }

    private static func frequency(_ midiNote: Double) -> Double {
        440 * pow(2, (midiNote - 69) / 12)
    }

    private static func lfoTable(_ waveform: NormalizedSynthVoice.LFOWaveform) -> Table {
        switch waveform {
        case .sine:
            return sineLFO
        case .square:
            return squareLFO
        case .sawtooth:
            return sawtoothLFO
        case .reverseSawtooth:
            return reverseSawtoothLFO
        }
    }

    private static let sineLFO = Table(.positiveSine)
    private static let squareLFO = Table(.positiveSquare)
    private static let sawtoothLFO = Table(.positiveSawtooth)
    private static let reverseSawtoothLFO = Table(.positiveReverseSawtooth)
}

/// A deliberately small realtime voice for phones. The full voice owns a
/// delay, reverb, phaser, saturation, autopan, tremolo, and three parallel
/// filters per note. Those colors are useful while authoring, but multiplying
/// that graph by every chord voice makes cold start and realtime rendering too
/// expensive on a device. Mobile voices keep the oscillators, envelope, and
/// musical filter; the existing shared role buses provide spatial effects.
final class DayObjectsMobileTonalVoice: DayObjectsAudioKitVoice {
    static let graphLayout = DayObjectsTonalVoiceGraphLayout(
        morphingOscillatorCount: 2,
        subOscillatorCount: 1,
        noiseGeneratorCount: 1,
        filterBranchCount: 1,
        envelopeCount: 1,
        normalizedLFORouteCount: 1,
        phaserCount: 0,
        saturationCount: 0,
        autoPanCount: 0,
        delaySendCount: 0,
        reverbSendCount: 0,
        outputTrimCount: 1,
        allocatedNodeCount: 8
    )
    static let modulationUpdateInterval: TimeInterval = 1.0 / 30.0

    let output: Fader
    let allocatedNodeCount = graphLayout.allocatedNodeCount

    var nodeIdentities: [ObjectIdentifier] {
        nodes.map(ObjectIdentifier.init)
    }

    private let oscillator1: MorphingOscillator
    private let oscillator2: MorphingOscillator
    private let subOscillator: MorphingOscillator
    private let noise: WhiteNoise
    private let sourceMixer: Mixer
    private let lowPass: LowPassFilter
    private let amplitudeEnvelope: AmplitudeEnvelope
    private let controlExecutor = DayObjectsTonalVoiceControlExecutor(label: "DayObjectsMobileTonalVoice.control")
    private let gateScheduler: DayObjectsTonalGateScheduler

    private var currentPreset: NormalizedSynthVoice?
    private var currentMIDINote = 60.0
    private var expression = 0.0
    private var pan = 0.0
    private var baseOutputGain = 0.0
    private var graphLifecycle = DayObjectsTonalVoiceGraphLifecycle()
    private var modulationState: DayObjectsTonalVoiceModulationState?
    private var modulationLifecycle = DayObjectsTonalVoiceModulationLifecycle()
    private var modulationTimer: DispatchSourceTimer?
    private var noteStartedAt: TimeInterval?
    private var currentFilterEnvelopeLevel = 0.0

    init(gateScheduler: DayObjectsTonalGateScheduler = .init()) {
        self.gateScheduler = gateScheduler
        let tables = [Table(.sine), Table(.triangle), Table(.square), Table(.sawtooth)]
        oscillator1 = MorphingOscillator(waveformArray: tables, amplitude: 0)
        oscillator2 = MorphingOscillator(waveformArray: tables, amplitude: 0)
        subOscillator = MorphingOscillator(
            waveformArray: [Table(.sine), Table(.square), Table(.sine), Table(.square)],
            amplitude: 0
        )
        noise = WhiteNoise(amplitude: 0)
        sourceMixer = Mixer(oscillator1, oscillator2, subOscillator, noise)
        lowPass = LowPassFilter(sourceMixer, cutoffFrequency: 12_000, resonance: 0)
        amplitudeEnvelope = AmplitudeEnvelope(lowPass, sustainLevel: 0)
        output = Fader(amplitudeEnvelope, gain: 0)
    }

    deinit {
        modulationTimer?.setEventHandler {}
        modulationTimer?.cancel()
    }

    func replacePreset(
        _ rawPreset: NormalizedSynthVoice,
        instrumentID _: DayObjectsInstrumentID,
        transitionDuration: TimeInterval
    ) {
        controlExecutor.sync {
            stopModulation()
            gateScheduler.close(amplitudeEnvelope)
            let preset = DayObjectsAudioParameters.clamped(rawPreset)
            currentPreset = preset
            modulationState = DayObjectsTonalVoiceModulationState(preset: preset)
            baseOutputGain = DayObjectsAudioParameters.linearGain(decibels: preset.outputTrimDB)
            graphLifecycle.preparePreset()
            synchronizeGraphIfAttachedOnControlExecutor(transitionDuration: transitionDuration)
        }
    }

    func synchronizeGraphIfAttached() {
        controlExecutor.sync {
            synchronizeGraphIfAttachedOnControlExecutor(
                transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
            )
        }
    }

    private func synchronizeGraphIfAttachedOnControlExecutor(transitionDuration: TimeInterval) {
        guard let preset = currentPreset,
              graphLifecycle.synchronizeIfAttached(output.avAudioNode.engine != nil) else { return }
        oscillator1.start()
        oscillator2.start()
        subOscillator.start()
        noise.start()
        let duration = Float(max(0, transitionDuration))
        ramp(oscillator1.$index, to: preset.oscillator1.wavePosition * 3, duration: duration)
        ramp(oscillator2.$index, to: preset.oscillator2.wavePosition * 3, duration: duration)
        ramp(oscillator1.$amplitude, to: preset.oscillator1.level * (1 - preset.oscillatorBalance), duration: duration)
        ramp(oscillator2.$amplitude, to: preset.oscillator2.level * preset.oscillatorBalance, duration: duration)
        ramp(oscillator1.$detuningOffset, to: preset.oscillator1.detuneHz, duration: duration)
        ramp(oscillator2.$detuningOffset, to: preset.oscillator2.detuneHz, duration: duration)
        ramp(subOscillator.$index, to: preset.subOscillator.waveform == .square ? 1 : 0, duration: duration)
        ramp(subOscillator.$amplitude, to: preset.subOscillator.level, duration: duration)
        ramp(noise.$amplitude, to: preset.noiseLevel, duration: duration)
        applyEnvelope(preset, duration: duration)
        setFilterCutoff(mappedCutoff(for: preset), duration: duration)
        ramp(lowPass.$resonance, to: preset.filter.resonance * 40, duration: duration)
        rampOutput(expression: 0, pan: pan, duration: duration)
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) {
        controlExecutor.sync { noteOn(request, scheduledHostTime: nil) }
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest, atHostTime hostTime: TimeInterval) {
        controlExecutor.sync { noteOn(request, scheduledHostTime: hostTime) }
    }

    private func noteOn(_ request: DayObjectsTonalNoteRequest, scheduledHostTime: TimeInterval?) {
        guard let preset = currentPreset else { return }
        synchronizeGraphIfAttachedOnControlExecutor(
            transitionDuration: DayObjectsAudioParameters.presetTransitionDuration
        )
        currentMIDINote = Double(request.midiNote)
        expression = request.velocity * (request.role == .chord ? 0.72 : 1)
        pan = request.pan
        let envelope = request.envelopeVariant
        amplitudeEnvelope.attackDuration = AUValue(
            envelope?.absoluteAttackSeconds
                ?? preset.amplitudeEnvelope.attackSeconds * (envelope?.attackScale ?? 1)
        )
        amplitudeEnvelope.releaseDuration = AUValue(
            envelope?.absoluteReleaseSeconds
                ?? preset.amplitudeEnvelope.releaseSeconds * (envelope?.releaseScale ?? 1)
        )
        setFrequencies(midiNote: currentMIDINote, pitchSemitoneOffset: 0, duration: Float(preset.glideSeconds))
        rampOutput(expression: expression, pan: pan, duration: Float(DayObjectsAudioParameters.controlRampDuration))
        if let scheduledHostTime {
            gateScheduler.open(amplitudeEnvelope, atHostTime: scheduledHostTime)
        } else {
            amplitudeEnvelope.openGate()
        }
        startModulation()
    }

    func update(_ update: DayObjectsVoiceUpdate) {
        controlExecutor.sync {
            guard currentPreset != nil else { return }
            if let midiNote = update.midiNote { currentMIDINote = midiNote }
            if let expression = update.expression { self.expression = expression }
            if let pan = update.pan { self.pan = pan }
            if let cutoff = update.cutoffHz { modulationState?.updateBaseCutoffHz(cutoff) }
            guard output.avAudioNode.engine != nil else { return }
            if update.midiNote != nil {
                setFrequencies(
                    midiNote: currentMIDINote,
                    pitchSemitoneOffset: 0,
                    duration: Float(update.pitchRampSeconds ?? DayObjectsAudioParameters.controlRampDuration)
                )
            }
            if let cutoff = update.cutoffHz {
                setFilterCutoff(cutoff, duration: Float(update.cutoffRampSeconds ?? DayObjectsAudioParameters.controlRampDuration))
            }
            rampOutput(
                expression: expression,
                pan: pan,
                duration: Float(update.expressionRampSeconds ?? DayObjectsAudioParameters.controlRampDuration)
            )
        }
    }

    func noteOff() { noteOff(releaseSeconds: nil) }

    func noteOff(releaseSeconds: TimeInterval?) {
        controlExecutor.sync {
            guard currentPreset != nil else { return }
            let release = min(max(releaseSeconds ?? Double(amplitudeEnvelope.releaseDuration), 0), 30)
            amplitudeEnvelope.releaseDuration = AUValue(release)
            gateScheduler.close(amplitudeEnvelope)
            rampOutput(expression: 0, pan: pan, duration: Float(release))
            stopModulation()
        }
    }

    func advanceOfflineModulation() {
        controlExecutor.sync {
            guard output.avAudioNode.engine?.isInManualRenderingMode == true,
                  modulationLifecycle.isTimerActive else { return }
            applyModulation(at: modulationTime)
        }
    }

    private var modulationTime: TimeInterval {
        if let engine = output.avAudioNode.engine, engine.isInManualRenderingMode {
            return Double(engine.manualRenderingSampleTime) / engine.manualRenderingFormat.sampleRate
        }
        return Date.timeIntervalSinceReferenceDate
    }

    private func startModulation() {
        stopModulation()
        let now = modulationTime
        noteStartedAt = now
        currentFilterEnvelopeLevel = 0
        applyModulation(at: now)
        modulationLifecycle.start()
        guard output.avAudioNode.engine?.isInManualRenderingMode != true else { return }
        modulationTimer = controlExecutor.makeRepeatingTimer(interval: Self.modulationUpdateInterval) { [weak self] in
            self?.applyModulation(at: Date.timeIntervalSinceReferenceDate)
        }
    }

    private func stopModulation() {
        modulationTimer?.setEventHandler {}
        modulationTimer?.cancel()
        modulationTimer = nil
        modulationLifecycle.stop()
        noteStartedAt = nil
    }

    private func applyModulation(at now: TimeInterval) {
        guard let state = modulationState, let noteStartedAt else {
            stopModulation()
            return
        }
        guard output.avAudioNode.engine != nil else {
            stopModulation()
            return
        }
        let elapsed = now - noteStartedAt
        let envelope = state.plan.filterEnvelope
        let level: Double
        if elapsed < envelope.attackSeconds {
            level = elapsed / max(envelope.attackSeconds, 0.000_001)
        } else if elapsed < envelope.attackSeconds + envelope.decaySeconds {
            let progress = (elapsed - envelope.attackSeconds) / max(envelope.decaySeconds, 0.000_001)
            level = 1 - (1 - envelope.sustainLevel) * progress
        } else {
            level = envelope.sustainLevel
        }
        currentFilterEnvelopeLevel = level
        let phase = elapsed * state.plan.lfo.rateHz
        setFrequencies(
            midiNote: currentMIDINote,
            pitchSemitoneOffset: state.plan.pitchSemitoneOffset(phase: phase),
            duration: Float(Self.modulationUpdateInterval)
        )
        setFilterCutoff(
            state.filterCutoff(envelopeLevel: level, lfoPhase: phase),
            duration: Float(Self.modulationUpdateInterval)
        )
    }

    private func applyEnvelope(_ preset: NormalizedSynthVoice, duration: Float) {
        let envelope = preset.amplitudeEnvelope
        ramp(amplitudeEnvelope.$attackDuration, to: envelope.attackSeconds, duration: duration)
        ramp(amplitudeEnvelope.$decayDuration, to: envelope.decaySeconds, duration: duration)
        ramp(amplitudeEnvelope.$sustainLevel, to: envelope.sustainLevel, duration: duration)
        ramp(amplitudeEnvelope.$releaseDuration, to: envelope.releaseSeconds, duration: duration)
    }

    private func mappedCutoff(for preset: NormalizedSynthVoice) -> Double {
        switch preset.filter.kind {
        case .lowPass: preset.filter.cutoffHz
        case .bandPass: min(max(preset.filter.cutoffHz * 1.6, 1_200), 14_000)
        case .highPass: min(max(preset.filter.cutoffHz * 2, 6_000), 16_000)
        }
    }

    private func setFrequencies(midiNote: Double, pitchSemitoneOffset: Double, duration: Float) {
        guard let preset = currentPreset else { return }
        ramp(oscillator1.$frequency, to: Self.frequency(midiNote + Double(preset.oscillator1.semitoneOffset) + pitchSemitoneOffset), duration: duration)
        ramp(oscillator2.$frequency, to: Self.frequency(midiNote + Double(preset.oscillator2.semitoneOffset) + pitchSemitoneOffset), duration: duration)
        ramp(subOscillator.$frequency, to: Self.frequency(midiNote + Double(preset.subOscillator.octaveOffset * 12) + pitchSemitoneOffset), duration: duration)
    }

    private func setFilterCutoff(_ cutoff: Double, duration: Float) {
        ramp(
            lowPass.$cutoffFrequency,
            to: min(max(cutoff, DayObjectsAudioParameters.minimumCutoffHz), DayObjectsAudioParameters.maximumCutoffHz),
            duration: duration
        )
    }

    private func rampOutput(expression: Double, pan: Double, duration: Float) {
        let gain = baseOutputGain * expression
        ramp(output.$leftGain, to: gain * (pan > 0 ? 1 - pan : 1), duration: duration)
        ramp(output.$rightGain, to: gain * (pan < 0 ? 1 + pan : 1), duration: duration)
    }

    private func ramp(_ parameter: NodeParameter, to target: Double, duration: Float) {
        let value = AUValue(target)
        if parameter.parameter.flags.contains(.flag_CanRamp) {
            parameter.ramp(to: value, duration: max(0, duration))
        } else {
            parameter.value = value
        }
    }

    private static func frequency(_ midiNote: Double) -> Double {
        440 * pow(2, (midiNote - 69) / 12)
    }

    private var nodes: [any Node] {
        [oscillator1, oscillator2, subOscillator, noise, sourceMixer, lowPass, amplitudeEnvelope, output]
    }
}
#endif
