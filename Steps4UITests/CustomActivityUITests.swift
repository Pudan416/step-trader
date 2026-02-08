import XCTest

final class CustomActivityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        seedDefaults()
    }
    
    override func tearDownWithError() throws {
        clearDefaults()
    }

    func testCustomActivityAppearsInCategorySettings() {
        let app = XCUIApplication()
        app.launchArguments = ["ui-testing"]
        app.launch()

        let galleryTab = app.buttons["tab_gallery"]
        XCTAssertTrue(galleryTab.waitForExistence(timeout: 5))
        galleryTab.tap()

        let activityChip = app.buttons["chip_activity"]
        XCTAssertTrue(activityChip.waitForExistence(timeout: 5))
        activityChip.tap()

        let editButton = app.buttons["category_edit_button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let customTitle = "UITest Custom Activity"
        if !app.staticTexts[customTitle].waitForExistence(timeout: 3) {
            let scrollView = app.scrollViews.firstMatch
            for _ in 0..<5 where !app.staticTexts[customTitle].exists {
                scrollView.swipeUp()
            }
        }
        XCTAssertTrue(app.staticTexts["UITest Custom Activity"].exists)
    }

    private func seedDefaults() {
        let standard = UserDefaults.standard
        standard.set(true, forKey: "hasSeenIntro_v3")
        standard.set(true, forKey: "hasSeenEnergySetup_v1")
        standard.set(true, forKey: "hasCompletedOnboarding_v1")
        standard.set("en", forKey: "appLanguage")

        guard let appGroup = UserDefaults(suiteName: "group.personal-project.StepsTrader") else {
            XCTFail("App Group defaults not available")
            return
        }

        struct CustomOptionSeed: Codable {
            let id: String
            let titleEn: String
            let titleRu: String
            let category: String
            let icon: String
        }

        let seed = CustomOptionSeed(
            id: "custom_activity_uitest",
            titleEn: "UITest Custom Activity",
            titleRu: "UITest Custom Activity",
            category: "activity",
            icon: "figure.run"
        )

        if let data = try? JSONEncoder().encode([seed]) {
            appGroup.set(data, forKey: "customEnergyOptions_v1")
        }
    }

    private func clearDefaults() {
        let standard = UserDefaults.standard
        standard.removeObject(forKey: "hasSeenIntro_v3")
        standard.removeObject(forKey: "hasSeenEnergySetup_v1")
        standard.removeObject(forKey: "hasCompletedOnboarding_v1")
        standard.removeObject(forKey: "appLanguage")

        if let appGroup = UserDefaults(suiteName: "group.personal-project.StepsTrader") {
            appGroup.removeObject(forKey: "customEnergyOptions_v1")
        }
    }
}
