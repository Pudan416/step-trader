import XCTest
import FamilyControls
import DeviceActivity
import Darwin
@testable import Nowhere

@MainActor
final class TimedAccessPassTests: XCTestCase {
    private let groupId = "group-under-test"
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_789_200_000)

    override func setUpWithError() throws {
        suiteName = "TimedAccessPassTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func session(minutes: Int = 10, duration: TimeInterval = 10 * 60) -> UsageBudgetSession {
        UsageBudgetSession(minutes: minutes, startedAt: now, expiresAt: now.addingTimeInterval(duration))
    }

    private func remaining(at date: Date) -> Int {
        ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId, at: date)
    }

    func testScreenTimeRegistrationRunsOutsidePassStateLock() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-access-lock-\(UUID().uuidString)")
        let registrationLockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timed-access-registration-lock-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: lockURL)
            try? FileManager.default.removeItem(at: registrationLockURL)
        }

        let lock = UsageBudgetFileLock(fileURL: lockURL)
        let registrationLock = UsageBudgetFileLock(fileURL: registrationLockURL)
        var phases: [String] = []

        try UsageBudgetRegistrationCoordinator.perform(
            stateLock: lock,
            registrationLock: registrationLock,
            prepare: {
                phases.append("prepare")
                XCTAssertFalse(try canAcquireLock(at: lockURL))
                return "prepared"
            },
            register: { prepared in
                phases.append("register:\(prepared)")
                XCTAssertTrue(try canAcquireLock(at: lockURL))
                XCTAssertFalse(try canAcquireLock(at: registrationLockURL))
            },
            commit: { prepared in
                phases.append("commit:\(prepared)")
                XCTAssertFalse(try canAcquireLock(at: lockURL))
            },
            rollback: { _ in XCTFail("Successful registration must not roll back") }
        )
        XCTAssertEqual(phases, ["prepare", "register:prepared", "commit:prepared"])
    }

    private func canAcquireLock(at url: URL) throws -> Bool {
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { return false }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        flock(descriptor, LOCK_UN)
        return true
    }

    func testPassCountsDownDuringIdleTimeAndSurvivesReload() {
        session(duration: 30 * 60).save(to: defaults, groupId: groupId)
        XCTAssertEqual(remaining(at: now), 30)
        XCTAssertEqual(remaining(at: now.addingTimeInterval(12 * 60)), 18)

        let reloaded = UsageBudgetSession.load(from: UserDefaults(suiteName: suiteName)!, groupId: groupId)
        XCTAssertEqual(reloaded?.expiresAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(remaining(at: now.addingTimeInterval(30 * 60)), 0)
    }

    func testPassKeepsItsDeadlineAcrossCustomDayBoundary() {
        let pass = session(duration: 30 * 60)
        pass.save(to: defaults, groupId: groupId)
        let customDayBoundary = now.addingTimeInterval(15 * 60)

        XCTAssertEqual(remaining(at: customDayBoundary), 15)
        XCTAssertEqual(ShieldRebuildHelper.usageBudgetDeadline(defaults: defaults, groupId: groupId), pass.expiresAt)
    }

    func testExpiredPassDoesNotUnlockGroup() {
        session(duration: 10 * 60).save(to: defaults, groupId: groupId)
        XCTAssertTrue(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId,
                                                              at: now.addingTimeInterval(9 * 60)))
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId,
                                                               at: now.addingTimeInterval(10 * 60)))
        XCTAssertNil(ShieldRebuildHelper.usageBudgetDisplayExpiry(defaults: defaults, groupId: groupId,
                                                                  at: now.addingTimeInterval(10 * 60)))
    }

    func testOnlyCurrentTimedPassIdentityResolves() throws {
        let data = try JSONEncoder().encode(FamilyActivitySelection())
        let groups: [[String: Any]] = [["id": groupId, "name": "Test",
            "selectionData": data.base64EncodedString(),
            "settings": ["familyControlsModeEnabled": true]]]
        defaults.set(try JSONSerialization.data(withJSONObject: groups), forKey: SharedKeys.ticketGroups)

        let current = session()
        current.save(to: defaults, groupId: groupId)
        XCTAssertEqual(ShieldRebuildHelper.groupIdForUsageActivity(
            defaults: defaults, activityName: current.activityName(groupId: groupId)), groupId)
        XCTAssertNil(ShieldRebuildHelper.groupIdForUsageActivity(
            defaults: defaults, activityName: current.legacyActivityName(groupId: groupId)))
        XCTAssertNil(ShieldRebuildHelper.groupIdForUsageActivity(
            defaults: defaults, activityName: session().activityName(groupId: groupId)))
    }

    func testAccountRotationClosesPassUntilFreshMonitorIsRegistered() {
        let pass = session()
        pass.save(to: defaults, groupId: groupId)
        let outgoingEpoch = UsageBudgetAccountBoundary.epoch(in: defaults)

        let stoppedActivities = UsageBudgetAccountBoundary.suspend(defaults: defaults)

        XCTAssertTrue(stoppedActivities.contains(pass.activityName(groupId: groupId)))
        XCTAssertFalse(UsageBudgetAccountBoundary.accepts(outgoingEpoch, in: defaults))
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
        XCTAssertTrue(UsageBudgetSession.load(from: defaults, groupId: groupId)?.monitoringFailed == true)

        UsageBudgetAccountBoundary.resume(defaults: defaults)
        XCTAssertTrue(UsageBudgetAccountBoundary.accepts(UsageBudgetAccountBoundary.epoch(in: defaults), in: defaults))
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now),
                       "A stopped pass must stay shielded until its deadline monitor is recovered")
    }

    func testLegacyBalancesCannotRestoreAccessAfterMigration() {
        defaults.set(10, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(now.addingTimeInterval(60), forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        XCTAssertEqual(remaining(at: now), 0)
        XCTAssertFalse(ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId, at: now))
    }

    func testWidgetTimelineSchedulesRefreshAtPassExpiry() {
        let deadline = now.addingTimeInterval(30 * 60)
        XCTAssertEqual(ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(10 * 60), expiries: [deadline]), [])
        XCTAssertEqual(ShieldRebuildHelper.budgetObservationDates(from: now,
            through: now.addingTimeInterval(60 * 60), expiries: [deadline, deadline]), [deadline])
    }
}
