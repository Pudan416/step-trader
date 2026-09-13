import Foundation
import Testing
@testable import EditorialFieldCore

@Suite("Editorial motion field")
struct MotionFieldTests {
    private let ids = CorpusManifest.canonicalEventIDs

    @Test("motion recipes are exactly repeatable, finite, codable, and sendable")
    func recipesAreStableValueTypes() throws {
        let first = MotionField.make(daySeed: 0xA11C_E55E, eventIDs: ids)
        let second = MotionField.make(daySeed: 0xA11C_E55E, eventIDs: ids)

        #expect(first == second)
        #expect(first.values.allSatisfy(recipeIsFinite))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(first)
        let decoded = try JSONDecoder().decode([String: ActorMotionRecipe].self, from: encoded)
        #expect(decoded == first)

        let recipe = try #require(first[ids[0]])
        let pose = MotionField.pose(recipe: recipe, phase: 0.375, steps: .normal)
        let transition = MotionField.transition(kind: .insertion, progress: 0.375)
        requireSendable(recipe)
        requireSendable(pose)
        requireSendable(transition)
        requireSendable(ActorTransitionKind.removal)
        #expect(try roundTrip(pose) == pose)
        #expect(try roundTrip(transition) == transition)
        #expect(try roundTrip(ActorTransitionKind.insertion) == .insertion)
    }

    @Test("canonical identities are admitted first, duplicates collapse, and count is capped at ten")
    func admissionIsCanonicalUniqueAndBounded() {
        let extras = ["external-z", "external-b", "external-a", "external-c"]
        let input = Array(ids.prefix(8).reversed()) + extras + [ids[2], "external-a"]
        let recipes = MotionField.make(daySeed: 19, eventIDs: input)

        #expect(recipes.count == 10)
        #expect(Set(recipes.keys) == Set(Array(ids.prefix(8)) + ["external-a", "external-b"]))

        let canonicalOnly = MotionField.make(
            daySeed: 19,
            eventIDs: Array(ids.reversed()) + extras + [ids[4]]
        )
        #expect(canonicalOnly.count == 10)
        #expect(Set(canonicalOnly.keys) == Set(ids))
    }

    @Test("retained recipes and poses ignore reorder, insertion, and removal")
    func retainedActorsDoNotReroll() throws {
        let full = MotionField.make(daySeed: 77, eventIDs: ids)
        let prefix = MotionField.make(daySeed: 77, eventIDs: Array(ids.prefix(5)))
        let reordered = MotionField.make(daySeed: 77, eventIDs: ids.reversed())
        let removedIDs = ids.enumerated().compactMap { [1, 4, 8].contains($0.offset) ? nil : $0.element }
        let removed = MotionField.make(daySeed: 77, eventIDs: removedIDs)
        let inserted = MotionField.make(daySeed: 77, eventIDs: Array(ids.prefix(5)) + ["external-actor"])

        for id in ids.prefix(5) {
            let reference = try #require(full[id])
            #expect(prefix[id] == reference)
            #expect(reordered[id] == reference)
            #expect(inserted[id] == reference)
            #expect(
                MotionField.pose(recipe: try #require(prefix[id]), elapsedTime: 37, steps: .normal, baseDepth: 0.72)
                    == MotionField.pose(recipe: reference, elapsedTime: 37, steps: .normal, baseDepth: 0.72)
            )
        }
        for id in removedIDs {
            #expect(removed[id] == full[id])
        }
    }

    @Test("every recipe stays inside the frozen numeric bounds")
    func recipeBoundsHoldAcrossSeeds() {
        for seed in UInt64(0)..<512 {
            let recipes = MotionField.make(daySeed: seed, eventIDs: ids)
            #expect(recipes.count == 10)
            for recipe in recipes.values {
                #expect((90...220).contains(recipe.period))
                #expect(recipe.phase >= 0 && recipe.phase < 1)
                #expect(recipe.directionBias >= -.pi && recipe.directionBias < .pi)
                #expect((0.045...0.115).contains(recipe.amplitude))
                #expect((0.82...1.18).contains(recipe.speedRatio))
                #expect((0.02...0.05).contains(recipe.breathingAmplitude))
                #expect((0.018...0.060).contains(recipe.depthParallax))
                #expect(recipeIsFinite(recipe))
            }
        }
    }

