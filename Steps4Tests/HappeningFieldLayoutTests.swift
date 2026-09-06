import SwiftUI
import UIKit
import XCTest
@testable import Steps4

final class Task7UITestAccessibilityConfigurationTests: XCTestCase {

    func testTask7FixtureReadsAccessibilityTypeAndIncreasedContrastFromLaunchEnvironment() {
        let configuration = Task7UITestAccessibilityConfiguration(
            arguments: ["ui-testing", "ui-testing-task7"],
            environment: [
                "TASK7_DYNAMIC_TYPE_SIZE": "accessibility1",
                "TASK7_INCREASED_CONTRAST": "1",
            ]
        )

        XCTAssertEqual(configuration.dynamicTypeSize, .accessibility1)
        XCTAssertTrue(configuration.usesIncreasedContrast)
    }

    func testAccessibilityOverridesStayDisabledOutsideTheTask7Fixture() {
        let configuration = Task7UITestAccessibilityConfiguration(
            arguments: ["ui-testing"],
            environment: [
                "TASK7_DYNAMIC_TYPE_SIZE": "accessibility1",
                "TASK7_INCREASED_CONTRAST": "1",
            ]
        )

        XCTAssertNil(configuration.dynamicTypeSize)
        XCTAssertFalse(configuration.usesIncreasedContrast)
    }
}

@MainActor
final class CanvasOverlayIntegrationRegressionTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.stepsTrader()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    func testUnloadedCanvasRejectsSpawnWithoutCreatingDomainAddition() {
        let model = makeModel()
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
        let element = fixedElement(on: canvas)

        let result = CanvasHappeningSpawnTransaction.commit(
            canvasLoaded: false,
            canvas: canvas,
            model: model,
            element: element,
            recordUse: true,
            at: .now,
            persist: { _ in true }
        )

