import XCTest
import FamilyControls
import DeviceActivity
@testable import Steps4

@MainActor
final class UnspentUsageBudgetTests: XCTestCase {
    private let groupId = "group-under-test"
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_789_200_000)

    override func setUpWithError() throws {
        suiteName = "UnspentUsageBudgetTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func session() -> UsageBudgetSession {
        UsageBudgetSession(minutes: 10, startedAt: now, expiresAt: now.addingTimeInterval(12 * 3600))
    }

    private func remaining(at date: Date) -> Int {
        ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId, at: date)
    }

    func testTenMinutePurchaseSurvivesHalfHourOfIdleTimeAndReload() {
        session().save(to: defaults, groupId: groupId)
        XCTAssertEqual(remaining(at: now.addingTimeInterval(30 * 60)), 10)
        let reloaded = UsageBudgetSession.load(from: UserDefaults(suiteName: suiteName)!, groupId: groupId)
        XCTAssertEqual(reloaded?.remainingMinutes, 10)
    }

    func testOnlyCumulativeUsageEventsSpendMinutesAndReplaysCannotSpendTwice() {
        var budget = session()
        XCTAssertTrue(budget.record(event: budget.eventName(minute: 3)))
        budget.save(to: defaults, groupId: groupId)
        XCTAssertEqual(remaining(at: now.addingTimeInterval(3600)), 7)
        XCTAssertFalse(budget.record(event: budget.eventName(minute: 3)))
        XCTAssertFalse(budget.record(event: budget.eventName(minute: 2)))
        XCTAssertFalse(budget.record(event: budget.eventName(minute: 11)))
        XCTAssertFalse(budget.record(event: session().eventName(minute: 10)))
        XCTAssertEqual(budget.remainingMinutes, 7)
        XCTAssertTrue(budget.record(event: budget.eventName(minute: 10)))
        budget.save(to: defaults, groupId: groupId)
        XCTAssertEqual(remaining(at: now.addingTimeInterval(3600)), 0)
    }

    func testTopUpKeepsCurrentGenerationAndWaitsForItsUsageToFinish() {
        var budget = session()
        let generation = budget.generation
        _ = budget.record(event: budget.eventName(minute: 3))
        budget.queuedMinutes += 10
        XCTAssertEqual(budget.generation, generation)
        XCTAssertEqual(budget.initialMinutes, 10)
        XCTAssertEqual(budget.remainingMinutes, 17)
        XCTAssertFalse(budget.needsNextSegment)
        _ = budget.record(event: budget.eventName(minute: 10))
        XCTAssertEqual(budget.remainingMinutes, 10)
        XCTAssertTrue(budget.needsNextSegment)
        budget.save(to: defaults, groupId: groupId)
        XCTAssertEqual(UsageBudgetSession.load(from: defaults, groupId: groupId)?.queuedMinutes, 10,
                       "A failed continuation must retain the already paid minutes for recovery")
    }

    func testDayBoundaryClosesUnspentUsageWithoutInventingUsageTicks() {
        let budget = session()
        budget.save(to: defaults, groupId: groupId)
        XCTAssertEqual(remaining(at: budget.expiresAt.addingTimeInterval(-1)), 10)
        XCTAssertEqual(remaining(at: budget.expiresAt), 0)
        XCTAssertEqual(remaining(at: budget.expiresAt.addingTimeInterval(60)), 0)
    }

    func testEventsAreIndependentCumulativeThresholdsExcludingPastUsage() throws {
        let budget = session()
        let events = ShieldRebuildHelper.usageEvents(selection: FamilyActivitySelection(), session: budget)
        XCTAssertEqual(events.count, 10)
        for minute in 1...10 {
            let event = try XCTUnwrap(events[DeviceActivityEvent.Name(budget.eventName(minute: minute))])
            XCTAssertEqual(event.threshold.minute, minute)
            XCTAssertFalse(event.includesPastActivity, "Padding a short schedule must not consume pre-purchase usage")
        }
    }

    func testWidgetTimelineDoesNotPredictUsageFromElapsedClockTime() {
        let deadline = now.addingTimeInterval(3600)
        XCTAssertEqual(ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(600), expiries: [deadline]), [])
        XCTAssertEqual(ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(7200), expiries: [deadline, deadline]), [deadline])
    }

    private func installSelectionFixture() throws -> Data {
        let data = try JSONEncoder().encode(FamilyActivitySelection())
        let groups: [[String: Any]] = [["id": groupId, "name": "Test",
            "selectionData": data.base64EncodedString(),
            "settings": ["familyControlsModeEnabled": true]]]
        defaults.set(try JSONSerialization.data(withJSONObject: groups), forKey: SharedKeys.ticketGroups)
        return data
    }

    func testFailedMonitoringClosesAccessWithoutDiscardingPaidMinutes() throws {
        var budget = session()
        budget.monitoredSelectionData = try installSelectionFixture()
        budget.save(to: defaults, groupId: groupId)
        XCTAssertTrue(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        XCTAssertFalse(ShieldRebuildHelper.hasRecoverableUsageBudget(defaults: defaults, groupId: groupId, at: now))
        budget.monitoringFailed = true
        budget.save(to: defaults, groupId: groupId)
        XCTAssertTrue(ShieldRebuildHelper.hasRecoverableUsageBudget(defaults: defaults, groupId: groupId, at: now),
                      "Widget recovery must remain available even with no colors for another purchase")
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        XCTAssertEqual(remaining(at: now), 10)
        budget.monitoringFailed = false
        budget.save(to: defaults, groupId: groupId)
        XCTAssertTrue(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
    }

    func testUnverifiedSelectionCannotUseExistingGroupBudget() throws {
        let selection = try installSelectionFixture()
        var budget = session()
        budget.save(to: defaults, groupId: groupId)
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        budget.monitoredSelectionData = selection
        budget.save(to: defaults, groupId: groupId)
        XCTAssertTrue(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        defaults.removeObject(forKey: SharedKeys.ticketGroups)
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        XCTAssertEqual(remaining(at: now), 10)
    }

    func testLegacyExpiredClockPurchaseIsNotResurrectedByUpgrade() {
        defaults.set(10, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(now.addingTimeInterval(-1), forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        XCTAssertEqual(remaining(at: now), 0)
    }

    func testMissingMetadataCannotOpenAccess() {
        defaults.set(10, forKey: SharedKeys.usageBudgetKey(groupId))
        XCTAssertEqual(remaining(at: now), 0)
    }
}
