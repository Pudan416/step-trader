import XCTest

final class CustomActivityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCustomActivityAppearsInCategorySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing"]

        let seedJSON = """
        [{"id":"custom_body_uitest","titleEn":"UITest Custom Card","category":"body","icon":"figure.run"}]
        """
        app.launchEnvironment["UITEST_CUSTOM_ENERGY_OPTIONS"] = seedJSON
        app.launch()

        let canvasTab = app.buttons["tab_canvas"]
        XCTAssertTrue(canvasTab.waitForExistence(timeout: 5))
        canvasTab.tap()

        let openBody = app.buttons["uitest_open_body"]
        XCTAssertTrue(openBody.waitForExistence(timeout: 5))
        openBody.tap()

        let customOption = app.descendants(matching: .any)
            .matching(identifier: "category_option_custom_body_uitest")
            .firstMatch
        if !customOption.waitForExistence(timeout: 5) {
            let scrollable = app.scrollViews.firstMatch
            for _ in 0..<6 where !customOption.exists {
                scrollable.swipeUp()
            }
        }
        XCTAssertTrue(customOption.exists)
    }
}
