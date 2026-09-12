import XCTest

final class Steps4UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testMeCalendarAllButtonKeepsTheFullCalendarPresented() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing"]
        app.launch()

        let meTab = app.buttons["tab_me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        let allButton = app.buttons["me_archive_button"]
        XCTAssertTrue(allButton.waitForExistence(timeout: 8))
        allButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let calendarTitle = app.staticTexts["Calendar"]
        XCTAssertTrue(calendarTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(calendarTitle.isHittable)
        XCTAssertTrue(app.buttons["Previous month"].isHittable)
        XCTAssertFalse(app.buttons["tab_me"].isHittable)
        attachScreenshot(named: "me-full-calendar")
    }

    func testMeKeepsRecentDaysAboveTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
        ]
        app.launch()

        let meTab = app.buttons["tab_me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        let archive = app.buttons["me_archive_button"]
        XCTAssertTrue(archive.waitForExistence(timeout: 8))
        let settingsButton = app.buttons["me_settings_button"]
        XCTAssertTrue(settingsButton.exists)
        XCTAssertLessThan(
            settingsButton.frame.minY,
            archive.frame.minY,
            "Opening Me should keep the page header above the recent-days section"
        )

        let dayButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'me_calendar_day_'")
        )
        XCTAssertEqual(
            dayButtons.count,
            7,
            "The compact strip should expose only the latest seven days; older history belongs in All"
        )
        let dayFrames = (0..<dayButtons.count)
            .map { dayButtons.element(boundBy: $0).frame }
            .sorted { $0.minX < $1.minX }
        attachScreenshot(named: "me-layout-before-overlap-check")
        for (left, right) in zip(dayFrames, dayFrames.dropFirst()) {
            XCTAssertLessThan(
                left.midX,
                right.midX,
                "All seven calendar cards must retain distinct visual slots"
            )
        }
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(dayFrames.first).minX, app.frame.minX)
        XCTAssertLessThanOrEqual(try XCTUnwrap(dayFrames.last).maxX, app.frame.maxX)

        let poster = app.otherElements["me_selected_day_poster"]
        XCTAssertTrue(poster.waitForExistence(timeout: 3))
        let newestDay = try XCTUnwrap(poster.value as? String)

        poster.swipeRight()
        let movedToOlderDay = NSPredicate(format: "value != %@", newestDay)
        expectation(for: movedToOlderDay, evaluatedWith: poster)
        waitForExpectations(timeout: 3)
        let olderDay = try XCTUnwrap(poster.value as? String)
        XCTAssertNotEqual(olderDay, newestDay)

        poster.swipeLeft()
        let returnedToNewestDay = NSPredicate(format: "value == %@", newestDay)
        expectation(for: returnedToNewestDay, evaluatedWith: poster)
        waitForExpectations(timeout: 3)

        poster.swipeLeft()
        XCTAssertEqual(
            poster.value as? String,
            newestDay,
            "Swiping toward a newer day must stop on today"
        )
        let visibleBottom = (0..<dayButtons.count)
            .map { dayButtons.element(boundBy: $0) }
            .map { $0.frame.maxY }
            .max()
        let calendarBottom = try XCTUnwrap(visibleBottom)
        let calendarGap = meTab.frame.minY - calendarBottom
        XCTAssertGreaterThan(
            calendarGap,
            0,
            "Calendar should not sit underneath the floating tab bar"
        )
        XCTAssertLessThan(
            calendarGap,
            120,
            "Calendar should finish immediately above the floating tab bar"
        )
        attachScreenshot(named: "me-layout")
    }

    func testMeArchiveActionLivesInTheRecentDaysHeader() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing"]
        app.launch()

        let meTab = app.buttons["tab_me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        let archive = app.buttons["me_archive_button"]
        XCTAssertTrue(archive.waitForExistence(timeout: 8))

        let dayButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'me_calendar_day_'")
        )
        XCTAssertEqual(dayButtons.count, 7)
        let firstDay = dayButtons.element(boundBy: 0)
        XCTAssertTrue(firstDay.exists)
        XCTAssertLessThan(
            archive.frame.maxY,
            firstDay.frame.minY,
            "Archive should read as a lightweight action in the recent-days header, not as a second bar above the tab bar"
        )

        archive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Calendar"].waitForExistence(timeout: 3))
    }

    func testTask7FixRoundOneDefaultScreenshots() throws {
        let app = launchTask7App()
        openPalette(in: app)

        attachScreenshot(named: "task7-fix-r1-open-10")

        let firstHappening = app.buttons["Made something"]
        let energyPill = app.otherElements["canvas_energy_pill"]
        XCTAssertTrue(energyPill.exists)
        let energyFrameBeforePreview = energyPill.frame
        firstHappening.tap()
        XCTAssertTrue(firstHappening.exists, "The first tap must keep the happening as a preview")
        XCTAssertEqual(firstHappening.value as? String, "Preview. Tap again to add")
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(energyPill.frame, energyFrameBeforePreview)
        attachScreenshot(named: "task7-circle-preview")
        firstHappening.tap()
        XCTAssertTrue(firstHappening.waitForNonExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.6)
        let paletteClose = app.buttons["canvas_palette_close_button"]
        XCTAssertTrue(paletteClose.exists)
        attachScreenshot(named: "task7-fix-r1-open-9")

        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.staticTexts["Choose happenings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Search happenings"].exists)
        XCTAssertTrue(app.buttons["Add new happening"].exists)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r1-chooser")

        app.buttons["Add new happening"].tap()

        let creatorField = app.textFields["What happened?"]
        let addAction = app.buttons["Add to palette"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(creatorField.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add a happening"].exists)
        // The explanatory copy is intentionally hidden from the accessibility
        // tree because the heading exposes the same sentence as its hint.
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(addAction.exists)
        XCTAssertFalse(addAction.isEnabled)
        XCTAssertLessThanOrEqual(addAction.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r1-creator-keyboard-increased-contrast")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
    }

    func testTask7FixRoundOneAllUsedScreenshot() throws {
        let app = launchTask7App()
        openPalette(in: app)

        // The word field stays open while its available vocabulary shrinks.
        for title in task7BuiltInTitles {
            let label = app.buttons[title]
            XCTAssertTrue(label.waitForExistence(timeout: 3), "Missing palette label: \(title)")
            label.tap()
            XCTAssertTrue(label.exists, "First tap should preview \(title)")
            label.tap()
            XCTAssertTrue(label.waitForNonExistence(timeout: 3), "Label did not leave field: \(title)")
            XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable, "Palette closed after picking \(title)")
        }

        XCTAssertTrue(app.staticTexts["All added for today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_palette_list_button"].isHittable)
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
        XCTAssertTrue(app.buttons["tab_canvas"].isHittable)
        attachScreenshot(named: "task7-fix-r1-all-used")
    }

    func testTask7FixRoundTwoAllUsedScreenshot() throws {
        let app = launchTask7App()
        openPalette(in: app)

        // The word field stays open while its available vocabulary shrinks.
        for title in task7BuiltInTitles {
            let label = app.buttons[title]
            XCTAssertTrue(label.waitForExistence(timeout: 3), "Missing palette label: \(title)")
            label.tap()
            XCTAssertTrue(label.exists, "First tap should preview \(title)")
            label.tap()
            XCTAssertTrue(label.waitForNonExistence(timeout: 3), "Label did not leave field: \(title)")
            XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable, "Palette closed after picking \(title)")
        }

        XCTAssertTrue(app.staticTexts["All added for today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_palette_list_button"].isHittable)
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
        attachScreenshot(named: "task7-fix-r2-all-used")
    }

    func testTask7FixRoundOneDynamicTypeScreenshot() throws {
        let app = launchTask7App()
        openPalette(in: app)

        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full primary label: \(title)")
        }
        attachScreenshot(named: "task7-fix-r1-dynamic-type-open-10")

        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Cancel"].tap()

        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.buttons["Add new happening"].waitForExistence(timeout: 3))
        app.buttons["Add new happening"].tap()
        XCTAssertTrue(app.textFields["What happened?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(app.buttons["Add to palette"].exists)
    }

    func testTask7FixRoundThreeAccessibilityDynamicTypeScreenshot() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility1")
        let configuration = app.otherElements["task7_accessibility_configuration"]

        XCTAssertTrue(configuration.waitForExistence(timeout: 8))
        XCTAssertEqual(configuration.value as? String, "accessibility1,standard-contrast")
        openPalette(in: app)

        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full accessibility label: \(title)")
        }
        XCTAssertTrue(app.buttons["canvas_palette_list_button"].isHittable)
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)

        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Cancel"].tap()

        attachScreenshot(named: "task7-fix-r3-dynamic-type-open-10")
    }

    func testTask7FixRoundThreeIncreasedContrastCreatorDismissesKeyboardInteractively() throws {
        let app = launchTask7App(
            dynamicTypeSize: "accessibility1",
            increasedContrast: true
        )
        let configuration = app.otherElements["task7_accessibility_configuration"]

        XCTAssertTrue(configuration.waitForExistence(timeout: 8))
        XCTAssertEqual(configuration.value as? String, "accessibility1,increased-contrast")
        openPalette(in: app)
        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.buttons["Add new happening"].waitForExistence(timeout: 3))
        app.buttons["Add new happening"].tap()

        let creatorField = app.textFields["What happened?"]
        let addAction = app.buttons["Add to palette"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(creatorField.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add a happening"].exists)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(addAction.exists)
        XCTAssertFalse(addAction.isEnabled)
        XCTAssertLessThanOrEqual(addAction.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r3-creator-keyboard-accessibility-increased-contrast")

        let creatorScroll = app.scrollViews["happening_creator_scroll"]
        XCTAssertTrue(creatorScroll.exists)
        let dragStart = creatorScroll.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)
        )
        let dragEnd = creatorScroll.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)
        )
        dragStart.press(forDuration: 0.15, thenDragTo: dragEnd)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(addAction.exists)
    }

    func testTask7FixRoundFourAccessibilityDynamicTypeContourScreenshot() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility1")
        let configuration = app.otherElements["task7_accessibility_configuration"]

        XCTAssertTrue(configuration.waitForExistence(timeout: 8))
        XCTAssertEqual(configuration.value as? String, "accessibility1,standard-contrast")
        openPalette(in: app)

        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full accessibility label: \(title)")
        }
        XCTAssertTrue(app.buttons["canvas_palette_list_button"].isHittable)
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
        attachScreenshot(named: "task7-fix-r4-dynamic-type-open-10")
    }

    func testTask7FixRoundFourCreatorUsesComfortableVerticalActions() throws {
        let app = launchTask7App(
            dynamicTypeSize: "accessibility1",
            increasedContrast: true
        )
        let configuration = app.otherElements["task7_accessibility_configuration"]

        XCTAssertTrue(configuration.waitForExistence(timeout: 8))
        XCTAssertEqual(configuration.value as? String, "accessibility1,increased-contrast")
        openPalette(in: app)
        app.buttons["canvas_palette_list_button"].tap()
        XCTAssertTrue(app.buttons["Add new happening"].waitForExistence(timeout: 3))
        app.buttons["Add new happening"].tap()

        let creatorField = app.textFields["What happened?"]
        let cancelAction = app.buttons["Cancel"]
        let addAction = app.buttons["Add to palette"]
        let creatorScroll = app.scrollViews["happening_creator_scroll"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(creatorField.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertTrue(cancelAction.isHittable)
        XCTAssertTrue(addAction.exists)
        XCTAssertFalse(addAction.isEnabled)
        XCTAssertGreaterThanOrEqual(cancelAction.frame.width, creatorField.frame.width - 4)
        XCTAssertGreaterThanOrEqual(addAction.frame.width, creatorField.frame.width - 4)
        XCTAssertLessThan(cancelAction.frame.maxY, addAction.frame.minY)
        XCTAssertLessThanOrEqual(
            addAction.frame.maxY,
            creatorScroll.frame.maxY - 12,
            "the primary action needs visible breathing room inside the creator card"
        )
        XCTAssertLessThanOrEqual(addAction.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r4-creator-keyboard-accessibility-increased-contrast")
    }

    private var task7BuiltInTitles: [String] {
        [
            "Walk",
            "Workout",
            "Slept well",
            "Called someone",
            "Drinks together",
            "Read",
            "Laughed",
            "Made something",
            "Time outside",
            "Did nothing",
        ]
    }

    /// Shape assignments now appear only after a deliberate first tap, so the
    /// old shake gesture has no affordance and must not disturb the field.
    func testLegacyShakeFixtureLeavesTheWordFieldIntact() throws {
        let app = launchTask7App(shakeTrigger: true)
        openPalette(in: app)

        XCTAssertFalse(app.staticTexts["Shake to change the shapes"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing word before shake: \(title)")
        }

        // The fixture shakes the palette 1.2s after it appears — nothing to
        // tap, because a tap anywhere over the field reaches the dismissing
        // backdrop and closes the palette instead.
        Thread.sleep(forTimeInterval: 3)

        // Dock first: if the palette closed, the words being gone says nothing
        // about whether the obsolete fixture was safely ignored.
        XCTAssertTrue(app.buttons["canvas_palette_list_button"].isHittable, "Palette closed")
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
        XCTAssertFalse(app.staticTexts["Shake to change the shapes"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Word lost on shake: \(title)")
        }
        attachScreenshot(named: "palette-words-after-shake")
    }

    private func launchTask7App(
        dynamicTypeSize: String? = nil,
        increasedContrast: Bool = false,
        shakeTrigger: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-task7",
            "-uiLab", "none",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        if let dynamicTypeSize {
            app.launchEnvironment["TASK7_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityM",
            ]
        } else {
            // Simulator accessibility preferences persist between tests. Pin
            // the default fixture so its screenshots do not accidentally use
            // the previous accessibility run's expanded two-column layout.
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryL",
            ]
        }
        if shakeTrigger {
            app.launchEnvironment["TASK7_SHAKE_PALETTE"] = "1"
        }
        if increasedContrast {
            app.launchEnvironment["TASK7_INCREASED_CONTRAST"] = "1"
            app.launchArguments += [
                "-UIAccessibilityDarkerSystemColorsEnabled",
                "YES",
            ]
        }
        app.launch()
        return app
    }

    private func openPalette(in app: XCUIApplication) {
        let addHappening = app.buttons["Add happening"]
        XCTAssertTrue(addHappening.waitForExistence(timeout: 8))
        addHappening.tap()
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
