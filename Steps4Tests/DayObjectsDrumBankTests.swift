import AudioKit
import AudioToolbox
import Foundation
import SoundpipeAudioKit
import XCTest
@testable import Steps4

final class DayObjectsDrumBankTests: XCTestCase {
    func testMetricsReportActuallyStartedRhythmPlayersAndResetOnRelease() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in URL(fileURLWithPath: "/fixtures/\(sample.rawValue)") },
            playerFactory: { _, _, _ in ActiveFakeDrumPlayer() }
        )

        XCTAssertEqual(bank.metrics.activePlayerCount, 0)
        bank.hit(.kickSoft)
        XCTAssertEqual(bank.metrics.activePlayerCount, 1)
        bank.hit(.kickSoft)
        XCTAssertEqual(bank.metrics.activePlayerCount, 2)

        bank.releaseAll()
        XCTAssertEqual(bank.metrics.activePlayerCount, 0)
    }

    func testSemanticInventoryResolvesToBoundedRecipes() {
        XCTAssertEqual(
            DayObjectsDrumVoice.allCases,
            [.kickSoft, .kickFull, .hatClosed, .hatOpen, .shaker, .clapSoft, .stick, .organicHigh, .organicLow]
        )

        for voice in DayObjectsDrumVoice.allCases {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)
            XCTAssertGreaterThan(recipe.overlapCount, 0, "\(voice) must have a fixed overlap pool")
            XCTAssertLessThanOrEqual(recipe.overlapCount, 4, "\(voice) must stay bounded")
            XCTAssertLessThanOrEqual(recipe.variation.pitchRateRange.upperBound, 1.03)
            XCTAssertGreaterThanOrEqual(recipe.variation.pitchRateRange.lowerBound, 0.97)
            XCTAssertTrue(recipe.outputTrimDecibels.isFinite)
            XCTAssertTrue((-24...0).contains(recipe.outputTrimDecibels))
        }
    }

    func testDrumRecipesUseCorrectiveHighPassAndProtectKickFundamentals() {
        for voice in DayObjectsDrumVoice.allCases {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)
            if [.kickSoft, .kickFull].contains(voice) {
                XCTAssertGreaterThanOrEqual(recipe.highPassCutoffHz, 25)
                XCTAssertLessThanOrEqual(recipe.highPassCutoffHz, 40)
            } else {
                XCTAssertGreaterThan(recipe.highPassCutoffHz, 40)
            }
        }
    }

    func testKicksCombineSinePitchDropBodiesWithFilteredSampleTransients() {
        for voice in [DayObjectsDrumVoice.kickSoft, .kickFull] {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)

            XCTAssertEqual(recipe.synthesis, [.sinePitchDrop])
            XCTAssertNotNil(recipe.primarySample)
            XCTAssertNotNil(recipe.transientFilterCutoffHz)
            XCTAssertFalse(recipe.allowsPitchDrift)
            XCTAssertFalse(recipe.allowsBroadbandSustainedNoise)
            XCTAssertFalse(recipe.usesSawOscillator)
            XCTAssertNil(recipe.delayFeedback)
        }
    }

    func testShakerIsFilteredSynthesizedNoiseWithoutAnAsset() {
        let recipe = DayObjectsDrumRecipe.recipe(for: .shaker)

        XCTAssertEqual(recipe.synthesis, [.filteredNoise])
        XCTAssertNil(recipe.primarySample)
        XCTAssertNotNil(recipe.noiseFilterCutoffHz)
        XCTAssertNil(recipe.delayFeedback)
    }

    func testSynthesizedRhythmVoiceLeavesActiveCountAfterItsEnvelopeCompletes() {
        var now = 10.0
        let player = DayObjectsAudioKitDrumPlayer(
            recipe: .recipe(for: .shaker),
            sampleURL: nil,
            preloadedSamplePlayer: nil,
            layerScheduler: RecordingDrumLayerScheduler(),
            hostTimeProvider: { now }
        )

        player.play(.init(
            voice: .shaker,
            velocity: 1,
            pitchRate: 1,
            scheduledHostTimeSeconds: now,
            microtimingMilliseconds: 0,
            roomSend: 0,
            stereoOffset: 0
        ))
        XCTAssertTrue(player.isActive)

        now += 0.2
        XCTAssertFalse(player.isActive)
    }

    func testMissingOptionalSampleDisablesOnlyItsDependentVoiceWithExactDiagnostics() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                sample == .stick ? nil : URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _, _ in FakeDrumPlayer() }
        )

        XCTAssertFalse(bank.isEnabled(.stick))
        XCTAssertTrue(bank.isEnabled(.kickSoft))
        XCTAssertTrue(bank.isEnabled(.hatClosed))
        XCTAssertEqual(
            bank.diagnostics,
            [
                DayObjectsDrumDiagnostic(
                    id: "day-objects.drum.resource-missing.cheeb-stick",
                    voice: .stick
                ),
                DayObjectsDrumDiagnostic(
                    id: "day-objects.drum.voice-disabled.stick",
                    voice: .stick
                ),
            ]
        )
    }

    func testDeclaredHatFallbackKeepsVoiceEnabledWhenPrimarySampleIsMissing() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                sample == .closedHat ? nil : URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _, _ in FakeDrumPlayer() }
        )

        XCTAssertTrue(bank.isEnabled(.hatClosed))
        XCTAssertEqual(bank.resolvedSample(for: .hatClosed), .cheebHat)
        XCTAssertEqual(
            bank.diagnostics,
            [DayObjectsDrumDiagnostic(id: "day-objects.drum.resource-missing.closed-hi-hat-f1", voice: .hatClosed)]
        )
    }

    func testOneThousandHitsReuseTheFixedPlayerPoolWithoutStartingAudio() {
        var players: [FakeDrumPlayer] = []
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in URL(fileURLWithPath: "/fixtures/\(sample.rawValue)") },
            playerFactory: { _, _, _ in
                let player = FakeDrumPlayer()
                players.append(player)
                return player
            }
        )
        let baseline = bank.metrics

        for index in 0..<1_000 {
            bank.hit(DayObjectsDrumVoice.allCases[index % DayObjectsDrumVoice.allCases.count])
        }

        XCTAssertEqual(bank.metrics, baseline)
        XCTAssertEqual(players.count, baseline.allocatedPlayerCount)
        XCTAssertEqual(players.reduce(0) { $0 + $1.hitCount }, 1_000)
    }

    func testScheduledPlaybackHitAppliesAuthoritativeMetadataWithoutRecipeVariation() throws {
        var players: [FakeDrumPlayer] = []
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in URL(fileURLWithPath: "/fixtures/\(sample.rawValue)") },
            playerFactory: { _, _, _ in
                let player = FakeDrumPlayer()
                players.append(player)
                return player
            }
        )
        let request = DayObjectsScheduledDrumHit(
            voice: .hatClosed,
            velocity: 0.73,
            scheduledHostTimeSeconds: 42.125,
            microtimingMilliseconds: -3.5,
            roomSend: 0.21,
            stereoOffset: -0.17,
            pitchDriftCents: 2.75
        )

        bank.schedule(request)

        let applied = try XCTUnwrap(players.flatMap(\.playedHits).first)
        XCTAssertEqual(applied.voice, .hatClosed)
        XCTAssertEqual(applied.velocity, 0.73, accuracy: 0.000_001)
        XCTAssertEqual(applied.scheduledHostTimeSeconds, 42.125, accuracy: 0.000_001)
        XCTAssertEqual(applied.microtimingMilliseconds, -3.5, accuracy: 0.000_001)
        XCTAssertEqual(applied.roomSend, 0.21, accuracy: 0.000_001)
        XCTAssertEqual(applied.stereoOffset, -0.17, accuracy: 0.000_001)
        XCTAssertEqual(applied.pitchRate, pow(2, 2.75 / 1_200), accuracy: 0.000_001)
    }

    func testPreparationResolvesEveryCanonicalBundledDrumSampleBeforeAnyHit() {
        var resolved: [DayObjectsDrumSample] = []
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                resolved.append(sample)
                return URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _, _ in FakeDrumPlayer() }
        )

        XCTAssertEqual(resolved, DayObjectsDrumSample.allCases)
        XCTAssertEqual(bank.preloadedSampleCount, 8)
    }

    func testEveryMissingCanonicalSampleProducesAStableDiagnosticEvenWhenOnlyFallbackUsesIt() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                [.closedHat, .cheebHat].contains(sample) ? nil : URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _, _ in FakeDrumPlayer() }
        )

        XCTAssertFalse(bank.isEnabled(.hatClosed))
        XCTAssertTrue(bank.isEnabled(.hatOpen))
        XCTAssertEqual(
            bank.diagnostics,
            [
                .init(id: "day-objects.drum.resource-missing.closed-hi-hat-f1", voice: .hatClosed),
                .init(id: "day-objects.drum.resource-missing.cheeb-hat", voice: .hatClosed),
                .init(id: "day-objects.drum.voice-disabled.hatClosed", voice: .hatClosed),
            ]
        )
    }

    func testEveryCanonicalMissingSampleHasItsOwnStableResourceDiagnostic() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { _ in nil },
            playerFactory: { _, _, _ in FakeDrumPlayer() }
        )

        XCTAssertEqual(
            bank.diagnostics.filter { $0.id.contains(".resource-missing.") }.map(\.id),
            [
                "day-objects.drum.resource-missing.bass-drum-c1",
                "day-objects.drum.resource-missing.closed-hi-hat-f1",
                "day-objects.drum.resource-missing.open-hi-hat-a1",
                "day-objects.drum.resource-missing.clap-d1",
                "day-objects.drum.resource-missing.snare-d1",
                "day-objects.drum.resource-missing.cheeb-stick",
                "day-objects.drum.resource-missing.cheeb-hat",
                "day-objects.drum.resource-missing.cheeb-ch",
            ]
        )
    }

    func testAudioKitAdapterBuildsOnlyRecipeLayersAndRetainsFixedCountsWithoutAnEngine() {
        let adapter = DayObjectsAudioKitDrumBank(resourceResolver: bundledDrumURL)
        let baseline = adapter.metrics

        XCTAssertEqual(baseline.preloadedSampleCount, 8)
        XCTAssertEqual(baseline.fixedPlayerCount, adapter.bank.metrics.allocatedPlayerCount)
        for voice in DayObjectsDrumVoice.allCases {
            let recipe = DayObjectsDrumRecipe.recipe(for: voice)
            let layout = baseline.layout(for: voice)

            XCTAssertEqual(layout.sinePitchDropCount, recipe.synthesis.contains(.sinePitchDrop) ? 1 : 0)
            XCTAssertEqual(layout.filteredNoiseCount, recipe.synthesis.contains(.filteredNoise) ? 1 : 0)
            XCTAssertEqual(layout.transientFilterCutoffHz, recipe.primarySample == nil ? nil : recipe.transientFilterCutoffHz)
            XCTAssertEqual(layout.noiseFilterCutoffHz, recipe.synthesis.contains(.filteredNoise) ? recipe.noiseFilterCutoffHz : nil)
            XCTAssertEqual(layout.highPassCutoffHz, recipe.highPassCutoffHz)
            XCTAssertEqual(layout.outputTrimDecibels, recipe.outputTrimDecibels, accuracy: 1e-12)
            XCTAssertEqual(layout.finalOutputGain, 1, accuracy: 1e-12)
            XCTAssertEqual(
                layout.signalPath,
                [.source, .highPass, .pan, .preRoomTrim, .room, .unityOutput],
                "The corrective trim must occur before the room send and the final output remains unity."
            )
        }

        for index in 0..<1_000 {
            adapter.bank.hit(DayObjectsDrumVoice.allCases[index % DayObjectsDrumVoice.allCases.count])
        }

        XCTAssertEqual(adapter.metrics, baseline)
    }

    func testRealKickBackendSchedulesEveryLogicalLayerAtTheSameFutureHostTime() {
        let scheduler = RecordingDrumLayerScheduler()
        let recipe = DayObjectsDrumRecipe.recipe(for: .kickFull)
        let player = DayObjectsAudioKitDrumPlayer(
            recipe: recipe,
            sampleURL: nil,
            preloadedSamplePlayer: AudioPlayer(),
            layerScheduler: scheduler
        )

        player.play(.init(
            voice: .kickFull,
            velocity: 0.72,
            pitchRate: 1,
            scheduledHostTimeSeconds: 42.125,
            microtimingMilliseconds: 0,
            roomSend: 0.24,
            stereoOffset: -0.18
        ))

        XCTAssertEqual(Set(scheduler.events.map(\.layer)), [
            .preRoomGainLeft, .preRoomGainRight, .stereo, .roomSend,
            .samplePitch, .sampleTransient,
            .sineAmplitude, .sinePitchDrop, .sineEnvelope,
        ])
        XCTAssertTrue(scheduler.events.allSatisfy { $0.hostTimeSeconds == 42.125 })
        let expectedPreRoomGain = 0.72 * pow(10, recipe.outputTrimDecibels / 20)
        XCTAssertEqual(try XCTUnwrap(scheduler.parameterValue(for: .preRoomGainLeft)), expectedPreRoomGain, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(scheduler.parameterValue(for: .preRoomGainRight)), expectedPreRoomGain, accuracy: 1e-6)
        XCTAssertNil(scheduler.parameterValue(for: .outputGainLeft))
        XCTAssertNil(scheduler.parameterValue(for: .outputGainRight))
        XCTAssertEqual(scheduler.immediateGateOpenCount, 0)
    }

    func testRealShakerBackendSchedulesNoiseEnvelopeAndSpatialMetadataAtTheSameFutureHostTime() {
        let scheduler = RecordingDrumLayerScheduler()
        let player = DayObjectsAudioKitDrumPlayer(
            recipe: .recipe(for: .shaker),
            sampleURL: nil,
            preloadedSamplePlayer: nil,
            layerScheduler: scheduler
        )

        player.play(.init(
            voice: .shaker,
            velocity: 0.61,
            pitchRate: 1,
            scheduledHostTimeSeconds: 9.75,
            microtimingMilliseconds: -2,
            roomSend: 0.4,
            stereoOffset: 0.25
        ))

        XCTAssertEqual(Set(scheduler.events.map(\.layer)), [
            .preRoomGainLeft, .preRoomGainRight, .stereo, .roomSend,
            .noiseAmplitude, .noiseEnvelope,
        ])
        XCTAssertTrue(scheduler.events.allSatisfy { $0.hostTimeSeconds == 9.75 })
        XCTAssertEqual(scheduler.immediateGateOpenCount, 0)
    }

    func testSystemLayerSchedulerNeverClassifiesAFutureEnvelopeAsImmediate() {
        let scheduler = DayObjectsAudioKitDrumLayerScheduler(
            hostTimeProvider: { 100 },
            sampleRateProvider: { 48_000 }
        )

        XCTAssertEqual(
            scheduler.delivery(atHostTime: 100.08),
            .scheduled(sampleOffset: 3_840)
        )
        XCTAssertEqual(scheduler.delivery(atHostTime: 100), .immediate)
    }

    private func bundledDrumURL(for sample: DayObjectsDrumSample) -> URL? {
        let filename = sample.rawValue as NSString
        return Bundle(for: type(of: self)).url(
            forResource: filename.deletingPathExtension,
            withExtension: filename.pathExtension,
            subdirectory: "Drums"
        )
    }
}

