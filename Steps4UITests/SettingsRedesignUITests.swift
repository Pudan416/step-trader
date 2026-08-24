import XCTest

final class SettingsRedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing", "ui-testing-settings",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
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
}