    @Test("actors share a daily direction while retaining phase, direction, and speed diversity")
    func dailyDirectionIsCoherentButActorsAreNotLocked() {
        for seed in UInt64(0)..<128 {
            let recipes = Array(MotionField.make(daySeed: seed, eventIDs: ids).values)
            #expect(minimumCircularArc(recipes.map(\.directionBias)) <= 0.84 + 1e-12)
            #expect(Set(recipes.map { quantized($0.phase) }).count >= 8)
            #expect(Set(recipes.map { quantized($0.directionBias) }).count >= 8)
            #expect(Set(recipes.map { quantized($0.speedRatio) }).count >= 8)
        }
    }

    @Test("step tempo is exactly one at normal and 0.12 at low")
    func phaseUsesTheFrozenTempoMultipliers() throws {
        let recipe = testRecipe(period: 100, speedRatio: 1)
        let normal = MotionField.phase(recipe: recipe, elapsedTime: 10, steps: .normal)
        let low = MotionField.phase(recipe: recipe, elapsedTime: 10, steps: .low)

        #expect(abs(normal - 0.1) < 1e-15)
        #expect(abs(low - 0.012) < 1e-15)
        #expect(abs(low - normal * 0.12) < 1e-15)
        for elapsed in [-10_000.0, -1, 0, 1, 10_000] {
            let value = MotionField.phase(recipe: recipe, elapsedTime: elapsed, steps: .normal)
            #expect(value >= 0 && value < 1)
        }
    }

    @Test("actor phase and direction bias materially change the sampled route and heading")
    func phaseAndDirectionShapePose() {
        let baseline = testRecipe(phase: 0.07, directionBias: 0, amplitude: 0.10)
        let shiftedPhase = testRecipe(phase: 0.43, directionBias: 0, amplitude: 0.10)
        let turned = testRecipe(phase: 0.07, directionBias: .pi / 2, amplitude: 0.10)
        let baselinePose = MotionField.pose(
            recipe: baseline,
            phase: 0.31,
            steps: .normal,
            baseDepth: 0.5
        )
        let phasePose = MotionField.pose(
            recipe: shiftedPhase,
            phase: 0.31,
            steps: .normal,
            baseDepth: 0.5
        )
        let turnedPose = MotionField.pose(
            recipe: turned,
            phase: 0.31,
            steps: .normal,
            baseDepth: 0.5
        )

        #expect(distance(baselinePose.positionOffset, phasePose.positionOffset) > 0.01)
        #expect(distance(baselinePose.positionOffset, turnedPose.positionOffset) > 0.01)
        let baselineHeading = atan2(baselinePose.positionOffset.y, baselinePose.positionOffset.x)
        let turnedHeading = atan2(turnedPose.positionOffset.y, turnedPose.positionOffset.x)
        #expect(abs(circularDifference(baselineHeading, turnedHeading)) > 1.4)
    }

    @Test("speed ratio participates in authoritative elapsed-time phase and pose")
    func speedRatioChangesElapsedMotion() {
        let normalSpeed = testRecipe(period: 100, phase: 0.17, speedRatio: 1)
        let faster = testRecipe(period: 100, phase: 0.17, speedRatio: 1.18)

        #expect(abs(MotionField.phase(recipe: normalSpeed, elapsedTime: 10, steps: .normal) - 0.1) < 1e-15)
        #expect(abs(MotionField.phase(recipe: faster, elapsedTime: 10, steps: .normal) - 0.118) < 1e-15)
        let normalPose = MotionField.pose(
            recipe: normalSpeed,
            elapsedTime: 10,
            steps: .normal,
            baseDepth: 0.5
        )
        let fasterPose = MotionField.pose(
            recipe: faster,
            elapsedTime: 10,
            steps: .normal,
            baseDepth: 0.5
        )
        #expect(distance(normalPose.positionOffset, fasterPose.positionOffset) > 0.001)
    }

