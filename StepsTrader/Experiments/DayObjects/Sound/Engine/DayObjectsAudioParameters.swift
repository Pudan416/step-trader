#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsAudioParameters {
    static let defaultAuditionVoiceCapacity = 6
    static let maximumChordVoiceCount = 4
    static let presetTransitionDuration: TimeInterval = 0.120
    static let controlRampDuration: TimeInterval = 0.025

    static let minimumMIDINote = 24.0
    static let maximumMIDINote = 108.0
    static let minimumCutoffHz = 20.0
    static let maximumCutoffHz = 18_000.0
    static let maximumDelayFeedback = 0.90
    static let delayFeedbackSafetyLimit = 0.91
    static let maximumReverbFeedback = 0.95
    static let reverbFeedbackSafetyLimit = 0.96
    static let defaultReverbFeedback = 0.80
    static let minimumOutputTrimDB = -60.0
    static let maximumOutputTrimDB = -6.0

    static func clamped(_ voice: NormalizedSynthVoice) -> NormalizedSynthVoice {
        .init(
            oscillator1: clamped(voice.oscillator1),
            oscillator2: clamped(voice.oscillator2),
            oscillatorBalance: finite(voice.oscillatorBalance, default: 0.5, in: 0...1),
            subOscillator: .init(
                level: finite(voice.subOscillator.level, default: 0, in: 0...1),
                waveform: voice.subOscillator.waveform,
                octaveOffset: min(max(voice.subOscillator.octaveOffset, -2), -1)
            ),
            noiseLevel: finite(voice.noiseLevel, default: 0, in: 0...1),
            amplitudeEnvelope: clamped(voice.amplitudeEnvelope),
            filter: .init(
                kind: voice.filter.kind,
                cutoffHz: finite(voice.filter.cutoffHz, default: 12_000, in: minimumCutoffHz...maximumCutoffHz),
                resonance: finite(voice.filter.resonance, default: 0.1, in: 0...0.95),
                envelope: clamped(voice.filter.envelope),
                envelopeAmount: finite(voice.filter.envelopeAmount, default: 0, in: -1...1)
            ),
            glideSeconds: finite(voice.glideSeconds, default: 0, in: 0...2),
            isMonophonic: voice.isMonophonic,
            lfo: .init(
                target: voice.lfo.target,
                rateHz: finite(voice.lfo.rateHz, default: 1, in: 0.01...30),
                depth: finite(voice.lfo.depth, default: 0, in: 0...1),
                waveform: voice.lfo.waveform
            ),
            delay: .init(
                isEnabled: voice.delay.isEnabled,
                timeSeconds: finite(voice.delay.timeSeconds, default: 0.25, in: 0.001...2),
                feedback: finite(
                    voice.delay.feedback,
                    default: maximumDelayFeedback,
                    in: 0...maximumDelayFeedback
                ),
                mix: finite(voice.delay.mix, default: 0, in: 0...1)
            ),
            reverb: .init(
                isEnabled: voice.reverb.isEnabled,
                feedback: finite(
                    voice.reverb.feedback,
                    default: defaultReverbFeedback,
                    in: 0...maximumReverbFeedback
                ),
                highPassHz: finite(voice.reverb.highPassHz, default: 80, in: 20...4_000),
                mix: finite(voice.reverb.mix, default: 0, in: 0...1)
            ),
            phaser: .init(
                rateHz: finite(voice.phaser.rateHz, default: 0.5, in: 0.01...20),
                feedback: finite(voice.phaser.feedback, default: 0, in: -0.95...0.95),
                mix: finite(voice.phaser.mix, default: 0, in: 0...1),
                notchWidthHz: finite(voice.phaser.notchWidthHz, default: 800, in: 20...2_000)
            ),
            autoPan: .init(
                rateHz: finite(voice.autoPan.rateHz, default: 0.25, in: 0.01...20),
                depth: finite(voice.autoPan.depth, default: 0, in: 0...1),
                stereoWidth: finite(voice.autoPan.stereoWidth, default: 0, in: 0...1)
            ),
            outputTrimDB: finite(
                voice.outputTrimDB,
                default: -18,
                in: minimumOutputTrimDB...maximumOutputTrimDB
            ),
            referenceMIDI: UInt8(min(max(Int(voice.referenceMIDI), Int(minimumMIDINote)), Int(maximumMIDINote))),
            auditionChord: Array(voice.auditionChord.prefix(maximumChordVoiceCount)).map {
                UInt8(min(max(Int($0), Int(minimumMIDINote)), Int(maximumMIDINote)))
            }
        )
    }

    static func clamped(_ request: DayObjectsTonalNoteRequest) -> DayObjectsTonalNoteRequest {
        .init(
            instrumentID: request.instrumentID,
            midiNote: UInt8(min(max(Double(request.midiNote), minimumMIDINote), maximumMIDINote)),
            velocity: finite(request.velocity, default: 1, in: 0...1),
            role: request.role,
            envelopeVariant: request.envelopeVariant.map(clamped),
            pan: finite(request.pan, default: 0, in: -1...1),
            delaySend: finite(request.delaySend, default: 0, in: 0...1),
            reverbSend: finite(request.reverbSend, default: 0, in: 0...1)
        )
    }

    static func clamped(_ update: DayObjectsVoiceUpdate, fallbackMIDINote: Double) -> DayObjectsVoiceUpdate {
        .init(
            midiNote: update.midiNote.map {
                finite($0, default: fallbackMIDINote, in: minimumMIDINote...maximumMIDINote)
            },
            cutoffHz: update.cutoffHz.map {
                finite($0, default: minimumCutoffHz, in: minimumCutoffHz...maximumCutoffHz)
            },
            expression: update.expression.map { finite($0, default: 1, in: 0...1) },
            pan: update.pan.map { finite($0, default: 0, in: -1...1) },
            delaySend: update.delaySend.map { finite($0, default: 0, in: 0...1) },
            reverbSend: update.reverbSend.map { finite($0, default: 0, in: 0...1) }
        )
    }

    static func linearGain(decibels: Double) -> Double {
        pow(10, finite(decibels, default: -18, in: minimumOutputTrimDB...maximumOutputTrimDB) / 20)
    }

    private static func clamped(_ oscillator: NormalizedSynthVoice.Oscillator) -> NormalizedSynthVoice.Oscillator {
        .init(
            wavePosition: finite(oscillator.wavePosition, default: 0.5, in: 0...1),
            level: finite(oscillator.level, default: 0.5, in: 0...1),
            semitoneOffset: min(max(oscillator.semitoneOffset, -24), 24),
            detuneHz: finite(oscillator.detuneHz, default: 0, in: -4...4)
        )
    }

    private static func clamped(_ envelope: NormalizedSynthVoice.Envelope) -> NormalizedSynthVoice.Envelope {
        .init(
            attackSeconds: finite(envelope.attackSeconds, default: 0.05, in: 0...30),
            decaySeconds: finite(envelope.decaySeconds, default: 0.2, in: 0...30),
            sustainLevel: finite(envelope.sustainLevel, default: 0.8, in: 0...1),
            releaseSeconds: finite(envelope.releaseSeconds, default: 0.4, in: 0...30)
        )
    }

    private static func clamped(_ variant: DayObjectsEnvelopeVariant) -> DayObjectsEnvelopeVariant {
        .init(
            attackScale: finite(variant.attackScale, default: 1, in: 0.25...4),
            releaseScale: finite(variant.releaseScale, default: 1, in: 0.25...4)
        )
    }

    private static func finite(_ value: Double, default defaultValue: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct DayObjectsEnvelopeVariant: Equatable, Sendable {
    let attackScale: Double
    let releaseScale: Double
}

enum DayObjectsTonalVoiceRole: Equatable, Sendable {
    case note
    case chord
    case lead
}

struct DayObjectsTonalNoteRequest: Equatable, Sendable {
    let instrumentID: DayObjectsInstrumentID
    let midiNote: UInt8
    let velocity: Double
    let role: DayObjectsTonalVoiceRole
    let envelopeVariant: DayObjectsEnvelopeVariant?
    let pan: Double
    let delaySend: Double
    let reverbSend: Double
}

struct DayObjectsVoiceUpdate: Equatable, Sendable {
    let midiNote: Double?
    let cutoffHz: Double?
    let expression: Double?
    let pan: Double?
    let delaySend: Double?
    let reverbSend: Double?

    init(
        midiNote: Double? = nil,
        cutoffHz: Double? = nil,
        expression: Double? = nil,
        pan: Double? = nil,
        delaySend: Double? = nil,
        reverbSend: Double? = nil
    ) {
        self.midiNote = midiNote
        self.cutoffHz = cutoffHz
        self.expression = expression
        self.pan = pan
        self.delaySend = delaySend
        self.reverbSend = reverbSend
    }
}
#endif
