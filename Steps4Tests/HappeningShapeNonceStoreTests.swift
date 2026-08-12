import XCTest
@testable import Steps4

final class HappeningShapeNonceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HappeningShapeNonceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNonceIsStableWithinADay() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        XCTAssertEqual(store.nonce(for: "2026-08-10"), store.nonce(for: "2026-08-10"))
    }

    func testNonceSurvivesAReload() {
        let first = HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10")
        let second = HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10")
        XCTAssertEqual(first, second)
    }

    /// Reading is what rolls the day over, so there is no separate rollover hook
    /// to forget to call.
    func testANewDayRollsANewNonce() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        let today = store.nonce(for: "2026-08-10")
        let tomorrow = store.nonce(for: "2026-08-11")

        XCTAssertNotEqual(today, tomorrow)
        XCTAssertEqual(store.nonce(for: "2026-08-11"), tomorrow)
    }

    func testRerollChangesTheNonceAndPersists() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        let before = store.nonce(for: "2026-08-10")
        let after = store.reroll(for: "2026-08-10")

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(store.nonce(for: "2026-08-10"), after)
        XCTAssertEqual(HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10"), after)
    }

    /// `UserDefaults` has no `UInt64`. The bit pattern round-trips through
    /// `Int64`, and a value with the high bit set is where a naive conversion
    /// would lose it.
    func testAHighBitNonceRoundTripsExactly() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        defaults.set(
            NSNumber(value: Int64(bitPattern: UInt64.max)),
            forKey: SharedKeys.happeningShapeNonce
        )
        defaults.set("2026-08-10", forKey: SharedKeys.happeningShapeNonceDayKey)

        XCTAssertEqual(store.nonce(for: "2026-08-10"), UInt64.max)
    }
}
