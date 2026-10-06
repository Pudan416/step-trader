import XCTest
@testable import Nowhere

final class CanvasOverlayStyleTests: XCTestCase {

    func testSmudgeRequiresOnlyTheSmudgeRenderer() {
        XCTAssertEqual(CanvasOverlayStyle.smudge.requiredResource, .smudge)
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

    func testRemovedCosmicPreferenceFallsBackToSmudge() {
        XCTAssertEqual(CanvasOverlayStyle(rawValue: "cosmic") ?? .smudge, .smudge)
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
