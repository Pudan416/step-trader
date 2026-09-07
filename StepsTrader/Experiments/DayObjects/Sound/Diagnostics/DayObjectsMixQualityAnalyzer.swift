#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Foundation

enum DayObjectsMixQualityAnalyzerError: Error, Equatable, Sendable {
    case sampleRateMismatch(role: DayObjectsMixRole)
    case frameCountMismatch(role: DayObjectsMixRole)
    case missingActiveStem(role: DayObjectsMixRole)
    case tailBoundaryForInactiveRole(role: DayObjectsMixRole)
    case invalidTailBoundary(role: DayObjectsMixRole, frame: Int)
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
    static let maximumReverbTailEnergyRatio = 0.2

    private static let silentFloorDB = -120.0
    private static let clippingAmplitude = 1.0
    private static let kickBassCorrelationThreshold = 0.8
    private static let reverbTailSeconds = 2.0
    private static let maskingAbsoluteFloorDBFS = -80.0
    private static let transientFrameSeconds = 0.01
    private static let transientHopSeconds = 0.005
    private static let transientHistorySeconds = 0.05
    private static let transientEnergyFloor = 0.01
    private static let transientMinimumRise = 0.005
    private static let transientRelativeRise = 0.5
    private static let transientDeviationMultiplier = 3.0
    private static let transientRefractorySeconds = 0.04

