import XCTest

final class SettingsRedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSettings() -> XCUIApplication {
        launchSettings(contentSizeCategory: "UICTContentSizeCategoryL")
    }

    private func launchSettings(contentSizeCategory: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing", "ui-testing-settings",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", contentSizeCategory
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 10))
        app.buttons["tab_me"].tap()
        XCTAssertTrue(app.buttons["me_settings_button"].waitForExistence(timeout: 5))
        app.buttons["me_settings_button"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        return app
    }

    func testYourDayIsAvailableWithoutOpeningLogin() {
        let app = launchSettings()

        let yourDay = app.buttons["settings.yourDay"]
        XCTAssertTrue(yourDay.waitForExistence(timeout: 3))
        yourDay.tap()

        XCTAssertTrue(app.staticTexts["Your day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.yourDay.steps"].exists)
        XCTAssertTrue(app.otherElements["settings.yourDay.sleep"].exists)
        XCTAssertTrue(app.otherElements["settings.yourDay.boundary"].exists)
        XCTAssertFalse(app.staticTexts["Sign in to continue"].exists)
    }

    func testCardHomePrioritizesAccountThenYourDay() {
        let app = launchSettings()
        let account = app.buttons["settings.account"]
        let yourDay = app.buttons["settings.yourDay"]

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.exists)
        XCTAssertLessThan(account.frame.minY, yourDay.frame.minY)
        XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)

        for id in [
            "settings.destination.appearance",
            "settings.destination.notifications",
            "settings.destination.permissions",
            "settings.destination.widgetsWallpaper",
            "settings.destination.notes",
            "settings.destination.about",
        ] {
            XCTAssertTrue(app.buttons[id].exists, "Missing Settings destination: \(id)")
        }
    }

    func testAccessibilityTypeKeepsDestinationCardsReadable() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]

        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(notifications.exists)
        XCTAssertEqual(appearance.frame.minX, notifications.frame.minX, accuracy: 2)
        XCTAssertGreaterThan(notifications.frame.minY, appearance.frame.minY)
        XCTAssertTrue(appearance.isHittable)
        XCTAssertTrue(notifications.isHittable)
    }

    func testWidgetsAndWallpaperShareOneDetailPage() {
        let app = launchSettings()
        let combined = app.buttons["settings.destination.widgetsWallpaper"]
        XCTAssertTrue(combined.waitForExistence(timeout: 3))
        combined.tap()

        XCTAssertTrue(app.staticTexts["Widgets & wallpaper"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.widgets.controls"].exists)
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings.wallpaper.controls"].exists)
    }

    func testDeveloperDiagnosticsHaveOneDestination() {
        let app = launchSettings()

        let developer = app.buttons["settings.destination.developer"]
        XCTAssertTrue(developer.exists)
        developer.tap()
        XCTAssertTrue(app.staticTexts["Developer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Copy Shield Diagnostics"].exists)
    }
}
