import XCTest
@testable import Steps4

final class SynthOnePresetAdapterTests: XCTestCase {
    func testMissingValuesUseDocumentedFiniteDefaults() {
        let result = SynthOnePresetAdapter.convert(.init(uid: "fixture", name: "Fixture"))
        let voice = result.voice

        XCTAssertEqual(voice.oscillator1, .init(wavePosition: 0.5, level: 0.5, semitoneOffset: 0, detuneHz: 0))
        XCTAssertEqual(voice.oscillator2, .init(wavePosition: 0.5, level: 0.5, semitoneOffset: 0, detuneHz: 0))
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
            voice.oscillator1.wavePosition, voice.oscillator1.level, voice.oscillator1.detuneHz,
            voice.oscillator2.wavePosition, voice.oscillator2.level, voice.oscillator2.detuneHz,
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

    func testSupportedBalanceAndPhaserWidthArePreserved() {
        let result = SynthOnePresetAdapter.convert(
            .init(
                uid: "fixture",
                name: "Character",
                vcoBalance: 0.75,
                phaserNotchWidth: 900
            )
        )

        XCTAssertEqual(result.voice.oscillatorBalance, 0.75)
        XCTAssertEqual(result.voice.phaser.notchWidthHz, 900)
    }

    func testPinnedWaveformIndicesMapToExactSynthOneShapes() {
        let fixtures: [(Int, NormalizedSynthVoice.LFOWaveform)] = [
            (0, .sine),
            (1, .square),
            (2, .sawtooth),
            (3, .reverseSawtooth),
        ]

        for (sourceWaveform, expected) in fixtures {
            let result = SynthOnePresetAdapter.convert(
                .init(
                    uid: "waveform-\(sourceWaveform)",
                    name: "Waveform",
                    lfoAmplitude: 1,
                    lfoRate: 1,
                    lfoWaveform: sourceWaveform,
                    pitchLFO: 1
                )
            )

            XCTAssertEqual(result.voice.lfo.waveform, expected, "source index \(sourceWaveform)")
        }
    }

    func testVCO2DetuningPreservesHertzAndClampsPinnedRange() {
        let fixtures: [(source: Double, expectedHz: Double, isClamped: Bool)] = [
            (-5, -4, true),
            (-4, -4, false),
            (0, 0, false),
            (4, 4, false),
            (5, 4, true),
        ]

        for fixture in fixtures {
            let result = SynthOnePresetAdapter.convert(
                .init(uid: "detune-\(fixture.source)", name: "Detune", vco2Detuning: fixture.source)
            )

            XCTAssertEqual(result.voice.oscillator1.detuneHz, 0)
            XCTAssertEqual(result.voice.oscillator2.detuneHz, fixture.expectedHz)
            XCTAssertEqual(
                result.diagnostics.contains(.init(code: .clampedValue, field: "vco2Detuning")),
                fixture.isClamped
            )
        }
    }

    func testEachPrimaryDestinationUsingSelectorOneMapsLFOOne() {
        for (source, target) in primaryRouteFixtures(selector: 1) {
            let result = SynthOnePresetAdapter.convert(source)

            XCTAssertEqual(
                result.voice.lfo,
                .init(target: target, rateHz: 2, depth: 0.25, waveform: .sine),
                source.uid
            )
        }
    }

    func testEachPrimaryDestinationUsingSelectorTwoMapsLFOTwo() {
        for (source, target) in primaryRouteFixtures(selector: 2) {
            let result = SynthOnePresetAdapter.convert(source)

            XCTAssertEqual(
                result.voice.lfo,
                .init(target: target, rateHz: 7, depth: 0.75, waveform: .sine),
                source.uid
            )
        }
    }

    func testEachPrimaryDestinationUsingCombinedSelectorIsDiagnosedAndNotAttached() {
        let expectedFields = ["pitchLFO.combined", "cutoffLFO.combined", "tremoloLFO.combined"]

        for ((source, _), field) in zip(primaryRouteFixtures(selector: 3), expectedFields) {
            let result = SynthOnePresetAdapter.convert(source)

            XCTAssertEqual(result.voice.lfo, .init(target: .none, rateHz: 1, depth: 0, waveform: .sine), source.uid)
            XCTAssertTrue(
                result.diagnostics.contains(.init(code: .unsupportedModulationRoute, field: field)),
                source.uid
            )
        }
    }

    func testBundledSelectorTwoAndCombinedRoutesUsePinnedSourceSemantics() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let byUID = Dictionary(uniqueKeysWithValues: records.map { ($0.uid, $0) })
        let selectorTwo = try XCTUnwrap(byUID["9BDE3DCB-219D-4D70-A067-C1057B557F19"])
        let combined = try XCTUnwrap(byUID["88335303-C675-4D14-907E-2D80823C2BCA"])

        XCTAssertEqual(
            SynthOnePresetAdapter.convert(selectorTwo).voice.lfo,
            .init(target: .pitch, rateHz: 0.118055559694767, depth: 0.31000000238418579, waveform: .sine)
        )

        let combinedResult = SynthOnePresetAdapter.convert(combined)
        XCTAssertEqual(combinedResult.voice.lfo, .init(target: .none, rateHz: 1, depth: 0, waveform: .sine))
        XCTAssertTrue(
            combinedResult.diagnostics.contains(
                .init(code: .unsupportedModulationRoute, field: "pitchLFO.combined")
            )
        )
    }