    @Test("normalized cycle endpoints are the exact frozen composition pose")
    func cycleEndpointsAreExactlyNeutral() throws {
        for recipe in MotionField.make(daySeed: 43, eventIDs: ids).values {
            let zero = MotionField.pose(recipe: recipe, phase: 0, steps: .low, baseDepth: 0.93)
            let one = MotionField.pose(recipe: recipe, phase: 1, steps: .normal, baseDepth: 0.07)

            #expect(zero == one)
            #expect(zero.positionOffset == CompositionPoint(x: 0, y: 0))
            #expect(zero.depthOffset == 0)
            #expect(zero.scale == 1)
            #expect(zero.rotation == 0)
        }
    }

    @Test("position, depth, breathing, and rotation remain continuous through the loop boundary")
    func normalizedBoundaryHasNoSeam() throws {
        let epsilon = 1e-7
        for recipe in MotionField.make(daySeed: 55, eventIDs: ids).values {
            let before = MotionField.pose(
                recipe: recipe,
                phase: 1 - epsilon,
                steps: .normal,
                baseDepth: 0.61
            )
            let after = MotionField.pose(
                recipe: recipe,
                phase: 1 + epsilon,
                steps: .low,
                baseDepth: 0.61
            )

            #expect(distance(before.positionOffset, after.positionOffset) < 1e-5)
            #expect(abs(before.depthOffset - after.depthOffset) < 1e-5)
            #expect(abs(before.scale - after.scale) < 1e-5)
            #expect(abs(before.rotation - after.rotation) < 1e-5)
        }
    }

    @Test("all sampled poses are finite and remain inside translation, depth, scale, and rotation bounds")
    func poseBoundsHoldAcrossSeedsAndPhases() {
        for seed in UInt64(0)..<128 {
            for recipe in MotionField.make(daySeed: seed, eventIDs: ids).values {
                for sample in 0...128 {
                    let phase = Double(sample) / 128
                    let pose = MotionField.pose(
                        recipe: recipe,
                        phase: phase,
                        steps: sample.isMultiple(of: 2) ? .normal : .low,
                        baseDepth: Double(sample) / 128
                    )
                    #expect(poseIsFinite(pose))
                    #expect(distance(.init(x: 0, y: 0), pose.positionOffset) <= 1.15 * recipe.amplitude + 1e-12)
                    #expect(abs(pose.depthOffset) <= 0.075 + 1e-12)
                    #expect((0.95...1.05).contains(pose.scale))
                    #expect(abs(pose.rotation) <= 0.026 + 1e-12)
                }
            }
        }
    }

    @Test("adverse generated actor phases retain visible 8, 10, and 12 second travel")
    func shortEvidenceWindowsPreserveSubtleTravel() {
        let generated = (UInt64(0)..<96).flatMap {
            MotionField.make(daySeed: $0, eventIDs: ids).values
        }
        let adverse = generated.map { recipe in
            (
                recipe: recipe,
                travel: elapsedPathLength(recipe: recipe, steps: .normal, duration: 8, samples: 96)
            )
        }.sorted { $0.travel < $1.travel }.prefix(16).map(\.recipe)

        #expect(adverse.count == 16)
        for recipe in adverse {
            for duration in [8.0, 10, 12] {
                let normal = elapsedPathLength(
                    recipe: recipe,
                    steps: .normal,
                    duration: duration,
                    samples: 96
                )
                let low = elapsedPathLength(
                    recipe: recipe,
                    steps: .low,
                    duration: duration,
                    samples: 96
                )

                #expect(normal > 0.001)
                #expect(low > 0)
                #expect(low < normal * 0.35)
            }
        }
    }

