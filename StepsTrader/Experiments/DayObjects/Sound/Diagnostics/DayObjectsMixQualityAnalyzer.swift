#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Foundation

enum DayObjectsMixQualityAnalyzerError: Error, Equatable, Sendable {
    case sampleRateMismatch(role: DayObjectsMixRole)
    case frameCountMismatch(role: DayObjectsMixRole)
}

enum DayObjectsMixQualityAnalyzer {
    static let acceptedIntegratedLUFS = -18.0 ... -16.0
    static let maximumTruePeakDBTP = -1.0
    static let maximumAbsoluteDCOffset = 0.01
    static let maximumHighBandEnergyRatio = 0.45
    static let minimumActiveStemAudibilityDB = -42.0

    private static let silentFloorDB = -120.0
    private static let kickBassCorrelationThreshold = 0.8

    static func analyze(
        fullMix: AVAudioPCMBuffer,
        stems: [DayObjectsMixRole: AVAudioPCMBuffer]
    ) throws -> DayObjectsMixQualityReport {
        let fullMixSamples = try DayObjectsPCMBufferAdapter.samples(from: fullMix)
        let loudness = try DayObjectsLoudnessAnalyzer.analyze(
            channels: fullMixSamples.channels,
            channelWeights: [Double](repeating: 1, count: fullMixSamples.channels.count),
            sampleRate: fullMixSamples.sampleRate
        )
        let stemSamples = try validatedStemSamples(
            stems,
            sampleRate: fullMixSamples.sampleRate,
            frameCount: fullMixSamples.frameCount
        )

        let rms = rootMeanSquare(fullMixSamples.channels)
        let samplePeak = fullMixSamples.channels
            .flatMap { $0 }
            .map { abs(Double($0)) }
            .max() ?? 0
        let crestFactorDB = rms > 0 && samplePeak > 0
            ? finiteDecibels(samplePeak / rms)
            : 0
        let maximumAbsoluteDCOffset = fullMixSamples.channels
            .map(channelMean)
            .map(abs)
            .max() ?? 0
        let bands = bandEnergyRatios(
            channels: fullMixSamples.channels,
            sampleRate: fullMixSamples.sampleRate
        )

        var layerAudibilityDB: [String: Double] = [:]
        for role in DayObjectsMixRole.allCases {
            guard let samples = stemSamples[role] else { continue }
            layerAudibilityDB[role.rawValue] = relativeAudibilityDB(
                stemRMS: rootMeanSquare(samples.channels),
                mixRMS: rms
            )
        }

        let kickBassCorrelation: Double
        if let rhythm = stemSamples[.rhythm], let bass = stemSamples[.bass] {
            kickBassCorrelation = normalizedCorrelation(
                lowBandSignal(rhythm.mono, sampleRate: rhythm.sampleRate),
                lowBandSignal(bass.mono, sampleRate: bass.sampleRate)
            )
        } else {
            kickBassCorrelation = 0
        }

        var detected = Set<DayObjectsMixIssue>()
        if rms == 0 { detected.insert(.silence) }
        if !acceptedIntegratedLUFS.contains(loudness.integratedLUFS) {
            detected.insert(.integratedLoudness)
        }
        if loudness.truePeakDBTP > maximumTruePeakDBTP {
            detected.insert(.truePeak)
        }
        if maximumAbsoluteDCOffset > self.maximumAbsoluteDCOffset {
            detected.insert(.dcOffset)
        }
        if bands.high > maximumHighBandEnergyRatio {
            detected.insert(.excessiveBrightness)
        }
        if layerAudibilityDB.values.contains(where: { $0 <= minimumActiveStemAudibilityDB }) {
            detected.insert(.inaudibleStem)
        }
        if kickBassCorrelation > kickBassCorrelationThreshold {
            detected.insert(.kickBassMasking)
        }

        var suggestions: [DayObjectsMixSuggestion] = []
        if detected.contains(.kickBassMasking) {
            let severity = ((kickBassCorrelation - kickBassCorrelationThreshold)
                / (1 - kickBassCorrelationThreshold)).clamped(to: 0 ... 1)
            suggestions.append(DayObjectsMixSuggestion(
                role: .bass,
                gainAdjustmentDB: -3 * severity,
                additionalDuckingDB: 4 * severity,
                cutoffMultiplier: 1 - (0.25 * severity),
                reverbSendAdjustment: -0.15 * severity
            ))
        }

        return DayObjectsMixQualityReport(
            integratedLUFS: loudness.integratedLUFS,
            truePeakDBTP: loudness.truePeakDBTP,
            maximumAbsoluteDCOffset: maximumAbsoluteDCOffset,
            crestFactorDB: crestFactorDB,
            lowBandEnergyRatio: bands.low,
            midBandEnergyRatio: bands.mid,
            highBandEnergyRatio: bands.high,
            layerAudibilityDB: layerAudibilityDB,
            kickBassLowBandCorrelation: kickBassCorrelation,
            issues: DayObjectsMixIssue.allCases.filter(detected.contains),
            suggestions: suggestions.sorted { $0.role.rawValue < $1.role.rawValue }
        )
    }

