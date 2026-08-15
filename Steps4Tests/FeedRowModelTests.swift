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
}
