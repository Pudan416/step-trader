import XCTest
@testable import Steps4

final class RenderingActivityTests: XCTestCase {
    func testSelectedActiveViewWithoutReduceMotionAnimates() {
        XCTAssertTrue(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: true,
                reduceMotion: false
            )
        )
    }

    func testHiddenTabDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: false,
                sceneIsActive: true,
                reduceMotion: false
            )
        )
    }

    func testBackgroundSceneDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: false,
                reduceMotion: false
            )
        )
    }

    func testReduceMotionDoesNotAnimate() {
        XCTAssertFalse(
            RenderingActivity.shouldAnimate(
                isViewActive: true,
                sceneIsActive: true,
                reduceMotion: true
            )
        )
    }

    func testInactiveOverlayNeverRendersActiveEffect() {
        XCTAssertFalse(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: false,
                hasActiveEffect: true
            )
        )
    }

    func testActiveOverlayRendersActiveEffect() {
        XCTAssertTrue(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: true,
                hasActiveEffect: true
            )
        )
    }

    func testActiveOverlayKeepsIdleRendererParked() {
        XCTAssertFalse(
            MetalOverlayRenderingPolicy.shouldRender(
                isRenderingAllowed: true,
                hasActiveEffect: false
            )
        )
    }
}
