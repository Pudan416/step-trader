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
        XCTAssertLessThanOrEqual(duplicateScene.actors.count, 40)
        XCTAssertEqual(Set(duplicateScene.actorIDs).count, duplicateScene.actors.count)
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

    func testLeadAuditionRegionEndsBeforeTheLabControls() {
        let leadRegion = DayObjectNormalizedRect.dayObjectsLeadAudition
        let controls = DayObjectNormalizedRect.dayObjectsLabControls

        XCTAssertLessThan(leadRegion.maxY, controls.minY)
        XCTAssertFalse(leadRegion.intersects(controls))
    }

#if DEBUG || INTERNAL_BUILD
    @MainActor
    func testLabDayProgressMapsExactlyIntoSceneInput() {
        let model = DayObjectsLabMusicViewModel()

        for (steps, expectedMotion) in [(0.0, 0.25), (5_000.0, 0.625), (10_000.0, 1.0)] {
            model.setSteps(steps)
            XCTAssertEqual(
                model.sceneInput(dayKey: "2026-08-20", reduceMotion: false).motionEnergy,
                expectedMotion,
                accuracy: 0.000_001
            )
        }

        for (sleep, expectedClarity) in [(0.0, 0.35), (4.0, 0.625), (8.0, 0.90)] {
            model.setSleepHours(sleep)
            XCTAssertEqual(
                model.sceneInput(dayKey: "2026-08-20", reduceMotion: false).visualClarity,
                expectedClarity,
                accuracy: 0.000_001
            )
        }
    }

    @MainActor
    func testLabHappeningsRemainTheSceneEventSource() {
        let model = DayObjectsLabMusicViewModel()
        model.setHappeningCount(3)

        let input = model.sceneInput(dayKey: "2026-08-20", reduceMotion: false)
        let scene = DayObjectScene.make(input: input)

        XCTAssertEqual(input.eventIDs, [
            "lab-happening-01",
            "lab-happening-02",
            "lab-happening-03",
        ])
        XCTAssertFalse(scene.actors.isEmpty)
        XCTAssertEqual(Set(scene.actors.map(\.eventID)), Set(input.eventIDs))
    }
#endif
}

final class DayObjectCompositionTests: XCTestCase {
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
}
