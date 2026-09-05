#if DEBUG || INTERNAL_BUILD
import Accelerate
import AVFAudio
import Foundation

struct DayObjectsLoudnessReport: Equatable, Sendable {
    let integratedLUFS: Double
    let truePeakDBTP: Double
    let durationSeconds: Double
    let containsOnlyFiniteSamples: Bool
}

enum DayObjectsLoudnessAnalyzerError: Error, Equatable, Sendable {
    case emptySamples
    case nonFiniteSample
    case unsupportedSampleRate
    case unsupportedPCMFormat
    case unsupportedChannelLayout
}

enum DayObjectsLoudnessAnalyzer {
    private static let loudnessOffset = -0.691
    private static let absoluteGateLUFS = -70.0
    private static let silentFloorDB = -120.0

    static func analyze(
        samples: [Float],
        sampleRate: Double
    ) throws -> DayObjectsLoudnessReport {
        try analyze(channels: [samples], channelWeights: [1], sampleRate: sampleRate)
    }

    fileprivate static func analyze(
        channels: [[Float]],
        channelWeights: [Double],
        sampleRate: Double
    ) throws -> DayObjectsLoudnessReport {
        guard let frameCount = channels.first?.count, frameCount > 0 else {
            throw DayObjectsLoudnessAnalyzerError.emptySamples
        }
        guard sampleRate.isFinite, (8_000...384_000).contains(sampleRate) else {
            throw DayObjectsLoudnessAnalyzerError.unsupportedSampleRate
        }
        guard channels.count == channelWeights.count,
              channels.allSatisfy({ $0.count == frameCount }) else {
            throw DayObjectsLoudnessAnalyzerError.unsupportedChannelLayout
        }
        guard channels.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw DayObjectsLoudnessAnalyzerError.nonFiniteSample
        }

        let perChannelBlockEnergies = channels.map {
            kWeightedBlockEnergies(samples: $0, sampleRate: sampleRate)
        }
        let blockCount = perChannelBlockEnergies.map(\.count).min() ?? 0
        let blockEnergies = (0..<blockCount).map { blockIndex in
            perChannelBlockEnergies.indices.reduce(0) { result, channelIndex in
                result + (
                    perChannelBlockEnergies[channelIndex][blockIndex]
                        * channelWeights[channelIndex]
                )
            }
        }
        let integratedLUFS = gatedLoudness(blockEnergies)
        let truePeak = channels.map(fourTimesOversampledPeak).max() ?? 0

        return DayObjectsLoudnessReport(
            integratedLUFS: integratedLUFS,
            truePeakDBTP: decibels(truePeak),
            durationSeconds: Double(frameCount) / sampleRate,
            containsOnlyFiniteSamples: true
        )
    }

    private static func kWeightedBlockEnergies(
        samples: [Float],
        sampleRate: Double
    ) -> [Double] {
        var shelf = Biquad(kWeightingShelfCoefficients(sampleRate: sampleRate))
        var highPass = Biquad(kWeightingHighPassCoefficients(sampleRate: sampleRate))
        var squaredPrefix = [Double](repeating: 0, count: samples.count + 1)

        for index in samples.indices {
            let filtered = highPass.process(shelf.process(Double(samples[index])))
            squaredPrefix[index + 1] = squaredPrefix[index] + (filtered * filtered)
        }

        let requestedBlockFrames = Int((0.4 * sampleRate).rounded())
        let blockFrames = min(max(requestedBlockFrames, 1), samples.count)
        let stepFrames = max(Int((0.1 * sampleRate).rounded()), 1)
        var energies: [Double] = []
        energies.reserveCapacity(max(1, ((samples.count - blockFrames) / stepFrames) + 1))

        var start = 0
        while start + blockFrames <= samples.count {
            let end = start + blockFrames
            energies.append(
                (squaredPrefix[end] - squaredPrefix[start]) / Double(blockFrames)
            )
            start += stepFrames
        }
        return energies
    }

    private static func gatedLoudness(_ blockEnergies: [Double]) -> Double {
        let absoluteGated = blockEnergies.filter {
            loudness(energy: $0) >= absoluteGateLUFS
        }
        guard !absoluteGated.isEmpty else { return silentFloorDB }

        let ungatedEnergy = absoluteGated.reduce(0, +) / Double(absoluteGated.count)
        let relativeGateLUFS = loudness(energy: ungatedEnergy) - 10
        let relativeGated = absoluteGated.filter {
            loudness(energy: $0) >= relativeGateLUFS
        }
        guard !relativeGated.isEmpty else { return silentFloorDB }

        let integratedEnergy = relativeGated.reduce(0, +) / Double(relativeGated.count)
        return loudness(energy: integratedEnergy)
    }

    private static func loudness(energy: Double) -> Double {
        guard energy.isFinite, energy > 0 else { return -.infinity }
        return loudnessOffset + (10 * log10(energy))
    }

    private static func fourTimesOversampledPeak(_ samples: [Float]) -> Double {
        var samplePeak: Float = 0
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            vDSP_maxmgv(baseAddress, 1, &samplePeak, vDSP_Length(samples.count))
        }
        var peak = Double(samplePeak)
        guard samples.count > SincKernel.radius * 2 else { return peak }

        let kernelLength = SincKernel.floatCoefficients[0].count
        let resultCount = samples.count - kernelLength + 1
        var phaseSamples = [Float](repeating: 0, count: resultCount)
        for kernel in SincKernel.floatCoefficients {
            samples.withUnsafeBufferPointer { input in
                kernel.withUnsafeBufferPointer { filter in
                    phaseSamples.withUnsafeMutableBufferPointer { output in
                        guard let inputBase = input.baseAddress,
                              let filterBase = filter.baseAddress,
                              let outputBase = output.baseAddress else { return }
                        vDSP_conv(
                            inputBase,
                            1,
                            filterBase,
                            1,
                            outputBase,
                            1,
                            vDSP_Length(resultCount),
                            vDSP_Length(kernelLength)
                        )
                    }
                }
            }
            var phasePeak: Float = 0
            phaseSamples.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return }
                vDSP_maxmgv(baseAddress, 1, &phasePeak, vDSP_Length(resultCount))
            }
            peak = max(peak, Double(phasePeak))
        }
        return peak
    }

    private static func decibels(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return silentFloorDB }
        return max(20 * log10(amplitude), silentFloorDB)
    }

    private static func kWeightingShelfCoefficients(sampleRate: Double) -> Biquad.Coefficients {
        let gainDB = 3.999_843_853_973_347
        let quality = 0.707_175_236_955_419_6
        let centerFrequency = 1_681.974_450_955_533
        let k = tan(.pi * centerFrequency / sampleRate)
        let highGain = pow(10, gainDB / 20)
        let bandGain = pow(highGain, 0.499_666_774_154_541_6)
        let denominator = 1 + (k / quality) + (k * k)

        return .init(
            b0: (highGain + (bandGain * k / quality) + (k * k)) / denominator,
            b1: 2 * ((k * k) - highGain) / denominator,
            b2: (highGain - (bandGain * k / quality) + (k * k)) / denominator,
            a1: 2 * ((k * k) - 1) / denominator,
            a2: (1 - (k / quality) + (k * k)) / denominator
        )
    }

    private static func kWeightingHighPassCoefficients(sampleRate: Double) -> Biquad.Coefficients {
        let quality = 0.500_327_037_323_877_3
        let centerFrequency = 38.135_470_876_024_44
        let k = tan(.pi * centerFrequency / sampleRate)
        let denominator = 1 + (k / quality) + (k * k)

        return .init(
            b0: 1 / denominator,
            b1: -2 / denominator,
            b2: 1 / denominator,
            a1: 2 * ((k * k) - 1) / denominator,
            a2: (1 - (k / quality) + (k * k)) / denominator
        )
    }
}

