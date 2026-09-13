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
        XCTAssertTrue(report.reverbTailEnergyRatioByRole.values.allSatisfy(\.isFinite))
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

    func testEnvelopeTransientDensityFlagsRealisticToneBurstsAcrossPitch() throws {
        for frequency in [100.0, 250, 400, 600, 1_000, 5_000] {
            let toneBursts = try makeMonoBuffer { frame, sampleRate in
                let eventFrame = frame % Int(0.05 * sampleRate)
                let eventTime = Double(eventFrame) / sampleRate
                let envelope: Double
                if eventTime < 0.005 {
                    envelope = eventTime / 0.005
                } else if eventTime < 0.020 {
                    envelope = 1 - ((eventTime - 0.005) / 0.015)
                } else {
                    envelope = 0
                }
                return 0.5 * envelope
                    * sin(2 * Double.pi * frequency * Double(frame) / sampleRate)
            }

            let report = try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: toneBursts,
                stems: [:]
            )

            XCTAssertEqual(
                report.transientDensityPerSecond,
                20,
                accuracy: 0.5,
                "Missed pitched bursts at \(frequency) Hz"
            )
            XCTAssertTrue(
                report.issues.contains(.excessiveTransientDensity),
                "Missed transient issue at \(frequency) Hz"
            )
        }
    }

    func testTwentyFourSecondSteadyBassDoesNotBecomeTwentyFiveOnsetsPerSecond() throws {
        let steady = try makeMonoBuffer(seconds: 24) { frame, sampleRate in
            0.2 * sin((2 * .pi * 25 * Double(frame) / sampleRate) + 0.37)
        }
        let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: steady, stems: [:])

        XCTAssertLessThanOrEqual(report.transientDensityPerSecond, 1.0 / 24)
        XCTAssertFalse(report.issues.contains(.excessiveTransientDensity))
    }

    func testTwentyFourSecondExponentialPercussionRetainsTwentyOnsetsPerSecond() throws {
        let percussion = try makeMonoBuffer(seconds: 24) { frame, sampleRate in
            let time = Double(frame) / sampleRate
            let elapsed = time.truncatingRemainder(dividingBy: 0.05)
            let envelope = min(elapsed / 0.002, 1) * exp(-elapsed / 0.03)
            return 0.5 * envelope * sin(2 * .pi * 1_000 * time)
        }
        let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: percussion, stems: [:])

        XCTAssertEqual(report.transientDensityPerSecond, 20, accuracy: 0.1)
        XCTAssertTrue(report.issues.contains(.excessiveTransientDensity))
    }

    func testSteadyCarrierOnsetsStayIndependentOfPhaseLevelAndSampleRate() throws {
        let frequencies: [Double] = [20, 25, 32, 40, 55, 80, 100, 250, 440, 1_000, 2_500, 5_000]
        let sampleRates: [Double] = [16_000, 44_100, 48_000, 96_000]
        let amplitudes: [Double] = [0.03, 0.2, 0.8]
        for (frequencyIndex, frequency) in frequencies.enumerated() {
            for phaseIndex in 0..<32 {
                let sampleRate = sampleRates[(phaseIndex + frequencyIndex) % sampleRates.count]
                let amplitude = amplitudes[(phaseIndex / 4 + frequencyIndex) % amplitudes.count]
                let phase = 2 * .pi * Double(phaseIndex) / 32
                let steady = try makeMonoBuffer(seconds: 1, sampleRate: sampleRate) { frame, rate in
                    amplitude * sin((2 * .pi * frequency * Double(frame) / rate) + phase)
                }
                let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: steady, stems: [:])
                let label = "steady \(frequency) Hz, phase \(phaseIndex)/32, amplitude \(amplitude), rate \(sampleRate)"
                XCTAssertLessThanOrEqual(report.transientDensityPerSecond, 1, label)
                XCTAssertFalse(report.issues.contains(.excessiveTransientDensity), label)
            }
        }
    }

    func testPercussiveOnsetDensityAcrossPitchEnvelopeTempoAndOffset() throws {
        let frequencies: [Double] = [40, 60, 100, 250, 440, 1_000, 5_000]
        let densities: [Double] = [2, 8, 12, 16, 20]
        let envelopes: [(attack: Double, decay: Double)] = [(0.002, 0.03), (0.005, 0.015), (0.01, 0.06)]
        let sampleRates: [Double] = [16_000, 44_100, 48_000]
        let offsets: [Double] = [0, 0.0017, 0.013]
        for (frequencyIndex, frequency) in frequencies.enumerated() {
            for (densityIndex, density) in densities.enumerated() {
                for (envelopeIndex, envelope) in envelopes.enumerated() {
                    for (offsetIndex, offset) in offsets.enumerated() {
                        let sampleRate = sampleRates[(frequencyIndex + densityIndex + offsetIndex) % 3]
                        let amplitude = [0.15, 0.5, 0.8][(envelopeIndex + offsetIndex) % 3]
                        let percussion = try makeMonoBuffer(seconds: 2, sampleRate: sampleRate) { frame, rate in
                            let time = Double(frame) / rate
                            guard time >= offset else { return 0 }
                            let elapsed = (time - offset).truncatingRemainder(dividingBy: 1 / density)
                            let level = min(elapsed / envelope.attack, 1) * exp(-elapsed / envelope.decay)
                            return amplitude * level * sin((2 * .pi * frequency * time) + 0.37)
                        }
                        let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: percussion, stems: [:])
                        let label = "bursts \(frequency) Hz, \(density)/s, attack/decay \(envelope), offset \(offset), rate \(sampleRate)"
                        XCTAssertEqual(report.transientDensityPerSecond, density, accuracy: 0.5, label)
                        XCTAssertEqual(report.issues.contains(.excessiveTransientDensity), density > 12, label)
                    }
                }
            }
        }
    }

    func testTransientDensityDoesNotFlagSteadyCarriers() throws {
        let frequencies: [Double] = [20, 30, 40, 50, 60, 100, 250, 400, 600, 1_000, 5_000]
        for frequency in frequencies {
            let steady = try makeMonoBuffer { frame, sampleRate in
                0.2 * sin(2 * Double.pi * frequency * Double(frame) / sampleRate)
            }
            let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: steady, stems: [:])

            XCTAssertLessThanOrEqual(
                report.transientDensityPerSecond,
                1,
                "Unexpected onset density for \(frequency) Hz"
            )
            XCTAssertFalse(
                report.issues.contains(.excessiveTransientDensity),
                "Unexpected transient issue for \(frequency) Hz"
            )
        }
    }

    func testTransientDensityDoesNotFlagNoiseFloor() throws {
        let noiseFloor = try makeMonoBuffer { frame, _ in
            let hash = (UInt64(frame) &* 2_862_933_555_777_941_757) &+ 3_037_000_493
            let normalized = (Double(hash & 0xffff) / 32_767.5) - 1
            return 0.002 * normalized
        }

        let noiseReport = try DayObjectsMixQualityAnalyzer.analyze(fullMix: noiseFloor, stems: [:])

        XCTAssertEqual(noiseReport.transientDensityPerSecond, 0)
        XCTAssertFalse(noiseReport.issues.contains(.excessiveTransientDensity))
    }

    func testTransientDensityDoesNotFlagAudibleStationaryNoise() throws {
        for seed in [UInt64(1), 0x1234_5678, 0xdead_beef] {
            for amplitude in [0.15, 0.2] {
                let stationaryNoise = try makeMonoBuffer { frame, _ in
                    var value = UInt64(frame) &+ (seed &* 0x9e37_79b9_7f4a_7c15)
                    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
                    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
                    value ^= value >> 31
                    let normalized = (Double(value >> 11) / 4_503_599_627_370_495.5) - 1
                    return amplitude * normalized
                }

                let report = try DayObjectsMixQualityAnalyzer.analyze(
                    fullMix: stationaryNoise,
                    stems: [:]
                )

                XCTAssertLessThanOrEqual(
                    report.transientDensityPerSecond,
                    1,
                    "Stationary noise seed \(seed), amplitude \(amplitude)"
                )
                XCTAssertFalse(
                    report.issues.contains(.excessiveTransientDensity),
                    "Stationary noise seed \(seed), amplitude \(amplitude)"
                )
            }
        }
    }

    func testFilteredStationaryNoiseDoesNotCrossExcessiveDensityGate() throws {
        for (cutoffIndex, cutoff) in [20.0, 32, 40, 55, 100, 250, 1_500].enumerated() {
            for seed in 0..<16 {
                let sampleRate = [16_000.0, 44_100, 48_000][(seed + cutoffIndex) % 3]
                let amplitude = [0.03, 0.2, 0.8][(seed / 3 + cutoffIndex) % 3]
                let noise = try makeFilteredNoiseBuffer(
                    seconds: 2, sampleRate: sampleRate, cutoff: cutoff,
                    amplitude: amplitude, seed: UInt64(seed)
                )
                let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: noise, stems: [:])
                let label = "stationary low-pass \(cutoff) Hz, seed \(seed), amplitude \(amplitude), rate \(sampleRate)"
                // Narrow bass noise has real random envelope swells. Its
                // acceptance contract is no excessive-density issue, rather
                // than a claim that stationary noise has a constant envelope.
                XCTAssertLessThanOrEqual(report.transientDensityPerSecond, 12, label)
                XCTAssertFalse(report.issues.contains(.excessiveTransientDensity), label)
                XCTAssertTrue(report.suggestions.isEmpty, label)
            }
        }
    }

    func testTwentyFourSecondStrongStationaryBassNoiseStaysBelowDensityGate() throws {
        for (cutoff, seed) in [(20.0, UInt64(28)), (32.0, 10), (40.0, 1), (55.0, 0xdead_beef)] {
            let noise = try makeFilteredNoiseBuffer(
                seconds: 24, sampleRate: 16_000, cutoff: cutoff,
                amplitude: 0.8, seed: seed
            )
            let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: noise, stems: [:])
            let label = "24s stationary low-pass \(cutoff) Hz, seed \(seed)"
            XCTAssertLessThanOrEqual(report.transientDensityPerSecond, 12, label)
            XCTAssertFalse(report.issues.contains(.excessiveTransientDensity), label)
            XCTAssertTrue(report.suggestions.isEmpty, label)
        }
    }

    func testNoiseBurstDensityAcrossColorEnvelopeAndTempo() throws {
        for (cutoffIndex, cutoff) in [40.0, 250, 1_000, 5_000].enumerated() {
            for (densityIndex, density) in [2.0, 12, 20].enumerated() {
                for (envelopeIndex, envelope) in [(0.002, 0.03), (0.005, 0.015), (0.01, 0.06)].enumerated() {
                    let sampleRate = [16_000.0, 44_100, 48_000][(cutoffIndex + densityIndex + envelopeIndex) % 3]
                    let offset = [0.0, 0.0017, 0.013][envelopeIndex]
                    let coefficient = exp(-2 * .pi * cutoff / sampleRate)
                    var lowPass = 0.0
                    let noise = try makeMonoBuffer(seconds: 2, sampleRate: sampleRate) { frame, rate in
                        let white = seededNoise(frame: frame, seed: UInt64(1 + cutoffIndex + densityIndex + envelopeIndex))
                        lowPass = (coefficient * lowPass) + ((1 - coefficient) * white)
                        let time = Double(frame) / rate
                        guard time >= offset else { return 0 }
                        let elapsed = (time - offset).truncatingRemainder(dividingBy: 1 / density)
                        let level = min(elapsed / envelope.0, 1) * exp(-elapsed / envelope.1)
                        return 0.8 * level * (white - lowPass)
                    }
                    let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: noise, stems: [:])
                    let label = "noise bursts above \(cutoff) Hz, \(density)/s, envelope \(envelope), offset \(offset)"
                    XCTAssertEqual(report.transientDensityPerSecond, density, accuracy: 0.5, label)
                    XCTAssertEqual(report.issues.contains(.excessiveTransientDensity), density > 12, label)
                }
            }
        }
    }

    func testPitchSweptKickOnsetsSurviveLongOverlappingDecays() throws {
        for frequency in [40.0, 60, 100] {
            for density in [2.0, 12, 20] {
                let kick = try makeMonoBuffer(seconds: 2) { frame, sampleRate in
                    let time = Double(frame) / sampleRate
                    let elapsed = time.truncatingRemainder(dividingBy: 1 / density)
                    let level = min(elapsed / 0.002, 1) * exp(-elapsed / 0.03)
                    let cycles = (frequency * elapsed) + (180 * 0.02 * (1 - exp(-elapsed / 0.02)))
                    return 0.5 * level * sin((2 * .pi * cycles) + 0.37)
                }
                let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: kick, stems: [:])
                let label = "pitch-swept \(frequency) Hz kick, \(density)/s"
                XCTAssertEqual(report.transientDensityPerSecond, density, accuracy: 0.5, label)
                XCTAssertEqual(report.issues.contains(.excessiveTransientDensity), density > 12, label)
            }
        }
    }

    func testShortCaptureCountsSilenceAndStartupWithoutEndPaddingOnsets() throws {
        for sampleRate in [8_000.0, 48_000, 96_000] {
            let silence = try makeMonoBuffer(seconds: 0.4, sampleRate: sampleRate) { _, _ in 0 }
            let silentReport = try DayObjectsMixQualityAnalyzer.analyze(fullMix: silence, stems: [:])
            XCTAssertEqual(silentReport.transientDensityPerSecond, 0)
            for frequency in [20.0, 25, 1_000] {
                for onset in [0.0, 0.2] {
                    let tone = try makeMonoBuffer(seconds: 0.4, sampleRate: sampleRate) { frame, rate in
                        let time = Double(frame) / rate
                        return time < onset ? 0 : 0.2 * sin((2 * .pi * frequency * time) + 0.37)
                    }
                    let report = try DayObjectsMixQualityAnalyzer.analyze(fullMix: tone, stems: [:])
                    XCTAssertEqual(report.transientDensityPerSecond, 2.5, accuracy: 0.001,
                                   "short \(frequency) Hz, start \(onset), rate \(sampleRate)")
                    XCTAssertFalse(report.issues.contains(.excessiveTransientDensity))
                }
            }
        }
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

    func testIdenticalFrequenciesSeparatedInTimeDoNotFlagMasking() throws {
        let harmony = try makeMonoBuffer(seconds: 2) { frame, sampleRate in
            guard frame < Int(0.7 * sampleRate) else { return 0 }
            return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let happenings = try makeMonoBuffer(seconds: 2) { frame, sampleRate in
            guard frame < Int(0.7 * sampleRate) else { return 0 }
            return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let lead = try makeMonoBuffer(seconds: 2) { frame, sampleRate in
            guard frame >= Int(1.3 * sampleRate) else { return 0 }
            return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let mix = try makeMonoBuffer(seconds: 2) { frame, sampleRate in
            guard frame < Int(0.7 * sampleRate) || frame >= Int(1.3 * sampleRate) else {
                return 0
            }
            return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: [.harmony: harmony, .happenings: happenings, .lead: lead],
            activeRoles: [.harmony, .happenings, .lead]
        )

        XCTAssertEqual(report.harmonyLeadMaskingScore, 0, accuracy: 0.000_01)
        XCTAssertEqual(report.happeningsLeadMaskingScore, 0, accuracy: 0.000_01)
        XCTAssertFalse(report.issues.contains(.harmonyLeadMasking))
        XCTAssertFalse(report.issues.contains(.happeningsLeadMasking))
    }

    func testAdjacentIdenticalFrequenciesDoNotMaskAcrossFFTWindow() throws {
        for gapMilliseconds in [0, 10, 20] {
            let gapFrames = gapMilliseconds * 48
            let boundary = 24_000
            let harmony = try makeMonoBuffer { frame, sampleRate in
                guard frame < boundary else { return 0 }
                return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            let happenings = try makeMonoBuffer { frame, sampleRate in
                guard frame < boundary else { return 0 }
                return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            let lead = try makeMonoBuffer { frame, sampleRate in
                guard frame >= boundary + gapFrames else { return 0 }
                return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            let mix = try makeMonoBuffer { frame, sampleRate in
                guard frame < boundary || frame >= boundary + gapFrames else { return 0 }
                return 0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }

            let report = try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: mix,
                stems: [.harmony: harmony, .happenings: happenings, .lead: lead],
                activeRoles: [.harmony, .happenings, .lead]
            )

            XCTAssertEqual(
                report.harmonyLeadMaskingScore,
                0,
                accuracy: 0.000_01,
                "Gap: \(gapMilliseconds) ms"
            )
            XCTAssertEqual(
                report.happeningsLeadMaskingScore,
                0,
                accuracy: 0.000_01,
                "Gap: \(gapMilliseconds) ms"
            )
            XCTAssertFalse(report.issues.contains(.harmonyLeadMasking))
            XCTAssertFalse(report.issues.contains(.happeningsLeadMasking))
        }
    }

    func testMaskingScorePreservesWeakerStemLevelRatio() throws {
        func report(weakerAmplitude: Double) throws -> DayObjectsMixQualityReport {
            let lead = try makeMonoBuffer { frame, sampleRate in
                0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            let weaker = try makeMonoBuffer { frame, sampleRate in
                weakerAmplitude * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            let mix = try makeMonoBuffer { frame, sampleRate in
                (0.1 + (2 * weakerAmplitude))
                    * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
            }
            return try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: mix,
                stems: [.harmony: weaker, .happenings: weaker, .lead: lead],
                activeRoles: [.harmony, .happenings, .lead]
            )
        }

        let equalLevel = try report(weakerAmplitude: 0.1)
        let minus20DB = try report(weakerAmplitude: 0.01)
        let minus40DB = try report(weakerAmplitude: 0.001)

        XCTAssertGreaterThan(equalLevel.harmonyLeadMaskingScore, 0.95)
        XCTAssertGreaterThan(equalLevel.happeningsLeadMaskingScore, 0.95)
        XCTAssertLessThan(minus20DB.harmonyLeadMaskingScore, 0.2)
        XCTAssertLessThan(minus20DB.happeningsLeadMaskingScore, 0.2)
        XCTAssertLessThan(minus40DB.harmonyLeadMaskingScore, 0.02)
        XCTAssertLessThan(minus40DB.happeningsLeadMaskingScore, 0.02)
        XCTAssertFalse(minus20DB.issues.contains(.harmonyLeadMasking))
        XCTAssertFalse(minus20DB.issues.contains(.happeningsLeadMasking))
        XCTAssertFalse(minus40DB.issues.contains(.harmonyLeadMasking))
        XCTAssertFalse(minus40DB.issues.contains(.happeningsLeadMasking))
        XCTAssertTrue(minus20DB.suggestions.isEmpty)
        XCTAssertTrue(minus40DB.suggestions.isEmpty)
        assertSuggestionsAreBounded(equalLevel.suggestions)
    }

    func testSubAudibleStemDoesNotFlagContemporaneousMasking() throws {
        let lead = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate)
        }
        let subAudibleHarmony = try makeMonoBuffer { frame, sampleRate in
            (0.1 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate))
                + (0.000_01 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate))
        }
        let mix = try makeMonoBuffer { frame, sampleRate in
            (0.1 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate))
                + (0.100_01 * sin(2 * Double.pi * 1_000 * Double(frame) / sampleRate))
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: [.harmony: subAudibleHarmony, .lead: lead],
            activeRoles: [.harmony, .lead]
        )

        XCTAssertLessThan(report.harmonyLeadMaskingScore, 0.01)
        XCTAssertFalse(report.issues.contains(.harmonyLeadMasking))
    }

    func testSteadyToneWithoutTailBoundarySkipsTailClassification() throws {
        let steady = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: steady,
            stems: [:]
        )

        XCTAssertTrue(report.reverbTailEnergyRatioByRole.isEmpty)
        XCTAssertEqual(report.reverbTailEnergyRatio, 0)
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

    func testKnownBoundaryClassifiesLongExponentialTailForEvidencedRole() throws {
        let longTail = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            let time = Double(frame) / sampleRate
            let envelope = time < 2 ? 0.1 : 0.1 * exp(-(time - 2) / 1.5)
            return envelope * sin(2 * Double.pi * 600 * time)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: longTail,
            stems: [.harmony: longTail],
            activeRoles: [.harmony],
            tailBoundaryFrames: [.harmony: 96_000]
        )

        XCTAssertGreaterThan(report.reverbTailEnergyRatioByRole["harmony"] ?? 0, 0.2)
        XCTAssertTrue(report.issues.contains(.excessiveReverbTail))
        let suggestion = try XCTUnwrap(report.suggestions.first { $0.role == .harmony })
        XCTAssertLessThan(suggestion.reverbSendAdjustment, 0)
        XCTAssertEqual(report.suggestions.map(\.role), [.harmony])
        assertSuggestionsAreBounded(report.suggestions)
    }

    func testDryHarmonyTailIsNotBlamedForLateDryBass() throws {
        let harmony = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            guard frame < Int(2 * sampleRate) else { return 0 }
            return 0.1 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
        }
        let lateBass = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            guard frame >= Int(3.5 * sampleRate) else { return 0 }
            return 0.15 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }
        let mix = try makeMonoBuffer(seconds: 4) { frame, sampleRate in
            if frame < Int(2 * sampleRate) {
                return 0.1 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
            }
            guard frame >= Int(3.5 * sampleRate) else { return 0 }
            return 0.15 * sin(2 * Double.pi * 80 * Double(frame) / sampleRate)
        }

        let report = try DayObjectsMixQualityAnalyzer.analyze(
            fullMix: mix,
            stems: [.harmony: harmony, .bass: lateBass],
            activeRoles: [.harmony, .bass],
            tailBoundaryFrames: [.harmony: 96_000]
        )

        XCTAssertEqual(report.reverbTailEnergyRatioByRole["harmony"], 0)
        XCTAssertNil(report.reverbTailEnergyRatioByRole["bass"])
        XCTAssertFalse(report.issues.contains(.excessiveReverbTail))
        XCTAssertFalse(report.suggestions.contains { $0.reverbSendAdjustment < 0 })
    }

    func testRejectsTailBoundaryOutsideStemFrames() throws {
        let harmony = try makeMonoBuffer { frame, sampleRate in
            0.1 * sin(2 * Double.pi * 600 * Double(frame) / sampleRate)
        }

        XCTAssertThrowsError(
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: harmony,
                stems: [.harmony: harmony],
                activeRoles: [.harmony],
                tailBoundaryFrames: [.harmony: 48_000]
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsMixQualityAnalyzerError,
                .invalidTailBoundary(role: .harmony, frame: 48_000)
            )
        }
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

    private func seededNoise(frame: Int, seed: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(frame)) &+ (seed &* 0x9e37_79b9_7f4a_7c15)
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        value ^= value >> 31
        return (Double(value >> 11) / 4_503_599_627_370_495.5) - 1
    }

    private func makeFilteredNoiseBuffer(
        seconds: Double, sampleRate: Double, cutoff: Double,
        amplitude: Double, seed: UInt64
    ) throws -> AVAudioPCMBuffer {
        let coefficient = exp(-2 * .pi * cutoff / sampleRate)
        let normalization = sqrt((1 + coefficient) / (1 - coefficient))
        var state = 0.0
        for frame in -Int(sampleRate)..<0 {
            state = (coefficient * state) + ((1 - coefficient) * seededNoise(frame: frame, seed: seed))
        }
        return try makeMonoBuffer(seconds: seconds, sampleRate: sampleRate) { frame, _ in
            state = (coefficient * state) + ((1 - coefficient) * seededNoise(frame: frame, seed: seed))
            return amplitude * normalization * state
        }
    }
}
#endif
