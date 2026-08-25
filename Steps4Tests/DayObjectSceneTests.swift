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
}

final class DayObjectCompositionTests: XCTestCase {
    func testDayObjectsOnlyExposeCircleDerivedShapes() {
        XCTAssertEqual(DayObjectShape.allCases, [.sphere, .ellipse, .lens, .softBlob])
    }

    func testRestingSizeBandsUseApprovedDiameterRanges() {
        XCTAssertEqual(DayObjectSizeBand.support.diameterRange, 0.14...0.21)
        XCTAssertEqual(DayObjectSizeBand.satellite.diameterRange, 0.08...0.13)
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

    func testShapeAndFillNumericValuesMatchMetalShaderABI() {
        let expectedShapes: [DayObjectShape: UInt32] = [
            .sphere: 0,
            .ellipse: 1,
            .lens: 2,
            .softBlob: 3,
        ]
        let expectedFills: [DayObjectFill: UInt32] = [
            .radialOne: 0,
            .radialTwo: 1,
            .radialThree: 2,
        ]
        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
        var observedShapes = [DayObjectShape: UInt32]()
        var observedFills = [DayObjectFill: UInt32]()

        for index in 0..<2_048
        where observedShapes.count < expectedShapes.count || observedFills.count < expectedFills.count {
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
            guard let gpuActor = frame.actors.first?.gpuActor else {
                XCTFail("A one-event scene must provide an actor")
                return
            }
            observedShapes[scene.composition.shape] = gpuActor.shape
            observedFills[scene.composition.fill] = gpuActor.fill
        }

        XCTAssertEqual(observedShapes, expectedShapes)
        XCTAssertEqual(observedFills, expectedFills)
    }

    func testOrbShapeNumericValuesAreExplicitAndStable() {
        XCTAssertEqual(DayObjectShape.sphere.numericValue, 0)
        XCTAssertEqual(DayObjectShape.ellipse.numericValue, 1)
        XCTAssertEqual(DayObjectShape.lens.numericValue, 2)
        XCTAssertEqual(DayObjectShape.softBlob.numericValue, 3)
    }
}
