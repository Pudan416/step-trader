import XCTest
@testable import Steps4

/// `@SceneStorage("selectedTab")` survives app updates, so a raw value stored by
/// the five-tab build must resolve to something that still exists.
final class MainTabSelectionTests: XCTestCase {

    func testKnownRawValuesResolveToThemselves() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 0), .canvas)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 1), .feeds)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 2), .me)
    }

    func testRetiredSettingsRawValueResolvesToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 4), .canvas)
    }

    func testOutOfRangeRawValuesResolveToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: -1), .canvas)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 99), .canvas)
    }

    func testSettingsIsNoLongerATab() {
        XCTAssertNil(MainTabView.Tab.allCases.first { $0.accessibilityId == "tab_settings" })
    }

    func testTabBarHasExactlyThreeDestinations() {
        XCTAssertEqual(MainTabView.Tab.allCases.count, 3)
    }

    func testRetiredHistoryRawValueResolvesToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 3), .canvas)
    }

    func testTabsUseRequestedContourSymbols() {
        XCTAssertEqual(MainTabView.Tab.canvas.icon, "scribble.variable")
        XCTAssertEqual(MainTabView.Tab.feeds.icon, "line.3.horizontal")
        XCTAssertEqual(MainTabView.Tab.me.icon, "person.circle")
    }
}