private final class RecordingDrumLayerScheduler: DayObjectsDrumLayerScheduling {
    private(set) var events: [DayObjectsDrumLayerScheduleEvent] = []
    private(set) var immediateGateOpenCount = 0

    func isReady(output: Node) -> Bool { true }

    func scheduleSample(
        _ player: AudioPlayer,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        events.append(.init(layer: layer, hostTimeSeconds: hostTimeSeconds))
    }

    func scheduleGate(
        _ envelope: AmplitudeEnvelope,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        events.append(.init(layer: layer, hostTimeSeconds: hostTimeSeconds))
    }

    func scheduleParameter(
        _ parameter: NodeParameter,
        value: AUValue,
        rampDuration: TimeInterval,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        events.append(.init(layer: layer, hostTimeSeconds: hostTimeSeconds, value: Double(value)))
    }

    func scheduleAUParameter(
        _ node: Node,
        address: AUParameterAddress,
        value: AUValue,
        range: ClosedRange<AUValue>,
        layer: DayObjectsDrumScheduledLayer,
        atHostTime hostTimeSeconds: TimeInterval
    ) {
        events.append(.init(layer: layer, hostTimeSeconds: hostTimeSeconds))
    }

    func stop(_ player: AudioPlayer?) {}
    func closeGate(_ envelope: AmplitudeEnvelope?) {}

    func parameterValue(for layer: DayObjectsDrumScheduledLayer) -> Double? {
        events.last(where: { $0.layer == layer })?.value
    }
}

private final class FakeDrumPlayer: DayObjectsDrumPlayerBackend {
    private(set) var hitCount = 0
    private(set) var playedHits: [DayObjectsDrumHit] = []

    func play(_ hit: DayObjectsDrumHit) {
        hitCount += 1
        playedHits.append(hit)
    }
}

private final class ActiveFakeDrumPlayer: DayObjectsDrumPlayerBackend {
    private(set) var isActive = false
    func play(_ hit: DayObjectsDrumHit) { isActive = true }
    func stop() { isActive = false }
}
