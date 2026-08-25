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

    func testDailyMotionPlansUseSlowWideStableRoutesAndBothDirections() {
        var reachedFamilies = Set<DayObjectChoreographyFamily>()

        for seed in UInt64(0)..<64 {
            for count in [1, 4, 7, 10] {
                let ids = (0..<count).map { "event-\($0)" }
                let plan = DayObjectMotionPlan.make(rootSeed: seed, eventIDs: ids)
                XCTAssertEqual(plan, DayObjectMotionPlan.make(rootSeed: seed, eventIDs: ids))
                XCTAssertEqual(Set(plan.routes.keys), Set(ids))
                reachedFamilies.insert(plan.family)

                for route in plan.routes.values {
                    XCTAssertTrue((4...6).contains(route.controlPoints.count))
                    XCTAssertTrue((45...120).contains(route.period))
                    XCTAssertTrue(route.direction == -1 || route.direction == 1)
                    XCTAssertTrue((0..<9).contains(route.sector))
                    let xs = route.controlPoints.map(\.x)
                    let ys = route.controlPoints.map(\.y)
                    let xExtent = (xs.max() ?? 0) - (xs.min() ?? 0)
                    let yExtent = (ys.max() ?? 0) - (ys.min() ?? 0)
                    XCTAssertTrue((0.20...0.70).contains(max(xExtent, yExtent)))
                }

                if count == 10 {
                    XCTAssertEqual(Set(plan.routes.values.map(\.direction)), [-1, 1])
                }
            }
        }

        XCTAssertEqual(reachedFamilies, Set(DayObjectChoreographyFamily.allCases))
    }

    func testEightToTenOrbsOccupyAtLeastFiveCanvasSectors() {
        for seed in UInt64(0)..<64 {
            for count in 8...10 {
                let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: count))
                for elapsed in [0.0, 19.0, 43.0] {
                    let sectors = Set(scene.actors.map { actor in
                        let pose = scene.score.pose(
                            for: actor,
                            at: elapsed,
                            canvasAspect: 1,
                            compositionPlan: scene.compositionPlan
                        )
                        let column = min(max(Int((pose.position.x + 0.5) * 3), 0), 2)
                        let row = min(max(Int((0.5 - pose.position.y) * 3), 0), 2)
                        return row * 3 + column
                    })
                    guard sectors.count >= 5 else {
                        XCTFail(
                            "seed=\(seed) count=\(count) elapsed=\(elapsed) sectors=\(sectors) "
                                + "poses=\(scene.actors.map { scene.score.pose(for: $0, at: elapsed, canvasAspect: 1, compositionPlan: scene.compositionPlan).position })"
                        )
                        return
                    }
                }
            }
        }
    }

    func testArbitraryEventIDsStillReceiveDistributedRoutesAndBothDirections() {
        var idsByPreferredSector = [Int: [String]]()
        for index in 0..<1_000 {
            let eventID = "uuid-like-\(index)-x"
            let route = DayObjectMotionPlan.make(
                rootSeed: 44,
                eventIDs: [eventID]
            ).routes[eventID]!
            idsByPreferredSector[route.sector, default: []].append(eventID)
        }
        let eventIDs = Array(idsByPreferredSector.values.first { $0.count >= 10 }!.prefix(10))
        let plan = DayObjectMotionPlan.make(rootSeed: 44, eventIDs: eventIDs)

        XCTAssertGreaterThanOrEqual(Set(plan.routes.values.map(\.sector)).count, 5)
        XCTAssertEqual(Set(plan.routes.values.map(\.direction)), [-1, 1])
    }

    func testRepresentativeSceneContainsBothTravelDirections() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 19, count: 10))
        XCTAssertEqual(Set(scene.actors.map { scene.score.travelDirection(for: $0) }), [-1, 1])
    }

    func testSoftEncounterChannelsAreBoundedAndUseApprovedWindows() {
        var softRoots = 0
        for seed in UInt64(0)..<128 {
            let plan = DayObjectMotionPlan.make(
                rootSeed: seed,
                eventIDs: (0..<10).map { "event-\($0)" }
            )
            guard plan.family == .softEncounters else { continue }
            softRoots += 1
            let channelCounts = Dictionary(grouping: plan.encounters.values, by: \.channel)
                .mapValues(\.count)
            XCTAssertLessThanOrEqual(channelCounts.values.max() ?? 0, 4)
            XCTAssertTrue(plan.encounters.values.allSatisfy {
                (0.05...0.18).contains($0.durationFraction)
                    && (0.15...0.40).contains($0.overlapFraction)
            })
        }
        XCTAssertGreaterThan(softRoots, 0)
    }

    func testSoftEncountersOverlapBrieflyThenSeparate() throws {
        let seed = try XCTUnwrap((UInt64(0)..<128).first {
            DayObjectMotionPlan.make(rootSeed: $0, eventIDs: ["event-0"]).family
                == .softEncounters
        })
        let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10))
        var sawApprovedOverlap = false
        var sawSeparatedFrame = false

        for sample in 0...360 {
            let time = Double(sample) * 0.5
            let poses = scene.actors.map {
                scene.score.pose(
                    for: $0, at: time, canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                )
            }
            var actorsInsideOneDiameter = 0
            for lhs in poses.indices {
                for rhs in poses.indices where rhs > lhs {
                    let reach = poses[lhs].bodyRadius + poses[rhs].bodyRadius
                    let distance = simd_distance(poses[lhs].position, poses[rhs].position)
                    let overlap = max(0, 1 - distance / max(reach, 0.000_001))
                    sawApprovedOverlap = sawApprovedOverlap || (0.15...0.40).contains(overlap)
                    sawSeparatedFrame = sawSeparatedFrame || distance > reach * 1.5
                    if distance <= max(poses[lhs].bodyRadius, poses[rhs].bodyRadius) {
                        actorsInsideOneDiameter += 1
                    }
                }
            }
            XCTAssertLessThan(actorsInsideOneDiameter, poses.count - 1)
        }

        XCTAssertTrue(sawApprovedOverlap)
        XCTAssertTrue(sawSeparatedFrame)
    }

    func testSoftEncounterChannelConvergesOnItsDeclaredSharedOverlap() throws {
        let scene = try XCTUnwrap((UInt64(0)..<256).lazy.map {
            DayObjectScene.make(input: self.fixtureInput(seed: $0, count: 10))
        }.first { scene in
            scene.motionPlan.family == .softEncounters
                && Dictionary(grouping: scene.actors, by: { $0.encounter.channel })
                    .values.contains { $0.count >= 2 }
        })
        let group = try XCTUnwrap(
            Dictionary(grouping: scene.actors, by: { $0.encounter.channel })
                .values.first { $0.count >= 2 }
        )
        let orderedGroup = group.sorted {
            $0.encounter.memberOrdinal < $1.encounter.memberOrdinal
        }
        let lhsActor = orderedGroup[0]
        let rhsActor = orderedGroup[1]
        let encounter = lhsActor.encounter
        let midpoint = (encounter.phase + encounter.durationFraction * 0.5) * 90
        let lhs = scene.score.pose(
            for: lhsActor, at: midpoint, canvasAspect: 1,
            compositionPlan: scene.compositionPlan
        )
        let rhs = scene.score.pose(
            for: rhsActor, at: midpoint, canvasAspect: 1,
            compositionPlan: scene.compositionPlan
        )
        let overlap = max(
            0,
            1 - simd_distance(lhs.position, rhs.position)
                / max(lhs.bodyRadius + rhs.bodyRadius, 0.000_001)
        )

        XCTAssertEqual(lhsActor.encounter.phase, rhsActor.encounter.phase)
        XCTAssertEqual(lhsActor.encounter.overlapFraction, rhsActor.encounter.overlapFraction)
        XCTAssertEqual(overlap, encounter.overlapFraction, accuracy: 0.10)
    }

    func testDepthSchedulesAreContinuousAndMapNearMidFarAppearance() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 27, count: 10))
        XCTAssertTrue(scene.actors.allSatisfy { (60...140).contains($0.depthSchedule.period) })
        let poses = scene.actors.map {
            scene.score.pose(
                for: $0, at: 0, canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
        }
        XCTAssertLessThan(poses.map(\.depth).min() ?? 1, 0.33)
        XCTAssertGreaterThan(poses.map(\.depth).max() ?? 0, 0.66)
        XCTAssertTrue(poses.contains { (0.33...0.66).contains($0.depth) })

        let far = poses.min { $0.depth < $1.depth }!
        let near = poses.max { $0.depth < $1.depth }!
        XCTAssertGreaterThan(near.scale, far.scale)
        XCTAssertGreaterThan(far.localDepthSoftness, near.localDepthSoftness)
        XCTAssertGreaterThan(near.opacity, far.opacity)

        for actor in scene.actors {
            let before = scene.score.pose(
                for: actor, at: 31.999, canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
            let after = scene.score.pose(
                for: actor, at: 32.001, canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
            XCTAssertLessThan(abs(after.depth - before.depth), 0.001)
            XCTAssertLessThan(abs(after.materialPhase - before.materialPhase), 0.001)
        }
    }

    func testEveryRouteIsContinuousAcrossItsOwnLoop() {
        for seed in UInt64(0)..<32 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10))
            for actor in scene.actors {
                let before = actor.route.position(at: actor.route.period - 0.0001)
                let after = actor.route.position(at: 0.0001)
                let beforeTangent = actor.route.position(at: actor.route.period)
                    - actor.route.position(at: actor.route.period - 0.001)
                let afterTangent = actor.route.position(at: 0.001)
                    - actor.route.position(at: 0)
                XCTAssertLessThan(simd_distance(before, after), 0.002)
                XCTAssertGreaterThan(simd_dot(beforeTangent, afterTangent), 0)
            }
        }
    }

    func testShaderDerivedFootprintUsesSoftBlobAndFullTrailSupport() {
        let horizontal = DayObjectGeometryFootprint.make(
            halfSize: SIMD2<Double>(0.12, 0.08), direction: SIMD2<Double>(1, 0),
            shape: .softBlob, trailLength: 0.05, shortSidePixels: 1_000
        )
        XCTAssertEqual(horizontal.forwardReach, 0.12 * (1.06 + 0.18), accuracy: 0.000_001)
        XCTAssertEqual(horizontal.backwardReach, 0.12 + 0.05, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.lateralReach, 0.08 * 1.06 + 0.12 * 0.18, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.axisAlignedHalfExtents.x, 0.172, accuracy: 0.000_001)
        XCTAssertEqual(horizontal.axisAlignedHalfExtents.y, 0.1084, accuracy: 0.000_001)
    }

    func testDailyPlanKeepsApprovedNegativeSpace() {
        for seed in UInt64(0)..<64 {
            let plan = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10)).compositionPlan
            XCTAssertTrue((0.35...0.55).contains(plan.targetNegativeSpaceFraction))
            XCTAssertTrue((0.35...0.55).contains(plan.negativeSpaceRegion.area))
        }
    }

    func testPlannedFootprintsStayInsideBordersAndOutsideReservedRegions() {
        for seed in UInt64(0)..<24 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10))
            for aspect in [0.46, 0.75, 1.0, 4.0 / 3.0, 2.16] {
                for sample in 0..<48 {
                    for actor in scene.actors {
                        let time = actor.route.period * Double(sample) / 48
                        let pose = scene.score.pose(
                            for: actor, at: time, canvasAspect: aspect,
                            compositionPlan: scene.compositionPlan
                        )
                        XCTAssertTrue(pose.isInsideSafeBounds)
                        XCTAssertFalse(pose.intersectsUIExclusion)
                        XCTAssertFalse(pose.intersectsNegativeSpace)
                    }
                }
            }
        }
    }

    func testCustomExclusionRoutesStaySafeAndContinuous() {
        let regions = [
            DayObjectNormalizedRect(minX: 0.02, minY: 0.03, maxX: 0.34, maxY: 0.27),
            DayObjectNormalizedRect(minX: 0.35, minY: 0.28, maxX: 0.68, maxY: 0.66),
            DayObjectNormalizedRect(minX: 0.66, minY: 0.70, maxX: 0.98, maxY: 0.97),
        ]
        var maximumPositionStep = 0.0
        var maximumTangentStep = 0.0

        for seed in UInt64(0)..<8 {
            for region in regions {
                let base = fixtureInput(seed: seed, count: 10)
                let input = DayObjectSceneInput(
                    dayKey: base.dayKey, identity: base.identity, eventIDs: base.eventIDs,
                    motionEnergy: base.motionEnergy, visualClarity: base.visualClarity,
                    reduceMotion: base.reduceMotion, uiExclusionRegion: region
                )
                let scene = DayObjectScene.make(input: input)
                for aspect in [0.46, 1.0, 4.0 / 3.0, 2.16] {
                    for actor in scene.actors.prefix(8) {
                        var previous: DayObjectPose?
                        for sample in 0...192 {
                            let time = actor.route.period * Double(sample) / 192
                            let pose = scene.score.pose(
                                for: actor, at: time, canvasAspect: aspect,
                                compositionPlan: scene.compositionPlan
                            )
                            guard pose.isInsideSafeBounds,
                                  !pose.intersectsUIExclusion,
                                  !pose.intersectsNegativeSpace else {
                                XCTFail(
                                    "unsafe seed=\(seed) region=\(region) aspect=\(aspect) "
                                        + "actor=\(actor.id) sample=\(sample) pose=\(pose)"
                                )
                                return
                            }
                            if let previous {
                                maximumPositionStep = max(
                                    maximumPositionStep,
                                    simd_distance(previous.position, pose.position)
                                )
                                maximumTangentStep = max(
                                    maximumTangentStep,
                                    simd_distance(previous.tangent, pose.tangent)
                                )
                            }
                            previous = pose
                        }
                    }
                }
            }
        }

        XCTAssertLessThanOrEqual(maximumPositionStep, 0.035)
        XCTAssertLessThanOrEqual(maximumTangentStep, 0.65)
    }

    func testAtLeastFiftyFivePercentOfActorsRemainVisible() {
        for seed in UInt64(0)..<48 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10))
            for sample in 0..<96 {
                let visible = scene.actors.filter { actor in
                    let time = actor.route.period * Double(sample) / 96
                    return scene.score.pose(for: actor, at: time, canvasAspect: 1).opacity > 0.001
                }
                XCTAssertGreaterThanOrEqual(Double(visible.count) / 10, 0.55)
            }
        }
    }

    func testTangentAndGPUUploadFollowActualTravelInBothDirections() throws {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 19, count: 10))
        let environment = DayObjectEnvironment(
            motionEnergy: 1, visualClarity: 1, reduceMotion: false
        )
        let actorsByID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.id, $0) })
        var sawPositiveX = false
        var sawNegativeX = false

        for elapsed in stride(from: 0.37, through: 64.0, by: 2.17) {
            let frame = DayObjectRenderFrame.make(
                scene: scene, environment: environment, elapsed: elapsed,
                insertions: [:], canvasAspect: 1
            )
            let upload = DayObjectsActorUpload(
                actors: frame.actors, resolution: SIMD2(128, 128)
            )
            for (renderActor, gpuActor) in zip(frame.actors, upload.actors) {
                let actor = try XCTUnwrap(actorsByID[renderActor.actorID])
                let before = scene.score.pose(
                    for: actor, at: frame.choreographyTime - 0.0005,
                    canvasAspect: 1, compositionPlan: scene.compositionPlan
                )
                let after = scene.score.pose(
                    for: actor, at: frame.choreographyTime + 0.0005,
                    canvasAspect: 1, compositionPlan: scene.compositionPlan
                )
                let travel = after.position - before.position
                let distance = simd_length(travel)
                guard distance > 0.000_000_1 else { continue }
                let actual = SIMD2<Float>(Float(travel.x / distance), Float(travel.y / distance))
                XCTAssertGreaterThan(simd_dot(gpuActor.direction, actual), 0.999)
                sawPositiveX = sawPositiveX || actual.x > 0.15
                sawNegativeX = sawNegativeX || actual.x < -0.15
            }
        }

        XCTAssertTrue(sawPositiveX)
        XCTAssertTrue(sawNegativeX)
    }
}
