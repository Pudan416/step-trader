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

    func testTask7FixRoundOneDefaultScreenshots() throws {
        let app = launchTask7App()
        openPalette(in: app)

        attachScreenshot(named: "task7-fix-r1-open-10")

        app.buttons["Choose happenings"].tap()
        XCTAssertTrue(app.staticTexts["Choose happenings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Search happenings"].exists)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r1-chooser")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Add a happening"].waitForExistence(timeout: 3))
        app.buttons["Add a happening"].tap()

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

        // Picking closes the palette, so each happening needs it opened again.
        // That is the behaviour, not a workaround: one tap logs one thing and
        // hands the canvas back.
        for title in task7BuiltInTitles {
            let label = app.buttons[title]
            XCTAssertTrue(label.waitForExistence(timeout: 3), "Missing palette label: \(title)")
            label.tap()
            XCTAssertTrue(label.waitForNonExistence(timeout: 3), "Label did not leave field: \(title)")
            openPalette(in: app)
        }

        XCTAssertTrue(app.staticTexts["All added for today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)
        attachScreenshot(named: "task7-fix-r1-all-used")
    }

    func testTask7FixRoundTwoAllUsedScreenshot() throws {
        let app = launchTask7App()
        openPalette(in: app)

        // Picking closes the palette, so each happening needs it opened again.
        // That is the behaviour, not a workaround: one tap logs one thing and
        // hands the canvas back.
        for title in task7BuiltInTitles {
            let label = app.buttons[title]
            XCTAssertTrue(label.waitForExistence(timeout: 3), "Missing palette label: \(title)")
            label.tap()
            XCTAssertTrue(label.waitForNonExistence(timeout: 3), "Label did not leave field: \(title)")
            openPalette(in: app)
        }

        XCTAssertTrue(app.staticTexts["All added for today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)
        attachScreenshot(named: "task7-fix-r2-all-used")
    }

    func testTask7FixRoundOneDynamicTypeScreenshot() throws {
        let app = launchTask7App()
        openPalette(in: app)

        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full primary label: \(title)")
        }
        attachScreenshot(named: "task7-fix-r1-dynamic-type-open-10")

        app.buttons["Choose happenings"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Cancel"].tap()

        app.buttons["Add a happening"].tap()
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

        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full accessibility label: \(title)")
        }
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)

        app.buttons["Choose happenings"].tap()
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
        app.buttons["Add a happening"].tap()

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
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
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

        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing full accessibility label: \(title)")
        }
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)
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
        app.buttons["Add a happening"].tap()

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
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        attachScreenshot(named: "task7-fix-r4-creator-keyboard-accessibility-increased-contrast")
    }

    private var task7BuiltInTitles: [String] {
        [
            "Walk",
            "Workout",
            "Slept well",
            "Called someone I love",
            "Drinks with friends",
            "Read",
            "Laughed",
            "Made something",
            "Time outside",
            "Did nothing on purpose",
        ]
    }

    /// Shake changes the figures without disturbing anything around them.
    ///
    /// What a UI test can see is structure, not silhouettes: the ten tiles
    /// survive, the dock still has exactly its three buttons, and the hint is
    /// on screen. That the figures actually changed is a thing for eyes.
    func testShakeKeepsTheFieldAndTheDockIntact() throws {
        let app = launchTask7App(shakeTrigger: true)
        openPalette(in: app)

        XCTAssertTrue(app.staticTexts["Shake to change the shapes"].exists)
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing tile before shake: \(title)")
        }

        // The fixture shakes the palette 1.2s after it appears — nothing to
        // tap, because a tap anywhere over the field reaches the dismissing
        // backdrop and closes the palette instead.
        Thread.sleep(forTimeInterval: 3)

        // Dock first: if the palette closed instead of re-rolling, the tiles
        // being gone says nothing about the shake.
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable, "Palette closed")
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)
        XCTAssertTrue(app.staticTexts["Shake to change the shapes"].exists, "Hint gone")
        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Tile lost on shake: \(title)")
        }
        attachScreenshot(named: "palette-shapes-after-shake")
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
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        if let dynamicTypeSize {
            app.launchEnvironment["TASK7_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityM",
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
        // The dock, not a happening: once one has been picked it never comes
        // back, and the palette is just as open without it.
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
