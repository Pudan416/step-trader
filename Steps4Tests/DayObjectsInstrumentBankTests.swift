import Foundation
import AudioKit
import AudioKitEX
import AVFoundation
import SoundpipeAudioKit
import XCTest
@testable import Steps4

private let testHappeningEffects = HappeningEffectCommand(
    filterCutoffHz: 8_000,
    delayMix: 0,
    delayFeedback: 0,
    reverbMix: 0
)

private func renderedPeak(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let channels = buffer.floatChannelData else { return 0 }
    var peak = 0.0
    for channel in 0..<Int(buffer.format.channelCount) {
        for frame in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(Double(channels[channel][frame])))
        }
    }
    return peak
}

private func renderedRMS(_ buffer: AVAudioPCMBuffer) -> Double {
    guard let channels = buffer.floatChannelData else { return 0 }
    var squared = 0.0
    let sampleCount = Int(buffer.frameLength) * Int(buffer.format.channelCount)
    guard sampleCount > 0 else { return 0 }
    for channel in 0..<Int(buffer.format.channelCount) {
        for frame in 0..<Int(buffer.frameLength) {
            squared += Double(channels[channel][frame] * channels[channel][frame])
        }
    }
    return sqrt(squared / Double(sampleCount))
}

private func channelDifferenceRMS(_ buffer: AVAudioPCMBuffer) -> Double {
    guard buffer.format.channelCount >= 2,
          let left = buffer.floatChannelData?[0],
          let right = buffer.floatChannelData?[1],
          buffer.frameLength > 0 else { return 0 }
    let squared = (0..<Int(buffer.frameLength)).reduce(0.0) { result, frame in
        let difference = Double(left[frame] - right[frame])
        return result + difference * difference
    }
    return sqrt(squared / Double(buffer.frameLength))
}

@MainActor
private func renderAntiPhaseBassProbe(frequency: Double) -> AVAudioPCMBuffer {
    let sampleRate = 48_000.0
    let frameCount = AVAudioFrameCount(sampleRate * 0.2)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    for frame in 0..<Int(frameCount) {
        let sample = Float(sin(2 * Double.pi * frequency * Double(frame) / sampleRate) * 0.5)
        buffer.floatChannelData?[0][frame] = sample
        buffer.floatChannelData?[1][frame] = -sample
    }
    let player = AudioPlayer()
    player.buffer = buffer
    let highPass = HighPassFilter(player, cutoffFrequency: 27, resonance: 0)
    let lowPass = LowPassFilter(highPass, cutoffFrequency: 140, resonance: 0)
    let mono = Fader(lowPass, gain: 1)
    let highBand = HighPassFilter(highPass, cutoffFrequency: 140, resonance: 0)
    let highBandSlope = HighPassFilter(highBand, cutoffFrequency: 140, resonance: 0)
    let output = Mixer([mono, highBandSlope])
    let engine = AudioEngine()
    engine.output = output
    _ = engine.startTest(totalDuration: 0.2)
    mono.$mixToMono.parameter.value = 1
    player.play()
    return engine.render(duration: 0.2)
}

@MainActor
final class DayObjectsInstrumentBankTests: XCTestCase {
    func testPersistentMasterUsesRealRatioGlueWithBoundedRenderedReduction() {
        func measure(amplitude: AUValue) -> Double {
            let happenings = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
            let graph = DayObjectsPersistentMasterGraph(happenings: happenings)
            let sources = (0..<5).map { _ in
                Oscillator(waveform: Table(.sine), frequency: 440, amplitude: amplitude)
            }
            sources.forEach { graph.masterMixer.addInput($0) }
            let engine = AudioEngine()
            engine.output = graph.glueCompressor
            _ = engine.startTest(totalDuration: 0.6)
            graph.startMeters()
            sources.forEach { $0.start() }
            return Swift.max(renderedRMS(engine.render(duration: 0.6)), .leastNonzeroMagnitude)
        }

        let quiet = measure(amplitude: 0.02)
        let loud = measure(amplitude: 0.20)
        let measuredReductionDB = 20 * log10(10 / (loud / quiet))

        XCTAssertGreaterThan(measuredReductionDB, 0.25)
        XCTAssertLessThanOrEqual(measuredReductionDB, 1.55)

        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try? pair.prepare(configuration: smallPlaybackPairConfiguration())
        XCTAssertEqual(
            pair.bankA.metrics.engineTopology.acceptedParameterValues["master.glue.ratio"] ?? .nan,
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            pair.bankA.metrics.engineTopology.acceptedParameterValues["master.glue.thresholdDB"] ?? .nan,
            -4.5,
            accuracy: 0.001
        )
    }

    func testRealMasterGraphRetainsPhysicalConnectionsAndEveryTapCapturesAfterRestart() throws {
        let happenings = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        let graph = DayObjectsPersistentMasterGraph(happenings: happenings)
        let sources = DayObjectsRoleBus.allCases.enumerated().map { index, role in
            (role, Oscillator(
                waveform: Table(.sine),
                frequency: AUValue(180 + index * 70),
                amplitude: 0.35
            ))
        }
        for (role, source) in sources { graph.bus(for: role).addInput(source) }
        let engine = AudioEngine()
        engine.output = graph.finalOutput
        graph.prepareMeters()
        _ = engine.startTest(totalDuration: 0.5)
        graph.startMeters()
        sources.forEach { $0.1.start() }
        _ = engine.render(duration: 0.25)

        let attachedBefore = Set(engine.avEngine.attachedNodes.map(ObjectIdentifier.init))
        let requiredNodes = Set(graph.fixedNodes.map { ObjectIdentifier($0.avAudioNode) })
        XCTAssertTrue(requiredNodes.isSubset(of: attachedBefore))
        for destination in graph.fixedNodes {
            for source in destination.connections {
                let points = engine.avEngine.outputConnectionPoints(for: source.avAudioNode, outputBus: 0)
                XCTAssertTrue(points.contains { $0.node === destination.avAudioNode })
            }
        }
        XCTAssertTrue(graph.meterTapCapturedScalarSampleCounts.values.allSatisfy { $0 > 0 })

        engine.stop()
        graph.stopMeters()
        for index in 0..<100 {
            graph.applyMix(DayObjectsMixState.testingFiveRoleMix(masterDecibels: index.isMultiple(of: 2) ? -6 : -12))
        }
        graph.startMeters()
        try requireLiveAudioOutput()
        try engine.start()
        sources.forEach { $0.1.start() }
        _ = engine.render(duration: 0.25)

        XCTAssertEqual(Set(engine.avEngine.attachedNodes.map(ObjectIdentifier.init)), attachedBefore)
        XCTAssertTrue(graph.meterTapCapturedScalarSampleCounts.values.allSatisfy { $0 > 0 })
        let restarted = graph.meterSnapshots(graphs: [], happeningVoiceCount: 0, now: 1)
        for role in DayObjectsRoleBus.allCases {
            XCTAssertGreaterThan(restarted.0.metrics(for: role).peakDBFS, -120)
        }
        XCTAssertGreaterThan(restarted.1.peakDBFS, -120)
        sources.forEach { $0.1.stop() }
        graph.stopMeters()
        engine.stop()
    }

    func testProductionMasterMeterEstimatesOverCeilingReductionThenExpiresAndResets() {
        let happenings = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        let graph = DayObjectsPersistentMasterGraph(happenings: happenings)
        let sources = (0..<5).map { _ in
            Oscillator(waveform: Table(.sine), frequency: 330, amplitude: 1)
        }
        sources.forEach { graph.masterMixer.addInput($0) }
        let engine = AudioEngine()
        engine.output = graph.finalOutput
        graph.prepareMeters()
        _ = engine.startTest(totalDuration: 1.5)
        graph.startMeters()
        sources.forEach { $0.start() }
        _ = engine.render(duration: 0.25)

        let driven = graph.meterSnapshots(graphs: [], happeningVoiceCount: 0, now: 1).1
        XCTAssertGreaterThan(
            driven.estimatedLimiterReductionDB,
            0.1,
            "\(graph.limiterMeterTimelineDiagnostics)"
        )

        sources.forEach { $0.stop() }
        _ = engine.render(duration: 0.9)
        let expired = graph.meterSnapshots(graphs: [], happeningVoiceCount: 0, now: 2).1
        XCTAssertEqual(expired.estimatedLimiterReductionDB, 0, accuracy: 0.01)

        graph.stopMeters()
        let reset = graph.meterSnapshots(graphs: [], happeningVoiceCount: 0, now: 3).1
        XCTAssertEqual(reset.estimatedLimiterReductionDB, 0, accuracy: 1e-12)
        XCTAssertEqual(reset.peakDBFS, -120)
    }

