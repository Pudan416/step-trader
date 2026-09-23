import XCTest
import UIKit

final class NowhereUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSingleScreenFeedRequiresAppsAndCancelKeepsGroups() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_feeds"].waitForExistence(timeout: 10))
        app.buttons["tab_feeds"].tap()
        let groups = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.' AND identifier ENDSWITH '.access'"))
        let initialCount = groups.count
        app.buttons["feed.add"].tap()
        let name = app.textFields["feed.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let done = app.buttons["feed.selection.create"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.label, "Done")
        XCTAssertFalse(done.isEnabled)
        XCTAssertFalse(app.buttons["feed.name.next"].exists)
        attachScreenshot(named: "single-screen-feed-empty")
        name.tap()
        name.typeText("No apps yet\n")
        XCTAssertTrue(name.exists)
        XCTAssertFalse(done.isEnabled)
        app.buttons["feed.selection.cancel"].tap()
        XCTAssertTrue(app.buttons["feed.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(groups.count, initialCount)
    }

    func testSingleScreenFeedRequiresNameAndCancelKeepsGroups() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
            "ui-testing-feed-selection"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_feeds"].waitForExistence(timeout: 10))
        app.buttons["tab_feeds"].tap()
        let groups = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.' AND identifier ENDSWITH '.access'"))
        let initialCount = groups.count
        app.buttons["feed.add"].tap()
        let name = app.textFields["feed.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let done = app.buttons["feed.selection.create"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(done.isEnabled)
        name.tap()
        name.typeText("   ")
        XCTAssertFalse(done.isEnabled)
        name.typeText("Focus\n")
        XCTAssertTrue(done.isEnabled)
        XCTAssertTrue(name.isHittable)
        XCTAssertTrue(done.isHittable)
        XCTAssertFalse(app.buttons["feed.name.next"].exists)
        attachScreenshot(named: "single-screen-feed-light-large")
        app.buttons["feed.selection.cancel"].tap()
        XCTAssertTrue(app.buttons["feed.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(groups.count, initialCount)
    }

    func testCreatingFeedPersistsRequiredName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "ui-testing-feed-selection"]
        app.launch()
        XCTAssertTrue(app.buttons["tab_feeds"].waitForExistence(timeout: 10))
        app.buttons["tab_feeds"].tap()
        app.buttons["feed.add"].tap()
        let name = app.textFields["feed.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("  Named feed  ")
        let done = app.buttons["feed.selection.create"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isEnabled)
        done.tap()
        XCTAssertTrue(app.buttons["feed.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.' AND identifier ENDSWITH '.access' AND label CONTAINS 'Named feed'")).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(named: "single-screen-feed-created")
        app.terminate()
        app.launch()
        app.buttons["tab_feeds"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'feed.' AND identifier ENDSWITH '.access' AND label CONTAINS 'Named feed'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testCalmPaletteAndSmokedChromeAppearances() throws {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["ui-testing", "ui-testing-task7", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", appearance, "-appTheme", appearance == "Light" ? "daylight" : "night"]
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.buttons["tab_canvas"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
            attachScreenshot(named: "smoked-canvas-\(appearance)")
            openPalette(in: app)
            let walk = app.buttons["happening_choice_happening_walk"]
            XCTAssertTrue(walk.waitForExistence(timeout: 5))
            attachScreenshot(named: "neutral-picker-\(appearance)")
            walk.tap()
            XCTAssertEqual(walk.value as? String, "Previewing addition to Canvas")
            attachScreenshot(named: "revealed-picker-\(appearance)")
            walk.tap()
            XCTAssertEqual(walk.value as? String, "On Canvas")
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 5))
            app.buttons["tab_me"].tap()
            XCTAssertTrue(app.buttons["me_archive_button"].waitForExistence(timeout: 8))
            attachScreenshot(named: "smoked-me-\(appearance)")
            app.buttons["tab_feeds"].tap()
            XCTAssertTrue(app.staticTexts["Feeds"].waitForExistence(timeout: 5))
            attachScreenshot(named: "frost-feeds-\(appearance)")
            app.terminate()
        }
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

        let posterCarousel = app.descendants(matching: .any)["me_poster_carousel"]
        XCTAssertTrue(posterCarousel.waitForExistence(timeout: 3))
        let newestDay = try XCTUnwrap(posterCarousel.value as? String)

        posterCarousel.swipeRight()
        let movedToOlderDay = NSPredicate(format: "value != %@", newestDay)
        expectation(for: movedToOlderDay, evaluatedWith: posterCarousel)
        waitForExpectations(timeout: 3)
        let olderDay = try XCTUnwrap(posterCarousel.value as? String)
        XCTAssertNotEqual(olderDay, newestDay)

        posterCarousel.swipeLeft()
        let returnedToNewestDay = NSPredicate(format: "value == %@", newestDay)
        expectation(for: returnedToNewestDay, evaluatedWith: posterCarousel)
        waitForExpectations(timeout: 3)

        posterCarousel.swipeLeft()
        XCTAssertEqual(
            posterCarousel.value as? String,
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

    func testTappingCalendarDayCentersTheWholeSelectedPoster() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()

        let meTab = app.buttons["tab_me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        let dayButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'me_calendar_day_'")
        )
        XCTAssertEqual(dayButtons.count, 7)
        let targetDay = dayButtons.allElementsBoundByAccessibilityElement
            .sorted { $0.frame.minX < $1.frame.minX }[3]
        let targetKey = targetDay.identifier.replacingOccurrences(
            of: "me_calendar_day_",
            with: ""
        )

        attachScreenshot(named: "me-before-calendar-selection")
        targetDay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let carousel = app.descendants(matching: .any)["me_poster_carousel"]
        attachScreenshot(named: "me-after-calendar-selection")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "me-after-calendar-selection-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let selectedValue = NSPredicate(format: "value == %@", targetKey)
        expectation(for: selectedValue, evaluatedWith: carousel)
        waitForExpectations(timeout: 3)

        let selectedPoster = app.otherElements.matching(
            NSPredicate(
                format: "identifier == 'me_selected_day_poster' AND value == %@",
                targetKey
            )
        ).firstMatch
        XCTAssertTrue(selectedPoster.waitForExistence(timeout: 3))
        XCTAssertEqual(
            selectedPoster.frame.midX,
            carousel.frame.midX,
            accuracy: 2,
            "Calendar selection must settle on one centered poster, not between two pages"
        )
        XCTAssertGreaterThanOrEqual(selectedPoster.frame.minX, carousel.frame.minX)
        XCTAssertLessThanOrEqual(selectedPoster.frame.maxX, carousel.frame.maxX)
        attachScreenshot(named: "me-calendar-selection-centered")
    }

    func testMePosterArtworkStaysFrozenAfterOpening() throws {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "ui-testing-me-static-poster"]
        app.launch()

        let meTab = app.buttons["tab_me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 8))
        meTab.tap()

        let carousel = app.descendants(matching: .any)["me_poster_carousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 5))
        let todayKey = try XCTUnwrap(carousel.value as? String)
        let poster = app.otherElements.matching(
            NSPredicate(
                format: "identifier == 'me_selected_day_poster' AND value == %@",
                todayKey
            )
        ).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 5))

        sleep(1)
        let firstFrame = poster.screenshot().pngRepresentation
        sleep(2)
        let secondFrame = poster.screenshot().pngRepresentation

        XCTAssertEqual(
            firstFrame,
            secondFrame,
            "A Me poster must keep one saved artwork frame instead of replaying Canvas animation"
        )
        attachScreenshot(named: "me-static-poster")
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

        attachScreenshot(named: "me-daily-accent")
        archive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Calendar"].waitForExistence(timeout: 3))
        attachScreenshot(named: "archive-daily-accent")
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
            "Connected",
            "Time together",
            "Read",
            "Laughed",
            "Made something",
            "Time outside",
            "Rested",
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

    func testHappeningMenuStatesAndReopening() throws {
        let app = launchTask7App()
        openPalette(in: app)
        scrollPaletteToStart(in: app)
        let walk = app.buttons["happening_choice_happening_walk"]
        let workout = app.buttons["happening_choice_happening_workout"]
        XCTAssertEqual(walk.value as? String, "Available")
        attachScreenshot(named: "menu-1-available")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Previewing addition to Canvas")
        workout.tap()
        XCTAssertEqual(walk.value as? String, "Available")
        XCTAssertEqual(workout.value as? String, "Previewing addition to Canvas")
        walk.tap()
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(named: "menu-2-preview")
        Thread.sleep(forTimeInterval: 3) // Retain a visible pulse cycle for simulator capture.
        walk.tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        for id in ["workout", "slept_well"] {
            let item = app.buttons["happening_choice_happening_\(id)"]
            item.tap(); item.tap()
            XCTAssertEqual(item.value as? String, "On Canvas")
        }
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(named: "menu-3-added-color")
        app.buttons["Close"].tap()
        openPalette(in: app)
        scrollPaletteToStart(in: app)
        XCTAssertEqual(walk.value as? String, "On Canvas")
        XCTAssertEqual(workout.value as? String, "On Canvas")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Previewing removal from Canvas")
        XCTAssertTrue(walk.staticTexts["Delete"].exists)
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(named: "menu-4-removal-preview")
        Thread.sleep(forTimeInterval: 3)
        app.buttons["Close"].tap()
        openPalette(in: app)
        scrollPaletteToStart(in: app)
        XCTAssertEqual(walk.value as? String, "On Canvas")
        // Leave no additions for a subsequent hosted unit-test launch to recover.
        for id in ["walk", "workout", "slept_well"] {
            let item = app.buttons["happening_choice_happening_\(id)"]
            item.tap(); item.tap()
            XCTAssertEqual(item.value as? String, "Available")
        }
        app.buttons["Close"].tap()
    }

    func testHappeningPaletteToggleFlow() throws {
        let app = launchTask7App()
        openPalette(in: app)
        scrollPaletteToStart(in: app)
        let walk = app.buttons["happening_choice_happening_walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        walk.tap()
        XCTAssertTrue(walk.staticTexts["Add"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Tap again to add to Canvas"].exists)
        XCTAssertEqual(walk.value as? String, "Previewing addition to Canvas")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        XCTAssertFalse(app.staticTexts["On Canvas"].exists)
        XCTAssertFalse(walk.staticTexts["Add"].exists)
        XCTAssertFalse(app.otherElements["happening_status_added_happening_walk"].exists)
        assertPersistentPaletteChrome(in: app)
        walk.tap()
        XCTAssertTrue(walk.staticTexts["Delete"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Tap again to remove from Canvas"].exists)
        XCTAssertEqual(walk.value as? String, "Previewing removal from Canvas")
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Available")
        XCTAssertTrue(walk.exists)
        assertPersistentPaletteChrome(in: app)
    }

    private func assertPersistentPaletteChrome(in app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'")).count, 30)
        for id in [
            "walk", "workout", "slept_well", "called_someone", "drinks",
            "read", "laughed", "made_something", "outside", "did_nothing",
        ] {
            XCTAssertTrue(
                app.buttons["happening_choice_happening_\(id)"].waitForExistence(timeout: 2)
            )
        }
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
    }

    func testEditorialHappeningPaletteScreenshots() throws {
        let app = launchTask7App()
        openPalette(in: app)
        scrollPaletteToStart(in: app)

        XCTAssertTrue(app.buttons["Walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        XCTAssertTrue(app.otherElements["task7_accessibility_configuration"].exists)
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(named: "editorial-palette-circles")

        app.buttons["happening_choice_happening_walk"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        XCTAssertEqual(app.buttons["Walk"].value as? String, "Previewing addition to Canvas")
        for title in task7BuiltInTitles.dropFirst() {
            XCTAssertEqual(app.buttons[title].value as? String, "Available")
        }
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(named: "editorial-palette-shape-preview")

        app.buttons["happening_choice_happening_walk"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        XCTAssertEqual(app.buttons["Walk"].value as? String, "On Canvas")
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'")
            ).count,
            31
        )
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        Thread.sleep(forTimeInterval: 0.7)
        attachScreenshot(named: "editorial-palette-added-fixed-slots")

        app.buttons["happening_choice_happening_walk"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        XCTAssertTrue(app.buttons["happening_choice_happening_walk"].staticTexts["Delete"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["Walk"].value as? String, "Previewing removal from Canvas")
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(named: "editorial-palette-removal-preview")
        assertPersistentPaletteChrome(in: app)
    }

    func testHappeningPaletteAccessibilityKeepsReadableScrollableRows() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility5", increasedContrast: true)
        openPalette(in: app)
        assertPersistentPaletteChrome(in: app)
        let slots = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'")
        ).allElementsBoundByIndex
        let rows = Dictionary(grouping: slots) { round($0.frame.midY) }
            .sorted { $0.key < $1.key }.map { $0.value.count }
        XCTAssertEqual(rows, [4, 5, 4, 5, 4, 5, 4])
        for slot in slots {
            XCTAssertGreaterThanOrEqual(slot.frame.width, 44)
            XCTAssertGreaterThanOrEqual(slot.frame.height, 44)
        }
        attachScreenshot(named: "editorial-palette-accessibility5-scrollable-rows")
    }

    func testHappeningEditorReplacementCreationAndCancellation() throws {
        let app = launchTask7App(resetEditor: true)
        openPalette(in: app, all: false)
        let walk = app.buttons["happening_choice_happening_walk"]
        walk.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        walk.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        app.buttons["Choose happenings"].tap()
        let rootWalk = app.buttons["happening_editor_row_happening_walk"]
        XCTAssertTrue(rootWalk.waitForExistence(timeout: 5))
        XCTAssertTrue(rootWalk.staticTexts["Health"].exists)
        XCTAssertFalse(app.buttons["Close"].isHittable)
        attachScreenshot(named: "happening-editor-list")
        rootWalk.tap()
        XCTAssertTrue(app.alerts["Health happenings stay in Frequent"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        app.buttons["happening_editor_row_happening_called_someone"].tap()
        app.buttons["happening_editor_new"].tap()
        let name = app.textFields["happening_editor_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Tea break")
        attachScreenshot(named: "happening-editor-create-keyboard")
        // Tap the outer edge: the entire capsule must be an active target.
        app.buttons["happening_editor_done"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Tea break"].waitForExistence(timeout: 5))
        XCTAssertEqual(walk.value as? String, "On Canvas")
        XCTAssertFalse(app.buttons["Connected"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_' ")).count, 10)

        app.buttons["Choose happenings"].tap()
        let tea = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_editor_row_' AND label CONTAINS 'Tea break'")).firstMatch
        XCTAssertTrue(tea.waitForExistence(timeout: 5))
        tea.tap()
        let search = app.textFields["happening_editor_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        attachScreenshot(named: "happening-editor-replace")
        search.tap()
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matches"].exists)
        app.buttons["Clear search"].tap()
        app.buttons["happening_replacement_happening_called_someone"].tap()
        XCTAssertTrue(app.buttons["happening_editor_row_happening_called_someone"].waitForExistence(timeout: 3))
        app.buttons["happening_editor_back"].tap()
        XCTAssertTrue(app.buttons["Tea break"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Connected"].exists)

        app.buttons["Choose happenings"].tap()
        XCTAssertTrue(tea.waitForExistence(timeout: 5))
        tea.tap()
        app.buttons["happening_replacement_happening_called_someone"].tap()
        app.buttons["happening_editor_done"].tap()
        XCTAssertTrue(app.buttons["Connected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Tea break"].exists)
        XCTAssertEqual(walk.value as? String, "On Canvas")
        walk.tap()
        walk.tap()
        app.buttons["Close"].tap()
    }

    func testHappeningEditorLargeTextKeepsActionsReachable() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility5", increasedContrast: true, resetEditor: true)
        openPalette(in: app, all: false)
        app.buttons["Choose happenings"].tap()
        let done = app.buttons["happening_editor_done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(app.frame.contains(done.frame))
        XCTAssertTrue(app.buttons["happening_editor_back"].isHittable)
        attachScreenshot(named: "happening-editor-large-text")
        let connected = app.buttons["happening_editor_row_happening_called_someone"]
        for _ in 0..<5 where !connected.isHittable { app.scrollViews.firstMatch.swipeUp() }
        connected.tap()
        let newHappening = app.buttons["happening_editor_new"]
        for _ in 0..<5 where !newHappening.isHittable { app.scrollViews.firstMatch.swipeDown() }
        newHappening.tap()
        let name = app.textFields["happening_editor_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Tea")
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(app.frame.contains(done.frame))
        attachScreenshot(named: "happening-editor-large-text-keyboard")
        done.tap()
        XCTAssertTrue(app.buttons["Tea"].waitForExistence(timeout: 5))
    }

    func testAllShrinksEdgeChoicesAndRestoresThemNearCenter() throws {
        let app = launchTask7App(resetEditor: true)
        openPalette(in: app)
        XCTAssertTrue(waitForChoiceCount(31, in: app))
        Thread.sleep(forTimeInterval: 0.7)
        let field = app.scrollViews["happening_field_scroll"]
        let centered = app.buttons["happening_choice_happening_read"]
        XCTAssertTrue(centered.waitForExistence(timeout: 3))
        let originalFrame = centered.frame
        XCTAssertEqual(originalFrame.midX, field.frame.midX, accuracy: 2)
        attachScreenshot(named: "happenings-edge-scale-centered")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.58))
            .press(forDuration: 0.08, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.58)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 0.25)
        attachScreenshot(named: "happenings-edge-scale-panned")
        XCTAssertLessThan(centered.frame.midX, originalFrame.midX - 80)
        XCTAssertLessThan(centered.frame.width, originalFrame.width * 0.97)
        XCTAssertGreaterThanOrEqual(centered.frame.width, 44)
        app.buttons["happening_mode_frequent"].tap()
        XCTAssertTrue(waitForChoiceCount(10, in: app))
        app.buttons["happening_mode_all"].tap()
        XCTAssertTrue(waitForChoiceCount(31, in: app))
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertEqual(centered.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(centered.frame.midX, originalFrame.midX, accuracy: 1)
    }

    func testFrequentDefaultsIncludeHealthAndSwitchBackFromAll() throws {
        let app = launchTask7App(resetEditor: true)
        let canvasTab = app.buttons["tab_canvas"]
        XCTAssertTrue(canvasTab.waitForExistence(timeout: 8))
        let tabBarCenterY = canvasTab.frame.midY
        attachScreenshot(named: "happenings-tab-bar-baseline")
        openPalette(in: app, all: false)
        func assertTabBarAlignment() {
            for control in [app.buttons["canvas_happening_list_button"], app.buttons["Close"],
                            app.buttons["happening_mode_frequent"], app.buttons["happening_mode_all"]] {
                XCTAssertEqual(control.frame.midY, tabBarCenterY, accuracy: 1,
                    "Happenings controls should replace the tab bar at its measured center")
                XCTAssertTrue(control.isHittable)
            }
        }
        assertTabBarAlignment()
        let frequent = app.buttons["happening_mode_frequent"]
        let all = app.buttons["happening_mode_all"]
        XCTAssertTrue(frequent.isSelected)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'"))
        XCTAssertEqual(choices.count, 10)
        for id in ["happening_slept_well", "happening_walk", "happening_workout", "happening_did_nothing"] {
            XCTAssertTrue(app.buttons["happening_choice_" + id].isHittable)
        }
        let initialFrames = choices.allElementsBoundByIndex.map(\.frame)
        attachScreenshot(named: "happenings-frequent-health")
        all.tap()
        XCTAssertTrue(all.isSelected)
        XCTAssertTrue(waitForChoiceCount(31, in: app))
        Thread.sleep(forTimeInterval: 0.7)
        attachScreenshot(named: "happenings-all-with-switch")
        assertTabBarAlignment()
        let field = app.scrollViews["happening_field_scroll"]
        let switchFrame = all.frame
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4)))
        XCTAssertEqual(all.frame, switchFrame)
        frequent.tap()
        XCTAssertTrue(waitForChoiceCount(10, in: app))
        XCTAssertEqual(choices.allElementsBoundByIndex.map(\.frame), initialFrames)
        attachScreenshot(named: "happenings-frequent-returned")
        all.tap()
        app.buttons["Close"].tap()
        openPalette(in: app, all: false)
        XCTAssertTrue(frequent.isSelected)
        XCTAssertEqual(choices.count, 10)
    }

    func testFrequentSelectionSurvivesModeChangesAndHealthSlotsStayPinned() throws {
        let app = launchTask7App(resetEditor: true)
        openPalette(in: app, all: false)
        let walk = app.buttons["happening_choice_happening_walk"]
        walk.tap()
        walk.tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        app.buttons["happening_mode_all"].tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        app.buttons["happening_mode_frequent"].tap()
        XCTAssertEqual(walk.value as? String, "On Canvas")
        attachScreenshot(named: "happenings-frequent-added")
        app.buttons["canvas_happening_list_button"].tap()
        app.buttons["happening_editor_row_happening_workout"].tap()
        XCTAssertTrue(app.alerts["Health happenings stay in Frequent"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        app.buttons["happening_editor_done"].tap()
        walk.tap()
        walk.tap()
        XCTAssertEqual(walk.value as? String, "Available")
        app.buttons["Close"].tap()
    }

    func testFrequentSwitchAndHealthChoicesRemainReachableAtLargeType() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility5", increasedContrast: true)
        openPalette(in: app, all: false)
        for id in ["happening_mode_frequent", "happening_mode_all", "canvas_palette_close_button", "canvas_happening_list_button"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(app.frame.contains(button.frame))
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        attachScreenshot(named: "happenings-frequent-large-type")
        let last = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'" )).element(boundBy: 9)
        let field = app.scrollViews["happening_field_scroll"]
        let dockTop = app.buttons["happening_mode_frequent"].frame.minY
        for _ in 0..<12 where !last.isHittable || last.frame.maxY > dockTop - 8 { field.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThan(last.frame.maxY, dockTop - 8)
        attachScreenshot(named: "happenings-frequent-large-type-last")
        app.buttons["happening_mode_all"].tap()
        XCTAssertTrue(app.buttons["happening_mode_all"].isSelected)
        app.buttons["happening_mode_frequent"].tap()
        XCTAssertTrue(waitForChoiceCount(10, in: app))
    }

    func testHappeningCanvasPixelsStayFixedWhileTargetsPan() throws {
        let app = launchTask7App()
        openPalette(in: app)
        let field = app.scrollViews["happening_field_scroll"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'"))
        func targets() -> [(CGRect, Bool)] {
            choices.allElementsBoundByIndex.map { ($0.frame, ($0.value as? String) == "Available") }
        }
        func pixels(_ image: UIImage) throws -> (data: [UInt8], width: Int, height: Int) {
            let cg = try XCTUnwrap(image.cgImage)
            var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &data, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return (data, cg.width, cg.height)
        }
        let initialTargets = targets()
        let before = try pixels(app.screenshot().image)
        attachScreenshot(named: "stationary-canvas-before-pan")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)))
        Thread.sleep(forTimeInterval: 0.5)
        let finalTargets = targets()
        let after = try pixels(app.screenshot().image)
        attachScreenshot(named: "stationary-canvas-after-pan")
        XCTAssertEqual(before.width, after.width)
        XCTAssertNotEqual(initialTargets[0].0.origin, finalTargets[0].0.origin)
        func covers(_ target: (CGRect, Bool), _ point: CGPoint) -> Bool {
            let (frame, available) = target
            guard available else { return frame.insetBy(dx: -20, dy: -20).contains(point) }
            let x = abs(point.x - frame.midX) / (frame.width / 2 + 8)
            let y = abs(point.y - frame.midY) / (frame.height / 2 + 8)
            return pow(x, 2.2) + pow(y, 2.2) <= 1
        }
        let scale = CGFloat(before.width) / app.frame.width
        var compared = 0
        var changed = 0
        for y in stride(from: 200, to: Int(app.frame.height) - 140, by: 4) {
            for x in stride(from: 8, to: Int(app.frame.width) - 8, by: 4) {
                let point = CGPoint(x: x, y: y)
                guard !(initialTargets + finalTargets).contains(where: { covers($0, point) }) else { continue }
                let i = (Int(CGFloat(y) * scale) * before.width + Int(CGFloat(x) * scale)) * 4
                compared += 1
                if (0..<3).contains(where: { abs(Int(before.data[i + $0]) - Int(after.data[i + $0])) > 3 }) { changed += 1 }
            }
        }
        XCTAssertGreaterThan(compared, 20, "Need visible canvas samples between targets")
        XCTAssertLessThan(Double(changed) / Double(max(compared, 1)), 0.01,
            "The same canvas pixels must remain stationary beneath the transparent field (\(changed)/\(compared) moved)")
    }

    func testStaggeredHappeningsOpenCenteredAndPanAsOneField() throws {
        let app = launchTask7App()
        openPalette(in: app)
        let field = app.scrollViews["happening_field_scroll"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'"))
        XCTAssertEqual(choices.count, 31)
        let frames = choices.allElementsBoundByIndex.map(\.frame)
        let bounds = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        XCTAssertEqual(bounds.midX, field.frame.midX, accuracy: 2)
        XCTAssertEqual(bounds.midY, field.frame.midY, accuracy: 2)
        let rows = Dictionary(grouping: frames) { round($0.midY) }.sorted { $0.key < $1.key }
        XCTAssertEqual(rows.map { $0.value.count }, [4, 5, 4, 5, 4, 5, 4])
        let middle = app.buttons["happening_choice_happening_played"]
        XCTAssertTrue(middle.isHittable)
        let initial = middle.frame
        attachScreenshot(named: "happenings-field-start")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.72))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.38)))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertLessThan(middle.frame.minX, initial.minX - 40)
        XCTAssertLessThan(middle.frame.minY, initial.minY - 40)
        let choice = app.buttons["happening_choice_happening_said_no"]
        XCTAssertTrue(choice.isHittable)
        attachScreenshot(named: "happenings-field-diagonal")
        choice.tap()
        XCTAssertEqual(choice.value as? String, "Previewing addition to Canvas")
        choice.tap()
        XCTAssertEqual(choice.value as? String, "On Canvas")
        Thread.sleep(forTimeInterval: 0.6)
        attachScreenshot(named: "happenings-field-added")
        let selectedFrame = choice.frame
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(choice.value as? String, "On Canvas")
        XCTAssertGreaterThan(choice.frame.minX, selectedFrame.minX)
        XCTAssertGreaterThan(choice.frame.minY, selectedFrame.minY)
        app.buttons["Close"].tap()
        openPalette(in: app)
        XCTAssertEqual(middle.frame.midX, initial.midX, accuracy: 2)
        XCTAssertEqual(middle.frame.midY, initial.midY, accuracy: 2)
        // Do not leave domain additions in the simulator's shared app group.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.72))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.38)))
        choice.tap()
        choice.tap()
        XCTAssertEqual(choice.value as? String, "Available")
        app.buttons["Close"].tap()
    }

    func testHappeningFieldLargeTypeCanReachTheLastChoice() throws {
        let app = launchTask7App(dynamicTypeSize: "accessibility5", increasedContrast: true)
        openPalette(in: app)
        let field = app.scrollViews["happening_field_scroll"]
        let last = app.buttons["happening_choice_happening_listened"]
        for _ in 0..<3 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.35)))
        }
        XCTAssertTrue(last.isHittable)
        last.tap()
        XCTAssertEqual(last.value as? String, "Previewing addition to Canvas")
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(named: "happenings-field-large-type")
        XCTAssertTrue(app.buttons["Close"].isHittable)
    }

    private func waitForChoiceCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let predicate = NSPredicate { _, _ in
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'happening_choice_'" )).count == count
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3) == .completed
    }

    private func launchTask7App(
        dynamicTypeSize: String? = nil,
        increasedContrast: Bool = false,
        shakeTrigger: Bool = false,
        resetEditor: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-task7",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        if resetEditor { app.launchArguments.append("ui-testing-happening-editor") }
        if let dynamicTypeSize {
            app.launchEnvironment["TASK7_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityM",
            ]
        } else {
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

    private func scrollPaletteToStart(in app: XCUIApplication) {
        let field = app.scrollViews["happening_field_scroll"]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func openPalette(in app: XCUIApplication, all: Bool = true) {
        let addHappening = app.buttons["Add happening"]
        XCTAssertTrue(addHappening.waitForExistence(timeout: 8))
        addHappening.tap()
        // Existing field scenarios exercise All; dedicated tests verify the
        // new default Frequent set and its persistent bottom switch.
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        if all { app.buttons["happening_mode_all"].tap() }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