        XCTAssertNil(result)
        XCTAssertTrue(model.todayAdditions.isEmpty)
    }

    func testFailedCanvasSaveRejectsSpawnWithoutCreatingDomainAddition() {
        let model = makeModel()
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
        let element = fixedElement(on: canvas)

        let result = CanvasHappeningSpawnTransaction.commit(
            canvasLoaded: true,
            canvas: canvas,
            model: model,
            element: element,
            recordUse: true,
            at: .now,
            persist: { _ in false }
        )

        XCTAssertNil(result)
        XCTAssertTrue(model.todayAdditions.isEmpty)
    }

    func testSpawnPersistsCanonicalDestinationBeforeCommittingMatchingDomainEntry() throws {
        let model = makeModel()
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
        let element = fixedElement(on: canvas)
        var persistedCanvas: DayCanvas?

        let result = try XCTUnwrap(
            CanvasHappeningSpawnTransaction.commit(
                canvasLoaded: true,
                canvas: canvas,
                model: model,
                element: element,
                recordUse: true,
                at: .now,
                persist: {
                    XCTAssertTrue(
                        model.todayAdditions.isEmpty,
                        "the canvas must become durable before the day entry commits"
                    )
                    persistedCanvas = $0
                    return true
                }
            )
        )

        let persisted = try XCTUnwrap(persistedCanvas)
        XCTAssertEqual(persisted.elements.count, 1)
        XCTAssertEqual(persisted.elements[0].basePosition, CGPoint(x: 0.82, y: 0.24))
        XCTAssertEqual(result.canvas.elements[0].basePosition, CGPoint(x: 0.82, y: 0.24))
        XCTAssertEqual(model.todayAdditions.map(\.id), [element.id.uuidString])
        XCTAssertEqual(model.todayAdditions.map(\.optionId), [element.optionId])
    }

    func testAllTenDifferentPaletteHappeningsCanBeAddedToTheCanvas() throws {
        let date = Date.now
        let dayKey = AppModel.dayKey(for: date)
        let model = makeModel()
        let happenings = model.availablePaletteHappenings(on: date)
        let figures = model.paletteFigures(on: date)
        var canvas = DayCanvas(dayKey: dayKey)

        XCTAssertEqual(happenings.count, 10)

        for happening in happenings {
            let element = CanvasElement.spawn(
                optionId: happening.id,
                label: happening.localizedTitle(),
                existingElements: canvas.elements,
                dayKey: dayKey,
                composition: DayComposition.forDay(
                    dayKey: dayKey,
                    happeningCount: canvas.elements.count
                ),
                figure: try XCTUnwrap(figures[happening.id])
            )
            let result = try XCTUnwrap(
                CanvasHappeningSpawnTransaction.commit(
                    canvasLoaded: true,
                    canvas: canvas,
                    model: model,
                    element: element,
                    recordUse: true,
                    at: date,
                    persist: { _ in true }
                )
            )
            canvas = result.canvas
        }

        XCTAssertEqual(canvas.elements.count, 10)
        XCTAssertEqual(Set(canvas.elements.map(\.optionId)).count, 10)
        XCTAssertEqual(model.todayAdditions.count, 10)
        XCTAssertEqual(model.happeningPointsToday, 60)
        XCTAssertTrue(model.availablePaletteHappenings(on: date).isEmpty)
    }

    func testSpawnRejectsCapturedDayBoundaryMismatchWithoutPersistingEitherRecord() {
        let model = makeModel()
        let beforeBoundary = Date(timeIntervalSince1970: 1_786_176_000)
        let afterBoundary = beforeBoundary.addingTimeInterval(24 * 60 * 60)
        let staleCanvas = DayCanvas(dayKey: AppModel.dayKey(for: beforeBoundary))
        let staleElement = fixedElement(on: staleCanvas)
        var persistedCanvases: [DayCanvas] = []

        let result = CanvasHappeningSpawnTransaction.commit(
            canvasLoaded: true,
            canvas: staleCanvas,
            model: model,
            element: staleElement,
            recordUse: true,
            at: afterBoundary,
            persist: {
                persistedCanvases.append($0)
                return true
            }
        )

        XCTAssertNil(result)
        XCTAssertTrue(persistedCanvases.isEmpty)
        XCTAssertTrue(model.todayAdditions.isEmpty)
    }

    func testSpawnPresentationUsesOriginWithoutMutatingCanonicalDestination() throws {
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
        let element = fixedElement(on: canvas)
        var canonical = canvas
        canonical.elements = [element]
        var presentation = CanvasSpawnPresentationState()

        presentation.stage(elementID: element.id, origin: CGPoint(x: 0.5, y: 0.5))

        let originFrame = try XCTUnwrap(presentation.renderedElements(from: canonical.elements).first)
        XCTAssertEqual(originFrame.basePosition, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(canonical.elements[0].basePosition, CGPoint(x: 0.82, y: 0.24))

        presentation.complete(elementID: element.id)

        let destinationFrame = try XCTUnwrap(presentation.renderedElements(from: canonical.elements).first)
        XCTAssertEqual(destinationFrame.basePosition, CGPoint(x: 0.82, y: 0.24))
        XCTAssertEqual(canonical.elements[0].basePosition, CGPoint(x: 0.82, y: 0.24))
    }

    func testPaletteOpenRequestWaitsForTargetCanvasAndIsConsumedOnce() {
        let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var route = CanvasPaletteRouteState()
        route.requestOpen(id: requestID)

        XCTAssertNil(route.consumeIfReady(isCanvasSelected: false, canPresent: true))
        XCTAssertEqual(route.pendingRequestID, requestID)
        XCTAssertEqual(
            route.consumeIfReady(isCanvasSelected: true, canPresent: true),
            requestID
        )
        XCTAssertNil(route.pendingRequestID)
        XCTAssertNil(route.consumeIfReady(isCanvasSelected: true, canPresent: true))

        let reopenID = UUID(uuidString: "11111111-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        route.requestOpen(id: reopenID)
        XCTAssertEqual(
            route.consumeIfReady(isCanvasSelected: true, canPresent: true),
            reopenID,
            "a later targeted request must reopen after the first acknowledgement"
        )
    }

    func testPaletteOnlyBlocksTabsOnCanvasAndLeavingRequestsClosure() {
        XCTAssertTrue(
            CanvasPaletteRouteState.blocksTabBar(
                isCanvasSelected: true,
                isPaletteVisible: true
            )
        )
        XCTAssertFalse(
            CanvasPaletteRouteState.blocksTabBar(
                isCanvasSelected: false,
                isPaletteVisible: true
            )
        )
        XCTAssertTrue(
            CanvasPaletteRouteState.shouldClosePalette(
                isCanvasSelected: false,
                isPaletteVisible: true
            )
        )

        var route = CanvasPaletteRouteState()
        route.requestOpen()
        route.cancelPendingRequest()
        XCTAssertNil(route.pendingRequestID, "explicit tab departure must cancel a stale open")
    }

    private func fixedElement(on canvas: DayCanvas) -> CanvasElement {
        var element = CanvasElement.spawn(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            optionId: "happening_walk",
            label: "Walk",
            existingElements: canvas.elements,
            dayKey: canvas.dayKey,
            composition: DayComposition.forDay(
                dayKey: canvas.dayKey, happeningCount: canvas.elements.count)
        )
        element.basePosition = CGPoint(x: 0.82, y: 0.24)
        return element
    }

    private func makeModel() -> AppModel {
        let subscriptionStore = SubscriptionStore()
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: subscriptionStore
        )
        model.isBootstrapping = true
        model.loadDailyEnergyState()
        return model
    }

    private func clearDefaults() {
        CanvasStorageService.shared.deleteCanvas(for: AppModel.dayKey(for: .now))
        [
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.stepsBalanceAnchor,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.happeningPaletteSelection,
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}

@MainActor
final class HappeningFieldLayoutTests: XCTestCase {

    func testConfiguredSlotsRemainFixedAfterCanvasMembershipChanges() {
        let configured = Array(HappeningDefaults.builtIns.prefix(10))
        var state = HappeningFieldPresentationState(happenings: configured)
        let original = state.layout(in: size, safeInsets: safeInsets)
        var interaction = HappeningPaletteInteractionState()
        _ = interaction.tap(id: configured[0].id, addedIDs: [])
        _ = interaction.tap(id: configured[0].id, addedIDs: [])
        interaction.resolve(.add(configured[0].id), succeeded: true)
        state.receiveParent(configured)
        XCTAssertEqual(state.presentedHappenings.map(\.id), configured.map(\.id))
        XCTAssertEqual(state.layout(in: size, safeInsets: safeInsets), original)
    }

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    // MARK: - The dock stays put

    private var dockSafeBounds: CGRect {
        CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )
    }

    func testFailedCanvasSaveRejectsRemovalWithoutRemovingDomainAddition() {
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        let model = makeRemovalModel()
        defer { clearRemovalDefaults() }
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: date))
        let element = fixedRemovalElement(on: canvas)
        var populatedCanvas = canvas
        populatedCanvas.elements = [element]
        XCTAssertNotNil(
            model.addHappening(
                id: "walk",
                colorHex: element.hexColor,
                at: date,
                recordUse: false,
                entryId: element.id.uuidString
            )
        )

        let failed = CanvasHappeningRemovalTransaction.commit(
            canvasLoaded: true,
            canvas: populatedCanvas,
            model: model,
            happeningID: "walk",
            at: date,
            persist: { _ in false }
        )

        XCTAssertNil(failed)
        XCTAssertEqual(populatedCanvas.elements.count, 1)
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["walk"])
    }

    func testSuccessfulRemovalPersistsEmptyCanonicalCanvasAndRemovesMatchingDomainAddition() throws {
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        let model = makeRemovalModel()
        defer { clearRemovalDefaults() }
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: date))
        let element = fixedRemovalElement(on: canvas)
        var populatedCanvas = canvas
        populatedCanvas.elements = [element]
        XCTAssertNotNil(
            model.addHappening(
                id: "walk",
                colorHex: element.hexColor,
                at: date,
                recordUse: false,
                entryId: element.id.uuidString
            )
        )
        var persistedCanvas: DayCanvas?

        let result = try XCTUnwrap(
            CanvasHappeningRemovalTransaction.commit(
                canvasLoaded: true,
                canvas: populatedCanvas,
                model: model,
                happeningID: "walk",
                at: date,
                persist: {
                    persistedCanvas = $0
                    return true
                }
            )
        )

        XCTAssertTrue(result.canvas.elements.isEmpty)
        XCTAssertEqual(result.removedElement.id, element.id)
        XCTAssertTrue(try XCTUnwrap(persistedCanvas).elements.isEmpty)
        XCTAssertTrue(model.todayAdditions.isEmpty)
    }

    func testFailedEmptyCanonicalSaveKeepsCanvasAndMatchingDomainAddition() {
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        let model = makeRemovalModel()
        defer { clearRemovalDefaults() }
        let canvas = DayCanvas(dayKey: AppModel.dayKey(for: date))
        let element = fixedRemovalElement(on: canvas)
        var populatedCanvas = canvas
        populatedCanvas.elements = [element]
        XCTAssertNotNil(
            model.addHappening(
                id: "walk",
                colorHex: element.hexColor,
                at: date,
                recordUse: false,
                entryId: element.id.uuidString
            )
        )
        var savedCanvases: [DayCanvas] = []

        let failed = CanvasHappeningRemovalTransaction.commit(
            canvasLoaded: true,
            canvas: populatedCanvas,
            model: model,
            happeningID: "walk",
            at: date,
            persist: { canonical in
                CanvasHappeningRemovalPersistence.persist(
                    canonical,
                    save: {
                        savedCanvases.append($0)
                        return false
                    }
                )
            }
        )

        XCTAssertNil(failed)
        XCTAssertEqual(populatedCanvas.elements.map(\.id), [element.id])
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["walk"])
        XCTAssertEqual(savedCanvases.count, 1)
        guard let savedCanvas = savedCanvases.first else {
            XCTFail("The empty canonical canvas should reach persistence")
            return
        }
        XCTAssertTrue(savedCanvas.elements.isEmpty)
        XCTAssertEqual(savedCanvas.lastModified, date)
    }

    func testRemovalRejectsMismatchedDayOrMissingHappeningWithoutSideEffects() {
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        let model = makeRemovalModel()
        defer { clearRemovalDefaults() }
        let element = fixedRemovalElement(on: DayCanvas(dayKey: AppModel.dayKey(for: date)))
        var staleCanvas = DayCanvas(dayKey: "2001-01-01")
        staleCanvas.elements = [element]
        var currentCanvas = DayCanvas(dayKey: AppModel.dayKey(for: date))
        currentCanvas.elements = [element]
        var persistedCanvases: [DayCanvas] = []

        let mismatchedDay = CanvasHappeningRemovalTransaction.commit(
            canvasLoaded: true,
            canvas: staleCanvas,
            model: model,
            happeningID: "walk",
            at: date,
            persist: {
                persistedCanvases.append($0)
                return true
            }
        )
        let missingHappening = CanvasHappeningRemovalTransaction.commit(
            canvasLoaded: true,
            canvas: currentCanvas,
            model: model,
            happeningID: "read",
            at: date,
            persist: {
                persistedCanvases.append($0)
                return true
            }
        )

        XCTAssertNil(mismatchedDay)
        XCTAssertNil(missingHappening)
        XCTAssertEqual(staleCanvas.elements.map(\.id), [element.id])
        XCTAssertEqual(currentCanvas.elements.map(\.id), [element.id])
        XCTAssertTrue(model.todayAdditions.isEmpty)
        XCTAssertTrue(persistedCanvases.isEmpty)
    }

    /// Close · choose · add used to hang off the blob contour, so consuming a
    /// happening slid them up the screen — and with everything added they
    /// jumped to the middle, following the completion island.
    func testDockAnchorIsIdenticalForEveryItemCount() {
        let anchors = (0...10).map {
            HappeningFieldLayout.layout(count: $0, in: size, safeInsets: safeInsets).dockAnchor
        }
        for (count, anchor) in anchors.enumerated() {
            XCTAssertEqual(anchor.x, anchors[0].x, accuracy: 0.01, "count \(count) moved the dock")
            XCTAssertEqual(anchor.y, anchors[0].y, accuracy: 0.01, "count \(count) moved the dock")
        }
    }

    func testDockAnchorIsIdenticalForEveryCountAtAccessibilitySizes() {
        let anchors = (0...10).map {
            HappeningFieldLayout.layout(
                count: $0, in: size, safeInsets: safeInsets, dynamicTypeSize: .accessibility3
            ).dockAnchor
        }
        for (count, anchor) in anchors.enumerated() {
            XCTAssertEqual(anchor.y, anchors[0].y, accuracy: 0.01, "count \(count) moved the dock")
        }
    }

    /// With the tab bar hidden, the palette controls occupy the bottom-safe
    /// corner positions formerly used by the Canvas controls.
    func testDockAnchorSitsAtTheBottomSafeControlLine() {
        let anchor = HappeningFieldLayout.layout(
            count: 3, in: size, safeInsets: safeInsets
        ).dockAnchor
        XCTAssertEqual(anchor.x, dockSafeBounds.midX, accuracy: 0.01)
        XCTAssertGreaterThan(anchor.y, dockSafeBounds.midY)
        XCTAssertEqual(
            anchor.y, dockSafeBounds.maxY - 36, accuracy: 0.01,
            "the list and close controls should stay on the Canvas control line"
        )
    }

    /// Nothing may slide under the pinned dock.
    func testContentNeverOverlapsTheDock() {
        for count in 0...10 {
            let layout = HappeningFieldLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )
            if !layout.contourBounds.isEmpty {
                XCTAssertLessThanOrEqual(
                    layout.contourBounds.maxY, layout.dockAnchor.y,
                    "count \(count): contour runs under the dock"
                )
            }
            if let completion = layout.completionBounds {
                XCTAssertLessThanOrEqual(
                    completion.maxY, layout.dockAnchor.y,
                    "count \(count): completion island runs under the dock"
                )
            }
        }
    }

    func testEverySupportedCountHasAccessibleNonOverlappingCentralLabelZones() {
        for count in 0...10 {
            let layout = HappeningFieldLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            XCTAssertEqual(layout.sources.count, count, "count \(count)")
            XCTAssertEqual(layout.labelFrames.count, count, "count \(count)")

            for frame in layout.labelFrames {
                XCTAssertGreaterThanOrEqual(frame.width, 44, "count \(count)")
                XCTAssertGreaterThanOrEqual(frame.height, 44, "count \(count)")
            }

            let centralLabelZones = layout.labelFrames.map {
                $0.insetBy(dx: $0.width * 0.1, dy: $0.height * 0.12)
            }
            for (index, frame) in centralLabelZones.enumerated() {
                for other in centralLabelZones.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other), "count \(count), frame \(index)")
                }
            }
        }
    }

    func testTenItemPhoneLayoutReservesReadableThreeLineLabelZones() {
        let layout = HappeningFieldLayout.layout(
            count: 10, in: size, safeInsets: safeInsets
        )

        for frame in layout.labelFrames {
            XCTAssertGreaterThanOrEqual(frame.width, 88)
            XCTAssertGreaterThanOrEqual(frame.height, 64)
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
            let layout = HappeningFieldLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            for frame in layout.labelFrames {
                XCTAssertTrue(safeBounds.contains(frame), "count \(count), frame \(frame)")
            }
        }
    }

    /// The dock no longer tracks the contour, so the old "gap of at most 44pt"
    /// clause is deliberately gone — `testContentNeverOverlapsTheDock` covers
    /// what still has to hold.
    func testContourLeavesFreeCanvasOnEverySafeEdge() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for count in 1...10 {
            let layout = HappeningFieldLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )
            let contour = layout.contourBounds

            XCTAssertGreaterThanOrEqual(contour.minX - safeBounds.minX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxX - contour.maxX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(contour.minY - safeBounds.minY, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxY - contour.maxY, 16, "count \(count)")
            XCTAssertGreaterThan(layout.dockAnchor.y, contour.maxY, "count \(count)")
            XCTAssertTrue(safeBounds.contains(layout.dockAnchor), "count \(count)")
        }
    }

    func testExpandedTenItemMetaballIsOneClosedContourInsideSafeBounds() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for typeSize in [
            DynamicTypeSize.accessibility1,
            .accessibility3,
            .accessibility5,
        ] {
            let layout = HappeningFieldLayout.layout(
                count: 10,
                in: size,
                safeInsets: safeInsets,
                dynamicTypeSize: typeSize
            )
            let contour = ProceduralShapeGenerator.metaballPath(
                blobs: layout.sources.map {
                    ProceduralShapeGenerator.BlobSource(
                        center: $0.center,
                        radius: $0.radius
                    )
                },
                in: CGRect(origin: .zero, size: size),
                gridResolution: 58
            )
            var moveCount = 0
            var closeCount = 0
            contour.cgPath.applyWithBlock { element in
                switch element.pointee.type {
                case .moveToPoint:
                    moveCount += 1
                case .closeSubpath:
                    closeCount += 1
                default:
                    break
                }
            }

            XCTAssertEqual(moveCount, 1, "\(typeSize) must generate one contour component")
            XCTAssertEqual(closeCount, 1, "\(typeSize) must close exactly one component")
            XCTAssertTrue(
                safeBounds.insetBy(dx: 2, dy: 2).contains(contour.boundingRect),
                "\(typeSize) contour \(contour.boundingRect) must not be clipped into a boundary chord"
            )
        }
    }

    func testRemovingIndexPreservesRelativeIdentityOrder() {
        let ten = HappeningFieldLayout.layout(count: 10, in: size, safeInsets: EdgeInsets())
        let nine = HappeningFieldLayout.layout(count: 9, in: size, safeInsets: EdgeInsets())
        let eight = HappeningFieldLayout.layout(count: 8, in: size, safeInsets: EdgeInsets())

        XCTAssertEqual(ten.sources.map(\.index), Array(0..<10))
        XCTAssertEqual(nine.sources.map(\.index), Array(0..<9))
        XCTAssertEqual(eight.sources.map(\.index), Array(0..<8))
        XCTAssertTrue(nine.contourBounds.width < size.width)
        XCTAssertTrue(eight.contourBounds.width < size.width)
    }

    func testEmptyFieldKeepsAResidualCompletionIslandAttachedToTheDock() {
        let layout = HappeningFieldLayout.layout(count: 0, in: size, safeInsets: safeInsets)
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        XCTAssertTrue(layout.sources.isEmpty)
        XCTAssertTrue(layout.labelFrames.isEmpty)
        XCTAssertTrue(layout.contourBounds.isEmpty)
        let completionBounds = try! XCTUnwrap(layout.completionBounds)
        XCTAssertTrue(safeBounds.contains(completionBounds))
        XCTAssertGreaterThan(layout.dockAnchor.y, completionBounds.maxY)
        XCTAssertLessThanOrEqual(layout.dockAnchor.y - completionBounds.maxY, 32)
        XCTAssertTrue(safeBounds.contains(layout.dockAnchor))
        XCTAssertGreaterThan(layout.dockAnchor.y, safeBounds.midY)
        XCTAssertEqual(
            layout.dockAnchor.y,
            safeBounds.maxY - 36,
            accuracy: 0.01,
            "the empty state keeps list and close on the Canvas control line"
        )
    }

    func testCompletionIslandHasAnUnbrokenHorizontalNeckBetweenItsLobes() {
        let bounds = CGRect(x: 0, y: 0, width: 216, height: 92)
        let contour = HappeningCompletionIslandShape().path(in: bounds)

        for x in stride(from: 42.0, through: 174.0, by: 4.0) {
            XCTAssertTrue(
                contour.contains(CGPoint(x: x, y: 46)),
                "the completion island must stay filled through its center at x=\(x)"
            )
        }
        XCTAssertFalse(contour.contains(CGPoint(x: 0, y: 0)))
        XCTAssertFalse(contour.contains(CGPoint(x: 216, y: 92)))
    }

    func testLayoutIsDeterministicForTheSameInputs() {
        XCTAssertEqual(
            HappeningFieldLayout.layout(count: 10, in: size, safeInsets: safeInsets),
            HappeningFieldLayout.layout(count: 10, in: size, safeInsets: safeInsets)
        )
    }

    private func fixedRemovalElement(on canvas: DayCanvas) -> CanvasElement {
        var element = CanvasElement.spawn(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            optionId: "walk",
            label: "Walk",
            existingElements: canvas.elements,
            dayKey: canvas.dayKey,
            composition: DayComposition.forDay(
                dayKey: canvas.dayKey,
                happeningCount: canvas.elements.count
            )
        )
        element.basePosition = CGPoint(x: 0.82, y: 0.24)
        return element
    }

    private func makeRemovalModel() -> AppModel {
        clearRemovalDefaults()
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )
        model.isBootstrapping = true
        model.loadDailyEnergyState()
        return model
    }

    private func clearRemovalDefaults() {
        let defaults = UserDefaults.stepsTrader()
        [
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.stepsBalanceAnchor,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.happeningPaletteSelection,
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}

final class HappeningFieldTransitionStateTests: XCTestCase {

    func testBeginRemovalLocksTheSelectedIDAndStartsPressing() {
        var state = HappeningFieldTransitionState()

        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testBusyTransitionIgnoresDuplicateButQueuesAnotherZone() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))

        XCTAssertFalse(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
        XCTAssertEqual(state.queuedIDs, ["happening_read"])
        XCTAssertTrue(state.isLocked(id: "happening_walk"))
        XCTAssertTrue(state.isLocked(id: "happening_read"))
        XCTAssertFalse(state.isLocked(id: "happening_coffee"))
    }

    func testRapidSecondTapRunsAfterFirstReflowWithoutClosingPalette() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
        XCTAssertTrue(state.resolveBreakthrough(id: "happening_walk", accepted: true))
        XCTAssertTrue(state.finishRemoval(id: "happening_walk"))

        XCTAssertEqual(state.beginNextQueuedRemoval(), "happening_read")
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_read")
        XCTAssertTrue(state.queuedIDs.isEmpty)
    }

    func testRejectedFirstTapStillAdvancesAQueuedValidZone() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))

        XCTAssertFalse(state.resolveBreakthrough(id: "happening_walk", accepted: false))
        XCTAssertEqual(state.beginNextQueuedRemoval(), "happening_read")
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_read")
    }

    func testMetadataRefreshKeepsEveryHitTargetAtItsConfiguredSource() throws {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let configured = Array(HappeningDefaults.builtIns.prefix(10))
        var presentation = HappeningFieldPresentationState(happenings: configured)
        let original = presentation.layout(in: size, safeInsets: safeInsets)
        var refreshed = configured
        refreshed[0].useCount += 1
        presentation.receiveParent(refreshed)
        XCTAssertEqual(presentation.layout(in: size, safeInsets: safeInsets), original)
        XCTAssertEqual(presentation.presentedHappenings.first?.useCount, refreshed[0].useCount)
    }

    func testFinishRemovalUnlocksOnlyAfterReflowAndAllowsAnotherID() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .reflowing))

        XCTAssertFalse(state.finishRemoval(id: "happening_read"))
        XCTAssertTrue(state.finishRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selectedID)
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
    }

    func testCancelRemovalRollsBackEveryBusyPhaseAndUnlocksControls() {
        for terminalPhase in [RemovalPhase.pressing, .sinking, .reflowing] {
            var state = HappeningFieldTransitionState()
            XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
            if terminalPhase == .sinking || terminalPhase == .reflowing {
                XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
            }
            if terminalPhase == .reflowing {
                XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .reflowing))
            }

            state.cancelRemoval()

            XCTAssertEqual(state.phase, .idle, "cancel from \(terminalPhase)")
            XCTAssertNil(state.selectedID, "cancel from \(terminalPhase)")
            XCTAssertTrue(
                state.beginRemoval(id: "happening_read"),
                "controls should unlock after cancelling \(terminalPhase)"
            )
        }
    }

    func testRejectedBreakthroughRestoresTheZoneAndUnlocksAnotherID() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))

        XCTAssertFalse(
            state.resolveBreakthrough(id: "happening_walk", accepted: false)
        )

        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selectedID)
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
    }

    func testAcceptedBreakthroughAdvancesToReflow() {
        var state = HappeningFieldTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))

        XCTAssertTrue(
            state.resolveBreakthrough(id: "happening_walk", accepted: true)
        )

        XCTAssertEqual(state.phase, .reflowing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testTransitionHitRegionCoversOldNewAndInterpolatedVisibleContours() {
        let bounds = CGRect(x: 0, y: 0, width: 260, height: 180)
        let old = [
            HappeningFieldLayout.Source(index: 0, center: CGPoint(x: 50, y: 90), radius: 38),
            HappeningFieldLayout.Source(index: 1, center: CGPoint(x: 90, y: 90), radius: 38),
        ]
        let new = [
            HappeningFieldLayout.Source(index: 0, center: CGPoint(x: 170, y: 90), radius: 38),
            HappeningFieldLayout.Source(index: 1, center: CGPoint(x: 210, y: 90), radius: 38),
        ]

        let hitRegion = HappeningFieldContourHitRegion.path(
            currentSources: new,
            transitionSources: old,
            in: bounds
        )

        XCTAssertTrue(hitRegion.contains(CGPoint(x: 70, y: 90)), "old contour")
        XCTAssertTrue(hitRegion.contains(CGPoint(x: 130, y: 90)), "interpolated contour")
        XCTAssertTrue(hitRegion.contains(CGPoint(x: 190, y: 90)), "new contour")
        XCTAssertFalse(hitRegion.contains(CGPoint(x: 130, y: 10)))
    }
}

