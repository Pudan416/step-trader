import XCTest

final class DayObjectsLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSoundControlIsExplicitAndRemainsVisibleOutsideCollapsedControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let sound = app.buttons["dayObjects.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? String, "off")
        XCTAssertTrue(sound.isEnabled)
        XCTAssertTrue(app.buttons["dayObjects.remix"].isEnabled)
        XCTAssertEqual(app.buttons["dayObjects.instrumentDiagnostics"].value as? String, "collapsed")

        app.buttons["dayObjects.controlsToggle"].tap()
        XCTAssertTrue(sound.exists)
        XCTAssertFalse(app.buttons["dayObjects.remix"].exists)
    }

    func testLabExposesAutomaticDayControlsAndAddsHappeningsInPlace() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let stepsSlider = app.sliders["dayObjects.steps"]
        let sleepSlider = app.sliders["dayObjects.sleep"]
        let happeningsSlider = app.sliders["dayObjects.happenings"]
        let spentSlider = app.sliders["dayObjects.spentColors"]
        XCTAssertTrue(stepsSlider.waitForExistence(timeout: 5))
        XCTAssertTrue(sleepSlider.exists)
        XCTAssertTrue(happeningsSlider.exists)
        XCTAssertTrue(spentSlider.exists)
        XCTAssertTrue(String(describing: stepsSlider.value).contains("10,000 / 10,000 steps"))
        XCTAssertTrue(String(describing: sleepSlider.value).contains("8 / 8 hours"))
        XCTAssertTrue(String(describing: happeningsSlider.value).contains("8"))
        XCTAssertTrue(String(describing: spentSlider.value).contains("Spent colors 0"))
        let leadSurface = app.otherElements["dayObjects.leadSurface"]
        XCTAssertTrue(leadSurface.exists)
        XCTAssertEqual(leadSurface.label, "Canvas Lead")
        XCTAssertFalse(app.sliders["dayObjects.motionEnergy"].exists)
        XCTAssertFalse(app.sliders["dayObjects.visualClarity"].exists)

        stepsSlider.adjust(toNormalizedSliderPosition: 0)
        sleepSlider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(String(describing: stepsSlider.value).contains("0 / 10,000 steps"))
        XCTAssertTrue(String(describing: sleepSlider.value).contains(" / 8 hours"))

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
        XCTAssertFalse(app.otherElements["dayObjects.leadSurface"].exists)
        XCTAssertTrue(String(describing: app.otherElements["dayObjects.grid"].value).contains("Touch performance unavailable"))

        Thread.sleep(forTimeInterval: 1.5)
        let gridScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gridScreenshot.name = "task-10-day-objects-grid"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)
    }

    func testLabExposesRemixSummaryAndCollapsedFineTuning() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let fineTuning = app.buttons["dayObjects.fineTuning"]
        let diagnostics = app.buttons["dayObjects.instrumentDiagnostics"]
        XCTAssertTrue(fineTuning.waitForExistence(timeout: 5))
        XCTAssertTrue(diagnostics.exists)
        XCTAssertLessThan(fineTuning.frame.minY, diagnostics.frame.minY)
        XCTAssertFalse(app.sliders["dayObjects.motionEnergy"].exists)
        XCTAssertFalse(app.sliders["dayObjects.visualClarity"].exists)

        XCTAssertTrue(app.buttons["dayObjects.remix"].exists)
        XCTAssertTrue(app.staticTexts["dayObjects.worldSummary"].exists)

        fineTuning.tap()
        let motion = app.sliders["dayObjects.motionEnergy"]
        let reset = app.buttons["dayObjects.fineTuning.reset"]
        XCTAssertTrue(motion.waitForExistence(timeout: 2))
        XCTAssertTrue(app.sliders["dayObjects.visualClarity"].exists)
        XCTAssertTrue(reset.exists)

        motion.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(String(describing: motion.value).contains("0.00"))
        reset.tap()
        XCTAssertTrue(String(describing: motion.value).contains("1.00"))
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

    func testLabExposesInstrumentAuditionControlsWithoutASecondSoundSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let diagnostics = app.buttons["dayObjects.instrumentDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dayObjects.audition.category"].exists)
        diagnostics.tap()

        XCTAssertTrue(app.buttons["dayObjects.audition.category"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["dayObjects.audition.preset"].exists)
        XCTAssertFalse(app.switches["dayObjects.audition.sound"].exists)
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

    func testInstrumentCategoriesExposeAutomaticActionsAndThreeTonalPresets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let diagnostics = app.buttons["dayObjects.instrumentDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()

        let note = app.buttons["dayObjects.audition.note"]
        let chord = app.buttons["dayObjects.audition.chord"]
        let hit = app.buttons["dayObjects.audition.hit"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))

        for category in ["Pad", "Pluck", "Bass", "Lead", "Keys"] {
            selectCategory(category, in: app)
            let preset = app.buttons["dayObjects.audition.preset"]
            XCTAssertTrue(preset.waitForExistence(timeout: 2))
            XCTAssertEqual(preset.value as? String, "3 presets", "\(category) must expose exactly three choices")
            assertEnabled(note)
            assertEnabled(chord)
            assertDisabled(hit, value: "disabled for \(category)")
        }

        selectCategory("Drums", in: app)
        XCTAssertFalse(app.buttons["dayObjects.audition.preset"].exists)
        assertDisabled(note, value: "disabled for Drums")
        assertDisabled(chord, value: "disabled for Drums")
        assertEnabled(hit)
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

    private func assertEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isEnabled)
        XCTAssertEqual(element.value as? String, "enabled")
    }

    private static func figureCount(from accessibilityValue: Any?) -> Int? {
        String(describing: accessibilityValue ?? "")
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .last
    }
}
