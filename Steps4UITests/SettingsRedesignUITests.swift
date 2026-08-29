import XCTest

final class SettingsRedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchSettings(extraArguments: [String] = []) -> XCUIApplication {
        launchSettings(
            contentSizeCategory: "UICTContentSizeCategoryL",
            extraArguments: extraArguments
        )
    }

    private func launchSettings(
        contentSizeCategory: String,
        seedSettings: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        launchSettings(
            app,
            contentSizeCategory: contentSizeCategory,
            seedSettings: seedSettings,
            extraArguments: extraArguments
        )
        return app
    }

    private func launchSettings(
        _ app: XCUIApplication,
        contentSizeCategory: String = "UICTContentSizeCategoryL",
        seedSettings: Bool,
        extraArguments: [String] = []
    ) {
        app.launchArguments = ["ui-testing"]
        if seedSettings {
            app.launchArguments.append("ui-testing-settings")
        }
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", contentSizeCategory,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 10))
        app.buttons["tab_me"].tap()
        XCTAssertTrue(app.buttons["me_settings_button"].waitForExistence(timeout: 5))
        app.buttons["me_settings_button"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
    }

    private func launchTicketSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-ticket-settings",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["tab_feeds"].waitForExistence(timeout: 10))
        app.buttons["tab_feeds"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
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

    func testSettingsUsesVisibleCloseAndSystemBackNavigation() {
        let app = launchSettings()
        let close = app.buttons["settings.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        assertMinimumHitTarget(close)

        app.buttons["settings.yourDay"].tap()
        XCTAssertTrue(app.navigationBars["Your day"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
    }

    func testAppearanceHorizontalSwipeDoesNotDismissDestination() {
        let app = launchSettings()
        app.buttons["settings.destination.appearance"].tap()
        app.segmentedControls.buttons["Manual"].tap()
        let carousel = app.otherElements["settings.appearance.paletteCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 3))
        carousel.swipeLeft()
        carousel.swipeRight()
        XCTAssertTrue(app.navigationBars["Appearance"].exists)
    }

    func testAppearanceManualChoicesExposeSelectedStateAtAccessibilitySize() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
        app.buttons["settings.destination.appearance"].tap()
        app.segmentedControls.buttons["Manual"].tap()
        let selectedPalette = app.buttons.matching(
            NSPredicate(format: "value == 'Selected'")
        ).firstMatch
        XCTAssertTrue(selectedPalette.waitForExistence(timeout: 3))
        XCTAssertTrue(selectedPalette.isHittable)
    }

    func testNotificationsUsesGroupedDetailSurface() {
        let app = launchSettings()
        app.buttons["settings.destination.notifications"].tap()
        XCTAssertTrue(app.otherElements["settings.detail.background"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.notifications.accessWindow"].exists)
    }

    func testZeroHealthDataDoesNotProduceUrgentWarning() {
        let app = launchSettings(extraArguments: ["ui-testing-health-zero-success"])
        app.buttons["settings.destination.permissions"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Health not granted"].exists)
    }

    func testDeletingFeedRequiresConfirmation() {
        let app = launchTicketSettings()

        app.buttons["settings.feed.delete"].tap()
        let confirmation = app.sheets["Delete Study?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete Feed"].exists)

        app.otherElements["dismiss popup"].tap()

        XCTAssertFalse(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Study"].exists)
    }

    func testConfirmingFeedDeletionRemovesSeededFeed() {
        let app = launchTicketSettings()

        app.buttons["settings.feed.delete"].tap()
        XCTAssertTrue(app.sheets["Delete Study?"].waitForExistence(timeout: 3))
        app.buttons["Delete Feed"].tap()

        XCTAssertFalse(app.staticTexts["Study"].waitForExistence(timeout: 3))
    }

    func testDeniedNotificationsShowSystemRecoveryAction() {
        let app = launchSettings(extraArguments: ["ui-testing-notifications-denied"])
        app.buttons["settings.destination.notifications"].tap()
        XCTAssertTrue(app.staticTexts["Off in System Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    func testYourDayEditorsExposeContextualSemanticsAndMinimumHitTargets() {
        let app = launchSettings()
        app.buttons["settings.yourDay"].tap()

        let stepsAdjustable = app.otherElements["settings.yourDay.steps.adjustable"]
        XCTAssertTrue(stepsAdjustable.waitForExistence(timeout: 3))
        XCTAssertEqual(stepsAdjustable.label, "Daily Steps Goal")
        XCTAssertTrue(String(describing: stepsAdjustable.value).contains("10,000"))

        let stepsIncrement = app.buttons["settings.yourDay.steps.thousands.increment"]
        XCTAssertTrue(stepsIncrement.exists)
        XCTAssertEqual(stepsIncrement.label, "Increase daily steps goal by 1,000 steps")
        assertMinimumHitTarget(stepsIncrement)

        let sleepAdjustable = app.otherElements["settings.yourDay.sleep.adjustable"]
        XCTAssertTrue(sleepAdjustable.waitForExistence(timeout: 3))
        XCTAssertEqual(sleepAdjustable.label, "Sleep Goal")
        XCTAssertTrue(String(describing: sleepAdjustable.value).contains("8"))

        let sleepIncrement = app.buttons["settings.yourDay.sleep.increment"]
        XCTAssertTrue(sleepIncrement.exists)
        XCTAssertEqual(sleepIncrement.label, "Increase sleep goal")
        assertMinimumHitTarget(sleepIncrement)

        app.swipeUp()

        let hourAdjustable = app.otherElements["settings.yourDay.boundary.hour.adjustable"]
        let minuteAdjustable = app.otherElements["settings.yourDay.boundary.minute.adjustable"]
        XCTAssertTrue(hourAdjustable.waitForExistence(timeout: 3))
        XCTAssertTrue(minuteAdjustable.exists)
        XCTAssertEqual(hourAdjustable.label, "New day hour")
        XCTAssertEqual(minuteAdjustable.label, "New day minute")
        XCTAssertTrue(String(describing: hourAdjustable.value).contains("0"))
        XCTAssertTrue(String(describing: minuteAdjustable.value).contains("0"))

        for id in [
            "settings.yourDay.boundary.hour.increment",
            "settings.yourDay.boundary.hour.decrement",
            "settings.yourDay.boundary.minute.increment",
            "settings.yourDay.boundary.minute.decrement",
        ] {
            assertMinimumHitTarget(app.buttons[id])
        }
    }

    func testSignedOutYourDayEditsPersistAcrossOrdinaryRelaunch() {
        let app = launchSettings()
        XCTAssertEqual(app.buttons["settings.account"].label, "Sign in with Apple")
        app.buttons["settings.yourDay"].tap()

        let stepsIncrement = app.buttons["settings.yourDay.steps.thousands.increment"]
        XCTAssertTrue(stepsIncrement.waitForExistence(timeout: 3))
        stepsIncrement.tap()

        let sleepIncrement = app.buttons["settings.yourDay.sleep.increment"]
        XCTAssertTrue(sleepIncrement.waitForExistence(timeout: 3))
        sleepIncrement.tap()

        app.swipeUp()
        let hourIncrement = app.buttons["settings.yourDay.boundary.hour.increment"]
        let minuteIncrement = app.buttons["settings.yourDay.boundary.minute.increment"]
        XCTAssertTrue(hourIncrement.waitForExistence(timeout: 3))
        XCTAssertTrue(minuteIncrement.waitForExistence(timeout: 3))
        hourIncrement.tap()
        minuteIncrement.tap()

        let hourValue = app.otherElements["settings.yourDay.boundary.hour.adjustable"]
        let minuteValue = app.otherElements["settings.yourDay.boundary.minute.adjustable"]
        XCTAssertTrue(waitForValue("1", of: hourValue))
        XCTAssertTrue(waitForValue("15", of: minuteValue))

        // `AppModel.updateDayEnd` intentionally debounces for 350 ms. Wait past
        // that real production boundary before terminating; do not write the
        // app-group defaults from the test process.
        let dayBoundaryCommit = expectation(description: "Day boundary commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dayBoundaryCommit.fulfill()
        }
        wait(for: [dayBoundaryCommit], timeout: 1)

        app.terminate()
        launchSettings(app, seedSettings: false)

        XCTAssertEqual(app.buttons["settings.account"].label, "Sign in with Apple")
        app.buttons["settings.yourDay"].tap()

        let persistedSteps = app.otherElements["settings.yourDay.steps.adjustable"]
        XCTAssertTrue(persistedSteps.waitForExistence(timeout: 3))
        XCTAssertTrue(String(describing: persistedSteps.value).contains("11,000"))

        let persistedSleep = app.otherElements["settings.yourDay.sleep.adjustable"]
        XCTAssertTrue(persistedSleep.waitForExistence(timeout: 3))
        XCTAssertTrue(String(describing: persistedSleep.value).contains("8.5"))

        app.swipeUp()
        let persistedHour = app.otherElements["settings.yourDay.boundary.hour.adjustable"]
        let persistedMinute = app.otherElements["settings.yourDay.boundary.minute.adjustable"]
        XCTAssertTrue(waitForValue("1", of: persistedHour))
        XCTAssertTrue(persistedMinute.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue("15", of: persistedMinute))
    }

    func testCardHomePrioritizesAccountThenYourDay() {
        let app = launchSettings()
        let account = app.buttons["settings.account"]
        let yourDay = app.buttons["settings.yourDay"]

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.exists)
        XCTAssertLessThan(account.frame.minY, yourDay.frame.minY)
        XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)

        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]
        XCTAssertTrue(appearance.exists)
        XCTAssertTrue(notifications.exists)
        XCTAssertLessThan(appearance.frame.minX, notifications.frame.minX)
        XCTAssertEqual(appearance.frame.minY, notifications.frame.minY, accuracy: 2)

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

    func testCompactHomeKeepsTheHierarchyScannable() {
        let app = launchSettings()
        let account = app.buttons["settings.account"]
        let yourDay = app.buttons["settings.yourDay"]
        let appearance = app.buttons["settings.destination.appearance"]
        let appSettingsSection = app.staticTexts["settings.appSettings.section"]

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.exists)
        XCTAssertTrue(appearance.exists)
        XCTAssertTrue(appSettingsSection.exists)

        XCTAssertGreaterThanOrEqual(account.frame.height, 76)
        XCTAssertLessThanOrEqual(account.frame.height, 82)
        XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)
        XCTAssertLessThanOrEqual(yourDay.frame.height, 188)
        XCTAssertLessThanOrEqual(appearance.frame.height, 114)
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

        app.swipeUp()
        let widgets = app.buttons["settings.destination.widgetsWallpaper"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 3))
        XCTAssertEqual(widgets.label, "Widgets & wallpaper")
        XCTAssertGreaterThan(widgets.frame.width, 250)
        XCTAssertGreaterThanOrEqual(widgets.frame.height, 112)
    }

    func testGridUsesMeasuredDeviceWidth() {
        let app = launchSettings()
        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]

        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(notifications.exists)
        let minimumTwoColumnAppWidth: CGFloat = (2 * 164) + 12 + (2 * 20)
        if app.frame.width < minimumTwoColumnAppWidth {
            XCTAssertEqual(appearance.frame.minX, notifications.frame.minX, accuracy: 2)
            XCTAssertGreaterThan(notifications.frame.minY, appearance.frame.minY)
            XCTAssertGreaterThan(appearance.frame.width, 300)
        } else {
            XCTAssertLessThan(appearance.frame.minX, notifications.frame.minX)
            XCTAssertEqual(appearance.frame.minY, notifications.frame.minY, accuracy: 2)
        }
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

    private func assertMinimumHitTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
    }

    private func waitForValue(_ expected: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return String(describing: element.value).contains(expected)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}
