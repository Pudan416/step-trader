import XCTest
import simd
@testable import Steps4

final class DayObjectChoreographyTests: XCTestCase {
    private func fixtureInput(seed: UInt64, count: Int) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "fixture-\(seed)", identity: "tester",
            eventIDs: (0..<count).map { "event-\($0)" },
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false
        )
    }

    func testEveryScoreUsesCuratedSpeedRatios() {
        let allowed: Set<Double> = [0.5, 0.75, 1, 1.5, 2]
        for seed in UInt64(0)..<300 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 12))
            XCTAssertTrue(scene.actors.allSatisfy { allowed.contains($0.speedRatio) })
        }
    }

    func testScoresAreDeterministicAndUseTheCuratedDailyStructure() {
        XCTAssertEqual(DayObjectChapter.allCases.count, 6)
        XCTAssertEqual(
            DayObjectChapter.allCases.map { String(describing: $0) },
            ["orbit", "spiral", "crossing", "stack", "bloom", "drift"]
        )
        XCTAssertEqual(DayObjectChapter.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])

        var reached = Set<DayObjectChapter>()
        for seed in UInt64(0)..<300 {
            let score = DayObjectChoreographyScore.make(seed: seed)
            XCTAssertEqual(score, DayObjectChoreographyScore.make(seed: seed))
            XCTAssertTrue((3...5).contains(score.chapters.count))
            XCTAssertTrue((36...72).contains(score.duration))
            XCTAssertEqual(score.boundaryTimes.count, score.chapters.count - 1)
            reached.formUnion(score.chapters)
        }
        XCTAssertEqual(reached, Set(DayObjectChapter.allCases))
    }

    func testLoopAndChapterBoundariesAreContinuous() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 7, count: 10))
        let score = scene.score
        for actor in scene.actors {
            for boundary in score.boundaryTimes + [score.duration] {
                let a = score.pose(for: actor, at: boundary - 0.0001, canvasAspect: 0.46)
                let b = score.pose(for: actor, at: boundary + 0.0001, canvasAspect: 0.46)
                XCTAssertLessThan(simd_distance(a.position, b.position), 0.002)
                XCTAssertLessThan(abs(a.opacity - b.opacity), 0.01)
            }
        }
    }

    func testScaleTangentAndOrientationAreContinuousAtEveryBoundary() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 7, count: 10))
        let template = scene.actors[0]
        let actors = DayObjectSpin.allCases.map { spin in
            DayObjectActor(
                id: template.id,
                seed: template.seed,
                role: template.role,
                shape: template.shape,
                elongation: template.elongation,
                sizeBand: template.sizeBand,
                fill: template.fill,
                trajectory: template.trajectory,
                spin: spin,
                speedRatio: template.speedRatio,
                phaseOffset: template.phaseOffset,
                depthBand: template.depthBand,
                zIndex: template.zIndex
            )
        }

        for actor in actors {
            for boundary in scene.score.boundaryTimes + [scene.score.duration] {
                let a = scene.score.pose(for: actor, at: boundary - 0.0001, canvasAspect: 0.46)
                let b = scene.score.pose(for: actor, at: boundary + 0.0001, canvasAspect: 0.46)
                let aDirection = SIMD2<Double>(cos(a.rotation), sin(a.rotation))
                let bDirection = SIMD2<Double>(cos(b.rotation), sin(b.rotation))

                XCTAssertLessThan(abs(a.scale - b.scale), 0.001)
                XCTAssertLessThan(simd_distance(a.tangent, b.tangent), 0.01)
                XCTAssertLessThan(simd_distance(aDirection, bDirection), 0.01)
            }
        }
    }

    func testPlannedProductionPathIsContinuousAcrossChapterAndLoopBoundaries() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 7, count: 40))
        for aspect in [0.46, 1.0, 4.0 / 3.0, 2.16] {
            for actor in scene.actors {
                for boundary in scene.score.boundaryTimes + [scene.score.duration] {
                    let before = scene.score.pose(
                        for: actor,
                        at: boundary - 0.0001,
                        canvasAspect: aspect,
                        compositionPlan: scene.compositionPlan
                    )
                    let after = scene.score.pose(
                        for: actor,
                        at: boundary + 0.0001,
                        canvasAspect: aspect,
                        compositionPlan: scene.compositionPlan
                    )
                    XCTAssertLessThan(simd_distance(before.position, after.position), 0.002)
                    XCTAssertLessThan(abs(before.scale - after.scale), 0.001)
                    XCTAssertLessThan(abs(before.opacity - after.opacity), 0.01)
                }
            }
        }
    }

    func testPathsRemainInsideShortSideBounds() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 11, count: 40))
        for aspect in [0.46, 0.75, 1.0, 1.5, 2.16] {
            for sample in 0..<240 {
                let time = scene.score.duration * Double(sample) / 240
                for actor in scene.actors {
                    XCTAssertTrue(scene.score.pose(
                        for: actor,
                        at: time,
                        canvasAspect: aspect,
                        compositionPlan: scene.compositionPlan
                    ).isInsideSafeBounds)
                }
            }
        }
    }

    func testShaderDerivedFootprintUsesScallopAndFullTrailSupport() {
        let horizontal = DayObjectGeometryFootprint.make(
            halfSize: SIMD2<Double>(0.12, 0.08),
            direction: SIMD2<Double>(1, 0),
            shape: .scallop,
            trailLength: 0.05,
            shortSidePixels: 1_000
        )
        XCTAssertEqual(horizontal.forwardReach, 0.12 * 1.13, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.backwardReach, 0.12 + 0.05, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.lateralReach, 0.08 * 0.70 * 3.5, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.axisAlignedHalfExtents.x, 0.172, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.axisAlignedHalfExtents.y, 0.198, accuracy: 0.000_001)

        let diagonal = DayObjectGeometryFootprint.make(
            halfSize: SIMD2<Double>(0.12, 0.08),
            direction: SIMD2<Double>(1, 1),
            shape: .scallop,
            trailLength: 0.05,
            shortSidePixels: 1_000
        )
        XCTAssertEqual(
            diagonal.axisAlignedHalfExtents.x,
            (0.17 + 0.196) / sqrt(2) + 0.002,
            accuracy: 0.000_001
        )
        XCTAssertEqual(diagonal.axisAlignedHalfExtents.x, diagonal.axisAlignedHalfExtents.y, accuracy: 0.000_001)
    }

    func testDailyPlanTargetsNegativeSpaceAndKeepsRoleAnchorsCoherent() {
        for seed in UInt64(0)..<64 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 40))
            let plan = scene.compositionPlan
            XCTAssertTrue((0.35...0.55).contains(plan.targetNegativeSpaceFraction))
            XCTAssertTrue((0.35...0.55).contains(plan.negativeSpaceRegion.area))

            let focal = plan.anchor(for: .focal)
            let support = plan.anchor(for: .support)
            let bridge = plan.anchor(for: .bridge)
            XCTAssertLessThanOrEqual(simd_distance(focal, support), 0.62)
            XCTAssertLessThanOrEqual(
                simd_distance(bridge, (focal + support) * 0.5),
                0.12
            )
        }
    }

    func testPlannedFootprintsStayInsideBordersAndOutsideUIAndNegativeSpace() {
        for seed in UInt64(0)..<24 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 40))
            for aspect in [0.46, 0.75, 1.0, 4.0 / 3.0, 2.16] {
                for sample in 0..<48 {
                    let time = scene.score.duration * Double(sample) / 48
                    for actor in scene.actors {
                        let pose = scene.score.pose(
                            for: actor,
                            at: time,
                            canvasAspect: aspect,
                            compositionPlan: scene.compositionPlan
                        )
                        XCTAssertTrue(
                            pose.isInsideSafeBounds,
                            "border seed=\(seed) aspect=\(aspect) actor=\(actor.id) sample=\(sample)"
                        )
                        XCTAssertFalse(
                            pose.intersectsUIExclusion,
                            "exclusion seed=\(seed) aspect=\(aspect) actor=\(actor.id) sample=\(sample)"
                        )
                        XCTAssertFalse(
                            pose.intersectsNegativeSpace,
                            "negative seed=\(seed) aspect=\(aspect) actor=\(actor.id) sample=\(sample)"
                        )
                    }
                }
            }
        }
    }

    func testCustomExclusionRegionsAreEnforcedAcrossSupportedAspectsAndSeeds() {
        let regions = [
            DayObjectNormalizedRect(minX: 0.02, minY: 0.03, maxX: 0.34, maxY: 0.27),
            DayObjectNormalizedRect(minX: 0.35, minY: 0.28, maxX: 0.68, maxY: 0.66),
            DayObjectNormalizedRect(minX: 0.66, minY: 0.70, maxX: 0.98, maxY: 0.97),
        ]
        for seed in UInt64(0)..<8 {
            for region in regions {
                var input = fixtureInput(seed: seed, count: 40)
                input = DayObjectSceneInput(
                    dayKey: input.dayKey,
                    identity: input.identity,
                    eventIDs: input.eventIDs,
                    motionEnergy: input.motionEnergy,
                    visualClarity: input.visualClarity,
                    reduceMotion: input.reduceMotion,
                    uiExclusionRegion: region
                )
                let scene = DayObjectScene.make(input: input)
                for aspect in [0.46, 1.0, 4.0 / 3.0, 2.16] {
                    for sample in 0..<24 {
                        let time = scene.score.duration * Double(sample) / 24
                        for actor in scene.actors {
                            let pose = scene.score.pose(
                                for: actor,
                                at: time,
                                canvasAspect: aspect,
                                compositionPlan: scene.compositionPlan
                            )
                            XCTAssertFalse(
                                pose.intersectsUIExclusion,
                                "seed=\(seed) region=\(region) aspect=\(aspect) actor=\(actor.id) sample=\(sample)"
                            )
                            XCTAssertFalse(
                                pose.intersectsNegativeSpace,
                                "seed=\(seed) region=\(region) aspect=\(aspect) actor=\(actor.id) sample=\(sample)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testCustomExclusionRoutesStayContinuousAcrossDenseMidChapterSamples() {
        let regions = [
            DayObjectNormalizedRect(minX: 0.02, minY: 0.03, maxX: 0.34, maxY: 0.27),
            DayObjectNormalizedRect(minX: 0.35, minY: 0.28, maxX: 0.68, maxY: 0.66),
            DayObjectNormalizedRect(minX: 0.66, minY: 0.70, maxX: 0.98, maxY: 0.97),
        ]
        var maximumPositionStep = 0.0
        var maximumDirectionStep = 0.0
        var maximumPositionContext = ""
        var maximumDirectionContext = ""

        for seed in UInt64(0)..<8 {
            for region in regions {
                var input = fixtureInput(seed: seed, count: 40)
                input = DayObjectSceneInput(
                    dayKey: input.dayKey,
                    identity: input.identity,
                    eventIDs: input.eventIDs,
                    motionEnergy: input.motionEnergy,
                    visualClarity: input.visualClarity,
                    reduceMotion: input.reduceMotion,
                    uiExclusionRegion: region
                )
                let scene = DayObjectScene.make(input: input)
                let chapterDuration = scene.score.duration / Double(scene.score.chapters.count)

                for aspect in [0.46, 1.0, 4.0 / 3.0, 2.16] {
                    for actor in scene.actors.prefix(8) {
                        for chapterIndex in scene.score.chapters.indices {
                            var previous: DayObjectPose?
                            for sample in 0...96 {
                                let localProgress = 0.02 + 0.84 * Double(sample) / 96
                                let time = (Double(chapterIndex) + localProgress) * chapterDuration
                                let pose = scene.score.pose(
                                    for: actor,
                                    at: time,
                                    canvasAspect: aspect,
                                    compositionPlan: scene.compositionPlan
                                )
                                XCTAssertTrue(pose.isInsideSafeBounds)
                                XCTAssertFalse(pose.intersectsUIExclusion)
                                XCTAssertFalse(pose.intersectsNegativeSpace)

                                if let previous {
                                    let positionStep = simd_distance(previous.position, pose.position)
                                    let directionStep = simd_distance(previous.tangent, pose.tangent)
                                    let context = "seed=\(seed) region=\(region) aspect=\(aspect) actor=\(actor.id) chapter=\(chapterIndex):\(scene.score.chapters[chapterIndex]) speed=\(actor.speedRatio) sample=\(sample)"
                                    if positionStep > maximumPositionStep {
                                        maximumPositionStep = positionStep
                                        maximumPositionContext = context
                                    }
                                    if directionStep > maximumDirectionStep {
                                        maximumDirectionStep = directionStep
                                        maximumDirectionContext = "\(context) previousPosition=\(previous.position) position=\(pose.position) previousTangent=\(previous.tangent) tangent=\(pose.tangent)"
                                    }
                                }
                                previous = pose
                            }
                        }
                    }
                }
            }
        }

        XCTContext.runActivity(
            named: "maximum position step=\(maximumPositionStep), maximum direction step=\(maximumDirectionStep)"
        ) { _ in }
        XCTAssertLessThanOrEqual(
            maximumPositionStep,
            0.035,
            "mid-chapter route teleport \(maximumPositionStep): \(maximumPositionContext)"
        )
        XCTAssertLessThanOrEqual(
            maximumDirectionStep,
            0.65,
            "mid-chapter direction flip \(maximumDirectionStep): \(maximumDirectionContext)"
        )
    }

    func testAtLeastFiftyFivePercentOfActorsStayVisibleAcrossSampledScores() {
        for seed in UInt64(0)..<48 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 40))
            XCTAssertEqual(scene.actors.count, 40)

            for sample in 0..<96 {
                let time = scene.score.duration * Double(sample) / 96
                let visibleCount = scene.actors.reduce(into: 0) { count, actor in
                    if scene.score.pose(for: actor, at: time, canvasAspect: 1).opacity > 0.001 {
                        count += 1
                    }
                }
                let visibleShare = Double(visibleCount) / Double(scene.actors.count)
                XCTAssertGreaterThanOrEqual(
                    visibleShare,
                    0.55,
                    "seed=\(seed) sample=\(sample) visible=\(visibleCount)"
                )
            }
        }
    }

    func testTangentFollowsActualTravelInBothDirections() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 19, count: 40))
        var sawPositiveX = false
        var sawNegativeX = false

        for sample in 0..<37 {
            let time = scene.score.duration * (Double(sample) + 0.37) / 37
            for actor in scene.actors {
                let before = scene.score.pose(for: actor, at: time - 0.0005, canvasAspect: 1)
                let pose = scene.score.pose(for: actor, at: time, canvasAspect: 1)
                let after = scene.score.pose(for: actor, at: time + 0.0005, canvasAspect: 1)
                let travel = after.position - before.position
                let distance = simd_length(travel)
                guard distance > 0.000_000_1 else { continue }

                let actualDirection = travel / distance
                XCTAssertGreaterThan(simd_dot(pose.tangent, actualDirection), 0.999)
                sawPositiveX = sawPositiveX || travel.x > 0
                sawNegativeX = sawNegativeX || travel.x < 0
            }
        }

        XCTAssertTrue(sawPositiveX)
        XCTAssertTrue(sawNegativeX)
    }

    func testActorUploadPreservesActualTimeDerivativeInBothDirections() throws {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 19, count: 40))
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: false
        )
        let actorsByID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.id, $0) })
        var sawPositiveX = false
        var sawNegativeX = false

        for elapsed in stride(from: 0.37, through: 64.0, by: 2.17) {
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: environment,
                elapsed: elapsed,
                insertions: [:],
                canvasAspect: 1
            )
            let upload = DayObjectsActorUpload(
                actors: frame.actors,
                resolution: SIMD2(128, 128)
            )
            XCTAssertEqual(upload.actors, frame.actors.map(\.gpuActor))

            for (renderActor, gpuActor) in zip(frame.actors, upload.actors) {
                let actor = try XCTUnwrap(actorsByID[renderActor.actorID])
                let before = scene.score.pose(
                    for: actor,
                    at: frame.choreographyTime - 0.0005,
                    canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                )
                let after = scene.score.pose(
                    for: actor,
                    at: frame.choreographyTime + 0.0005,
                    canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                )
                let travel = after.position - before.position
                let distance = simd_length(travel)
                guard distance > 0.000_000_1 else { continue }

                let actualDirection = SIMD2<Float>(
                    Float(travel.x / distance),
                    Float(travel.y / distance)
                )
                XCTAssertGreaterThan(simd_dot(gpuActor.direction, actualDirection), 0.999)
                sawPositiveX = sawPositiveX || actualDirection.x > 0.15
                sawNegativeX = sawNegativeX || actualDirection.x < -0.15
            }
        }

        XCTAssertTrue(sawPositiveX)
        XCTAssertTrue(sawNegativeX)
    }
}
