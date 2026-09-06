import XCTest
@testable import Steps4

final class DayCanvasArtworkRoutingTests: XCTestCase {
    func testThumbnailCacheIdentityIncludesVisualStyle() {
        XCTAssertNotEqual(
            HistoryThumbnailCache.cacheIdentity(
                dayKey: "2026-09-06",
                style: .legacy
            ),
            HistoryThumbnailCache.cacheIdentity(
                dayKey: "2026-09-06",
                style: .editorial
            )
        )
    }

    func testExportRouteUsesSavedCanvasVisualStyle() {
        var legacyCanvas = DayCanvas(dayKey: "2026-09-05")
        legacyCanvas.visualStyleRaw = CanvasVisualStyle.legacy.rawValue
        var editorialCanvas = DayCanvas(dayKey: "2026-09-06")
        editorialCanvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue

        XCTAssertEqual(CanvasExportRoute(canvas: legacyCanvas), .legacySwiftUI)
        XCTAssertEqual(CanvasExportRoute(canvas: editorialCanvas), .editorialMetal)
    }

    func testEditorialDoesNotConstructLegacyLayers() {
        let policy = DayCanvasArtworkLayerPolicy(style: .editorial)

        XCTAssertTrue(policy.usesEditorial)
        XCTAssertFalse(policy.usesLegacyBackground)
        XCTAssertFalse(policy.usesRasterTexture)
        XCTAssertTrue(policy.usesInteractiveAnimationOverlay)
        XCTAssertEqual(policy.animationSnapshotSource, .editorialMetal)
    }

    func testLegacyKeepsExistingLayers() {
        let policy = DayCanvasArtworkLayerPolicy(style: .legacy)

        XCTAssertFalse(policy.usesEditorial)
        XCTAssertTrue(policy.usesLegacyBackground)
        XCTAssertTrue(policy.usesRasterTexture)
        XCTAssertTrue(policy.usesInteractiveAnimationOverlay)
        XCTAssertEqual(policy.animationSnapshotSource, .legacySwiftUI)
    }
}
