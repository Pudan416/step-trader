import XCTest
@testable import Nowhere

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

    func testCurrentCanvasAlwaysUsesSmudgeWhenLegacyPreferenceWasOff() {
        XCTAssertEqual(
            CanvasOverlayStyle.currentCanvasStyle(storedRaw: CanvasOverlayStyle.none.rawValue),
            .smudge
        )
    }

    func testCurrentCanvasAlwaysUsesSmudgeWhenLegacyPreferenceWasCosmic() {
        XCTAssertEqual(
            CanvasOverlayStyle.currentCanvasStyle(storedRaw: CanvasOverlayStyle.cosmic.rawValue),
            .smudge
        )
    }

    func testCurrentCanvasIgnoresLegacyOverrideFromSavedRemix() {
        XCTAssertEqual(
            CanvasOverlayStyle.currentCanvasStyle(
                storedRaw: CanvasOverlayStyle.none.rawValue,
                overrideRaw: CanvasOverlayStyle.none.rawValue
            ),
            .smudge
        )
    }
}
