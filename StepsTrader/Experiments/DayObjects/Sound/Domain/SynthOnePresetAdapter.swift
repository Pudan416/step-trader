#if DEBUG || INTERNAL_BUILD
import Foundation

struct SynthOnePresetRecord: Decodable, Equatable, Sendable {
    let uid: String
    let name: String

    var waveform1: Double? = nil
    var waveform2: Double? = nil
    var vco1Volume: Double? = nil
    var vco2Volume: Double? = nil
    var vco1Semitone: Double? = nil
    var vco2Semitone: Double? = nil
    var vco2Detuning: Double? = nil
    var vcoBalance: Double? = nil
    var subVolume: Double? = nil
    var subOscSquareToggled: Int? = nil
    var subOsc24Toggled: Int? = nil
    var noiseVolume: Double? = nil

    var attackDuration: Double? = nil
    var decayDuration: Double? = nil
    var sustainLevel: Double? = nil
    var releaseDuration: Double? = nil
    var glide: Double? = nil
    var isMono: Int? = nil

    var filterType: Int? = nil
    var cutoff: Double? = nil
    var resonance: Double? = nil
    var filterAttack: Double? = nil
    var filterDecay: Double? = nil
    var filterSustain: Double? = nil
    var filterRelease: Double? = nil
    var filterADSRMix: Double? = nil

    var lfoAmplitude: Double? = nil
    var lfoRate: Double? = nil
    var lfoWaveform: Int? = nil
    var pitchLFO: Double? = nil
    var cutoffLFO: Double? = nil
    var tremoloLFO: Double? = nil

    var delayToggled: Int? = nil
    var delayTime: Double? = nil
    var delayFeedback: Double? = nil
    var delayMix: Double? = nil
    var reverbToggled: Int? = nil
    var reverbFeedback: Double? = nil
    var reverbHighPass: Double? = nil
    var reverbMix: Double? = nil
    var phaserRate: Double? = nil
    var phaserFeedback: Double? = nil
    var phaserMix: Double? = nil
    var phaserNotchWidth: Double? = nil
    var autoPanFrequency: Double? = nil
    var autoPanAmount: Double? = nil
    var widen: Double? = nil

    var isArpMode: Int? = nil
    var arpIsSequencer: Bool? = nil
    var isHoldMode: Int? = nil
    var frequencyA4: Double? = nil
    var tuningName: String? = nil
    var tuningMasterSet: [Double]? = nil
    var midiBendRange: Double? = nil
    var pitchbendMaxSemitones: Double? = nil
    var pitchbendMinSemitones: Double? = nil
    var modWheelRouting: Double? = nil
    var bitcrushLFO: Double? = nil
    var crushFreq: Double? = nil
    var fmAmount: Double? = nil
    var fmVolume: Double? = nil
    var fmLFO: Double? = nil
    var oscMixLFO: Double? = nil
    var noiseLFO: Double? = nil
    var resonanceLFO: Double? = nil
    var filterEnvLFO: Double? = nil
    var detuneLFO: Double? = nil
    var decayLFO: Double? = nil
    var reverbMixLFO: Double? = nil
    var lfo2Amplitude: Double? = nil
    var lfo2Rate: Double? = nil
    var lfo2Waveform: Double? = nil

    var compressorMasterAttack: Double? = nil
    var compressorMasterMakeupGain: Double? = nil
    var compressorMasterRatio: Double? = nil
    var compressorMasterRelease: Double? = nil
    var compressorMasterThreshold: Double? = nil
    var compressorReverbInputAttack: Double? = nil
    var compressorReverbInputMakeupGain: Double? = nil
    var compressorReverbInputRatio: Double? = nil
    var compressorReverbInputRelease: Double? = nil
    var compressorReverbInputThreshold: Double? = nil
    var compressorReverbWetAttack: Double? = nil
    var compressorReverbWetMakeupGain: Double? = nil
    var compressorReverbWetRatio: Double? = nil
    var compressorReverbWetRelease: Double? = nil
    var compressorReverbWetThreshold: Double? = nil
    var delayInputCutoffTrackingRatio: Double? = nil
    var delayInputResonance: Double? = nil
    var masterVolume: Double? = nil

