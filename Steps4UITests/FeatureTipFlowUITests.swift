import XCTest

final class FeatureTipFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchTip(_ tip: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing", "ui-testing-feature-tips", "ui-testing-me-static-poster",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-uiLab", "none", "-hasWallpaperShortcut", "NO",
            "-onboarding_state_v1", "1", "-appLaunchCount", "20",
            "-hasRequestedReview_v1", "YES", "-shouldStartCoachMark", "NO",
            // Argument-domain values isolate scheduling from the previous run's
            // defaults. Persistence is exercised by FeatureTipPolicyTests.
            "-featureTipHistory_v2_widgets", "fresh",
            "-featureTipHistory_v2_wallpaper", "fresh",
            "-featureTipLastPrompt_v2", "fresh",
            "-featureTipSeen_widgets_v1", tip == "widgets" ? "NO" : "YES",
            "-featureTipSeen_wallpaper_v1", tip == "wallpaper" ? "NO" : "YES",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["featureTip.continue"].waitForExistence(timeout: 20), app.debugDescription)
        return app
    }

    func testWidgetTipOpensWidgetSettingsFromCanvas() {
        let app = launchTip("widgets")
        app.buttons["featureTip.continue"].tap()
        XCTAssertTrue(app.buttons["settings.widgets.install"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["settings.wallpaper.install"].exists)
        app.buttons["settings.widgets.install"].tap()
        XCTAssertTrue(app.staticTexts["Home Screen → Edit → Add Widget → Nowhere"].waitForExistence(timeout: 5))
    }

    func testWallpaperTipOpensWallpaperSettingsFromCanvas() {
        let app = launchTip("wallpaper")
        app.buttons["featureTip.continue"].tap()
        XCTAssertTrue(app.buttons["settings.wallpaper.install"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["settings.widgets.install"].exists)
    }

    func testSwipeDismissalReturnsToCanvasWithoutOpeningSettings() {
        let app = launchTip("wallpaper")
        let sheet = app.otherElements["featureTip.sheet"]
        XCTAssertTrue(sheet.exists)
        sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(forDuration: 0.1, thenDragTo:
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(app.buttons["featureTip.continue"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.wallpaper.install"].exists)
    }

    func testMaybeLaterReturnsToCanvasWithoutOpeningSettingsOrAnotherTip() {
        let app = launchTip("widgets")
        app.buttons["featureTip.later"].tap()
        XCTAssertTrue(app.buttons["featureTip.continue"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.widgets.install"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.buttons["featureTip.continue"].waitForExistence(timeout: 3))
    }
}
