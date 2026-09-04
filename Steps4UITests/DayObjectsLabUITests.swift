import XCTest

final class DayObjectsLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEditorialFieldMVPVisualHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let canvas = app.otherElements["dayObjects.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        setHappenings(10, on: app.sliders["dayObjects.happenings"])

        let controlsToggle = app.buttons["dayObjects.controlsToggle"]
        controlsToggle.tap()
        Thread.sleep(forTimeInterval: 10)
        attachScreenshot(named: "editorial-field-metal-full")

        controlsToggle.tap()
        let tileToggle = app.buttons["dayObjects.tileToggle"]
        XCTAssertTrue(tileToggle.waitForExistence(timeout: 5))
        tileToggle.tap()
        let tileState = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "tile"),
            object: tileToggle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [tileState], timeout: 5), .completed)
        XCTAssertTrue(app.otherElements["dayObjects.calendarTile"].waitForExistence(timeout: 5))
        controlsToggle.tap()
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(named: "editorial-field-metal-calendar-tile")

        controlsToggle.tap()
        app.switches["dayObjects.reduceMotionPreview"].tap()
        app.buttons["dayObjects.tileToggle"].tap()
        controlsToggle.tap()
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(named: "editorial-field-metal-reduce-motion")
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
        XCTAssertTrue(String(describing: happeningsSlider.value).contains("8 · 8 figures"))
        let language = app.staticTexts["dayObjects.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        let initialLanguage = String(describing: language.value)
        assertLanguageSummary(initialLanguage, expectedActorCount: 8)

        setHappenings(10, on: happeningsSlider)
        assertLanguageSummary(
            String(describing: language.value),
            expectedActorCount: 10
        )
        XCTAssertTrue(app.otherElements["dayObjects.canvas"].exists)

        Thread.sleep(forTimeInterval: 1.5)
        let maximumScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        maximumScreenshot.name = "task-11-day-objects-ten-living-orbs"
        maximumScreenshot.lifetime = .keepAlways
        add(maximumScreenshot)

        for count in [7, 4, 1] {
            setHappenings(count, on: happeningsSlider)
            assertLanguageSummary(
                String(describing: language.value),
                expectedActorCount: count
            )
        }

        setHappenings(0, on: happeningsSlider)
        XCTAssertTrue(app.otherElements["dayObjects.canvas"].exists)

        let zeroEventScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        zeroEventScreenshot.name = "task-10-day-objects-zero-events"
        zeroEventScreenshot.lifetime = .keepAlways
        add(zeroEventScreenshot)

        setHappenings(4, on: happeningsSlider)
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
        let populatedCounts = Self.counts(from: happeningsSlider.value)
        XCTAssertEqual(populatedCounts.count, 2)
        XCTAssertEqual(populatedCounts.first, populatedCounts.last)

        Thread.sleep(forTimeInterval: 1.5)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "task-10-day-objects-lab"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["dayObjects.nextDay"].tap()
        XCTAssertNotEqual(String(describing: language.value), initialLanguage)

        app.buttons["dayObjects.gridToggle"].tap()
        XCTAssertTrue(app.otherElements["dayObjects.grid"].waitForExistence(timeout: 5))

        Thread.sleep(forTimeInterval: 1.5)
        let gridScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        gridScreenshot.name = "task-10-day-objects-grid"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)
    }

    func testLabExposesEditorialMaterialAndPlacementControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let material = app.descendants(matching: .any)["dayObjects.materialMode"].firstMatch
        let placement = app.descendants(matching: .any)["dayObjects.placement"].firstMatch

        XCTAssertTrue(material.waitForExistence(timeout: 8))
        XCTAssertTrue(String(describing: material.value).contains("Mixed"))
        XCTAssertTrue(placement.exists)
        XCTAssertTrue(String(describing: placement.value).contains("Depth field"))
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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func figureCount(from accessibilityValue: Any?) -> Int? {
        counts(from: accessibilityValue).last
    }

    private func setHappenings(_ target: Int, on slider: XCUIElement) {
        if target == 1 {
            slider.adjust(toNormalizedSliderPosition: 0)
            slider.swipeUp()
            if Self.figureCount(from: slider.value) == 1 {
                XCTAssertTrue(String(describing: slider.value).contains("1 · 1 figures"))
                return
            }
        }
        var lower = 0.0
        var upper = 1.0
        var position = Double(target) / 10
        for _ in 0..<20 {
            slider.adjust(toNormalizedSliderPosition: min(max(position, 0), 1))
            let current = Self.figureCount(from: slider.value) ?? -1
            if current == target {
                XCTAssertTrue(String(describing: slider.value).contains("\(target) · \(target) figures"))
                return
            }
            if current < target {
                lower = position
            } else {
                upper = position
            }
            position = (lower + upper) * 0.5
        }
        XCTFail("Could not set Day Objects happenings to \(target); value=\(slider.value ?? "nil")")
    }

    private static func counts(from accessibilityValue: Any?) -> [Int] {
        String(describing: accessibilityValue ?? "")
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    private func assertLanguageSummary(
        _ summary: String,
        expectedActorCount: Int
    ) {
        XCTAssertTrue(summary.contains("family="), summary)
        XCTAssertTrue(summary.contains("mutations="), summary)
        XCTAssertTrue(summary.contains("motion="), summary)
        XCTAssertTrue(summary.contains("palettes="), summary)
        let mutationText = summary
            .components(separatedBy: "mutations=").dropFirst().first?
            .split(separator: " ").first
            .map(String.init) ?? ""
        let mutationCounts = mutationText
            .split(separator: "/")
            .compactMap { Int($0) }
        XCTAssertEqual(mutationCounts.count, 3, summary)
        XCTAssertEqual(mutationCounts.reduce(0, +), expectedActorCount, summary)
        let paletteText = summary
            .components(separatedBy: "palettes=").dropFirst().first ?? ""
        XCTAssertEqual(paletteText.split(separator: "/").count, 3, summary)
    }
}
