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
            color: "#AABBCC",
            label: "Walk",
            existingElements: canvas.elements,
            dayKey: canvas.dayKey
        )
        element.basePosition = CGPoint(x: 0.82, y: 0.24)
        return element
    }

    private func makeModel() -> AppModel {
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        let subscriptionStore = SubscriptionStore(defaults: defaults)
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
            SharedKeys.isGrandfathered,
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.stepsBalanceAnchor,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.happeningPaletteSelection,
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}

final class HappeningLiquidLayoutTests: XCTestCase {

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

    /// Close · choose · add used to hang off the blob contour, so consuming a
    /// happening slid them up the screen — and with everything added they
    /// jumped to the middle, following the completion island.
    func testDockAnchorIsIdenticalForEveryItemCount() {
        let anchors = (0...10).map {
            HappeningLiquidLayout.layout(count: $0, in: size, safeInsets: safeInsets).dockAnchor
        }
        for (count, anchor) in anchors.enumerated() {
            XCTAssertEqual(anchor.x, anchors[0].x, accuracy: 0.01, "count \(count) moved the dock")
            XCTAssertEqual(anchor.y, anchors[0].y, accuracy: 0.01, "count \(count) moved the dock")
        }
    }

    func testDockAnchorIsIdenticalForEveryCountAtAccessibilitySizes() {
        let anchors = (0...10).map {
            HappeningLiquidLayout.layout(
                count: $0, in: size, safeInsets: safeInsets, dynamicTypeSize: .accessibility3
            ).dockAnchor
        }
        for (count, anchor) in anchors.enumerated() {
            XCTAssertEqual(anchor.y, anchors[0].y, accuracy: 0.01, "count \(count) moved the dock")
        }
    }

    /// Pinned means low and stable, not floating mid-screen.
    func testDockAnchorSitsBelowTheMiddleAndClearOfBottomChrome() {
        let anchor = HappeningLiquidLayout.layout(
            count: 3, in: size, safeInsets: safeInsets
        ).dockAnchor
        XCTAssertEqual(anchor.x, dockSafeBounds.midX, accuracy: 0.01)
        XCTAssertGreaterThan(anchor.y, dockSafeBounds.midY)
        XCTAssertLessThanOrEqual(
            anchor.y, dockSafeBounds.maxY - 120,
            "must stay clear of the canvas controls and tab bar underneath"
        )
    }

