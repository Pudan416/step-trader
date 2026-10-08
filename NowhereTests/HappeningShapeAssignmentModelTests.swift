import XCTest
@testable import Nowhere

@MainActor
final class HappeningShapeAssignmentModelTests: XCTestCase {

    func testNativeCatalogSnapshotAvoidsLegacySceneConstruction() throws {
        let happenings = HappeningDefaults.builtIns
        XCTAssertEqual(happenings.count, 100)
        let day = "2026-10-08"
        let baseRecipe = NativeAtlasRecipe.makeDaily(dayKey: day, paletteCategories: ModernPaletteSelection.all, collection: .circles)
        for nonce: UInt64 in [19, 20, 21] {
            let count = nonce == 19 ? 0 : (nonce == 20 ? 3 : 10)
            let retainedIDs = (0..<count).map { "retained-\($0)" }
            let recipe = baseRecipe.reconciled(eventIDs: retainedIDs)
            let input = DayObjectSceneInput(dayKey: day, identity: "primary-canvas", eventIDs: retainedIDs, motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: recipe)
            let request = HappeningEditorialAssignmentRequest(happenings: happenings, baseInput: input, committedElements: [], colorNonce: nonce)
            var builds = 0
            let started = DispatchTime.now().uptimeNanoseconds
            let snapshot = HappeningEditorialAssignmentResolver.snapshot(request: request, legacySceneFactory: { input in
                builds += 1
                return DayObjectScene.make(input: input)
            })
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            print("Native snapshot nonce=\(nonce) legacyScenes=\(builds) elapsedMs=\(milliseconds)")
            XCTAssertEqual(snapshot.assignments.count, 100)
            XCTAssertEqual(builds, 0, "Native candidates must not construct discarded legacy scene trees")
            for assignment in snapshot.assignments.values {
                XCTAssertEqual(assignment.nativeActor, recipe.prospectiveActor(eventID: assignment.elementID.uuidString.lowercased()))
            }
        }
        let legacy = DayObjectSceneInput(dayKey: day, identity: "primary-canvas", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true)
        var legacyBuilds = 0
        let fallback = HappeningEditorialAssignmentResolver.snapshot(request: .init(happenings: happenings, baseInput: legacy, committedElements: [], colorNonce: 19), legacySceneFactory: { input in
            legacyBuilds += 1
            return DayObjectScene.make(input: input)
        })
        XCTAssertEqual(legacyBuilds, 100)
        XCTAssertEqual(fallback.assignments.count, 100)
    }

    func testNativeSnapshotKeepsLegacyPresentationMetadataAndCommittedIdentity() throws {
        let day = "2026-10-08"
        var element = CanvasElement.spawn(optionId: "happening_walk", label: "Walk", existingElements: [], dayKey: day, composition: DayComposition.forDay(dayKey: day, happeningCount: 0))
        let happenings: [Happening] = [.init(id: "event_walk", title: "Walk", isBuiltIn: true), .init(id: "event_read", title: "Read", isBuiltIn: true)]
        let configurations: [DayObjectEditorialLabConfiguration?] = [nil, .init(materialMode: .generativeDNA, placement: .depthField)]
        for collection in NativeAtlasDailyStyle.Collection.selectableCases {
            for configuration in configurations {
                for preview in [nil, DayObjectEditorialPreviewCatalog.all.first] {
                    for variant: Int? in [nil, 7] {
                        element.editorialColorVariant = variant
                        for occupancy in [1, 10] {
                            let retainedID = element.id.uuidString.lowercased()
                            let retainedIDs = [retainedID] + (1..<occupancy).map { "retained-other-\($0)" }
                            let recipe = NativeAtlasRecipe.makeDaily(dayKey: day, paletteCategories: ModernPaletteSelection.all, collection: collection).reconciled(eventIDs: retainedIDs)
                            let input = DayObjectSceneInput(dayKey: day, identity: "primary-canvas", eventIDs: retainedIDs, motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, editorialPreview: preview, editorialLabConfiguration: configuration, nativeAtlasRecipe: recipe)
                            let request = HappeningEditorialAssignmentRequest(happenings: happenings, baseInput: input, committedElements: [element], colorNonce: 5)
                            let snapshot = HappeningEditorialAssignmentResolver.snapshot(request: request)
                            let committed = try XCTUnwrap(snapshot.assignments["event_walk"])
                            XCTAssertEqual(committed.elementID, element.id)
                            XCTAssertEqual(committed.colorVariant, element.editorialColorVariant)
                            for assignment in snapshot.assignments.values {
                                let id = assignment.elementID.uuidString.lowercased()
                                let ids = input.eventIDs.contains(id) ? input.eventIDs : Array(input.eventIDs.prefix(9)) + [id]
                                var variants = input.actorColorVariants
                                variants[id] = assignment.colorVariant
                                let referenceInput = DayObjectSceneInput(dayKey: day, identity: input.identity, eventIDs: ids, motionEnergy: input.motionEnergy, visualClarity: input.visualClarity, usesEditorialField: true, editorialPreview: preview, editorialLabConfiguration: configuration, actorColorVariants: variants)
                                let expected = try XCTUnwrap(DayObjectScene.make(input: referenceInput).sceneRecipeV1?.actor(id))
                                XCTAssertEqual(assignment.shape, expected.shape)
                                XCTAssertEqual(assignment.material, expected.material)
                                XCTAssertEqual(assignment.silhouette, expected.silhouette)
                                XCTAssertEqual(assignment.nativeActor, recipe.prospectiveActor(eventID: id))
                            }
                        }
                    }
                }
            }
        }
    }

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
        let defaults = UserDefaults.nowhere()
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
