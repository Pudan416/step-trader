import XCTest
@testable import Nowhere

/// Unified Remix rerolls art and music while preserving the recorded day.
/// The older element-only restyling API retains its positional compatibility.
final class CanvasRemixTests: XCTestCase {
    func testSequentialNativeRemixesChangeCollectionAndRetainItThroughAdoption() throws {
        var canvas = DayCanvas.newDailyCanvas(dayKey: dayKey)
        canvas.elements = makeElements()
        canvas.artworkRecipe = canvas.artworkRecipe?.reconciled(
            eventIDs: canvas.elements.map { $0.id.uuidString.lowercased() }
        )
        canvas.remixSeed = 1_234_567_890_123_456_789
        let elementIDs = canvas.elements.map(\.id)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var visited = Set<NativeAtlasDailyStyle.Collection>()
        for _ in 0..<128 {
            let previous = try XCTUnwrap(canvas.artworkRecipe)
            var history = CanvasRemixHistory()
            let result = try XCTUnwrap(history.commitRemix(canvas: canvas, at: date, persist: { _ in true }))
            let recipe = try XCTUnwrap(result.canvas.artworkRecipe)
            let style = try XCTUnwrap(recipe.dailyStyle)
            XCTAssertNotEqual(style.collection, previous.dailyStyle?.collection)
            let background = try XCTUnwrap(recipe.backgroundStyle)
            let previousBackground = try XCTUnwrap(previous.backgroundStyle)
            XCTAssertNotEqual(Set(background.colors), Set(previousBackground.colors))
            XCTAssertNotEqual(background.archetype, previousBackground.archetype)
            XCTAssertEqual(style.palette, background.colors)
            let previousPalettes = ModernPaletteCatalog.all.filter {
                Set(previousBackground.colors).isSubset(of: Set($0.hexes.map { DayObjectRGB(hex: $0).linearRGB }))
            }
            XCTAssertFalse(previousPalettes.contains {
                Set(background.colors).isSubset(of: Set($0.hexes.map { DayObjectRGB(hex: $0).linearRGB }))
            })
            XCTAssertEqual(recipe, CanvasUnifiedRemix.next(canvas: canvas, at: date).canvas.artworkRecipe)
            XCTAssertEqual(result.canvas.elements.map(\.id), elementIDs)
            XCTAssertEqual(recipe.actors.map(\.eventID), elementIDs.map { $0.uuidString.lowercased() })
            XCTAssertTrue(recipe.actors.allSatisfy { $0.presetID == style.presetID })
            for actor in recipe.actors {
                XCTAssertFalse([MetalShapeMaterial.proceduralLight, .proceduralFlow, .sunset].contains(actor.materialID))
                XCTAssertEqual(actor.materialID == .directionalBlur, style.resolvedCollection.isBlurred)
                if style.family == .circles {
                    XCTAssertEqual(actor.geometry.metadata, SIMD4<UInt32>(1, 0, 1, 0))
                    XCTAssertEqual(actor.geometry.anisotropyOffset, SIMD4<Float>(1, 1, 0, 0))
                }
                if style.collection == .blurredSquares {
                    XCTAssertEqual(actor.presetID, "legacy.soft-square")
                }
            }
            visited.insert(try XCTUnwrap(style.collection))
            let restored = try XCTUnwrap(history.commitUndo(into: result.canvas, at: date, persist: { _ in true }))
            XCTAssertEqual(restored.artworkRecipe, previous)
            canvas = result.canvas
            canvas.adoptDailyStyleForCurrentDay(currentDayKey: dayKey, paletteCategories: ModernPaletteSelection.all, at: date)
            XCTAssertEqual(canvas.artworkRecipe?.dailyStyle?.collection, style.collection)
        }
        XCTAssertEqual(visited, Set(NativeAtlasDailyStyle.Collection.allCases))
    }

    func testRemixPaletteSelectionKeepsNoirAndSinglePaletteScopes() throws {
        let noir = ModernPaletteCatalog.palettes(matching: [.noir])
        var background = NativeAtlasRecipe.makeRemixBackgroundStyle(recipeSeed: 1, palettes: noir, excluding: [])
        for seed in UInt64(2)...33 {
            let next = NativeAtlasRecipe.makeRemixBackgroundStyle(recipeSeed: seed, palettes: noir,
                excluding: background.colors, previousArchetype: background.archetype)
            XCTAssertTrue(next.isNoir == true)
            XCTAssertNotEqual(Set(next.colors), Set(background.colors))
            XCTAssertNotEqual(next.archetype, background.archetype)
            XCTAssertTrue(noir.contains { Set(next.colors).isSubset(of: Set($0.hexes.map { DayObjectRGB(hex: $0).linearRGB })) })
            background = next
        }
        let only = try XCTUnwrap(noir.first)
        let first = NativeAtlasRecipe.makeRemixBackgroundStyle(recipeSeed: 42, palettes: [only], excluding: background.colors)
        let next = NativeAtlasRecipe.makeRemixBackgroundStyle(recipeSeed: 43, palettes: [only],
            excluding: Array(first.colors.reversed()), previousArchetype: first.archetype)
        XCTAssertEqual(next, NativeAtlasRecipe.makeRemixBackgroundStyle(recipeSeed: 43, palettes: [only],
            excluding: first.colors, previousArchetype: first.archetype))
        XCTAssertTrue(Set(next.colors).isSubset(of: Set(only.hexes.map { DayObjectRGB(hex: $0).linearRGB })))
        XCTAssertNotEqual(next.archetype, first.archetype)
    }

    func testNativeRemixCollectionSelectionUsesFullSeedAndHonorsArtworkLock() throws {
        for previous in NativeAtlasDailyStyle.Collection.allCases {
            let choices = (0..<128).map { offset in
                NativeAtlasDailyStyle.remixCollection(
                    seedKey: String(1_234_567_890_123_456_789 + UInt64(offset)), excluding: previous
                )
            }
            XCTAssertFalse(choices.contains(previous))
            XCTAssertEqual(Set(choices), Set(NativeAtlasDailyStyle.Collection.allCases.filter { $0 != previous }))
        }
        var recipe = NativeAtlasRecipe.make(dayKey: dayKey).reconciled(eventIDs: ["one", "two"])
        recipe.locks = ["artwork"]
        let remixed = recipe.remixed(seedKey: "1234567890123456790", dayKey: dayKey)
        XCTAssertEqual(remixed.dailyStyle, recipe.dailyStyle)
        XCTAssertEqual(remixed.actors, recipe.actors)
        XCTAssertEqual(remixed.seedHex, recipe.seedHex)
        XCTAssertEqual(remixed.locks, recipe.locks)
    }

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
