import XCTest
@testable import Steps4

/// Unified Remix rerolls art and music while preserving the recorded day.
/// The older element-only restyling API retains its positional compatibility.
final class CanvasRemixTests: XCTestCase {
    func testUnifiedRemixChangesNativeArtworkAndUndoRestoresItWithMusic() throws {
        var before = DayCanvas.newDailyCanvas(dayKey: dayKey)
        before.elements = makeElements()
        var history = CanvasRemixHistory()
        let result = history.remix(canvas: before)
        XCTAssertNotEqual(result.canvas.artworkRecipe, before.artworkRecipe)
        XCTAssertEqual(result.canvas.elements.map(\.id), before.elements.map(\.id))
        let restored = try XCTUnwrap(history.undo(into: result.canvas))
        XCTAssertEqual(restored.artworkRecipe, before.artworkRecipe)
        XCTAssertEqual(restored.resolvedMusicSelection, before.resolvedMusicSelection)
    }

    func testRemixAndUndoEachPersistOneCompleteCanvasBeforeCommittingHistory() throws {
        var before = DayCanvas(dayKey: dayKey)
        before.elements = makeElements()
        var history = CanvasRemixHistory()
        var writes: [DayCanvas] = []
        let result = try XCTUnwrap(history.commitRemix(canvas: before, persist: {
            writes.append($0)
            return true
        }))
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(try encoded(writes[0]), try encoded(result.canvas))
        XCTAssertEqual(writes[0].resolvedMusicSelection, result.musicSelection)
        XCTAssertNotEqual(writes[0].elements.map(\.basePosition), before.elements.map(\.basePosition))
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let undo = try XCTUnwrap(history.commitUndo(into: result.canvas, at: date, persist: {
            writes.append($0)
            return true
        }))
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[1].elements.map(\.basePosition), before.elements.map(\.basePosition))
        XCTAssertEqual(writes[1].resolvedMusicSelection, before.resolvedMusicSelection)
        XCTAssertEqual(writes[1].lastModified, date)
        XCTAssertTrue(undo.elements.allSatisfy { $0.lastEditedAt == date })
        XCTAssertFalse(history.canUndo)
    }

    func testFailedRemixOrUndoWriteLeavesHistoryIntactForRetry() throws {
        let before = DayCanvas(dayKey: dayKey)
        var history = CanvasRemixHistory()
        var attempts = 0
        XCTAssertNil(history.commitRemix(canvas: before, persist: { _ in
            attempts += 1
            return false
        }))
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(history.canUndo)
        let result = try XCTUnwrap(history.commitRemix(canvas: before, persist: { _ in true }))
        XCTAssertNil(history.commitUndo(into: result.canvas, persist: { _ in false }))
        XCTAssertTrue(history.canUndo)
        let restored = try XCTUnwrap(history.commitUndo(into: result.canvas, persist: { _ in true }))
        XCTAssertEqual(restored.remixSeed, before.remixSeed)
        XCTAssertFalse(history.canUndo)
    }
    func testLegacyRendererUsesTheRemixedMaterialComposition() {
        let view = GenerativeCanvasView(
            elements: makeElements(), dayKey: dayKey, remixSeed: 77,
            sleepPoints: 12, stepsPoints: 18, sleepColor: .black, stepsColor: .yellow,
            decayNorm: 0
        )
        XCTAssertEqual(view.renderedComposition, .forDay(dayKey: dayKey, happeningCount: 4, remixSeed: 77))
        XCTAssertNotEqual(view.renderedComposition, composition)
    }
    func testUnifiedRemixIsDeterministicPreservesDataAndRerollsTheWholeArtwork() throws {
        var before = DayCanvas(dayKey: dayKey)
        before.elements = makeElements(count: 10)
        before.elements[0].userSize = 0.6
        before.elements[0].editorialColorVariant = 7
        before.sleepPoints = 13
        before.stepsPoints = 19
        before.inkEarned = 87
        before.inkSpent = 31
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = CanvasUnifiedRemix.next(canvas: before, allowedShapes: [.circle, .rays], at: date)
        let repeated = CanvasUnifiedRemix.next(canvas: before, allowedShapes: [.circle, .rays], at: date)
        XCTAssertEqual(try encoded(first.canvas), try encoded(repeated.canvas))
        XCTAssertEqual(first.canvas.elements.count, 10)
        XCTAssertEqual(first.canvas.elements.map(\.id), before.elements.map(\.id))
        XCTAssertEqual(first.canvas.elements.map(\.optionId), before.elements.map(\.optionId))
        XCTAssertEqual(first.canvas.elements.map(\.label), before.elements.map(\.label))
        XCTAssertEqual(first.canvas.elements.map(\.createdAt), before.elements.map(\.createdAt))
        XCTAssertEqual(first.canvas.elements.map(\.editorialColorVariant), before.elements.map(\.editorialColorVariant))
        XCTAssertEqual(first.canvas.sleepPoints, 13)
        XCTAssertEqual(first.canvas.stepsPoints, 19)
        XCTAssertEqual(first.canvas.inkEarned, 87)
        XCTAssertEqual(first.canvas.inkSpent, 31)
        XCTAssertEqual(first.canvas.createdAt, before.createdAt)
        XCTAssertEqual(first.canvas.lastModified, date)
        XCTAssertNotEqual(first.canvas.elements.map(\.basePosition), before.elements.map(\.basePosition))
        XCTAssertNotEqual(first.canvas.elements.map(\.size), before.elements.map(\.size))
        XCTAssertNotEqual(first.canvas.elements.map(\.phaseOffset), before.elements.map(\.phaseOffset))
        XCTAssertNotEqual(first.canvas.elements.map(\.shapeSeed), before.elements.map(\.shapeSeed))
        XCTAssertTrue(first.canvas.elements.allSatisfy { [.circle, .rays].contains($0.resolvedShapeType) })
        XCTAssertTrue(first.canvas.elements.allSatisfy { $0.lastEditedAt == date && $0.userSize == nil })
        XCTAssertNotNil(first.canvas.gradientPalette)
        XCTAssertNotNil(first.canvas.gradientStyle)
        XCTAssertNotNil(first.canvas.textureRaw)
        XCTAssertEqual(first.musicSelection, DayObjectsWorldSelector.makeSelection(remixSeed: first.seed))
        XCTAssertEqual(first.canvas.resolvedMusicSelection, first.musicSelection)
        let next = CanvasUnifiedRemix.next(canvas: first.canvas, at: date)
        XCTAssertNotEqual(next.seed, first.seed)
    }

    func testUnifiedUndoRestoresManualArrangementAndMusicWithoutRollingBackHealth() throws {
        var before = DayCanvas(dayKey: dayKey)
        before.elements = makeElements()
        before.elements[0].userSize = 0.6
        before.elements[0].userRotation = 1.2
        before.remixSeed = 77
        before.soundWorldRaw = "electricDream"
        before.soundMoodRaw = "strange"
        before.guestSoundWorldRaw = "livingField"
        let result = CanvasUnifiedRemix.next(canvas: before)
        var current = result.canvas
        current.stepsPoints = 20
        current.inkSpent = 49
        let restored = CanvasUnifiedRemix.restore(result.previous, into: current)
        XCTAssertEqual(try encoded(restored.elements), try encoded(before.elements))
        XCTAssertEqual(restored.remixSeed, 77)
        XCTAssertEqual(restored.resolvedMusicSelection, before.resolvedMusicSelection)
        XCTAssertEqual(restored.gradientPalette, before.gradientPalette)
        XCTAssertEqual(restored.textureRaw, before.textureRaw)
        XCTAssertEqual(restored.stepsPoints, 20)
        XCTAssertEqual(restored.inkSpent, 49)
    }

    func testUnifiedHistoryRetainsOnlyTenSnapshotsAndNeverCrossesDays() throws {
        var canvas = DayCanvas(dayKey: dayKey)
        var history = CanvasRemixHistory()
        for _ in 0..<12 {
            canvas = history.remix(canvas: canvas).canvas
        }
        for _ in 0..<10 {
            canvas = try XCTUnwrap(history.undo(into: canvas))
        }
        XCTAssertNil(history.undo(into: canvas))
        XCTAssertFalse(history.canUndo)
        _ = history.remix(canvas: canvas)
        XCTAssertNil(history.undo(into: DayCanvas(dayKey: "2026-08-19")))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

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