    var adsrPitchTracking: Double? = nil
    var isLegato: Int? = nil
    var octavePosition: Int? = nil
    var transpose: Int? = nil

    // Source metadata and inert engine settings are retained so the selected
    // upstream schema is explicit even though they do not drive conversion.
    var author: String? = nil
    var bank: String? = nil
    var category: Int? = nil
    var position: Int? = nil
    var userText: String? = nil
    var isFavorite: Bool? = nil
    var isUser: Bool? = nil
    var arpDirection: Int? = nil
    var arpInterval: Int? = nil
    var arpOctave: Int? = nil
    var arpRate: Double? = nil
    var arpSeqTempoMultiplier: Double? = nil
    var arpTotalSteps: Int? = nil
    var seqNoteOn: [Bool]? = nil
    var seqOctBoost: [Bool]? = nil
    var seqPatternNote: [Int]? = nil
    var tempoSyncToArpRate: Int? = nil
    var oscBandlimitEnable: Int? = nil
    var oscBandlimitIndexOverride: Int? = nil
}

struct SynthOneAdapterDiagnostic: Equatable, Hashable, Sendable {
    enum Code: String, Equatable, Hashable, Sendable {
        case defaultedValue
        case nonFiniteValue
        case clampedValue
        case unknownDescriptor
        case unsupportedArpeggiatorSequencer
        case unsupportedHold
        case unsupportedCustomTuning
        case unsupportedMIDIMapping
        case unsupportedBitCrush
        case unsupportedFM
        case unsupportedModulationRoute
        case unsupportedCompressor
        case unsupportedDelayRouting
        case unsupportedSourceGain
        case unsupportedPerformanceMode
    }

    let code: Code
    let field: String

    var sortKey: String { "\(code.rawValue):\(field)" }
}

struct SynthOneConversionResult: Equatable, Sendable {
    let voice: NormalizedSynthVoice
    let diagnostics: [SynthOneAdapterDiagnostic]
}

