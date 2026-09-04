import XCTest
@testable import Steps4

final class GroovePlannerTests: XCTestCase {
    func testEveryHundredBucketsUseExactDistribution() {
        let modes = (0..<100).map(GroovePlanner.mode(forBucket:))

        XCTAssertEqual(modes.filter { $0 == .percussion }.count, 40)
        XCTAssertEqual(modes.filter { $0 == .bassPulse }.count, 25)
        XCTAssertEqual(modes.filter { $0 == .bassArp }.count, 20)
        XCTAssertEqual(modes.filter { $0 == .bassBed }.count, 15)
    }

    func testEveryModePublishesItsExactRetentionAndAnchorKickCap() {
        let expected: [(GrooveMode, Double, Int)] = [
            (.percussion, 1.00, 2),
            (.bassPulse, 0.65, 2),
            (.bassArp, 0.40, 1),
            (.bassBed, 0.50, 1)
        ]

        for (mode, retention, anchorKickCap) in expected {
            let plan = GroovePlanner.makePlan(remixSeed: seedProducing(mode))

            XCTAssertEqual(plan.auxiliaryRetention, retention, accuracy: 1e-12)
            XCTAssertEqual(plan.maximumAnchorKicksPerBar, anchorKickCap)
        }
    }

    func testSameSeedProducesAnIndependentRepeatableThinningPlan() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let first = GroovePlanner.makePlan(remixSeed: seed)
        let second = GroovePlanner.makePlan(remixSeed: seed)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.thinningSeed, seed)
    }

    private func seedProducing(_ mode: GrooveMode) -> UInt64 {
        for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).mode == mode {
            return seed
        }
        XCTFail("No seed found for \(mode)")
        return 0
    }
}
