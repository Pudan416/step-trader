import XCTest
@testable import Steps4

final class StableMusicRandomTests: XCTestCase {
    func testFixedVectorsUseUTF8FNV1aDomainsAndSplitMix64() {
        let vectors: [(seed: UInt64, domain: MusicSeedDomain, expected: UInt64)] = [
            (0, .worldKey, 0x6175_5352_7D40_714D),
            (0, .worldMode, 0xDEA1_E2DD_EED6_DA65),
            (0, .rhythmPattern, 0x9B77_630E_EF4F_7FFF),
            (0, .happeningIdentity(stableID: "event-7"), 0xE9FA_FEA2_4206_F902),
            (1, .worldKey, 0x5265_9CAC_9038_DCB2),
            (1, .worldMode, 0x62C1_9237_6FBA_C66E),
            (1, .rhythmPattern, 0x5D60_90C5_A9B0_926A),
            (1, .happeningIdentity(stableID: "event-7"), 0x7EBA_8F53_785F_4BF5),
            (0xD4A0_B1EC_75ED_0001, .worldKey, 0xD15F_2BC7_CEC8_5BA0),
            (0xD4A0_B1EC_75ED_0001, .worldMode, 0xBD3B_EC27_7321_BC1C),
            (0xD4A0_B1EC_75ED_0001, .rhythmPattern, 0x14B7_1A69_510D_2CE7),
            (0xD4A0_B1EC_75ED_0001, .happeningIdentity(stableID: "event-7"), 0x0F53_6D1C_EBC4_B1A9)
        ]

        for vector in vectors {
            var random = StableMusicRandom(seed: vector.seed, domain: vector.domain)
            XCTAssertEqual(random.nextUInt64(), vector.expected)
        }
    }

    func testSiblingDomainsHaveIndependentRepeatableStreams() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        var worldKey = StableMusicRandom(seed: seed, domain: .worldKey)
        var worldMode = StableMusicRandom(seed: seed, domain: .worldMode)
        var anotherWorldKey = StableMusicRandom(seed: seed, domain: .worldKey)

        let keyValue = worldKey.nextUInt64()
        XCTAssertNotEqual(keyValue, worldMode.nextUInt64())
        XCTAssertEqual(keyValue, anotherWorldKey.nextUInt64())
    }

    func testHappeningIdentityUsesEscapedStableIDRatherThanArrayPosition() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let existingID = "event.7/alpha"
        let initialIDs = [existingID]
        let insertedIDs = ["new-event", existingID]

        XCTAssertEqual(initialIDs.last, existingID)
        XCTAssertEqual(insertedIDs.last, existingID)
        XCTAssertEqual(
            MusicSeedDomain.happeningIdentity(stableID: existingID).rawValue,
            "happening.event%2E7%2Falpha.identity"
        )

        var original = StableMusicRandom(
            seed: seed,
            domain: .happeningIdentity(stableID: initialIDs[0])
        )
        var afterInsertion = StableMusicRandom(
            seed: seed,
            domain: .happeningIdentity(stableID: insertedIDs[1])
        )

        XCTAssertEqual(original.nextUInt64(), afterInsertion.nextUInt64())
        XCTAssertEqual(original.nextUInt64(), afterInsertion.nextUInt64())
    }

    func testBoundedIntegerReturnsAnExplicitOptionalForInvalidBounds() {
        let seed: UInt64 = 42
        var random = StableMusicRandom(seed: seed, domain: .rhythmPattern)

        XCTAssertEqual(random.nextInt(upperBound: 1), 0)
        XCTAssertNil(random.nextInt(upperBound: 0))
        XCTAssertNil(random.nextInt(upperBound: -1))
    }

    func testChoiceReturnsAnExplicitOptionalForEmptyCollections() {
        var random = StableMusicRandom(seed: 42, domain: .rhythmPattern)

        XCTAssertNil(random.choice(from: [Int]()))
        XCTAssertEqual(random.choice(from: ["one", "two", "three"]), "two")
    }

    func testStableShuffleHasAFixedPermutation() {
        var random = StableMusicRandom(seed: 42, domain: .rhythmPattern)

        XCTAssertEqual(random.shuffled([1, 2, 3, 4]), [1, 3, 2, 4])
    }

    func testUnitDoubleAndBernoulliRespectTheirClosedBounds() {
        var random = StableMusicRandom(seed: 42, domain: .rhythmPattern)

        XCTAssertTrue(random.nextUnitDouble() >= 0)
        XCTAssertTrue(random.nextUnitDouble() < 1)
        XCTAssertFalse(random.bernoulli(probability: 0))
        XCTAssertTrue(random.bernoulli(probability: 1))
        XCTAssertFalse(random.bernoulli(probability: .nan))
    }
}
