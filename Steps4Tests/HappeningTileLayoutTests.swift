import XCTest
@testable import Steps4

final class HappeningTileLayoutTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 360, height: 560)
    private let side: CGFloat = 84

    func testTenTilesFallIntoThreeTwoThreeTwo() {
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 10), [3, 2, 3, 2])
    }

    func testRowsAlternateThreeAndTwoAsTilesAreConsumed() {
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 9), [3, 2, 3, 1])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 8), [3, 2, 3])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 5), [3, 2])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 3), [3])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 1), [1])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 0), [])
    }

    func testEveryTileGetsAFrame() {
        XCTAssertEqual(
            HappeningTileLayout.frames(count: 10, in: bounds, tileSide: side).count,
            10
        )
    }

    /// The point of the stagger: the row of two sits in the gaps of the row of
    /// three, not aligned to its columns. A flat grid would read as a table.
    func testTheRowOfTwoSitsInTheGapsOfTheRowOfThree() {
        let frames = HappeningTileLayout.frames(count: 10, in: bounds, tileSide: side)
        let firstRow = Array(frames[0..<3]).map(\.midX)
        let secondRow = Array(frames[3..<5]).map(\.midX)

        XCTAssertEqual(secondRow[0], (firstRow[0] + firstRow[1]) / 2, accuracy: 0.5)
        XCTAssertEqual(secondRow[1], (firstRow[1] + firstRow[2]) / 2, accuracy: 0.5)
    }

    func testTilesStayInsideTheBounds() {
        let inset = CGRect(x: 20, y: 40, width: 360, height: 560)
        for frame in HappeningTileLayout.frames(count: 10, in: inset, tileSide: side) {
            XCTAssertTrue(inset.contains(frame), "\(frame) escapes \(inset)")
        }
    }

    func testRowsDoNotOverlapVertically() {
        let frames = HappeningTileLayout.frames(count: 10, in: bounds, tileSide: side)
        XCTAssertLessThanOrEqual(frames[0].maxY, frames[3].minY)
        XCTAssertLessThanOrEqual(frames[3].maxY, frames[5].minY)
        XCTAssertLessThanOrEqual(frames[5].maxY, frames[8].minY)
    }

    /// A single tile has no row to centre against, so it centres on the bounds.
    func testOneTileSitsInTheMiddle() {
        let frames = HappeningTileLayout.frames(count: 1, in: bounds, tileSide: side)
        XCTAssertEqual(frames[0].midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(frames[0].midY, bounds.midY, accuracy: 0.5)
    }

    /// The field empties one tile at a time, so every count between ten and
    /// zero has to lay out without escaping or crashing.
    func testEveryCountFromZeroToTenLaysOut() {
        for count in 0...10 {
            let frames = HappeningTileLayout.frames(count: count, in: bounds, tileSide: side)
            XCTAssertEqual(frames.count, count, "wrong frame count for \(count)")
            for frame in frames {
                XCTAssertTrue(bounds.contains(frame), "\(count) tiles: \(frame) escapes")
            }
        }
    }

    /// A short viewport must squeeze the rows rather than push them off the
    /// bottom — accessibility type sizes shrink the space the field gets.
    func testAShortViewportKeepsTilesInside() {
        let short = CGRect(x: 0, y: 0, width: 360, height: 300)
        for frame in HappeningTileLayout.frames(count: 10, in: short, tileSide: side) {
            XCTAssertTrue(short.contains(frame), "\(frame) escapes \(short)")
        }
    }
}
