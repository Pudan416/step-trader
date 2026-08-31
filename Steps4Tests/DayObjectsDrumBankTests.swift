import Foundation
import XCTest
@testable import Steps4

final class DayObjectsDrumBankTests: XCTestCase {
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

    func testMissingOptionalSampleDisablesOnlyItsDependentVoiceWithExactDiagnostics() {
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                sample == .stick ? nil : URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _ in FakeDrumPlayer() }
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
            playerFactory: { _, _ in FakeDrumPlayer() }
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
            playerFactory: { _, _ in
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

    func testPreparationResolvesEveryCanonicalBundledDrumSampleBeforeAnyHit() {
        var resolved: [DayObjectsDrumSample] = []
        let bank = DayObjectsDrumBank(
            resourceResolver: { sample in
                resolved.append(sample)
                return URL(fileURLWithPath: "/fixtures/\(sample.rawValue)")
            },
            playerFactory: { _, _ in FakeDrumPlayer() }
        )

        XCTAssertEqual(resolved, DayObjectsDrumSample.allCases)
        XCTAssertEqual(bank.preloadedSampleCount, 8)
    }
}

private final class FakeDrumPlayer: DayObjectsDrumPlayerBackend {
    private(set) var hitCount = 0

    func play(_ hit: DayObjectsDrumHit) {
        hitCount += 1
    }
}
