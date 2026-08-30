import XCTest
@testable import Steps4

final class SynthOnePresetAdapterTests: XCTestCase {
    func testMissingValuesUseDocumentedFiniteDefaults() {
        let result = SynthOnePresetAdapter.convert(.init(uid: "fixture", name: "Fixture"))
        let voice = result.voice

        XCTAssertEqual(voice.oscillator1, .init(wavePosition: 0.5, level: 0.5, semitoneOffset: 0, fineDetuneSemitones: 0))
        XCTAssertEqual(voice.oscillator2, .init(wavePosition: 0.5, level: 0.5, semitoneOffset: 0, fineDetuneSemitones: 0))
        XCTAssertEqual(voice.subOscillator, .init(level: 0, waveform: .sine, octaveOffset: -1))
        XCTAssertEqual(voice.noiseLevel, 0)
        XCTAssertEqual(voice.amplitudeEnvelope, .init(attackSeconds: 0.05, decaySeconds: 0.2, sustainLevel: 0.8, releaseSeconds: 0.4))
        XCTAssertEqual(voice.filter.kind, .lowPass)
        XCTAssertEqual(voice.filter.cutoffHz, 12_000)
        XCTAssertEqual(voice.filter.resonance, 0.1)
        XCTAssertEqual(voice.glideSeconds, 0)
        XCTAssertEqual(voice.lfo, .init(target: .none, rateHz: 1, depth: 0))
        XCTAssertEqual(voice.delay, .init(isEnabled: false, timeSeconds: 0.25, feedback: 0.2, mix: 0))
        XCTAssertEqual(voice.reverb, .init(isEnabled: false, feedback: 0.8, highPassHz: 80, mix: 0))
        XCTAssertEqual(voice.outputTrimDB, -18)
        XCTAssertEqual(voice.referenceMIDI, 60)
        XCTAssertEqual(voice.auditionChord, [48, 55, 62, 67])
        XCTAssertTrue(result.diagnostics.contains(.init(code: .defaultedValue, field: "attackDuration")))
        XCTAssertTrue(result.diagnostics.contains(.init(code: .unknownDescriptor, field: "uid")))
    }

