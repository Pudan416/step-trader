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

        let snapshot = meter.masterSnapshot(limiterReductionDB: .nan)

        XCTAssertEqual(snapshot.peakDBFS, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.rmsDBFS, 0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.limiterReductionDB, 0)
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
}
#endif