enum SynthOnePresetAdapter {
    static func convert(_ source: SynthOnePresetRecord) -> SynthOneConversionResult {
        var diagnostics: [SynthOneAdapterDiagnostic] = []

        let oscillator1 = NormalizedSynthVoice.Oscillator(
            wavePosition: value(source.waveform1, default: 0.5, in: 0...1, field: "waveform1", diagnostics: &diagnostics),
            level: value(source.vco1Volume, default: 0.5, in: 0...1, field: "vco1Volume", diagnostics: &diagnostics),
            semitoneOffset: integer(source.vco1Semitone, default: 0, in: -24...24, field: "vco1Semitone", diagnostics: &diagnostics),
            fineDetuneSemitones: 0
        )
        let oscillator2 = NormalizedSynthVoice.Oscillator(
            wavePosition: value(source.waveform2, default: 0.5, in: 0...1, field: "waveform2", diagnostics: &diagnostics),
            level: value(source.vco2Volume, default: 0.5, in: 0...1, field: "vco2Volume", diagnostics: &diagnostics),
            semitoneOffset: integer(source.vco2Semitone, default: 0, in: -24...24, field: "vco2Semitone", diagnostics: &diagnostics),
            fineDetuneSemitones: value(source.vco2Detuning, default: 0, in: -12...12, field: "vco2Detuning", diagnostics: &diagnostics)
        )

        let amplitudeEnvelope = envelope(
            attack: source.attackDuration,
            decay: source.decayDuration,
            sustain: source.sustainLevel,
            release: source.releaseDuration,
            prefix: "",
            diagnostics: &diagnostics
        )
        let filterEnvelope = envelope(
            attack: source.filterAttack,
            decay: source.filterDecay,
            sustain: source.filterSustain,
            release: source.filterRelease,
            prefix: "filter",
            diagnostics: &diagnostics
        )
        let filter = NormalizedSynthVoice.Filter(
            kind: filterKind(source.filterType, diagnostics: &diagnostics),
            cutoffHz: value(source.cutoff, default: 12_000, in: 20...18_000, field: "cutoff", diagnostics: &diagnostics),
            resonance: value(source.resonance, default: 0.1, in: 0...0.95, field: "resonance", diagnostics: &diagnostics),
            envelope: filterEnvelope,
            envelopeAmount: value(source.filterADSRMix, default: 0, in: -1...1, field: "filterADSRMix", diagnostics: &diagnostics)
        )

        let lfo = makeLFO(source, diagnostics: &diagnostics)
        appendUnsupportedDiagnostics(source, diagnostics: &diagnostics)

        let descriptor = DayObjectsInstrumentManifest.defaultDescriptors.first { $0.sourceUID == source.uid }
        if descriptor == nil {
            diagnostics.append(.init(code: .unknownDescriptor, field: "uid"))
        }

        let voice = NormalizedSynthVoice(
            oscillator1: oscillator1,
            oscillator2: oscillator2,
            oscillatorBalance: value(source.vcoBalance, default: 0.5, in: 0...1, field: "vcoBalance", diagnostics: &diagnostics),
            subOscillator: .init(
                level: value(source.subVolume, default: 0, in: 0...1, field: "subVolume", diagnostics: &diagnostics),
                waveform: source.subOscSquareToggled == 1 ? .square : .sine,
                octaveOffset: source.subOsc24Toggled == 1 ? -2 : -1
            ),
            noiseLevel: value(source.noiseVolume, default: 0, in: 0...1, field: "noiseVolume", diagnostics: &diagnostics),
            amplitudeEnvelope: amplitudeEnvelope,
            filter: filter,
            glideSeconds: value(source.glide, default: 0, in: 0...2, field: "glide", diagnostics: &diagnostics),
            isMonophonic: source.isMono == 1,
            lfo: lfo,
            delay: .init(
                isEnabled: source.delayToggled == 1,
                timeSeconds: value(source.delayTime, default: 0.25, in: 0.001...2, field: "delayTime", diagnostics: &diagnostics),
                feedback: value(source.delayFeedback, default: 0.2, in: 0...0.9, field: "delayFeedback", diagnostics: &diagnostics),
                mix: value(source.delayMix, default: 0, in: 0...1, field: "delayMix", diagnostics: &diagnostics)
            ),
            reverb: .init(
                isEnabled: source.reverbToggled == 1,
                feedback: value(source.reverbFeedback, default: 0.8, in: 0...0.95, field: "reverbFeedback", diagnostics: &diagnostics),
                highPassHz: value(source.reverbHighPass, default: 80, in: 20...4_000, field: "reverbHighPass", diagnostics: &diagnostics),
                mix: value(source.reverbMix, default: 0, in: 0...1, field: "reverbMix", diagnostics: &diagnostics)
            ),
            phaser: .init(
                rateHz: value(source.phaserRate, default: 0.5, in: 0.01...20, field: "phaserRate", diagnostics: &diagnostics),
                feedback: value(source.phaserFeedback, default: 0, in: -0.95...0.95, field: "phaserFeedback", diagnostics: &diagnostics),
                mix: value(source.phaserMix, default: 0, in: 0...1, field: "phaserMix", diagnostics: &diagnostics),
                notchWidthHz: value(source.phaserNotchWidth, default: 800, in: 20...2_000, field: "phaserNotchWidth", diagnostics: &diagnostics)
            ),
            autoPan: .init(
                rateHz: value(source.autoPanFrequency, default: 0.25, in: 0.01...20, field: "autoPanFrequency", diagnostics: &diagnostics),
                depth: value(source.autoPanAmount, default: 0, in: 0...1, field: "autoPanAmount", diagnostics: &diagnostics),
                stereoWidth: value(source.widen, default: 0, in: 0...1, field: "widen", diagnostics: &diagnostics)
            ),
            outputTrimDB: descriptor?.outputTrimDB ?? -18,
            referenceMIDI: descriptor?.referenceMIDI ?? 60,
            auditionChord: descriptor?.auditionChord ?? [48, 55, 62, 67]
        )

        return SynthOneConversionResult(
            voice: voice,
            diagnostics: diagnostics.sorted { $0.sortKey < $1.sortKey }
        )
    }

