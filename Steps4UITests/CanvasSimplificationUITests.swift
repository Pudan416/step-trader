import XCTest

/// The Canvas screen's four states and the paths between them. These assert
/// structure, not looks: which controls exist, and where a tap lands you.
final class CanvasSimplificationUITests: XCTestCase {
    func testViewingDockClosesAndLandscapeHidesAllControls() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchCanvas()
        app.buttons["canvas_sound_button"].tap()
        let close = app.buttons["canvas_close_fullscreen_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_remix_button"].exists)
        XCTAssertFalse(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_undo_remix_button"].exists)
        let portraitCapture = XCTAttachment(screenshot: app.screenshot())
        portraitCapture.name = "compact-viewing-dock"; portraitCapture.lifetime = .keepAlways; add(portraitCapture)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height && !close.exists
        }, object: nil)
        let rotationResult = XCTWaiter.wait(for: [landscape], timeout: 8)
        let rotationCapture = XCTAttachment(screenshot: app.screenshot())
        rotationCapture.name = "rotation-diagnostic"; rotationCapture.lifetime = .keepAlways; add(rotationCapture)
        XCTAssertEqual(rotationResult, .completed, "frame=\(app.frame), close=\(close.exists)\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["canvas_remix_button"].exists)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        let artwork = app.otherElements["dayObjects.canvas"]
        XCTAssertEqual(artwork.frame.width, app.frame.width, accuracy: 2)
        XCTAssertEqual(artwork.frame.height, app.frame.height, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "clean-landscape-canvas"; screenshot.lifetime = .keepAlways; add(screenshot)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertFalse(close.exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertLessThan(app.frame.width, app.frame.height)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchCanvas(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-task7",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ] + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 12))
        return app
    }

    private func dataHandle(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["canvas_show_data_button"]
    }

    private func energyPill(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["canvas_energy_pill"]
    }

    private func pullDown(_ element: XCUIElement, distance: CGFloat = 90) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func pullUp(_ element: XCUIElement, distance: CGFloat = 90) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func openDataDrawer(in app: XCUIApplication) {
        let pill = energyPill(in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        pullDown(pill)
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))
    }

    private func closeDataDrawer(in app: XCUIApplication) {
        let handle = dataHandle(in: app)
        XCTAssertTrue(handle.waitForExistence(timeout: 3))
        pullUp(handle)
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForNonExistence(timeout: 3))
    }

    func testCanvasShowsExactlyThreeBottomActions() {
        let app = launchCanvas()

        XCTAssertTrue(app.buttons["canvas_sound_button"].exists)
        XCTAssertTrue(dataHandle(in: app).exists)
        XCTAssertTrue(app.buttons["canvas_add_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    func testBottomNavigationIsCompactIconOnlyAndSharesTheCanvasActionBaseline() {
        let app = launchCanvas()
        let sound = app.buttons["canvas_sound_button"]
        let add = app.buttons["canvas_add_button"]
        let tabs = ["tab_canvas", "tab_feeds", "tab_me"].map { app.buttons[$0] }

        for tab in tabs {
            XCTAssertTrue(tab.exists)
            XCTAssertLessThanOrEqual(tab.frame.height, 48)
            XCTAssertEqual(tab.frame.midY, add.frame.midY, accuracy: 2)
        }
        XCTAssertEqual(sound.frame.midY, add.frame.midY, accuracy: 2)

        // The destination names remain on the buttons for VoiceOver, but the
        // visual tab bar is glyph-only and therefore exposes no text children.
        for title in ["Canvas", "Feeds", "Me"] {
            XCTAssertFalse(app.staticTexts[title].exists)
        }

        tabs[1].tap()
        XCTAssertTrue(sound.waitForNonExistence(timeout: 3))
        XCTAssertTrue(add.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        XCTAssertTrue(app.buttons["tab_feeds"].exists)
        XCTAssertTrue(app.buttons["tab_me"].exists)

        app.buttons["tab_me"].tap()
        XCTAssertFalse(app.buttons["canvas_sound_button"].exists)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
    }

    func testActivitySuggestionAppearsDirectlyAboveTheBottomMenu() {
        let app = launchCanvas()
        let suggestion = app.descendants(matching: .any)["canvas_activity_suggestions"]
        let tabBar = app.descendants(matching: .any)["canvas_tab_bar"]

        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.exists)
        let gap = tabBar.frame.minY - suggestion.frame.maxY
        let geometry = "suggestion=\(suggestion.frame), tab=\(tabBar.frame), gap=\(gap)"
        XCTAssertGreaterThanOrEqual(gap, 8, geometry)
        XCTAssertLessThanOrEqual(gap, 18, geometry)
    }

    func testActivitySuggestionsFormACompactTwoLayerStack() {
        let app = launchCanvas(additionalArguments: ["ui-testing-suggestion-stack"])
        let front = app.descendants(matching: .any)["canvas_activity_suggestion_front"]
        let back = app.descendants(matching: .any)["canvas_activity_suggestion_back"]

        XCTAssertTrue(front.waitForExistence(timeout: 5))
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertLessThan(back.frame.maxY, front.frame.maxY)
        XCTAssertLessThan(back.frame.width, front.frame.width)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'more'")
        ).firstMatch.exists)
        XCTAssertFalse(app.buttons["Dismiss all"].exists)
    }

    func testPullingTheEnergyPillOpensAndBottomHandleClosesWithoutMovingThePill() {
        let app = launchCanvas()
        let pill = energyPill(in: app)
        let pillFrameBefore = pill.frame

        openDataDrawer(in: app)
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)

        let happeningsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Happenings,'")
        ).firstMatch
        let handle = dataHandle(in: app)
        XCTAssertTrue(happeningsRow.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(handle.frame.midY, happeningsRow.frame.maxY)

        closeDataDrawer(in: app)
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)
    }

    func testPullingTheCollapsedHandleAlsoOpensThePanel() {
        let app = launchCanvas()
        let handle = dataHandle(in: app)
        XCTAssertTrue(handle.waitForExistence(timeout: 3))

        pullDown(handle)

        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))
    }

    func testTappingFreeCanvasClosesTheDataPanel() {
        let app = launchCanvas()
        openDataDrawer(in: app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()

        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(dataHandle(in: app).waitForExistence(timeout: 3))
    }

    func testTappingTheHandleDoesNotOpenThePanel() {
        let app = launchCanvas()

        dataHandle(in: app).tap()

        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    func testHandleSitsCloseToTheEnergyPill() {
        let app = launchCanvas()
        let pill = app.descendants(matching: .any)["canvas_energy_pill"]
        let handle = dataHandle(in: app)

        // The pill's accessibility frame hugs its text/bar content rather
        // than the 58pt visual glass frame. Reconstruct the visual bottom
        // from that documented minimum height before comparing the gap.
        let pillVisualBottom = pill.frame.maxY + max(0, (58 - pill.frame.height) / 2)
        // The handle's button frame starts at the visible 16pt footer and
        // extends its hit target downward to 44pt. The 4pt capsule is centred
        // inside that footer, not inside the full accessibility target.
        let visibleHandleTop = handle.frame.minY + (16 - 4) / 2
        let gap = visibleHandleTop - pillVisualBottom
        let geometry = "pill=\(pill.frame), handle=\(handle.frame), gap=\(gap)"
        XCTAssertGreaterThanOrEqual(gap, 6, geometry)
        XCTAssertLessThanOrEqual(gap, 10, geometry)
    }

    func testExpandedDataRowsStayCompact() {
        let app = launchCanvas()
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Canvas daily chrome — collapsed"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        openDataDrawer(in: app)

        let stepsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Steps,'")
        ).firstMatch
        XCTAssertTrue(stepsRow.waitForExistence(timeout: 3))
        // Labels and the separate progress line now occupy a two-line row.
        XCTAssertGreaterThanOrEqual(stepsRow.frame.height, 44)
        XCTAssertLessThanOrEqual(stepsRow.frame.height, 68)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Canvas daily chrome — expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
    }

    func testActivitySuggestionDoesNotMoveWhenDataPanelOpens() {
        let app = launchCanvas()
        let suggestion = app.descendants(matching: .any)["canvas_activity_suggestions"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        let frameBefore = suggestion.frame

        openDataDrawer(in: app)

        XCTAssertEqual(suggestion.frame.midY, frameBefore.midY, accuracy: 1)
    }

    func testFullScreenHidesChromeAndDoesNotStartEditing() {
        let app = launchCanvas(additionalArguments: ["-canvasVisualStyle_v1", "legacy"])
        app.buttons["canvas_sound_button"].tap()
        XCTAssertTrue(app.buttons["canvas_close_fullscreen_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_fullscreen_share_button"].exists)
        XCTAssertTrue(app.buttons["canvas_remix_button"].exists)
        XCTAssertFalse(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_undo_remix_button"].exists)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
        XCTAssertFalse(dataHandle(in: app).exists)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
    }

    func testCloseReturnsToCanvasWithoutWaitingForAudioStartup() {
        let app = launchCanvas()
        app.buttons["canvas_sound_button"].tap()
        let close = app.buttons["canvas_close_fullscreen_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isEnabled)
        close.tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_canvas"].exists)
    }

    func testFullScreenRemixKeepsCompactViewingActions() {
        let app = launchCanvas()
        app.buttons["canvas_sound_button"].tap()
        let remix = app.buttons["canvas_remix_button"]
        XCTAssertTrue(remix.waitForExistence(timeout: 5))
        remix.tap()
        XCTAssertTrue(app.buttons["canvas_close_fullscreen_button"].exists)
        XCTAssertTrue(app.buttons["canvas_fullscreen_share_button"].exists)
        XCTAssertFalse(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_undo_remix_button"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Compact viewing dock"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddReplacesTheTabBarWithTheHappeningDock() {
        let app = launchCanvas()
        let tabBar = app.descendants(matching: .any)["canvas_tab_bar"]

        XCTAssertTrue(tabBar.exists)

        app.buttons["canvas_add_button"].tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose happenings"].exists)
        XCTAssertTrue(app.buttons["Add a happening"].exists)
        XCTAssertTrue(tabBar.waitForNonExistence(timeout: 3))
    }

    /// The `+` and the full-screen circle are removed from the tree while
    /// the drawer is open, not merely covered — a panel the user can't see
    /// through must not leave a live hit region under it. That also means
    /// there is no longer a way to open the happening palette without first
    /// closing the drawer (the drawer's own handle both opens and closes it),
    /// so the palette/data interlock this test used to exercise via
    /// `canvas_add_button` is structurally unreachable now; this asserts the
    /// hide instead.
    func testAddAndFullScreenAreUnavailableWhileTheDataPanelIsOpen() {
        let app = launchCanvas()

        openDataDrawer(in: app)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
        XCTAssertFalse(app.buttons["canvas_sound_button"].exists)

        closeDataDrawer(in: app)
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_sound_button"].exists)
    }

    /// Metric explanations live inside the drawer: tapping the same row
    /// collapses it, while tapping another row switches the open disclosure.
    func testMetricRowsToggleInlineExplanations() {
        let app = launchCanvas()

        openDataDrawer(in: app)

        let stepsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Steps,'")
        ).firstMatch
        XCTAssertTrue(stepsRow.waitForExistence(timeout: 3))
        stepsRow.tap()

        let stepsDisclosure = app.descendants(matching: .any)["canvas_metric_disclosure_steps"]
        XCTAssertTrue(stepsDisclosure.waitForExistence(timeout: 3))
        let researchLink = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Why this matters'")
        ).firstMatch
        XCTAssertTrue(researchLink.waitForExistence(timeout: 3))

        stepsRow.tap()
        XCTAssertTrue(stepsDisclosure.waitForNonExistence(timeout: 3))

        stepsRow.tap()
        XCTAssertTrue(stepsDisclosure.waitForExistence(timeout: 3))

        let sleepRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Sleep,'")
        ).firstMatch
        XCTAssertTrue(sleepRow.waitForExistence(timeout: 3))
        sleepRow.tap()

        XCTAssertTrue(stepsDisclosure.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["canvas_metric_disclosure_sleep"]
                .waitForExistence(timeout: 3)
        )
    }
}

/// Uses an otherwise empty, dedicated QA simulator with the real product views.
/// The fixture flag isolates coordinator persistence only; it never grants colors or tokens.
final class DebugCanvasOnboardingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "debug-canvas-tour-welcome", "debug-canvas-tour-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["canvas_tour.begin"].waitForExistence(timeout: 20), app.debugDescription)
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTourDoesNotResizeTheCanvasViewport() {
        let app = launch()
        let viewport = app.descendants(matching: .any)["canvas_render_viewport"].firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let welcomeFrame = viewport.frame
        capture(app, "tour-viewport-welcome")
        app.buttons["canvas_tour.begin"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.add"].waitForExistence(timeout: 5))
        let actionFrame = viewport.frame
        capture(app, "tour-viewport-add")
        app.buttons["canvas_tour.skip"].tap()
        app.buttons["canvas_tour.exit.confirm"].tap()
        XCTAssertTrue(app.buttons["canvas_sound_button"].waitForExistence(timeout: 5))
        let normalFrame = viewport.frame
        capture(app, "tour-viewport-normal")
        let frames = XCTAttachment(string: "window=\(app.frame)\nwelcome=\(welcomeFrame)\naction=\(actionFrame)\nnormal=\(normalFrame)")
        frames.name = "canvas-viewport-frames"; frames.lifetime = .keepAlways; add(frames)
        XCTAssertEqual(welcomeFrame.width, normalFrame.width, accuracy: 1)
        XCTAssertEqual(welcomeFrame.height, normalFrame.height, accuracy: 1, "Welcome must not shrink the render viewport")
        XCTAssertEqual(welcomeFrame.minY, normalFrame.minY, accuracy: 1)
        XCTAssertEqual(actionFrame.height, normalFrame.height, accuracy: 1, "Action coaching must not change the canvas aspect ratio")
        XCTAssertEqual(actionFrame.minY, normalFrame.minY, accuracy: 1)
    }
    func testOutsideTapAsksAndResumeKeepsExactStep() {
        let app = launch()
        let welcome = app.descendants(matching: .any)["canvas_tour.card.welcome"].firstMatch
        XCTAssertFalse(welcome.buttons["canvas_tour.skip"].exists, "Exit belongs to the screen, not the coach card")
        let skip = app.buttons["canvas_tour.skip"]
        XCTAssertLessThan(skip.frame.midY, app.frame.height * 0.2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        let keepGoing = app.buttons["canvas_tour.exit.continue"]
        XCTAssertTrue(keepGoing.waitForExistence(timeout: 5))
        capture(app, "tour-outside-tap-confirmation")
        keepGoing.tap()
        XCTAssertTrue(app.buttons["canvas_tour.begin"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.begin"].tap()
        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.happening"].waitForExistence(timeout: 5))
        XCTAssertFalse(keepGoing.exists, "A taught action must not count as a missed tap")
        skip.tap()
        XCTAssertTrue(keepGoing.waitForExistence(timeout: 5))
        keepGoing.tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.happening"].waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["canvas_tour.exit.confirm"].tap()
        XCTAssertFalse(skip.exists)
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
    }

    func testRealMomentDrawerAndOptionalBranches() {
        let app = launch()
        capture(app, "tour-welcome")
        app.buttons["canvas_tour.begin"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        app.buttons["canvas_add_button"].tap()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "happening_choice_"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        capture(app, "tour-happenings")
        guard let choice = choices.allElementsBoundByIndex.first(where: { $0.isEnabled && $0.isHittable }) else {
            XCTFail("No available actual happening"); return
        }
        choice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.happening"].exists)
        choice.tap()
        let next = app.buttons["canvas_tour.momentNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        capture(app, "tour-moment-result")
        XCTAssertFalse(app.buttons["canvas_tour.healthLater"].exists)
        next.tap()
        let handle = app.descendants(matching: .any)["canvas_show_data_button"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.balance"].waitForExistence(timeout: 8))
        let pill = app.descendants(matching: .any)["canvas_energy_pill"].firstMatch.frame
        XCTAssertLessThanOrEqual(handle.frame.minY, pill.maxY + 24, "Grabber must sit directly below the actual balance pill")
        capture(app, "tour-balance")
        handle.tap()
        XCTAssertTrue(app.buttons["canvas_tour.healthLater"].waitForExistence(timeout: 5))
        let panelFrame = app.descendants(matching: .any)["canvas_data_panel"].firstMatch.frame
        let healthCardFrame = app.descendants(matching: .any)["canvas_tour.card.healthValue"].firstMatch.frame
        XCTAssertFalse(panelFrame.intersects(healthCardFrame), "The Health coach must clear the drawer footer")
        XCTAssertTrue(app.buttons["canvas_tour.health"].isHittable, "Connect must stay outside the text scroll area")
        XCTAssertTrue(app.buttons["canvas_tour.healthLater"].isHittable, "Later must be visible without scrolling")
        XCTAssertFalse(app.scrollViews["canvas_tour.textScroll"].exists, "The Health explanation must fit at the default text size")
        capture(app, "tour-health")
        app.buttons["canvas_tour.healthLater"].tap()
        app.buttons["canvas_tour.healthContinue"].tap()
        XCTAssertFalse(app.buttons["feed.add"].exists)
        capture(app, "tour-feeds-tab")
        app.buttons["tab_feeds"].tap()
        XCTAssertTrue(app.buttons["feed.add"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["feed.add"].frame.minY, app.buttons["canvas_tour.skip"].frame.maxY,
                                    "The exit toolbar must not overlap Feeds controls")
        capture(app, "tour-choose-apps")
        app.buttons["canvas_tour.skipApps"].tap()
        capture(app, "tour-me-tab")
        app.buttons["tab_me"].tap()
        let later = app.buttons["canvas_tour.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in later.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let posterFrame = app.descendants(matching: .any)["me_poster_carousel"].firstMatch.frame
        let coachFrame = app.descendants(matching: .any)["canvas_tour.card.saveDays"].firstMatch.frame
        XCTAssertLessThanOrEqual(posterFrame.maxY + 8, coachFrame.minY, "The coach must not cover today's poster")
        capture(app, "tour-save-days")
        later.tap()
        XCTAssertTrue(app.buttons["canvas_tour.setup.continue"].waitForExistence(timeout: 5))
        capture(app, "tour-setup")
        app.buttons["canvas_tour.setup.continue"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.skipExport"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["me_share_selected_day"].frame.minY, app.buttons["canvas_tour.skip"].frame.maxY,
                                    "The exit toolbar must not overlap Me controls")
        capture(app, "tour-poster")
        app.buttons["canvas_tour.skipExport"].tap()
        capture(app, "tour-finish-card")
        app.buttons["canvas_tour.finish"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_sound_button"].isHittable)
        XCTAssertTrue(app.buttons["tab_me"].isHittable)
        XCTAssertFalse(app.buttons["canvas_tour.skip"].exists)
        capture(app, "tour-finished")
    }
    func testStopRestoresControlsAndRestartAlwaysShowsWelcome() {
        let app = launch()
        app.buttons["canvas_tour.begin"].tap()
        app.buttons["canvas_tour.controls"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.debug.restart"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.debug.restart"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.begin"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.skip"].tap()
        app.buttons["canvas_tour.exit.confirm"].tap()
        XCTAssertTrue(app.buttons["canvas_sound_button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_feeds"].isHittable)
        XCTAssertTrue(app.buttons["canvas_add_button"].isHittable)
    }
    func testDragDrawerAndShareCancellation() {
        let app = launch()
        app.buttons["canvas_tour.begin"].tap()
        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.existingDay"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.existingDay"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.momentNext"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.momentNext"].tap()
        let handle = app.descendants(matching: .any)["canvas_show_data_button"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 120)))
        XCTAssertTrue(app.buttons["canvas_tour.healthLater"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.healthLater"].tap()
        app.buttons["canvas_tour.healthContinue"].tap()
        app.buttons["tab_feeds"].tap()
        XCTAssertGreaterThanOrEqual(app.buttons["feed.add"].frame.minY, app.buttons["canvas_tour.skip"].frame.maxY,
                                    "The exit toolbar must not overlap Feeds controls")
        capture(app, "tour-choose-apps")
        app.buttons["canvas_tour.skipApps"].tap()
        capture(app, "tour-me-tab")
        app.buttons["tab_me"].tap()
        let later = app.buttons["canvas_tour.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in later.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        later.tap()
        app.buttons["canvas_tour.setup.continue"].tap()
        let share = app.buttons["me_share_selected_day"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(share.frame.minY, app.buttons["canvas_tour.skip"].frame.maxY,
                                    "The exit toolbar must not overlap Me share")
        share.tap()
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 25), app.debugDescription)
        capture(app, "tour-real-share")
        close.tap()
        XCTAssertTrue(app.buttons["canvas_tour.finish"].waitForExistence(timeout: 8))
        app.buttons["canvas_tour.finish"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
    }

    func testSetupPagesKeepExitAndReturnContext() {
        let app = launch()
        app.buttons["canvas_tour.begin"].tap()
        app.buttons["canvas_add_button"].tap()
        app.buttons["canvas_tour.existingDay"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.momentNext"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.momentNext"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["canvas_tour.card.balance"].waitForExistence(timeout: 5))
        let handle = app.descendants(matching: .any)["canvas_show_data_button"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.tap()
        XCTAssertTrue(app.buttons["canvas_tour.healthLater"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.healthLater"].tap()
        app.buttons["canvas_tour.healthContinue"].tap()
        app.buttons["tab_feeds"].tap()
        app.buttons["canvas_tour.skipApps"].tap()
        app.buttons["tab_me"].tap()
        let later = app.buttons["canvas_tour.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in later.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        later.tap()
        XCTAssertTrue(app.buttons["canvas_tour.setup.continue"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.setup.notifications"].tap()
        capture(app, "tour-setup-notifications")
        XCTAssertEqual(app.buttons.matching(identifier: "canvas_tour.skip").count, 1)
        XCTAssertTrue(app.buttons["canvas_tour.skip"].isHittable, app.debugDescription)
        app.buttons["canvas_tour.setup.notifications.later"].tap()
        app.buttons["canvas_tour.setup.health"].tap()
        capture(app, "tour-setup-health")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["canvas_tour.setup.appAccess"].tap()
        capture(app, "tour-setup-app-access")
        app.buttons["canvas_tour.skip"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.exit.continue"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.exit.continue"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["canvas_tour.setup.account"].tap()
        let close = app.buttons["Dismiss"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        capture(app, "tour-setup-login")
        XCTAssertTrue(app.buttons["canvas_tour.skip"].isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["canvas_tour.setup.continue"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.setup.continue"].tap()
        app.buttons["canvas_tour.skipExport"].tap()
        app.buttons["canvas_tour.finish"].tap()
        XCTAssertFalse(app.buttons["canvas_tour.skip"].exists)
    }

    func testLargeTextMomentNextKeepsRealHandleAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "debug-canvas-tour-welcome", "debug-canvas-tour-fixtures", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["canvas_tour.begin"].waitForExistence(timeout: 20))
        app.buttons["canvas_tour.begin"].tap()
        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.existingDay"].waitForExistence(timeout: 5))
        app.buttons["canvas_tour.existingDay"].tap()
        let next = app.buttons["canvas_tour.momentNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable, "Next must remain outside the scrolling explanation")
        capture(app, "tour-moment-accessibility")
        next.tap()
        let handle = app.descendants(matching: .any)["canvas_show_data_button"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(handle.isHittable, "The Pull it down coach must leave the real handle accessible")
        capture(app, "tour-balance-accessibility")
        app.buttons["canvas_tour.skip"].tap()
        app.buttons["canvas_tour.exit.confirm"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].isHittable)
    }

    func testLargeTextKeepsSkipAndActualTargetAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing", "debug-canvas-tour-welcome", "debug-canvas-tour-fixtures", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleLanguages", "(en)"]
        app.launch()
        let begin = app.buttons["canvas_tour.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["canvas_tour.skip"].isHittable)
        begin.tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].isHittable)
        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.buttons["canvas_tour.skip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["canvas_tour.skip"].isHittable)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "happening_choice_"))
        XCTAssertTrue(choices.allElementsBoundByIndex.contains { $0.isEnabled && $0.isHittable })
        capture(app, "tour-accessibility-text")
        app.buttons["canvas_tour.skip"].tap()
        app.buttons["canvas_tour.exit.confirm"].tap()
        // The ordinary product palette intentionally hides tabs until closed.
        XCTAssertTrue(app.buttons["canvas_palette_close_button"].isHittable)
        app.buttons["canvas_palette_close_button"].tap()
        XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_me"].isHittable)
    }

}