    func testNonFiniteNegativeAndExtremeInputsProduceFiniteClampedOutput() {
        let source = SynthOnePresetRecord(
            uid: "fixture",
            name: "Unsafe",
            waveform1: .nan,
            waveform2: .infinity,
            vco1Volume: -.infinity,
            vco2Volume: 8,
            vco1Semitone: -Double.greatestFiniteMagnitude,
            vco2Semitone: Double.greatestFiniteMagnitude,
            vco2Detuning: .nan,
            vcoBalance: .infinity,
            attackDuration: -4,
            decayDuration: .infinity,
            sustainLevel: 3,
            releaseDuration: -1,
            glide: 200,
            cutoff: .infinity,
            resonance: 10,
            filterAttack: -2,
            delayFeedback: 12,
            reverbFeedback: 9
        )

        let result = SynthOnePresetAdapter.convert(source)
        let voice = result.voice
        let scalars = [
            voice.oscillator1.wavePosition, voice.oscillator1.level, voice.oscillator1.fineDetuneSemitones,
            voice.oscillator2.wavePosition, voice.oscillator2.level, voice.oscillator2.fineDetuneSemitones,
            voice.oscillatorBalance,
            voice.subOscillator.level, voice.noiseLevel,
            voice.amplitudeEnvelope.attackSeconds, voice.amplitudeEnvelope.decaySeconds,
            voice.amplitudeEnvelope.sustainLevel, voice.amplitudeEnvelope.releaseSeconds,
            voice.filter.cutoffHz, voice.filter.resonance, voice.filter.envelope.attackSeconds,
            voice.filter.envelopeAmount, voice.glideSeconds, voice.lfo.rateHz, voice.lfo.depth,
            voice.delay.timeSeconds, voice.delay.feedback, voice.delay.mix,
            voice.reverb.feedback, voice.reverb.highPassHz, voice.reverb.mix,
            voice.phaser.rateHz, voice.phaser.feedback, voice.phaser.mix, voice.phaser.notchWidthHz,
            voice.autoPan.rateHz, voice.autoPan.depth, voice.autoPan.stereoWidth,
            voice.outputTrimDB,
        ]

        XCTAssertTrue(scalars.allSatisfy(\.isFinite))
        XCTAssertEqual(voice.oscillator1.wavePosition, 0.5)
        XCTAssertEqual(voice.oscillator2.wavePosition, 0.5)
        XCTAssertEqual(voice.oscillator1.level, 0.5)
        XCTAssertEqual(voice.oscillator2.level, 1)
        XCTAssertEqual(voice.oscillatorBalance, 0.5)
        XCTAssertEqual(voice.oscillator1.semitoneOffset, -24)
        XCTAssertEqual(voice.oscillator2.semitoneOffset, 24)
        XCTAssertEqual(voice.amplitudeEnvelope.attackSeconds, 0)
        XCTAssertEqual(voice.amplitudeEnvelope.decaySeconds, 0.2)
        XCTAssertEqual(voice.amplitudeEnvelope.sustainLevel, 1)
        XCTAssertEqual(voice.amplitudeEnvelope.releaseSeconds, 0)
        XCTAssertEqual(voice.glideSeconds, 2)
        XCTAssertEqual(voice.filter.cutoffHz, 12_000)
        XCTAssertEqual(voice.filter.resonance, 0.95)
        XCTAssertEqual(voice.delay.feedback, 0.9)
        XCTAssertEqual(voice.reverb.feedback, 0.95)
        XCTAssertEqual(voice.outputTrimDB, -18)
        XCTAssertTrue(result.diagnostics.contains(.init(code: .nonFiniteValue, field: "waveform1")))
        XCTAssertTrue(result.diagnostics.contains(.init(code: .clampedValue, field: "delayFeedback")))
    }