    private static func envelope(
        attack: Double?,
        decay: Double?,
        sustain: Double?,
        release: Double?,
        prefix: String,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> NormalizedSynthVoice.Envelope {
        let names = prefix.isEmpty
            ? ("attackDuration", "decayDuration", "sustainLevel", "releaseDuration")
            : ("filterAttack", "filterDecay", "filterSustain", "filterRelease")
        return .init(
            attackSeconds: value(attack, default: 0.05, in: 0...30, field: names.0, diagnostics: &diagnostics),
            decaySeconds: value(decay, default: 0.2, in: 0...30, field: names.1, diagnostics: &diagnostics),
            sustainLevel: value(sustain, default: 0.8, in: 0...1, field: names.2, diagnostics: &diagnostics),
            releaseSeconds: value(release, default: 0.4, in: 0...30, field: names.3, diagnostics: &diagnostics)
        )
    }

    private static func makeLFO(
        _ source: SynthOnePresetRecord,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> NormalizedSynthVoice.LFO {
        let routes: [(NormalizedSynthVoice.LFOTarget, Double?)] = [
            (.pitch, source.pitchLFO),
            (.filter, source.cutoffLFO),
            (.amplitude, source.tremoloLFO),
        ]
        let active = routes.filter { isActive($0.1) }
        if active.count > 1 {
            diagnostics.append(.init(code: .unsupportedModulationRoute, field: "multiplePrimaryLFORoutes"))
        }
        return .init(
            target: active.first?.0 ?? .none,
            rateHz: value(source.lfoRate, default: 1, in: 0.01...30, field: "lfoRate", diagnostics: &diagnostics),
            depth: value(source.lfoAmplitude, default: 0, in: 0...1, field: "lfoAmplitude", diagnostics: &diagnostics),
            waveform: lfoWaveform(source.lfoWaveform, diagnostics: &diagnostics)
        )
    }

    private static func lfoWaveform(
        _ source: Int?,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> NormalizedSynthVoice.LFOWaveform {
        guard let source else {
            diagnostics.append(.init(code: .defaultedValue, field: "lfoWaveform"))
            return .sine
        }
        guard let waveform = NormalizedSynthVoice.LFOWaveform(rawValue: source) else {
            diagnostics.append(.init(code: .clampedValue, field: "lfoWaveform"))
            return .sine
        }
        return waveform
    }

    private static func appendUnsupportedDiagnostics(
        _ source: SynthOnePresetRecord,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) {
        if source.isArpMode == 1 {
            diagnostics.append(.init(code: .unsupportedArpeggiatorSequencer, field: source.arpIsSequencer == true ? "sequencer" : "arpeggiator"))
        }
        if source.isHoldMode == 1 {
            diagnostics.append(.init(code: .unsupportedHold, field: "isHoldMode"))
        }
        if isCustomTuning(source) {
            diagnostics.append(.init(code: .unsupportedCustomTuning, field: "tuning"))
        }
        if isActive(source.modWheelRouting) {
            diagnostics.append(.init(code: .unsupportedMIDIMapping, field: "modWheelRouting"))
        }
        if source.midiBendRange != nil || source.pitchbendMaxSemitones != nil
            || source.pitchbendMinSemitones != nil {
            diagnostics.append(.init(code: .unsupportedMIDIMapping, field: "pitchBendConfiguration"))
        }
        if isActive(source.bitcrushLFO) || (source.crushFreq.map { $0 != 48_000 } ?? false) {
            diagnostics.append(.init(code: .unsupportedBitCrush, field: "bitCrush"))
        }
        if [source.fmAmount, source.fmVolume, source.fmLFO].contains(where: isActive) {
            diagnostics.append(.init(code: .unsupportedFM, field: "fm"))
        }
        let extraRoutes = [
            source.oscMixLFO, source.noiseLFO, source.resonanceLFO, source.filterEnvLFO,
            source.detuneLFO, source.decayLFO, source.reverbMixLFO, source.lfo2Amplitude,
        ]
        if extraRoutes.contains(where: isActive) {
            diagnostics.append(.init(code: .unsupportedModulationRoute, field: "additionalModulation"))
        }
        let compressorFields = [
            source.compressorMasterAttack, source.compressorMasterMakeupGain, source.compressorMasterRatio,
            source.compressorMasterRelease, source.compressorMasterThreshold,
            source.compressorReverbInputAttack, source.compressorReverbInputMakeupGain,
            source.compressorReverbInputRatio, source.compressorReverbInputRelease,
            source.compressorReverbInputThreshold, source.compressorReverbWetAttack,
            source.compressorReverbWetMakeupGain, source.compressorReverbWetRatio,
            source.compressorReverbWetRelease, source.compressorReverbWetThreshold,
        ]
        if compressorFields.contains(where: { $0 != nil }) {
            diagnostics.append(.init(code: .unsupportedCompressor, field: "compressor"))
        }
        if source.delayInputCutoffTrackingRatio != nil || source.delayInputResonance != nil {
            diagnostics.append(.init(code: .unsupportedDelayRouting, field: "delayInputRouting"))
        }
        if source.masterVolume != nil {
            diagnostics.append(.init(code: .unsupportedSourceGain, field: "masterVolume"))
        }
        if source.isLegato == 1 || source.octavePosition.map({ $0 != 0 }) == true
            || source.transpose.map({ $0 != 0 }) == true || isActive(source.adsrPitchTracking) {
            diagnostics.append(.init(code: .unsupportedPerformanceMode, field: "performanceConfiguration"))
        }
    }

    private static func isCustomTuning(_ source: SynthOnePresetRecord) -> Bool {
        if let frequency = source.frequencyA4, (!frequency.isFinite || frequency != 440) { return true }
        if let name = source.tuningName, name != "12 ET" { return true }
        guard let tuning = source.tuningMasterSet else { return false }
        let twelveET = (0..<12).map { pow(2, Double($0) / 12) }
        return tuning.count != twelveET.count || zip(tuning, twelveET).contains { abs($0 - $1) > 0.000_001 }
    }

    private static func filterKind(
        _ source: Int?,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> NormalizedSynthVoice.FilterKind {
        guard let source else {
            diagnostics.append(.init(code: .defaultedValue, field: "filterType"))
            return .lowPass
        }
        guard let kind = NormalizedSynthVoice.FilterKind(rawValue: source) else {
            diagnostics.append(.init(code: .clampedValue, field: "filterType"))
            return .lowPass
        }
        return kind
    }

    private static func value(
        _ source: Double?,
        default defaultValue: Double,
        in range: ClosedRange<Double>,
        field: String,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> Double {
        guard let source else {
            diagnostics.append(.init(code: .defaultedValue, field: field))
            return defaultValue
        }
        guard source.isFinite else {
            diagnostics.append(.init(code: .nonFiniteValue, field: field))
            return defaultValue
        }
        let result = min(max(source, range.lowerBound), range.upperBound)
        if result != source {
            diagnostics.append(.init(code: .clampedValue, field: field))
        }
        return result
    }

    private static func integer(
        _ source: Double?,
        default defaultValue: Int,
        in range: ClosedRange<Int>,
        field: String,
        diagnostics: inout [SynthOneAdapterDiagnostic]
    ) -> Int {
        guard let source else {
            diagnostics.append(.init(code: .defaultedValue, field: field))
            return defaultValue
        }
        guard source.isFinite else {
            diagnostics.append(.init(code: .nonFiniteValue, field: field))
            return defaultValue
        }
        let bounded = min(max(source, Double(range.lowerBound)), Double(range.upperBound))
        let result = Int(bounded.rounded())
        if Double(result) != source {
            diagnostics.append(.init(code: .clampedValue, field: field))
        }
        return result
    }

    private static func isActive(_ value: Double?) -> Bool {
        guard let value else { return false }
        return !value.isFinite || value != 0
    }
}
#endif
