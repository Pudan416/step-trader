import XCTest

final class DayObjectsLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLabExposesChoreographyControlsAndAddsEventsInPlace() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let happeningsSlider = app.sliders["dayObjects.happenings"]
        XCTAssertTrue(happeningsSlider.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["dayObjects.motionEnergy"].exists)
        XCTAssertTrue(app.sliders["dayObjects.visualClarity"].exists)

        happeningsSlider.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(app.otherElements["dayObjects.canvas"].exists)
        XCTAssertTrue(
            String(describing: happeningsSlider.value)
                .contains("0 · 0 figures")
        )

        let zeroEventScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        zeroEventScreenshot.name = "task-10-day-objects-zero-events"
        zeroEventScreenshot.lifetime = .keepAlways
        add(zeroEventScreenshot)

        happeningsSlider.adjust(toNormalizedSliderPosition: 0.5)
        app.sliders["dayObjects.visualClarity"].adjust(toNormalizedSliderPosition: 1)

        XCTAssertTrue(app.otherElements["dayObjects.canvas"].exists)
        let populatedFigureCount = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let slider = object as? XCUIElement else { return false }
                return Self.figureCount(from: slider.value) ?? 0 > 0
            },
            object: happeningsSlider
        )
        XCTAssertEqual(XCTWaiter.wait(for: [populatedFigureCount], timeout: 5), .completed)
        XCTAssertGreaterThan(try XCTUnwrap(Self.figureCount(from: happeningsSlider.value)), 0)

        Thread.sleep(forTimeInterval: 1.5)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "task-10-day-objects-lab"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["dayObjects.gridToggle"].tap()
        XCTAssertTrue(app.otherElements["dayObjects.grid"].waitForExistence(timeout: 5))

        Thread.sleep(forTimeInterval: 1.5)
        let gridScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gridScreenshot.name = "task-10-day-objects-grid"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)
    }

    func testLabControlsAbsoluteSpentColorsInSingleAndGridModes() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let spentSlider = app.sliders["dayObjects.spentColors"]
        XCTAssertTrue(spentSlider.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: spentSlider.value).contains("Spent colors 0"))
        attachScreenshot(named: "day-objects-glitch-spent-0")

        app.buttons["dayObjects.spend.plus10"].tap()
        XCTAssertTrue(String(describing: spentSlider.value).contains("Spent colors 10"))
        XCTAssertTrue(
            String(describing: app.otherElements["dayObjects.canvas"].value)
                .contains("Spent colors 10")
        )

        app.buttons["dayObjects.spend.preset.100"].tap()
        XCTAssertTrue(String(describing: spentSlider.value).contains("Spent colors 100"))
        XCTAssertTrue(
            String(describing: app.otherElements["dayObjects.canvas"].value)
                .contains("Spent colors 100")
        )
        attachScreenshot(named: "day-objects-glitch-spent-100")

        app.buttons["dayObjects.gridToggle"].tap()
        let grid = app.otherElements["dayObjects.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: grid.value).contains("Spent colors 100"))
        attachScreenshot(named: "day-objects-glitch-grid-spent-100")
    }

    func testLabExposesInstrumentAuditionControlsWithSoundOff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.buttons["dayObjects.audition.category"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dayObjects.audition.preset"].exists)
        XCTAssertTrue(app.switches["dayObjects.audition.sound"].exists)
        XCTAssertEqual(app.switches["dayObjects.audition.sound"].value as? String, "0")
        XCTAssertTrue(app.buttons["dayObjects.audition.note"].exists)
        XCTAssertTrue(app.buttons["dayObjects.audition.chord"].exists)
        XCTAssertTrue(app.buttons["dayObjects.audition.hit"].exists)
        XCTAssertTrue(app.staticTexts["dayObjects.audition.attribution"].exists)
        XCTAssertTrue(app.staticTexts["dayObjects.audition.diagnostics"].exists)

        let canvas = app.otherElements["dayObjects.canvas"]
        let category = app.buttons["dayObjects.audition.category"]
        XCTAssertTrue(canvas.exists)
        XCTAssertFalse(canvas.frame.intersects(category.frame), "Controls must be laid out below the Lead canvas")

        app.buttons["dayObjects.gridToggle"].tap()
        XCTAssertTrue(app.otherElements["dayObjects.grid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dayObjects.audition.category"].exists)
    }

    func testInstrumentCategoriesExposeDisabledActionsAndThreeTonalPresetsWithoutStartingAudio() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let sound = app.switches["dayObjects.audition.sound"]
        let note = app.buttons["dayObjects.audition.note"]
        let chord = app.buttons["dayObjects.audition.chord"]
        let hit = app.buttons["dayObjects.audition.hit"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? String, "0")

        for category in ["Pad", "Pluck", "Bass", "Lead", "Keys"] {
            selectCategory(category, in: app)
            let preset = app.buttons["dayObjects.audition.preset"]
            XCTAssertTrue(preset.waitForExistence(timeout: 2))
            XCTAssertEqual(preset.value as? String, "3 presets", "\(category) must expose exactly three choices")
            assertDisabled(note, value: "disabled while Sound is off")
            assertDisabled(chord, value: "disabled while Sound is off")
            assertDisabled(hit, value: "disabled for \(category)")
        }

        selectCategory("Drums", in: app)
        XCTAssertFalse(app.buttons["dayObjects.audition.preset"].exists)
        assertDisabled(note, value: "disabled for Drums")
        assertDisabled(chord, value: "disabled for Drums")
        assertDisabled(hit, value: "disabled while Sound is off")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectCategory(_ category: String, in app: XCUIApplication) {
        let picker = app.buttons["dayObjects.audition.category"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let choice = app.buttons[category]
        XCTAssertTrue(choice.waitForExistence(timeout: 2))
        choice.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let picker = object as? XCUIElement else { return false }
                return String(describing: picker.value).localizedCaseInsensitiveContains(category)
            },
            object: picker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 2), .completed)
    }

    private func assertDisabled(_ element: XCUIElement, value: String) {
        XCTAssertTrue(element.exists)
        XCTAssertFalse(element.isEnabled)
        XCTAssertEqual(element.value as? String, value)
    }

    private static func figureCount(from accessibilityValue: Any?) -> Int? {
        String(describing: accessibilityValue ?? "")
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .last
    }
}