/// Converts the renderer's planar float capture into independently weighted
/// BS.1770 channels. Left and right each carry unity weight; they are never
/// summed as waveforms, so anti-phase stereo cannot cancel from loudness.
enum DayObjectsStereoCaptureAdapter {
    static func analyze(_ buffer: AVAudioPCMBuffer) throws -> DayObjectsLoudnessReport {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved,
              let channelData = buffer.floatChannelData else {
            throw DayObjectsLoudnessAnalyzerError.unsupportedPCMFormat
        }
        let channelCount = Int(buffer.format.channelCount)
        guard (1...2).contains(channelCount) else {
            throw DayObjectsLoudnessAnalyzerError.unsupportedChannelLayout
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            throw DayObjectsLoudnessAnalyzerError.emptySamples
        }
        let channels = (0..<channelCount).map { channel in
            Array(UnsafeBufferPointer(start: channelData[channel], count: frameCount))
        }
        return try DayObjectsLoudnessAnalyzer.analyze(
            channels: channels,
            channelWeights: [Double](repeating: 1, count: channelCount),
            sampleRate: buffer.format.sampleRate
        )
    }
}

private struct Biquad {
    struct Coefficients {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double
    }

    private let coefficients: Coefficients
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    init(_ coefficients: Coefficients) {
        self.coefficients = coefficients
    }

    mutating func process(_ sample: Double) -> Double {
        let output = (coefficients.b0 * sample)
            + (coefficients.b1 * x1)
            + (coefficients.b2 * x2)
            - (coefficients.a1 * y1)
            - (coefficients.a2 * y2)
        x2 = x1
        x1 = sample
        y2 = y1
        y1 = output
        return output
    }
}

private enum SincKernel {
    static let radius = 8
    static let coefficients: [[Double]] = (1..<4).map { phase in
        let fraction = Double(phase) / 4
        var result = (-(radius - 1)...radius).map { offset -> Double in
            let distance = fraction - Double(offset)
            let normalizedDistance = abs(distance) / Double(radius)
            guard normalizedDistance <= 1 else { return 0 }
            let sinc = distance == 0
                ? 1
                : sin(.pi * distance) / (.pi * distance)
            let window = 0.42
                + (0.5 * cos(.pi * normalizedDistance))
                + (0.08 * cos(2 * .pi * normalizedDistance))
            return sinc * window
        }
        let sum = result.reduce(0, +)
        if sum != 0 {
            for index in result.indices { result[index] /= sum }
        }
        return result
    }
    static let floatCoefficients = coefficients.map { $0.map(Float.init) }
}
#endif
