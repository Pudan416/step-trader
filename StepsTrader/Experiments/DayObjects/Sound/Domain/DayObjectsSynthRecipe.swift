import CryptoKit
import Foundation

enum DayObjectsSynthRole: String, Codable, CaseIterable, Sendable {
    case harmony, bass, lead

    var category: DayObjectsInstrumentCategory {
        switch self {
        case .harmony: .pad
        case .bass: .bass
        case .lead: .lead
        }
    }
}

struct DayObjectsSynthPatch: Codable, Equatable, Sendable {
    var oscillator1WaveOffset: Double = 0
    var oscillator2WaveOffset: Double = 0
    var oscillatorBalanceOffset: Double = 0
    var subLevelOffset: Double = 0
    var noiseLevelOffset: Double = 0
    var cutoffMultiplier: Double = 1
    var resonanceOffset: Double = 0
    var attackMultiplier: Double = 1
    var releaseMultiplier: Double = 1
    var lfoRateMultiplier: Double = 1
    var lfoDepthMultiplier: Double = 1
    var delayMixOffset: Double = 0
    var reverbMixOffset: Double = 0

    var isFinite: Bool {
        [oscillator1WaveOffset, oscillator2WaveOffset, oscillatorBalanceOffset,
         subLevelOffset, noiseLevelOffset, cutoffMultiplier, resonanceOffset,
         attackMultiplier, releaseMultiplier, lfoRateMultiplier, lfoDepthMultiplier,
         delayMixOffset, reverbMixOffset].allSatisfy(\.isFinite)
    }

    fileprivate func applying(to voice: NormalizedSynthVoice) -> NormalizedSynthVoice {
        func oscillator(_ value: NormalizedSynthVoice.Oscillator, offset: Double) -> NormalizedSynthVoice.Oscillator {
            .init(wavePosition: value.wavePosition + offset, level: value.level,
                  semitoneOffset: value.semitoneOffset, detuneHz: value.detuneHz)
        }
        func envelope(_ value: NormalizedSynthVoice.Envelope) -> NormalizedSynthVoice.Envelope {
            .init(attackSeconds: value.attackSeconds * attackMultiplier, decaySeconds: value.decaySeconds,
                  sustainLevel: value.sustainLevel, releaseSeconds: value.releaseSeconds * releaseMultiplier)
        }
        let delayMix = voice.delay.mix + delayMixOffset
        let reverbMix = voice.reverb.mix + reverbMixOffset
        return .init(
            oscillator1: oscillator(voice.oscillator1, offset: oscillator1WaveOffset),
            oscillator2: oscillator(voice.oscillator2, offset: oscillator2WaveOffset),
            oscillatorBalance: voice.oscillatorBalance + oscillatorBalanceOffset,
            subOscillator: .init(level: voice.subOscillator.level + subLevelOffset,
                                 waveform: voice.subOscillator.waveform, octaveOffset: voice.subOscillator.octaveOffset),
            noiseLevel: voice.noiseLevel + noiseLevelOffset,
            amplitudeEnvelope: envelope(voice.amplitudeEnvelope),
            filter: .init(kind: voice.filter.kind, cutoffHz: voice.filter.cutoffHz * cutoffMultiplier,
                          resonance: voice.filter.resonance + resonanceOffset, envelope: envelope(voice.filter.envelope),
                          envelopeAmount: voice.filter.envelopeAmount),
            glideSeconds: voice.glideSeconds, isMonophonic: voice.isMonophonic,
            lfo: .init(target: voice.lfo.target, rateHz: voice.lfo.rateHz * lfoRateMultiplier,
                       depth: voice.lfo.depth * lfoDepthMultiplier, waveform: voice.lfo.waveform),
            delay: .init(isEnabled: delayMix > 0, timeSeconds: voice.delay.timeSeconds,
                         feedback: voice.delay.feedback, mix: delayMix),
            reverb: .init(isEnabled: reverbMix > 0, feedback: voice.reverb.feedback,
                          highPassHz: voice.reverb.highPassHz, mix: reverbMix),
            phaser: voice.phaser, autoPan: voice.autoPan, outputTrimDB: voice.outputTrimDB,
            referenceMIDI: voice.referenceMIDI, auditionChord: voice.auditionChord
        )
    }
}

struct DayObjectsMoodPatch: Codable, Equatable, Sendable {
    let mood: DayObjectsSoundMood
    let patch: DayObjectsSynthPatch
}

struct DayObjectsSynthRecipe: Codable, Equatable, Sendable {
    let id: DayObjectsInstrumentID
    let world: DayObjectsSoundWorld
    let role: DayObjectsSynthRole
    let family: String
    let sourceInstrumentID: DayObjectsInstrumentID
    let basePatch: DayObjectsSynthPatch
    let moodPatches: [DayObjectsMoodPatch]
    let referenceMIDI: UInt8
    let outputTrimDB: Double

