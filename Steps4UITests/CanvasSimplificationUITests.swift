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
        openDataDrawer(in: app)

        let stepsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Steps,'")
        ).firstMatch
        XCTAssertTrue(stepsRow.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(stepsRow.frame.height, 44)
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
