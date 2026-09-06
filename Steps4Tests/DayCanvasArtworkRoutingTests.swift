import XCTest
@testable import Steps4

final class DayCanvasArtworkRoutingTests: XCTestCase {
    func testEditorialDoesNotConstructLegacyLayers() {
        let policy = DayCanvasArtworkLayerPolicy(style: .editorial)

        XCTAssertTrue(policy.usesEditorial)
        XCTAssertFalse(policy.usesLegacyBackground)
        XCTAssertFalse(policy.usesRasterTexture)
        XCTAssertFalse(policy.usesLegacyAnimationOverlay)
    }

    func testLegacyKeepsExistingLayers() {
        let policy = DayCanvasArtworkLayerPolicy(style: .legacy)

        XCTAssertFalse(policy.usesEditorial)
        XCTAssertTrue(policy.usesLegacyBackground)
        XCTAssertTrue(policy.usesRasterTexture)
        XCTAssertTrue(policy.usesLegacyAnimationOverlay)
    }
}
