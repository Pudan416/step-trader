#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
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
    let autoPanCount: Int
    let delaySendCount: Int
    let reverbSendCount: Int
    let outputTrimCount: Int
    let allocatedNodeCount: Int
}

enum DayObjectsTonalPoolPreparationError: Error, Equatable {
    case missingInstrument(DayObjectsInstrumentID)
}

final class DayObjectsAudioKitTonalPool {
    let pool: DayObjectsTonalVoicePool
    let output: Mixer

    var voiceNodeIdentities: [ObjectIdentifier] {
        voices.flatMap(\.nodeIdentities)
    }

    private let voices: [DayObjectsTonalVoice]

    init(
        specification: DayObjectsTonalPoolSpecification,
        instruments: [DayObjectsInstrumentID: NormalizedSynthVoice]
    ) {
        let builtVoices = (0..<specification.capacity).map { _ in DayObjectsTonalVoice() }
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
            }
        )
    }
}

final class DayObjectsTonalVoice: DayObjectsTonalVoiceBackend {
    static let graphLayout = DayObjectsTonalVoiceGraphLayout(
        morphingOscillatorCount: 2,
        subOscillatorCount: 1,
        noiseGeneratorCount: 1,
        filterBranchCount: 3,
        envelopeCount: 2,
        normalizedLFORouteCount: 1,
        phaserCount: 1,
        autoPanCount: 1,
        delaySendCount: 1,
        reverbSendCount: 1,
        outputTrimCount: 1,
        allocatedNodeCount: 35
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

    private let filterColor: LowPassFilter
    private let filterEnvelope: AmplitudeEnvelope
    private let filterDryFader: Fader
    private let filterEnvelopeFader: Fader
    private let filterEnvelopeMixer: Mixer
    private let amplitudeEnvelope: AmplitudeEnvelope

    private let pitchVibrato: Vibrato
    private let lfoDryFader: Fader
    private let filterLFOHighPass: HighPassFilter
    private let filterLFOTremolo: Tremolo
    private let filterLFOFader: Fader
    private let filterLFOMixer: Mixer
    private let amplitudeTremolo: Tremolo

    private let phaser: Phaser
    private let autoPanner: AutoPanner
    private let dryFader: Fader
    private let delaySendFader: Fader
    private let delay: Delay
    private let reverbSendFader: Fader
    private let reverbHighPass: HighPassFilter
    private let reverb: CostelloReverb
    private let effectsMixer: Mixer

    private var currentPreset: NormalizedSynthVoice?
    private var currentMIDINote = 60.0
    private var baseOutputGain = 0.0
    private var expression = 1.0
    private var pan = 0.0
    private var delayMix = 0.0
    private var reverbMix = 0.0
    private var delaySend = 1.0
    private var reverbSend = 1.0
    private var isGateOpen = false

    init() {
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

        filterColor = LowPassFilter(filterMixer, cutoffFrequency: 12_000, resonance: 0)
        filterEnvelope = AmplitudeEnvelope(filterColor, sustainLevel: 0)
        filterDryFader = Fader(filterMixer, gain: 1)
        filterEnvelopeFader = Fader(filterEnvelope, gain: 0)
        filterEnvelopeMixer = Mixer(filterDryFader, filterEnvelopeFader)
        amplitudeEnvelope = AmplitudeEnvelope(filterEnvelopeMixer, sustainLevel: 0)

        pitchVibrato = Vibrato(amplitudeEnvelope, speed: 1, depth: 0)
        lfoDryFader = Fader(pitchVibrato, gain: 1)
        filterLFOHighPass = HighPassFilter(pitchVibrato, cutoffFrequency: 2_000, resonance: 0)
        filterLFOTremolo = Tremolo(filterLFOHighPass, frequency: 1, depth: 0)
        filterLFOFader = Fader(filterLFOTremolo, gain: 0)
        filterLFOMixer = Mixer(lfoDryFader, filterLFOFader)
        amplitudeTremolo = Tremolo(filterLFOMixer, frequency: 1, depth: 0)

        phaser = Phaser(amplitudeTremolo, dryWetMix: 0)
        autoPanner = AutoPanner(phaser, frequency: 0.25, depth: 0)
        dryFader = Fader(autoPanner, gain: 1)
        delaySendFader = Fader(autoPanner, gain: 0)
        delay = Delay(delaySendFader, time: 0.25, feedback: 0, dryWetMix: 100)
        reverbSendFader = Fader(autoPanner, gain: 0)
        reverbHighPass = HighPassFilter(reverbSendFader, cutoffFrequency: 80, resonance: 0)
        reverb = CostelloReverb(reverbHighPass, balance: 1, feedback: 0.8, cutoffFrequency: 8_000)
        effectsMixer = Mixer(dryFader, delay, reverb)
        output = Fader(effectsMixer, gain: 0)
    }

    func replacePreset(
        _ rawPreset: NormalizedSynthVoice,
        instrumentID _: DayObjectsInstrumentID,
        transitionDuration: TimeInterval
    ) {
        noteOff()
        let preset = DayObjectsAudioParameters.clamped(rawPreset)
        currentPreset = preset
        baseOutputGain = DayObjectsAudioParameters.linearGain(decibels: preset.outputTrimDB)
        delayMix = preset.delay.isEnabled ? preset.delay.mix : 0
        reverbMix = preset.reverb.isEnabled ? preset.reverb.mix : 0

        guard isGraphAttached else { return }

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

        let envelope = request.envelopeVariant
        amplitudeEnvelope.attackDuration = value(
            preset.amplitudeEnvelope.attackSeconds * (envelope?.attackScale ?? 1)
        )
        amplitudeEnvelope.releaseDuration = value(
            preset.amplitudeEnvelope.releaseSeconds * (envelope?.releaseScale ?? 1)
        )
        setFrequencies(midiNote: currentMIDINote, duration: Float(preset.glideSeconds))
        rampEffects(duration: Float(DayObjectsAudioParameters.controlRampDuration))
        rampOutput(
            expression: expression,
            pan: pan,
            duration: Float(DayObjectsAudioParameters.controlRampDuration)
        )
        filterEnvelope.openGate()
        amplitudeEnvelope.openGate()
        isGateOpen = true
    }

    func update(_ update: DayObjectsVoiceUpdate) {
        guard currentPreset != nil else { return }
        let duration = Float(DayObjectsAudioParameters.controlRampDuration)
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

        guard isGraphAttached else { return }

        if let midiNote = update.midiNote {
            setFrequencies(midiNote: midiNote, duration: duration)
        }
        if let cutoffHz = update.cutoffHz {
            setFilterCutoff(cutoffHz, duration: duration)
        }
        rampEffects(duration: duration)
        rampOutput(expression: expression, pan: pan, duration: duration)
    }

    func noteOff() {
        guard isGateOpen else { return }
        defer { isGateOpen = false }
        guard isGraphAttached else { return }
        filterEnvelope.closeGate()
        amplitudeEnvelope.closeGate()
        let release = currentPreset?.amplitudeEnvelope.releaseSeconds ?? 0.05
        rampOutput(expression: 0, pan: pan, duration: Float(release))
    }

    private var isGraphAttached: Bool {
        output.avAudioNode.engine != nil
    }

    private var nodes: [any Node] {
        [
            oscillator1, oscillator2, subOscillator, noise, sourceMixer,
            lowPass, bandPass, highPass, lowPassFader, bandPassFader, highPassFader, filterMixer,
            filterColor, filterEnvelope, filterDryFader, filterEnvelopeFader, filterEnvelopeMixer,
            amplitudeEnvelope, pitchVibrato, lfoDryFader, filterLFOHighPass, filterLFOTremolo,
            filterLFOFader, filterLFOMixer, amplitudeTremolo, phaser, autoPanner, dryFader,
            delaySendFader, delay, reverbSendFader, reverbHighPass, reverb, effectsMixer, output,
        ]
    }

    private func applyFilter(_ filter: NormalizedSynthVoice.Filter, duration: Float) {
        setFilterCutoff(filter.cutoffHz, duration: duration)
        let resonanceDB = filter.resonance * 40
        ramp(lowPass.$resonance, to: resonanceDB, duration: duration)
        ramp(highPass.$resonance, to: resonanceDB, duration: duration)
        ramp(bandPass.$bandwidth, to: 12_000 - filter.resonance * 11_900, duration: duration)
        ramp(lowPassFader, to: filter.kind == .lowPass ? 1 : 0, duration: duration)
        ramp(bandPassFader, to: filter.kind == .bandPass ? 1 : 0, duration: duration)
        ramp(highPassFader, to: filter.kind == .highPass ? 1 : 0, duration: duration)

        let amount = abs(filter.envelopeAmount)
        ramp(filterDryFader, to: 1 - amount * 0.5, duration: duration)
        ramp(filterEnvelopeFader, to: amount, duration: duration)
    }

    private func applyEnvelopes(_ preset: NormalizedSynthVoice, duration: Float) {
        let filter = preset.filter.envelope
        ramp(filterEnvelope.$attackDuration, to: filter.attackSeconds, duration: duration)
        ramp(filterEnvelope.$decayDuration, to: filter.decaySeconds, duration: duration)
        ramp(filterEnvelope.$sustainLevel, to: filter.sustainLevel, duration: duration)
        ramp(filterEnvelope.$releaseDuration, to: filter.releaseSeconds, duration: duration)

        let amplitude = preset.amplitudeEnvelope
        ramp(amplitudeEnvelope.$attackDuration, to: amplitude.attackSeconds, duration: duration)
        ramp(amplitudeEnvelope.$decayDuration, to: amplitude.decaySeconds, duration: duration)
        ramp(amplitudeEnvelope.$sustainLevel, to: amplitude.sustainLevel, duration: duration)
        ramp(amplitudeEnvelope.$releaseDuration, to: amplitude.releaseSeconds, duration: duration)
    }

    private func applyLFO(_ lfo: NormalizedSynthVoice.LFO, duration: Float) {
        let table = Self.lfoTable(lfo.waveform)
        filterLFOTremolo.setWaveform(table)
        amplitudeTremolo.setWaveform(table)
        ramp(pitchVibrato.$speed, to: lfo.rateHz, duration: duration)
        ramp(filterLFOTremolo.$frequency, to: lfo.rateHz, duration: duration)
        ramp(amplitudeTremolo.$frequency, to: lfo.rateHz, duration: duration)

        ramp(
            pitchVibrato.$depth,
            to: lfo.target == .pitch ? lfo.depth * 2 : 0,
            duration: duration
        )
        ramp(
            filterLFOTremolo.$depth,
            to: lfo.target == .filter ? lfo.depth : 0,
            duration: duration
        )
        ramp(filterLFOFader, to: lfo.target == .filter ? lfo.depth : 0, duration: duration)
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

    private func setFrequencies(midiNote: Double, duration: Float) {
        guard let preset = currentPreset else { return }
        ramp(
            oscillator1.$frequency,
            to: Self.frequency(midiNote + Double(preset.oscillator1.semitoneOffset)),
            duration: duration
        )
        ramp(
            oscillator2.$frequency,
            to: Self.frequency(midiNote + Double(preset.oscillator2.semitoneOffset)),
            duration: duration
        )
        ramp(
            subOscillator.$frequency,
            to: Self.frequency(midiNote + Double(preset.subOscillator.octaveOffset * 12)),
            duration: duration
        )
    }

    private func setFilterCutoff(_ cutoffHz: Double, duration: Float) {
        guard let preset = currentPreset else { return }
        let bounded = min(max(cutoffHz, DayObjectsAudioParameters.minimumCutoffHz), DayObjectsAudioParameters.maximumCutoffHz)
        ramp(lowPass.$cutoffFrequency, to: bounded, duration: duration)
        ramp(bandPass.$centerFrequency, to: bounded, duration: duration)
        ramp(highPass.$cutoffFrequency, to: bounded, duration: duration)
        ramp(filterLFOHighPass.$cutoffFrequency, to: bounded, duration: duration)

        let colorCutoff = min(
            max(bounded * pow(2, preset.filter.envelopeAmount * 4), DayObjectsAudioParameters.minimumCutoffHz),
            DayObjectsAudioParameters.maximumCutoffHz
        )
        ramp(filterColor.$cutoffFrequency, to: colorCutoff, duration: duration)
    }

    private func rampEffects(duration: Float) {
        ramp(delaySendFader, to: delayMix * delaySend, duration: duration)
        ramp(reverbSendFader, to: reverbMix * reverbSend, duration: duration)
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
#endif
