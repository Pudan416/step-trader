import XCTest
@testable import Steps4

final class DayObjectSceneTests: XCTestCase {
    private func input(_ ids: [String]) -> DayObjectSceneInput {
        .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: ids,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
    }

    func testAddingEventPreservesExistingActors() {
        let before = DayObjectScene.make(input: input(["walk", "sleep"]))
        let after = DayObjectScene.make(input: input(["walk", "sleep", "read"]))
        let retained = after.actors.filter { before.actorIDs.contains($0.id) }
        XCTAssertEqual(retained, before.actors)
    }

    func testSceneUsesOnePresetAndOneMaterialForTheWholeDay() {
        let scene = DayObjectScene.make(input: input((0..<10).map { "event-\($0)" }))
        XCTAssertEqual(scene.motionPlan.configuration, scene.choreographyConfiguration)
        XCTAssertEqual(Set(scene.actors.map { $0.appearance.material }), [scene.visualLanguage.family])
        XCTAssertEqual(Set(scene.actors.map { $0.choreographySlot.ordinal }).count,
                       Set(scene.actors.map { $0.id }).count)
    }

    func testAddingAnEventDoesNotRerollRetainedActors() {
        let five = DayObjectScene.make(input: input((0..<5).map { "event-\($0)" }))
        let six = DayObjectScene.make(input: input((0..<6).map { "event-\($0)" }))
        for actor in five.actors {
            let retained = six.actors.first { $0.id == actor.id }!
            XCTAssertEqual(retained.appearance, actor.appearance)
            XCTAssertEqual(retained.route, actor.route)
            XCTAssertEqual(retained.choreographySlot, actor.choreographySlot)
        }
    }

    func testArbitraryActorAppearanceIsIndependentOfPreferredPrimaryAddRemoveAndOrder() throws {
        let eventIDs = [
            "alpha-forest", "beta-river", "gamma-stone", "delta-cloud",
            "epsilon-lantern", "zeta-window", "eta-orchard", "theta-bridge",
        ]

        for retainedID in eventIDs {
            let alone = DayObjectScene.make(input: input([retainedID]))
            let expected = try XCTUnwrap(alone.actors.first)
            for addedID in eventIDs where addedID != retainedID {
                for order in [[addedID, retainedID], [retainedID, addedID]] {
                    let expanded = DayObjectScene.make(input: input(order))
                    let retained = try XCTUnwrap(
                        expanded.actors.first { $0.eventID == retainedID }
                    )
                    XCTAssertEqual(retained.appearance, expected.appearance)
                    XCTAssertEqual(retained.choreographySlot, expected.choreographySlot)
                    XCTAssertEqual(retained.route, expected.route)
                }
            }
        }
    }

    func testEventOrderDoesNotChangeActors() {
        let a = DayObjectScene.make(input: input(["walk", "sleep"]))
        let b = DayObjectScene.make(input: input(["sleep", "walk"]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: a.actors.map { ($0.id, $0) }),
            Dictionary(uniqueKeysWithValues: b.actors.map { ($0.id, $0) })
        )
    }

    func testDuplicateEventsAreDeduplicatedAndBudgeted() {
        let uniqueIDs = (0..<80).map { "event-\($0)" }
        let duplicateIDs = uniqueIDs.flatMap { [$0, $0] }
        let uniqueScene = DayObjectScene.make(input: input(uniqueIDs))
        let duplicateScene = DayObjectScene.make(input: input(duplicateIDs))

        XCTAssertEqual(duplicateScene.actors, uniqueScene.actors)
        XCTAssertEqual(duplicateScene.actors.count, 10)
        XCTAssertEqual(DayObjectScene.maxActors, 10)
        XCTAssertEqual(Set(duplicateScene.actorIDs).count, duplicateScene.actors.count)
    }

