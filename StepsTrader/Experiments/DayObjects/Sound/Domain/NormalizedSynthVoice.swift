import Foundation

struct NormalizedSynthVoice: Equatable, Sendable {
    struct Oscillator: Equatable, Sendable {
        let wavePosition: Double
        let level: Double
        let semitoneOffset: Int
        let detuneHz: Double
    }

    enum SubWaveform: String, Equatable, Sendable {
        case sine
        case square
    }

    struct SubOscillator: Equatable, Sendable {
        let level: Double
        let waveform: SubWaveform
        let octaveOffset: Int
    }

    struct Envelope: Equatable, Sendable {
        let attackSeconds: Double
        let decaySeconds: Double
        let sustainLevel: Double
        let releaseSeconds: Double
    }

    enum FilterKind: Int, Equatable, Sendable {
        case lowPass
        case bandPass
        case highPass
    }

    struct Filter: Equatable, Sendable {
        let kind: FilterKind
        let cutoffHz: Double
        let resonance: Double
        let envelope: Envelope
        let envelopeAmount: Double
    }

    enum LFOTarget: String, Equatable, Sendable {
        case none
        case pitch
        case filter
        case amplitude
    }

    enum LFOWaveform: Int, Equatable, Sendable {
        case sine = 0
        case square = 1
        case sawtooth = 2
        case reverseSawtooth = 3
    }

    struct LFO: Equatable, Sendable {
        let target: LFOTarget
        let rateHz: Double
        let depth: Double
        let waveform: LFOWaveform

        init(target: LFOTarget, rateHz: Double, depth: Double, waveform: LFOWaveform = .sine) {
            self.target = target
            self.rateHz = rateHz
            self.depth = depth
            self.waveform = waveform
        }
    }

    struct Delay: Equatable, Sendable {
        let isEnabled: Bool
        let timeSeconds: Double
        let feedback: Double
        let mix: Double
    }

    struct Reverb: Equatable, Sendable {
        let isEnabled: Bool
        let feedback: Double
        let highPassHz: Double
        let mix: Double
    }

    struct Phaser: Equatable, Sendable {
        let rateHz: Double
        let feedback: Double
        let mix: Double
        let notchWidthHz: Double

        init(rateHz: Double, feedback: Double, mix: Double, notchWidthHz: Double = 800) {
            self.rateHz = rateHz
            self.feedback = feedback
            self.mix = mix
            self.notchWidthHz = notchWidthHz
        }
    }

    struct AutoPan: Equatable, Sendable {
        let rateHz: Double
        let depth: Double
        let stereoWidth: Double
    }

    let oscillator1: Oscillator
    let oscillator2: Oscillator
    let oscillatorBalance: Double
    let subOscillator: SubOscillator
    let noiseLevel: Double
    let amplitudeEnvelope: Envelope
    let filter: Filter
    let glideSeconds: Double
    let isMonophonic: Bool
    let lfo: LFO
    let delay: Delay
    let reverb: Reverb
    let phaser: Phaser
    let autoPan: AutoPan
    let outputTrimDB: Double
    let referenceMIDI: UInt8
    let auditionChord: [UInt8]
}
