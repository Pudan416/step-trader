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

    func testDetailTierDistributionCountsVisiblePreviewItemsInStableOrder() {
        let items = RichAssignmentFixture.previewItems(count: 10, nonce: 7)

        let distribution = RichDetailTierDistribution(items: items)

        XCTAssertEqual(
            distribution,
            RichDetailTierDistribution(accent: 1, medium: 6, large: 3)
        )
        XCTAssertEqual(distribution.compactDescription, "1A · 6M · 3L")
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

    @MainActor
    func testCadenceSessionBoundaryExcludesPausedDuration() {
        let cache = RichRenderCache()
        cache.recordFrame(time: 0, requestedFPS: 20)
        cache.recordFrame(time: 0.05, requestedFPS: 20)

        cache.beginCadenceSession(requestedFPS: 20)
        cache.recordFrame(time: 10.05, requestedFPS: 20)
        XCTAssertEqual(cache.cadenceSnapshot(), .zero)

        cache.recordFrame(time: 10.10, requestedFPS: 20)
        let resumed = cache.cadenceSnapshot()
        XCTAssertEqual(resumed.observedFPS, 20, accuracy: 0.001)
        XCTAssertEqual(resumed.slowIntervalCount, 0)
    }

    @MainActor
    func testCadenceRequestedFPSChangeStartsFreshWindow() {
        let cache = RichRenderCache()
        cache.recordFrame(time: 0, requestedFPS: 20)
        cache.recordFrame(time: 0.05, requestedFPS: 20)

        cache.recordFrame(time: 0.10, requestedFPS: 15)
        XCTAssertEqual(cache.cadenceSnapshot(), .zero)

        cache.recordFrame(time: 0.10 + 1.0 / 15.0, requestedFPS: 15)
        let reducedBudget = cache.cadenceSnapshot()
        XCTAssertEqual(reducedBudget.observedFPS, 15, accuracy: 0.001)
        XCTAssertEqual(reducedBudget.slowIntervalCount, 0)
    }

    func testEveryElementCountBandHasExactNormalAndLowPowerBudgets() {
        let lowPower = RichRenderBudget(
            contourCount: 5,
            orbitalRingCount: 5,
            filamentCount: 12,
            glowPassCount: 1,
            globalParticleCount: 8,
            requestedFPS: 15,
            trailsEnabled: false
        )
        let cases: [(
            label: String,
            counts: [Int],
            normal: RichRenderBudget,
            lowPower: RichRenderBudget
        )] = [
            (
                "0...5",
                [0, 1, 5],
                RichRenderBudget(
                    contourCount: 10,
                    orbitalRingCount: 8,
                    filamentCount: 32,
                    glowPassCount: 2,
                    globalParticleCount: 30,
                    requestedFPS: 20,
                    trailsEnabled: false
                ),
                lowPower
            ),
            (
                "6...10",
                [6, 8, 10],
                RichRenderBudget(
                    contourCount: 8,
                    orbitalRingCount: 8,
                    filamentCount: 24,
                    glowPassCount: 2,
                    globalParticleCount: 24,
                    requestedFPS: 20,
                    trailsEnabled: false
                ),
                lowPower
            ),
            (
                "11+",
                [11, 20, 100],
                RichRenderBudget(
                    contourCount: 6,
                    orbitalRingCount: 6,
                    filamentCount: 16,
                    glowPassCount: 1,
                    globalParticleCount: 16,
                    requestedFPS: 20,
                    trailsEnabled: false
                ),
                lowPower
            )
        ]

        for testCase in cases {
            for count in testCase.counts {
                XCTAssertEqual(
                    RichRenderBudget.resolve(
                        elementCount: count,
                        lowPowerMode: false
                    ),
                    testCase.normal,
                    "normal \(testCase.label), count \(count)"
                )
                XCTAssertEqual(
                    RichRenderBudget.resolve(
                        elementCount: count,
                        lowPowerMode: true
                    ),
                    testCase.lowPower,
                    "Low Power \(testCase.label), count \(count)"
                )
            }
        }
    }

    func testSeedPhaseDesynchronizesGeometryUpdates() {
        XCTAssertNotEqual(RichTimeBuckets.phase(for: 1),
                          RichTimeBuckets.phase(for: 2))
    }

    func testTimeBucketsChangeImmediatelyAroundSeededTransitions() {
        let epsilon = 0.000_000_001
        for seed in [UInt64(0), 1, 42, .max] {
            let phase = RichTimeBuckets.phase(for: seed)
            for bucket in [-2, 0, 1, 9] {
                let transition = Double(bucket) * RichTimeBuckets.bucketSeconds - phase

                XCTAssertEqual(
                    RichTimeBuckets.bucket(time: transition - epsilon, seed: seed),
                    bucket - 1,
                    "before transition for seed \(seed), bucket \(bucket)"
                )
                XCTAssertEqual(
                    RichTimeBuckets.bucket(time: transition + epsilon, seed: seed),
                    bucket,
                    "after transition for seed \(seed), bucket \(bucket)"
                )
            }
        }
    }

    func testOnlyCrystallineStarUsesChangingGeometryBuckets() {
        let seed: UInt64 = 42
        let phase = RichTimeBuckets.phase(for: seed)
        let beforeTransition = RichTimeBuckets.bucketSeconds - phase - 0.000_000_001
        let afterTransition = RichTimeBuckets.bucketSeconds - phase + 0.000_000_001

        for family in RichFigureFamily.allCases where family != .crystallineStar {
            XCTAssertEqual(
                RichTimeBuckets.geometryBucket(
                    family: family,
                    time: beforeTransition,
                    seed: seed
                ),
                RichTimeBuckets.geometryBucket(
                    family: family,
                    time: afterTransition,
                    seed: seed
                ),
                "static geometry churned for \(family)"
            )
        }
        XCTAssertNotEqual(
            RichTimeBuckets.geometryBucket(
                family: .crystallineStar,
                time: beforeTransition,
                seed: seed
            ),
            RichTimeBuckets.geometryBucket(
                family: .crystallineStar,
                time: afterTransition,
                seed: seed
            )
        )
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