    /// Nothing may slide under the pinned dock.
    func testContentNeverOverlapsTheDock() {
        for count in 0...10 {
            let layout = HappeningLiquidLayout.layout(
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

    func testTenItemPhoneLayoutReservesReadableThreeLineLabelZones() {
        let layout = HappeningLiquidLayout.layout(
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
            let layout = HappeningLiquidLayout.layout(
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
            let layout = HappeningLiquidLayout.layout(
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
            let layout = HappeningLiquidLayout.layout(
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
        let ten = HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: EdgeInsets())
        let nine = HappeningLiquidLayout.layout(count: 9, in: size, safeInsets: EdgeInsets())
        let eight = HappeningLiquidLayout.layout(count: 8, in: size, safeInsets: EdgeInsets())

        XCTAssertEqual(ten.sources.map(\.index), Array(0..<10))
        XCTAssertEqual(nine.sources.map(\.index), Array(0..<9))
        XCTAssertEqual(eight.sources.map(\.index), Array(0..<8))
        XCTAssertTrue(nine.contourBounds.width < size.width)
        XCTAssertTrue(eight.contourBounds.width < size.width)
    }

    func testEmptyFieldKeepsAResidualCompletionIslandAttachedToTheDock() {
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
        let completionBounds = try! XCTUnwrap(layout.completionBounds)
        XCTAssertTrue(safeBounds.contains(completionBounds))
        XCTAssertGreaterThan(layout.dockAnchor.y, completionBounds.maxY)
        XCTAssertLessThanOrEqual(layout.dockAnchor.y - completionBounds.maxY, 32)
        XCTAssertTrue(safeBounds.contains(layout.dockAnchor))
        XCTAssertGreaterThan(layout.dockAnchor.y, safeBounds.midY)
        XCTAssertLessThanOrEqual(
            layout.dockAnchor.y,
            safeBounds.maxY - 120,
            "the empty-state controls must stay clear of persistent bottom chrome"
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

    func testBusyTransitionIgnoresDuplicateButQueuesAnotherZone() {
        var state = HappeningLiquidTransitionState()
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
        var state = HappeningLiquidTransitionState()
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
        var state = HappeningLiquidTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))

        XCTAssertFalse(state.resolveBreakthrough(id: "happening_walk", accepted: false))
        XCTAssertEqual(state.beginNextQueuedRemoval(), "happening_read")
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_read")
    }

    func testQueuedRemovalResolvesMovedZoneFromCurrentNineItemLayout() throws {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let initial = Array(HappeningDefaults.builtIns.prefix(10))
        let queued = initial[9]
        var presentation = HappeningLiquidPresentationState(happenings: initial)
        let tenItemLayout = presentation.layout(in: size, safeInsets: safeInsets)
        let staleSource = tenItemLayout.sources[9]

        XCTAssertTrue(presentation.remove(id: initial[0].id))
        let nineItemLayout = presentation.layout(in: size, safeInsets: safeInsets)
        let currentIndex = try XCTUnwrap(
            presentation.presentedHappenings.firstIndex { $0.id == queued.id }
        )
        let resolved = try XCTUnwrap(
            HappeningLiquidRemovalResolver.resolve(
                id: queued.id,
                presentation: presentation,
                size: size,
                safeInsets: safeInsets,
                dynamicTypeSize: .large
            )
        )

        XCTAssertEqual(resolved.happening.id, queued.id)
        XCTAssertEqual(resolved.source, nineItemLayout.sources[currentIndex])
        XCTAssertEqual(resolved.transitionSources, nineItemLayout.sources)
        XCTAssertGreaterThan(
            hypot(
                resolved.source.center.x - staleSource.center.x,
                resolved.source.center.y - staleSource.center.y
            ),
            80,
            "the fixture must prove the queued zone moved substantially during 10→9 reflow"
        )
        XCTAssertNotEqual(resolved.source, staleSource)
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

    func testCancelRemovalRollsBackEveryBusyPhaseAndUnlocksControls() {
        for terminalPhase in [RemovalPhase.pressing, .sinking, .reflowing] {
            var state = HappeningLiquidTransitionState()
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
        var state = HappeningLiquidTransitionState()
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
        var state = HappeningLiquidTransitionState()
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
            HappeningLiquidLayout.Source(index: 0, center: CGPoint(x: 50, y: 90), radius: 38),
            HappeningLiquidLayout.Source(index: 1, center: CGPoint(x: 90, y: 90), radius: 38),
        ]
        let new = [
            HappeningLiquidLayout.Source(index: 0, center: CGPoint(x: 170, y: 90), radius: 38),
            HappeningLiquidLayout.Source(index: 1, center: CGPoint(x: 210, y: 90), radius: 38),
        ]

        let hitRegion = HappeningLiquidContourHitRegion.path(
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

final class HappeningLiquidPresentationStateTests: XCTestCase {

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testOnPickParentUpdateDuringReflowDoesNotResurrectSessionRemoval() throws {
        let initial = Array(HappeningDefaults.builtIns.prefix(3))
        let removed = initial[0]
        let survivor = initial[1]
        var state = HappeningLiquidPresentationState(happenings: initial)

        var parentRefresh = initial
        parentRefresh[1].useCount = 7
        state.receiveParent(parentRefresh, whileTransitioning: true)
        XCTAssertTrue(state.remove(id: removed.id))
        state.finishTransition()

        XCTAssertFalse(state.presentedHappenings.contains { $0.id == removed.id })
        XCTAssertEqual(
            try XCTUnwrap(state.presentedHappenings.first { $0.id == survivor.id }).useCount,
            7,
            "parent metadata should still merge into surviving session items"
        )
    }

    func testSharedPresentationCountLeavesDockFixedThroughTenNineEight() {
        var state = HappeningLiquidPresentationState(
            happenings: Array(HappeningDefaults.builtIns.prefix(10))
        )

        let ten = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 10)

        XCTAssertTrue(state.remove(id: state.presentedHappenings[0].id))
        let nine = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 9)

        XCTAssertTrue(state.remove(id: state.presentedHappenings[0].id))
        let eight = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 8)

        // Inverted deliberately: the dock is anchored to a full field, so
        // consuming happenings must NOT move it. It used to ride up the screen
        // with the shrinking cluster.
        XCTAssertEqual(ten.dockAnchor, nine.dockAnchor)
        XCTAssertEqual(nine.dockAnchor, eight.dockAnchor)
    }

}

/// Label contrast is unrelated to the replaced blob geometry, so it remains
/// covered here after the legacy layout test file is retired.
final class HappeningPaletteLabelContrastTests: XCTestCase {

    func testLuminanceEndpoints() {
        XCTAssertEqual(HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#000000"), 0, accuracy: 0.001)
        XCTAssertEqual(HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"), 1, accuracy: 0.001)
    }

    func testLuminanceToleratesMissingHashAndWhitespace() {
        XCTAssertEqual(
            HappeningLiquidLabelTreatment.relativeLuminance(ofHex: " FFFFFF "),
            HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"),
            accuracy: 0.001
        )
    }

    func testTreatmentUsesProductionWeightedTwoColorBlend() {
        let treatment = HappeningLiquidLabelTreatment(
            primaryHex: "#CC5050",
            accentHex: "#E098A0"
        )

        XCTAssertEqual(treatment.red, 0.821960784, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.green, 0.392784314, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.blue, 0.401568627, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.backingLuminance, 0.237553298, accuracy: 0.000_000_1)
    }

    func testEveryRenderedWarmBlendHasFourPointFiveContrastInItsTranslucentFieldZone() {
        for slot in 0..<HappeningLiquidField.warmPaletteIndices.count {
            let treatment = HappeningLiquidField.labelTreatment(forSlot: slot)

            XCTAssertGreaterThanOrEqual(
                treatment.fieldZoneContrastRatio,
                4.5,
                "slot \(slot) has insufficient rendered field-zone contrast (\(treatment.fieldZoneContrastRatio))"
            )
            XCTAssertLessThan(
                treatment.fieldZoneOpacity,
                1,
                "slot \(slot) must blend into the shared field instead of becoming an opaque control"
            )
        }
    }

    func testTextBoundsUseMostOfTheFieldZoneWithoutRecreatingAButtonLens() {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        for count in 1...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count,
                in: size,
                safeInsets: safeInsets
            )
            for labelFrame in layout.labelFrames {
                let textSize = HappeningLiquidLabelTreatment.inscribedTextSize(
                    in: labelFrame.size
                )
                XCTAssertGreaterThanOrEqual(textSize.width / labelFrame.width, 0.82)
                XCTAssertGreaterThanOrEqual(textSize.height / labelFrame.height, 0.76)
            }
        }
    }

    func testAccessibilityTypographyExpandsGeometryAndFitsEveryPrimaryLabel() {
        let standardLayout = HappeningLiquidLayout.layout(
            count: 10,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .large
        )
        let accessibilityLayout = HappeningLiquidLayout.layout(
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
        XCTAssertGreaterThan(
            accessibilityLayout.labelFrames[0].width,
            standardLayout.labelFrames[0].width
        )
        XCTAssertGreaterThan(
            accessibilityLayout.labelFrames[0].height,
            standardLayout.labelFrames[0].height
        )

        for (index, frame) in accessibilityLayout.labelFrames.enumerated() {
            for other in accessibilityLayout.labelFrames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), "accessibility label frames must not overlap")
            }
        }

        for (happening, frame) in zip(HappeningDefaults.builtIns, accessibilityLayout.labelFrames) {
            let textSize = HappeningLiquidLabelTreatment.inscribedTextSize(in: frame.size)
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
        let standard = HappeningLiquidLayout.layout(
            count: 0,
            in: CGSize(width: 402, height: 874),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            dynamicTypeSize: .large
        )
        let accessibility = HappeningLiquidLayout.layout(
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

    func testOpenPanelHidesChromeAndUsesCompactInsetsAtStandardType() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true,
                isPanelPresented: true,
                dynamicTypeSize: .large
            )
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelTopInset(
                topCardHeight: 176,
                hidesSurroundingChrome: true
            ),
            20
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelBottomInset(
                tabBarHeight: 82,
                hidesSurroundingChrome: true
            ),
            20
        )
    }

    func testAccessibilityTypeHidesSurroundingChromeAndUsesCompactInsets() {
        XCTAssertTrue(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true,
                isPanelPresented: false,
                dynamicTypeSize: .accessibility2
            )
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelTopInset(
                topCardHeight: 220,
                hidesSurroundingChrome: true
            ),
            20
        )
        XCTAssertEqual(
            HappeningPaletteChromeLayout.panelBottomInset(
                tabBarHeight: 150,
                hidesSurroundingChrome: true
            ),
            20
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
                    isPalettePresented: true,
                    isPanelPresented: false,
                    dynamicTypeSize: typeSize
                ),
                "\(typeSize) uses expanded field geometry and must hide surrounding chrome"
            )

            let layout = HappeningLiquidLayout.layout(
                count: 10,
                in: size,
                safeInsets: safeInsets,
                dynamicTypeSize: typeSize
            )
            XCTAssertTrue(safeBounds.contains(layout.dockAnchor), "\(typeSize)")
            XCTAssertLessThanOrEqual(layout.dockAnchor.y + 22, safeBounds.maxY, "\(typeSize)")
        }
    }

    func testPaletteWithoutPanelKeepsStandardChrome() {
        XCTAssertFalse(
            HappeningPaletteChromeLayout.hidesSurroundingChrome(
                isPalettePresented: true,
                isPanelPresented: false,
                dynamicTypeSize: .large
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

    func testCanvasControlsYieldToPresentedPalette() {
        XCTAssertFalse(
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

final class HappeningLiquidContourHitRegionTests: XCTestCase {

    func testHitRegionIncludesVisibleMetaballNeckOutsideSourceCircles() {
        let sources = [
            HappeningLiquidLayout.Source(
                index: 0,
                center: CGPoint(x: 80, y: 100),
                radius: 42
            ),
            HappeningLiquidLayout.Source(
                index: 1,
                center: CGPoint(x: 180, y: 100),
                radius: 42
            ),
        ]
        let neck = CGPoint(x: 130, y: 100)

        XCTAssertGreaterThan(hypot(neck.x - sources[0].center.x, neck.y - sources[0].center.y), 42)
        XCTAssertGreaterThan(hypot(neck.x - sources[1].center.x, neck.y - sources[1].center.y), 42)
        XCTAssertTrue(
            HappeningLiquidContourHitRegion.path(
                sources: sources,
                in: CGRect(x: 0, y: 0, width: 260, height: 200)
            ).contains(neck)
        )
    }

    func testHitRegionIncludesAntialiasedHaloOutsideSingleSourceContour() {
        let sources = [
            HappeningLiquidLayout.Source(
                index: 0,
                center: CGPoint(x: 100, y: 100),
                radius: 40
            )
        ]

        XCTAssertTrue(
            HappeningLiquidContourHitRegion.path(
                sources: sources,
                in: CGRect(x: 0, y: 0, width: 200, height: 200)
            ).contains(CGPoint(x: 150, y: 100))
        )
    }
}
