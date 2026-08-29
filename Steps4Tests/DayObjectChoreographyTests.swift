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

    private func scenes(
        for preset: DayObjectChoreographyPreset,
        count: Int,
        sampleCount: Int = 3
    ) throws -> [DayObjectScene] {
        var result = [DayObjectScene]()
        for seed in UInt64(0)..<8_192 where result.count < sampleCount {
            let candidate = DayObjectScene.make(input: fixtureInput(seed: seed, count: count))
            if candidate.motionPlan.preset == preset {
                result.append(candidate)
            }
        }
        XCTAssertEqual(result.count, sampleCount, "preset=\(preset)")
        return result
    }

    private func pose(
        _ actor: DayObjectActor,
        in scene: DayObjectScene,
        at time: Double
    ) -> DayObjectPose {
        scene.score.pose(
            for: actor,
            at: time,
            canvasAspect: 1,
            compositionPlan: scene.compositionPlan
        )
    }

    private func canvasPoint(_ normalized: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(normalized.x - 0.5, 0.5 - normalized.y)
    }

    private func rotated(
        _ point: SIMD2<Double>,
        by angle: Double
    ) -> SIMD2<Double> {
        let cosine = cos(angle)
        let sine = sin(angle)
        return SIMD2(
            point.x * cosine - point.y * sine,
            point.x * sine + point.y * cosine
        )
    }

    private func wrappedPositiveAngle(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        return remainder >= 0 ? remainder : remainder + 2 * Double.pi
    }

    private func levelCount(_ values: [Double], tolerance: Double) -> Int {
        values.sorted().reduce(into: [Double]()) { levels, value in
            if levels.last.map({ abs($0 - value) > tolerance }) ?? true {
                levels.append(value)
            }
        }.count
    }

    func testPresetFramesKeepEveryActorFiniteWithinCapacity() throws {
        for preset in [DayObjectChoreographyPreset.circularChoir,
                       .eclipseStack, .depthField] {
            for count in [1, 5, 10] {
                let scene = try scene(for: preset, count: count)
                let frame = DayObjectRenderFrame.make(
                    scene: scene,
                    environment: .init(motionEnergy: 0.55,
                                       visualClarity: 0.55,
                                       reduceMotion: false),
                    elapsed: 42,
                    insertions: [:]
                )
                XCTAssertEqual(frame.actors.count, scene.actors.count)
                XCTAssertLessThanOrEqual(frame.actors.count, DayObjectScene.maxActors)
                XCTAssertTrue(frame.actors.allSatisfy {
                    $0.halfSize.x.isFinite && $0.halfSize.y.isFinite
                        && $0.opacity.isFinite && $0.depth.isFinite
                        && $0.halfSize.x >= 0 && $0.halfSize.y >= 0
                })
            }
        }
    }

    func testMotionEnergyChangesTimeButNotDailyConfiguration() throws {
        let scene = try scene(for: .waveRibbon, count: 10)
        let slow = DayObjectRenderFrame.make(
            scene: scene,
            environment: .init(motionEnergy: 0, visualClarity: 1, reduceMotion: false),
            elapsed: 30,
            insertions: [:]
        )
        let fast = DayObjectRenderFrame.make(
            scene: scene,
            environment: .init(motionEnergy: 1, visualClarity: 1, reduceMotion: false),
            elapsed: 30,
            insertions: [:]
        )
        XCTAssertLessThan(slow.choreographyTime, fast.choreographyTime)
        let rebuilt = DayObjectScene.make(input: scene.input)
        XCTAssertEqual(scene.motionPlan.preset, .waveRibbon)
        XCTAssertEqual(scene.actors.map(\.choreographySlot),
                       rebuilt.actors.map(\.choreographySlot))
    }

    func testScoreIdentityComesFromTheSelectedPresetConfiguration() throws {
        for preset in DayObjectChoreographyPreset.allCases {
            for scene in try scenes(for: preset, count: 10, sampleCount: 2) {
                XCTAssertEqual(scene.score.configuration, scene.choreographyConfiguration)
                XCTAssertEqual(scene.score.preset, scene.motionPlan.preset)
            }
        }
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

    func testMaterialCompatibilityWeightsMatchTheApprovedMatrixExactly() throws {
        let preferred: [DayObjectMaterialFamily: Set<DayObjectChoreographyPreset>] = [
            .outline: [.circularChoir, .doubleOrbit, .waveRibbon],
            .glass: [.eclipseStack, .constellation, .depthField],
            .luminous: [.radialBloom, .spiralProcession, .depthField],
            .halo: [.radialBloom, .spiralProcession, .depthField],
            .solid: [.breathingGrid, .crossCurrents, .circularChoir],
            .sphere: [.breathingGrid, .crossCurrents, .circularChoir],
            .mist: [.constellation, .eclipseStack, .depthField],
            .gradient: Set(DayObjectChoreographyPreset.allCases),
            .counterform: Set(DayObjectChoreographyPreset.allCases),
        ]

        for preset in DayObjectChoreographyPreset.allCases {
            let configuration = try XCTUnwrap((UInt64(0)..<4_096).lazy
                .map { DayObjectChoreographyConfiguration.make(seed: $0) }
                .first { $0.preset == preset })
            for family in DayObjectMaterialFamily.allCases {
                XCTAssertEqual(
                    configuration.materialWeight(for: family),
                    preferred[family]!.contains(preset) ? 3 : 1,
                    "preset=\(preset) family=\(family)"
                )
            }
        }
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

    func testFlatPresetRoutesCloseContinuouslyAndUseOneFocusPlane() throws {
        let presets: [DayObjectChoreographyPreset] = [
            .circularChoir, .doubleOrbit, .radialBloom,
            .breathingGrid, .waveRibbon, .spiralProcession,
        ]
        for preset in presets {
            for scene in try scenes(for: preset, count: 10) {
                for actor in scene.actors {
                    XCTAssertLessThanOrEqual(actor.depthSchedule.amplitude, 0.04)
                    XCTAssertEqual(actor.depthSchedule.baseDepth, 0.55, accuracy: 0.000_001)
                    XCTAssertLessThan(
                        simd_distance(
                            actor.route.position(at: 0),
                            actor.route.position(at: actor.route.period)
                        ),
                        0.000_001
                    )
                }
            }
        }
    }

    func testCircularChoirRotatesOneSharedFormationAroundOneCenter() throws {
        for scene in try scenes(for: .circularChoir, count: 10) {
            let expectedCenter = canvasPoint(scene.choreographyConfiguration.center)
            XCTAssertEqual(Set(scene.actors.map { $0.choreographySlot.group }), [0])
            XCTAssertEqual(Set(scene.actors.map { $0.route.direction }), [1])
            XCTAssertLessThan(
                (scene.actors.map { $0.route.period }.max() ?? 0)
                    - (scene.actors.map { $0.route.period }.min() ?? 0),
                0.000_001
            )

            let times = [0.0, scene.score.duration * 0.125, scene.score.duration * 0.25]
            let poseSets = times.map { time in scene.actors.map { pose($0, in: scene, at: time) } }
            for (time, poses) in zip(times, poseSets) {
                let centroid = poses.map(\.position).reduce(.zero, +) / Double(poses.count)
                XCTAssertLessThan(
                    simd_distance(centroid, expectedCenter), 0.025,
                    "seed=\(scene.rootSeed) time=\(time) centroid=\(centroid)"
                )
                XCTAssertTrue(poses.allSatisfy {
                    simd_distance($0.position, expectedCenter) > 0.16
                })
            }

            let angularAdvances = zip(poseSets[0], poseSets[1]).map { start, end in
                wrappedPositiveAngle(
                    atan2((end.position - expectedCenter).y, (end.position - expectedCenter).x)
                        - atan2((start.position - expectedCenter).y, (start.position - expectedCenter).x)
                )
            }
            XCTAssertLessThan(
                (angularAdvances.max() ?? 0) - (angularAdvances.min() ?? 0),
                0.16,
                "seed=\(scene.rootSeed) advances=\(angularAdvances)"
            )
        }
    }

    func testDoubleOrbitUsesTwoCommonOpposingRingsWithRelatedMediumSizes() throws {
        for scene in try scenes(for: .doubleOrbit, count: 10) {
            let groups = Dictionary(grouping: scene.actors) { $0.choreographySlot.group }
            XCTAssertEqual(Set(groups.keys), [0, 1])
            XCTAssertEqual(Set(groups.values.flatMap { $0.map(\.route.direction) }), [-1, 1])
            let expectedCenter = canvasPoint(scene.choreographyConfiguration.center)

            for time in [0.0, scene.score.duration * 0.19, scene.score.duration * 0.43] {
                var ringRadii = [Double]()
                for group in [0, 1] {
                    let actors = try XCTUnwrap(groups[group])
                    let poses = actors.map { pose($0, in: scene, at: time) }
                    let centroid = poses.map(\.position).reduce(.zero, +) / Double(poses.count)
                    XCTAssertLessThan(simd_distance(centroid, expectedCenter), 0.035)
                    let radii = poses.map { simd_distance($0.position, expectedCenter) }
                    XCTAssertLessThan((radii.max() ?? 0) - (radii.min() ?? 0), 0.04)
                    ringRadii.append(radii.reduce(0, +) / Double(radii.count))
                }
                XCTAssertGreaterThan(abs(ringRadii[0] - ringRadii[1]), 0.055)
            }

            let scales = scene.actors.map { pose($0, in: scene, at: 0).scale }
            XCTAssertTrue(scales.allSatisfy { (0.22...0.38).contains($0) })
            XCTAssertLessThanOrEqual(scales.max()! / scales.min()!, 1.15)
            let periods = groups.keys.sorted().map { groups[$0]!.first!.route.period }
            XCTAssertTrue((0.72...1.38).contains(periods[0] / periods[1]))
        }
    }

    func testRadialBloomSharesOneCenterAndOpensAndClosesTogether() throws {
        for scene in try scenes(for: .radialBloom, count: 10) {
            let center = canvasPoint(scene.choreographyConfiguration.center)
            let period = try XCTUnwrap(scene.actors.first).route.period
            let sampleTimes = [0.0, period * 0.25, period * 0.50, period * 0.75]
            let radii = sampleTimes.map { time in
                scene.actors.map { simd_distance(pose($0, in: scene, at: time).position, center) }
            }
            for (time, values) in zip(sampleTimes, radii) {
                XCTAssertLessThan(
                    (values.max() ?? 0) - (values.min() ?? 0), 0.055,
                    "seed=\(scene.rootSeed) time=\(time) radii=\(values)"
                )
            }
            let means = radii.map { $0.reduce(0, +) / Double($0.count) }
            XCTAssertGreaterThan((means.max() ?? 0) - (means.min() ?? 0), 0.045)
        }
    }

    func testBreathingGridUsesRealSharedGridTopologyInProductionPoses() throws {
        for scene in try scenes(for: .breathingGrid, count: 10) {
            let center = canvasPoint(scene.choreographyConfiguration.center)
            let canonicalAnchors = scene.actors.map {
                rotated(canvasPoint($0.choreographySlot.anchor) - center,
                        by: -scene.choreographyConfiguration.orientation)
            }
            let rowCount = levelCount(canonicalAnchors.map(\.y), tolerance: 0.035)
            XCTAssertTrue((2...3).contains(rowCount), "anchors=\(canonicalAnchors)")
            XCTAssertGreaterThanOrEqual(
                canonicalAnchors.filter { abs($0.y - canonicalAnchors[0].y) < 0.035 }.count,
                3
            )

            for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
                for actor in scene.actors {
                    XCTAssertLessThan(
                        simd_distance(
                            pose(actor, in: scene, at: time).position,
                            canvasPoint(actor.choreographySlot.anchor)
                        ),
                        0.055,
                        "seed=\(scene.rootSeed) time=\(time) actor=\(actor.id)"
                    )
                }
            }
        }
    }

    func testWaveRibbonHasOneOrTwoCoordinatedRibbonsWithTravellingDisplacement() throws {
        for scene in try scenes(for: .waveRibbon, count: 10) {
            let groups = Dictionary(grouping: scene.actors) { $0.choreographySlot.group }
            XCTAssertTrue((1...2).contains(groups.count))
            let tangent = SIMD2(
                cos(scene.choreographyConfiguration.orientation),
                sin(scene.choreographyConfiguration.orientation)
            )
            let normal = SIMD2(-tangent.y, tangent.x)

            for actors in groups.values {
                let ordered = actors.sorted {
                    simd_dot(canvasPoint($0.choreographySlot.anchor), tangent)
                        < simd_dot(canvasPoint($1.choreographySlot.anchor), tangent)
                }
                for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
                    let longitudinal = ordered.map {
                        simd_dot(pose($0, in: scene, at: time).position, tangent)
                    }
                    XCTAssertTrue(
                        zip(longitudinal, longitudinal.dropFirst()).allSatisfy { $0 < $1 }
                    )
                }
                let displacements = [0.0, scene.score.duration * 0.2].map { time in
                    ordered.map {
                        simd_dot(
                            pose($0, in: scene, at: time).position
                                - canvasPoint($0.choreographySlot.anchor),
                            normal
                        )
                    }
                }
                XCTAssertGreaterThan(
                    zip(displacements[0], displacements[1]).map { abs($0 - $1) }.max() ?? 0,
                    0.02
                )
            }
        }
    }

    func testSpiralProcessionKeepsIncreasingRadiusAndAngularOrderWithoutPiling() throws {
        for scene in try scenes(for: .spiralProcession, count: 10) {
            let center = canvasPoint(scene.choreographyConfiguration.center)
            for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
                let positions = scene.actors.map { pose($0, in: scene, at: time).position }
                let radii = positions.map { simd_distance($0, center) }
                XCTAssertTrue(zip(radii, radii.dropFirst()).allSatisfy { $0 < $1 })
                let angles = positions.map { atan2(($0 - center).y, ($0 - center).x) }
                let steps = zip(angles, angles.dropFirst()).map {
                    wrappedPositiveAngle($1 - $0)
                }
                XCTAssertTrue(steps.allSatisfy { $0 > 0.20 && $0 < .pi })
                let minimumDistance = positions.enumerated().flatMap { index, lhs in
                    positions.dropFirst(index + 1).map { simd_distance(lhs, $0) }
                }.min() ?? 1
                XCTAssertGreaterThan(minimumDistance, 0.025)
            }
        }
    }

    func testEclipseStackUsesOneOrTwoClustersAndExchangesFrontBackOrder() throws {
        for scene in try scenes(for: .eclipseStack, count: 10) {
            let groups = Dictionary(grouping: scene.actors) { $0.choreographySlot.group }
            XCTAssertTrue((1...2).contains(groups.count), "groups=\(groups.keys)")
            for actors in groups.values {
                guard actors.count >= 2 else {
                    XCTFail("Each eclipse cluster needs at least two actors")
                    continue
                }
                let pair = Array(actors.prefix(2))
                var sawOverlap = false
                var sawSeparation = false
                var depthSigns = Set<Int>()
                for time in stride(from: 0.0, through: scene.score.duration, by: 3.0) {
                    let poses = pair.map { pose($0, in: scene, at: time) }
                    let distance = simd_distance(poses[0].position, poses[1].position)
                    let reach = poses[0].bodyRadius + poses[1].bodyRadius
                    sawOverlap = sawOverlap || distance < reach * 0.85
                    sawSeparation = sawSeparation || distance > reach * 1.05
                    let difference = poses[0].depth - poses[1].depth
                    if abs(difference) > 0.03 { depthSigns.insert(difference > 0 ? 1 : -1) }
                    let foreground = poses.max { $0.depth < $1.depth }!
                    let middle = poses.min { abs($0.depth - 0.55) < abs($1.depth - 0.55) }!
                    if foreground.depth > middle.depth + 0.06 {
                        XCTAssertGreaterThan(foreground.scale, middle.scale)
                        XCTAssertGreaterThan(foreground.localDepthSoftness, middle.localDepthSoftness)
                    }
                }
                XCTAssertTrue(sawOverlap)
                XCTAssertTrue(sawSeparation)
                XCTAssertEqual(depthSigns, [-1, 1])
            }
        }
    }

    func testCrossCurrentsUsesExactlyTwoOpposingStreamsWithStreamSizedActors() throws {
        for scene in try scenes(for: .crossCurrents, count: 10) {
            let groups = Dictionary(grouping: scene.actors) { $0.choreographySlot.group }
            XCTAssertEqual(Set(groups.keys), [0, 1])
            let directions = groups.keys.sorted().map { groups[$0]!.first!.route.direction }
            XCTAssertEqual(Set(directions), [-1, 1])
            for actors in groups.values {
                XCTAssertEqual(Set(actors.map(\.route.direction)).count, 1)
                let scales = actors.map { pose($0, in: scene, at: 0).scale }
                XCTAssertLessThanOrEqual(scales.max()! / scales.min()!, 1.05)
            }
            let allScales = scene.actors.map { pose($0, in: scene, at: 0).scale }
            XCTAssertLessThanOrEqual(allScales.max()! / allScales.min()!, 1.25)

            var closestIntersection = Double.greatestFiniteMagnitude
            for time in stride(from: 0.0, through: scene.score.duration, by: 2.0) {
                let lhs = groups[0]!.map { pose($0, in: scene, at: time).position }
                let rhs = groups[1]!.map { pose($0, in: scene, at: time).position }
                for a in lhs { for b in rhs {
                    closestIntersection = min(closestIntersection, simd_distance(a, b))
                }}
            }
            XCTAssertLessThan(closestIntersection, 0.12)
        }
    }

    func testConstellationRetainsLocalClustersAndCoversAllVerticalThirds() throws {
        let sampledScenes = try [6, 10].flatMap {
            try scenes(for: .constellation, count: $0)
        }
        for scene in sampledScenes {
            let groups = Dictionary(grouping: scene.actors) { $0.choreographySlot.group }
            XCTAssertTrue((3...4).contains(groups.count), "groups=\(groups.keys)")
            var baselineDistances = [Int: [Double]]()
            for (group, actors) in groups where actors.count >= 2 {
                let positions = actors.map { pose($0, in: scene, at: 0).position }
                baselineDistances[group] = zip(positions, positions.dropFirst()).map {
                    simd_distance($0, $1)
                }
            }
            for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
                let positions = scene.actors.map { pose($0, in: scene, at: time).position }
                let thirds = Set(positions.map {
                    min(max(Int((0.5 - $0.y) * 3), 0), 2)
                })
                XCTAssertEqual(thirds, [0, 1, 2])
                for (group, expected) in baselineDistances {
                    let current = groups[group]!.map { pose($0, in: scene, at: time).position }
                    let distances = zip(current, current.dropFirst()).map {
                        simd_distance($0, $1)
                    }
                    XCTAssertLessThan(
                        zip(expected, distances).map { abs($0 - $1) }.max() ?? 0,
                        0.035
                    )
                }
            }
        }
    }

    func testDepthFieldMigratesIndependentlyAcrossCanvasAndDepthPlanes() throws {
        for scene in try scenes(for: .depthField, count: 10) {
            let samples = stride(from: 0.0, through: scene.score.duration, by: 2.0)
                .flatMap { time in scene.actors.map { pose($0, in: scene, at: time) } }
            XCTAssertLessThan(samples.map(\.depth).min()!, 0.20)
            XCTAssertGreaterThan(samples.map(\.depth).max()!, 0.85)
            XCTAssertTrue(samples.contains { (0.48...0.62).contains($0.depth) })
            XCTAssertLessThan(samples.map(\.position.x).min()!, -0.25)
            XCTAssertGreaterThan(samples.map(\.position.x).max()!, 0.25)
            XCTAssertLessThan(samples.map(\.position.y).min()!, -0.25)
            XCTAssertGreaterThan(samples.map(\.position.y).max()!, 0.25)
            XCTAssertGreaterThan(Set(scene.actors.map { $0.route.period }).count, 3)
        }
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
        let cropAllowlist: Set<DayObjectChoreographyPreset> = [.depthField, .eclipseStack]
        var presetsObservedCropping = Set<DayObjectChoreographyPreset>()
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
                        let allowsIntentionalCrop = cropAllowlist.contains(scene.motionPlan.preset)
                        XCTAssertTrue(
                            pose.isInsideSafeBounds || allowsIntentionalCrop,
                            "preset=\(scene.motionPlan.preset) seed=\(seed) aspect=\(aspect) actor=\(actor.id) pose=\(pose)"
                        )
                        if !allowsIntentionalCrop {
                            XCTAssertEqual(
                                pose.intentionalCropFraction, 0, accuracy: 0.000_001,
                                "preset=\(scene.motionPlan.preset) seed=\(seed) aspect=\(aspect) actor=\(actor.id)"
                            )
                        }
                        if pose.intentionalCropFraction > 0.000_001 {
                            presetsObservedCropping.insert(scene.motionPlan.preset)
                            XCTAssertTrue(
                                allowsIntentionalCrop,
                                "preset=\(scene.motionPlan.preset) seed=\(seed) aspect=\(aspect) actor=\(actor.id)"
                            )
                        }
                        XCTAssertFalse(pose.intersectsUIExclusion)
                        XCTAssertFalse(pose.intersectsNegativeSpace)
                    }
                }
            }
        }
        XCTAssertFalse(presetsObservedCropping.isEmpty)
        XCTAssertTrue(presetsObservedCropping.isSubset(of: cropAllowlist))
    }

    func testCustomExclusionPlansForMaximumSpatialDiameter() throws {
        let fullCanvasScene = try scene(for: .depthField, count: 10)
        let regions = [
            DayObjectNormalizedRect(minX: 0.02, minY: 0.03, maxX: 0.34, maxY: 0.27),
            DayObjectNormalizedRect(minX: 0.35, minY: 0.28, maxX: 0.68, maxY: 0.66),
            DayObjectNormalizedRect(minX: 0.66, minY: 0.70, maxX: 0.98, maxY: 0.97),
        ]

        for region in regions {
            let source = fullCanvasScene.input
            let input = DayObjectSceneInput(
                dayKey: source.dayKey, identity: source.identity,
                eventIDs: source.eventIDs, motionEnergy: source.motionEnergy,
                visualClarity: source.visualClarity, reduceMotion: source.reduceMotion,
                uiExclusionRegion: region, canvasCoverage: .excluding(region),
                paletteCategories: source.paletteCategories
            )
            let scene = DayObjectScene.make(input: input)
            XCTAssertEqual(scene.motionPlan.preset, .depthField)
            for aspect in [0.46, 1.0, 4.0 / 3.0, 2.16] {
                for actor in scene.actors {
                    for sample in 0...192 {
                        let time = actor.depthSchedule.period * Double(sample) / 192
                        let pose = scene.score.pose(
                            for: actor, at: time, canvasAspect: aspect,
                            compositionPlan: scene.compositionPlan
                        )
                        let context = "region=\(region) aspect=\(aspect) actor=\(actor.id) sample=\(sample) pose=\(pose)"
                        XCTAssertTrue(pose.isInsideSafeBounds, context)
                        XCTAssertFalse(pose.intersectsUIExclusion, context)
                        XCTAssertFalse(pose.intersectsNegativeSpace, context)
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
                            let context = "unsafe seed=\(seed) region=\(region) aspect=\(aspect) "
                                + "actor=\(actor.id) sample=\(sample) pose=\(pose)"
                            XCTAssertTrue(pose.isInsideSafeBounds, context)
                            XCTAssertFalse(pose.intersectsUIExclusion, context)
                            XCTAssertFalse(pose.intersectsNegativeSpace, context)
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
