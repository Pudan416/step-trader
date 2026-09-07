#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Foundation

enum DayObjectsMixQualityAnalyzerError: Error, Equatable, Sendable {
    case sampleRateMismatch(role: DayObjectsMixRole)
    case frameCountMismatch(role: DayObjectsMixRole)
    case missingActiveStem(role: DayObjectsMixRole)
}

enum DayObjectsMixQualityAnalyzer {
    /// Fixed acceptance gates for the 24-second offline audition renders.
    static let acceptedIntegratedLUFS = -18.0 ... -16.0
    static let maximumTruePeakDBTP = -1.0
    static let maximumAbsoluteDCOffset = 0.01
    static let maximumHighBandEnergyRatio = 0.45
    static let minimumActiveStemAudibilityDB = -42.0
    static let maximumTransientDensityPerSecond = 12.0
    static let maximumSpectralMaskingScore = 0.75
    static let maximumReverbTailEnergyRatio = 1.5

    private static let silentFloorDB = -120.0
    private static let clippingAmplitude = 1.0
    private static let kickBassCorrelationThreshold = 0.8
    private static let reverbTailSeconds = 2.0
    private static let transientRefractorySeconds = 0.04

    static func analyze(
        fullMix: AVAudioPCMBuffer,
        stems: [DayObjectsMixRole: AVAudioPCMBuffer],
        activeRoles: Set<DayObjectsMixRole>? = nil
    ) throws -> DayObjectsMixQualityReport {
        let resolvedActiveRoles = activeRoles ?? Set(stems.keys)
        if let missingRole = DayObjectsMixRole.allCases.first(where: {
            resolvedActiveRoles.contains($0) && stems[$0] == nil
        }) {
            throw DayObjectsMixQualityAnalyzerError.missingActiveStem(role: missingRole)
        }
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
        let sampleStatistics = samplePeakAndClippingRatio(fullMixSamples.channels)
        let samplePeak = sampleStatistics.peak
        let crestFactorDB = rms > 0 && samplePeak > 0
            ? finiteDecibels(samplePeak / rms)
            : 0
        let maximumAbsoluteDCOffset = fullMixSamples.channels
            .map(channelMean)
            .map(abs)
            .max() ?? 0
        let fullMixSpectrum = spectralEnergy(
            channels: fullMixSamples.channels,
            sampleRate: fullMixSamples.sampleRate
        )
        let bands = bandEnergyRatios(
            spectrum: fullMixSpectrum,
            sampleRate: fullMixSamples.sampleRate
        )
        let transientDensity = transientDensityPerSecond(
            channels: fullMixSamples.channels,
            sampleRate: fullMixSamples.sampleRate
        )
        let reverbTailRatio = trailingEnergyRatio(
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
        if resolvedActiveRoles.isSuperset(of: [.rhythm, .bass]),
           let rhythm = stemSamples[.rhythm],
           let bass = stemSamples[.bass] {
            kickBassCorrelation = normalizedCorrelation(
                lowBandSignal(rhythm.mono, sampleRate: rhythm.sampleRate),
                lowBandSignal(bass.mono, sampleRate: bass.sampleRate)
            )
        } else {
            kickBassCorrelation = 0
        }

        var stemSpectra: [DayObjectsMixRole: [Double]] = [:]
        for role in [DayObjectsMixRole.harmony, .happenings, .lead]
            where resolvedActiveRoles.contains(role) {
            guard let samples = stemSamples[role] else { continue }
            stemSpectra[role] = spectralEnergy(
                channels: samples.channels,
                sampleRate: samples.sampleRate
            )
        }
        let harmonyLeadMasking = spectralMaskingScore(
            lhs: stemSpectra[.harmony],
            rhs: stemSpectra[.lead],
            sampleRate: fullMixSamples.sampleRate
        )
        let happeningsLeadMasking = spectralMaskingScore(
            lhs: stemSpectra[.happenings],
            rhs: stemSpectra[.lead],
            sampleRate: fullMixSamples.sampleRate
        )

        var detected = Set<DayObjectsMixIssue>()
        if rms == 0 { detected.insert(.silence) }
        if !acceptedIntegratedLUFS.contains(loudness.integratedLUFS) {
            detected.insert(.integratedLoudness)
        }
        if loudness.truePeakDBTP > maximumTruePeakDBTP {
            detected.insert(.truePeak)
        }
        if sampleStatistics.clippedRatio > 0 {
            detected.insert(.clipping)
        }
        if maximumAbsoluteDCOffset > self.maximumAbsoluteDCOffset {
            detected.insert(.dcOffset)
        }
        if bands.high > maximumHighBandEnergyRatio {
            detected.insert(.excessiveBrightness)
        }
        if transientDensity > maximumTransientDensityPerSecond {
            detected.insert(.excessiveTransientDensity)
        }
        if resolvedActiveRoles.contains(where: {
            layerAudibilityDB[$0.rawValue, default: silentFloorDB]
                <= minimumActiveStemAudibilityDB
        }) {
            detected.insert(.inaudibleStem)
        }
        if kickBassCorrelation > kickBassCorrelationThreshold {
            detected.insert(.kickBassMasking)
        }
        if harmonyLeadMasking > maximumSpectralMaskingScore {
            detected.insert(.harmonyLeadMasking)
        }
        if happeningsLeadMasking > maximumSpectralMaskingScore {
            detected.insert(.happeningsLeadMasking)
        }
        if reverbTailRatio > maximumReverbTailEnergyRatio {
            detected.insert(.excessiveReverbTail)
        }

        var suggestionValues: [DayObjectsMixRole: SuggestionValues] = [:]
        if detected.contains(.kickBassMasking) {
            let severity = ((kickBassCorrelation - kickBassCorrelationThreshold)
                / (1 - kickBassCorrelationThreshold)).clamped(to: 0 ... 1)
            suggestionValues[.bass, default: .neutral].merge(
                gainAdjustmentDB: -3 * severity,
                additionalDuckingDB: 4 * severity,
                cutoffMultiplier: 1 - (0.25 * severity),
                reverbSendAdjustment: -0.15 * severity
            )
        }
        if detected.contains(.harmonyLeadMasking) {
            let severity = maskingSeverity(harmonyLeadMasking)
            suggestionValues[.harmony, default: .neutral].merge(
                gainAdjustmentDB: -2 * severity,
                cutoffMultiplier: 1 - (0.15 * severity),
                reverbSendAdjustment: -0.05 * severity
            )
        }
        if detected.contains(.happeningsLeadMasking) {
            let severity = maskingSeverity(happeningsLeadMasking)
            suggestionValues[.happenings, default: .neutral].merge(
                gainAdjustmentDB: -2 * severity,
                cutoffMultiplier: 1 - (0.15 * severity),
                reverbSendAdjustment: -0.05 * severity
            )
        }
        if detected.contains(.excessiveReverbTail),
           let role = mostAccumulatedSpatialRole(
               stemSamples,
               activeRoles: resolvedActiveRoles
           ) {
            let severity = ((reverbTailRatio - maximumReverbTailEnergyRatio)
                / maximumReverbTailEnergyRatio).clamped(to: 0 ... 1)
            suggestionValues[role, default: .neutral].merge(
                gainAdjustmentDB: -severity,
                reverbSendAdjustment: -0.15 * severity
            )
        }

        let suggestions = DayObjectsMixRole.allCases.compactMap { role in
            suggestionValues[role].map { $0.suggestion(role: role) }
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
            clippedSampleRatio: sampleStatistics.clippedRatio,
            transientDensityPerSecond: transientDensity,
            harmonyLeadMaskingScore: harmonyLeadMasking,
            happeningsLeadMaskingScore: happeningsLeadMasking,
            reverbTailEnergyRatio: reverbTailRatio,
            issues: DayObjectsMixIssue.allCases.filter(detected.contains),
            suggestions: suggestions
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

    private static func samplePeakAndClippingRatio(
        _ channels: [[Float]]
    ) -> (peak: Double, clippedRatio: Double) {
        var peak = 0.0
        var clippedCount = 0
        var sampleCount = 0
        for channel in channels {
            for sample in channel {
                let magnitude = abs(Double(sample))
                peak = max(peak, magnitude)
                clippedCount += magnitude >= clippingAmplitude ? 1 : 0
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return (0, 0) }
        return (peak, Double(clippedCount) / Double(sampleCount))
    }

    /// Counts separated full-band onsets. A rise must exceed max(0.02 FS,
    /// 1.5 x full-mix RMS), and detections have a 40 ms refractory period.
    private static func transientDensityPerSecond(
        channels: [[Float]],
        sampleRate: Double
    ) -> Double {
        guard let first = channels.first, !first.isEmpty else { return 0 }
        let threshold = max(0.02, 1.5 * rootMeanSquare(channels))
        let refractoryFrames = max(Int((transientRefractorySeconds * sampleRate).rounded()), 1)
        var previousMagnitude = 0.0
        var lastDetection = -refractoryFrames
        var count = 0
        for frame in first.indices {
            let magnitude = channels.reduce(0.0) {
                max($0, abs(Double($1[frame])))
            }
            if magnitude - previousMagnitude >= threshold,
               frame - lastDetection >= refractoryFrames {
                count += 1
                lastDetection = frame
            }
            previousMagnitude = magnitude
        }
        let duration = Double(first.count) / sampleRate
        guard duration.isFinite, duration > 0 else { return 0 }
        return Double(count) / duration
    }

    /// Ratio of mean-square energy in the final two seconds to mean-square
    /// energy across the whole render. Steady material is 1.0; values above
    /// 1.5 indicate energy is accumulating into the acceptance-render tail.
    private static func trailingEnergyRatio(
        channels: [[Float]],
        sampleRate: Double
    ) -> Double {
        guard let frameCount = channels.first?.count, frameCount > 0 else { return 0 }
        let totalEnergy = channels.reduce(0.0) { sum, channel in
            sum + channel.reduce(0.0) {
                let value = Double($1)
                return $0 + (value * value)
            }
        }
        guard totalEnergy.isFinite, totalEnergy > 0 else { return 0 }
        let tailFrames = min(
            max(Int((reverbTailSeconds * sampleRate).rounded()), 1),
            frameCount
        )
        let tailStart = frameCount - tailFrames
        let tailEnergy = channels.reduce(0.0) { sum, channel in
            sum + channel[tailStart..<frameCount].reduce(0.0) {
                let value = Double($1)
                return $0 + (value * value)
            }
        }
        let totalMeanSquare = totalEnergy / Double(frameCount * channels.count)
        let tailMeanSquare = tailEnergy / Double(tailFrames * channels.count)
        guard totalMeanSquare > 0 else { return 0 }
        return (tailMeanSquare / totalMeanSquare).clamped(to: 0 ... 120)
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
        spectrum: [Double],
        sampleRate: Double
    ) -> (low: Double, mid: Double, high: Double) {
        let transformSize = max((spectrum.count - 1) * 2, 1)
        var energy = (low: 0.0, mid: 0.0, high: 0.0)
        for bin in spectrum.indices {
            let frequency = Double(bin) * sampleRate / Double(transformSize)
            guard frequency >= 20, frequency <= 20_000 else { continue }
            if frequency < 160 {
                energy.low += spectrum[bin]
            } else if frequency < 4_000 {
                energy.mid += spectrum[bin]
            } else {
                energy.high += spectrum[bin]
            }
        }
        let total = energy.low + energy.mid + energy.high
        guard total.isFinite, total > 0 else { return (0, 0, 0) }
        return (energy.low / total, energy.mid / total, energy.high / total)
    }

    /// Accumulates Hann-windowed 4,096-point FFT energy with a 50% hop.
    /// The final window, including a short only window, is zero-padded.
    private static func spectralEnergy(
        channels: [[Float]],
        sampleRate: Double
    ) -> [Double] {
        let windowSize = 4_096
        guard channels.allSatisfy({ !$0.isEmpty }) else {
            return [Double](repeating: 0, count: (windowSize / 2) + 1)
        }
        let hopSize = windowSize / 2
        let window = (0..<windowSize).map { index in
            0.5 - (0.5 * cos(2 * Double.pi * Double(index) / Double(windowSize - 1)))
        }
        var energy = [Double](repeating: 0, count: (windowSize / 2) + 1)

        for channel in channels {
            for start in stride(from: 0, to: channel.count, by: hopSize) {
                var real = [Double](repeating: 0, count: windowSize)
                var imaginary = [Double](repeating: 0, count: windowSize)
                let availableFrames = min(windowSize, channel.count - start)
                for index in 0..<availableFrames {
                    real[index] = Double(channel[start + index]) * window[index]
                }
                radix2FFT(real: &real, imaginary: &imaginary)
                for bin in 0...(windowSize / 2) {
                    let binEnergy = (real[bin] * real[bin]) + (imaginary[bin] * imaginary[bin])
                    energy[bin] += binEnergy
                }
            }
        }
        return energy
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

    /// Cosine similarity of 160...4,000 Hz FFT energy. This is phase
    /// independent: identical occupied bins score 1, disjoint bins score 0.
    private static func spectralMaskingScore(
        lhs: [Double]?,
        rhs: [Double]?,
        sampleRate: Double
    ) -> Double {
        guard let lhs, let rhs, lhs.count == rhs.count, lhs.count > 1 else { return 0 }
        let transformSize = (lhs.count - 1) * 2
        var dot = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        for bin in lhs.indices {
            let frequency = Double(bin) * sampleRate / Double(transformSize)
            guard frequency >= 160, frequency < 4_000 else { continue }
            dot += lhs[bin] * rhs[bin]
            lhsEnergy += lhs[bin] * lhs[bin]
            rhsEnergy += rhs[bin] * rhs[bin]
        }
        let denominator = sqrt(lhsEnergy * rhsEnergy)
        guard denominator.isFinite, denominator > 0 else { return 0 }
        return (dot / denominator).clamped(to: 0 ... 1)
    }

    private static func maskingSeverity(_ score: Double) -> Double {
        ((score - maximumSpectralMaskingScore) / (1 - maximumSpectralMaskingScore))
            .clamped(to: 0 ... 1)
    }

    private static func mostAccumulatedSpatialRole(
        _ stems: [DayObjectsMixRole: DayObjectsPCMBufferSamples],
        activeRoles: Set<DayObjectsMixRole>
    ) -> DayObjectsMixRole? {
        let spatialRoles: [DayObjectsMixRole] = [.harmony, .happenings, .lead]
        return spatialRoles
            .filter(activeRoles.contains)
            .compactMap { role -> (DayObjectsMixRole, Double)? in
                guard let samples = stems[role] else { return nil }
                return (
                    role,
                    trailingEnergyRatio(
                        channels: samples.channels,
                        sampleRate: samples.sampleRate
                    )
                )
            }
            .max { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return spatialRoles.firstIndex(of: lhs.0)! > spatialRoles.firstIndex(of: rhs.0)!
                }
                return lhs.1 < rhs.1
            }?.0
    }
}

private struct SuggestionValues {
    static let neutral = SuggestionValues(
        gainAdjustmentDB: 0,
        additionalDuckingDB: 0,
        cutoffMultiplier: 1,
        reverbSendAdjustment: 0
    )

    private(set) var gainAdjustmentDB: Double
    private(set) var additionalDuckingDB: Double
    private(set) var cutoffMultiplier: Double
    private(set) var reverbSendAdjustment: Double

    mutating func merge(
        gainAdjustmentDB: Double = 0,
        additionalDuckingDB: Double = 0,
        cutoffMultiplier: Double = 1,
        reverbSendAdjustment: Double = 0
    ) {
        self.gainAdjustmentDB = min(self.gainAdjustmentDB, gainAdjustmentDB)
        self.additionalDuckingDB = max(self.additionalDuckingDB, additionalDuckingDB)
        self.cutoffMultiplier = min(self.cutoffMultiplier, cutoffMultiplier)
        self.reverbSendAdjustment = min(self.reverbSendAdjustment, reverbSendAdjustment)
    }

    func suggestion(role: DayObjectsMixRole) -> DayObjectsMixSuggestion {
        DayObjectsMixSuggestion(
            role: role,
            gainAdjustmentDB: gainAdjustmentDB,
            additionalDuckingDB: additionalDuckingDB,
            cutoffMultiplier: cutoffMultiplier,
            reverbSendAdjustment: reverbSendAdjustment
        )
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
