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
        XCTAssertNil(state.action)
    }

    func testDeniedNotificationsAreKnownActionableIssue() {
        let state = SettingsPermissionPresentation.notifications(status: .denied)
        XCTAssertEqual(state.status, .offInSystemSettings)
        XCTAssertEqual(state.action, .openSystemSettings)
        XCTAssertTrue(state.contributesToWarning)
    }

    func testNotDeterminedNotificationsOfferPermissionRequest() {
        let state = SettingsPermissionPresentation.notifications(status: .notDetermined)
        XCTAssertEqual(state.status, .notRequested)
        XCTAssertEqual(state.action, .requestPermission)
        XCTAssertTrue(state.contributesToWarning)
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