final class HappeningFieldPresentationStateTests: XCTestCase {

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testParentRefreshPreservesAllTenConfiguredSlotsAndUpdatesMetadata() throws {
        let initial = Array(HappeningDefaults.builtIns.prefix(10))
        var state = HappeningFieldPresentationState(happenings: initial)
        let original = state.layout(in: size, safeInsets: safeInsets)
        var refreshed = initial
        refreshed[1].useCount = 7
        state.receiveParent(refreshed)
        XCTAssertEqual(state.presentedHappenings.map(\.id), initial.map(\.id))
        XCTAssertEqual(state.presentedHappenings[1].useCount, 7)
        XCTAssertEqual(state.layout(in: size, safeInsets: safeInsets), original)
    }

    func testConfiguredReplacementTakesFirstTenAndPreservesTheirOrder() {
        var state = HappeningFieldPresentationState(happenings: [])
        let configured = Array(HappeningDefaults.builtIns.reversed())
        state.receiveParent(configured)
        XCTAssertEqual(state.presentedHappenings.map(\.id), Array(configured.prefix(10)).map(\.id))
    }
}

/// Label contrast is unrelated to the replaced blob geometry, so it remains
/// covered here after the legacy layout test file is retired.
final class HappeningPaletteLabelContrastTests: XCTestCase {