    func testSceneOwnsThreeDailyPalettesAndOneAppearancePerActor() {
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: (0..<10).map { "event-\($0)" },
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            paletteCategories: [.pastel, .cold]
        ))

        XCTAssertEqual(
            Set([
                scene.paletteSet.background.code,
                scene.paletteSet.primaryObjects.code,
                scene.paletteSet.secondaryObjects.code,
            ]).count,
            3
        )
        XCTAssertEqual(scene.visualLanguage.paletteSet, scene.paletteSet)
        XCTAssertEqual(
            scene.palette.colors,
            scene.paletteSet.background.hexes.map(DayObjectRGB.init(hex:))
        )
        XCTAssertEqual(scene.actors.count, 10)
        XCTAssertEqual(
            scene.actors.map(\.appearance),
            scene.actors.compactMap {
                scene.visualLanguage.appearances(
                    eventIDs: scene.input.eventIDs,
                    rootSeed: scene.rootSeed
                )[$0.eventID]
            }
        )
        XCTAssertTrue(scene.actors.allSatisfy { $0.id.memberIndex == 0 })
    }

    func testOneUniqueHappeningProducesOneStableOrb() {
        let scene = DayObjectScene.make(input: input(["walk", "walk", "sleep", "read"]))

        XCTAssertEqual(scene.actors.map(\.eventID), ["walk", "sleep", "read"])
        XCTAssertEqual(scene.composition.flockSize, 1)
    }

    func testEmptyEventIDIsDeduplicatedWithoutDisplacingLaterEvents() {
        let withDuplicate = DayObjectScene.make(input: input(["", "", "walk"]))
        let withSingle = DayObjectScene.make(input: input(["", "walk"]))

        XCTAssertEqual(withDuplicate.actors, withSingle.actors)
        XCTAssertTrue(withDuplicate.actorIDs.contains { $0.eventID.isEmpty })
        XCTAssertTrue(withDuplicate.actorIDs.contains { $0.eventID == "walk" })
    }

    func testZeroEventsProduceStableDailySceneWithoutActors() {
        let first = DayObjectScene.make(input: input([]))
        let second = DayObjectScene.make(input: input([]))

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.actors.isEmpty)
        XCTAssertTrue(first.actorIDs.isEmpty)
        XCTAssertFalse(first.meshGradientStyle.colors.isEmpty)
    }

    func testRemovingAndReaddingEventRestoresIdenticalActors() {
        let original = DayObjectScene.make(input: input(["walk", "sleep", "read"]))
        let withoutSleep = DayObjectScene.make(input: input(["walk", "read"]))
        let restored = DayObjectScene.make(input: input(["walk", "sleep", "read"]))

        XCTAssertEqual(restored, original)
        XCTAssertEqual(
            withoutSleep.actors,
            original.actors.filter { $0.eventID != "sleep" }
        )
    }

    func testSceneInputDefaultsToLabExclusionAndPreservesCustomRegion() {
        let defaultInput = input(["walk"])
        XCTAssertEqual(defaultInput.uiExclusionRegion, .dayObjectsLabControls)
        XCTAssertEqual(DayObjectsLabView.uiExclusionRegion, .dayObjectsLabControls)

        let custom = DayObjectNormalizedRect(
            minX: 0.72,
            minY: 0.05,
            maxX: 0.98,
            maxY: 0.46
        )
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: ["walk"],
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            uiExclusionRegion: custom
        ))
        XCTAssertEqual(scene.input.uiExclusionRegion, custom)
        XCTAssertEqual(scene.compositionPlan.uiExclusionRegion, custom)
    }

    func testLabUsesFullCanvasCoverageInsteadOfBottomControlExclusion() {
        XCTAssertEqual(DayObjectsLabView.canvasCoverage, .fullCanvas)
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "day-objects-lab",
            eventIDs: (0..<10).map { "event-\($0)" },
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            canvasCoverage: .fullCanvas
        ))

        XCTAssertEqual(scene.input.canvasCoverage, .fullCanvas)
        XCTAssertEqual(scene.compositionPlan.uiExclusionRegion.area, 0)
    }

    func testHarmonicWeaveDayUsesOneDialectWithCircleDerivedCarrierVariety() throws {
        let scene = try firstHarmonicWeaveScene()
        let styles = try scene.actors.map {
            try XCTUnwrap($0.appearance.harmonicWeaveStyle)
        }

        XCTAssertEqual(Set(scene.actors.map { $0.appearance.material }), [.harmonicWeave])
        XCTAssertEqual(Set(styles.map(\.dialect)).count, 1)
        XCTAssertGreaterThanOrEqual(Set(scene.actors.map { $0.appearance.shape }).count, 4)
        XCTAssertTrue(scene.actors.allSatisfy {
            [.sphere, .ellipse, .lens, .softBlob, .softStar, .roundedPolygon, .roundedSquare]
                .contains($0.appearance.shape)
        })
        XCTAssertLessThanOrEqual(
            scene.actors.filter { $0.appearance.shape == .softStar }.count,
            2
        )
    }

    func testHarmonicWeaveActorStyleSurvivesInsertionRemovalAndReorder() throws {
        let seedScene = try firstHarmonicWeaveScene()
        let dayKey = seedScene.input.dayKey
        let ids = (0..<10).map { "lab-event-\($0)" }
        func scene(_ eventIDs: [String]) -> DayObjectScene {
            DayObjectScene.make(input: .init(
                dayKey: dayKey,
                identity: "day-objects-lab",
                eventIDs: eventIDs,
                motionEnergy: 0.55,
                visualClarity: 0.55,
                reduceMotion: false,
                canvasCoverage: .fullCanvas,
                paletteCategories: ModernPaletteSelection.all
            ))
        }

        let full = scene(ids)
        let reordered = scene(Array(ids.reversed()))
        let removed = scene(ids.filter { $0 != "lab-event-4" })

        for actor in full.actors {
            let reorderedActor = try XCTUnwrap(
                reordered.actors.first { $0.eventID == actor.eventID }
            )
            XCTAssertEqual(reorderedActor.appearance, actor.appearance)
            if actor.eventID != "lab-event-4" {
                let retained = try XCTUnwrap(
                    removed.actors.first { $0.eventID == actor.eventID }
                )
                XCTAssertEqual(retained.appearance, actor.appearance)
            }
        }
    }

    func testHarmonicWeaveParametersRemainInsideApprovedRanges() throws {
        let scene = try firstHarmonicWeaveScene()
        for actor in scene.actors {
            let style = try XCTUnwrap(actor.appearance.harmonicWeaveStyle)
            XCTAssertTrue((3...6).contains(style.primaryFrequency))
            XCTAssertTrue((4...10).contains(style.secondaryFrequency))
            XCTAssertTrue((0.04...0.52).contains(style.aperture))
            XCTAssertTrue((0.024...0.052).contains(style.lineWidth))
        }
    }

    func testHarmonicWeaveReservesDetailedConstructionForLargeMinority() throws {
        let scene = try firstHarmonicWeaveScene()
        let detailed = scene.actors.filter { $0.appearance.mutationRole == .base }

        XCTAssertTrue((3...5).contains(detailed.count))

        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: DayObjectEnvironment(
                motionEnergy: scene.input.motionEnergy,
                visualClarity: scene.input.visualClarity,
                reduceMotion: false
            ),
            elapsed: 0,
            insertions: [:]
        )
        for actor in detailed {
            let rendered = try XCTUnwrap(
                frame.actors.first { $0.eventID == actor.eventID }
            )
            XCTAssertGreaterThanOrEqual(
                rendered.gpuActor.halfSize.x * 2,
                0.35,
                "Detailed line construction must only appear at a legible large scale"
            )
        }
    }

    private func firstHarmonicWeaveScene() throws -> DayObjectScene {
        for index in 0..<4_096 {
            let scene = DayObjectScene.make(input: .init(
                dayKey: "harmonic-weave-\(index)",
                identity: "day-objects-lab",
                eventIDs: (0..<10).map { "lab-event-\($0)" },
                motionEnergy: 0.55,
                visualClarity: 0.55,
                reduceMotion: false,
                canvasCoverage: .fullCanvas,
                paletteCategories: ModernPaletteSelection.all
            ))
            if scene.visualLanguage.family == .harmonicWeave { return scene }
        }
        throw XCTSkip("No Harmonic Weave day found in deterministic sample")
    }
}

