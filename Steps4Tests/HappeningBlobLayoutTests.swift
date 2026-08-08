import XCTest
import SwiftUI
@testable import Steps4

/// Layout maths for the palette's metaball cluster.
///
/// Kept out of the view so the "7–8 visible without scrolling" rule and the
/// overlap the metaball merge depends on are actually testable.
final class HappeningBlobLayoutTests: XCTestCase {

    private let canvas = CGSize(width: 390, height: 700)

    // MARK: - Basics

    func testProducesOneBlobPerHappening() {
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 10, in: canvas).count, 10)
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 11, in: canvas).count, 11)
        XCTAssertEqual(HappeningBlobLayout.blobs(count: 1, in: canvas).count, 1)
    }

    func testHandlesEmptyInput() {
        XCTAssertTrue(HappeningBlobLayout.blobs(count: 0, in: canvas).isEmpty)
    }

    func testHandlesDegenerateCanvas() {
        XCTAssertTrue(HappeningBlobLayout.blobs(count: 5, in: .zero).isEmpty)
        XCTAssertTrue(
            HappeningBlobLayout.blobs(count: 5, in: CGSize(width: 0, height: 700)).isEmpty
        )
    }

    func testIndicesAreSequential() {
        XCTAssertEqual(
            HappeningBlobLayout.blobs(count: 6, in: canvas).map(\.index), Array(0..<6)
        )
    }

    // MARK: - Bounds and overlap

    func testBlobsStayWithinTheHorizontalBounds() {
        for blob in HappeningBlobLayout.blobs(count: 11, in: canvas) {
            XCTAssertGreaterThanOrEqual(blob.center.x - blob.radius, 0, "blob \(blob.index)")
            XCTAssertLessThanOrEqual(blob.center.x + blob.radius, canvas.width, "blob \(blob.index)")
        }
    }

    func testRadiiArePositive() {
        for blob in HappeningBlobLayout.blobs(count: 11, in: canvas) {
            XCTAssertGreaterThan(blob.radius, 0, "blob \(blob.index)")
        }
    }

    /// The spec asks for 7–8 blobs visible without scrolling; the rest scroll.
    func testSevenOrEightBlobsFitInTheFirstViewport() {
        let blobs = HappeningBlobLayout.blobs(count: 11, in: canvas)
        let visible = blobs.filter { $0.center.y + $0.radius <= canvas.height }
        XCTAssertGreaterThanOrEqual(visible.count, 7)
        XCTAssertLessThanOrEqual(visible.count, 8)
    }

    /// Neighbours must overlap or the metaball contour renders as separate
    /// circles and the cluster reads wrong.
    func testEachBlobOverlapsAtLeastOneEarlierNeighbour() {
        let blobs = HappeningBlobLayout.blobs(count: 8, in: canvas)
        for (index, blob) in blobs.enumerated().dropFirst() {
            let nearestGap = blobs[..<index]
                .map { hypot($0.center.x - blob.center.x, $0.center.y - blob.center.y)
                     - ($0.radius + blob.radius) }
                .min() ?? .greatestFiniteMagnitude
            XCTAssertLessThan(nearestGap, 0, "blob \(index) does not touch any neighbour")
        }
    }

    // MARK: - Determinism

    /// The cluster must not reshuffle between renders — SwiftUI re-runs `body`
    /// constantly, and a random layout would jitter.
    func testLayoutIsDeterministic() {
        let a = HappeningBlobLayout.blobs(count: 9, in: canvas)
        let b = HappeningBlobLayout.blobs(count: 9, in: canvas)
        XCTAssertEqual(a, b)
    }

    /// Adding an eleventh happening mid-day must not move the first ten.
    func testExistingBlobsDoNotMoveWhenOneIsAppended() {
        let ten = HappeningBlobLayout.blobs(count: 10, in: canvas)
        let eleven = HappeningBlobLayout.blobs(count: 11, in: canvas)
        XCTAssertEqual(Array(eleven.prefix(10)), ten, "Nothing already on screen moves")
    }

    // MARK: - Content height

    func testContentHeightGrowsWithCount() {
        let eight = HappeningBlobLayout.contentHeight(count: 8, in: canvas)
        let sixteen = HappeningBlobLayout.contentHeight(count: 16, in: canvas)
        XCTAssertGreaterThan(sixteen, eight)
    }

    func testContentHeightIsAtLeastTheViewport() {
        for count in [0, 1, 8, 20] {
            XCTAssertGreaterThanOrEqual(
                HappeningBlobLayout.contentHeight(count: count, in: canvas),
                canvas.height, "count \(count)"
            )
        }
    }

    func testContentHeightClearsTheLowestBlob() {
        let count = 16
        let lowest = HappeningBlobLayout.blobs(count: count, in: canvas)
            .map { $0.center.y + $0.radius }.max() ?? 0
        XCTAssertGreaterThanOrEqual(
            HappeningBlobLayout.contentHeight(count: count, in: canvas), lowest,
            "The last blob must not be clipped"
        )
    }
}

/// Label contrast on the blobs. The reference asks for dark text set on the
/// shapes, but the canvas palette carries deep jewel tones where dark-on-dark
/// is unreadable, so those have to flip.
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

    /// Every palette entry must resolve to a readable pairing — no entry may
    /// land in the gap where neither text colour works.
    func testEveryPaletteColorGetsAReadableLabel() {
        for hex in CanvasColorPalette.paletteHex {
            let luminance = HappeningPaletteView.relativeLuminance(ofHex: hex)
            let isLight = HappeningPaletteView.labelColor(onHex: hex) == .black.opacity(0.8)
            // Contrast against the chosen text colour, WCAG ratio.
            let textLuminance = isLight ? 0.0 : 1.0
            let ratio = (max(luminance, textLuminance) + 0.05)
                      / (min(luminance, textLuminance) + 0.05)
            XCTAssertGreaterThan(ratio, 3.0, "\(hex) has poor label contrast (\(ratio))")
        }
    }
}
