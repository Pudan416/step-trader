import XCTest
@testable import Steps4

final class RichCanvasLabIsolationTests: XCTestCase {
    func testShuffleIsSessionOnlyValueState() {
        var session = RichCanvasLabSession()
        session.shuffle()
        session.shuffle()

        XCTAssertEqual(session.shuffleNonce, 2)
        XCTAssertEqual(RichCanvasLabSession().shuffleNonce, 0)
    }

    func testSnapshotLoaderReceivesDayKeyAndReturnsCanvas() {
        let expected = DayCanvas(dayKey: "2026-08-16")
        var requestedKey: String?

        let loaded = RichCanvasLabSnapshot.load(dayKey: expected.dayKey) { key in
            requestedKey = key
            return expected
        }

        XCTAssertEqual(requestedKey, expected.dayKey)
        XCTAssertEqual(loaded?.dayKey, expected.dayKey)
        XCTAssertEqual(loaded?.elements.count, expected.elements.count)
    }

    func testRichAssignmentDoesNotMutateCanvasElementEncoding() throws {
        let elements = RichAssignmentFixture.elements(count: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(elements)

        _ = RichFigureAssignment.previewItems(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 3
        )

        let after = try encoder.encode(elements)
        XCTAssertEqual(before, after)
    }
}