final class DayObjectCompositionTests: XCTestCase {
    func testDayObjectsOnlyExposeCircleDerivedShapes() {
        XCTAssertEqual(
            DayObjectShape.allCases,
            [.sphere, .ellipse, .lens, .softBlob, .softStar, .roundedPolygon, .roundedSquare]
        )
    }

    func testRestingSizeBandsUseApprovedDiameterRanges() {
        XCTAssertEqual(DayObjectSizeBand.focal.diameterRange, 0.28...0.42)
        XCTAssertEqual(DayObjectSizeBand.support.diameterRange, 0.15...0.26)
        XCTAssertEqual(DayObjectSizeBand.satellite.diameterRange, 0.065...0.13)
    }

    func testOrbElongationNeverProducesThinLegacyParticles() {
        XCTAssertEqual(DayObjectElongation.allCases, [.round, .oval])
        XCTAssertEqual(DayObjectElongation.round.aspectRange, 0.92...1.0)
        XCTAssertEqual(DayObjectElongation.oval.aspectRange, 0.72...0.90)
    }

    func testAllShapeFamiliesAreReachableAcrossBroadDailySample() {
        var reached = Set<DayObjectShape>()

        for index in 0..<2_048 {
            reached.insert(DayObjectComposition.forDay(
                dayKey: "shape-reachability-\(index)",
                identity: "tester"
            ).shape)
        }

        XCTAssertEqual(reached, Set(DayObjectShape.allCases))
    }

