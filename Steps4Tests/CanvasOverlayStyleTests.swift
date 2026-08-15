import XCTest
@testable import Steps4

final class CanvasOverlayStyleTests: XCTestCase {

    func testSmudgeRequiresOnlyTheSmudgeRenderer() {
        XCTAssertEqual(CanvasOverlayStyle.smudge.requiredResource, .smudge)
    }

    func testCosmicRequiresOnlyTheCosmicRenderer() {
        XCTAssertEqual(CanvasOverlayStyle.cosmic.requiredResource, .cosmic)
    }

    func testNoneRequiresNoRendererAndDoesNotInterceptTouches() {
        XCTAssertEqual(CanvasOverlayStyle.none.requiredResource, .none)
        XCTAssertFalse(CanvasOverlayStyle.none.interceptsTouches)
    }
}
