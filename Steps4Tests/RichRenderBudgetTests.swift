import XCTest
@testable import Steps4

final class RichRenderBudgetTests: XCTestCase {
    func testTenElementNormalBudgetMatchesApprovedCeilings() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)

        XCTAssertEqual(budget.contourCount, 8)
        XCTAssertEqual(budget.orbitalRingCount, 8)
        XCTAssertEqual(budget.filamentCount, 24)
        XCTAssertEqual(budget.glowPassCount, 2)
        XCTAssertEqual(budget.globalParticleCount, 24)
        XCTAssertEqual(budget.requestedFPS, 20)
        XCTAssertFalse(budget.trailsEnabled)
    }

    func testLowPowerNeverExceedsNormalBudget() {
        let normal = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let low = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: true)

        XCTAssertLessThanOrEqual(low.contourCount, normal.contourCount)
        XCTAssertLessThanOrEqual(low.filamentCount, normal.filamentCount)
        XCTAssertLessThanOrEqual(low.glowPassCount, normal.glowPassCount)
        XCTAssertFalse(low.trailsEnabled)
    }

    func testSeedPhaseDesynchronizesGeometryUpdates() {
        XCTAssertNotEqual(RichTimeBuckets.phase(for: 1),
                          RichTimeBuckets.phase(for: 2))
    }
}
