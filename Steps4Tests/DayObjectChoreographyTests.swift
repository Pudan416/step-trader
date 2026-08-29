import XCTest
import simd
@testable import Steps4

final class DayObjectChoreographyTests: XCTestCase {
    private func fixtureInput(seed: UInt64, count: Int) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "fixture-\(seed)", identity: "tester",
            eventIDs: (0..<count).map { "event-\($0)" },
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false,
            canvasCoverage: .fullCanvas
        )
    }

    private func scene(
        for preset: DayObjectChoreographyPreset,
        count: Int
    ) throws -> DayObjectScene {
        try XCTUnwrap((UInt64(0)..<4_096).lazy.map {
            DayObjectScene.make(input: self.fixtureInput(seed: $0, count: count))
        }.first { $0.motionPlan.preset == preset })
    }

    func testDailyPresetCatalogIsDeterministicAndReachesAllTenPresets() {
        var reached = Set<DayObjectChoreographyPreset>()
        for seed in UInt64(0)..<2_048 {
            let first = DayObjectChoreographyConfiguration.make(seed: seed)
            XCTAssertEqual(first, DayObjectChoreographyConfiguration.make(seed: seed))
            XCTAssertEqual(first.slots.map(\.ordinal), Array(0..<10))
            XCTAssertEqual(Set(first.slots.map(\.ordinal)).count, 10)
            reached.insert(first.preset)
        }
        XCTAssertEqual(reached, Set(DayObjectChoreographyPreset.allCases))
    }

    func testEventSeedAlwaysReturnsTheSameStableSlot() {
        let configuration = DayObjectChoreographyConfiguration.make(seed: 77)
        let ids = (0..<10).map { "event-\($0)" }
        let before = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, configuration.slot(eventID: $0, rootSeed: 77))
        })
        for retained in ids.dropFirst().dropLast() {
            XCTAssertEqual(
                before[retained],
                configuration.slot(eventID: retained, rootSeed: 77)
            )
        }
    }

    func testNegativeNumericLookingEventIDUsesAStableArbitrarySlot() {
        let configuration = DayObjectChoreographyConfiguration.make(seed: 77)
        let first = configuration.slot(eventID: "event--1", rootSeed: 77)

        XCTAssertTrue((0..<10).contains(first.ordinal))
        XCTAssertEqual(first, configuration.slot(eventID: "event--1", rootSeed: 77))
    }

    func testArbitraryEventIDCollisionsKeepDistinctStablePhaseOffsets() throws {
        let configuration = DayObjectChoreographyConfiguration.make(seed: 77)
        var idsBySlot = [Int: [String]]()
        for index in 0..<1_000 {
            let eventID = "uuid-like-\(index)-x"
            let slot = configuration.slot(eventID: eventID, rootSeed: 77)
            idsBySlot[slot.ordinal, default: []].append(eventID)
        }
        let collision = try XCTUnwrap(idsBySlot.values.first { $0.count >= 2 })
        let lhs = configuration.slot(eventID: collision[0], rootSeed: 77)
        let rhs = configuration.slot(eventID: collision[1], rootSeed: 77)

        XCTAssertEqual(lhs.ordinal, rhs.ordinal)
        XCTAssertNotEqual(lhs.phase, rhs.phase)
        XCTAssertEqual(lhs, configuration.slot(eventID: collision[0], rootSeed: 77))
        XCTAssertEqual(rhs, configuration.slot(eventID: collision[1], rootSeed: 77))
    }

    func testExplicitConfigurationProducesDeterministicSlowRoutesAndDepthProfiles() {
        let ids = (0..<10).map { "event-\($0)" }
        for seed in UInt64(0)..<128 {
            let configuration = DayObjectChoreographyConfiguration.make(seed: seed)
            let plan = DayObjectMotionPlan.make(
                configuration: configuration,
                rootSeed: seed,
                eventIDs: ids
            )

            XCTAssertEqual(plan.configuration, configuration)
            XCTAssertEqual(
                plan,
                DayObjectMotionPlan.make(
                    configuration: configuration,
                    rootSeed: seed,
                    eventIDs: ids
                )
            )
            XCTAssertEqual(Set(plan.routes.keys), Set(ids))
            XCTAssertTrue(plan.routes.values.allSatisfy { (90...220).contains($0.period) })
            XCTAssertTrue(plan.depths.values.allSatisfy { (90...220).contains($0.period) })

            switch configuration.depthProfile {
            case .flat:
                XCTAssertTrue(plan.depths.values.allSatisfy {
                    $0.baseDepth == 0.55 && (0...0.04).contains($0.amplitude)
                })
            case .layered:
                XCTAssertTrue(plan.depths.values.allSatisfy {
                    (0.10...0.22).contains($0.amplitude)
                })
            case .migrating:
                XCTAssertTrue(plan.depths.values.allSatisfy {
                    (0.36...0.47).contains($0.amplitude)
                })
            }
        }
    }

    func testCompatibilityWrapperStoresTheConfigurationSelectedFromItsRootSeed() {
        let ids = (0..<10).map { "event-\($0)" }
        for seed in UInt64(0)..<64 {
            let plan = DayObjectMotionPlan.make(rootSeed: seed, eventIDs: ids)
            XCTAssertEqual(plan.configuration, DayObjectChoreographyConfiguration.make(seed: seed))
            XCTAssertEqual(
                plan,
                DayObjectMotionPlan.make(
                    configuration: plan.configuration,
                    rootSeed: seed,
                    eventIDs: ids
                )
            )
        }
    }

    func testFlatPresetRoutesCloseContinuouslyAndUseOneFocusPlane() throws {
        for preset in [DayObjectChoreographyPreset.circularChoir, .radialBloom,
                       .breathingGrid, .waveRibbon] {
            let scene = try scene(for: preset, count: 10)
            XCTAssertTrue(scene.actors.allSatisfy { abs($0.depthSchedule.amplitude) <= 0.04 })
            for actor in scene.actors {
                let start = actor.route.position(at: 0)
                let end = actor.route.position(at: actor.route.period)
                XCTAssertLessThan(simd_distance(start, end), 0.000_001)
            }
        }
    }

    func testDoubleOrbitAndCrossCurrentsUseOpposingGroups() throws {
        for preset in [DayObjectChoreographyPreset.doubleOrbit, .crossCurrents] {
            let scene = try scene(for: preset, count: 10)
            XCTAssertEqual(Set(scene.actors.map { $0.route.direction }), [-1, 1])
        }
    }

    func testApprovedSizesKeepDistributedPresetsVerticallySpread() throws {
        let presets = DayObjectChoreographyPreset.allCases.filter { $0 != .eclipseStack }
        for preset in presets {
            let scene = try scene(for: preset, count: 6)
            var thirds = Set<Int>()
            for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
                for actor in scene.actors {
                    let pose = scene.score.pose(
                        for: actor, at: time, canvasAspect: 1,
                        compositionPlan: scene.compositionPlan
                    )
                    thirds.insert(min(max(Int((0.5 - pose.position.y) * 3), 0), 2))
                }
            }
            if scene.motionPlan.configuration.sizeProfile == .grouped {
                XCTAssertGreaterThanOrEqual(thirds.count, 2, "preset=\(preset)")
            } else {
                XCTAssertEqual(thirds, [0, 1, 2], "preset=\(preset)")
            }
        }
    }

    func testDepthFieldTraversesFarMiddleAndNearPlanes() throws {
        let scene = try scene(for: .depthField, count: 10)
        let depths = stride(from: 0.0, through: scene.score.duration, by: 2.0)
            .flatMap { time in
                scene.actors.map {
                    scene.score.pose(for: $0, at: time, canvasAspect: 1,
                                     compositionPlan: scene.compositionPlan).depth
                }
            }
        XCTAssertLessThan(depths.min()!, 0.20)
        XCTAssertGreaterThan(depths.max()!, 0.85)
        XCTAssertTrue(depths.contains { (0.48...0.62).contains($0) })
    }

    func testCircularChoirKeepsRingRadiusVarianceBelowFourHundredths() throws {
        let scene = try scene(for: .circularChoir, count: 10)
        let times = Array(stride(from: 0.0, through: scene.score.duration, by: 12.0))
        for actor in scene.actors {
            let routeCenter = actor.route.controlPoints.reduce(.zero, +)
                / Double(actor.route.controlPoints.count)
            let radii = times.map { time -> Double in
                let position = scene.score.pose(
                    for: actor, at: time, canvasAspect: 1
                ).position
                let localPosition = actor.route.position(at: time)
                let center = position - localPosition * 0.45 + routeCenter * 0.45
                return simd_distance(position, center)
            }
            for (time, radius) in zip(times, radii) {
                XCTAssertLessThan(
                    (radii.max() ?? 0) - (radii.min() ?? 0),
                    0.04,
                    "preset=\(scene.motionPlan.preset) time=\(time) radius=\(radius)"
                )
            }
        }
    }

    func testBreathingGridPreservesStaggeredRowAndColumnOrder() throws {
        let scene = try scene(for: .breathingGrid, count: 6)
        let expectedSectors = [0, 1, 2, 3, 4, 6]
        for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
            let sectors = scene.actors.map { actor -> Int in
                let position = scene.score.pose(
                    for: actor, at: time, canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                ).position
                let column = min(max(Int((position.x + 0.5) * 3), 0), 2)
                let row = min(max(Int((0.5 - position.y) * 3), 0), 2)
                return row * 3 + column
            }
            XCTAssertEqual(
                sectors, expectedSectors,
                "preset=\(scene.motionPlan.preset) time=\(time) sectors=\(sectors)"
            )
        }
    }

    func testWaveRibbonPreservesActorOrderAlongTheRibbon() throws {
        let scene = try scene(for: .waveRibbon, count: 6)
        for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
            let positions = scene.actors.map {
                scene.score.pose(
                    for: $0, at: time, canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                ).position
            }
            let columnRanges = stride(from: 0, to: positions.count, by: 2).map {
                let column = positions[$0..<min($0 + 2, positions.count)].map(\.x)
                return (minimum: column.min()!, maximum: column.max()!)
            }
            for pair in zip(columnRanges, columnRanges.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    pair.0.maximum, pair.1.minimum,
                    "preset=\(scene.motionPlan.preset) time=\(time) positions=\(positions)"
                )
            }
        }
    }

    func testSpiralProcessionPreservesAngularActorOrder() throws {
        let scene = try scene(for: .spiralProcession, count: 6)
        for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
            let positions = scene.actors.map {
                scene.score.pose(
                    for: $0, at: time, canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                ).position
            }
            let center = positions.reduce(.zero, +) / Double(positions.count)
            let angles = positions.map { atan2(($0 - center).y, ($0 - center).x) }
            let clockwiseSteps = zip(angles, angles.dropFirst()).map { lhs, rhs in
                let raw = lhs - rhs
                return raw >= 0 ? raw : raw + 2 * Double.pi
            }
            XCTAssertTrue(
                clockwiseSteps.allSatisfy { $0 > 0 && $0 < .pi },
                "preset=\(scene.motionPlan.preset) time=\(time) angles=\(angles)"
            )
        }
    }

    func testEclipseStackOverlapsThenSeparates() throws {
        let scene = try scene(for: .eclipseStack, count: 10)
        let pairs = stride(from: 0, to: scene.actors.count, by: 2).map {
            Array(scene.actors[$0..<min($0 + 2, scene.actors.count)])
        }.filter { $0.count == 2 }
        var overlapTimes = Array<Double?>(repeating: nil, count: pairs.count)
        var laterSeparationTimes = Array<Double?>(repeating: nil, count: pairs.count)

        for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
            for (index, pair) in pairs.enumerated() {
                let poses = pair.map {
                    scene.score.pose(
                        for: $0, at: time, canvasAspect: 1,
                        compositionPlan: scene.compositionPlan
                    )
                }
                let distance = simd_distance(poses[0].position, poses[1].position)
                let reach = poses[0].bodyRadius + poses[1].bodyRadius
                if overlapTimes[index] == nil, distance < reach {
                    overlapTimes[index] = time
                } else if overlapTimes[index] != nil, distance > reach {
                    laterSeparationTimes[index] = time
                }
                XCTAssertTrue(
                    distance.isFinite,
                    "preset=\(scene.motionPlan.preset) time=\(time) distance=\(distance)"
                )
            }
        }

        XCTAssertTrue(
            zip(overlapTimes, laterSeparationTimes).contains { $0 != nil && $1 != nil },
            "preset=\(scene.motionPlan.preset) overlaps=\(overlapTimes) "
                + "separations=\(laterSeparationTimes)"
        )
    }

    func testCameraFocusIsSharpestAtMidDepthAndSoftAtBothExtremes() throws {
        let scene = try scene(for: .depthField, count: 10)
        let actor = try XCTUnwrap(scene.actors.first)
        let samples = stride(from: 0.0, through: actor.depthSchedule.period, by: 0.1).map {
            scene.score.pose(
                for: actor,
                at: $0,
                canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
        }
        let far = try XCTUnwrap(samples.min { $0.depth < $1.depth })
        let near = try XCTUnwrap(samples.max { $0.depth < $1.depth })
        let middle = try XCTUnwrap(samples.min {
            abs($0.depth - 0.55) < abs($1.depth - 0.55)
        })

        XCTAssertGreaterThan(far.localDepthSoftness, middle.localDepthSoftness)
        XCTAssertGreaterThan(near.localDepthSoftness, middle.localDepthSoftness)
        XCTAssertGreaterThan(near.scale, middle.scale)
        XCTAssertGreaterThan(middle.scale, far.scale)
    }

    func testUniformDaysKeepMediumActorsWithinFivePercent() throws {
        let scene = try scene(for: .circularChoir, count: 10)
        let scales = scene.actors.map {
            scene.score.pose(for: $0, at: 0, canvasAspect: 1,
                             compositionPlan: scene.compositionPlan).scale
        }
        XCTAssertLessThanOrEqual(scales.max()! / scales.min()!, 1.05)
        XCTAssertTrue(scales.allSatisfy { (0.22...0.38).contains($0) })
    }

    func testDepthFieldUsesVeryDifferentSizesAndBlursNearestActorMost() throws {
        let scene = try scene(for: .depthField, count: 10)
        let poses = scene.actors.map {
            scene.score.pose(for: $0, at: 0, canvasAspect: 1,
                             compositionPlan: scene.compositionPlan)
        }
        XCTAssertGreaterThan(poses.map(\.scale).max()! / poses.map(\.scale).min()!, 3.0)
        let nearest = poses.max { $0.depth < $1.depth }!
        let middle = poses.min { abs($0.depth - 0.55) < abs($1.depth - 0.55) }!
        XCTAssertGreaterThan(nearest.localDepthSoftness, middle.localDepthSoftness * 2)
    }

    func testActorsStoreTheDeterministicSlotUsedByTheirPreset() throws {
        let scene = try scene(for: .doubleOrbit, count: 10)
        for actor in scene.actors {
            XCTAssertEqual(
                actor.choreographySlot,
                scene.motionPlan.configuration.slot(
                    eventID: actor.eventID,
                    rootSeed: scene.rootSeed
                )
            )
        }
    }

    func testFlatProfilesKeepOpacityIndependentOfDepth() throws {
        let scene = try scene(for: .circularChoir, count: 10)
        let actor = try XCTUnwrap(scene.actors.first)
        let opacities = stride(from: 0.0, through: actor.depthSchedule.period, by: 1.0).map {
            scene.score.pose(
                for: actor, at: $0, canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            ).opacity
        }
        XCTAssertTrue(opacities.allSatisfy { (0.86...1.0).contains($0) })
        XCTAssertEqual(opacities.max()!, opacities.min()!, accuracy: 0.000_001)
    }

    func testGroupedDaysUseRelatedApprovedSizes() throws {
        let scene = try scene(for: .doubleOrbit, count: 10)
        let scales = scene.actors.map {
            scene.score.pose(
                for: $0, at: 0, canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            ).scale
        }
        XCTAssertTrue(scales.allSatisfy { (0.15...0.48).contains($0) })
        XCTAssertLessThan(scales.min()!, 0.22)
        XCTAssertGreaterThan(scales.max()!, 0.42)
        XCTAssertGreaterThan(scales.max()! / scales.min()!, 2.0)
    }

    func testDepthBreathingRemainsContinuousAtItsLoopBoundary() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 33, count: 10))
        for actor in scene.actors {
            let period = actor.depthSchedule.period
            let before = scene.score.pose(
                for: actor,
                at: period - 0.001,
                canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
            let after = scene.score.pose(
                for: actor,
                at: 0.001,
                canvasAspect: 1,
                compositionPlan: scene.compositionPlan
            )
            XCTAssertLessThan(abs(before.scale - after.scale), 0.003)
            XCTAssertLessThan(
                abs(before.localDepthSoftness - after.localDepthSoftness),
                0.003
            )
        }
    }

    func testActorGeometryUsesTheInheritedDailyElongation() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 41, count: 10))
        for actor in scene.actors {
            XCTAssertEqual(
                DayObjectActorGeometry.aspectRatio(for: actor),
                min(max(actor.appearance.elongation, 0.95), 1.05),
                accuracy: 0.000_001
            )
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

    func testFullCanvasPlanDoesNotReserveAnUpperOrLowerStrip() {
        for seed in UInt64(0)..<64 {
            let plan = DayObjectScene.make(input: fixtureInput(seed: seed, count: 10)).compositionPlan
            XCTAssertEqual(plan.targetNegativeSpaceFraction, 0)
            XCTAssertEqual(plan.negativeSpaceRegion.area, 0)
            XCTAssertTrue(plan.usesFullCanvas)
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
                        let allowsIntentionalCrop = [
                            DayObjectChoreographyPreset.depthField,
                            .eclipseStack,
                        ].contains(scene.motionPlan.preset)
                        XCTAssertTrue(pose.isInsideSafeBounds || allowsIntentionalCrop)
                        if !allowsIntentionalCrop {
                            XCTAssertEqual(pose.intentionalCropFraction, 0, accuracy: 0.000_001)
                        }
                        if allowsIntentionalCrop {
                            XCTAssertLessThanOrEqual(pose.intentionalCropFraction, 1)
                        }
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
        var maximumTangentContext = ""

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
                                let tangentStep = simd_distance(previous.tangent, pose.tangent)
                                if tangentStep > maximumTangentStep {
                                    maximumTangentStep = tangentStep
                                    maximumTangentContext = "preset=\(scene.motionPlan.preset) "
                                        + "seed=\(seed) actor=\(actor.id) sample=\(sample)"
                                }
                            }
                            previous = pose
                        }
                    }
                }
            }
        }

        XCTAssertLessThanOrEqual(maximumPositionStep, 0.035)
        XCTAssertLessThanOrEqual(
            maximumTangentStep, 0.65,
            "\(maximumTangentContext) tangentStep=\(maximumTangentStep)"
        )
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
