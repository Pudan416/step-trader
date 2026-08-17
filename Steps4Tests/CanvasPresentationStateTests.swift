import XCTest
@testable import Steps4

/// Canvas has four mutually exclusive presentation states. The combinations the
/// old `isWideCanvas` + `isEditMode` pair allowed — a data sheet over full
/// screen, edit mode without full screen, chrome over a full-screen canvas —
/// must be unrepresentable, not merely unreachable.
final class CanvasPresentationStateTests: XCTestCase {

    // MARK: - The transition table from the spec

    func testShowDataFromCanvas() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.showData), .data)
    }

    func testHideDataReturnsToCanvas() {
        XCTAssertEqual(CanvasPresentationState.data.applying(.hideData), .canvas)
    }

    func testEnterFullScreenFromCanvasAndFromData() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.enterFullScreen), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.data.applying(.enterFullScreen), .fullScreen)
    }

    func testExitFullScreenReturnsToCanvas() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.exitFullScreen), .canvas)
    }

    func testEditIsReachableOnlyFromFullScreen() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.beginEditing), .editing)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.beginEditing), .canvas)
        XCTAssertEqual(CanvasPresentationState.data.applying(.beginEditing), .data)
    }

    /// Done returns to viewing, not to the collapsed canvas.
    func testDoneReturnsToFullScreen() {
        XCTAssertEqual(CanvasPresentationState.editing.applying(.endEditing), .fullScreen)
    }

    func testOpeningThePaletteDismissesDataAndKeepsCanvas() {
        XCTAssertEqual(CanvasPresentationState.data.applying(.openHappeningPalette), .canvas)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.openHappeningPalette), .canvas)
    }

    /// The palette cannot present over a wide canvas, so the event is inert there.
    func testOpeningThePaletteDoesNotCollapseFullScreen() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.openHappeningPalette), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.editing.applying(.openHappeningPalette), .editing)
    }

    func testLeavingTheCanvasTabAlwaysCollapsesToCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertEqual(state.applying(.leftCanvasTab), .canvas, "\(state)")
        }
    }

    func testDayBoundaryAlwaysResetsToCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertEqual(state.applying(.dayBoundary), .canvas, "\(state)")
        }
    }

    /// An event that does not apply leaves the state alone rather than
    /// dropping the user somewhere unexpected.
    func testInapplicableEventsAreInert() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.hideData), .canvas)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.exitFullScreen), .canvas)
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.showData), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.editing.applying(.showData), .editing)
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.endEditing), .fullScreen)
    }

    // MARK: - Forbidden combinations

    func testDataPanelNeverCoexistsWithAWideCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertFalse(state.showsDataPanel && state.isWideCanvas, "\(state)")
        }
    }

    func testEditingAlwaysImpliesAWideCanvas() {
        for state in CanvasPresentationState.allCases where state.isEditing {
            XCTAssertTrue(state.isWideCanvas, "\(state)")
        }
    }

    func testChromeIsHiddenWheneverTheCanvasIsWide() {
        for state in CanvasPresentationState.allCases where state.isWideCanvas {
            XCTAssertFalse(state.showsStatusPill, "\(state)")
            XCTAssertFalse(state.showsBottomActionRow, "\(state)")
        }
    }

    /// Raising the canvas must never start an edit by itself.
    func testEnteringFullScreenNeverStartsEditing() {
        for state in CanvasPresentationState.allCases {
            XCTAssertFalse(state.applying(.enterFullScreen).isEditing, "\(state)")
        }
    }

    func testExactlyOneDockIsVisiblePerState() {
        for state in CanvasPresentationState.allCases {
            let docks = [state.showsFullScreenDock, state.showsEditingChrome, state.showsBottomActionRow]
            XCTAssertEqual(docks.filter { $0 }.count, 1, "\(state)")
        }
    }

    // MARK: - Analytics

    func testAnalyticsNamesCoverTheTrackedTransitions() {
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .canvas, to: .data), "canvas_data_opened")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .data, to: .canvas), "canvas_data_closed")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .canvas, to: .fullScreen), "canvas_fullscreen_entered")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .fullScreen, to: .canvas), "canvas_fullscreen_exited")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .fullScreen, to: .editing), "canvas_edit_entered")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .editing, to: .fullScreen), "canvas_edit_exited")
    }

    func testAnalyticsNameIsNilWhenNothingChanged() {
        for state in CanvasPresentationState.allCases {
            XCTAssertNil(CanvasPresentationState.analyticsEventName(from: state, to: state), "\(state)")
        }
    }
}
