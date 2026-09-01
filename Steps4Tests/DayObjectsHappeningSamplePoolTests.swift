#if DEBUG || INTERNAL_BUILD
import AudioKit
import AVFoundation
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsHappeningSamplePoolTests: XCTestCase {
    func testAllocatesExactlyFourPlayersAndNeverCreatesAFifthOnPlay() throws {
        let harness = try makeHarness(recipes: [makeRecipe(id: 1, resources: ["one.wav"])])

        XCTAssertEqual(harness.pool.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(harness.voices.count, 4)
        let identities = harness.pool.metrics.fixedPlayerIdentities

        try harness.pool.prepare(recipeIDs: [id(1)])
        for _ in 0..<20 {
            let voiceID = try harness.pool.play(sound(id: 1, resource: "one.wav"), gain: 0.5, priority: .manualAudition)
            harness.pool.stop(voiceID: voiceID)
        }

        XCTAssertEqual(harness.voices.count, 4)
        XCTAssertEqual(harness.pool.metrics.fixedPlayerIdentities, identities)
    }

    func testReleasedVoiceIsReusedBeforeAnActiveVoiceIsStolen() throws {
        let harness = try preparedHarness()
        let voiceIDs = try (1...4).map {
            try harness.pool.play(sound(id: $0, resource: "\($0).wav"), gain: 0.5)
        }
        harness.pool.stop(voiceID: voiceIDs[2])

        let reused = try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.7,
            priority: .birth
        )

        XCTAssertEqual(reused, voiceIDs[2])
        XCTAssertEqual(harness.pool.metrics.stealCount, 0)
    }

    func testBirthAndManualAuditionStealTheOldestEligibleRecurrences() throws {
        let harness = try preparedHarness()
        let recurrenceIDs = try (1...4).map {
            try harness.pool.play(sound(id: $0, resource: "\($0).wav"), gain: 0.5)
        }

        let birth = try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.6,
            priority: .birth
        )
        let manual = try harness.pool.play(
            sound(id: 6, resource: "6.wav"),
            gain: 0.7,
            priority: .manualAudition
        )

        XCTAssertEqual(birth, recurrenceIDs[0])
        XCTAssertEqual(manual, recurrenceIDs[1])
        XCTAssertEqual(harness.pool.metrics.stealCount, 2)
    }

    func testRecurrenceCannotStealEqualOrHigherPriorityVoices() throws {
        let harness = try preparedHarness()
        for recipeID in 1...4 {
            _ = try harness.pool.play(
                sound(id: recipeID, resource: "\(recipeID).wav"),
                gain: 0.7,
                priority: recipeID == 1 ? .manualAudition : .birth
            )
        }

        XCTAssertThrowsError(try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.4,
            priority: .recurrence
        )) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .noEligibleVoice)
        }
        XCTAssertEqual(harness.pool.metrics.stealCount, 0)
    }

    func testCompatibilityPlayDefaultsToRecurrencePriority() throws {
        let harness = try preparedHarness()
        for recipeID in 1...4 {
            _ = try harness.pool.play(sound(id: recipeID, resource: "\(recipeID).wav"), gain: 0.5)
        }

        XCTAssertThrowsError(try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.5,
            priority: .recurrence
        )) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .noEligibleVoice)
        }
    }

    func testPreparationReusesDecodedBuffersAndAccountsBytesOnce() throws {
        let recipes = [
            makeRecipe(id: 1, resources: ["shared.wav", "one.wav"]),
            makeRecipe(id: 2, resources: ["shared.wav", "two.wav"]),
        ]
        let harness = try makeHarness(recipes: recipes, bytesPerResource: 4_096)

        try harness.pool.prepare(recipeIDs: [id(1), id(2)])
        try harness.pool.prepare(recipeIDs: [id(1), id(2)])

        XCTAssertEqual(harness.decodeCounts, [
            "one.wav": 1,
            "shared.wav": 1,
            "two.wav": 1,
        ])
        XCTAssertEqual(harness.pool.metrics.decodedBufferCount, 3)
        XCTAssertEqual(harness.pool.metrics.decodedByteCount, 12_288)
        XCTAssertEqual(harness.pool.metrics.availableRecipeIDs, [id(1), id(2)])
    }

    func testDecodeFailureIsIsolatedToItsRecipe() throws {
        let recipes = [
            makeRecipe(id: 1, resources: ["good.wav"]),
            makeRecipe(id: 2, resources: ["bad.wav"]),
        ]
        let harness = try makeHarness(recipes: recipes, failingResources: ["bad.wav"])

        try harness.pool.prepare(recipeIDs: [id(1), id(2)])

        XCTAssertEqual(harness.pool.metrics.availableRecipeIDs, [id(1)])
        XCTAssertEqual(harness.pool.metrics.unavailableRecipeIDs, [id(2)])
        XCTAssertNoThrow(try harness.pool.play(sound(id: 1, resource: "good.wav"), gain: 0.5))
        XCTAssertThrowsError(try harness.pool.play(sound(id: 2, resource: "bad.wav"), gain: 0.5)) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .recipeUnavailable(id(2)))
        }
    }

    func testReleaseAllStopsEveryVoiceAndClearsActiveMetrics() throws {
        let harness = try preparedHarness()
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        for recipeID in 1...4 {
            _ = try harness.pool.play(sound(id: recipeID, resource: "\(recipeID).wav"), gain: 0.5)
        }

        harness.pool.releaseAll()

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 4)
        XCTAssertTrue(harness.voices.allSatisfy { $0.stopCount == 1 })
    }

    func testSharedEffectsAreSanitizedAndRampWithoutAllocatingPlayers() throws {
        let harness = try preparedHarness()
        let identities = harness.pool.metrics.fixedPlayerIdentities

        harness.pool.applyEffects(.init(
            filterCutoffHz: .infinity,
            delayMix: -1,
            delayFeedback: 99,
            reverbMix: 2
        ), rampSeconds: 99)

        XCTAssertEqual(harness.pool.metrics.effects, .init(
            filterCutoffHz: 80,
            delayMix: 0,
            delayFeedback: DayObjectsAudioParameters.maximumDelayFeedback,
            reverbMix: 1
        ))
        XCTAssertEqual(harness.pool.metrics.lastEffectRampSeconds, 2)
        XCTAssertEqual(harness.pool.metrics.fixedPlayerIdentities, identities)
        XCTAssertEqual(harness.voices.count, 4)
    }

    func testProductionCatalogDecodesWithinFortyEightMiB() throws {
        let pool = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))

        try pool.prepare(recipeIDs: Set(HappeningSoundCatalog.recipes.map(\.id)))

        XCTAssertEqual(pool.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(pool.metrics.availableRecipeIDs.count, 30)
        XCTAssertEqual(pool.metrics.unavailableRecipeIDs, [])
        XCTAssertEqual(pool.metrics.decodedBufferCount, 102)
        XCTAssertLessThanOrEqual(pool.metrics.decodedByteCount, 48 * 1_024 * 1_024)
    }

    private func preparedHarness() throws -> PoolHarness {
        let recipes = (1...6).map { makeRecipe(id: $0, resources: ["\($0).wav"]) }
        let harness = try makeHarness(recipes: recipes)
        try harness.pool.prepare(recipeIDs: Set(recipes.map(\.id)))
        return harness
    }

    private func makeHarness(
        recipes: [HappeningSoundRecipe],
        bytesPerResource: Int = 1_024,
        failingResources: Set<String> = []
    ) throws -> PoolHarness {
        try PoolHarness(
            recipes: recipes,
            bytesPerResource: bytesPerResource,
            failingResources: failingResources
        )
    }

    private func makeRecipe(id rawID: Int, resources: [String]) -> HappeningSoundRecipe {
        HappeningSoundRecipe(
            id: id(rawID),
            label: String(format: "%02d", rawID),
            family: .texture,
            sources: resources.enumerated().map { index, resource in
                .init(resourceName: resource, rootMIDI: UInt8(60 + index), sha256: String(repeating: "a", count: 64))
            },
            pitch: .unpitched,
            gainDB: -12,
            attackSeconds: 0.01,
            releaseSeconds: 0.2,
            delayMix: 0.1,
            delayFeedback: 0.2,
            reverbMix: 0.15,
            filterStartHz: 8_000,
            filterEndHz: 4_000
        )
    }

    private func sound(id rawID: Int, resource: String) -> ResolvedHappeningSound {
        .init(
            recipeID: id(rawID),
            resourceName: resource,
            sourceRootMIDI: nil,
            targetMIDI: nil,
            playbackRate: 1,
            resonantFilterHz: nil
        )
    }

    private func id(_ rawValue: Int) -> HappeningSoundRecipeID {
        HappeningSoundRecipeID(rawValue: rawValue)!
    }
}