    private static func validatedStemSamples(
        _ stems: [DayObjectsMixRole: AVAudioPCMBuffer],
        sampleRate: Double,
        frameCount: Int
    ) throws -> [DayObjectsMixRole: DayObjectsPCMBufferSamples] {
        var result: [DayObjectsMixRole: DayObjectsPCMBufferSamples] = [:]
        for role in DayObjectsMixRole.allCases {
            guard let buffer = stems[role] else { continue }
            let samples = try DayObjectsPCMBufferAdapter.samples(from: buffer)
            guard samples.sampleRate == sampleRate else {
                throw DayObjectsMixQualityAnalyzerError.sampleRateMismatch(role: role)
            }
            guard samples.frameCount == frameCount else {
                throw DayObjectsMixQualityAnalyzerError.frameCountMismatch(role: role)
            }
            result[role] = samples
        }
        return result
    }

    private static func channelMean(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0) { $0 + Double($1) } / Double(samples.count)
    }

    private static func rootMeanSquare(_ channels: [[Float]]) -> Double {
        let sampleCount = channels.reduce(0) { $0 + $1.count }
        guard sampleCount > 0 else { return 0 }
        let sum = channels.reduce(0.0) { channelSum, channel in
            channelSum + channel.reduce(0.0) { sampleSum, sample in
                let value = Double(sample)
                return sampleSum + (value * value)
            }
        }
        return sqrt(sum / Double(sampleCount))
    }

    private static func relativeAudibilityDB(stemRMS: Double, mixRMS: Double) -> Double {
        guard stemRMS > 0 else { return silentFloorDB }
        guard mixRMS > 0 else { return -silentFloorDB }
        return finiteDecibels(stemRMS / mixRMS).clamped(to: silentFloorDB ... -silentFloorDB)
    }

    private static func finiteDecibels(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return silentFloorDB }
        return max(20 * log10(amplitude), silentFloorDB)
    }

    private static func bandEnergyRatios(
        channels: [[Float]],
        sampleRate: Double
    ) -> (low: Double, mid: Double, high: Double) {
        let windowSize = 4_096
        guard channels.allSatisfy({ $0.count >= windowSize }) else {
            return (0, 0, 0)
        }
        let hopSize = windowSize / 2
        let window = (0..<windowSize).map { index in
            0.5 - (0.5 * cos(2 * Double.pi * Double(index) / Double(windowSize - 1)))
        }
        var energy = (low: 0.0, mid: 0.0, high: 0.0)

        for channel in channels {
            var starts = Array(stride(
                from: 0,
                through: channel.count - windowSize,
                by: hopSize
            ))
            let finalStart = channel.count - windowSize
            if starts.last != finalStart { starts.append(finalStart) }

            for start in starts {
                var real = [Double](repeating: 0, count: windowSize)
                var imaginary = [Double](repeating: 0, count: windowSize)
                for index in 0..<windowSize {
                    real[index] = Double(channel[start + index]) * window[index]
                }
                radix2FFT(real: &real, imaginary: &imaginary)
                for bin in 0...(windowSize / 2) {
                    let frequency = Double(bin) * sampleRate / Double(windowSize)
                    guard frequency >= 20, frequency <= 20_000 else { continue }
                    let binEnergy = (real[bin] * real[bin]) + (imaginary[bin] * imaginary[bin])
                    if frequency < 160 {
                        energy.low += binEnergy
                    } else if frequency < 4_000 {
                        energy.mid += binEnergy
                    } else {
                        energy.high += binEnergy
                    }
                }
            }
        }

        let total = energy.low + energy.mid + energy.high
        guard total.isFinite, total > 0 else { return (0, 0, 0) }
        return (energy.low / total, energy.mid / total, energy.high / total)
    }

    private static func radix2FFT(real: inout [Double], imaginary: inout [Double]) {
        let count = real.count
        var target = 0
        for index in 1..<count {
            var bit = count >> 1
            while target & bit != 0 {
                target ^= bit
                bit >>= 1
            }
            target ^= bit
            if index < target {
                real.swapAt(index, target)
                imaginary.swapAt(index, target)
            }
        }

        var length = 2
        while length <= count {
            let angle = -2 * Double.pi / Double(length)
            let stepReal = cos(angle)
            let stepImaginary = sin(angle)
            for start in stride(from: 0, to: count, by: length) {
                var twiddleReal = 1.0
                var twiddleImaginary = 0.0
                for offset in 0..<(length / 2) {
                    let even = start + offset
                    let odd = even + (length / 2)
                    let oddReal = (real[odd] * twiddleReal) - (imaginary[odd] * twiddleImaginary)
                    let oddImaginary = (real[odd] * twiddleImaginary) + (imaginary[odd] * twiddleReal)
                    real[odd] = real[even] - oddReal
                    imaginary[odd] = imaginary[even] - oddImaginary
                    real[even] += oddReal
                    imaginary[even] += oddImaginary
                    let nextReal = (twiddleReal * stepReal) - (twiddleImaginary * stepImaginary)
                    twiddleImaginary = (twiddleReal * stepImaginary) + (twiddleImaginary * stepReal)
                    twiddleReal = nextReal
                }
            }
            length <<= 1
        }
    }

    private static func lowBandSignal(_ samples: [Double], sampleRate: Double) -> [Double] {
        var highPass = OnePoleHighPass(cutoff: 20, sampleRate: sampleRate)
        var lowPass = OnePoleLowPass(cutoff: 160, sampleRate: sampleRate)
        return samples.map { lowPass.process(highPass.process($0)) }
    }

    private static func normalizedCorrelation(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }
        var dot = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        for index in 0..<count {
            dot += lhs[index] * rhs[index]
            lhsEnergy += lhs[index] * lhs[index]
            rhsEnergy += rhs[index] * rhs[index]
        }
        let denominator = sqrt(lhsEnergy * rhsEnergy)
        guard denominator.isFinite, denominator > 0 else { return 0 }
        return (abs(dot) / denominator).clamped(to: 0 ... 1)
    }
}

private struct OnePoleLowPass {
    private let alpha: Double
    private var output = 0.0

    init(cutoff: Double, sampleRate: Double) {
        alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
    }

    mutating func process(_ input: Double) -> Double {
        output += alpha * (input - output)
        return output
    }
}

private struct OnePoleHighPass {
    private let alpha: Double
    private var previousInput = 0.0
    private var previousOutput = 0.0

    init(cutoff: Double, sampleRate: Double) {
        alpha = exp(-2 * Double.pi * cutoff / sampleRate)
    }

    mutating func process(_ input: Double) -> Double {
        let output = alpha * (previousOutput + input - previousInput)
        previousInput = input
        previousOutput = output
        return output
    }
}
#endif
