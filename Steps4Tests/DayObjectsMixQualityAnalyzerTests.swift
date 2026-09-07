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
            report.clippedSampleRatio,
            report.transientDensityPerSecond,
            report.harmonyLeadMaskingScore,
            report.happeningsLeadMaskingScore,
            report.reverbTailEnergyRatio,
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

    func testExplicitActiveRolesIgnoreSilentExportedStems() throws {
        let mix = try makeMonoBuffer { frame, sampleRate in
            0.2 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let harmony = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let silence = try makeMonoBuffer { _, _ in 0 }
        let allExportedStems: [DayObjectsMixRole: AVAudioPCMBuffer] = [
            .rhythm: silence,
            .bass: silence,
            .harmony: harmony,
            .happenings: silence,
            .lead: silence,
        ]

        let explicit = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: allExportedStems,
            activeRoles: [.harmony]
        )
        let legacy = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: allExportedStems
        )

        XCTAssertFalse(explicit.issues.contains(.inaudibleStem))
        XCTAssertFalse(explicit.issues.contains(.harmonyLeadMasking))
        XCTAssertEqual(explicit.layerAudibilityDB["lead"], -120)
        XCTAssertTrue(legacy.issues.contains(.inaudibleStem))
    }

    func testTruePeakSafetyAndSampleClippingAreDistinctIssues() throws {
        let interSamplePeak = try makeMonoBuffer { frame, sampleRate in
            0.95 * sin(
                (2 * Double.pi * 12_000 * Double(frame) / sampleRate) + (.pi / 4)
            )
        }
        let clipped = try makeMonoBuffer { frame, sampleRate in
            frame.isMultiple(of: 2_400)
                ? 1.05
                : 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }

        let safeSamples = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: interSamplePeak,
            stems: [:]
        )
        let clippedSamples = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: clipped,
            stems: [:]
        )

        XCTAssertTrue(safeSamples.issues.contains(.truePeak))
        XCTAssertFalse(safeSamples.issues.contains(.clipping))
        XCTAssertEqual(safeSamples.clippedSampleRatio, 0)
        XCTAssertTrue(clippedSamples.issues.contains(.clipping))
        XCTAssertGreaterThan(clippedSamples.clippedSampleRatio, 0)
    }

    func testTransientDensityFlagsFrequentSeparatedImpulses() throws {
        let impulseTrain = try makeMonoBuffer { frame, _ in
            frame.isMultiple(of: 2_400) ? 0.8 : 0
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: impulseTrain,
            stems: [:]
        )

        XCTAssertEqual(report.transientDensityPerSecond, 20, accuracy: 0.001)
        XCTAssertTrue(report.issues.contains(.excessiveTransientDensity))
    }

    func testSpectralMaskingClassifiesHarmonyAndHappeningsAgainstLead() throws {
        let mix = try makeMonoBuffer { frame, sampleRate in
            0.3 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let sharedSpectrum = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: [
                .harmony: sharedSpectrum,
                .happenings: sharedSpectrum,
                .lead: sharedSpectrum,
            ],
            activeRoles: [.harmony, .happenings, .lead]
        )

        XCTAssertGreaterThan(report.harmonyLeadMaskingScore, 0.95)
        XCTAssertGreaterThan(report.happeningsLeadMaskingScore, 0.95)
        XCTAssertTrue(report.issues.contains(.harmonyLeadMasking))
        XCTAssertTrue(report.issues.contains(.happeningsLeadMasking))
        XCTAssertEqual(Set(report.suggestions.map(\.role)), [.harmony, .happenings])
        assertSuggestionsAreBounded(report.suggestions)
    }

    func testSeparatedSpectraDoNotFlagMasking() throws {
        let harmony = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 400 * Double(frame) / sampleRate)
        }
        let happenings = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 800 * Double(frame) / sampleRate)
        }
        let lead = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 3_000 * Double(frame) / sampleRate)
        }
        let mix = try makeMonoBuffer { frame, sampleRate in
            (0.1 * sin(2 * Double.pi * 400 * Double(frame) / sampleRate))
                + (0.1 * sin(2 * Double.pi * 800 * Double(frame) / sampleRate))
                + (0.1 * sin(2 * Double.pi * 3_000 * Double(frame) / sampleRate))
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: [.harmony: harmony, .happenings: happenings, .lead: lead],
            activeRoles: [.harmony, .happenings, .lead]
        )

        XCTAssertLessThan(report.harmonyLeadMaskingScore, 0.1)
        XCTAssertLessThan(report.happeningsLeadMaskingScore, 0.1)
        XCTAssertFalse(report.issues.contains(.harmonyLeadMasking))
        XCTAssertFalse(report.issues.contains(.happeningsLeadMasking))
    }

    func testSteadyToneDoesNotFlagTransientDensityOrTailAccumulation() throws {
        let steady = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: steady,
            stems: [:]
        )

        XCTAssertEqual(report.transientDensityPerSecond, 0)
        XCTAssertEqual(report.reverbTailEnergyRatio, 1, accuracy: 0.000_01)
        XCTAssertFalse(report.issues.contains(.excessiveTransientDensity))
        XCTAssertFalse(report.issues.contains(.excessiveReverbTail))
    }

    func testExplicitActiveRoleRequiresItsStemBuffer() throws {
        let mix = try makeMonoBuffer { _, _ in 0 }

        XCTAssertThrowsError(
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: mix,
                stems: [:],
                activeRoles: [.lead]
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsMixQualityAnalyzerError,
                .missingActiveStem(role: .lead)
            )
        }
    }

    func testReverbTailAccumulationUsesRelativeTrailingEnergy() throws {
        let accumulatingTail = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            guard frame >= Int(2 * sampleRate) else { return 0 }
            return 0.15 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: accumulatingTail,
            stems: [.harmony: accumulatingTail],
            activeRoles: [.harmony]
        )

        XCTAssertGreaterThan(report.reverbTailEnergyRatio, 1.5)
        XCTAssertTrue(report.issues.contains(.excessiveReverbTail))
        let suggestion = try XCTUnwrap(report.suggestions.first { $0.role == .harmony })
        XCTAssertLessThan(suggestion.reverbSendAdjustment, 0)
        assertSuggestionsAreBounded(report.suggestions)
    }

    func testShortSupportedCaptureUsesZeroPaddedSpectrum() throws {
        let nyquistTone = try makeMonoBuffer(seconds: 0.4, sampleRate: 8_000) { frame, _ in
            frame.isMultiple(of: 2) ? 0.5 : -0.5
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: nyquistTone,
            stems: [:]
        )

        XCTAssertGreaterThan(report.highBandEnergyRatio, 0.45)
        XCTAssertTrue(report.issues.contains(.excessiveBrightness))
    }

    private func assertSuggestionsAreBounded(
        _ suggestions: [DayObjectsMixSuggestion],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for suggestion in suggestions {
            XCTAssertTrue((-3.0 ... 0.0).contains(suggestion.gainAdjustmentDB), file: file, line: line)
            XCTAssertTrue((0.0 ... 4.0).contains(suggestion.additionalDuckingDB), file: file, line: line)
            XCTAssertTrue((0.75 ... 1.0).contains(suggestion.cutoffMultiplier), file: file, line: line)
            XCTAssertTrue((-0.15 ... 0.0).contains(suggestion.reverbSendAdjustment), file: file, line: line)
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