    func testLuminanceEndpoints() {
        XCTAssertEqual(HappeningFieldLabelTreatment.relativeLuminance(ofHex: "#000000"), 0, accuracy: 0.001)
        XCTAssertEqual(HappeningFieldLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"), 1, accuracy: 0.001)
    }

    func testLuminanceToleratesMissingHashAndWhitespace() {
        XCTAssertEqual(
            HappeningFieldLabelTreatment.relativeLuminance(ofHex: " FFFFFF "),
            HappeningFieldLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"),
            accuracy: 0.001
        )
    }

    func testTreatmentUsesProductionWeightedTwoColorBlend() {
        let treatment = HappeningFieldLabelTreatment(
            primaryHex: "#CC5050",
            accentHex: "#E098A0"
        )

        XCTAssertEqual(treatment.red, 0.821960784, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.green, 0.392784314, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.blue, 0.401568627, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.backingLuminance, 0.237553298, accuracy: 0.000_000_1)
    }

    func testTextBoundsUseMostOfTheFieldZoneWithoutRecreatingAButtonLens() {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        for count in 1...10 {
            let layout = HappeningFieldLayout.layout(
                count: count,
                in: size,
                safeInsets: safeInsets
            )
            for labelFrame in layout.labelFrames {
                let textSize = HappeningFieldLabelTreatment.inscribedTextSize(
                    in: labelFrame.size
                )
                XCTAssertGreaterThanOrEqual(textSize.width / labelFrame.width, 0.82)
                XCTAssertGreaterThanOrEqual(textSize.height / labelFrame.height, 0.76)
            }
        }
    }

    func testAccessibilityTypographyAdaptsGeometryAndFitsEveryPrimaryLabel() {
        let standardLayout = HappeningFieldLayout.layout(
            count: 10,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .large
        )
        let accessibilityLayout = HappeningFieldLayout.layout(
            count: 10,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .accessibility1
        )

        let baseFont = UIFont.systemFont(
            ofSize: 14,
            weight: .semibold
        )
        let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded)
            ?? baseFont.fontDescriptor
        let roundedBaseFont = UIFont(
            descriptor: roundedDescriptor,
            size: 14
        )
        let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: roundedBaseFont,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: .accessibilityMedium
            )
        )

        XCTAssertGreaterThan(font.pointSize, 14)
        XCTAssertGreaterThanOrEqual(accessibilityLayout.labelFrames[0].width, 44)
        XCTAssertGreaterThanOrEqual(accessibilityLayout.labelFrames[0].height, 44)
        XCTAssertLessThan(
            accessibilityLayout.labelFrames[0].width,
            standardLayout.labelFrames[0].width,
            "the accessible two-column layout trades diameter for more vertical text room"
        )

        for (index, frame) in accessibilityLayout.labelFrames.enumerated() {
            for other in accessibilityLayout.labelFrames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), "accessibility label frames must not overlap")
            }
        }

        for (happening, frame) in zip(HappeningDefaults.builtIns, accessibilityLayout.labelFrames) {
            let textSize = HappeningFieldLabelTreatment.inscribedTextSize(in: frame.size)
            let measured = (happening.localizedTitle() as NSString).boundingRect(
                with: CGSize(width: textSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )

            XCTAssertLessThanOrEqual(
                ceil(measured.height),
                textSize.height,
                "\(happening.localizedTitle()) must fit without truncation"
            )
            XCTAssertLessThanOrEqual(
                ceil(measured.height / font.lineHeight),
                4,
                "\(happening.localizedTitle()) must fit within four accessibility lines"
            )
        }
    }

    func testCompletionMessageGetsLargerGeometryAtAccessibilitySizes() {
        let standard = HappeningFieldLayout.layout(
            count: 0,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .large
        )
        let accessibility = HappeningFieldLayout.layout(
            count: 0,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .accessibility1
        )

        XCTAssertGreaterThan(
            try! XCTUnwrap(accessibility.completionBounds).width,
            try! XCTUnwrap(standard.completionBounds).width
        )
        XCTAssertGreaterThan(
            try! XCTUnwrap(accessibility.completionBounds).height,
            try! XCTUnwrap(standard.completionBounds).height
        )
    }
}

