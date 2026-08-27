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

    func testTicketShapeUsesAFullHeightRoundedCap() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 82)
        let path = FeedTicketShape().path(in: bounds)

        XCTAssertFalse(
            path.contains(CGPoint(x: 10, y: 10)),
            "A full-height cap must cut farther into the corner than the old rounded rectangle"
        )
        XCTAssertTrue(path.contains(CGPoint(x: 4, y: 41)))
    }

    func testTicketShapeKeepsTheTrailingMenuInsideTheCard() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 82)
        let path = FeedTicketShape().path(in: bounds)

        XCTAssertTrue(
            path.contains(CGPoint(x: 300, y: 41)),
            "The reference uses an inset menu inside a continuous rounded card, not a cutout"
        )
    }

}

final class ResourceGradientLayoutTests: XCTestCase {

    func testDarkSideSpansTheWholeLeadingEdge() {
        let layout = ResourceGradientLayout.make(in: CGSize(width: 180, height: 82))

        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 0)), 0.95)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 41)), 0.95)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 82)), 0.95)
    }

    func testCircularGradientTravelsFromRightToLeft() {
        let layout = ResourceGradientLayout.make(in: CGSize(width: 180, height: 82))

        XCTAssertLessThan(layout.progress(at: CGPoint(x: 180, y: 41)), 0.35)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 41)), 0.95)
    }
}

final class FeedInlineExpansionTests: XCTestCase {

    func testTappingALockedGroupExpandsItsUnlockOptionsAndRequestsScroll() {
        let result = FeedInlineExpansion().toggling(groupID: "instagram")

        XCTAssertEqual(result.expandedGroupID, "instagram")
        XCTAssertEqual(result.scrollTargetID, "instagram-unlock-options")
    }

    func testTappingAnotherGroupMovesTheExpansion() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        let result = current.toggling(groupID: "youtube")

        XCTAssertEqual(result.expandedGroupID, "youtube")
        XCTAssertEqual(result.scrollTargetID, "youtube-unlock-options")
    }

    func testTappingTheExpandedGroupCollapsesIt() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        XCTAssertEqual(current.toggling(groupID: "instagram"), FeedInlineExpansion())
    }

    func testSuccessfulPurchaseCollapsesOnlyThePurchasedGroup() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        XCTAssertEqual(current.collapsing(groupID: "youtube"), current)
        XCTAssertEqual(current.collapsing(groupID: "instagram"), FeedInlineExpansion())
    }

    func testAutoScrollOnlyStartsWhenOptionsReachTheTabBar() {
        XCTAssertFalse(
            FeedInlineLayout.needsAutoScroll(
                optionsBottom: 450,
                viewportHeight: 640,
                tabBarHeight: 90
            )
        )
        XCTAssertTrue(
            FeedInlineLayout.needsAutoScroll(
                optionsBottom: 550,
                viewportHeight: 640,
                tabBarHeight: 90
            )
        )
    }
}
