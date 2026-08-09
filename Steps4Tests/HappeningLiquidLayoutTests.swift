import SwiftUI
import XCTest
@testable import Steps4

final class HappeningLiquidLayoutTests: XCTestCase {

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testEverySupportedCountHasAccessibleNonOverlappingLabelFrames() {
        for count in 0...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            XCTAssertEqual(layout.sources.count, count, "count \(count)")
            XCTAssertEqual(layout.labelFrames.count, count, "count \(count)")

            for frame in layout.labelFrames {
                XCTAssertGreaterThanOrEqual(frame.width, 44, "count \(count)")
                XCTAssertGreaterThanOrEqual(frame.height, 44, "count \(count)")
            }

            for (index, frame) in layout.labelFrames.enumerated() {
                for other in layout.labelFrames.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other), "count \(count), frame \(index)")
                }
            }
        }
    }

    func testHitFramesRemainInsideSafeBounds() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for count in 0...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            for frame in layout.labelFrames {
                XCTAssertTrue(safeBounds.contains(frame), "count \(count), frame \(frame)")
            }
        }
    }

    func testContourLeavesFreeCanvasOnEverySafeEdgeAndConnectsDock() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for count in 1...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )
            let contour = layout.contourBounds

            XCTAssertGreaterThanOrEqual(contour.minX - safeBounds.minX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxX - contour.maxX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(contour.minY - safeBounds.minY, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxY - contour.maxY, 16, "count \(count)")
            XCTAssertGreaterThan(layout.dockAnchor.y, contour.maxY, "count \(count)")
            XCTAssertLessThanOrEqual(layout.dockAnchor.y - contour.maxY, 44, "count \(count)")
            XCTAssertTrue(safeBounds.contains(layout.dockAnchor), "count \(count)")
        }
    }

    func testRemovingIndexPreservesRelativeIdentityOrder() {
        let ten = HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: EdgeInsets())
        let nine = HappeningLiquidLayout.layout(count: 9, in: size, safeInsets: EdgeInsets())
        let eight = HappeningLiquidLayout.layout(count: 8, in: size, safeInsets: EdgeInsets())

        XCTAssertEqual(ten.sources.map(\.index), Array(0..<10))
        XCTAssertEqual(nine.sources.map(\.index), Array(0..<9))
        XCTAssertEqual(eight.sources.map(\.index), Array(0..<8))
        XCTAssertTrue(nine.contourBounds.width < size.width)
        XCTAssertTrue(eight.contourBounds.width < size.width)
    }

    func testEmptyFieldHasNoSourcesAndAValidCloseDock() {
        let layout = HappeningLiquidLayout.layout(count: 0, in: size, safeInsets: safeInsets)
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        XCTAssertTrue(layout.sources.isEmpty)
        XCTAssertTrue(layout.labelFrames.isEmpty)
        XCTAssertTrue(layout.contourBounds.isEmpty)
        XCTAssertTrue(safeBounds.contains(layout.dockAnchor))
    }

    func testLayoutIsDeterministicForTheSameInputs() {
        XCTAssertEqual(
            HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: safeInsets),
            HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: safeInsets)
        )
    }
}

final class HappeningLiquidTransitionStateTests: XCTestCase {

    func testBeginRemovalLocksTheSelectedIDAndStartsPressing() {
        var state = HappeningLiquidTransitionState()

        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testBusyTransitionIgnoresDuplicateAndCompetingTaps() {
        var state = HappeningLiquidTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))

        XCTAssertFalse(state.beginRemoval(id: "happening_walk"))
        XCTAssertFalse(state.beginRemoval(id: "happening_read"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testFinishRemovalUnlocksOnlyAfterReflowAndAllowsAnotherID() {
        var state = HappeningLiquidTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .reflowing))

        XCTAssertFalse(state.finishRemoval(id: "happening_read"))
        XCTAssertTrue(state.finishRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selectedID)
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
    }
}

/// Label contrast is unrelated to the replaced blob geometry, so it remains
/// covered here after the legacy layout test file is retired.
final class HappeningPaletteLabelContrastTests: XCTestCase {

    func testLuminanceEndpoints() {
        XCTAssertEqual(HappeningPaletteView.relativeLuminance(ofHex: "#000000"), 0, accuracy: 0.001)
        XCTAssertEqual(HappeningPaletteView.relativeLuminance(ofHex: "#FFFFFF"), 1, accuracy: 0.001)
    }

    func testLuminanceToleratesMissingHashAndWhitespace() {
        XCTAssertEqual(
            HappeningPaletteView.relativeLuminance(ofHex: " FFFFFF "),
            HappeningPaletteView.relativeLuminance(ofHex: "#FFFFFF"),
            accuracy: 0.001
        )
    }

    func testMalformedHexFallsBackToLightSoTextStaysDark() {
        XCTAssertEqual(HappeningPaletteView.relativeLuminance(ofHex: "nope"), 1, accuracy: 0.001)
        XCTAssertEqual(HappeningPaletteView.labelColor(onHex: "nope"), .black.opacity(0.8))
    }

    func testDeepJewelTonesGetLightLabels() {
        for hex in ["#0E3A6E", "#1E2E78", "#6E1A2E", "#3A1660", "#5C1648", "#0E4A4E"] {
            XCTAssertEqual(
                HappeningPaletteView.labelColor(onHex: hex), .white.opacity(0.92),
                "\(hex) is too dark for dark text"
            )
        }
    }

    func testLightTonesKeepDarkLabels() {
        for hex in ["#E8B060", "#E098A0", "#D8C078", "#E89070"] {
            XCTAssertEqual(
                HappeningPaletteView.labelColor(onHex: hex), .black.opacity(0.8),
                "\(hex) should keep the reference's dark label"
            )
        }
    }

    func testEveryPaletteColorGetsAReadableLabel() {
        for hex in CanvasColorPalette.paletteHex {
            let luminance = HappeningPaletteView.relativeLuminance(ofHex: hex)
            let isLight = HappeningPaletteView.labelColor(onHex: hex) == .black.opacity(0.8)
            let textLuminance = isLight ? 0.0 : 1.0
            let ratio = (max(luminance, textLuminance) + 0.05)
                      / (min(luminance, textLuminance) + 0.05)
            XCTAssertGreaterThan(ratio, 3.0, "\(hex) has poor label contrast (\(ratio))")
        }
    }
}
