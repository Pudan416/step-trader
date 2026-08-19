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

    func testCanvasShowsExactlyThreeBottomActions() {
        let app = launchCanvas()

        XCTAssertTrue(app.buttons["canvas_fullscreen_button"].exists)
        XCTAssertTrue(app.buttons["canvas_show_data_button"].exists)
        XCTAssertTrue(app.buttons["canvas_add_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    func testShowDataOpensAndClosesThePanelWithoutMovingThePill() {
        let app = launchCanvas()
        let pill = app.descendants(matching: .any)["canvas_energy_pill"]
        let pillFrameBefore = pill.frame

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)
    }

    /// Raising the canvas is a viewing action. Nothing in it may start an edit.
    func testFullScreenHidesChromeAndDoesNotStartEditing() {
        let app = launchCanvas()

        app.buttons["canvas_fullscreen_button"].tap()

        XCTAssertTrue(app.buttons["canvas_exit_fullscreen_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
        XCTAssertFalse(app.buttons["canvas_show_data_button"].exists)
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

    func testOpeningThePaletteDismissesTheDataPanel() {
        let app = launchCanvas()

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))

        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    /// The `?` opens the metric overlay with its explanation, and does so
    /// without the row's own tap firing as well.
    func testRowHelpOpensTheExplanation() {
        let app = launchCanvas()

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))

        app.buttons["canvas_row_help_steps"].tap()

        // SwiftUI's `Link` surfaces to XCUITest as a Button element on this
        // iOS version, not `.link` — `app.links[...]` never matches it. Match
        // by identifier across any element type instead, the same pattern
        // this file already uses for `canvas_energy_pill`.
        XCTAssertTrue(app.descendants(matching: .any)["metric_research_link_steps"].waitForExistence(timeout: 3))
    }
}
