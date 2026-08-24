import XCTest
@testable import Steps4

final class FeedRowModelTests: XCTestCase {

    // MARK: - Icon source

    func testRegistryAppUsesBundledAsset() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.burbn.instagram"),
            .asset("instagram")
        )
    }

    func testUnknownAppFallsBackToSystemLabel() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.example.unknown"),
            .systemLabel
        )
    }

    func testNilBundleIdFallsBackToSystemLabel() {
        XCTAssertEqual(FeedRowModel.iconSource(forBundleId: nil), .systemLabel)
    }

    // MARK: - Row kind

    func testSingleAppGroupRendersAsPlainIcon() {
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 1)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testTemplateGroupWithNoTokensStillRendersAsSingle() {
        // Template groups are validated to exactly one app, but the token count
        // can read zero before the picker's selection has been persisted.
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 0)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testCustomGroupWithTwoAppsRendersAsCluster() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 2)
        XCTAssertEqual(kind, .cluster(sources: [.systemLabel, .systemLabel], total: 2))
    }

    func testClusterCapsRenderedIconsButKeepsTrueTotal() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 7)
        XCTAssertEqual(
            kind,
            .cluster(sources: Array(repeating: .systemLabel, count: FeedRowModel.clusterDisplayLimit), total: 7)
        )
    }

    func testCustomGroupWithOneAppRendersAsPlainIcon() {
        XCTAssertEqual(FeedRowModel.kind(templateApp: nil, appTokenCount: 1), .single(.systemLabel))
    }

    // MARK: - Access state

    func testZeroRemainingMinutesRendersLockedState() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 0, initialMinutes: 30),
            .locked
        )
    }

    func testFreshWindowFillsTheWholeRow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 30, initialMinutes: 30),
            .active(remainingMinutes: 30, fillFraction: 1)
        )
    }

    func testSpentWindowUsesRemainingShareAsRowFill() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 18, initialMinutes: 30),
            .active(remainingMinutes: 18, fillFraction: 0.6)
        )
    }

    func testRemainingMinutesCannotOverfillTheRow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 40, initialMinutes: 30),
            .active(remainingMinutes: 40, fillFraction: 1)
        )
    }

    func testMissingInitialBudgetTreatsCurrentValueAsFreshWindow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 10, initialMinutes: 0),
            .active(remainingMinutes: 10, fillFraction: 1)
        )
    }

    // MARK: - Row action

    func testLockedRowOpensDurationPicker() {
        XCTAssertEqual(
            FeedRowModel.tapAction(for: .locked, canOpen: true),
            .chooseDuration
        )
    }

    func testActiveLaunchableRowOpensItsApp() {
        XCTAssertEqual(
            FeedRowModel.tapAction(
                for: .active(remainingMinutes: 18, fillFraction: 0.6),
                canOpen: true
            ),
            .openApp
        )
    }

    func testActiveCustomRowFallsBackToSettings() {
        XCTAssertEqual(
            FeedRowModel.tapAction(
                for: .active(remainingMinutes: 18, fillFraction: 0.6),
                canOpen: false
            ),
            .openSettings
        )
    }

    // MARK: - Ticket shape

    func testTicketShapeCarvesSpaceForTheTrailingMenu() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 82)
        let path = FeedTicketShape().path(in: bounds)

        XCTAssertTrue(path.contains(CGPoint(x: 258, y: 41)), "The timer body must remain tappable before the notch")
        XCTAssertFalse(path.contains(CGPoint(x: 300, y: 41)), "The trailing menu needs a concave cutout")
        XCTAssertTrue(path.contains(CGPoint(x: 300, y: 12)), "Only the middle of the trailing edge should be cut out")
    }

}