    @Test("foreground parallax exceeds distant parallax through a continuous depth multiplier")
    func parallaxIsMonotonicWithoutDepthClasses() throws {
        let recipe = try #require(MotionField.make(daySeed: 71, eventIDs: ids)[ids[0]])
        let phases = (1..<64).map { Double($0) / 64 }
        let farTravel = phasePathLength(recipe: recipe, baseDepth: 0, phases: phases)
        let nearTravel = phasePathLength(recipe: recipe, baseDepth: 1, phases: phases)
        let farDepthTravel = depthPathLength(recipe: recipe, baseDepth: 0, phases: phases)
        let nearDepthTravel = depthPathLength(recipe: recipe, baseDepth: 1, phases: phases)

        #expect(nearTravel > farTravel)
        #expect(nearDepthTravel > farDepthTravel)

        let activePhase = try #require(phases.max { lhs, rhs in
            let left = MotionField.pose(recipe: recipe, phase: lhs, steps: .normal, baseDepth: 0)
            let right = MotionField.pose(recipe: recipe, phase: rhs, steps: .normal, baseDepth: 0)
            return distance(.init(x: 0, y: 0), left.positionOffset)
                < distance(.init(x: 0, y: 0), right.positionOffset)
        })
        let depthSamples = (0...1_000).map { index in
            MotionField.pose(
                recipe: recipe,
                phase: activePhase,
                steps: .normal,
                baseDepth: Double(index) / 1_000
            )
        }
        let magnitudes = depthSamples.map { distance(.init(x: 0, y: 0), $0.positionOffset) }
        let depthMagnitudes = depthSamples.map { abs($0.depthOffset) }
        #expect(zip(magnitudes, magnitudes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(zip(depthMagnitudes, depthMagnitudes.dropFirst()).allSatisfy { $0 < $1 })
        #expect(maximumAdjacentDelta(magnitudes) < 0.001)
        #expect(maximumAdjacentDelta(depthMagnitudes) < 0.001)
    }

    @Test("depth and breathing evolve continuously rather than switching state")
    func depthAndBreathingAreContinuous() throws {
        let recipe = try #require(MotionField.make(daySeed: 83, eventIDs: ids)[ids[3]])
        let poses = (0...512).map {
            MotionField.pose(
                recipe: recipe,
                phase: Double($0) / 512,
                steps: .normal,
                baseDepth: 0.76
            )
        }
        let depths = poses.map(\.depthOffset)
        let scales = poses.map(\.scale)

        #expect((depths.max() ?? 0) - (depths.min() ?? 0) > 0.001)
        #expect((scales.max() ?? 0) - (scales.min() ?? 0) > 0.001)
        #expect(maximumAdjacentDelta(depths) < 0.01)
        #expect(maximumAdjacentDelta(scales) < 0.01)
    }

    @Test("rotation remains bounded and energetically subordinate to translation")
    func rotationDoesNotDominate() {
        for recipe in MotionField.make(daySeed: 97, eventIDs: ids).values {
            let poses = (0..<256).map {
                MotionField.pose(
                    recipe: recipe,
                    phase: Double($0) / 256,
                    steps: .normal,
                    baseDepth: 0.5
                )
            }
            let translationEnergy = rootMeanSquare(
                poses.map { distance(.init(x: 0, y: 0), $0.positionOffset) }
            )
            let rotationEnergy = rootMeanSquare(poses.map(\.rotation))

            #expect(poses.allSatisfy { abs($0.rotation) <= 0.026 })
            #expect(rotationEnergy < translationEnergy)
        }
    }

    @Test("Reduce Motion returns the exact frozen pose for every phase, tempo, and depth")
    func reduceMotionIsExactlyNeutral() {
        for recipe in MotionField.make(daySeed: 101, eventIDs: ids).values {
            for elapsed in [-123.0, 0, 17, 9_999] {
                for steps in StepCondition.allCases {
                    for depth in [0.0, 0.27, 0.68, 1.0] {
                        let elapsedPose = MotionField.pose(
                            recipe: recipe,
                            elapsedTime: elapsed,
                            steps: steps,
                            reduceMotion: true,
                            baseDepth: depth
                        )
                        let phasePose = MotionField.pose(
                            recipe: recipe,
                            phase: elapsed / 10,
                            steps: steps,
                            reduceMotion: true,
                            baseDepth: depth
                        )
                        for pose in [elapsedPose, phasePose] {
                            #expect(pose.positionOffset == CompositionPoint(x: 0, y: 0))
                            #expect(pose.depthOffset == 0)
                            #expect(pose.scale == 1)
                            #expect(pose.rotation == 0)
                        }
                    }
                }
            }
        }
    }

    @Test("transition envelope has exact endpoints, clamps progress, and uses quintic smootherstep")
    func transitionEnvelopeMatchesContract() {
        let insertionStart = MotionField.transition(kind: .insertion, progress: -1)
        let insertionQuarter = MotionField.transition(kind: .insertion, progress: 0.25)
        let insertionMiddle = MotionField.transition(kind: .insertion, progress: 0.5)
        let insertionEnd = MotionField.transition(kind: .insertion, progress: 2)
        let removalStart = MotionField.transition(kind: .removal, progress: -1)
        let removalQuarter = MotionField.transition(kind: .removal, progress: 0.25)
        let removalEnd = MotionField.transition(kind: .removal, progress: 2)

        #expect(insertionStart == ActorTransitionPose(opacity: 0, scale: 0.96))
        #expect(insertionEnd == ActorTransitionPose(opacity: 1, scale: 1))
        #expect(removalStart == ActorTransitionPose(opacity: 1, scale: 1))
        #expect(removalEnd == ActorTransitionPose(opacity: 0, scale: 0.96))
        #expect(insertionQuarter.opacity == 0.103515625)
        #expect(abs(insertionQuarter.scale - 0.964140625) < 1e-15)
        #expect(insertionMiddle.opacity == 0.5)
        #expect(removalQuarter.opacity == 1 - insertionQuarter.opacity)
        #expect(abs(removalQuarter.scale - (1 - 0.04 * insertionQuarter.opacity)) < 1e-15)
    }

    @Test("non-finite transition progress has deterministic directed clamping")
    func nonFiniteTransitionProgressClampsByDirection() {
        for kind in [ActorTransitionKind.insertion, .removal] {
            #expect(
                MotionField.transition(kind: kind, progress: -Double.infinity)
                    == MotionField.transition(kind: kind, progress: 0)
            )
            #expect(
                MotionField.transition(kind: kind, progress: .infinity)
                    == MotionField.transition(kind: kind, progress: 1)
            )
            #expect(
                MotionField.transition(kind: kind, progress: .nan)
                    == MotionField.transition(kind: kind, progress: 0)
            )
        }
        #expect(MotionField.transition(kind: .insertion, progress: .infinity).opacity == 1)
        #expect(MotionField.transition(kind: .removal, progress: .infinity).opacity == 0)
    }

    @Test("invalid public recipe construction cannot escape finite global pose bounds")
    func invalidConstructedRecipesAreSafeAtSamplingBoundaries() {
        let recipes = [
            ActorMotionRecipe(
                eventID: "non-finite",
                period: .nan,
                phase: .infinity,
                directionBias: -.infinity,
                amplitude: .infinity,
                speedRatio: .nan,
                breathingAmplitude: -.infinity,
                depthParallax: .infinity
            ),
            ActorMotionRecipe(
                eventID: "finite-out-of-contract",
                period: -10,
                phase: 9.75,
                directionBias: 1_000,
                amplitude: -4,
                speedRatio: 10_000,
                breathingAmplitude: 8,
                depthParallax: -3
            ),
        ]

        for recipe in recipes {
            for elapsed in [-Double.infinity, -.greatestFiniteMagnitude, 0, .greatestFiniteMagnitude, .infinity, .nan] {
                for steps in StepCondition.allCases {
                    let phase = MotionField.phase(recipe: recipe, elapsedTime: elapsed, steps: steps)
                    #expect(phase.isFinite)
                    #expect(phase >= 0 && phase < 1)
                }
            }
            for sampledPhase in [-Double.infinity, -1e300, 0.25, 1e300, Double.infinity, Double.nan] {
                for depth in [-Double.infinity, -100, 0.5, 100, Double.infinity, Double.nan] {
                    assertGloballyBounded(
                        MotionField.pose(
                            recipe: recipe,
                            phase: sampledPhase,
                            steps: .normal,
                            baseDepth: depth
                        )
                    )
                    assertGloballyBounded(
                        MotionField.pose(
                            recipe: recipe,
                            elapsedTime: sampledPhase,
                            steps: .low,
                            baseDepth: depth
                        )
                    )
                }
            }
        }
    }

    @Test("invalid decoded recipes cannot poison phase or pose output")
    func invalidDecodedRecipeIsSafeAtSamplingBoundaries() throws {
        let json = Data(
            #"{"eventID":"decoded-invalid","period":"NaN","phase":"Infinity","directionBias":"-Infinity","amplitude":1e100,"speedRatio":-400,"breathingAmplitude":1e100,"depthParallax":-1e100}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let recipe = try decoder.decode(ActorMotionRecipe.self, from: json)

        assertGloballyBounded(
            MotionField.pose(
                recipe: recipe,
                phase: 0.25,
                steps: .normal,
                baseDepth: 0.5
            )
        )

        for elapsed in [-Double.infinity, 0, 17, .infinity, .nan] {
            let phase = MotionField.phase(recipe: recipe, elapsedTime: elapsed, steps: .normal)
            #expect(phase.isFinite)
            #expect(phase >= 0 && phase < 1)
            assertGloballyBounded(
                MotionField.pose(
                    recipe: recipe,
                    elapsedTime: elapsed,
                    steps: .normal,
                    baseDepth: .nan
                )
            )
        }
    }

    @Test("transition opacity and scale are monotonic with smooth endpoint easing")
    func transitionIsMonotonicAndSmooth() {
        let progress = (0...1_000).map { Double($0) / 1_000 }
        let insertion = progress.map { MotionField.transition(kind: .insertion, progress: $0) }
        let removal = progress.map { MotionField.transition(kind: .removal, progress: $0) }

        #expect(zip(insertion, insertion.dropFirst()).allSatisfy { $0.opacity <= $1.opacity })
        #expect(zip(insertion, insertion.dropFirst()).allSatisfy { $0.scale <= $1.scale })
        #expect(zip(removal, removal.dropFirst()).allSatisfy { $0.opacity >= $1.opacity })
        #expect(zip(removal, removal.dropFirst()).allSatisfy { $0.scale >= $1.scale })
        #expect(insertion[1].opacity < 1e-8)
        #expect(1 - insertion[999].opacity < 1e-8)
        #expect(insertion[1].opacity < insertion[501].opacity - insertion[500].opacity)
        #expect(insertion[1_000].opacity - insertion[999].opacity < insertion[501].opacity - insertion[500].opacity)
    }

    @Test("Reduce Motion preserves transition opacity but fixes transition scale at one")
    func reduceMotionTransitionOnlyFades() {
        for kind in [ActorTransitionKind.insertion, .removal] {
            for progress in stride(from: -0.25, through: 1.25, by: 0.05) {
                let animated = MotionField.transition(kind: kind, progress: progress)
                let reduced = MotionField.transition(kind: kind, progress: progress, reduceMotion: true)
                #expect(reduced.opacity == animated.opacity)
                #expect(reduced.scale == 1)
            }
        }
    }

    @Test("sampling a transition cannot alter unrelated actor recipes or poses")
    func transitionIsActorLocalValueState() throws {
        let beforeRecipes = MotionField.make(daySeed: 109, eventIDs: ids)
        let beforePoses = try ids.reduce(into: [String: ActorMotionPose]()) { result, id in
            result[id] = MotionField.pose(
                recipe: try #require(beforeRecipes[id]),
                elapsedTime: 29,
                steps: .normal,
                baseDepth: 0.58
            )
        }

        _ = MotionField.transition(kind: .removal, progress: 0.42)

        let afterRecipes = MotionField.make(daySeed: 109, eventIDs: ids)
        let afterPoses = try ids.reduce(into: [String: ActorMotionPose]()) { result, id in
            result[id] = MotionField.pose(
                recipe: try #require(afterRecipes[id]),
                elapsedTime: 29,
                steps: .normal,
                baseDepth: 0.58
            )
        }
        #expect(afterRecipes == beforeRecipes)
        #expect(afterPoses == beforePoses)
    }

    private func recipeIsFinite(_ recipe: ActorMotionRecipe) -> Bool {
        recipe.period.isFinite
            && recipe.phase.isFinite
            && recipe.directionBias.isFinite
            && recipe.amplitude.isFinite
            && recipe.speedRatio.isFinite
            && recipe.breathingAmplitude.isFinite
            && recipe.depthParallax.isFinite
    }

    private func poseIsFinite(_ pose: ActorMotionPose) -> Bool {
        pose.positionOffset.x.isFinite
            && pose.positionOffset.y.isFinite
            && pose.depthOffset.isFinite
            && pose.scale.isFinite
            && pose.rotation.isFinite
    }

    private func distance(_ lhs: CompositionPoint, _ rhs: CompositionPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func circularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        atan2(sin(rhs - lhs), cos(rhs - lhs))
    }

    private func testRecipe(
        period: Double = 150,
        phase: Double = 0.2,
        directionBias: Double = 0.3,
        amplitude: Double = 0.09,
        speedRatio: Double = 1,
        breathingAmplitude: Double = 0.035,
        depthParallax: Double = 0.04
    ) -> ActorMotionRecipe {
        ActorMotionRecipe(
            eventID: "mutation-fixture",
            period: period,
            phase: phase,
            directionBias: directionBias,
            amplitude: amplitude,
            speedRatio: speedRatio,
            breathingAmplitude: breathingAmplitude,
            depthParallax: depthParallax
        )
    }

    private func assertGloballyBounded(_ pose: ActorMotionPose) {
        #expect(poseIsFinite(pose))
        #expect(distance(.init(x: 0, y: 0), pose.positionOffset) <= 1.15 * 0.115 + 1e-12)
        #expect(abs(pose.depthOffset) <= 0.075 + 1e-12)
        #expect((0.95...1.05).contains(pose.scale))
        #expect(abs(pose.rotation) <= 0.026 + 1e-12)
    }

    private func quantized(_ value: Double) -> Int64 {
        Int64((value * 1_000_000_000).rounded())
    }

    private func minimumCircularArc(_ angles: [Double]) -> Double {
        guard angles.count > 1 else { return 0 }
        let turn = 2 * Double.pi
        let normalized = angles.map { angle -> Double in
            let value = angle.truncatingRemainder(dividingBy: turn)
            return value >= 0 ? value : value + turn
        }.sorted()
        let gaps = normalized.indices.map { index -> Double in
            let next = index == normalized.index(before: normalized.endIndex)
                ? normalized[0] + turn
                : normalized[index + 1]
            return next - normalized[index]
        }
        return turn - (gaps.max() ?? turn)
    }

    private func elapsedPathLength(
        recipe: ActorMotionRecipe,
        steps: StepCondition,
        duration: Double,
        samples: Int
    ) -> Double {
        let points = (0...samples).map {
            MotionField.pose(
                recipe: recipe,
                elapsedTime: duration * Double($0) / Double(samples),
                steps: steps,
                baseDepth: 0.5
            ).positionOffset
        }
        return zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private func phasePathLength(
        recipe: ActorMotionRecipe,
        baseDepth: Double,
        phases: [Double]
    ) -> Double {
        let points = phases.map {
            MotionField.pose(recipe: recipe, phase: $0, steps: .normal, baseDepth: baseDepth).positionOffset
        }
        return zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private func depthPathLength(
        recipe: ActorMotionRecipe,
        baseDepth: Double,
        phases: [Double]
    ) -> Double {
        let values = phases.map {
            MotionField.pose(recipe: recipe, phase: $0, steps: .normal, baseDepth: baseDepth).depthOffset
        }
        return zip(values, values.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
    }

    private func maximumAdjacentDelta(_ values: [Double]) -> Double {
        zip(values, values.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    private func rootMeanSquare(_ values: [Double]) -> Double {
        sqrt(values.map { $0 * $0 }.reduce(0, +) / Double(values.count))
    }

    private func roundTrip<Value>(_ value: Value) throws -> Value
    where Value: Codable & Equatable {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func requireSendable<Value: Sendable>(_: Value) {}
}