    /// Base IDs name editable families; only these mood-specific IDs bind runtime voices.
    func resolvedInstrumentID(for mood: DayObjectsSoundMood) -> DayObjectsInstrumentID {
        .init(rawValue: "\(id.rawValue).\(mood.rawValue)")
    }

    func resolvedVoice(
        mood: DayObjectsSoundMood,
        sourceVoices: [DayObjectsInstrumentID: NormalizedSynthVoice]
    ) throws -> NormalizedSynthVoice {
        try validate(sourceVoices: sourceVoices)
        guard let source = sourceVoices[sourceInstrumentID],
              let moodPatch = moodPatches.first(where: { $0.mood == mood }) else {
            throw DayObjectsSoundWorldCatalogError.invalidRecipe(id.rawValue)
        }
        let patched = moodPatch.patch.applying(to: basePatch.applying(to: source))
        let voice = NormalizedSynthVoice(
            oscillator1: patched.oscillator1, oscillator2: patched.oscillator2,
            oscillatorBalance: patched.oscillatorBalance, subOscillator: patched.subOscillator,
            noiseLevel: patched.noiseLevel, amplitudeEnvelope: patched.amplitudeEnvelope,
            filter: patched.filter, glideSeconds: patched.glideSeconds, isMonophonic: patched.isMonophonic,
            lfo: patched.lfo, delay: patched.delay, reverb: patched.reverb,
            phaser: patched.phaser, autoPan: patched.autoPan, outputTrimDB: outputTrimDB,
            referenceMIDI: referenceMIDI, auditionChord: source.auditionChord
        )
        guard voice.fingerprintScalars.allSatisfy(\.isFinite) else {
            throw DayObjectsSoundWorldCatalogError.invalidRecipe(id.rawValue)
        }
        return DayObjectsAudioParameters.clamped(voice)
    }

    func fingerprint(mood: DayObjectsSoundMood, sourceVoices: [DayObjectsInstrumentID: NormalizedSynthVoice]) throws -> String {
        try resolvedVoice(mood: mood, sourceVoices: sourceVoices).stableFingerprint
    }

    func validate(sourceVoices: [DayObjectsInstrumentID: NormalizedSynthVoice]) throws {
        guard !id.rawValue.isEmpty, !family.isEmpty, basePatch.isFinite,
              outputTrimDB.isFinite, (-30...6).contains(outputTrimDB),
              (24...108).contains(referenceMIDI),
              moodPatches.count == DayObjectsSoundMood.allCases.count,
              Set(moodPatches.map(\.mood)) == Set(DayObjectsSoundMood.allCases),
              moodPatches.allSatisfy({ $0.patch.isFinite }) else {
            throw DayObjectsSoundWorldCatalogError.invalidRecipe(id.rawValue)
        }
        guard let source = sourceVoices[sourceInstrumentID],
              source.fingerprintScalars.allSatisfy(\.isFinite) else {
            throw DayObjectsSoundWorldCatalogError.unknownSource(sourceInstrumentID.rawValue)
        }
    }
}

extension NormalizedSynthVoice {
    /// Declaration order, including enum/Boolean scalars and each audition note.
    /// String enum encodings are fixed: sine/square = 0/1; none/pitch/filter/amplitude = 0/1/2/3.
    var fingerprintScalars: [Double] {
        func oscillator(_ value: Oscillator) -> [Double] {
            [value.wavePosition, value.level, Double(value.semitoneOffset), value.detuneHz]
        }
        func envelope(_ value: Envelope) -> [Double] {
            [value.attackSeconds, value.decaySeconds, value.sustainLevel, value.releaseSeconds]
        }
        let target: Double
        switch lfo.target {
        case .none: target = 0
        case .pitch: target = 1
        case .filter: target = 2
        case .amplitude: target = 3
        }
        var values = oscillator(oscillator1) + oscillator(oscillator2)
        values += [oscillatorBalance, subOscillator.level, subOscillator.waveform == .sine ? 0 : 1,
                   Double(subOscillator.octaveOffset), noiseLevel]
        values += envelope(amplitudeEnvelope)
        values += [Double(filter.kind.rawValue), filter.cutoffHz, filter.resonance]
        values += envelope(filter.envelope)
        values += [filter.envelopeAmount, glideSeconds, isMonophonic ? 1 : 0,
                   target, lfo.rateHz, lfo.depth, Double(lfo.waveform.rawValue)]
        values += [delay.isEnabled ? 1 : 0, delay.timeSeconds, delay.feedback, delay.mix,
                   reverb.isEnabled ? 1 : 0, reverb.feedback, reverb.highPassHz, reverb.mix]
        values += [phaser.rateHz, phaser.feedback, phaser.mix, phaser.notchWidthHz,
                   autoPan.rateHz, autoPan.depth, autoPan.stereoWidth, outputTrimDB, Double(referenceMIDI)]
        values += auditionChord.map(Double.init)
        return values
    }

    var stableFingerprint: String {
        var bytes = Data()
        for scalar in fingerprintScalars {
            var littleEndian = scalar.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