    func testProductionSphereAndAppearanceColorCountNumericValuesMatchMetalShaderABI() {
        let expectedShapes: [DayObjectShape: UInt32] = Dictionary(
            uniqueKeysWithValues: DayObjectShape.allCases.map { ($0, $0.numericValue) }
        )
        let expectedColorCounts: Set<UInt32> = [1, 2, 3]
        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
        var observedShapes = [DayObjectShape: UInt32]()
        var observedColorCounts = Set<UInt32>()

        for index in 0..<2_048
        where observedShapes.count < expectedShapes.count
            || observedColorCounts.count < expectedColorCounts.count {
            let scene = DayObjectScene.make(input: .init(
                dayKey: "shape-abi-\(index)",
                identity: "tester",
                eventIDs: ["event"],
                motionEnergy: 0.55,
                visualClarity: 0.55,
                reduceMotion: false
            ))
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: environment,
                elapsed: 0,
                insertions: [:]
            )
            guard let actor = scene.actors.first,
                  let renderActor = frame.actors.first else {
                XCTFail("A one-event scene must provide an actor")
                return
            }
            observedShapes[actor.appearance.shape] = renderActor.gpuActor.shape
            observedColorCounts.insert(renderActor.gpuAppearance.metadata.y)
        }

        XCTAssertEqual(observedShapes, expectedShapes)
        XCTAssertEqual(observedColorCounts, expectedColorCounts)
    }

    func testOrbShapeNumericValuesAreExplicitAndStable() {
        XCTAssertEqual(DayObjectShape.sphere.numericValue, 0)
        XCTAssertEqual(DayObjectShape.ellipse.numericValue, 1)
        XCTAssertEqual(DayObjectShape.lens.numericValue, 2)
        XCTAssertEqual(DayObjectShape.softBlob.numericValue, 3)
        XCTAssertEqual(DayObjectShape.softStar.numericValue, 4)
        XCTAssertEqual(DayObjectShape.roundedPolygon.numericValue, 5)
        XCTAssertEqual(DayObjectShape.roundedSquare.numericValue, 6)
    }
}
