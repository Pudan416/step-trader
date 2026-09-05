#if DEBUG || INTERNAL_BUILD
import AVFAudio
import XCTest
@testable import Steps4

final class DayObjectsLoudnessAnalyzerTests: XCTestCase {
    func testOneKHzReferenceReportsFiniteLoudnessAndTruePeak() throws {
        let samples = makeSine(
            frequency: 1_000,
            amplitude: 0.1,
            seconds: 10,
            sampleRate: 48_000
        )

        let report = try DayObjectsLoudnessAnalyzer.analyze(
            samples: samples,
            sampleRate: 48_000
        )

        XCTAssertTrue(report.integratedLUFS.isFinite)
        XCTAssertTrue(report.truePeakDBTP.isFinite)
        XCTAssertEqual(report.integratedLUFS, -23.0, accuracy: 0.15)
        XCTAssertEqual(report.truePeakDBTP, -20, accuracy: 0.05)
        XCTAssertLessThanOrEqual(report.truePeakDBTP, -19.5)
        XCTAssertEqual(report.durationSeconds, 10, accuracy: 0.000_001)
        XCTAssertTrue(report.containsOnlyFiniteSamples)
    }

    func testAnalyzerRejectsEmptyNonFiniteAndUnsupportedRateInput() {
        XCTAssertThrowsError(
            try DayObjectsLoudnessAnalyzer.analyze(samples: [], sampleRate: 48_000)
        )
        XCTAssertThrowsError(
            try DayObjectsLoudnessAnalyzer.analyze(samples: [.nan], sampleRate: 48_000)
        )
        XCTAssertThrowsError(
            try DayObjectsLoudnessAnalyzer.analyze(samples: [.infinity], sampleRate: 48_000)
        )
        XCTAssertThrowsError(
            try DayObjectsLoudnessAnalyzer.analyze(samples: [0], sampleRate: 0)
        )
        XCTAssertThrowsError(
            try DayObjectsLoudnessAnalyzer.analyze(samples: [0], sampleRate: .infinity)
        )
    }

    func testRelativeGateExcludesAQuietTailFromIntegratedLoudness() throws {
        let loud = makeSine(
            frequency: 1_000,
            amplitude: 0.1,
            seconds: 5,
            sampleRate: 48_000
        )
        let quiet = makeSine(
            frequency: 1_000,
            amplitude: 0.001,
            seconds: 5,
            sampleRate: 48_000
        )

        let reference = try DayObjectsLoudnessAnalyzer.analyze(
            samples: loud,
            sampleRate: 48_000
        )
        let gated = try DayObjectsLoudnessAnalyzer.analyze(
            samples: loud + quiet,
            sampleRate: 48_000
        )

        XCTAssertEqual(gated.integratedLUFS, reference.integratedLUFS, accuracy: 0.15)
    }

    func testFourTimesOversamplingFindsAnInterSamplePeakAboveSamplePeak() throws {
        let samples = makeSine(
            frequency: 12_000,
            amplitude: 0.8,
            seconds: 1,
            sampleRate: 48_000,
            phaseRadians: .pi / 4
        )
        let samplePeak = samples.map { abs(Double($0)) }.max()!

        let report = try DayObjectsLoudnessAnalyzer.analyze(
            samples: samples,
            sampleRate: 48_000
        )

        XCTAssertGreaterThan(report.truePeakDBTP, 20 * log10(samplePeak) + 0.5)
        XCTAssertLessThanOrEqual(report.truePeakDBTP, 20 * log10(0.8) + 0.1)
    }

    func testStereoCaptureUsesIndependentBS1770ChannelEnergyAndPeak() throws {
        let sampleRate = 48_000.0
        let frameCount = AVAudioFrameCount(sampleRate * 2)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frameCount) {
            let sample = Float(0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate))
            channels[0][frame] = sample
            channels[1][frame] = -sample
        }

        let mono = try DayObjectsLoudnessAnalyzer.analyze(
            samples: (0..<Int(frameCount)).map { channels[0][$0] },
            sampleRate: sampleRate
        )
        let stereo = try DayObjectsStereoCaptureAdapter.analyze(buffer)

        XCTAssertEqual(
            stereo.integratedLUFS,
            mono.integratedLUFS + 10 * log10(2),
            accuracy: 0.02
        )
        XCTAssertEqual(stereo.truePeakDBTP, mono.truePeakDBTP, accuracy: 0.01)
        XCTAssertEqual(stereo.durationSeconds, 2, accuracy: 0.000_001)
    }

    private func makeSine(
        frequency: Double,
        amplitude: Float,
        seconds: Double,
        sampleRate: Double,
        phaseRadians: Double = 0
    ) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { frame in
            amplitude * sin(
                Float(
                    (2 * Double.pi * frequency * Double(frame) / sampleRate)
                        + phaseRadians
                )
            )
        }
    }
}
#endif