    /// Task 7 callers must pass the actual scheduled `activeRoles`, even when
    /// all five exported buffers exist. `tailBoundaryFrames` maps an active
    /// role to the first frame after its last intended event; roles without a
    /// trustworthy boundary are not evaluated for tail accumulation.
    static func analyze(
        fullMix: AVAudioPCMBuffer,
        stems: [DayObjectsMixRole: AVAudioPCMBuffer],
        activeRoles: Set<DayObjectsMixRole>? = nil,
        tailBoundaryFrames: [DayObjectsMixRole: Int] = [:]
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
        try validateTailBoundaries(
            tailBoundaryFrames,
            activeRoles: resolvedActiveRoles,
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
        let fullMixSpectralFrames = spectralFrames(channels: fullMixSamples.channels)
        let fullMixSpectrum = accumulatedSpectrum(fullMixSpectralFrames)
        let bands = bandEnergyRatios(
            spectrum: fullMixSpectrum,
            sampleRate: fullMixSamples.sampleRate
        )
        let transientDensity = transientDensityPerSecond(
            channels: fullMixSamples.channels,
            sampleRate: fullMixSamples.sampleRate
        )
        var reverbTailRatiosByRole: [String: Double] = [:]
        for role in DayObjectsMixRole.allCases {
            guard let boundary = tailBoundaryFrames[role],
                  let samples = stemSamples[role] else { continue }
            reverbTailRatiosByRole[role.rawValue] = postEventTailEnergyRatio(
                channels: samples.channels,
                boundaryFrame: boundary,
                sampleRate: samples.sampleRate
            )
        }
        let reverbTailRatio = reverbTailRatiosByRole.values.max() ?? 0

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

        var stemSpectralFrames: [DayObjectsMixRole: [SpectralFrame]] = [:]
        for role in [DayObjectsMixRole.harmony, .happenings, .lead]
            where resolvedActiveRoles.contains(role) {
            guard let samples = stemSamples[role] else { continue }
            stemSpectralFrames[role] = spectralFrames(channels: samples.channels)
        }
        let harmonyLeadMasking = spectralMaskingScore(
            lhs: stemSpectralFrames[.harmony],
            rhs: stemSpectralFrames[.lead],
            mix: fullMixSpectralFrames,
            lhsSamples: stemSamples[.harmony]?.channels,
            rhsSamples: stemSamples[.lead]?.channels,
            mixSamples: fullMixSamples.channels,
            sampleRate: fullMixSamples.sampleRate
        )
        let happeningsLeadMasking = spectralMaskingScore(
            lhs: stemSpectralFrames[.happenings],
            rhs: stemSpectralFrames[.lead],
            mix: fullMixSpectralFrames,
            lhsSamples: stemSamples[.happenings]?.channels,
            rhsSamples: stemSamples[.lead]?.channels,
            mixSamples: fullMixSamples.channels,
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
        let excessiveTailRoles = DayObjectsMixRole.allCases.filter {
            reverbTailRatiosByRole[$0.rawValue, default: 0]
                > maximumReverbTailEnergyRatio
        }
        if !excessiveTailRoles.isEmpty {
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
        for role in excessiveTailRoles {
            let roleRatio = reverbTailRatiosByRole[role.rawValue, default: 0]
            let severity = ((roleRatio - maximumReverbTailEnergyRatio)
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
            reverbTailEnergyRatioByRole: reverbTailRatiosByRole,
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

    private static func validateTailBoundaries(
        _ boundaries: [DayObjectsMixRole: Int],
        activeRoles: Set<DayObjectsMixRole>,
        frameCount: Int
    ) throws {
        for role in DayObjectsMixRole.allCases {
            guard let frame = boundaries[role] else { continue }
            guard activeRoles.contains(role) else {
                throw DayObjectsMixQualityAnalyzerError.tailBoundaryForInactiveRole(role: role)
            }
            guard frame > 0, frame < frameCount else {
                throw DayObjectsMixQualityAnalyzerError.invalidTailBoundary(
                    role: role,
                    frame: frame
                )
            }
        }
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

    /// Frequency-neutral onset novelty: 10 ms full-band RMS, sampled every
    /// 5 ms, is compared with the preceding 50 ms using a median and median
    /// absolute deviation. The adaptive rise threshold rejects stable pitched
    /// carriers and stationary noise without making low notes harder to detect.
    /// Detections retain the 40 ms refractory period.
    private static func transientDensityPerSecond(
        channels: [[Float]],
        sampleRate: Double
    ) -> Double {
        guard let first = channels.first, !first.isEmpty else { return 0 }
        let windowFrames = max(Int((transientFrameSeconds * sampleRate).rounded()), 2)
        let hopFrames = max(Int((transientHopSeconds * sampleRate).rounded()), 1)
        let historyCount = max(
            Int((transientHistorySeconds / transientHopSeconds).rounded()),
            1
        )
        let refractoryFrames = max(Int((transientRefractorySeconds * sampleRate).rounded()), 1)
        var history: [Double] = []
        history.reserveCapacity(historyCount)
        var wasAboveThreshold = false
        var lastDetection = -refractoryFrames
        var count = 0

        for start in stride(from: 0, to: first.count, by: hopFrames) {
            let availableFrames = min(windowFrames, first.count - start)
            var energy = 0.0
            for channel in channels {
                for offset in 0..<availableFrames {
                    let sample = Double(channel[start + offset])
                    energy += sample * sample
                }
            }
            let frameEnergy = sqrt(
                energy / Double(availableFrames * channels.count)
            )
            let baseline = median(history)
            let deviation = median(history.map { abs($0 - baseline) })
            let requiredRise = max(
                transientMinimumRise,
                baseline * transientRelativeRise,
                deviation * transientDeviationMultiplier
            )
            let novelty = frameEnergy - baseline
            let isAboveThreshold = frameEnergy >= transientEnergyFloor
                && novelty >= requiredRise
            if isAboveThreshold,
               !wasAboveThreshold,
               start - lastDetection >= refractoryFrames {
                count += 1
                lastDetection = start
            }
            wasAboveThreshold = isAboveThreshold
            history.append(frameEnergy)
            if history.count > historyCount {
                history.removeFirst()
            }
        }
        let duration = Double(first.count) / sampleRate
        guard duration.isFinite, duration > 0 else { return 0 }
        return Double(count) / duration
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    /// Compares up to two seconds after the caller-provided end-of-event frame
    /// against an equally sized pre-boundary reference from the same stem.
    private static func postEventTailEnergyRatio(
        channels: [[Float]],
        boundaryFrame: Int,
        sampleRate: Double
    ) -> Double {
        guard let frameCount = channels.first?.count, frameCount > 0 else { return 0 }
        let comparisonFrames = min(
            max(Int((reverbTailSeconds * sampleRate).rounded()), 1),
            boundaryFrame,
            frameCount - boundaryFrame
        )
        guard comparisonFrames > 0 else { return 0 }
        let preRange = (boundaryFrame - comparisonFrames)..<boundaryFrame
        let postRange = boundaryFrame..<(boundaryFrame + comparisonFrames)
        let preEnergy = meanSquareEnergy(channels, frames: preRange)
        let postEnergy = meanSquareEnergy(channels, frames: postRange)
        guard preEnergy > 0 else { return postEnergy > 0 ? 120 : 0 }
        return (postEnergy / preEnergy).clamped(to: 0 ... 120)
    }

    private static func meanSquareEnergy(
        _ channels: [[Float]],
        frames: Range<Int>
    ) -> Double {
        guard !channels.isEmpty, !frames.isEmpty else { return 0 }
        let energy = channels.reduce(0.0) { sum, channel in
            sum + channel[frames].reduce(0.0) {
                let sample = Double($1)
                return $0 + (sample * sample)
            }
        }
        return energy / Double(frames.count * channels.count)
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

    /// Produces Hann-windowed 4,096-point FFT energy with a 50% hop. The final
    /// window, including a short only window, is zero-padded.
    private static func spectralFrames(channels: [[Float]]) -> [SpectralFrame] {
        let windowSize = 4_096
        guard let frameCount = channels.first?.count,
              frameCount > 0,
              channels.allSatisfy({ $0.count == frameCount }) else { return [] }
        let hopSize = windowSize / 2
        let window = (0..<windowSize).map { index in
            0.5 - (0.5 * cos(2 * Double.pi * Double(index) / Double(windowSize - 1)))
        }
        var result: [SpectralFrame] = []

        for start in stride(from: 0, to: frameCount, by: hopSize) {
            let availableFrames = min(windowSize, frameCount - start)
            var frameEnergy = [Double](repeating: 0, count: (windowSize / 2) + 1)
            var timeDomainEnergy = 0.0
            for channel in channels {
                var real = [Double](repeating: 0, count: windowSize)
                var imaginary = [Double](repeating: 0, count: windowSize)
                for index in 0..<availableFrames {
                    let sample = Double(channel[start + index])
                    real[index] = sample * window[index]
                    timeDomainEnergy += sample * sample
                }
                radix2FFT(real: &real, imaginary: &imaginary)
                for bin in 0...(windowSize / 2) {
                    let binEnergy = (real[bin] * real[bin]) + (imaginary[bin] * imaginary[bin])
                    frameEnergy[bin] += binEnergy
                }
            }
            let sampleCount = availableFrames * channels.count
            let rms = sampleCount > 0
                ? sqrt(timeDomainEnergy / Double(sampleCount))
                : 0
            result.append(SpectralFrame(
                startFrame: start,
                frameCount: availableFrames,
                energy: frameEnergy,
                rms: rms
            ))
        }
        return result
    }

    private static func accumulatedSpectrum(_ frames: [SpectralFrame]) -> [Double] {
        let binCount = frames.first?.energy.count ?? 2_049
        var result = [Double](repeating: 0, count: binCount)
        for frame in frames {
            for bin in frame.energy.indices {
                result[bin] += frame.energy[bin]
            }
        }
        return result
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

    /// Relative-energy-weighted cosine overlap of 160...4,000 Hz FFT energy.
    /// Only contemporaneous frames where both stems exceed -42 dB relative to
    /// the mix and -80 dBFS absolute RMS contribute.
    private static func spectralMaskingScore(
        lhs: [SpectralFrame]?,
        rhs: [SpectralFrame]?,
        mix: [SpectralFrame],
        lhsSamples: [[Float]]?,
        rhsSamples: [[Float]]?,
        mixSamples: [[Float]],
        sampleRate: Double
    ) -> Double {
        guard let lhs, let rhs, let lhsSamples, let rhsSamples,
              lhs.count == rhs.count,
              lhs.count == mix.count,
              let binCount = lhs.first?.energy.count,
              binCount > 1 else { return 0 }
        let minimumRelativeEnergy = pow(10, minimumActiveStemAudibilityDB / 10)
        let minimumAbsoluteAmplitude = pow(10, maskingAbsoluteFloorDBFS / 20)
        let transformSize = (binCount - 1) * 2
        var weightedOverlap = 0.0
        var totalWeight = 0.0

        for frameIndex in lhs.indices {
            let lhsFrame = lhs[frameIndex]
            let rhsFrame = rhs[frameIndex]
            let mixFrame = mix[frameIndex]
            guard mixFrame.rms >= minimumAbsoluteAmplitude,
                  lhsFrame.rms >= minimumAbsoluteAmplitude,
                  rhsFrame.rms >= minimumAbsoluteAmplitude else { continue }

            var dot = 0.0
            var lhsVectorNorm = 0.0
            var rhsVectorNorm = 0.0
            var lhsBandEnergy = 0.0
            var rhsBandEnergy = 0.0
            var mixBandEnergy = 0.0
            for bin in 0..<binCount {
                let frequency = Double(bin) * sampleRate / Double(transformSize)
                guard frequency >= 160, frequency < 4_000 else { continue }
                let lhsValue = lhsFrame.energy[bin]
                let rhsValue = rhsFrame.energy[bin]
                dot += lhsValue * rhsValue
                lhsVectorNorm += lhsValue * lhsValue
                rhsVectorNorm += rhsValue * rhsValue
                lhsBandEnergy += lhsValue
                rhsBandEnergy += rhsValue
                mixBandEnergy += mixFrame.energy[bin]
            }
            guard mixBandEnergy.isFinite,
                  mixBandEnergy > 0,
                  lhsBandEnergy / mixBandEnergy > minimumRelativeEnergy,
                  rhsBandEnergy / mixBandEnergy > minimumRelativeEnergy else { continue }
            let denominator = sqrt(lhsVectorNorm * rhsVectorNorm)
            guard denominator.isFinite, denominator > 0 else { continue }
            let overlap = (dot / denominator).clamped(to: 0 ... 1)
            let support = contemporaneousSupport(
                lhs: lhsSamples,
                rhs: rhsSamples,
                mix: mixSamples,
                frames: mixFrame.startFrame..<(mixFrame.startFrame + mixFrame.frameCount),
                minimumAbsoluteAmplitude: minimumAbsoluteAmplitude
            )
            let relativeWeight = (
                min(lhsBandEnergy, rhsBandEnergy) / mixBandEnergy
            ).clamped(to: 0 ... 1)
            weightedOverlap += overlap
                * support.fraction
                * support.weakerToStrongerLevelRatio
                * relativeWeight
            totalWeight += relativeWeight
        }
        guard totalWeight.isFinite, totalWeight > 0 else { return 0 }
        return (weightedOverlap / totalWeight).clamped(to: 0 ... 1)
    }

    private static func contemporaneousSupport(
        lhs: [[Float]],
        rhs: [[Float]],
        mix: [[Float]],
        frames: Range<Int>,
        minimumAbsoluteAmplitude: Double
    ) -> (fraction: Double, weakerToStrongerLevelRatio: Double) {
        let minimumRelativeAmplitude = pow(10, minimumActiveStemAudibilityDB / 20)
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        var supportedFrames = 0
        for frame in frames {
            let mixMagnitude = maximumMagnitude(mix, frame: frame)
            let lhsMagnitude = maximumMagnitude(lhs, frame: frame)
            let rhsMagnitude = maximumMagnitude(rhs, frame: frame)
            guard mixMagnitude >= minimumAbsoluteAmplitude,
                  lhsMagnitude >= minimumAbsoluteAmplitude,
                  rhsMagnitude >= minimumAbsoluteAmplitude,
                  lhsMagnitude / mixMagnitude > minimumRelativeAmplitude,
                  rhsMagnitude / mixMagnitude > minimumRelativeAmplitude else { continue }
            lhsEnergy += lhsMagnitude * lhsMagnitude
            rhsEnergy += rhsMagnitude * rhsMagnitude
            supportedFrames += 1
        }
        guard supportedFrames > 0,
              lhsEnergy.isFinite,
              rhsEnergy.isFinite,
              lhsEnergy > 0,
              rhsEnergy > 0 else { return (0, 0) }
        return (
            Double(supportedFrames) / Double(frames.count),
            sqrt(min(lhsEnergy, rhsEnergy) / max(lhsEnergy, rhsEnergy))
                .clamped(to: 0 ... 1)
        )
    }

    private static func maximumMagnitude(_ channels: [[Float]], frame: Int) -> Double {
        channels.reduce(0) { max($0, abs(Double($1[frame]))) }
    }

    private static func maskingSeverity(_ score: Double) -> Double {
        ((score - maximumSpectralMaskingScore) / (1 - maximumSpectralMaskingScore))
            .clamped(to: 0 ... 1)
    }
}

private struct SpectralFrame {
    let startFrame: Int
    let frameCount: Int
    let energy: [Double]
    let rms: Double
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