    func testPairedMetricsExposeAppliedMasterTrimInsteadOfDefaultConstant() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: smallPlaybackPairConfiguration())

        pair.bankA.applyMix(.testingFiveRoleMix(masterDecibels: -12))

        XCTAssertEqual(pair.metrics.sharedMasterTrimDecibels, -12, accuracy: 0.001)
    }

    func testDiagnosticMuteHardZerosDirectAndReturnPathsWhileSoloKeepsConfiguredSpace() {
        let graph = DayObjectsPersistentMasterGraph(
            happenings: DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        )
        let muted = DayObjectsRoleBusMixParameters(
            directTargetDecibels: -60,
            sendLevel: 0.4,
            decay: 0.5
        )
        let mutedLead = DayObjectsRoleBusMixParameters(
            directTargetDecibels: -60,
            sendLevel: 0.4,
            decay: 0.5,
            secondarySendLevel: 0.3,
            secondaryDecay: 0.4
        )
        let solo = DayObjectsRoleBusMixParameters(
            directTargetDecibels: 0,
            sendLevel: 0.4,
            decay: 0.5
        )

        graph.applyMix(.init(
            buses: .init(
                rhythm: muted,
                bass: muted,
                harmony: solo,
                happenings: muted,
                lead: mutedLead
            ),
            harmonyPerVoiceTargetDecibels: 0,
            happeningPerVoiceTargetDecibels: -60,
            masterTargetDecibelsBeforeLimiter: -6,
            harmonyDuckingDecibels: 0,
            rampDurationSeconds: 0.25
        ))

        XCTAssertEqual(graph.rhythmDirect.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.bassDirect.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.happeningsDirect.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.leadDirect.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.rhythmSend.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.bassSend.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.happeningsSend.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.leadSend.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(graph.leadDelaySend.$leftGain.parameter.value, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(graph.harmonyDirect.$leftGain.parameter.value, 0)
        XCTAssertGreaterThan(graph.harmonySend.$leftGain.parameter.value, 0)
    }

    func testMeasuredRoleCalibrationScalesEveryAudiblePathWithoutMovingMasterTrim() {
        XCTAssertEqual(DayObjectsPersistentMasterGraph.rhythmPathCalibrationDecibels, 10.40)
        XCTAssertEqual(DayObjectsPersistentMasterGraph.bassPathCalibrationDecibels, 10.40)
        XCTAssertEqual(DayObjectsPersistentMasterGraph.harmonyPathCalibrationDecibels, 10.40)
        XCTAssertEqual(DayObjectsPersistentMasterGraph.happeningsPathCalibrationDecibels, 10.40)
        XCTAssertEqual(DayObjectsPersistentMasterGraph.leadPathCalibrationDecibels, 10.40)
        XCTAssertEqual(DayObjectsPersistentMasterGraph.limiterCeilingDBFS, -1.35)

        let graph = DayObjectsPersistentMasterGraph(
            happenings: DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        )
        let standard = DayObjectsRoleBusMixParameters(
            directTargetDecibels: 0,
            sendLevel: 0.1,
            decay: 0.5,
            secondarySendLevel: 0.1,
            secondaryDecay: 0.4
        )

        graph.applyMix(.init(
            buses: .init(
                rhythm: standard,
                bass: standard,
                harmony: standard,
                happenings: standard,
                lead: standard
            ),
            harmonyPerVoiceTargetDecibels: 0,
            happeningPerVoiceTargetDecibels: 0,
            masterTargetDecibelsBeforeLimiter: -6,
            harmonyDuckingDecibels: 0,
            rampDurationSeconds: 0
        ))

        let roleGain = AUValue(pow(10, 10.40 / 20))
        for direct in [
            graph.rhythmDirect, graph.bassDirect, graph.harmonyDirect,
            graph.happeningsDirect, graph.leadDirect,
        ] {
            XCTAssertEqual(direct.$leftGain.parameter.value, roleGain, accuracy: 0.000_01)
        }
        XCTAssertEqual(graph.rhythmSend.$leftGain.parameter.value, AUValue(0.1 * 8) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.bassSend.$leftGain.parameter.value, AUValue(0.1) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.harmonySend.$leftGain.parameter.value, AUValue(0.1 * 2) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.happeningsSend.$leftGain.parameter.value, AUValue(0.1 * 3.4) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.leadSend.$leftGain.parameter.value, AUValue(0.1) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.leadDelaySend.$leftGain.parameter.value, AUValue(0.1) * roleGain, accuracy: 0.000_01)
        XCTAssertEqual(graph.actualMasterTrimDecibels, -6, accuracy: 0.000_01)
        XCTAssertEqual(graph.finalOutput.linearGain, pow(10, -1.35 / 20), accuracy: 0.000_01)
    }

    func testRenderedLeadProcessorSoftensUpperMidMoreThanLowBand() {
        func ratio(at frequency: AUValue) -> Double {
            func render(processed: Bool) -> Double {
                let source = Oscillator(waveform: Table(.sine), frequency: frequency, amplitude: 0.8)
                let output: Node
                if processed {
                    let notch = PeakingParametricEqualizerFilter(source, centerFrequency: 3_200, gain: -5, q: 1.1)
                    let band = BandPassFilter(source, centerFrequency: 3_200, bandwidth: 1_900)
                    let dynamics = DynamicsProcessor(
                        band, threshold: -18, headRoom: 3,
                        expansionRatio: 1, expansionThreshold: 1,
                        attackTime: 0.008, releaseTime: 0.09, masterGain: 0
                    )
                    output = Mixer([notch, Fader(dynamics, gain: 0.42)])
                } else {
                    output = source
                }
                let engine = AudioEngine()
                engine.output = output
                _ = engine.startTest(totalDuration: 0.2)
                source.start()
                return renderedRMS(engine.render(duration: 0.2))
            }
            return render(processed: true) / max(render(processed: false), .leastNonzeroMagnitude)
        }

        XCTAssertLessThan(ratio(at: 3_200), ratio(at: 500) - 0.08)
    }

    func testRenderedBassCrossoverMakesLowBandMonoWithoutCollapsingUpperBand() {
        let low = renderAntiPhaseBassProbe(frequency: 100)
        let upper = renderAntiPhaseBassProbe(frequency: 1_000)

        XCTAssertLessThan(channelDifferenceRMS(low), channelDifferenceRMS(upper) * 0.4)
        XCTAssertGreaterThan(channelDifferenceRMS(upper), 0.05)
    }

    func testRenderedMasterOutputEnforcesMinusOneDecibelCeiling() {
        let oscillators = (0..<4).map { _ in
            Oscillator(waveform: Table(.sine), frequency: 440, amplitude: 1)
        }
        let limiter = PeakLimiter(Mixer(oscillators), attackTime: 0.001, decayTime: 0.02, preGain: 0)
        let output = DayObjectsMasterOutputGainNode(input: limiter, decibels: -1)
        let engine = AudioEngine()
        engine.output = output
        output.applyConfiguredGain()
        _ = engine.startTest(totalDuration: 0.25)
        oscillators.forEach { $0.start() }

        let rendered = engine.render(duration: 0.25)
        let peak = renderedPeak(rendered)

        XCTAssertGreaterThan(peak, 0.1)
        XCTAssertLessThanOrEqual(peak, pow(10, -1.0 / 20) + 0.002)
    }

    func testRenderedDefaultMasterAuditionIsNonSilentAndStartsAtSixDecibelsOfPreLimiterHeadroom() {
        let source = Oscillator(waveform: Table(.sine), frequency: 330, amplitude: 1)
        let saturation = TanhDistortion(
            source, pregain: 1.12, postgain: 0.94,
            positiveShapeParameter: 0, negativeShapeParameter: 0, dryWetMix: 0.10
        )
        let trim = Fader(saturation, gain: AUValue(pow(10, -6.0 / 20)))
        let limiter = PeakLimiter(trim, attackTime: 0.012, decayTime: 0.024, preGain: 0)
        let output = DayObjectsMasterOutputGainNode(input: limiter, decibels: -1)
        let engine = AudioEngine()
        engine.output = output
        output.applyConfiguredGain()
        _ = engine.startTest(totalDuration: 0.25)
        saturation.$pregain.parameter.value = 1.12
        saturation.$postgain.parameter.value = 0.94
        saturation.$positiveShapeParameter.parameter.value = 0
        saturation.$negativeShapeParameter.parameter.value = 0
        saturation.$dryWetMix.parameter.value = 0.10
        trim.$leftGain.parameter.value = AUValue(pow(10, -6.0 / 20))
        trim.$rightGain.parameter.value = AUValue(pow(10, -6.0 / 20))
        source.start()

        let rendered = engine.render(duration: 0.25)
        let peak = renderedPeak(rendered)

        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThan(peak, pow(10, -6.0 / 20))
    }

    func testWorldRecyclePreservesNewerSchedulerAndManualSharedHappeningsAfterExactOldCleanup() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        let oldWorld = PlaybackWorldBank(instrumentBank: pair.bankA)
        let newWorld = PlaybackWorldBank(instrumentBank: pair.bankB)
        try oldWorld.prepare()
        try newWorld.prepare()
        let tonalWorld = lifecycleWorld()
        let chord = try XCTUnwrap(tonalWorld.progression.first)
        let oldScheduler = HappeningScheduler(worldBank: oldWorld)
        let newScheduler = HappeningScheduler(worldBank: newWorld)
        try oldScheduler.configure(plans: [], tonalWorld: tonalWorld, remixSeed: 1)
        try newScheduler.configure(plans: [], tonalWorld: tonalWorld, remixSeed: 2)
        try oldScheduler.start()
        try newScheduler.start()

        let oldPlan = lifecycleHappeningPlan(id: "old", recipeRawValue: 1)
        let newPlan = lifecycleHappeningPlan(id: "new", recipeRawValue: 2)
        try oldScheduler.add(oldPlan, currentChord: chord, playBirth: true)
        try newScheduler.add(newPlan, currentChord: chord, playBirth: true)

        let pool = oldWorld.happenings
        XCTAssertTrue(pool === newWorld.happenings)
        let manualRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID(3)))
        let manualSound = HappeningPitchResolver.resolve(
            recipe: manualRecipe,
            chord: chord,
            tonalWorld: tonalWorld
        )
        let manualHandle = try pool.play(
            manualSound,
            gain: 1,
            priority: .manualAudition,
            effects: lifecycleEffects(for: manualRecipe)
        )
        XCTAssertEqual(pool.metrics.activeVoiceCount, 3)

        oldScheduler.remove(id: oldPlan.happeningID)
        let survivingEffects = pool.metrics.effects
        XCTAssertEqual(oldScheduler.metrics.activeVoiceCount, 0)
        XCTAssertEqual(newScheduler.metrics.activeVoiceCount, 1)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)

        oldWorld.recycleAfterTailsDrain()

        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
        XCTAssertEqual(pool.metrics.effects, survivingEffects)
        XCTAssertEqual(newScheduler.metrics.activeVoiceCount, 1)
        pool.update(manualHandle, gain: 0.5, playbackRate: manualSound.playbackRate)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
    }

    func testRepeatedWorldRecycleKeepsSharedPlayersBuffersAndLiveEffectAggregateStable() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        let worlds = [
            PlaybackWorldBank(instrumentBank: pair.bankA),
            PlaybackWorldBank(instrumentBank: pair.bankB),
        ]
        try worlds.forEach { try $0.prepare() }
        let pool = worlds[0].happenings
        let playerIdentities = pool.metrics.fixedPlayerIdentities
        let bufferIdentities = pool.metrics.decodedBufferIdentities
        XCTAssertEqual(bufferIdentities.count, 102)

        for cycle in 0..<8 {
            let firstRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID((cycle % 10) + 1)))
            let secondRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID(((cycle + 1) % 10) + 1)))
            let firstSound = lifecycleResolvedSound(recipe: firstRecipe)
            let secondSound = lifecycleResolvedSound(recipe: secondRecipe)
            let first = try pool.play(firstSound, gain: 1, priority: .birth, effects: lifecycleEffects(for: firstRecipe))
            let second = try pool.play(secondSound, gain: 1, priority: .manualAudition, effects: lifecycleEffects(for: secondRecipe))
            pool.stop(first)
            let survivingEffects = pool.metrics.effects

            worlds[cycle % 2].recycleAfterTailsDrain()

            XCTAssertEqual(pool.metrics.activeVoiceCount, 1, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.effects, survivingEffects, "cycle \(cycle)")
            pool.stop(second)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.fixedPlayerIdentities, playerIdentities, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.decodedBufferIdentities, bufferIdentities, "cycle \(cycle)")
        }
    }

    func testPlaybackPairStopClearsAllSharedHappeningHandlesAndEffectContributions() throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        try pair.start()
        let pool = pair.bankA.happenings
        let baselineEffects = pool.metrics.effects
        let recipes = Array(HappeningSoundCatalog.recipes.prefix(4))

        for recipe in recipes {
            _ = try pool.play(
                lifecycleResolvedSound(recipe: recipe),
                gain: 1,
                priority: .manualAudition,
                effects: lifecycleEffects(for: recipe)
            )
        }
        XCTAssertEqual(pool.metrics.activeVoiceCount, 4)
        XCTAssertNotEqual(pool.metrics.effects, baselineEffects)

        pair.stop()

        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
        XCTAssertEqual(pool.metrics.effects, baselineEffects)
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testPlaybackWorldReplacesTheTonalHappeningPoolWithFourSamplePlayers() throws {
        let configuration = PlaybackWorldBankConfiguration.playbackWorld

        XCTAssertEqual(configuration.tonalPools.map(\.capacity).reduce(0, +), 9)
        XCTAssertEqual(configuration.pianoVoiceCount, 2)
        XCTAssertEqual(configuration.drumOverlapCounts.values.reduce(0, +), 10)
        XCTAssertEqual(PlaybackWorldBankConfiguration.PoolName.allCases.count, 5)
        XCTAssertFalse(configuration.tonalPools.map(\.name).contains("happenings"))

        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        try bank.prepare(configuration: configuration)

        XCTAssertEqual(bank.happenings.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(bank.metrics.happeningMetrics.allocatedPlayerCount, 4)
        XCTAssertLessThanOrEqual(bank.metrics.happeningMetrics.decodedByteCount, 48 * 1_024 * 1_024)
    }

    func testFocusedFullMusicPreparationDecodesOnlyRequestedHappenings() throws {
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let requestedRecipeIDs = Set(HappeningSoundCatalog.recipes.prefix(2).map(\.id))

        try bank.prepare(
            configuration: .playbackWorld,
            happeningRecipeIDs: requestedRecipeIDs
        )

        XCTAssertEqual(bank.happenings.metrics.availableRecipeIDs, requestedRecipeIDs)
    }

    func testSampleOnlyPreparationUpgradesToFullMusicWithoutStartingASecondEngine() async throws {
        try requireLiveAudioOutput()
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))

        try bank.prepare(level: .sampleOnly([recipeID]))
        XCTAssertEqual(bank.preparationLevel, .sampleOnly([recipeID]))
        XCTAssertEqual(bank.happenings.metrics.availableRecipeIDs, [recipeID])
        XCTAssertEqual(bank.metrics.tonalPoolCount, 0)

        try bank.prepare(level: .fullMusic(.playbackWorld))
        try bank.start()

        XCTAssertEqual(bank.preparationLevel, .fullMusic(.playbackWorld))
        XCTAssertEqual(bank.metrics.engineInstanceCount, 1)
        XCTAssertEqual(bank.metrics.engineStartCount, 1)
        XCTAssertEqual(bank.metrics.happeningMetrics.allocatedPlayerCount, 4)
        await bank.stop()
    }

    func testSuccessfulSampleOnlyUpgradeHardReleasesManualAuditionsWithoutRebuildingSampleGraph() async throws {
        try requireLiveAudioOutput()
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let allRecipeIDs = Set(HappeningSoundCatalog.recipes.map(\.id))
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let sound = ResolvedHappeningSound(
            recipeID: recipe.id,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: source.rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )

        try bank.prepare(level: .sampleOnly(allRecipeIDs))
        try bank.start()
        let pool = bank.happenings
        let players = pool.metrics.fixedPlayerIdentities
        let buffers = pool.metrics.decodedBufferIdentities
        let bytes = pool.metrics.decodedByteCount
        let topology = bank.metrics.engineTopology
        let manualVoices = try Set((0..<4).map { _ in
            try pool.play(sound, gain: 1, priority: .manualAudition, effects: testHappeningEffects)
        })
        XCTAssertEqual(manualVoices.count, 4)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 4)

        try bank.prepare(level: .fullMusic(.playbackWorld))

        XCTAssertTrue(bank.happenings === pool)
        XCTAssertEqual(pool.metrics.fixedPlayerIdentities, players)
        XCTAssertEqual(pool.metrics.decodedBufferIdentities, buffers)
        XCTAssertEqual(pool.metrics.decodedByteCount, bytes)
        let upgradedTopology = bank.metrics.engineTopology
        XCTAssertEqual(upgradedTopology.persistentMasterNodeIdentities, topology.persistentMasterNodeIdentities)
        XCTAssertEqual(upgradedTopology.finalPeakLimiterIdentities, topology.finalPeakLimiterIdentities)
        XCTAssertEqual(upgradedTopology.roleBusIdentities, topology.roleBusIdentities)
        XCTAssertEqual(upgradedTopology.parallelSpatialReturnIdentities, topology.parallelSpatialReturnIdentities)
        XCTAssertEqual(upgradedTopology.commonMasterIdentity, topology.commonMasterIdentity)
        XCTAssertEqual(upgradedTopology.meterTapNodeIdentities, topology.meterTapNodeIdentities)
        XCTAssertEqual(upgradedTopology.meterTapInstallationCount, 1)
        XCTAssertFalse(upgradedTopology.physicalConnections.isEmpty)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
        XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .birth, effects: testHappeningEffects))
        XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .recurrence, effects: testHappeningEffects))
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
        bank.releaseAllIncludingSharedHappenings()
        await bank.stop()
    }

    func testStartedSampleOnlyUpgradeFailuresKeepRunningGraphAndRetryTransactionally() async throws {
        for stage in DayObjectsInstrumentBankPreparationStage.allCases {
            let harness = makeHarness()
            let allRecipeIDs = Set(HappeningSoundCatalog.recipes.map(\.id))
            let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
            let sound = ResolvedHappeningSound(
                recipeID: recipeID,
                resourceName: "one.wav",
                sourceRootMIDI: 60,
                targetMIDI: 60,
                playbackRate: 1,
                resonantFilterHz: nil
            )
            try harness.bank.prepare(level: .sampleOnly(allRecipeIDs))
            try harness.bank.start()
            let pool = try XCTUnwrap(harness.bank.happenings as? FakeHappeningSamplePool)
            for _ in 0..<4 {
                _ = try pool.play(sound, gain: 1, priority: .manualAudition, effects: testHappeningEffects)
            }
            let originalGraph = try XCTUnwrap(harness.engine.attachedGraph)
            let originalPlayerIdentities = harness.bank.happenings.metrics.fixedPlayerIdentities
            let originalBufferIdentities = harness.bank.happenings.metrics.decodedBufferIdentities
            let originalDecodedBytes = harness.bank.happenings.metrics.decodedByteCount
            let originalTopology = harness.bank.metrics.engineTopology
            XCTAssertEqual(pool.metrics.activeVoiceCount, 4)

            harness.failingAt = stage
            harness.engine.attachError = stage == .engine ? InjectedFailure() : nil
            XCTAssertThrowsError(try harness.bank.prepare(level: .fullMusic(configuration()))) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .preparationFailed(stage))
            }

            XCTAssertEqual(harness.bank.metrics.state, .started, "stage: \(stage)")
            XCTAssertTrue(harness.engine.isRunning, "stage: \(stage)")
            XCTAssertTrue(harness.engine.attachedGraph === originalGraph, "stage: \(stage)")
            XCTAssertEqual(harness.bank.happenings.metrics.fixedPlayerIdentities, originalPlayerIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedBufferIdentities, originalBufferIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedByteCount, originalDecodedBytes)
            XCTAssertEqual(harness.bank.metrics.engineTopology, originalTopology, "stage: \(stage)")
            XCTAssertEqual(harness.bank.metrics.engineTopology.finalPeakLimiterIdentities.count, 1)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 4, "stage: \(stage)")
            XCTAssertEqual(pool.releaseAllCount, 0, "stage: \(stage)")

            harness.failingAt = nil
            harness.engine.attachError = nil
            try harness.bank.prepare(level: .fullMusic(configuration()))
            XCTAssertEqual(harness.bank.metrics.state, .started)
            XCTAssertTrue(harness.engine.isRunning)
            XCTAssertEqual(harness.bank.happenings.metrics.fixedPlayerIdentities, originalPlayerIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedBufferIdentities, originalBufferIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedByteCount, originalDecodedBytes)
            XCTAssertEqual(harness.bank.metrics.engineTopology, originalTopology)
            XCTAssertEqual(pool.releaseAllCount, 1)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
            XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
            XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .birth, effects: testHappeningEffects))
            XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .recurrence, effects: testHappeningEffects))
            await harness.bank.stop()
        }
    }

    func testPairStopIsNoOpWhileAnIndividualBankOwnsTheSharedEngine() async throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankA.start()

        pair.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

        await pair.bankA.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
    }

    func testIndividualPlaybackBankOwnersStartOnFirstAndStopOnLastWithoutDetachingGraphs() async throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        try pair.bankA.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)

        try pair.bankB.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 2)

        await pair.bankA.stop()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
        XCTAssertEqual(pair.bankB.metrics.state, .started)

        await pair.bankB.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPairOwnershipRejectsIndividualStopsWithoutCorruptingBankStates() async throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        try pair.start()

        try pair.bankA.start()
        await pair.bankA.stop()
        await pair.bankB.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .started)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)

        pair.stop()
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testNonPromotableBankBOwnershipRejectsPairStartAndRecoversAfterLastOwnerStops() async throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankB.start()

        XCTAssertThrowsError(try pair.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
        XCTAssertEqual(pair.bankB.metrics.state, .started)

        await pair.bankB.stop()
        try pair.start()
        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
        pair.stop()
    }

    func testPairStartPromotesSoleBankAOwnerWithoutRestartingSharedEngineOrChangingTopology() async throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.bankA.prepare(level: .sampleOnly(Set(HappeningSoundCatalog.recipes.map(\.id))))
        try pair.bankA.start()
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let beforePromotion = pair.metrics

        try pair.start()

        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.metrics.sharedEngineStartCount, beforePromotion.sharedEngineStartCount)
        XCTAssertGreaterThan(beforePromotion.sharedEngineStartCount, 0)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, beforePromotion.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, beforePromotion.allocationFingerprint)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .started)

        pair.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.sharedEngineStopCount, 1)
    }

    func testPreparingAnAlreadyStartedPairPreservesStartedOwnershipInvariant() throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        let configuration = smallPlaybackPairConfiguration()
        try pair.prepare(configuration: configuration)
        try pair.start()
        let started = pair.metrics

        try pair.prepare(configuration: configuration)

        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.metrics.sharedEngineStartCount, started.sharedEngineStartCount)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, started.fixedSharedNodeIdentities)
        pair.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testPlaybackPairLifecycleStartsAndStopsSharedEngineOnceWithoutChangingTopology() throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        for cycle in 1...3 {
            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStartCount, cycle)

            pair.stop()
            pair.stop()
            pair.stop()
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStopCount, cycle)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        }
    }

    func testStandaloneStopRetainsAttachmentAndIsIdempotentAcrossStartedEpochs() async throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())
        try harness.bank.start()

        await harness.bank.stop()
        await harness.bank.stop()
        await harness.bank.stop()

        XCTAssertEqual(harness.releaseCount, 5)
        XCTAssertEqual(harness.engine.stopCount, 1)
        XCTAssertEqual(harness.engine.detachCount, 0)
        XCTAssertNotNil(harness.engine.attachedGraph)
        XCTAssertEqual(harness.bank.metrics.state, .prepared)

        try harness.bank.start()
        await harness.bank.stop()
        await harness.bank.stop()

        XCTAssertEqual(harness.releaseCount, 10)
        XCTAssertEqual(harness.engine.stopCount, 2)
        XCTAssertEqual(harness.engine.detachCount, 0)
        XCTAssertEqual(harness.engine.attachCount, 1)
        XCTAssertNotNil(harness.engine.attachedGraph)
        XCTAssertEqual(harness.bank.metrics.state, .prepared)
    }

    func testRealStandaloneRepeatedStopDoesNotClearPreparedAuditionUntilNextStartedEpochStops() async throws {
        try requireLiveAudioOutput()
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        try bank.prepare(configuration: .playbackWorld)
        try bank.start()
        let pool = bank.happenings
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipes.first)
        let sound = lifecycleResolvedSound(recipe: recipe)

        _ = try pool.play(sound, gain: 1, priority: .manualAudition, effects: lifecycleEffects(for: recipe))
        await bank.stop()
        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)

        _ = try pool.play(sound, gain: 1, priority: .manualAudition, effects: lifecycleEffects(for: recipe))
        await bank.stop()
        XCTAssertEqual(pool.metrics.activeVoiceCount, 1)

        try bank.start()
        await bank.stop()
        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
    }

    func testPlaybackPairStartFailuresRollbackWithoutLosingPreparedGraphsAndRetryWithoutAllocation() throws {
        try requireLiveAudioOutput()
        for failure in [
            DayObjectsPlaybackBankPairStartFailure.secondBankSynchronization,
            .sharedEngineStart,
        ] {
            var pendingFailure: DayObjectsPlaybackBankPairStartFailure? = failure
            let pair = DayObjectsInstrumentBank.makePlaybackPair(
                bundle: Bundle(for: type(of: self)),
                startFailureProvider: {
                    defer { pendingFailure = nil }
                    return pendingFailure
                }
            )
            try pair.prepare(configuration: smallPlaybackPairConfiguration())
            let baseline = pair.metrics
            let pool = pair.bankA.happenings
            let recipe = try XCTUnwrap(HappeningSoundCatalog.recipes.first)
            _ = try pool.play(
                lifecycleResolvedSound(recipe: recipe),
                gain: 1,
                priority: .manualAudition,
                effects: lifecycleEffects(for: recipe)
            )

            XCTAssertThrowsError(try pair.start()) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
            }
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

            _ = try pool.play(
                lifecycleResolvedSound(recipe: recipe),
                gain: 1,
                priority: .manualAudition,
                effects: lifecycleEffects(for: recipe)
            )
            pair.stop()
            XCTAssertEqual(pool.metrics.activeVoiceCount, 1)

            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            pair.stop()
            pair.stop()
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
        }
    }

    func testPlaybackPairUsesOneSharedEngineLimiterAndFixedRampableBankOutputs() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        let smallFixedWorld = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )

        try pair.prepare(configuration: smallFixedWorld)
        let baseline = pair.metrics

        XCTAssertEqual(baseline.attachedBankCount, 2)
        XCTAssertEqual(baseline.sharedAudioEngineCount, 1)
        XCTAssertEqual(baseline.finalPeakLimiterCount, 1)
        XCTAssertTrue(pair.bankA.happenings === pair.bankB.happenings)
        XCTAssertEqual(pair.bankA.happenings.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(pair.bankA.happenings.metrics.decodedBufferCount, 102)
        XCTAssertEqual(Set(baseline.happeningFixedPlayerIdentities).count, 4)
        XCTAssertEqual(baseline.happeningFixedPlayerIdentities.count, 4)
        XCTAssertEqual(Set(baseline.happeningDecodedBufferIdentities).count, 102)
        XCTAssertEqual(baseline.happeningDecodedBufferIdentities.count, 102)
        XCTAssertLessThanOrEqual(baseline.happeningDecodedByteCount, 48 * 1_024 * 1_024)
        XCTAssertEqual(Set(baseline.finalPeakLimiterIdentities).count, 1)
        XCTAssertEqual(baseline.sharedMasterTrimDecibels, -6, accuracy: 0.001)
        XCTAssertEqual(pair.bankA.metrics.graph?.finalPeakLimiterCount, 0)
        XCTAssertEqual(pair.bankB.metrics.graph?.finalPeakLimiterCount, 0)
        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 1)

        pair.bankA.setOutputGain(0.25, rampDurationSeconds: 0.5)
        pair.bankB.setOutputGain(0.75, rampDurationSeconds: 0.5)

        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 0.25)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 0.75)
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankB.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.bankA.outputGainMetrics.affectedRoles, [.rhythm, .bass, .harmony, .lead])
        XCTAssertEqual(pair.bankB.outputGainMetrics.affectedRoles, [.rhythm, .bass, .harmony, .lead])
        XCTAssertEqual(pair.metrics.fixedSharedNodeCount, baseline.fixedSharedNodeCount)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPlaybackPairRoutesAllFiveRolesThroughOnePersistentMaster() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: .playbackWorld)

        let topology = pair.bankA.metrics.engineTopology
        let master = try XCTUnwrap(topology.commonMasterIdentity)
        XCTAssertEqual(Set(topology.roleBusIdentities.keys), Set(DayObjectsRoleBus.allCases))
        XCTAssertEqual(topology.roleBusIdentities.count, 5)
        XCTAssertGreaterThanOrEqual(topology.parallelSpatialReturnIdentities.count, 4)
        XCTAssertEqual(topology.finalPeakLimiterIdentities.count, 1)
        XCTAssertEqual(Set(topology.roleMasterDestinations.values), [master])
        XCTAssertFalse(topology.happeningsUsesWorldTrim)
        XCTAssertEqual(topology.masterHighPassHz, 22)
        XCTAssertTrue((1.5...2).contains(topology.glueCompressorRatio))
        XCTAssertLessThanOrEqual(topology.nominalMaximumGlueReductionDB, 1.5)
        XCTAssertEqual(topology.limiterCeilingDBFS, -1.35)
        XCTAssertEqual(topology.roleHighPassHz[.bass], 27)
        XCTAssertGreaterThan(try XCTUnwrap(topology.roleHighPassHz[.harmony]), 27)
        XCTAssertTrue(topology.bassUsesMonoCompatibleLowBand)
        XCTAssertTrue(topology.bassUsesMildSaturation)
        XCTAssertNotNil(topology.masterSaturationIdentity)
        XCTAssertNotNil(topology.finalOutputIdentity)
        XCTAssertNotNil(topology.leadUpperMidDynamicsIdentity)
        XCTAssertEqual(topology.meterTapInstallationCount, 1)
        XCTAssertEqual(Set(topology.meterTapNodeIdentities).count, 7)

        func assertEdge(_ source: String, _ destination: String) throws {
            let edge = DayObjectsGraphConnection(
                source: try XCTUnwrap(topology.namedNodeIdentities[source]),
                destination: try XCTUnwrap(topology.namedNodeIdentities[destination])
            )
            XCTAssertTrue(topology.physicalConnections.contains(edge), "Missing physical edge \(source) -> \(destination)")
        }

        for bank in 0..<2 {
            let prefix = "bank\(bank).bass."
            try assertEdge(prefix + "source", prefix + "highPass27")
            try assertEdge(prefix + "highPass27", prefix + "lowPass140")
            try assertEdge(prefix + "lowPass140", prefix + "lowBandMono")
            try assertEdge(prefix + "highPass27", prefix + "highPass140")
            try assertEdge(prefix + "highPass140", prefix + "highPass140Slope")
            try assertEdge(prefix + "lowBandMono", prefix + "recombine")
            try assertEdge(prefix + "highPass140Slope", prefix + "recombine")
            try assertEdge(prefix + "recombine", prefix + "saturation")
            try assertEdge(prefix + "saturation", prefix + "duck")
            try assertEdge(prefix + "duck", prefix + "worldBassBus")
        }
        try assertEdge("lead.upperMidBand", "lead.upperMidDynamics")
        try assertEdge("lead.upperMidDynamics", "lead.upperMidBlend")
        try assertEdge("lead.upperMidBlend", "lead.recombine")
        try assertEdge("master.glue", "master.saturation")
        try assertEdge("master.saturation", "master.trim")
        try assertEdge("master.trim", "master.limiter")
        try assertEdge("master.limiter", "master.finalOutput")
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["master.trim.leftLinear"]), pow(10, -6.0 / 20), accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["master.trim.rightLinear"]), pow(10, -6.0 / 20), accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["master.saturation.dryWet"]), 0.10, accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["master.limiter.preGainDB"]), 0, accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["master.finalOutput.linear"]), pow(10, -1.35 / 20), accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["lead.upperMid.centerHz"]), 3_200, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["lead.upperMid.thresholdDB"]), -18, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["bass.saturation.pregain"]), 1.06, accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["bass.saturation.postgain"]), 0.96, accuracy: 0.000_01)
        XCTAssertEqual(try XCTUnwrap(topology.acceptedParameterValues["bass.saturation.dryWet"]), 0.06, accuracy: 0.000_01)
    }

    func testMeterTapNodesStayInstalledAcrossStopAndRestart() throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let prepared = pair.bankA.metrics.engineTopology

        try pair.start()
        pair.stop()
        try pair.start()
        let restarted = pair.bankA.metrics.engineTopology

        XCTAssertEqual(restarted.meterTapInstallationCount, 1)
        XCTAssertEqual(restarted.meterTapNodeIdentities, prepared.meterTapNodeIdentities)
        XCTAssertEqual(restarted.physicalConnections, prepared.physicalConnections)
        pair.stop()
    }

    func testMeterWindowsAndPublicationCacheResetAcrossStartStopRestart() throws {
        try requireLiveAudioOutput()
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        pair.consumeMeterSamplesForTesting(role: .rhythm, amplitude: 0.5)
        XCTAssertGreaterThan(pair.metrics.roleBusMetrics.rhythm.peakDBFS, -7)

        try pair.start()
        XCTAssertEqual(pair.metrics.roleBusMetrics.rhythm.peakDBFS, -120)
        pair.consumeMeterSamplesForTesting(role: .rhythm, amplitude: 0.25)
        XCTAssertGreaterThan(pair.metrics.roleBusMetrics.rhythm.peakDBFS, -13)

        pair.stop()
        XCTAssertEqual(pair.metrics.roleBusMetrics.rhythm.peakDBFS, -120)
        XCTAssertEqual(pair.metrics.masterMetrics.peakDBFS, -120)
        try pair.start()
        XCTAssertEqual(pair.metrics.roleBusMetrics.rhythm.peakDBFS, -120)
        pair.stop()
    }

    func testFiveRoleTopologyIdentityDoesNotChangeAcrossMixUpdates() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: .playbackWorld)
        let topology = pair.bankA.metrics.engineTopology
        let fixedSharedNodes = pair.metrics.fixedSharedNodeIdentities
        let mix = DayObjectsMixState.testingFiveRoleMix

        for _ in 0..<100 {
            pair.bankA.applyMix(mix)
            pair.bankB.applyMix(mix)
        }

        XCTAssertEqual(pair.bankA.metrics.engineTopology, topology)
        XCTAssertEqual(pair.bankB.metrics.engineTopology, topology)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, fixedSharedNodes)
    }

    func testPlaybackPairPublishesFiniteFiveRoleAndMasterMeterSnapshots() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: .playbackWorld)

        let metrics = pair.metrics

        for role in DayObjectsRoleBus.allCases {
            let snapshot = metrics.roleBusMetrics.metrics(for: role)
            XCTAssertTrue(snapshot.peakDBFS.isFinite)
            XCTAssertTrue(snapshot.rmsDBFS.isFinite)
            XCTAssertGreaterThanOrEqual(snapshot.activeVoiceCount, 0)
        }
        XCTAssertTrue(metrics.masterMetrics.peakDBFS.isFinite)
        XCTAssertTrue(metrics.masterMetrics.rmsDBFS.isFinite)
        XCTAssertTrue(metrics.masterMetrics.estimatedLimiterReductionDB.isFinite)
    }

    func testPlaybackPairFitsTheMobileRealtimeAllocationBudget() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        let allocations = pair.metrics.allocationFingerprint.compactMap { $0 }
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.tonalNodeIdentities.count },
            500
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.pianoLoadedPlayerCount },
            48
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.drumFixedPlayerCount },
            20
        )
    }

    func testPlaybackPairDoesNotStackMoreThanThreeDecibelsOfFixedTrimPerStage() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        for bank in [pair.bankA, pair.bankB] {
            let graph = try XCTUnwrap(bank.metrics.graph)
            XCTAssertGreaterThanOrEqual(graph.tonalBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.drumBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.masterTrimDB, -3.01)
        }
        XCTAssertEqual(pair.metrics.sharedMasterTrimDecibels, -6, accuracy: 0.001)
    }

    func testPlaybackPairSchedulesBankOutputGainAtAuthoritativeHostTimes() throws {
        var currentHostTime: TimeInterval = 100
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            outputGainHostTimeProvider: { currentHostTime }
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())

        pair.bankA.scheduleOutputGain(
            0.5,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )

        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.5,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 101,
            effectiveEndHostTimeSeconds: 102,
            wasForcedImmediate: false
        ))

        currentHostTime = 103
        pair.bankA.scheduleOutputGain(
            0.25,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.25,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 103,
            effectiveEndHostTimeSeconds: 103,
            wasForcedImmediate: true
        ))
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 2)
    }

    func testPlaybackPairSchedulesBassDuckGainAttackHoldAndUnityRecoveryAtHostTimes() throws {
        var currentHostTime: TimeInterval = 100
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            outputGainHostTimeProvider: { currentHostTime }
        )
        try pair.prepare(configuration: .playbackWorld)

        pair.bankA.scheduleBassDuck(.init(
            hostTimeSeconds: 101,
            maximumAttenuationDecibels: 4,
            attackSeconds: 0.005,
            holdSeconds: 0.040,
            releaseSeconds: 0.160
        ))

        let duck = pair.bankA.bassDuckGainMetrics
        XCTAssertTrue(duck.isSupported)
        XCTAssertEqual(duck.scheduledSegmentCount, 3)
        XCTAssertEqual(try XCTUnwrap(duck.lastAttack), .init(
            stage: .attack,
            targetLinearGain: pow(10, -4 / 20),
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 101.005,
            effectiveStartHostTimeSeconds: 101,
            effectiveEndHostTimeSeconds: 101.005,
            wasForcedImmediate: false
        ))
        XCTAssertEqual(try XCTUnwrap(duck.lastHold), .init(
            stage: .hold,
            targetLinearGain: pow(10, -4 / 20),
            requestedStartHostTimeSeconds: 101.005,
            requestedEndHostTimeSeconds: 101.045,
            effectiveStartHostTimeSeconds: 101.005,
            effectiveEndHostTimeSeconds: 101.045,
            wasForcedImmediate: false
        ))
        XCTAssertEqual(try XCTUnwrap(duck.lastRelease), .init(
            stage: .release,
            targetLinearGain: 1,
            requestedStartHostTimeSeconds: 101.045,
            requestedEndHostTimeSeconds: 101.205,
            effectiveStartHostTimeSeconds: 101.045,
            effectiveEndHostTimeSeconds: 101.205,
            wasForcedImmediate: false
        ))
        currentHostTime = 102
    }

    func testBassDuckResetCancelsActiveEnvelopeToUnityBeforeWorldReuse() throws {
        try requireLiveAudioOutput()
        var currentHostTime: TimeInterval = 100
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            outputGainHostTimeProvider: { currentHostTime }
        )
        try pair.prepare(configuration: .playbackWorld)
        try pair.start()
        let command = BassDuckCommand(
            hostTimeSeconds: 101,
            maximumAttenuationDecibels: 5,
            attackSeconds: 0.005,
            holdSeconds: 0.045,
            releaseSeconds: 0.180
        )

        pair.bankA.scheduleBassDuck(command)
        XCTAssertEqual(pair.bankA.bassDuckGainMetrics.scheduledSegmentCount, 3)
        XCTAssertLessThan(try XCTUnwrap(pair.bankA.bassDuckGainMetrics.lastAttack).targetLinearGain, 1)

        pair.stop()

        let reset = pair.bankA.bassDuckGainMetrics
        XCTAssertEqual(reset.resetCount, 1)
        XCTAssertTrue(reset.isEnvelopeClearedForReuse)
        XCTAssertNil(reset.lastAttack)
        XCTAssertNil(reset.lastHold)
        XCTAssertNil(reset.lastRelease)

        currentHostTime = 102
        try pair.prepare(configuration: .playbackWorld)
        try pair.start()
        pair.bankA.scheduleBassDuck(.init(
            hostTimeSeconds: 103,
            maximumAttenuationDecibels: 3,
            attackSeconds: 0.005,
            holdSeconds: 0.040,
            releaseSeconds: 0.160
        ))
        let reused = pair.bankA.bassDuckGainMetrics
        XCTAssertEqual(reused.resetCount, 1)
        XCTAssertEqual(try XCTUnwrap(reused.lastAttack).requestedStartHostTimeSeconds, 103, accuracy: 0.000_001)
        XCTAssertFalse(reused.isEnvelopeClearedForReuse)
        pair.stop()
    }

    private func smallPlaybackPairConfiguration() -> DayObjectsInstrumentBankConfiguration {
        .init(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )
    }

    private func lifecycleWorld() -> TonalWorldPlan {
        .init(
            centerPitchClass: 0,
            mode: .dorian,
            scalePitchClasses: [0, 2, 3, 5, 7, 9, 10],
            progression: [lifecycleChord()],
            cycleBars: 8
        )
    }

    private func lifecycleChord() -> ChordPlan {
        .init(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 3, 7],
            safePassingPitchClasses: [2, 5],
            voicedMIDINotes: [60, 63, 67],
            durationBars: 8
        )
    }

    private func lifecycleHappeningPlan(id: String, recipeRawValue: Int) -> HappeningMusicPlan {
        let recipe = HappeningSoundCatalog.recipe(for: lifecycleRecipeID(recipeRawValue))!
        return .init(
            happeningID: id,
            family: lifecycleFamily(for: recipe.family),
            recipeID: recipe.id,
            pan: 0,
            gain: 0.24,
            birthGain: 0.32,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds,
            delaySend: recipe.delayMix,
            reverbSend: recipe.reverbMix,
            recurrence: .init(scheduleSeed: UInt64(recipeRawValue), alignmentRank: UInt64(recipeRawValue), floatingOffsetBeats: 0.25)
        )
    }

    private func lifecycleResolvedSound(recipe: HappeningSoundRecipe) -> ResolvedHappeningSound {
        HappeningPitchResolver.resolve(
            recipe: recipe,
            chord: lifecycleChord(),
            tonalWorld: lifecycleWorld()
        )
    }

    private func lifecycleEffects(for recipe: HappeningSoundRecipe) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: recipe.delayMix,
            delayFeedback: recipe.delayFeedback,
            reverbMix: recipe.reverbMix
        )
    }

    private func lifecycleRecipeID(_ rawValue: Int) -> HappeningSoundRecipeID {
        HappeningSoundRecipeID(rawValue: rawValue)!
    }

    private func lifecycleFamily(for family: HappeningRecipeFamily) -> HappeningSoundFamily {
        switch family {
        case .synthPluck: return .pluck
        case .acousticMallet: return .mallet
        case .acousticBell: return .bell
        case .softOneShot: return .softOneShot
        case .texture: return .texture
        }
    }

    func testEqualPreparationBuildsTheFixedGraphOnlyOnceAndChangedConfigurationIsRejected() throws {
        let harness = makeHarness()
        let configuration = configuration()

        try harness.bank.prepare(configuration: configuration)
        try harness.bank.prepare(configuration: configuration)

        XCTAssertEqual(harness.tonalFactoryCallCount, 2)
        XCTAssertEqual(harness.drumFactoryCallCount, 1)
        XCTAssertEqual(harness.pianoFactoryCallCount, 1)
        XCTAssertEqual(harness.graphFactoryCallCount, 1)
        XCTAssertEqual(harness.bank.metrics.graph, .init(
            tonalBusCount: 1,
            drumBusCount: 1,
            sharedSpatialEffectCount: 2,
            tonalBusGainDB: -3,
            drumBusGainDB: -3,
            masterTrimDB: -3,
            finalPeakLimiterCount: 0
        ))

        XCTAssertThrowsError(try harness.bank.prepare(configuration: .init(
            tonalPools: [.init(name: "world", capacity: 3, reservesLeadVoice: false)],
            pianoVoiceCount: 4,
            drumOverlapCounts: [:]
        ))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .configurationChangedAfterPreparation)
        }
    }

    func testTonalPoolRejectsNonTonalInstrumentCommandsAtFacadeBoundary() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())

        let pool = try harness.bank.tonalPool(named: "role")
        XCTAssertThrowsError(try pool.prepareInstrument(.init(rawValue: "drums.kick"))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .invalidTonalInstrumentCategory(.drums))
        }
        XCTAssertThrowsError(try pool.prepareInstrument(.init(rawValue: "piano.felt"))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .invalidTonalInstrumentCategory(.piano))
        }
        XCTAssertNil(pool.noteOn(request(instrumentID: .init(rawValue: "drums.kick"))))
        XCTAssertNil(pool.noteOn(request(instrumentID: .init(rawValue: "piano.felt"))))
        XCTAssertEqual(harness.tonalNoteOnCount, 0)
    }

    func testEachPreparationFailureReleasesPartialStateAndIsRetryableWithStableDiagnostic() throws {
        for stage in DayObjectsInstrumentBankPreparationStage.allCases {
            let harness = makeHarness(failingAt: stage)

            XCTAssertThrowsError(try harness.bank.prepare(configuration: configuration())) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .preparationFailed(stage))
            }
            XCTAssertEqual(harness.bank.metrics.state, .unprepared)
            XCTAssertEqual(harness.releaseCount, expectedReleaseCount(for: stage))
            XCTAssertEqual(harness.engine.detachCount, 1)
            XCTAssertNil(harness.engine.attachedGraph)

            harness.failingAt = nil
            harness.engine.attachError = nil
            try harness.bank.prepare(configuration: configuration())
            XCTAssertEqual(harness.bank.metrics.state, .prepared)
        }
    }

    func testStartFailureStopsEngineReleasesVoicesAndLeavesTheBankRetryable() async throws {
        let harness = makeHarness()
        harness.engine.startError = InjectedFailure()
        try harness.bank.prepare(configuration: configuration())

        XCTAssertThrowsError(try harness.bank.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(harness.engine.stopCount, 1)
        XCTAssertEqual(harness.engine.detachCount, 1)
        XCTAssertEqual(harness.releaseCount, 5)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)
        XCTAssertNil(harness.engine.attachedGraph)

        harness.engine.startError = nil
        try harness.bank.prepare(configuration: configuration())
        try harness.bank.start()
        XCTAssertEqual(harness.bank.metrics.state, .started)
        await harness.bank.stop()
    }

    func testUnavailableCoreAudioOutputStartPreservesTypedDiagnosticClassification() throws {
        let harness = makeHarness()
        harness.engine.startError = NSError(
            domain: "com.apple.coreaudio.avfaudio",
            code: -10_851
        )
        try harness.bank.prepare(configuration: configuration())

        XCTAssertThrowsError(try harness.bank.start()) { error in
            XCTAssertEqual(
                error as? DayObjectsInstrumentBankError,
                .audioOutputUnavailable
            )
            XCTAssertEqual(
                (error as? DayObjectsInstrumentBankError)?.diagnosticID,
                "day-objects.instrument-bank.audio-output-unavailable"
            )
        }
    }

    func testLiveStartFailureClassifierMatchesOnlyExactTopLevelAndNestedCoreAudioErrors() {
        let unavailable = NSError(
            domain: "com.apple.coreaudio.avfaudio",
            code: -10_851
        )
        let nestedUnavailable = NSError(
            domain: "day-objects.test.wrapper",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: unavailable]
        )

        for error in [unavailable, nestedUnavailable] {
            XCTAssertEqual(
                DayObjectsInstrumentBankError.liveStartFailure(classifying: error),
                .audioOutputUnavailable
            )
        }

        for error in [
            NSError(domain: "com.apple.coreaudio.avfaudio", code: -10_850),
            NSError(domain: "day-objects.test", code: -10_851),
            NSError(domain: "day-objects.test", code: 7),
        ] {
            XCTAssertEqual(
                DayObjectsInstrumentBankError.liveStartFailure(classifying: error),
                .startFailed
            )
        }
    }

    func testLiveAudioPreflightSkipsOnlyExactTopLevelAndNestedOutputUnavailableErrors() {
        let unavailable = NSError(
            domain: "com.apple.coreaudio.avfaudio",
            code: -10_851
        )
        let nestedUnavailable = NSError(
            domain: "day-objects.test.wrapper",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: unavailable]
        )

        XCTAssertTrue(shouldSkipDayObjectsLiveAudioPreflightFailure(unavailable))
        XCTAssertTrue(shouldSkipDayObjectsLiveAudioPreflightFailure(nestedUnavailable))
        XCTAssertFalse(shouldSkipDayObjectsLiveAudioPreflightFailure(
            NSError(domain: "com.apple.coreaudio.avfaudio", code: -10_850)
        ))
        XCTAssertFalse(shouldSkipDayObjectsLiveAudioPreflightFailure(
            NSError(domain: "day-objects.test", code: -10_851)
        ))
        XCTAssertFalse(shouldSkipDayObjectsLiveAudioPreflightFailure(
            NSError(domain: "day-objects.test", code: 7)
        ))
    }

    func testColdPairedSampleOnlyStartUsesExactRawErrorClassification() throws {
        let unavailable = NSError(
            domain: "com.apple.coreaudio.avfaudio",
            code: -10_851
        )
        let cases: [(error: Error, expected: DayObjectsInstrumentBankError)] = [
            (unavailable, .audioOutputUnavailable),
            (
                NSError(
                    domain: "day-objects.test.wrapper",
                    code: 1,
                    userInfo: [NSUnderlyingErrorKey: unavailable]
                ),
                .audioOutputUnavailable
            ),
            (NSError(domain: "day-objects.test", code: 7), .startFailed),
        ]
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        var pendingErrors = cases.map(\.error)
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            individualStartFailureProvider: {
                guard !pendingErrors.isEmpty else { return nil }
                return pendingErrors.removeFirst()
            }
        )
        try pair.bankA.prepare(level: .sampleOnly([recipeID]))

        for testCase in cases {
            XCTAssertThrowsError(try pair.bankA.start()) { error in
                XCTAssertEqual(error as? DayObjectsInstrumentBankError, testCase.expected)
            }
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        }
        XCTAssertTrue(pendingErrors.isEmpty)
    }

    func testProcessLeasePrunesDeallocatedLiveAndOfflineOwnersWithoutExplicitStop() throws {
        final class Owner {}
        let lease = DayObjectsAudioPlaybackLease.shared

        weak var releasedLiveOwner: Owner?
        do {
            let owner = Owner()
            releasedLiveOwner = owner
            try lease.acquireLive(owner: owner)
        }
        XCTAssertNil(releasedLiveOwner)

        let offlineAfterAbandonedLive = Owner()
        XCTAssertNoThrow(try lease.acquireOffline(owner: offlineAfterAbandonedLive))
        lease.releaseOffline(owner: offlineAfterAbandonedLive)

        weak var releasedOfflineOwner: Owner?
        do {
            let owner = Owner()
            releasedOfflineOwner = owner
            try lease.acquireOffline(owner: owner)
        }
        XCTAssertNil(releasedOfflineOwner)

        let liveAfterAbandonedOffline = Owner()
        XCTAssertNoThrow(try lease.acquireLive(owner: liveAfterAbandonedOffline))
        lease.releaseLive(owner: liveAfterAbandonedOffline)
    }

    func testProcessLeasePrunesOwnersAbandonedByThrowAndCancellation() async throws {
        final class Owner {}
        enum Abort: Error { case injected }
        let lease = DayObjectsAudioPlaybackLease.shared

        do {
            let owner = Owner()
            try lease.acquireLive(owner: owner)
            throw Abort.injected
        } catch is Abort {}

        let offlineAfterThrow = Owner()
        XCTAssertNoThrow(try lease.acquireOffline(owner: offlineAfterThrow))
        lease.releaseOffline(owner: offlineAfterThrow)

        let cancelled = Task { @MainActor in
            let owner = Owner()
            try lease.acquireOffline(owner: owner)
            try Task.checkCancellation()
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("The lease-owning task should observe cancellation")
        } catch is CancellationError {}

        let liveAfterCancellation = Owner()
        XCTAssertNoThrow(try lease.acquireLive(owner: liveAfterCancellation))
        lease.releaseLive(owner: liveAfterCancellation)
    }

    func testProcessLeaseBlocksOfflineRenderingAcrossDistinctLiveBankInstancesThenReleases() async throws {
        let live = makeHarness()
        let offline = makeHarness()
        try live.bank.prepare(configuration: configuration())
        try offline.bank.prepare(configuration: configuration())
        try live.bank.start()

        XCTAssertThrowsError(
            try offline.bank.beginOfflineRendering(
                format: offlineFormat(),
                maximumFrameCount: 4_096
            )
        ) { error in
            XCTAssertEqual(
                error as? DayObjectsInstrumentBankError,
                .offlineRenderingConflictsWithLivePlayback
            )
        }

        await live.bank.stop()
        XCTAssertNoThrow(
            try offline.bank.beginOfflineRendering(
                format: offlineFormat(),
                maximumFrameCount: 4_096
            )
        )
        offline.bank.endOfflineRendering()
    }

    func testProcessLeaseBlocksLiveStartAcrossDistinctOfflineBankInstancesThenReleases() async throws {
        let offline = makeHarness()
        let live = makeHarness()
        try offline.bank.prepare(configuration: configuration())
        try live.bank.prepare(configuration: configuration())
        try offline.bank.beginOfflineRendering(
            format: offlineFormat(),
            maximumFrameCount: 4_096
        )

        XCTAssertThrowsError(try live.bank.start()) { error in
            XCTAssertEqual(
                error as? DayObjectsInstrumentBankError,
                .livePlaybackConflictsWithOfflineRendering
            )
        }

        offline.bank.endOfflineRendering()
        XCTAssertNoThrow(try live.bank.start())
        await live.bank.stop()
    }

    func testProcessLeaseReleasesAfterThrowingLiveStartAndOfflineBegin() async throws {
        let failingLive = makeHarness()
        let offlineAfterLiveFailure = makeHarness()
        try failingLive.bank.prepare(configuration: configuration())
        try offlineAfterLiveFailure.bank.prepare(configuration: configuration())
        failingLive.engine.startError = InjectedFailure()

        XCTAssertThrowsError(try failingLive.bank.start())
        XCTAssertNoThrow(
            try offlineAfterLiveFailure.bank.beginOfflineRendering(
                format: offlineFormat(),
                maximumFrameCount: 4_096
            )
        )
        offlineAfterLiveFailure.bank.endOfflineRendering()

        let failingOffline = makeHarness()
        let liveAfterOfflineFailure = makeHarness()
        try failingOffline.bank.prepare(configuration: configuration())
        try liveAfterOfflineFailure.bank.prepare(configuration: configuration())
        failingOffline.engine.offlineBeginError = InjectedFailure()

        XCTAssertThrowsError(
            try failingOffline.bank.beginOfflineRendering(
                format: offlineFormat(),
                maximumFrameCount: 4_096
            )
        )
        XCTAssertNoThrow(try liveAfterOfflineFailure.bank.start())
        await liveAfterOfflineFailure.bank.stop()
    }

    func testWorldLocalGraphTruthfullyExcludesSharedSpatialReturnsAndMasterLimiter() throws {
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let configuration = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )

        try bank.prepare(configuration: configuration)

        XCTAssertEqual(bank.metrics.state, .prepared)
        let graph = try XCTUnwrap(bank.metrics.graph)
        XCTAssertEqual(graph.tonalBusCount, 3)
        XCTAssertEqual(graph.drumBusCount, 1)
        XCTAssertEqual(graph.sharedSpatialEffectCount, 0)
        XCTAssertEqual(graph.roleBuses, [.rhythm, .bass, .harmony, .lead])
        XCTAssertEqual(graph.parallelSpatialReturnCount, 0)
        XCTAssertEqual(graph.tonalBusGainDB, 0, accuracy: 0.001)
        XCTAssertEqual(graph.drumBusGainDB, 0, accuracy: 0.001)
        XCTAssertEqual(graph.masterTrimDB, 0, accuracy: 0.001)
        XCTAssertEqual(graph.finalPeakLimiterCount, 0)
        XCTAssertEqual(bank.metrics.drumMetrics.allocatedPlayerCount, DayObjectsDrumVoice.allCases.count)
        XCTAssertEqual(bank.metrics.pianoMetrics.allocatedPlayerCount, 3)

        let pool = try bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.interstellar"))
        let fingerprint = try XCTUnwrap(bank.metrics.allocationFingerprint)
        for _ in 0..<20 {
            let token = try XCTUnwrap(pool.noteOn(request(instrumentID: .init(rawValue: "pad.interstellar"))))
            pool.update(token, with: .init(cutoffHz: 4_000, expression: 0.7, pan: 0.15))
            pool.noteOff(token)
            bank.drums.hit(.kickSoft, velocity: 0.7)
            let pianoToken = try XCTUnwrap(bank.piano.noteOn(60, velocity: 0.7))
            bank.piano.noteOff(pianoToken)
        }
        XCTAssertEqual(bank.metrics.allocationFingerprint, fingerprint)
    }

    func testFactoriesReceiveRequestedFixedCountsAndStopCanRestartWithoutReconfiguration() async throws {
        let harness = makeHarness()
        let requested = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: [.kickSoft: 1, .hatClosed: 2]
        )
        try harness.bank.prepare(configuration: requested)
        let graphIdentity = ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph))
        harness.engine.events.removeAll()
        let pool = try harness.bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.safe"))
        let identity = ObjectIdentifier(pool)
        for _ in 0..<100 {
            _ = pool.noteOn(request(instrumentID: .init(rawValue: "pad.safe")))
            harness.bank.drums.hit(.kickSoft, velocity: 0.7)
            _ = harness.bank.piano.noteOn(60, velocity: 0.7)
        }
        XCTAssertEqual(harness.requestedDrumOverlaps, [.kickSoft: 1, .hatClosed: 2])
        XCTAssertEqual(harness.requestedPianoVoiceCount, 3)
        XCTAssertEqual(harness.tonalFactoryCallCount, 1)
        XCTAssertEqual(harness.drumFactoryCallCount, 1)
        XCTAssertEqual(harness.pianoFactoryCallCount, 1)
        XCTAssertEqual(harness.tonalNoteOnCount, 100)
        XCTAssertEqual(harness.drumHitCount, 100)
        XCTAssertEqual(harness.pianoNoteOnCount, 100)
        XCTAssertEqual(ObjectIdentifier(try harness.bank.tonalPool(named: "role")), identity)

        try harness.bank.start()
        XCTAssertEqual(harness.engine.events, ["synchronize", "start"])
        await harness.bank.stop()
        XCTAssertEqual(harness.releaseCount, 4)
        XCTAssertEqual(harness.engine.detachCount, 0)
        XCTAssertNotNil(harness.engine.attachedGraph)
        harness.engine.events.removeAll()
        try harness.bank.start()
        XCTAssertEqual(harness.engine.attachCount, 1)
        XCTAssertEqual(harness.engine.events, ["synchronize", "start"])
        XCTAssertNotNil(harness.engine.attachedGraph)
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph)), graphIdentity)
        await harness.bank.stop()
    }

    func testPublicReleaseAllReachesEveryPreparedSubBank() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())

        harness.bank.releaseAllIncludingSharedHappenings()

        XCTAssertEqual(harness.releaseCount, 5)
        XCTAssertNotNil(harness.engine.attachedGraph)
    }

    func testSynchronizationAndStartFailuresDetachTheRetainedGraphAndAreRetryable() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())
        harness.graphSynchronizeError = InjectedFailure()
        harness.engine.events.removeAll()

        XCTAssertThrowsError(try harness.bank.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(harness.engine.events, ["synchronize", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)

        harness.graphSynchronizeError = nil
        try harness.bank.prepare(configuration: configuration())
        XCTAssertNotNil(harness.engine.attachedGraph)
        harness.engine.startError = InjectedFailure()
        harness.engine.events.removeAll()
        XCTAssertThrowsError(try harness.bank.start())
        XCTAssertEqual(harness.engine.events, ["synchronize", "start", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
    }

    private func configuration() -> DayObjectsInstrumentBankConfiguration {
        .init(
            tonalPools: [
                .init(name: "role", capacity: 2, reservesLeadVoice: true),
                .init(name: "world", capacity: 3, reservesLeadVoice: false),
            ],
            pianoVoiceCount: 4,
            drumOverlapCounts: [.kickSoft: 2, .hatClosed: 3]
        )
    }

    private func makeHarness(
        failingAt stage: DayObjectsInstrumentBankPreparationStage? = nil
    ) -> InstrumentBankHarness {
        InstrumentBankHarness(failingAt: stage)
    }

    private func request(instrumentID: DayObjectsInstrumentID) -> DayObjectsTonalNoteRequest {
        .init(instrumentID: instrumentID, midiNote: 60, velocity: 0.7, role: .note, envelopeVariant: nil, pan: 0, delaySend: 0, reverbSend: 0)
    }

    private func offlineFormat() -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
    }

    private func expectedReleaseCount(for stage: DayObjectsInstrumentBankPreparationStage) -> Int {
        switch stage {
        case .tonalInstruments: return 1
        case .tonalPools: return 2
        case .drums: return 3
        case .piano: return 4
        case .graph, .engine: return 5
        }
    }
}

@MainActor
private final class InstrumentBankHarness {
    var failingAt: DayObjectsInstrumentBankPreparationStage?
    var tonalFactoryCallCount = 0
    var drumFactoryCallCount = 0
    var pianoFactoryCallCount = 0
    var graphFactoryCallCount = 0
    var releaseCount = 0
    var tonalNoteOnCount = 0
    var drumHitCount = 0
    var pianoNoteOnCount = 0
    var graphSynchronizeError: Error?
    var requestedDrumOverlaps: [DayObjectsDrumVoice: Int] = [:]
    var requestedPianoVoiceCount: Int?
    let engine = FakeInstrumentBankEngine()
    private(set) var bank: DayObjectsInstrumentBank!

    init(failingAt: DayObjectsInstrumentBankPreparationStage?) {
        self.failingAt = failingAt
        engine.attachError = failingAt == .engine ? InjectedFailure() : nil
        bank = DayObjectsInstrumentBank(
            descriptors: [
                .init(id: .init(rawValue: "pad.safe"), category: .pad, displayName: "Safe", bankName: "Test", sourceUID: nil, referenceMIDI: 60, auditionChord: [60], outputTrimDB: -12),
                .init(id: .init(rawValue: "drums.kick"), category: .drums, displayName: "Kick", bankName: "Test", sourceUID: nil, referenceMIDI: 36, auditionChord: [], outputTrimDB: -12),
                .init(id: .init(rawValue: "piano.felt"), category: .piano, displayName: "Piano", bankName: "Test", sourceUID: nil, referenceMIDI: 60, auditionChord: [], outputTrimDB: -12),
            ],
            tonalInstrumentLoader: { [weak self] in
                guard self?.failingAt != .tonalInstruments else { throw InjectedFailure() }
                return [.init(rawValue: "pad.safe"): Self.safeVoice]
            },
            tonalPoolFactory: { [weak self] specification, _ in
                guard !(self?.failingAt == .tonalPools && self?.tonalFactoryCallCount == 1) else { throw InjectedFailure() }
                self?.tonalFactoryCallCount += 1
                return FakeTonalPool(name: specification.name, onNoteOn: { self?.tonalNoteOnCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            drumBankFactory: { [weak self] counts in
                guard self?.failingAt != .drums else { throw InjectedFailure() }
                self?.drumFactoryCallCount += 1
                self?.requestedDrumOverlaps = counts
                return FakeDrumBank(onHit: { self?.drumHitCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            pianoPoolFactory: { [weak self] count in
                guard self?.failingAt != .piano else { throw InjectedFailure() }
                self?.pianoFactoryCallCount += 1
                self?.requestedPianoVoiceCount = count
                return FakePianoPool(onNoteOn: { self?.pianoNoteOnCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            happeningPoolFactory: { [weak self] in
                FakeHappeningSamplePool(onRelease: { self?.releaseCount += 1 })
            },
            graphFactory: { [weak self] _, _, _, _ in
                guard self?.failingAt != .graph else { throw InjectedFailure() }
                self?.graphFactoryCallCount += 1
                return FakeInstrumentBankGraph(
                    isAttached: { [weak self] in self?.engine.attachedGraph != nil },
                    synchronizeError: { [weak self] in self?.graphSynchronizeError },
                    onSynchronize: { [weak self] in self?.engine.events.append("synchronize") }
                )
            },
            engine: engine
        )
    }

    private static let safeVoice = NormalizedSynthVoice(
        oscillator1: .init(wavePosition: 0, level: 0.8, semitoneOffset: 0, detuneHz: 0),
        oscillator2: .init(wavePosition: 0, level: 0, semitoneOffset: 0, detuneHz: 0),
        oscillatorBalance: 0.5,
        subOscillator: .init(level: 0, waveform: .sine, octaveOffset: -1),
        noiseLevel: 0,
        amplitudeEnvelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2),
        filter: .init(kind: .lowPass, cutoffHz: 12_000, resonance: 0.1, envelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2), envelopeAmount: 0),
        glideSeconds: 0,
        isMonophonic: false,
        lfo: .init(target: .none, rateHz: 1, depth: 0),
        delay: .init(isEnabled: false, timeSeconds: 0.2, feedback: 0, mix: 0),
        reverb: .init(isEnabled: false, feedback: 0.8, highPassHz: 80, mix: 0),
        phaser: .init(rateHz: 0.5, feedback: 0, mix: 0),
        autoPan: .init(rateHz: 0.25, depth: 0, stereoWidth: 0),
        outputTrimDB: -12,
        referenceMIDI: 60,
        auditionChord: [60]
    )
}

private struct InjectedFailure: Error {}

private extension DayObjectsMixState {
    static let testingFiveRoleMix = DayObjectsMixState(
        buses: .init(
            rhythm: .init(directTargetDecibels: -10, sendLevel: 0.08, decay: 0.42),
            bass: .init(directTargetDecibels: -12, sendLevel: 0.05, decay: 0.36),
            harmony: .init(directTargetDecibels: -10, sendLevel: 0.28, decay: 0.72),
            happenings: .init(directTargetDecibels: -8, sendLevel: 0.34, decay: 0.84),
            lead: .init(directTargetDecibels: -9, sendLevel: 0.24, decay: 0.62)
        ),
        harmonyPerVoiceTargetDecibels: -10,
        happeningPerVoiceTargetDecibels: -14,
        masterTargetDecibelsBeforeLimiter: -6,
        harmonyDuckingDecibels: 0,
        rampDurationSeconds: 0.25
    )

    static func testingFiveRoleMix(masterDecibels: Double) -> DayObjectsMixState {
        .init(
            buses: testingFiveRoleMix.buses,
            harmonyPerVoiceTargetDecibels: testingFiveRoleMix.harmonyPerVoiceTargetDecibels,
            happeningPerVoiceTargetDecibels: testingFiveRoleMix.happeningPerVoiceTargetDecibels,
            masterTargetDecibelsBeforeLimiter: masterDecibels,
            harmonyDuckingDecibels: testingFiveRoleMix.harmonyDuckingDecibels,
            rampDurationSeconds: 0
        )
    }
}

@MainActor
private final class FakeTonalPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let onNoteOn: () -> Void
    let onRelease: () -> Void
    init(name: String, onNoteOn: @escaping () -> Void, onRelease: @escaping () -> Void) { self.name = name; self.onNoteOn = onNoteOn; self.onRelease = onRelease }
    var metrics: DayObjectsTonalPoolMetrics { .init(name: name, allocatedVoiceCount: 2, allocatedNodeCount: 0, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0) }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { onNoteOn(); return nil }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeDrumBank: DayObjectsDrumBankProtocol {
    let onHit: () -> Void
    let onRelease: () -> Void
    init(onHit: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onHit = onHit; self.onRelease = onRelease }
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { onHit() }
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakePianoPool: DayObjectsPianoPoolProtocol {
    let onNoteOn: () -> Void
    let onRelease: () -> Void
    init(onNoteOn: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onNoteOn = onNoteOn; self.onRelease = onRelease }
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 4) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { onNoteOn(); return nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    let onRelease: () -> Void
    private let playerTokens = (0..<4).map { _ in NSObject() }
    private var preparedIDs: Set<HappeningSoundRecipeID> = []
    private var bufferTokens: [HappeningSoundRecipeID: NSObject] = [:]
    private var active: [Int: (priority: HappeningPlaybackPriority, handle: HappeningPlaybackHandle)] = [:]
    private var generation: UInt64 = 0
    private(set) var releaseAllCount = 0
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    var metrics: HappeningSamplePoolMetrics {
        .init(
            allocatedPlayerCount: 4,
            fixedPlayerIdentities: playerTokens.map(ObjectIdentifier.init),
            activeVoiceCount: active.count,
            releasingVoiceCount: 0,
            stealCount: 0,
            decodedBufferCount: preparedIDs.count,
            decodedBufferIdentities: preparedIDs.sorted(by: { $0.rawValue < $1.rawValue }).compactMap {
                bufferTokens[$0].map(ObjectIdentifier.init)
            },
            decodedByteCount: preparedIDs.count * 1_024,
            availableRecipeIDs: preparedIDs,
            unavailableRecipeIDs: [],
            effects: .init(filterCutoffHz: 8_000, delayMix: 0, delayFeedback: 0, reverbMix: 0),
            lastEffectRampSeconds: 0
        )
    }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {
        for id in recipeIDs where bufferTokens[id] == nil { bufferTokens[id] = NSObject() }
        preparedIDs.formUnion(recipeIDs)
    }
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand,
        pan: Double = 0
    ) throws -> HappeningPlaybackHandle {
        let voiceID: Int
        if let idle = (0..<4).first(where: { active[$0] == nil }) {
            voiceID = idle
        } else {
            guard let eligible = active
                .filter({ $0.value.priority < priority })
                .map(\.key)
                .min() else { throw HappeningSamplePoolError.noEligibleVoice }
            voiceID = eligible
        }
        generation &+= 1
        let handle = HappeningPlaybackHandle(voiceID: voiceID, generation: generation)
        active[voiceID] = (priority, handle)
        return handle
    }
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {}
    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {}
    func stop(_ handle: HappeningPlaybackHandle) {
        guard active[handle.voiceID]?.handle == handle else { return }
        active[handle.voiceID] = nil
    }
    func releaseAll() {
        releaseAllCount += 1
        active.removeAll()
        onRelease()
    }
}

@MainActor
private final class FakeInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    let layout = DayObjectsInstrumentBankGraphLayout(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, tonalBusGainDB: -3, drumBusGainDB: -3, masterTrimDB: -3, finalPeakLimiterCount: 0)
    let isAttached: () -> Bool
    let synchronizeError: () -> Error?
    let onSynchronize: () -> Void
    init(isAttached: @escaping () -> Bool, synchronizeError: @escaping () -> Error?, onSynchronize: @escaping () -> Void) {
        self.isAttached = isAttached
        self.synchronizeError = synchronizeError
        self.onSynchronize = onSynchronize
    }
    func synchronizeForStart() throws {
        onSynchronize()
        guard isAttached() else { throw InjectedFailure() }
        if let error = synchronizeError() { throw error }
    }
}

@MainActor
private final class FakeInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    private let masterToken = NSObject()
    private let limiterToken = NSObject()
    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        .init(
            persistentMasterNodeIdentities: [ObjectIdentifier(masterToken)],
            finalPeakLimiterIdentities: [ObjectIdentifier(limiterToken)]
        )
    }
    var startError: Error?
    var offlineBeginError: Error?
    var attachError: Error?
    private(set) var stopCount = 0
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private(set) var attachedGraph: (any DayObjectsInstrumentBankGraph)?
    private(set) var isRunning = false
    private(set) var isOfflineRendering = false
    var events: [String] = []
    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        events.append("attach")
        attachCount += 1
        if let attachError { throw attachError }
        attachedGraph = graph
    }
    func detach() { events.append("detach"); detachCount += 1; attachedGraph = nil }
    func start() throws {
        events.append("start")
        guard attachedGraph != nil else { throw InjectedFailure() }
        if let startError { throw startError }
        isRunning = true
    }
    func stop() { events.append("stop"); stopCount += 1; isRunning = false }
    func beginOfflineRendering(
        format: AVAudioFormat,
        maximumFrameCount: AVAudioFrameCount
    ) throws {
        events.append("begin-offline")
        guard attachedGraph != nil else { throw InjectedFailure() }
        if let offlineBeginError { throw offlineBeginError }
        isOfflineRendering = true
    }
    func endOfflineRendering() {
        events.append("end-offline")
        isOfflineRendering = false
    }
}
