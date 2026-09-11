import XCTest
@testable import Steps4

/// `AppModel.unspentUsageBudgetMatchingShield(for:defaults:)` is the number the
/// Feeds UI shows. It has to agree with `ShieldRebuildHelper`, because the
/// shield is what actually decides whether the apps are open: any surface that
/// says "locked" while the shield says "open" invites the user to buy a window
/// they are already inside.
///
/// The hard deadline limits the displayed number even when no foreground
/// usage occurred; a legacy counter may only shorten that remaining time.
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

    /// Idle time still approaches the hard deadline: only 15 minutes remain.
    func testIdleTimeIsBoundedByThePurchaseDeadline() {
        writeWindow(initial: 60, stored: 60, minutesAgo: 45)
        XCTAssertEqual(unspent(), 15)
    }

    /// A legacy usage counter cannot advertise more than the deadline permits.
    func testOnlySpentMinutesComeOff() {
        writeWindow(initial: 60, stored: 20, minutesAgo: 45)
        XCTAssertEqual(unspent(), 15)
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

        XCTAssertEqual(unspent(), 50)

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
    func testWidgetCountdownUsesPersistedDeadlineInsteadOfRestartingOnRefresh() throws {
        writeWindow(initial: 60, stored: 60, minutesAgo: 45)
        let expiry = try XCTUnwrap(defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupId)) as? Date)
        let first = try XCTUnwrap(ShieldRebuildHelper.usageBudgetDisplayExpiry(
            defaults: defaults, groupId: groupId, at: Date.now))
        let later = try XCTUnwrap(ShieldRebuildHelper.usageBudgetDisplayExpiry(
            defaults: defaults, groupId: groupId, at: Date.now.addingTimeInterval(5 * 60)))
        XCTAssertEqual(first, expiry)
        XCTAssertEqual(later, expiry)
    }

    func testLastPartialMinuteRemainsOpenUntilDeadline() {
        let now = Date.now
        defaults.set(10, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(now.addingTimeInterval(0.5), forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        XCTAssertEqual(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId, at: now), 1)
        XCTAssertEqual(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId, at: now.addingTimeInterval(1)), 0)
    }

    func testSpentUsageCanStillLimitLegacyWindowBeforeDeadline() {
        let now = Date.now
        defaults.set(3, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(now.addingTimeInterval(20 * 60), forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        XCTAssertEqual(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId, at: now), 3)
    }

    func testWidgetObservationsIncludeMinuteChangesAndExpiryWithoutReloading() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiry = now.addingTimeInterval(125)
        let dates = ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(600), expiries: [expiry])
        XCTAssertEqual(dates.map { $0.timeIntervalSince(now) }, [5, 65, 125])
    }

    func testWidgetObservationsDeduplicateAndStopAtRefreshHorizon() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expiry = now.addingTimeInterval(3600)
        let dates = ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(600), expiries: [expiry, expiry])
        XCTAssertEqual(dates.count, 10)
        XCTAssertEqual(dates.last, now.addingTimeInterval(600))
    }

}
