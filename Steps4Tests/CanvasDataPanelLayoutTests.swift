import XCTest
@testable import Steps4

/// The data sheet is a strip over the canvas, not a takeover: it may claim at
/// most 40% of the space between the status pill and the tab bar, so the
/// picture stays the subject of the screen.
final class CanvasDataPanelLayoutTests: XCTestCase {

    func testClaimsFortyPercentOfTheSpaceBetweenChrome() {
        let height = CanvasDataPanel.maxHeight(
            viewportHeight: 800,
            topInset: 120,
            bottomInset: 130
        )

        // 800 - 120 - 130 = 550 available; 40% of that.
        XCTAssertEqual(height, 220, accuracy: 0.001)
    }

    func testNeverGoesNegativeWhenChromeExceedsTheViewport() {
        let height = CanvasDataPanel.maxHeight(
            viewportHeight: 200,
            topInset: 150,
            bottomInset: 150
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    /// A first layout pass reports a zero viewport while the chrome insets are
    /// already known. An unclamped formula would hand back a negative height here.
    func testZeroViewportWithKnownChromeAsksForNothing() {
        XCTAssertEqual(
            CanvasDataPanel.maxHeight(viewportHeight: 0, topInset: 133, bottomInset: 206),
            0,
            accuracy: 0.001
        )
    }
}
