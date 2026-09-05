#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayObjectsBusMeterTests: XCTestCase {
    func testMeterAccumulatesWithoutPublishingNonFiniteValues() {
        let meter = DayObjectsBusMeter()

        meter.consume(
            left: [0, 0.5, -0.5, .nan, .infinity],
            right: [0, 0.25, -0.25, -.infinity, 0]
        )
        let snapshot = meter.snapshot(activeVoiceCount: 2)

        XCTAssertTrue(snapshot.peakDBFS.isFinite)
        XCTAssertTrue(snapshot.rmsDBFS.isFinite)
        XCTAssertEqual(snapshot.peakDBFS, 20 * log10(0.5), accuracy: 0.000_001)
        XCTAssertEqual(snapshot.rmsDBFS, 20 * log10(sqrt(0.625 / 10)), accuracy: 0.000_001)
        XCTAssertEqual(snapshot.activeVoiceCount, 2)
    }

    func testSilentAndInvalidBuffersPublishFiniteFloor() {
        let meter = DayObjectsBusMeter()

        meter.consume(left: [], right: [])
        let snapshot = meter.snapshot(activeVoiceCount: -4)

        XCTAssertEqual(snapshot.peakDBFS, -120)
        XCTAssertEqual(snapshot.rmsDBFS, -120)
        XCTAssertEqual(snapshot.activeVoiceCount, 0)
    }

    func testMasterSnapshotSanitizesLimiterReduction() {
        let meter = DayObjectsBusMeter()
        meter.consume(left: [1], right: [1])

        let snapshot = meter.masterSnapshot(estimatedLimiterReductionDB: .nan)

        XCTAssertEqual(snapshot.peakDBFS, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.rmsDBFS, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.estimatedLimiterReductionDB, 0)
    }

    func testMeterUsesABoundedRecentBufferWindowInsteadOfLifetimePeak() {
        let meter = DayObjectsBusMeter()
        meter.consume(left: [1], right: [1])

        for _ in 0..<DayObjectsBusMeter.windowBufferCount {
            meter.consume(left: [0.1], right: [0.1])
        }

        let snapshot = meter.snapshot(activeVoiceCount: 0)
        XCTAssertEqual(snapshot.peakDBFS, -20, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.rmsDBFS, -20, accuracy: 0.000_001)
    }

    func testResetStartsANewSilentWindowAndDoesNotLeakPreviousSamples() {
        let meter = DayObjectsBusMeter()
        meter.consume(left: [0.8, -0.8], right: [0.4, -0.4])

        meter.reset()

        let snapshot = meter.snapshot(activeVoiceCount: 0)
        XCTAssertEqual(snapshot.peakDBFS, -120)
        XCTAssertEqual(snapshot.rmsDBFS, -120)
    }

    func testLimiterEstimateUsesOnlyLatencyAlignedFrameRanges() {
        let pre = DayObjectsBusMeter()
        let post = DayObjectsBusMeter()
        pre.consume(left: [1, -1], right: [1, -1], sampleTime: 1_000)
        post.consume(left: [0.5, -0.5], right: [0.5, -0.5], sampleTime: 1_130)

        XCTAssertEqual(
            pre.estimatedReduction(
                comparedTo: post,
                latencyFrames: 128,
                fixedOutputGainDB: -1
            ),
            0,
            accuracy: 1e-12
        )

        post.reset()
        post.consume(left: [0.5, -0.5], right: [0.5, -0.5], sampleTime: 1_128)
        XCTAssertEqual(
            pre.estimatedReduction(
                comparedTo: post,
                latencyFrames: 128,
                fixedOutputGainDB: -1
            ),
            5.020599913,
            accuracy: 0.001
        )
    }

    func testLimiterEstimateExpiresWithBoundedWindowAndReset() {
        let pre = DayObjectsBusMeter()
        let post = DayObjectsBusMeter()
        pre.consume(left: [1, -1], right: [1, -1], sampleTime: 0)
        post.consume(left: [0.5, -0.5], right: [0.5, -0.5], sampleTime: 64)
        XCTAssertGreaterThan(
            pre.estimatedReduction(comparedTo: post, latencyFrames: 64, fixedOutputGainDB: -1),
            4
        )

        for index in 1...DayObjectsBusMeter.windowBufferCount {
            let start = Int64(index * 256)
            pre.consume(left: [0.1, -0.1], right: [0.1, -0.1], sampleTime: start)
            post.consume(left: [0.1, -0.1], right: [0.1, -0.1], sampleTime: start + 64)
        }
        XCTAssertEqual(
            pre.estimatedReduction(comparedTo: post, latencyFrames: 64, fixedOutputGainDB: -1),
            0,
            accuracy: 1e-12
        )

        pre.reset()
        post.reset()
        XCTAssertEqual(
            pre.estimatedReduction(comparedTo: post, latencyFrames: 64, fixedOutputGainDB: -1),
            0,
            accuracy: 1e-12
        )
    }
}
#endif
