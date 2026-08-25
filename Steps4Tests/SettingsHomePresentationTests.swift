import SwiftUI
import XCTest
@testable import Steps4

final class SettingsHomePresentationTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testYourDaySummaryFormatsCurrentTargets() {
        let summary = SettingsYourDaySummary(
            stepsTarget: 10_000,
            sleepTargetHours: 8,
            dayEndHour: 0,
            dayEndMinute: 0
        )

        XCTAssertEqual(summary.stepsText(locale: enUS), "10,000")
        XCTAssertEqual(summary.sleepText(locale: enUS), "8 h")
        XCTAssertEqual(
            summary.dayStartText(locale: enUS, timeZone: utc)
                .replacingOccurrences(of: "\u{202F}", with: " "),
            "12:00 AM"
        )
    }

    func testYourDaySummaryClampsInvalidBoundaryComponents() {
        let summary = SettingsYourDaySummary(
            stepsTarget: -1,
            sleepTargetHours: -1,
            dayEndHour: 27,
            dayEndMinute: -4
        )

        XCTAssertEqual(summary.stepsTarget, 0)
        XCTAssertEqual(summary.sleepTargetHours, 0)
        XCTAssertEqual(summary.dayStartMinutes, 23 * 60)
    }

    func testAccountInitialsUseAtMostTwoWords() {
        XCTAssertEqual(SettingsAccountPresentation.initials(for: "Konstantin Pudan"), "KP")
        XCTAssertEqual(SettingsAccountPresentation.initials(for: "Konstantin"), "KO")
        XCTAssertEqual(SettingsAccountPresentation.initials(for: "  "), "U")
    }

    func testSignedInPresentationCarriesIdentityButNoSyncControl() {
        let state = SettingsAccountPresentation.signedIn(
            displayName: "Konstantin",
            initials: "KO",
            avatarData: nil
        )
        XCTAssertEqual(
            state,
            .signedIn(displayName: "Konstantin", initials: "KO", avatarData: nil)
        )
    }

    func testAccessibilityTypeUsesOneGridColumn() {
        XCTAssertEqual(SettingsGridLayout.columnCount(for: .large), 2)
        XCTAssertEqual(SettingsGridLayout.columnCount(for: .accessibility1), 1)
        XCTAssertEqual(SettingsGridLayout.columnCount(for: .accessibility5), 1)
    }

    func testAccessibilityTypeStacksYourDayMetrics() {
        XCTAssertFalse(SettingsYourDayLayout.stacksMetrics(for: .large))
        XCTAssertTrue(SettingsYourDayLayout.stacksMetrics(for: .accessibility1))
        XCTAssertTrue(SettingsYourDayLayout.stacksMetrics(for: .accessibility5))
    }

    func testSettingsCardCasingUsesTheCurrentLocaleRules() {
        let turkish = Locale(identifier: "tr_TR")

        XCTAssertEqual(SettingsLocalizedCasing.uppercase("izin", locale: turkish), "İZİN")
    }
}
