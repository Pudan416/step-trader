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

    func testCanvasControlsUseTheMeasuredTabBarCenter() {
        XCTAssertEqual(
            CanvasBottomControlsLayout.padding(
                canvasBottomY: 844,
                tabBarCenterY: 790,
                controlHeight: 52,
                fallbackSafeAreaBottom: 34
            ),
            28
        )
    }

    func testSmudgePathFilterSoftensAbruptDirectionChanges() {
        var filter = SmudgeTouchPathFilter(responseSeconds: 0.05)
        let beginning = filter.begin(at: CGPoint(x: 20, y: 20), time: 1)
        let firstMove = filter.move(to: CGPoint(x: 120, y: 20), time: 1.01)
        let reversal = filter.move(to: CGPoint(x: 20, y: 20), time: 1.02)

        XCTAssertEqual(beginning.point, CGPoint(x: 20, y: 20))
        XCTAssertGreaterThan(firstMove.point.x, 20)
        XCTAssertLessThan(firstMove.point.x, 120)
        XCTAssertGreaterThan(reversal.point.x, 20)
        XCTAssertTrue(firstMove.speed.isFinite)
        XCTAssertGreaterThanOrEqual(firstMove.speed, 0)
    }

    func testSmudgePathFilterCapsLongFrameIntervals() {
        var filter = SmudgeTouchPathFilter(responseSeconds: 0.05)
        _ = filter.begin(at: CGPoint(x: 0, y: 0), time: 1)
        let sample = filter.move(to: CGPoint(x: 1_000, y: 0), time: 3)

        XCTAssertLessThan(sample.point.x, 1_000)
        XCTAssertLessThanOrEqual(sample.speed, SmudgeTouchPathFilter.maximumSpeed)
    }

    func testSmudgeAccumulatorCoalescesWorkWithoutLeavingAGap() {
        let touch = ObjectIdentifier(NSObject())
        var accumulator = SmudgeStrokeAccumulator()
        accumulator.enqueue(
            StrokeSegment(
                p0: SIMD2(0, 0), p1: SIMD2(10, 0), radius: 20,
                strength: 0.2, dragFactor: 3, direction: SIMD2(1, 0)
            ),
            for: touch
        )
        accumulator.enqueue(
            StrokeSegment(
                p0: SIMD2(10, 0), p1: SIMD2(30, 0), radius: 24,
                strength: 0.3, dragFactor: 4, direction: SIMD2(1, 0)
            ),
            for: touch
        )

        let strokes = accumulator.drain()
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].p0, SIMD2(0, 0))
        XCTAssertEqual(strokes[0].p1, SIMD2(30, 0))
        XCTAssertTrue(accumulator.drain().isEmpty)
    }

}