@MainActor
private final class PoolHarness {
    private let recorder: PoolHarnessRecorder
    var decodeCounts: [String: Int] { recorder.decodeCounts }
    var voices: [FakeHappeningVoice] { recorder.voices }
    let pool: DayObjectsHappeningSamplePool

    init(
        recipes: [HappeningSoundRecipe],
        bytesPerResource: Int,
        failingResources: Set<String>
    ) throws {
        let recorder = PoolHarnessRecorder()
        self.recorder = recorder
        pool = DayObjectsHappeningSamplePool(
            recipes: recipes,
            resourceResolver: { URL(fileURLWithPath: "/test/\($0)") },
            bufferLoader: { url in
                let resource = url.lastPathComponent
                recorder.decodeCounts[resource, default: 0] += 1
                if failingResources.contains(resource) { throw PoolTestFailure() }
                let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
                let frames = AVAudioFrameCount(max(bytesPerResource / MemoryLayout<Float>.size, 1))
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
                buffer.frameLength = frames
                return .init(buffer: buffer, decodedByteCount: bytesPerResource)
            },
            voiceFactory: { voiceID in
                let voice = FakeHappeningVoice(voiceID: voiceID)
                recorder.voices.append(voice)
                return voice
            }
        )
    }
}

@MainActor
private final class PoolHarnessRecorder {
    var decodeCounts: [String: Int] = [:]
    var voices: [FakeHappeningVoice] = []
}

private struct PoolTestFailure: Error {}

@MainActor
private final class FakeHappeningVoice: DayObjectsHappeningSampleVoiceBackend {
    let voiceID: Int
    private let mixer = Mixer()
    var output: Node { mixer }
    private(set) var playCount = 0
    private(set) var releaseCount = 0
    private(set) var stopCount = 0

    init(voiceID: Int) { self.voiceID = voiceID }

    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double
    ) {
        playCount += 1
    }

    func release() { releaseCount += 1 }
    func stop() { stopCount += 1 }
}
#endif