    func testUnsupportedFamiliesAreIgnoredWithSortedDeterministicDiagnostics() {
        let source = SynthOnePresetRecord(
            uid: "fixture",
            name: "Unsupported",
            isArpMode: 1,
            arpIsSequencer: true,
            isHoldMode: 1,
            frequencyA4: 432,
            tuningName: "Custom",
            modWheelRouting: 2,
            crushFreq: 12_000,
            fmAmount: 0.4,
            oscMixLFO: 0.2,
            compressorMasterRatio: 8,
            delayInputResonance: 0.5
        )

        let first = SynthOnePresetAdapter.convert(source)
        let second = SynthOnePresetAdapter.convert(source)
        let ignoredCodes = Set(first.diagnostics.filter { $0.code.rawValue.hasPrefix("unsupported") }.map(\.code))

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.diagnostics, first.diagnostics.sorted { $0.sortKey < $1.sortKey })
        XCTAssertEqual(
            ignoredCodes,
            [
                .unsupportedArpeggiatorSequencer,
                .unsupportedHold,
                .unsupportedCustomTuning,
                .unsupportedMIDIMapping,
                .unsupportedBitCrush,
                .unsupportedFM,
                .unsupportedModulationRoute,
                .unsupportedCompressor,
                .unsupportedDelayRouting,
            ]
        )
    }

    func testMalformedSupportedFieldIsRejectedByDecoder() {
        let data = Data(#"[{"uid":"fixture","name":"Fixture","cutoff":"loud"}]"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode([SynthOnePresetRecord].self, from: data))
    }

    func testMIDIPitchBendConfigurationIsExplicitlyDiagnosed() {
        let result = SynthOnePresetAdapter.convert(
            .init(
                uid: "fixture",
                name: "MIDI",
                midiBendRange: 2,
                pitchbendMaxSemitones: 12,
                pitchbendMinSemitones: -12
            )
        )

        XCTAssertTrue(result.diagnostics.contains(.init(code: .unsupportedMIDIMapping, field: "pitchBendConfiguration")))
    }

    func testSupportedBalanceLFOShapeAndPhaserWidthArePreserved() {
        let result = SynthOnePresetAdapter.convert(
            .init(
                uid: "fixture",
                name: "Character",
                vcoBalance: 0.75,
                lfoWaveform: 2,
                phaserNotchWidth: 900
            )
        )

        XCTAssertEqual(result.voice.oscillatorBalance, 0.75)
        XCTAssertEqual(result.voice.lfo.waveform, .square)
        XCTAssertEqual(result.voice.phaser.notchWidthHz, 900)
    }

    func testBundledSelectionLoadsOnceInManifestOrderAndConvertsDeterministically() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let first = records.map(SynthOnePresetAdapter.convert)
        let second = records.map(SynthOnePresetAdapter.convert)

        XCTAssertEqual(records.count, 15)
        XCTAssertEqual(records.map(\.uid), DayObjectsInstrumentManifest.defaultDescriptors.compactMap(\.sourceUID))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.voice.referenceMIDI), DayObjectsInstrumentManifest.defaultDescriptors.map(\.referenceMIDI))
        XCTAssertEqual(first.map(\.voice.auditionChord), DayObjectsInstrumentManifest.defaultDescriptors.map(\.auditionChord))
        XCTAssertEqual(first.map(\.voice.outputTrimDB), DayObjectsInstrumentManifest.defaultDescriptors.map(\.outputTrimDB))
    }

    func testAllFifteenConversionsMatchGoldenStableScalarsAndDiagnosticCodes() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let actual = records.map { source -> Golden in
            let result = SynthOnePresetAdapter.convert(source)
            return Golden(
                uid: source.uid,
                wave1: result.voice.oscillator1.wavePosition,
                wave2: result.voice.oscillator2.wavePosition,
                attack: result.voice.amplitudeEnvelope.attackSeconds,
                cutoff: result.voice.filter.cutoffHz,
                lfoTarget: result.voice.lfo.target,
                delayFeedback: result.voice.delay.feedback,
                reverbMix: result.voice.reverb.mix,
                trimDB: result.voice.outputTrimDB,
                diagnosticCodes: Array(Set(result.diagnostics.map { $0.code.rawValue })).sorted()
            )
        }

        XCTAssertEqual(actual, Self.golden)
    }

    private struct Golden: Equatable {
        let uid: String
        let wave1: Double
        let wave2: Double
        let attack: Double
        let cutoff: Double
        let lfoTarget: NormalizedSynthVoice.LFOTarget
        let delayFeedback: Double
        let reverbMix: Double
        let trimDB: Double
        let diagnosticCodes: [String]
    }

    private static let baseCodes = [
        "unsupportedCompressor",
        "unsupportedDelayRouting",
        "unsupportedMIDIMapping",
        "unsupportedSourceGain",
    ]

    private static func codes(_ additional: String...) -> [String] {
        Array(Set(baseCodes + additional)).sorted()
    }

    private static let golden: [Golden] = [
        .init(uid: "39529417-FBC1-41D5-B1D1-0DED9E38F164", wave1: 0.03926701471209526, wave2: 0.946351945400238, attack: 0.7000806331634521, cutoff: 4695.23828125, lfoTarget: .none, delayFeedback: 0.637749969959259, reverbMix: 0.2824999988079071, trimDB: -13.15, diagnosticCodes: codes("unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "96F9F71C-1D6C-41FC-8192-E4B550562357", wave1: 0, wave2: 0, attack: 1.080000877380371, cutoff: 7651.95703125, lfoTarget: .filter, delayFeedback: 0.09325000643730164, reverbMix: 0.3499999940395355, trimDB: -12.40, diagnosticCodes: codes("unsupportedModulationRoute")),
        .init(uid: "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9", wave1: 1, wave2: 1, attack: 1.2451887130737305, cutoff: 17073.958984375, lfoTarget: .pitch, delayFeedback: 0.60974997282028198, reverbMix: 0.23749999701976776, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedBitCrush", "unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D", wave1: 0.66237115859985352, wave2: 0.6682242751121521, attack: 0.0054987501353025436, cutoff: 5152.1552734375, lfoTarget: .filter, delayFeedback: 0.18999950587749481, reverbMix: 0.11000000685453415, trimDB: -13.15, diagnosticCodes: codes("unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "88335303-C675-4D14-907E-2D80823C2BCA", wave1: 0.8092783689498901, wave2: 0.5397196412086487, attack: 0.0005000000237487259, cutoff: 3631.431884765625, lfoTarget: .pitch, delayFeedback: 0.4522499740123749, reverbMix: 0.4124999940395355, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF", wave1: 0, wave2: 1, attack: 0.00050000002374872587, cutoff: 5726.6318359375, lfoTarget: .pitch, delayFeedback: 0.17874999344348907, reverbMix: 0.3775000274181366, trimDB: -13.15, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "C2958050-CDCA-4C64-AF92-3217539CE60A", wave1: 0.32216495275497, wave2: 0, attack: 0.0005000000237487299, cutoff: 3244.8913574219, lfoTarget: .filter, delayFeedback: 0.10000000149012, reverbMix: 0.15000000596046, trimDB: -14.89, diagnosticCodes: codes("unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "4131C811-FBB8-4E15-B238-8986645A62D3", wave1: 1, wave2: 1, attack: 0.00050000002374872587, cutoff: 64, lfoTarget: .filter, delayFeedback: 0, reverbMix: 0, trimDB: -15.92, diagnosticCodes: codes("unsupportedBitCrush", "unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "FA16AF16-3033-485F-A183-4DAAB7025B52", wave1: 0.6391752362251282, wave2: 0.4789719581604004, attack: 0.010497500188648697, cutoff: 7532.7783203125, lfoTarget: .filter, delayFeedback: 0.18324950337409973, reverbMix: 0.3375000059604645, trimDB: -17.08, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "9BDE3DCB-219D-4D70-A067-C1057B557F19", wave1: 0.84278351068496704, wave2: 0.084112152457237244, attack: 0.030492499470710754, cutoff: 2346.652587890625, lfoTarget: .pitch, delayFeedback: 0.53999996185302734, reverbMix: 0.99750000238418579, trimDB: -17.08, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F", wave1: 0.4304123818874359, wave2: 1, attack: 0.31042250990867615, cutoff: 4029.44189453125, lfoTarget: .pitch, delayFeedback: 0.10000000149011612, reverbMix: 0.33500000834465027, trimDB: -14.89, diagnosticCodes: codes("clampedValue")),
        .init(uid: "BB74B6AD-9076-464C-B373-F2E968BBD2BE", wave1: 0, wave2: 0.75, attack: 0.63985252380371094, cutoff: 1114.0987548828125, lfoTarget: .pitch, delayFeedback: 0.50949996709823608, reverbMix: 0.18500000238418579, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "AA903CDB-938B-4FC7-8E01-050DB95EFDE7", wave1: 0, wave2: 0, attack: 0.01000099349767, cutoff: 18_000, lfoTarget: .filter, delayFeedback: 0.76374983787537, reverbMix: 0.14000009000301, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1", wave1: 0, wave2: 1, attack: 0.00050000002374872587, cutoff: 1368.1875, lfoTarget: .pitch, delayFeedback: 0.10000000149011612, reverbMix: 0.17499999701976776, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute")),
        .init(uid: "9F2D32B0-ED71-4127-A4C5-F51209656AF7", wave1: 0.311855673789978, wave2: 0.3317756950855255, attack: 0.17045749723911285, cutoff: 2420.28076171875, lfoTarget: .filter, delayFeedback: 0.49049997329711914, reverbMix: 0.4000000059604645, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
    ]
}
