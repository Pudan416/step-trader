import XCTest
@testable import Steps4

/// Remix restyles the whole canvas at once. What it may never do is move an
/// element the user placed, rename it, drop it, or invent a new one — the
/// picture changes, the day it records does not.
final class CanvasRemixTests: XCTestCase {

    private let dayKey = "2026-08-18"

    private var composition: DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: 4)
    }

    private func makeElements(count: Int = 4) -> [CanvasElement] {
        var elements: [CanvasElement] = []
        for index in 0..<count {
            var element = CanvasElement.spawn(
                optionId: "happening_\(index)",
                label: "Happening \(index)",
                existingElements: elements,
                dayKey: dayKey,
                composition: composition
            )
            // A position the user "dragged" to, so preservation is observable.
            element.basePosition = CGPoint(x: 0.11 + 0.2 * Double(index), y: 0.9)
            elements.append(element)
        }
        return elements
    }

    func testPreservesIdentityOrderAndCount() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.optionId), before.map(\.optionId))
        XCTAssertEqual(after.map(\.label), before.map(\.label))
        XCTAssertEqual(after.map(\.createdAt), before.map(\.createdAt))
    }

    /// The one thing a user manually arranges. Remix must not touch it.
    func testPreservesManuallyArrangedPositions() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        for (old, new) in zip(before, after) {
            XCTAssertEqual(new.basePosition.x, old.basePosition.x, accuracy: 0.0001)
            XCTAssertEqual(new.basePosition.y, old.basePosition.y, accuracy: 0.0001)
        }
    }

    func testChangesTheVisualSeedOfEveryElement() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        for (old, new) in zip(before, after) {
            XCTAssertNotEqual(new.shapeSeed, old.shapeSeed)
        }
    }

    func testDrawsShapesOnlyFromTheAllowedSet() {
        let allowed: [CanvasShapeType] = [.snowflake]
        let after = CanvasRemix.remixed(
            makeElements(count: 6),
            composition: composition,
            allowedShapes: allowed
        )

        for element in after {
            XCTAssertEqual(element.frozenShapeType, .snowflake)
        }
    }

    func testDrawsColorsOnlyFromTheDayPalette() {
        let palette = Set(composition.palette)
        let after = CanvasRemix.remixed(makeElements(count: 6), composition: composition)

        for element in after {
            XCTAssertTrue(palette.contains(element.hexColor), element.hexColor)
            if let second = element.hexColor2 {
                XCTAssertTrue(palette.contains(second), second)
            }
        }
    }

    /// One batch, one timestamp — the whole canvas changed at the same moment,
    /// and last-write-wins merging needs that to be true.
    func testStampsEveryElementWithTheSameEditDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let after = CanvasRemix.remixed(makeElements(), composition: composition, at: date)

        for element in after {
            XCTAssertEqual(element.lastEditedAt, date)
        }
    }

    /// A pinch-resized element must follow the new shape's size curve, not keep
    /// a size chosen for the shape it no longer has.
    func testClearsTheUserSizeOverride() {
        var before = makeElements()
        before[0].userSize = 0.6
        let after = CanvasRemix.remixed(before, composition: composition)

        XCTAssertNil(after[0].userSize)
    }

    func testEmptyCanvasRemixesToAnEmptyCanvas() {
        XCTAssertTrue(CanvasRemix.remixed([], composition: composition).isEmpty)
    }
}
