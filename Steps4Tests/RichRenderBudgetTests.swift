import XCTest
@testable import Steps4

final class RichRenderBudgetTests: XCTestCase {
    func testCadenceStatsDistinguishStableAndSlowIntervals() {
        let stable = RichCadenceStats.calculate(
            intervals: Array(repeating: 0.05, count: 30), requestedFPS: 20
        )
        let slow = RichCadenceStats.calculate(
            intervals: [0.05, 0.05, 0.10, 0.05], requestedFPS: 20
        )

        XCTAssertEqual(stable.observedFPS, 20, accuracy: 0.1)
        XCTAssertEqual(stable.slowIntervalCount, 0)
        XCTAssertEqual(slow.slowIntervalCount, 1)
    }

    func testParticleDistributionUsesStableQuotientAndRemainderShares() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        ]

        let counts = RichParticleDistribution.counts(
            eligibleIDs: ids,
            globalParticleCount: 8
        )

        XCTAssertEqual(counts[ids[0]], 3)
        XCTAssertEqual(counts[ids[1]], 3)
        XCTAssertEqual(counts[ids[2]], 2)
        XCTAssertEqual(counts.values.reduce(0, +), 8)
    }

    func testParticleDistributionHandlesEmptyEligibilityWithoutAllocating() {
        XCTAssertEqual(
            RichParticleDistribution.counts(
                eligibleIDs: [],
                globalParticleCount: 24
            ),
            [:]
        )
    }

    func testNoRenderBudgetCanEnableTrails() {
        for count in [1, 5, 10, 20] {
            XCTAssertFalse(
                RichRenderBudget.resolve(elementCount: count, lowPowerMode: false).trailsEnabled
            )
            XCTAssertFalse(
                RichRenderBudget.resolve(elementCount: count, lowPowerMode: true).trailsEnabled
            )
        }
    }

    @MainActor
    func testGeometryCacheUsesExact256EntryLRUBoundAndCanClear() {
        let cache = RichRenderCache()
        for seed in 0..<300 {
            let key = cacheKey(seed: UInt64(seed))
            _ = cache.geometry(for: key) { cachedGeometry(seed: UInt64(seed)) }
        }

        XCTAssertEqual(cache.geometryCount, 256)

        var rebuiltOldest = false
        _ = cache.geometry(for: cacheKey(seed: 0)) {
            rebuiltOldest = true
            return cachedGeometry(seed: 0)
        }
        XCTAssertTrue(rebuiltOldest)
        XCTAssertEqual(cache.geometryCount, 256)

        cache.removeAllGeometry()
        XCTAssertEqual(cache.geometryCount, 0)
    }

    @MainActor
    func testGeometryCacheRefreshesAccessForLRUEviction() {
        let cache = RichRenderCache()
        for seed in 0..<256 {
            _ = cache.geometry(for: cacheKey(seed: UInt64(seed))) {
                cachedGeometry(seed: UInt64(seed))
            }
        }
        _ = cache.geometry(for: cacheKey(seed: 0)) {
            XCTFail("Recently used entry should be cached")
            return cachedGeometry(seed: 0)
        }
        _ = cache.geometry(for: cacheKey(seed: 256)) { cachedGeometry(seed: 256) }

        _ = cache.geometry(for: cacheKey(seed: 0)) {
            XCTFail("Recently used entry should survive eviction")
            return cachedGeometry(seed: 0)
        }
        var rebuiltLeastRecentlyUsed = false
        _ = cache.geometry(for: cacheKey(seed: 1)) {
            rebuiltLeastRecentlyUsed = true
            return cachedGeometry(seed: 1)
        }
        XCTAssertTrue(rebuiltLeastRecentlyUsed)
        XCTAssertEqual(cache.geometryCount, 256)
    }

    @MainActor
    func testCadenceKeepsMostRecent60PositiveIntervals() {
        let cache = RichRenderCache()
        cache.recordFrame(time: 0, requestedFPS: 20)
        cache.recordFrame(time: 0.10, requestedFPS: 20)
        for step in 1...60 {
            cache.recordFrame(time: 0.10 + Double(step) * 0.05, requestedFPS: 20)
        }
        cache.recordFrame(time: 3.10, requestedFPS: 20)

        let stats = cache.cadenceSnapshot()
        XCTAssertEqual(stats.observedFPS, 20, accuracy: 0.001)
        XCTAssertEqual(stats.slowIntervalCount, 0)
    }

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

    private func cacheKey(seed: UInt64) -> RichGeometryCacheKey {
        RichGeometryCacheKey(
            family: .circle,
            fill: .outlineWithCore,
            seed: seed,
            detailTier: .medium,
            timeBucket: RichTimeBuckets.bucket(time: 42, seed: seed)
        )
    }

    private func cachedGeometry(seed: UInt64) -> RichCachedGeometry {
        let point = CGPoint(x: CGFloat(seed % 10) / 10, y: 0)
        return RichCachedGeometry(
            base: RichFigureGeometry(
                lines: [RichPolyline(points: [point], isClosed: false, role: .accent)],
                core: point,
                bounds: CGRect(origin: point, size: CGSize(width: 1, height: 1))
            ),
            fill: RichFillGeometry(
                lines: [], translucentSurfaces: [], highlightPoints: [point]
            )
        )
    }
}
