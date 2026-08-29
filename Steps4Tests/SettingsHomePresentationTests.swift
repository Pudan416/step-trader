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

    func testAccountInitialsUseTurkishLocaleRules() {
        let turkish = Locale(identifier: "tr_TR")

        XCTAssertEqual(
            SettingsAccountPresentation.initials(for: "ipek öz", locale: turkish),
            "İÖ"
        )
        XCTAssertEqual(
            SettingsAccountPresentation.initials(for: "izin", locale: turkish),
            "İZ"
        )
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

    func testAccountFailuresUseStableRecoveryCopy() {
        XCTAssertEqual(
            SettingsAccountFailurePresentation.message(for: .deletion),
            "We couldn't delete your account. Check your connection and try again."
        )
        XCTAssertEqual(
            SettingsAccountFailurePresentation.message(for: .profileSaving),
            "We couldn't save your profile. Your previous details are still intact."
        )
        XCTAssertEqual(
            SettingsAccountFailurePresentation.message(for: .other),
            "Something went wrong. Please try again."
        )
    }

    func testNormalIPhone17ContentWidthUsesTwoGridColumns() {
        let contentWidth: CGFloat = 402 - (2 * 24)

        XCTAssertEqual(
            SettingsGridLayout.columnCount(
                for: .large,
                availableWidth: contentWidth
            ),
            2
        )
        XCTAssertGreaterThanOrEqual(
            SettingsGridLayout.cardWidth(
                availableWidth: contentWidth,
                columnCount: 2
            ),
            SettingsGridLayout.minimumCardWidth
        )
    }

    func testNarrowWidthCollapsesLongTitleCardsToOneReadableColumn() {
        let narrowContentWidth: CGFloat = 375 - (2 * 24)

        XCTAssertEqual(
            SettingsGridLayout.columnCount(
                for: .large,
                availableWidth: narrowContentWidth
            ),
            1
        )
        XCTAssertEqual(
            SettingsGridLayout.cardWidth(
                availableWidth: narrowContentWidth,
                columnCount: 1
            ),
            narrowContentWidth
        )
        XCTAssertGreaterThan(
            SettingsGridLayout.cardWidth(
                availableWidth: narrowContentWidth,
                columnCount: 1
            ),
            SettingsGridLayout.minimumCardWidth
        )
    }

    func testAccessibilityTypeUsesOneGridColumnAtWideWidth() {
        XCTAssertEqual(
            SettingsGridLayout.columnCount(
                for: .accessibility1,
                availableWidth: 1_000
            ),
            1
        )
        XCTAssertEqual(
            SettingsGridLayout.columnCount(
                for: .accessibility5,
                availableWidth: 1_000
            ),
            1
        )
    }

    func testCardPresentationTokensMeetWCAGAgainstWhiteWorstCaseBackground() {
        let measurement = SettingsCardContrast.measure(
            over: .init(red: 1, green: 1, blue: 1)
        )

        XCTAssertGreaterThanOrEqual(measurement.captionToSurface, 4.5)
        XCTAssertGreaterThanOrEqual(measurement.outlineToSurface, 3.0)
        XCTAssertGreaterThanOrEqual(measurement.surfaceToBackground, 3.0)
    }

    func testAccessibilityTypeStacksYourDayMetrics() {
        XCTAssertFalse(SettingsYourDayLayout.stacksMetrics(for: .large))
        XCTAssertTrue(SettingsYourDayLayout.stacksMetrics(for: .accessibility1))
        XCTAssertTrue(SettingsYourDayLayout.stacksMetrics(for: .accessibility5))
    }

    func testSettingsSharedCasingUsesTurkishLocaleRules() {
        let turkish = Locale(identifier: "tr_TR")

        XCTAssertEqual(SettingsLocalizedCasing.uppercase("izin", locale: turkish), "İZİN")
    }

    func testAppearanceModeMapsToExistingBooleanWithoutMigration() {
        XCTAssertEqual(SettingsAppearanceMode(dailyRandomEnabled: true), .automatic)
        XCTAssertEqual(SettingsAppearanceMode(dailyRandomEnabled: false), .manual)
        XCTAssertTrue(SettingsAppearanceMode.automatic.dailyRandomEnabled)
        XCTAssertFalse(SettingsAppearanceMode.manual.dailyRandomEnabled)
    }
}
