#if DEBUG || INTERNAL_BUILD
import AVFAudio
import XCTest
@testable import Steps4

final class DayObjectsMixQualityAnalyzerTests: XCTestCase {
    func testFlagsDCOffsetBrightnessAndTruePeak() throws {
        let brightOffsetBuffer = try makeMonoBuffer { frame, sampleRate in
            0.03 + (0.98 * sin(2 * Double.pi * 10_000 * Double(frame) / sampleRate))
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: brightOffsetBuffer,
            stems: [:]
        )

        XCTAssertTrue(report.issues.contains(.dcOffset))
        XCTAssertTrue(report.issues.contains(.excessiveBrightness))
        XCTAssertTrue(report.issues.contains(.truePeak))
    }

    func testKickBassSuggestionIsBounded() throws {
        let lowPulse = try makeMonoBuffer { frame, sampleRate in
            0.2 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }
        let mixBuffer = try makeMonoBuffer { frame, sampleRate in
            0.4 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mixBuffer,
            stems: [.rhythm: lowPulse, .bass: lowPulse]
        )
        let value = try XCTUnwrap(report.suggestions.first { $0.role == .bass })

        XCTAssertTrue((-3.0 ... 0.0).contains(value.gainAdjustmentDB))
        XCTAssertTrue((0.0 ... 4.0).contains(value.additionalDuckingDB))
        XCTAssertTrue((0.75 ... 1.0).contains(value.cutoffMultiplier))
        XCTAssertTrue((-0.15 ... 0.0).contains(value.reverbSendAdjustment))
    }

    func testBandEnergyAudibilityAndReportAreDeterministic() throws {
        let fullMix = try makeMonoBuffer { frame, sampleRate in
            0.2 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }
        let bass = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }

        let first = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: fullMix,
            stems: [.bass: bass]
        )
        let second = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: fullMix,
            stems: [.bass: bass]
        )

        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.lowBandEnergyRatio, 0.99)
        XCTAssertLessThan(first.midBandEnergyRatio, 0.01)
        XCTAssertLessThan(first.highBandEnergyRatio, 0.01)
        XCTAssertEqual(
            try XCTUnwrap(first.layerAudibilityDB["bass"]),
            -6.020_599_913,
            accuracy: 0.000_01
        )
    }

    func testSilentReportRemainsFiniteCodableAndFlagsActiveSilentStem() throws {
        let silence = try makeMonoBuffer { _, _ in 0 }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: silence,
            stems: [.lead: silence]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DayObjectsMixQualityReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertTrue(report.issues.contains(.silence))
        XCTAssertTrue(report.issues.contains(.inaudibleStem))
        XCTAssertEqual(report.layerAudibilityDB["lead"], -120)
        XCTAssertTrue([
            report.integratedLUFS,
            report.truePeakDBTP,
            report.maximumAbsoluteDCOffset,
            report.crestFactorDB,
            report.lowBandEnergyRatio,
            report.midBandEnergyRatio,
            report.highBandEnergyRatio,
            report.kickBassLowBandCorrelation,
        ].allSatisfy(\.isFinite))
    }

    func testRejectsMismatchedStemSampleRateAndFrameCount() throws {
        let fullMix = try makeMonoBuffer { _, _ in 0 }
        let wrongRate = try makeMonoBuffer(sampleRate: 44_100) { _, _ in 0 }
        let wrongLength = try makeMonoBuffer(seconds: 0.5) { _, _ in 0 }

        XCTAssertThrowsError(
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: fullMix,
                stems: [.rhythm: wrongRate]
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsMixQualityAnalyzerError,
                .sampleRateMismatch(role: .rhythm)
            )
        }
        XCTAssertThrowsError(
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: fullMix,
                stems: [.harmony: wrongLength]
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsMixQualityAnalyzerError,
                .frameCountMismatch(role: .harmony)
            )
        }
    }

    func testRejectsNonFiniteStemSamples() throws {
        let fullMix = try makeMonoBuffer { _, _ in 0 }
        let nonFinite = try makeMonoBuffer { frame, _ in frame == 2_000 ? .nan : 0 }

        XCTAssertThrowsError(
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: fullMix,
                stems: [.happenings: nonFinite]
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsLoudnessAnalyzerError,
                .nonFiniteSample
            )
        }
    }

    private func makeMonoBuffer(
        seconds: Double = 1,
        sampleRate: Double = 48_000,
        sample: (Int, Double) -> Double
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sample(frame, sampleRate))
        }
        return buffer
    }
}
#endif
