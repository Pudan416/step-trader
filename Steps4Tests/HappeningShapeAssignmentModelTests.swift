import XCTest
@testable import Steps4

@MainActor
final class HappeningShapeAssignmentModelTests: XCTestCase {

    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "HappeningShapeAssignmentModelTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: storageDirectory.appending(path: "pastDaySnapshots.json"))
        PersistenceManager.storageDirectoryOverride = storageDirectory
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        PersistenceManager.storageDirectoryOverride = nil
        try? FileManager.default.removeItem(at: storageDirectory)
        storageDirectory = nil
        super.tearDown()
    }

    private func clearKeys() {
        let defaults = UserDefaults.stepsTrader()
        for key in [
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.happeningPaletteSelection,
            SharedKeys.happeningShapeNonce,
            SharedKeys.happeningShapeNonceDayKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore.shared
        )
    }

    func testEveryConfiguredHappeningHasAFigure() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let figures = model.paletteFigures()
        for happening in model.configuredPaletteHappenings() {
            XCTAssertNotNil(figures[happening.id], "No figure for \(happening.id)")
        }
    }

    func testFiguresAreStableAcrossCalls() {
        let model = makeModel()
        model.loadDailyEnergyState()
        XCTAssertEqual(model.paletteFigures(), model.paletteFigures())
    }

    func testRerollChangesTheFigures() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let before = model.paletteFigures()
        model.rerollPaletteFigures()

        XCTAssertNotEqual(before, model.paletteFigures())
    }

    /// Shake must not reach what is already on the canvas. The addition keeps
    /// the colour it was logged with however many times the field re-rolls.
    func testRerollDoesNotChangeAlreadyLoggedAdditions() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        _ = model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)

        model.rerollPaletteFigures(on: date)

        XCTAssertEqual(model.todayAdditions.first?.colorHex, "#AABBCC")
    }

    /// Ten tiles, ten colours — the roll is fed the configured ids, so this is
    /// really a check that the model passes them all in one call rather than
    /// rolling per happening.
    func testConfiguredHappeningsGetDistinctColours() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let figures = model.paletteFigures()
        let colours = model.configuredPaletteHappenings().compactMap { figures[$0.id]?.colorHex }

        XCTAssertEqual(Set(colours).count, colours.count)
    }

    /// Catches the palette rebuilding a different assignment map for the same
    /// value inputs instead of retaining a stable, cacheable snapshot.
    func testSnapshotRetainsItsExactRequestAndAssignmentsForEqualInput() {
        let happening = Happening(
            id: "happening_walk",
            title: "Walk",
            isBuiltIn: true
        )
        let request = HappeningEditorialAssignmentRequest(
            happenings: [happening],
            baseInput: DayObjectSceneInput(
                dayKey: "2026-09-05",
                identity: "primary-canvas",
                eventIDs: [],
                motionEnergy: 0.625,
                visualClarity: 0.625,
                canvasCoverage: .fullCanvas,
                paletteCategories: ModernPaletteSelection.all,
                usesEditorialField: true,
                editorialBackground: .dark,
                lowSleep: true,
                editorialLabConfiguration: DayObjectEditorialLabConfiguration(
                    materialMode: .generativeDNA,
                    placement: .depthField
                )
            ),
            committedElements: [],
            colorNonce: 21
        )

        let first = HappeningEditorialAssignmentResolver.snapshot(request: request)
        let second = HappeningEditorialAssignmentResolver.snapshot(request: request)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.request, request)
    }

    /// Catches the state cache keeping an empty pre-hydration palette after a
    /// canvas arrives, or keeping actors made with stale metric-derived scene
    /// inputs while the palette stays open.
    func testSnapshotRefreshPolicyInvalidatesHydratedAndMetricChangedRequests() {
        let happening = Happening(
            id: "happening_walk",
            title: "Walk",
            isBuiltIn: true
        )
        let metrics = EditorialCanvasMetrics(
            stepsProgress: 0.5,
            sleepProgress: 0.5,
            spentProgress: 0.1
        )
        let emptyCanvas = DayCanvas(dayKey: "2026-09-05")
        let initialRequest = HappeningEditorialAssignmentRequest(
            happenings: [happening],
            baseInput: EditorialCanvasInputFactory.make(
                canvas: emptyCanvas,
                metrics: metrics,
                paletteCategories: ModernPaletteSelection.all
            ).sceneInput,
            committedElements: [],
            colorNonce: 21
        )
        let initialSnapshot = HappeningEditorialAssignmentResolver.snapshot(request: initialRequest)
        var hydratedCanvas = emptyCanvas
        var hydratedElement = CanvasElement.spawn(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            optionId: happening.id,
            label: happening.title,
            existingElements: [],
            dayKey: hydratedCanvas.dayKey,
            composition: DayComposition.forDay(dayKey: hydratedCanvas.dayKey, happeningCount: 0)
        )
        hydratedElement.editorialColorVariant = 37
        hydratedCanvas.elements = [hydratedElement]
        let hydratedRequest = HappeningEditorialAssignmentRequest(
            happenings: [happening],
            baseInput: EditorialCanvasInputFactory.make(
                canvas: hydratedCanvas,
                metrics: metrics,
                paletteCategories: ModernPaletteSelection.all
            ).sceneInput,
            committedElements: hydratedCanvas.elements,
            colorNonce: 21
        )
        let metricChangedRequest = HappeningEditorialAssignmentRequest(
            happenings: [happening],
            baseInput: EditorialCanvasInputFactory.make(
                canvas: emptyCanvas,
                metrics: EditorialCanvasMetrics(
                    stepsProgress: 0.75,
                    sleepProgress: 0.8,
                    spentProgress: 0.25
                ),
                paletteCategories: ModernPaletteSelection.all
            ).sceneInput,
            committedElements: [],
            colorNonce: 21
        )

        XCTAssertFalse(
            HappeningEditorialAssignmentResolver.needsRefresh(
                current: initialSnapshot,
                request: initialRequest
            )
        )
        XCTAssertTrue(
            HappeningEditorialAssignmentResolver.needsRefresh(
                current: initialSnapshot,
                request: hydratedRequest
            )
        )
        XCTAssertTrue(
            HappeningEditorialAssignmentResolver.needsRefresh(
                current: initialSnapshot,
                request: metricChangedRequest
            )
        )
    }
}
