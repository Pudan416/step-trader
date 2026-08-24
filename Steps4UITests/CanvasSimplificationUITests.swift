import XCTest

/// The Canvas screen's four states and the paths between them. These assert
/// structure, not looks: which controls exist, and where a tap lands you.
final class CanvasSimplificationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchCanvas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-task7",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
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

        XCTAssertTrue(app.buttons["canvas_fullscreen_button"].exists)
        XCTAssertTrue(dataHandle(in: app).exists)
        XCTAssertTrue(app.buttons["canvas_add_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    func testBottomNavigationIsCompactIconOnlyAndSharesTheCanvasActionBaseline() {
        let app = launchCanvas()
        let fullScreen = app.buttons["canvas_fullscreen_button"]
        let add = app.buttons["canvas_add_button"]
        let tabs = ["tab_canvas", "tab_feeds", "tab_me"].map { app.buttons[$0] }

        for tab in tabs {
            XCTAssertTrue(tab.exists)
            XCTAssertLessThanOrEqual(tab.frame.height, 48)
            XCTAssertEqual(tab.frame.midY, add.frame.midY, accuracy: 2)
        }
        XCTAssertEqual(fullScreen.frame.midY, add.frame.midY, accuracy: 2)

        // The destination names remain on the buttons for VoiceOver, but the
        // visual tab bar is glyph-only and therefore exposes no text children.
        for title in ["Canvas", "Feeds", "Me"] {
            XCTAssertFalse(app.staticTexts[title].exists)
        }

        tabs[1].tap()
        XCTAssertTrue(fullScreen.waitForNonExistence(timeout: 3))
        XCTAssertTrue(add.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tab_canvas"].exists)
        XCTAssertTrue(app.buttons["tab_feeds"].exists)
        XCTAssertTrue(app.buttons["tab_me"].exists)

        app.buttons["tab_me"].tap()
        XCTAssertFalse(app.buttons["canvas_fullscreen_button"].exists)
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

    /// Raising the canvas is a viewing action. Nothing in it may start an edit.
    func testFullScreenHidesChromeAndDoesNotStartEditing() {
        let app = launchCanvas()

        app.buttons["canvas_fullscreen_button"].tap()

        XCTAssertTrue(app.buttons["canvas_exit_fullscreen_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
        XCTAssertFalse(dataHandle(in: app).exists)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        XCTAssertFalse(app.buttons["canvas_remix_button"].exists)
        XCTAssertFalse(app.buttons["canvas_done_button"].exists)
    }

    func testDoneReturnsToFullScreenAndExitReturnsToCanvas() {
        let app = launchCanvas()

        app.buttons["canvas_fullscreen_button"].tap()
        XCTAssertTrue(app.buttons["canvas_edit_button"].waitForExistence(timeout: 3))
        app.buttons["canvas_edit_button"].tap()

        XCTAssertTrue(app.buttons["canvas_done_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_remix_button"].exists)

        app.buttons["canvas_done_button"].tap()
        // Done goes back to viewing, not all the way out.
        XCTAssertTrue(app.buttons["canvas_exit_fullscreen_button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)

        app.buttons["canvas_exit_fullscreen_button"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 3))
    }

    func testAddOpensTheExistingHappeningPalette() {
        let app = launchCanvas()

        app.buttons["canvas_add_button"].tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose happenings"].exists)
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
        XCTAssertFalse(app.buttons["canvas_fullscreen_button"].exists)

        closeDataDrawer(in: app)
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_fullscreen_button"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["canvas_metric_research_link_steps"].exists)

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
