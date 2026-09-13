import CryptoKit
import Foundation
import Testing
@testable import EditorialFieldCore

@Suite("Corpus manifest")
struct CorpusManifestTests {
    private let commit = "8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd"
    private let nonce = "day-objects-editorial-field-visible-v1"

    @Test("seed is the first eight SHA-256 bytes in big-endian order")
    func seedUsesSpecifiedDigestPrefix() {
        let input = [commit, nonce, "breadth", "0", "0"].joined(separator: "\u{001F}")
        let digest = SHA256.hash(data: Data(input.utf8))
        let expected = digest.prefix(8).reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }

        #expect(SeedDerivation.daySeed(commit: commit, nonce: nonce, suite: "breadth", index: 0, collision: 0) == expected)
    }

    @Test("visible manifest has reproducible breadth and presentation coverage")
    func visibleManifestIsByteReproducible() throws {
        let first = try CorpusManifest.visibleV1().canonicalJSON()
        let second = try CorpusManifest.visibleV1().canonicalJSON()

        #expect(first == second)
        #expect(CorpusManifest.visibleV1().breadth.map(\.actorCount) ==
            [1, 1, 2, 2, 3, 3, 5, 5, 7, 7, 10, 10])
        #expect(CorpusManifest.visibleV1().phases == [0, 0.25, 0.5, 0.75])
        #expect(Set(CorpusManifest.visibleV1().breadth.map(\.background)) ==
            Set(BackgroundCondition.allCases))
    }

    @Test("visible fixture tables retain all required corpus conditions")
    func visibleFixtureTablesCoverRequiredConditions() {
        let manifest = CorpusManifest.visibleV1()

        #expect(manifest.canonicalEventIDs.count == 10)
        #expect(Set(manifest.canonicalEventIDs).count == 10)
        #expect(manifest.breadth.count == 12)
        #expect(manifest.continuity.stages.map(\.actorCount) == [1, 2, 3, 5, 7, 10, 5])
        #expect(manifest.stress.count == 48)
        #expect(Set(manifest.breadth.map(\.sleep)) == Set(SleepCondition.allCases))
        #expect(Set(manifest.breadth.map(\.steps)) == Set(StepCondition.allCases))
        #expect(manifest.breadth.map(\.reduceMotion).contains(true))
        #expect(manifest.breadth.map(\.reduceMotion).contains(false))
    }

    @Test("generated fixture seeds are unique and match their recorded collision")
    func fixtureSeedsAreUniquelyDerived() {
        let manifest = CorpusManifest.visibleV1()
        let fixtures = manifest.breadth + manifest.stress
        let allSeeds = fixtures.map(\.seed) + [manifest.continuity.seed]

        #expect(Set(allSeeds).count == allSeeds.count)
        for fixture in fixtures {
            #expect(fixture.seed == SeedDerivation.daySeed(
                commit: manifest.specificationCommit,
                nonce: manifest.nonce,
                suite: fixture.suite,
                index: fixture.index,
                collision: fixture.collision
            ))
        }
    }
}
