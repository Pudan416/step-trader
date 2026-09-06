import UserNotifications
import XCTest
@testable import Steps4

final class SettingsPermissionPresentationTests: XCTestCase {
    func testHealthWithoutReturnedDataIsNeutralNotMissing() {
        let state = SettingsPermissionPresentation.health(
            isAvailable: true,
            hasReturnedData: false
        )
        XCTAssertEqual(state.status, .checkAccess)
        XCTAssertFalse(state.contributesToWarning)
        XCTAssertEqual(state.action, .checkAccess)
    }

    func testSuccessfulZeroValueHealthQueryCountsAsConnected() {
        let state = SettingsPermissionPresentation.health(
            isAvailable: true,
            hasReturnedData: true
        )
        XCTAssertEqual(state.status, .connected)
        XCTAssertFalse(state.contributesToWarning)
        XCTAssertEqual(state.action, .openSystemSettings)
    }

    func testDeniedNotificationsAreKnownActionableIssue() {
        let state = SettingsPermissionPresentation.notifications(status: .denied, remindersEnabled: true)
        XCTAssertEqual(state.status, .offInSystemSettings)
        XCTAssertEqual(state.action, .openSystemSettings)
        XCTAssertTrue(state.contributesToWarning)
    }

    func testNotDeterminedNotificationsOfferPermissionRequest() {
        let state = SettingsPermissionPresentation.notifications(status: .notDetermined, remindersEnabled: true)
        XCTAssertEqual(state.status, .notRequested)
        XCTAssertEqual(state.action, .requestPermission)
        XCTAssertTrue(state.contributesToWarning)
    }

    func testDisabledRemindersDoNotWarnButKeepRecoveryAvailable() {
        for status: UNAuthorizationStatus in [.denied, .notDetermined] {
            let state = SettingsPermissionPresentation.notifications(status: status, remindersEnabled: false)
            XCTAssertFalse(state.contributesToWarning)
            XCTAssertNotNil(state.action)
        }
    }

    func testAllowedNotificationsNeverWarn() {
        for status: UNAuthorizationStatus in [.authorized, .provisional, .ephemeral] {
            XCTAssertFalse(SettingsPermissionPresentation.notifications(status: status, remindersEnabled: true).contributesToWarning)
        }
    }

    func testReminderPolicyUsesDefaultsAndEachStoredPreference() {
        let suite = "SettingsPermissionPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(SettingsPermissionPresentation.remindersEnabled(in: defaults))
        let keys = [SharedKeys.notifyOneMinBefore, SharedKeys.notifyWhenTimerOver,
                    SharedKeys.notifyCanvasReminder, SharedKeys.notifyDayResetWarning]
        for key in keys { defaults.set(false, forKey: key) }
        XCTAssertFalse(SettingsPermissionPresentation.remindersEnabled(in: defaults))
        for key in keys {
            defaults.set(true, forKey: key)
            XCTAssertTrue(SettingsPermissionPresentation.remindersEnabled(in: defaults))
            defaults.set(false, forKey: key)
        }
    }

    func testMissingScreenTimeIsKnownActionableIssue() {
        XCTAssertTrue(
            SettingsPermissionPresentation.screenTime(isAuthorized: false)
                .contributesToWarning
        )
    }

    func testUnavailableStatusUsesExplicitUnavailableCopy() {
        XCTAssertEqual(SettingsPermissionStatus.unavailable.displayText, "Unavailable")
    }

    func testHealthFailureUsesStableCopyAndRecoveryActions() {
        let failure = SettingsPermissionFailurePresentation.health

        XCTAssertEqual(failure.message, "We couldn't check Health access.")
        XCTAssertEqual(failure.actions, [.tryAgain, .openSettings])
    }

    func testNotificationFailureUsesStableCopyAndRecoveryActions() {
        let failure = SettingsPermissionFailurePresentation.notifications

        XCTAssertEqual(failure.message, "We couldn't allow notifications.")
        XCTAssertEqual(failure.actions, [.tryAgain, .openSettings])
    }

    func testScreenTimeFailureUsesStableCopyAndRecoveryActions() {
        let failure = SettingsPermissionFailurePresentation.screenTime

        XCTAssertEqual(failure.message, "We couldn't allow Screen Time access.")
        XCTAssertEqual(failure.actions, [.tryAgain, .openSettings])
    }
}
