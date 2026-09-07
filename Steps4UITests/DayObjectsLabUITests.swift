import XCTest

final class DayObjectsLabUITests: XCTestCase {
    func testAuditionExportAppearsOnlyInsideInstrumentDiagnostics() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let diagnostics = app.buttons["dayObjects.instrumentDiagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dayObjects.audition.export"].exists)
        diagnostics.tap()
        XCTAssertTrue(app.buttons["dayObjects.audition.export"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dayObjects.audition.exportProgress"].label, "0 / 12 previews")
        diagnostics.tap()
        XCTAssertFalse(app.buttons["dayObjects.audition.export"].exists)
    }

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

        controlsToggle.tap()
        app.switches["dayObjects.reduceMotionPreview"].tap()
        app.switches["dayObjects.lowSleep"].tap()
        app.buttons["dayObjects.nextDay"].tap()
        let background = app.segmentedControls["dayObjects.background"]
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        background.buttons["Light"].tap()
        controlsToggle.tap()
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(named: "editorial-field-metal-light-low-sleep")
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
        XCTAssertFalse(app.otherElements["dayObjects.leadSurface"].exists)
        XCTAssertTrue(String(describing: app.otherElements["dayObjects.grid"].value).contains("Touch performance unavailable"))
        app.buttons["dayObjects.controlsToggle"].tap()

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
        XCTAssertTrue(String(describing: material.value).contains("Generative DNA"))
        XCTAssertTrue(placement.exists)
        XCTAssertTrue(String(describing: placement.value).contains("Depth field"))

        let language = app.staticTexts["dayObjects.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        let initialFingerprint = Self.dnaFingerprint(from: language.value)
        XCTAssertTrue(initialFingerprint.hasPrefix("DNA "), initialFingerprint)

        app.buttons["dayObjects.nextDay"].tap()
        let changedFingerprint = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                let fingerprint = Self.dnaFingerprint(from: element.value)
                return fingerprint.hasPrefix("DNA ") && fingerprint != initialFingerprint
            },
            object: language
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changedFingerprint], timeout: 5), .completed)
        let nextFingerprint = Self.dnaFingerprint(from: language.value)

        app.switches["dayObjects.reduceMotionPreview"].tap()
        app.buttons["dayObjects.tileToggle"].tap()
        XCTAssertEqual(Self.dnaFingerprint(from: language.value), nextFingerprint)

        material.tap()
        let comparison = app.buttons["All formats (comparison)"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 3))
        comparison.tap()
        XCTAssertTrue(
            String(describing: material.value).contains("All formats (comparison)")
        )
    }

    func testComplexGradientExamplesVisualHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let happenings = app.sliders["dayObjects.happenings"]
        let language = app.staticTexts["dayObjects.language"]
        let controlsToggle = app.buttons["dayObjects.controlsToggle"]
        let nextDay = app.buttons["dayObjects.nextDay"]
        XCTAssertTrue(happenings.waitForExistence(timeout: 8))
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        setHappenings(10, on: happenings)

        var captured = 0
        for offset in 0..<42 where captured < 4 {
            let fingerprint = Self.dnaFingerprint(from: language.value)
            let primaryMaterial = fingerprint
                .components(separatedBy: " · ")
                .dropFirst(2)
                .first ?? ""
            if primaryMaterial.hasPrefix("radial field") {
                controlsToggle.tap()
                Thread.sleep(forTimeInterval: 1)
                attachScreenshot(named: "complex-gradient-\(captured + 1)-offset-\(offset)")
                controlsToggle.tap()
                let controlsReady = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "isHittable == true"),
                    object: nextDay
                )
                XCTAssertEqual(
                    XCTWaiter.wait(for: [controlsReady], timeout: 3),
                    .completed
                )
                captured += 1
            }
            if captured < 4 {
                nextDay.tap()
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        XCTAssertEqual(captured, 4)
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

    func testHappeningPadsExposeThirtyStableAccessibleRecipesInFiveColumns() throws {
        let app = launchDayObjectsLab()
        let grid = app.otherElements["dayObjects.happeningPads"]

        XCTAssertTrue(scrollToElement(grid, in: app), "The pad grid must be reachable on a phone-sized viewport")

        let pads = (1...30).map { index in
            app.buttons[String(format: "dayObjects.happeningPad.%02d", index)]
        }
        XCTAssertTrue(scrollToElement(pads[0], in: app))
        for index in 0...4 {
            XCTAssertTrue(pads[index].exists, "Missing first-row Happening pad \(index + 1)")
        }
        XCTAssertEqual(grid.value as? String, "30 sounds")
        XCTAssertEqual(pads[0].label, "Happening 01, Warm analog ping")

        let firstRowY = pads[0].frame.midY
        for pad in pads[1...4] {
            XCTAssertEqual(pad.frame.midY, firstRowY, accuracy: 1)
        }
        XCTAssertTrue(scrollToElement(pads[5], in: app))
        XCTAssertGreaterThan(pads[5].frame.midY, firstRowY)

        for (index, pad) in pads.enumerated() {
            XCTAssertTrue(scrollToElement(pad, in: app), "Missing Happening pad \(index + 1)")
        }
        XCTAssertEqual(pads[6].label, "Happening 07, Wooden kalimba")
        XCTAssertEqual(pads[12].label, "Happening 13, Soft metal bowl")
        XCTAssertEqual(pads[18].label, "Happening 19, Sub bloom")
        XCTAssertEqual(pads[24].label, "Happening 25, Breath resonator")
        XCTAssertFalse(app.buttons["dayObjects.happeningPad.31"].exists)
    }

    func testHappeningPadsAuditionWithSoundOffAndOnWithoutChangingSceneCount() throws {
        let app = launchDayObjectsLab()
        let sound = app.buttons["dayObjects.sound"]
        let happenings = app.sliders["dayObjects.happenings"]
        let initialReadout = String(describing: happenings.value)
        let firstPad = app.buttons["dayObjects.happeningPad.01"]

        XCTAssertTrue(scrollToElement(firstPad, in: app))
        firstPad.tap()
        XCTAssertEqual(sound.value as? String, "off", "Sample-only audition must not turn on the composition")
        XCTAssertEqual(String(describing: happenings.value), initialReadout)

        let sampleOnlyAuditionFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Ready'"),
            object: firstPad
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [sampleOnlyAuditionFinished], timeout: 12),
            .completed,
            "Wait for the sound-off audition teardown before requesting live Sound"
        )

        sound.tap()
        let soundResolved = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let sound = object as? XCUIElement else { return false }
                guard let value = sound.value as? String else { return false }
                return value == "on" || value == "error, output unavailable, retry available"
            },
            object: sound
        )
        XCTAssertEqual(XCTWaiter.wait(for: [soundResolved], timeout: 12), .completed)
        let resolvedSoundValue = sound.value as? String
        if resolvedSoundValue == "error, output unavailable, retry available" {
            throw XCTSkip("Simulator has no valid Core Audio output; sound-off Happening audition remained safe")
        }
        XCTAssertEqual(
            resolvedSoundValue,
            "on",
            "Only a typed unavailable-output error may skip this test"
        )

        let lastPad = app.buttons["dayObjects.happeningPad.30"]
        XCTAssertTrue(scrollToElement(lastPad, in: app))
        lastPad.tap()
        XCTAssertEqual(String(describing: happenings.value), initialReadout)
        XCTAssertTrue(scrollToElement(app.buttons["dayObjects.remix"], in: app))
        XCTAssertTrue(app.buttons["dayObjects.remix"].isEnabled)
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
        XCTAssertTrue(app.buttons["dayObjects.audition.mode"].exists)
        XCTAssertFalse(app.buttons["dayObjects.audition.mode"].isEnabled)
        for role in ["rhythm", "bass", "harmony", "happenings", "lead"] {
            let bus = app.buttons["dayObjects.audition.bus.\(role)"]
            XCTAssertTrue(bus.exists)
            XCTAssertFalse(bus.isEnabled)
        }
        XCTAssertTrue(app.buttons["dayObjects.audition.sidechain"].exists)
        XCTAssertFalse(app.buttons["dayObjects.audition.sidechain"].isEnabled)
        XCTAssertTrue(app.staticTexts["dayObjects.audition.masterMeter"].exists)

        let canvas = app.otherElements["dayObjects.canvas"]
        let category = app.buttons["dayObjects.audition.category"]
        XCTAssertTrue(canvas.exists)
        XCTAssertTrue(category.isHittable, "Diagnostics must remain usable over the full-area Canvas background")
        XCTAssertTrue(app.buttons["dayObjects.audition.export"].exists)

        app.buttons["dayObjects.gridToggle"].tap()
        XCTAssertTrue(app.otherElements["dayObjects.grid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dayObjects.audition.category"].exists)
    }

    func testInstrumentCategoriesExposeAutomaticActionsAndApprovedTonalPresets() throws {
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

        for category in ["Pad", "Pluck", "Lead", "Keys"] {
            selectCategory(category, in: app)
            let preset = app.buttons["dayObjects.audition.preset"]
            XCTAssertTrue(preset.waitForExistence(timeout: 2))
            XCTAssertEqual(preset.value as? String, "3 presets", "\(category) must expose exactly three choices")
            assertEnabled(note)
            assertEnabled(chord)
            assertDisabled(hit, value: "disabled for \(category)")
        }

        selectCategory("Bass", in: app)
        XCTAssertEqual(app.buttons["dayObjects.audition.preset"].value as? String, "4 presets")
        assertEnabled(note)
        assertEnabled(chord)
        assertDisabled(hit, value: "disabled for Bass")

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

    @discardableResult
    private func launchDayObjectsLab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiLab", "dayObjects",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["dayObjects.sound"].waitForExistence(timeout: 5))
        return app
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.exists, element.isHittable { return true }
        if element.waitForExistence(timeout: 1), element.isHittable { return true }

        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<12 {
            drag(scrollView, fromY: 0.72, toY: 0.52)
            if element.exists, element.isHittable { return true }
        }
        for _ in 0..<12 {
            drag(scrollView, fromY: 0.40, toY: 0.60)
            if element.exists, element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    private func drag(_ element: XCUIElement, fromY: CGFloat, toY: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func selectCategory(_ category: String, in app: XCUIApplication) {
        let picker = app.buttons["dayObjects.audition.category"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let menu = app.collectionViews.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2))
        let choice = menu.buttons[category]
        XCTAssertTrue(choice.waitForExistence(timeout: 2))
        XCTAssertTrue(choice.isHittable)
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

    private static func dnaFingerprint(from accessibilityValue: Any?) -> String {
        String(describing: accessibilityValue ?? "")
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
    }

    private func assertLanguageSummary(
        _ summary: String,
        expectedActorCount: Int
    ) {
        XCTAssertTrue(summary.contains("DNA ") || summary.contains("family="), summary)
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