final class HappeningPaletteChromeLayoutTests: XCTestCase {

    func testPanelTextFieldsRetainAReadableSurfaceAndTouchTarget() {
        XCTAssertGreaterThanOrEqual(HappeningPanelTextFieldAppearance.minimumHeight, 44)
        XCTAssertGreaterThanOrEqual(HappeningPanelTextFieldAppearance.fillOpacity, 0.10)
        XCTAssertGreaterThanOrEqual(HappeningPanelTextFieldAppearance.strokeOpacity, 0.18)
    }

    func testOpenPanelHidesTabBarButClearsPersistentEnergyAndControls() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true
            )
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelTopInset(
                topCardHeight: 176,
                hidesSurroundingChrome: true
            ),
            188
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelBottomInset(
                tabBarHeight: 82,
                hidesSurroundingChrome: true
            ),
            94
        )
    }

    func testAccessibilityPanelClearsPersistentEnergyAndControls() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true
            )
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelTopInset(
                topCardHeight: 220,
                hidesSurroundingChrome: true
            ),
            232
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelBottomInset(
                tabBarHeight: 150,
                hidesSurroundingChrome: true
            ),
            162
        )
    }

    func testEveryExpandedTypeHidesChromeAndKeepsDockInsideSafeBounds() {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let safeBounds = CGRect(x: 0, y: 59, width: 402, height: 781)

        for typeSize in [
            DynamicTypeSize.xLarge,
            .xxLarge,
            .xxxLarge,
            .accessibility1,
        ] {
            XCTAssertTrue(
                HappeningPaletteChromeLayout.hidesSurroundingChrome(
                    isPalettePresented: true
                ),
                "\(typeSize) uses expanded field geometry and must hide surrounding chrome"
            )

            let layout = HappeningFieldLayout.layout(
                count: 10,
                in: size,
                safeInsets: safeInsets,
                dynamicTypeSize: typeSize
            )
            XCTAssertTrue(safeBounds.contains(layout.dockAnchor), "\(typeSize)")
            XCTAssertLessThanOrEqual(layout.dockAnchor.y + 22, safeBounds.maxY, "\(typeSize)")
        }
    }

    func testPresentedPaletteHidesStandardChromeBeforeAChildPanelOpens() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true
            )
        )
    }

    func testCreatorDisabledActionRemainsLegibleInIncreasedContrast() {
        XCTAssertEqual(HappeningCreatorActionAppearance.disabledForegroundOpacity, 1)
        XCTAssertGreaterThanOrEqual(
            HappeningCreatorActionAppearance.increasedContrastStrokeOpacity,
            0.6
        )
    }

    func testPaletteKeepsCornerControlsWhileHidingTheTabBar() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.showsCanvasControls(
                isPalettePresented: true
            )
        )
        XCTAssertTrue(
            HappeningPaletteChromeLayout.showsCanvasControls(
                isPalettePresented: false
            )
        )
    }
}

