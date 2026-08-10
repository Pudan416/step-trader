import XCTest
@testable import Steps4

/// `AppModel.unspentUsageBudgetMatchingShield(for:defaults:)` is the number the
/// Feeds UI shows. It has to agree with `ShieldRebuildHelper`, because the
/// shield is what actually decides whether the apps are open: any surface that
/// says "locked" while the shield says "open" invites the user to buy a window
/// they are already inside.
///
/// The central rule under test is that the window is *spent*, not *elapsed* —
/// an idle phone must not move the number.
@MainActor
final class UnspentUsageBudgetTests: XCTestCase {

    private let groupId = "group-under-test"
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "UnspentUsageBudgetTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    /// Writes a window bought `minutesAgo` minutes ago for `initial` minutes,
    /// of which `stored` are still unspent.
    private func writeWindow(initial: Int, stored: Int, minutesAgo: Int) {
        let started = Date.now.addingTimeInterval(TimeInterval(-minutesAgo * 60))
        defaults.set(stored, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(initial, forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.set(started, forKey: SharedKeys.usageBudgetStartedKey(groupId))
        defaults.set(
            started.addingTimeInterval(TimeInterval(initial * 60)),
            forKey: SharedKeys.usageBudgetExpiryKey(groupId)
        )
    }

    private func unspent() -> Int {
        AppModel.unspentUsageBudgetMatchingShield(for: groupId, defaults: defaults)
    }

    /// The regression this accessor exists for: 60 minutes bought, 45 of them
    /// idled away without touching the app. The shield still has the apps open
    /// on the full 60, so the UI must read 60 — not 15.
    func testIdleTimeDoesNotSpendTheWindow() {
        writeWindow(initial: 60, stored: 60, minutesAgo: 45)
        XCTAssertEqual(unspent(), 60)
    }

    /// Real usage is the only thing that moves it: the monitor decremented the
    /// stored value to 20, so 20 is what shows.
    func testOnlySpentMinutesComeOff() {
        writeWindow(initial: 60, stored: 20, minutesAgo: 45)
        XCTAssertEqual(unspent(), 20)
    }

    /// Past the window's expiry the shield goes back up, so the UI must stop
    /// claiming there is time left even though minutes went unspent.
    func testExpiredWindowReadsZero() {
        writeWindow(initial: 30, stored: 30, minutesAgo: 90)
        XCTAssertEqual(unspent(), 0)
    }

    func testZeroBudgetReadsZero() {
        writeWindow(initial: 60, stored: 0, minutesAgo: 5)
        XCTAssertEqual(unspent(), 0)
    }

    func testNoWindowAtAllReadsZero() {
        XCTAssertEqual(unspent(), 0)
    }

    /// No expiry key (older writes, and the widget path): the shield falls back
    /// to `started + initial`, and so must this.
    func testWindowWithoutExpiryFallsBackToStartedPlusInitial() {
        let started = Date.now.addingTimeInterval(-10 * 60)
        defaults.set(60, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(60, forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.set(started, forKey: SharedKeys.usageBudgetStartedKey(groupId))

        XCTAssertEqual(unspent(), 60)

        defaults.set(
            Date.now.addingTimeInterval(-120 * 60),
            forKey: SharedKeys.usageBudgetStartedKey(groupId)
        )
        XCTAssertEqual(unspent(), 0, "a window whose start is two hours back has closed")
    }

    /// Budget with no timing metadata at all: the shield refuses to skip
    /// shielding, so the UI must not show an open window either.
    func testBudgetWithoutTimingMetadataReadsZero() {
        defaults.set(60, forKey: SharedKeys.usageBudgetKey(groupId))
        XCTAssertEqual(unspent(), 0)
    }

    /// The accessor and the shield are never allowed to disagree about
    /// *whether* the window is open — that disagreement is what let a user be
    /// charged twice for the same hour.
    func testAgreesWithTheShieldAcrossCases() {
        let cases: [(name: String, write: () -> Void)] = [
            ("fresh", { self.writeWindow(initial: 60, stored: 60, minutesAgo: 0) }),
            ("idle", { self.writeWindow(initial: 60, stored: 60, minutesAgo: 45) }),
            ("partly spent", { self.writeWindow(initial: 60, stored: 20, minutesAgo: 45) }),
            ("expired", { self.writeWindow(initial: 30, stored: 30, minutesAgo: 90) }),
            ("empty", { self.writeWindow(initial: 60, stored: 0, minutesAgo: 5) })
        ]

        for testCase in cases {
            defaults.removePersistentDomain(forName: suiteName)
            testCase.write()

            let shieldSaysOpen = ShieldRebuildHelper.isUsageBudgetWallClockActive(
                defaults: defaults,
                groupId: groupId
            )
            XCTAssertEqual(
                unspent() > 0,
                shieldSaysOpen,
                "\(testCase.name): UI and shield disagree about whether the window is open"
            )
        }
    }
}