    func testBundledSelectionLoadsOnceInManifestOrderAndConvertsDeterministically() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let first = records.map(SynthOnePresetAdapter.convert)
        let second = records.map(SynthOnePresetAdapter.convert)

        XCTAssertEqual(records.count, 16)
        XCTAssertEqual(records.map(\.uid), DayObjectsInstrumentManifest.defaultDescriptors.compactMap(\.sourceUID))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.voice.referenceMIDI), DayObjectsInstrumentManifest.defaultDescriptors.map(\.referenceMIDI))
        XCTAssertEqual(first.map(\.voice.auditionChord), DayObjectsInstrumentManifest.defaultDescriptors.map(\.auditionChord))
        XCTAssertEqual(first.map(\.voice.outputTrimDB), DayObjectsInstrumentManifest.defaultDescriptors.map(\.outputTrimDB))
    }

    func testAllSixteenConversionsMatchGoldenStableScalarsAndDiagnosticCodes() throws {
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: Bundle(for: type(of: self)))
        let actual = records.map { source -> Golden in
            let result = SynthOnePresetAdapter.convert(source)
            return Golden(
                uid: source.uid,
                wave1: result.voice.oscillator1.wavePosition,
                wave2: result.voice.oscillator2.wavePosition,
                oscillator2DetuneHz: result.voice.oscillator2.detuneHz,
                attack: result.voice.amplitudeEnvelope.attackSeconds,
                cutoff: result.voice.filter.cutoffHz,
                lfoTarget: result.voice.lfo.target,
                lfoRateHz: result.voice.lfo.rateHz,
                lfoDepth: result.voice.lfo.depth,
                lfoWaveform: result.voice.lfo.waveform,
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
        let oscillator2DetuneHz: Double
        let attack: Double
        let cutoff: Double
        let lfoTarget: NormalizedSynthVoice.LFOTarget
        let lfoRateHz: Double
        let lfoDepth: Double
        let lfoWaveform: NormalizedSynthVoice.LFOWaveform
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

    private func primaryRouteFixtures(
        selector: Double
    ) -> [(SynthOnePresetRecord, NormalizedSynthVoice.LFOTarget)] {
        let common: (String, Double?, Double?, Double?) -> SynthOnePresetRecord = { uid, pitch, filter, amplitude in
            SynthOnePresetRecord(
                uid: uid,
                name: uid,
                lfoAmplitude: 0.25,
                lfoRate: 2,
                lfoWaveform: 0,
                pitchLFO: pitch,
                cutoffLFO: filter,
                tremoloLFO: amplitude,
                lfo2Amplitude: 0.75,
                lfo2Rate: 7,
                lfo2Waveform: 0
            )
        }

        return [
            (common("pitch", selector, nil, nil), .pitch),
            (common("filter", nil, selector, nil), .filter),
            (common("amplitude", nil, nil, selector), .amplitude),
        ]
    }

    private static let golden: [Golden] = [
        .init(uid: "39529417-FBC1-41D5-B1D1-0DED9E38F164", wave1: 0.03926701471209526, wave2: 0.946351945400238, oscillator2DetuneHz: 1.9600000381469727, attack: 0.7000806331634521, cutoff: 4695.23828125, lfoTarget: .none, lfoRateHz: 1, lfoDepth: 0, lfoWaveform: .sine, delayFeedback: 0.637749969959259, reverbMix: 0.2824999988079071, trimDB: -13.15, diagnosticCodes: codes("unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "96F9F71C-1D6C-41FC-8192-E4B550562357", wave1: 0, wave2: 0, oscillator2DetuneHz: 0.5000000596046448, attack: 1.080000877380371, cutoff: 7651.95703125, lfoTarget: .filter, lfoRateHz: 0.08333333581686017, lfoDepth: 0.8299999833106995, lfoWaveform: .sine, delayFeedback: 0.09325000643730164, reverbMix: 0.3499999940395355, trimDB: -12.40, diagnosticCodes: codes("unsupportedModulationRoute")),
        .init(uid: "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9", wave1: 1, wave2: 1, oscillator2DetuneHz: 2.940000057220459, attack: 1.2451887130737305, cutoff: 17073.958984375, lfoTarget: .none, lfoRateHz: 1, lfoDepth: 0, lfoWaveform: .sine, delayFeedback: 0.60974997282028198, reverbMix: 0.23749999701976776, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedBitCrush", "unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D", wave1: 0.66237115859985352, wave2: 0.6682242751121521, oscillator2DetuneHz: 0.059999998658895493, attack: 0.0054987501353025436, cutoff: 5152.1552734375, lfoTarget: .filter, lfoRateHz: 0.1388888955116272, lfoDepth: 0.072499997913837433, lfoWaveform: .sine, delayFeedback: 0.18999950587749481, reverbMix: 0.11000000685453415, trimDB: -13.15, diagnosticCodes: codes("unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "88335303-C675-4D14-907E-2D80823C2BCA", wave1: 0.8092783689498901, wave2: 0.5397196412086487, oscillator2DetuneHz: 0.25999999046325684, attack: 0.0005000000237487259, cutoff: 3631.431884765625, lfoTarget: .none, lfoRateHz: 1, lfoDepth: 0, lfoWaveform: .sine, delayFeedback: 0.4522499740123749, reverbMix: 0.4124999940395355, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF", wave1: 0, wave2: 1, oscillator2DetuneHz: 2.0399999618530273, attack: 0.00050000002374872587, cutoff: 5726.6318359375, lfoTarget: .pitch, lfoRateHz: 2, lfoDepth: 0.1550000011920929, lfoWaveform: .sine, delayFeedback: 0.17874999344348907, reverbMix: 0.3775000274181366, trimDB: -13.15, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute")),
        .init(uid: "C2958050-CDCA-4C64-AF92-3217539CE60A", wave1: 0.32216495275497, wave2: 0, oscillator2DetuneHz: 0.89999997615814, attack: 0.0005000000237487299, cutoff: 3244.8913574219, lfoTarget: .filter, lfoRateHz: 0.5, lfoDepth: 0, lfoWaveform: .sine, delayFeedback: 0.10000000149012, reverbMix: 0.15000000596046, trimDB: -14.89, diagnosticCodes: codes("unsupportedPerformanceMode")),
        .init(uid: "E2D8B458-C727-4388-A0EA-28802B605796", wave1: 0.5077319741249084, wave2: 0.3528037369251251, oscillator2DetuneHz: -0.000000002980233393401477, attack: 0.0005000000237487259, cutoff: 2912.136474609375, lfoTarget: .filter, lfoRateHz: 0.25, lfoDepth: 0.7099999785423279, lfoWaveform: .sine, delayFeedback: 0.1822499930858612, reverbMix: 0.5, trimDB: -18, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "4131C811-FBB8-4E15-B238-8986645A62D3", wave1: 1, wave2: 1, oscillator2DetuneHz: 0.040000010281801224, attack: 0.00050000002374872587, cutoff: 64, lfoTarget: .filter, lfoRateHz: 0.098958335816860199, lfoDepth: 0.74000000953674316, lfoWaveform: .sine, delayFeedback: 0, reverbMix: 0, trimDB: -15.92, diagnosticCodes: codes("unsupportedBitCrush", "unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "FA16AF16-3033-485F-A183-4DAAB7025B52", wave1: 0.6391752362251282, wave2: 0.4789719581604004, oscillator2DetuneHz: -2.380000352859497, attack: 0.010497500188648697, cutoff: 7532.7783203125, lfoTarget: .filter, lfoRateHz: 0.06966245919466019, lfoDepth: 0.6549996137619019, lfoWaveform: .sine, delayFeedback: 0.18324950337409973, reverbMix: 0.3375000059604645, trimDB: -17.08, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "9BDE3DCB-219D-4D70-A067-C1057B557F19", wave1: 0.84278351068496704, wave2: 0.084112152457237244, oscillator2DetuneHz: -0.059999998658895493, attack: 0.030492499470710754, cutoff: 2346.652587890625, lfoTarget: .pitch, lfoRateHz: 0.118055559694767, lfoDepth: 0.31000000238418579, lfoWaveform: .sine, delayFeedback: 0.53999996185302734, reverbMix: 0.99750000238418579, trimDB: -17.08, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F", wave1: 0.4304123818874359, wave2: 1, oscillator2DetuneHz: -1.440000057220459, attack: 0.31042250990867615, cutoff: 4029.44189453125, lfoTarget: .pitch, lfoRateHz: 5.6154279708862305, lfoDepth: 0.2775000035762787, lfoWaveform: .sine, delayFeedback: 0.10000000149011612, reverbMix: 0.33500000834465027, trimDB: -14.89, diagnosticCodes: codes("clampedValue")),
        .init(uid: "BB74B6AD-9076-464C-B373-F2E968BBD2BE", wave1: 0, wave2: 0.75, oscillator2DetuneHz: 1, attack: 0.63985252380371094, cutoff: 1114.0987548828125, lfoTarget: .pitch, lfoRateHz: 5.0664143562316895, lfoDepth: 0.49000000953674316, lfoWaveform: .sine, delayFeedback: 0.50949996709823608, reverbMix: 0.18500000238418579, trimDB: -14.89, diagnosticCodes: codes("unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
        .init(uid: "AA903CDB-938B-4FC7-8E01-050DB95EFDE7", wave1: 0, wave2: 0, oscillator2DetuneHz: 0.25999996066093, attack: 0.01000099349767, cutoff: 18_000, lfoTarget: .filter, lfoRateHz: 0.0625, lfoDepth: 0, lfoWaveform: .sine, delayFeedback: 0.76374983787537, reverbMix: 0.14000009000301, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedPerformanceMode")),
        .init(uid: "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1", wave1: 0, wave2: 1, oscillator2DetuneHz: 0, attack: 0.00050000002374872587, cutoff: 1368.1875, lfoTarget: .pitch, lfoRateHz: 3.7052958011627197, lfoDepth: 0.23999999463558197, lfoWaveform: .sine, delayFeedback: 0.10000000149011612, reverbMix: 0.17499999701976776, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedMIDIMapping", "unsupportedModulationRoute")),
        .init(uid: "9F2D32B0-ED71-4127-A4C5-F51209656AF7", wave1: 0.311855673789978, wave2: 0.3317756950855255, oscillator2DetuneHz: -0.7400000095367432, attack: 0.17045749723911285, cutoff: 2420.28076171875, lfoTarget: .filter, lfoRateHz: 1, lfoDepth: 0.1949996054172516, lfoWaveform: .sine, delayFeedback: 0.49049997329711914, reverbMix: 0.4000000059604645, trimDB: -14.89, diagnosticCodes: codes("clampedValue", "unsupportedFM", "unsupportedModulationRoute", "unsupportedPerformanceMode")),
    ]
}