final class CanvasSpawnOriginMapperTests: XCTestCase {

    func testViewportCenterMapsToCanonicalCanvasCenter() {
        let mapped = CanvasSpawnOriginMapper.normalizedPosition(
            for: CGPoint(x: 201, y: 400),
            viewportSize: CGSize(width: 402, height: 800),
            canvasSize: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(mapped.x, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(mapped.y, 0.5, accuracy: 0.000_001)
    }

    func testOriginMappingClampsPointsOutsideCanonicalCanvas() {
        let mapped = CanvasSpawnOriginMapper.normalizedPosition(
            for: CGPoint(x: -100, y: 1_000),
            viewportSize: CGSize(width: 402, height: 800),
            canvasSize: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(mapped, CGPoint(x: 0, y: 1))
    }
}

final class HappeningFieldContourHitRegionTests: XCTestCase {
    func testHitRegionIncludesVisibleMetaballNeckOutsideSourceCircles() {
        let sources = [
            HappeningFieldLayout.Source(
                index: 0,
                center: CGPoint(x: 80, y: 100),
                radius: 42
            ),
            HappeningFieldLayout.Source(
                index: 1,
                center: CGPoint(x: 180, y: 100),
                radius: 42
            ),
        ]
        let neck = CGPoint(x: 130, y: 100)

        XCTAssertGreaterThan(hypot(neck.x - sources[0].center.x, neck.y - sources[0].center.y), 42)
        XCTAssertGreaterThan(hypot(neck.x - sources[1].center.x, neck.y - sources[1].center.y), 42)
        XCTAssertTrue(
            HappeningFieldContourHitRegion.path(
                sources: sources,
                in: CGRect(x: 0, y: 0, width: 260, height: 200)
            ).contains(neck)
        )
    }

    func testHitRegionIncludesAntialiasedHaloOutsideSingleSourceContour() {
        let sources = [
            HappeningFieldLayout.Source(
                index: 0,
                center: CGPoint(x: 100, y: 100),
                radius: 40
            )
        ]

        XCTAssertTrue(
            HappeningFieldContourHitRegion.path(
                sources: sources,
                in: CGRect(x: 0, y: 0, width: 200, height: 200)
            ).contains(CGPoint(x: 150, y: 100))
        )
    }
}

final class HappeningEditorialAssignmentTests: XCTestCase {
    private let dayKey = "2026-09-05"
    private let happening = Happening(
        id: "happening_walk",
        title: "Walk",
        isBuiltIn: true
    )

    /// Catches a reroll accidentally changing the promised object instead of
    /// changing only its restrained color variation.
    func testColorRerollKeepsElementIdentityAndShapeStable() throws {
        let first = try XCTUnwrap(
            HappeningEditorialAssignmentResolver.assignments(
                happenings: [happening],
                baseInput: editorialInput(),
                colorNonce: 20
            )[happening.id]
        )
        let rerolled = try XCTUnwrap(
            HappeningEditorialAssignmentResolver.assignments(
                happenings: [happening],
                baseInput: editorialInput(),
                colorNonce: 21
            )[happening.id]
        )

        XCTAssertEqual(first.elementID, rerolled.elementID)
        XCTAssertEqual(first.shape, rerolled.shape)
        XCTAssertNotEqual(first.colorVariant, rerolled.colorVariant)
    }

    /// Catches the palette and production renderer deriving appearance through
    /// separate paths: the material shown before confirmation must be the one
    /// rendered after the element is persisted.
    func testPreviewMaterialMatchesTheFinalEditorialActor() throws {
        let assignment = try XCTUnwrap(
            HappeningEditorialAssignmentResolver.assignments(
                happenings: [happening],
                baseInput: editorialInput(),
                colorNonce: 21
            )[happening.id]
        )
        var canvas = DayCanvas(dayKey: dayKey)
        var element = CanvasElement.spawn(
            id: assignment.elementID,
            optionId: happening.id,
            label: happening.title,
            existingElements: [],
            dayKey: dayKey,
            composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
        )
        element.editorialColorVariant = assignment.colorVariant
        canvas.elements = [element]

        let finalInput = EditorialCanvasInputFactory.make(
            canvas: canvas,
            metrics: EditorialCanvasMetrics(
                stepsProgress: 0.5,
                sleepProgress: 0.5,
                spentProgress: 0
            ),
            paletteCategories: ModernPaletteSelection.all
        )
        let finalActor = try XCTUnwrap(
            DayObjectScene.make(input: finalInput.sceneInput)
                .sceneRecipeV1?
                .actor(assignment.elementID.uuidString.lowercased())
        )

        XCTAssertEqual(finalActor.shape, assignment.shape)
        XCTAssertEqual(finalActor.material, assignment.material)
    }

    /// Catches a committed tile being recomputed from its daily placeholder
    /// UUID or rerolled colour, and catches an uncommitted tile resolving in a
    /// different final slot than the one it receives after confirmation.
    func testSnapshotPreservesCommittedAppearanceAndMatchesProspectiveCommit() throws {
        let committed = Happening(
            id: "happening_read",
            title: "Read",
            isBuiltIn: true
        )
        let available = Happening(
            id: "happening_walk",
            title: "Walk",
            isBuiltIn: true
        )
        let committedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        var committedElement = CanvasElement.spawn(
            id: committedID,
            optionId: committed.id,
            label: committed.title,
            existingElements: [],
            dayKey: dayKey,
            composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
        )
        committedElement.editorialColorVariant = 37
        var baseCanvas = DayCanvas(dayKey: dayKey)
        baseCanvas.elements = [committedElement]
        let metrics = EditorialCanvasMetrics(
            stepsProgress: 0.5,
            sleepProgress: 0.5,
            spentProgress: 0
        )
        let baseInput = EditorialCanvasInputFactory.make(
            canvas: baseCanvas,
            metrics: metrics,
            paletteCategories: ModernPaletteSelection.all
        ).sceneInput
        let snapshot = HappeningEditorialAssignmentResolver.snapshot(
            request: HappeningEditorialAssignmentRequest(
                happenings: [committed, available],
                baseInput: baseInput,
                committedElements: baseCanvas.elements,
                colorNonce: 21
            )
        )
        let committedAssignment = try XCTUnwrap(snapshot.assignments[committed.id])
        let previewAssignment = try XCTUnwrap(snapshot.assignments[available.id])

        XCTAssertEqual(committedAssignment.elementID, committedID)
        XCTAssertEqual(committedAssignment.colorVariant, 37)

        var canvasAfterCommit = baseCanvas
        var committedPreview = CanvasElement.spawn(
            id: previewAssignment.elementID,
            optionId: available.id,
            label: available.title,
            existingElements: baseCanvas.elements,
            dayKey: dayKey,
            composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 1)
        )
        committedPreview.editorialColorVariant = previewAssignment.colorVariant
        canvasAfterCommit.elements.append(committedPreview)
        let finalActor = try XCTUnwrap(
            DayObjectScene.make(input: EditorialCanvasInputFactory.make(
                canvas: canvasAfterCommit,
                metrics: metrics,
                paletteCategories: ModernPaletteSelection.all
            ).sceneInput).sceneRecipeV1?.actor(
                previewAssignment.elementID.uuidString.lowercased()
            )
        )

        XCTAssertEqual(previewAssignment.shape, finalActor.shape)
        XCTAssertEqual(previewAssignment.material.gpuAppearance, finalActor.material.gpuAppearance)
    }

    /// Catches the renderer ignoring a persisted color variation. Shape,
    /// geometry, and gradient fields stay fixed while the color order changes.
    func testActorColorVariantChangesOnlyTheMaterialColors() throws {
        let eventID = "11111111-2222-3333-4444-555555555555"
        let original = try XCTUnwrap(
            DayObjectScene.make(input: editorialInput(
                eventIDs: [eventID],
                actorColorVariants: [eventID: 0],
                materialMode: .wideGradient
            )).sceneRecipeV1?.actor(eventID)
        )
        let rerolled = try XCTUnwrap(
            DayObjectScene.make(input: editorialInput(
                eventIDs: [eventID],
                actorColorVariants: [eventID: 1],
                materialMode: .wideGradient
            )).sceneRecipeV1?.actor(eventID)
        )

        XCTAssertEqual(original.shape, rerolled.shape)
        XCTAssertEqual(original.geometryRegion, rerolled.geometryRegion)
        XCTAssertEqual(original.material.fields, rerolled.material.fields)
        XCTAssertEqual(original.material.family, rerolled.material.family)
        XCTAssertNotEqual(original.material.colors, rerolled.material.colors)
    }

    /// Catches a regression back to irregular or loosely spaced templates.
    func testTenItemsUseTouchingThreeTwoThreeTwoRows() {
        let layout = HappeningFieldLayout.layout(
            count: 10,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            contentTopInset: 188,
            dockCenterY: 804
        )
        let rows = Dictionary(grouping: layout.sources) { round($0.center.y * 100) / 100 }
            .values
            .sorted { $0[0].center.y < $1[0].center.y }

        XCTAssertEqual(rows.map(\.count), [3, 2, 3, 2])
        XCTAssertEqual(Set(layout.sources.map { round($0.radius * 100) / 100 }).count, 1)
        for row in rows {
            let ordered = row.sorted { $0.center.x < $1.center.x }
            for pair in zip(ordered, ordered.dropFirst()) {
                let gap = pair.1.center.x - pair.0.center.x - pair.0.radius - pair.1.radius
                XCTAssertGreaterThanOrEqual(gap, -0.01)
                XCTAssertLessThanOrEqual(gap, 0.5)
            }
        }
    }

    private func editorialInput(
        eventIDs: [String] = [],
        actorColorVariants: [String: Int] = [:],
        materialMode: DayObjectEditorialLabMaterialMode = .generativeDNA
    ) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: dayKey,
            identity: "primary-canvas",
            eventIDs: eventIDs,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            canvasCoverage: .fullCanvas,
            paletteCategories: ModernPaletteSelection.all,
            usesEditorialField: true,
            editorialBackground: .dark,
            lowSleep: true,
            editorialLabConfiguration: DayObjectEditorialLabConfiguration(
                materialMode: materialMode,
                placement: .depthField
            ),
            actorColorVariants: actorColorVariants
        )
    }
}
