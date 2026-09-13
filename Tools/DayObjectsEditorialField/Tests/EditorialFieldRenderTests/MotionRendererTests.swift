import CoreGraphics
import Foundation
import ImageIO
import Testing
import EditorialFieldCore
import EditorialFieldEvidence
@testable import EditorialFieldRender

@Suite("Editorial motion render adapter")
struct MotionRendererTests {
    @Test("frame applies only transient pose geometry and preserves frozen inputs")
    func frameAppliesPoseWithoutMutatingInputs() throws {
        let inputs = makeInputs(actorCount: 3, family: .gradient)
        let compositionBefore = try canonicalData(inputs.recipe)
        let materialBefore = try canonicalData(inputs.material)
        let motionBefore = try canonicalData(inputs.motion)
        let renderer = MotionRenderer()

        let frame = try renderer.frame(
            recipe: inputs.recipe,
            motionRecipes: inputs.motion,
            phase: 0.37,
            steps: .normal
        )

        #expect(frame.recipe.daySeed == inputs.recipe.daySeed)
        #expect(frame.recipe.grammar == inputs.recipe.grammar)
        #expect(frame.recipe.viewport == inputs.recipe.viewport)
        #expect(frame.actorFrames.map(\.eventID) == inputs.recipe.actors.map(\.eventID))
        for base in inputs.recipe.actors {
            let transformed = try #require(frame.recipe.actor(base.eventID))
            let actorFrame = try #require(frame.actorFrames.first { $0.eventID == base.eventID })
            let pose = try #require(inputs.motion[base.eventID]).pipe {
                MotionField.pose(
                    recipe: $0,
                    phase: 0.37,
                    steps: .normal,
                    baseDepth: base.depth
                )
            }
            #expect(actorFrame.baseDrawOrder == base.drawOrder)
            #expect(actorFrame.pose == pose)
            #expect(actorFrame.transition == ActorTransitionPose(opacity: 1, scale: 1))
            #expect(transformed.eventID == base.eventID)
            #expect(transformed.cropAllowance == base.cropAllowance)
            #expect(abs(transformed.position.x - (
                base.position.x + pose.positionOffset.x * inputs.recipe.viewport.shortSide
                    / inputs.recipe.viewport.width
            )) < 1e-15)
            #expect(abs(transformed.position.y - (
                base.position.y + pose.positionOffset.y * inputs.recipe.viewport.shortSide
                    / inputs.recipe.viewport.height
            )) < 1e-15)
            #expect(abs(transformed.diameter - base.diameter * pose.scale) < 1e-15)
            #expect(frame.actorCompositeOpacities[base.eventID] == 1)
            #expect(frame.actorRigidRotations[base.eventID] == pose.rotation)
        }
        #expect(try canonicalData(inputs.recipe) == compositionBefore)
        #expect(try canonicalData(inputs.material) == materialBefore)
        #expect(try canonicalData(inputs.motion) == motionBefore)
    }

    @Test("phone-axis translation is not clamped and crop allowance remains exact")
    func translationUsesShortSideAxesWithoutPositionClamping() throws {
        let eventID = "edge"
        let motion = testMotion(eventID: eventID, phase: 0.11, directionBias: 0.4)
        let sampled = MotionField.pose(
            recipe: motion,
            phase: 0.43,
            steps: .normal,
            baseDepth: 0.73
        )
        let base = ActorCompositionRecipe(
            eventID: eventID,
            position: .init(
                x: sampled.positionOffset.x >= 0 ? 0.995 : 0.005,
                y: sampled.positionOffset.y >= 0 ? 0.998 : 0.002
            ),
            diameter: 0.42,
            depth: 0.73,
            localBlur: 0.013,
            cropAllowance: 0.41,
            drawOrder: 0
        )
        let recipe = CompositionRecipe(
            daySeed: 91,
            grammar: .croppedForeground,
            viewport: .phone,
            actors: [base]
        )
        let frame = try MotionRenderer().frame(
            recipe: recipe,
            motionRecipes: [eventID: motion],
            phase: 0.43,
            steps: .normal
        )
        let actor = try #require(frame.recipe.actor(eventID))

        #expect(actor.position.x == base.position.x + sampled.positionOffset.x)
        #expect(actor.position.y == base.position.y
            + sampled.positionOffset.y * EditorialViewport.phone.shortSide
                / EditorialViewport.phone.height)
        #expect(actor.cropAllowance == 0.41)
        #expect(actor.position.x < 0 || actor.position.x > 1
            || actor.position.y < 0 || actor.position.y > 1)
    }

    @Test("effective depth clamps and focus follows the exact continuous profile")
    func depthAndFocusUseContinuousProfile() throws {
        let eventID = "focus"
        let motion = testMotion(eventID: eventID, phase: 0.19, depthParallax: 0.06)
        let activePhase = try #require((1..<256).map { Double($0) / 256 }.max { lhs, rhs in
            MotionField.pose(recipe: motion, phase: lhs, steps: .normal, baseDepth: 1).depthOffset
                < MotionField.pose(recipe: motion, phase: rhs, steps: .normal, baseDepth: 1).depthOffset
        })
        let base = ActorCompositionRecipe(
            eventID: eventID,
            position: .init(x: 0.5, y: 0.5),
            diameter: 0.5,
            depth: 1,
            localBlur: 0.021,
            cropAllowance: 0,
            drawOrder: 0
        )
        let recipe = CompositionRecipe(
            daySeed: 92,
            grammar: .depthScatter,
            viewport: .phone,
            actors: [base]
        )
        let frame = try MotionRenderer().frame(
            recipe: recipe,
            motionRecipes: [eventID: motion],
            phase: activePhase,
            steps: .normal
        )
        let actor = try #require(frame.recipe.actor(eventID))
        let sampled = MotionField.pose(
            recipe: motion,
            phase: activePhase,
            steps: .normal,
            baseDepth: base.depth
        )
        let effectiveDepth = min(1, max(0, base.depth + sampled.depthOffset))
        let expectedBlur = max(
            0,
            base.localBlur + focusProfile(effectiveDepth) - focusProfile(base.depth)
        )

        #expect(actor.depth == 1)
        #expect(actor.localBlur == expectedBlur)

        let depths = Array(stride(from: 0.30, through: 0.70, by: 0.002))
        var blurValues = [Double]()
        for (batchIndex, batch) in depths.chunked(maximumCount: 10).enumerated() {
            let actors = batch.enumerated().map { offset, depth in
                ActorCompositionRecipe(
                    eventID: "d-\(batchIndex)-\(offset)",
                    position: .init(x: 0.5, y: 0.5),
                    diameter: 0.2,
                    depth: depth,
                    localBlur: 0.01,
                    cropAllowance: 0,
                    drawOrder: offset
                )
            }
            let boundedRecipe = CompositionRecipe(
                daySeed: UInt64(93 + batchIndex),
                grammar: .depthScatter,
                viewport: .phone,
                actors: actors
            )
            let boundedMotion = Dictionary(uniqueKeysWithValues: actors.map {
                ($0.eventID, testMotion(eventID: $0.eventID, phase: 0.21))
            })
            let boundedFrame = try MotionRenderer().frame(
                recipe: boundedRecipe,
                motionRecipes: boundedMotion,
                phase: 0.31,
                steps: .normal
            )
            blurValues.append(contentsOf: boundedFrame.recipe.actors.map(\.localBlur))
        }
        #expect(zip(blurValues, blurValues.dropFirst()).map { abs($0 - $1) }.max() ?? 1 < 0.001)

        let approvedRecipes = try approvedVisibleRecipes()
        let requiredPhases = CorpusManifest.visibleV1().phases
        var hierarchyComparisons = 0
        for approvedRecipe in approvedRecipes {
            let motion = MotionField.make(
                daySeed: approvedRecipe.daySeed,
                eventIDs: approvedRecipe.actors.map(\.eventID)
            )
            for phase in requiredPhases {
                let hierarchyFrame = try MotionRenderer().frame(
                    recipe: approvedRecipe,
                    motionRecipes: motion,
                    phase: phase,
                    steps: .normal
                )
                let foreground = hierarchyFrame.recipe.actors.filter {
                    $0.depth >= 0.68 && $0.diameter >= 0.38
                }
                let middle = hierarchyFrame.recipe.actors.filter {
                    (0.32..<0.68).contains($0.depth)
                }
                guard let sharpestMiddle = middle.map(\.localBlur).min(), !foreground.isEmpty else {
                    continue
                }
                hierarchyComparisons += foreground.count
                #expect(foreground.allSatisfy { $0.localBlur > sharpestMiddle })
            }
        }
        #expect(hierarchyComparisons > 0)
    }

    @Test("public adapter rejects scenes above the frozen ten-actor maximum before sampling")
    func actorLimitFailsBeforeSampling() {
        let actors = (0..<11).map {
            actor("over-cap-\($0)", depth: 0.5, drawOrder: $0)
        }
        let recipe = CompositionRecipe(
            daySeed: 95,
            grammar: .openField,
            viewport: .phone,
            actors: actors
        )

        #expect(throws: MotionRendererError.actorLimitExceeded(11)) {
            _ = try MotionRenderer().frame(
                recipe: recipe,
                motionRecipes: [:],
                phase: 0.2,
                steps: .normal
            )
        }
    }

    @Test("effective draw order follows depth with base order and event ID ties")
    func transientDrawOrderIsDeterministic() throws {
        let actors = [
            actor("z", depth: 0.50, drawOrder: 4),
            actor("b", depth: 0.50, drawOrder: 2),
            actor("a", depth: 0.50, drawOrder: 2),
            actor("front", depth: 0.80, drawOrder: 0),
        ]
        let recipe = CompositionRecipe(
            daySeed: 94,
            grammar: .depthScatter,
            viewport: .phone,
            actors: actors
        )
        let motion = Dictionary(uniqueKeysWithValues: actors.map {
            ($0.eventID, testMotion(eventID: $0.eventID, amplitude: 0.05, depthParallax: 0.018))
        })

        let frame = try MotionRenderer().frame(
            recipe: recipe,
            motionRecipes: motion,
            phase: 0.2,
            steps: .normal
        )

        let byEffectiveOrder = frame.actorFrames.sorted {
            $0.effectiveDrawOrder < $1.effectiveDrawOrder
        }
        #expect(byEffectiveOrder.map(\.eventID) == ["a", "b", "z", "front"])
        #expect(frame.actorFrames.map(\.baseDrawOrder) == [4, 2, 2, 0])
        #expect(recipe.actors.map(\.drawOrder) == [4, 2, 2, 0])
        #expect(frame.recipe.actors.map(\.drawOrder) == frame.actorFrames.map(\.effectiveDrawOrder))
    }

    @Test("phase zero preserves exact base geometry and full-scene pixels")
    func phaseZeroIsExactBaseRender() throws {
        let inputs = makeInputs(actorCount: 3, family: .gradient)
        let compositionBefore = try canonicalData(inputs.recipe)
        let materialBefore = try canonicalData(inputs.material)
        let base = try MaterialRenderer().render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .dark,
            configuration: .init(scale: 1)
        )
        let adapter = MotionRenderer()
        let frame = try adapter.frame(
            recipe: inputs.recipe,
            motionRecipes: inputs.motion,
            phase: 0,
            steps: .normal
        )
        let rendered = try adapter.render(
            recipe: inputs.recipe,
            material: inputs.material,
            motionRecipes: inputs.motion,
            background: .dark,
            phase: 0,
            steps: .normal,
            configuration: .init(scale: 1)
        )

        #expect(frame.recipe == inputs.recipe)
        #expect(frame.actorCompositeOpacities.values.allSatisfy { $0 == 1 })
        #expect(frame.actorRigidRotations.values.allSatisfy { $0 == 0 })
        #expect(rendered.fullScreen.pngData == base.fullScreen.pngData)
        #expect(rendered.calendarTile.pngData == base.calendarTile.pngData)
        #expect(rendered.tileCrop == base.tileCrop)
        #expect(rendered.drawSequence == base.drawSequence)
        #expect(try canonicalData(inputs.recipe) == compositionBefore)
        #expect(try canonicalData(inputs.material) == materialBefore)
    }

    @Test("Reduce Motion preserves the exact frozen render at every elapsed time")
    func reduceMotionIsExactBaseRender() throws {
        let inputs = makeInputs(actorCount: 2, family: .solid)
        let base = try MaterialRenderer().render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .light,
            configuration: .init(scale: 1)
        )
        let renderer = MotionRenderer()

        for elapsed in [-10_000.0, 0, 31, 100_000] {
            let rendered = try renderer.render(
                recipe: inputs.recipe,
                material: inputs.material,
                motionRecipes: inputs.motion,
                background: .light,
                elapsedTime: elapsed,
                steps: .low,
                reduceMotion: true,
                configuration: .init(scale: 1)
            )
            #expect(rendered.fullScreen.pngData == base.fullScreen.pngData)
            #expect(rendered.calendarTile.pngData == base.calendarTile.pngData)
            #expect(rendered.drawSequence == base.drawSequence)
        }
    }

    @Test("transition changes only its target and Reduce Motion keeps transition scale at one")
    func transitionIsTargetOnly() throws {
        let inputs = makeInputs(actorCount: 3, family: .gradient)
        let target = inputs.recipe.actors[1].eventID
        let baseline = try MotionRenderer().frame(
            recipe: inputs.recipe,
            motionRecipes: inputs.motion,
            phase: 0,
            steps: .normal
        )
        let transition = ActorMotionTransition(kind: .insertion, progress: 0.25)
        let changed = try MotionRenderer().frame(
            recipe: inputs.recipe,
            motionRecipes: inputs.motion,
            phase: 0,
            steps: .normal,
            transitions: [target: transition]
        )
        let reduced = try MotionRenderer().frame(
            recipe: inputs.recipe,
            motionRecipes: inputs.motion,
            phase: 0,
            steps: .normal,
            reduceMotion: true,
            transitions: [target: transition]
        )

        for actor in inputs.recipe.actors {
            let baseActor = try #require(baseline.recipe.actor(actor.eventID))
            let changedActor = try #require(changed.recipe.actor(actor.eventID))
            if actor.eventID == target {
                #expect(changedActor.diameter != baseActor.diameter)
                #expect(changed.actorCompositeOpacities[target] == 0.103515625)
                #expect(reduced.actorCompositeOpacities[target] == 0.103515625)
                #expect(try #require(reduced.recipe.actor(target)).diameter == actor.diameter)
            } else {
                #expect(changedActor == baseActor)
                #expect(changed.actorFrames.first { $0.eventID == actor.eventID }
                    == baseline.actorFrames.first { $0.eventID == actor.eventID })
            }
        }

        let renderInputs = makeSeparatedTransitionInputs()
        let renderedTarget = renderInputs.recipe.actors[1].eventID
        let renderer = MotionRenderer()
        let basePixels = try renderer.render(
            recipe: renderInputs.recipe,
            material: renderInputs.material,
            motionRecipes: renderInputs.motion,
            background: .dark,
            phase: 0,
            steps: .normal,
            configuration: .init(scale: 1)
        ).fullScreen.pngData
        let animatedPixels = try renderer.render(
            recipe: renderInputs.recipe,
            material: renderInputs.material,
            motionRecipes: renderInputs.motion,
            background: .dark,
            phase: 0,
            steps: .normal,
            transitions: [renderedTarget: transition],
            configuration: .init(scale: 1)
        ).fullScreen.pngData
        let reducedPixels = try renderer.render(
            recipe: renderInputs.recipe,
            material: renderInputs.material,
            motionRecipes: renderInputs.motion,
            background: .dark,
            phase: 0,
            steps: .normal,
            reduceMotion: true,
            transitions: [renderedTarget: transition],
            configuration: .init(scale: 1)
        ).fullScreen.pngData

        for actor in renderInputs.recipe.actors {
            let crop = actorPixelRect(actor, padding: 6)
            let baseCrop = try pixelCropBytes(basePixels, rect: crop)
            let animatedCrop = try pixelCropBytes(animatedPixels, rect: crop)
            let reducedCrop = try pixelCropBytes(reducedPixels, rect: crop)
            if actor.eventID == renderedTarget {
                #expect(animatedCrop != baseCrop)
                #expect(reducedCrop != baseCrop)
                #expect(animatedCrop != reducedCrop)
            } else {
                #expect(animatedCrop == baseCrop)
                #expect(reducedCrop == baseCrop)
            }
        }
    }

    @Test("material presentation identity is byte exact and opacity clamps")
    func materialPresentationIdentityAndOpacityClamp() throws {
        let inputs = makeInputs(actorCount: 1, family: .outline)
        let eventID = inputs.recipe.actors[0].eventID
        let renderer = MaterialRenderer()
        let base = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .lowContrast,
            configuration: .init(scale: 1, supersampling: 2)
        )
        let explicitIdentity = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                actorPresentations: [eventID: .init(opacity: 1, rigidRotation: 0)]
            )
        )
        let overbright = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                actorPresentations: [eventID: .init(opacity: 7, rigidRotation: 0)]
            )
        )
        let invisible = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .lowContrast,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                actorPresentations: [eventID: .init(opacity: -4, rigidRotation: 0)]
            )
        )
        let backgroundOnly = try renderer.render(
            recipe: CompositionRecipe(
                daySeed: inputs.recipe.daySeed,
                grammar: inputs.recipe.grammar,
                viewport: inputs.recipe.viewport,
                actors: []
            ),
            material: inputs.material,
            background: .lowContrast,
            configuration: .init(scale: 1, supersampling: 2)
        )

        #expect(explicitIdentity.fullScreen.pngData == base.fullScreen.pngData)
        #expect(explicitIdentity.calendarTile.pngData == base.calendarTile.pngData)
        #expect(overbright.fullScreen.pngData == base.fullScreen.pngData)
        #expect(invisible.fullScreen.pngData == backgroundOnly.fullScreen.pngData)
        #expect(invisible.calendarTile.pngData == backgroundOnly.calendarTile.pngData)
    }

    @Test("material presentation rejects the sorted first unknown identity before its values")
    func materialPresentationUnknownKeysFailClosedFirst() throws {
        let inputs = makeInputs(actorCount: 2, family: .gradient)

        do {
            _ = try MaterialRenderer().render(
                recipe: inputs.recipe,
                material: inputs.material,
                background: .dark,
                configuration: .init(
                    scale: 1,
                    actorPresentations: [
                        "unknown-z": .init(opacity: 1, rigidRotation: 0),
                        "unknown-a": .init(opacity: .nan, rigidRotation: .infinity),
                    ]
                )
            )
            Issue.record("Expected unknown actor presentation failure")
        } catch MaterialRendererError.unknownActorPresentation(let eventID) {
            #expect(eventID == "unknown-a")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("overlapping outlines share transformed support underlay ownership and final visibility")
    func outlinePresentationPropagatesThroughEveryOwnedLayer() throws {
        let inputs = makeAsymmetricOutlineInputs()
        let backID = inputs.recipe.actors[0].eventID
        let frontID = inputs.recipe.actors[1].eventID
        let backPresentation = MaterialActorPresentation(
            opacity: 0.48,
            rigidRotation: .pi / 2
        )
        let presentations = [
            backID: backPresentation,
            frontID: MaterialActorPresentation(opacity: 0.72, rigidRotation: -.pi / 5),
        ]
        let frontPresentation = try #require(presentations[frontID])
        let renderer = MaterialRenderer()
        let instrumentation = MaterialRenderInstrumentation()
        let transformed = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .dark,
            configuration: MaterialRenderConfiguration(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: instrumentation,
                presentationEvidenceRequest: .perActor,
                actorPresentations: presentations
            )
        )
        let evidence = try #require(transformed.presentationEvidence)
        let backEvidence = try #require(evidence.actors.first { $0.eventID == backID })
        let frontEvidence = try #require(evidence.actors.first { $0.eventID == frontID })

        #expect(instrumentation.preProjectionAuthorityAlphaPlanes.count == 2)
        #expect(instrumentation.preProjectionSupportAlphaPlanes.count == 2)
        let expectedSupport = try expectedPresentedSupportAlpha(
            recipe: inputs.recipe,
            material: inputs.material,
            presentations: presentations,
            actorIndex: 0
        )
        let actualSupport = instrumentation.preProjectionSupportAlphaPlanes[0]
        #expect(byteMismatchCount(actualSupport, expectedSupport.transformed) == 0)
        #expect(byteMismatchCount(actualSupport, expectedSupport.untransformed) > 100)
        #expect(Double(alphaPlaneSum(actualSupport))
            < Double(alphaPlaneSum(expectedSupport.fullOpacity)) * 0.55)

        let backIsolated = try rgba(backEvidence.isolated.fullScreen.pngData)
        let frontIsolated = try rgba(frontEvidence.isolated.fullScreen.pngData)
        let frontRemoved = try rgba(frontEvidence.removed.fullScreen.pngData)
        let expectedUnderlay = try compositedOverBackground(
            backEvidence.isolated.fullScreen.pngData,
            background: .dark
        )
        let underlayMaximumByteDelta = zip(frontRemoved.bytes, expectedUnderlay)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
        #expect(underlayMaximumByteDelta <= 2)

        let ownership = frontEvidence.projected.ownership
        #expect(ownership.ownerEventIDs == [backID, frontID])
        var overlappingPixels = 0
        var frontOwnedOverlap = 0
        for pixelIndex in 0..<(backIsolated.width * backIsolated.height) {
            let backAlpha = backIsolated.bytes[pixelIndex * 4 + 3]
            let frontAlpha = frontIsolated.bytes[pixelIndex * 4 + 3]
            guard backAlpha > 8, frontAlpha > 8 else { continue }
            overlappingPixels += 1
            if ownership.ownerLabels[pixelIndex] == 1 {
                frontOwnedOverlap += 1
                let counterfactual = Array(
                    ownership.counterfactualBackgroundRGBA[(pixelIndex * 4)..<(pixelIndex * 4 + 4)]
                )
                let removedPixel = Array(
                    frontRemoved.bytes[(pixelIndex * 4)..<(pixelIndex * 4 + 4)]
                )
                #expect(counterfactual == removedPixel)
            }
        }
        #expect(overlappingPixels > 100)
        #expect(frontOwnedOverlap == overlappingPixels)

        let invisibleBack = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .dark,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                actorPresentations: [
                    backID: .init(opacity: 0, rigidRotation: .pi / 2),
                    frontID: frontPresentation,
                ]
            )
        )
        let frontOnly = try renderer.render(
            recipe: CompositionRecipe(
                daySeed: inputs.recipe.daySeed,
                grammar: inputs.recipe.grammar,
                viewport: inputs.recipe.viewport,
                actors: [inputs.recipe.actors[1]]
            ),
            material: inputs.material,
            background: .dark,
            configuration: .init(
                scale: 1,
                supersampling: 2,
                actorPresentations: [frontID: frontPresentation]
            )
        )
        #expect(invisibleBack.fullScreen.pngData == frontOnly.fullScreen.pngData)
        #expect(invisibleBack.calendarTile.pngData == frontOnly.calendarTile.pngData)
    }

    @Test("explicit supersampled outline instrumentation preserves default output")
    func explicitSupportInstrumentationPreservesDefaultOutput() throws {
        let inputs = makeInputs(actorCount: 1, family: .outline)
        let renderer = MaterialRenderer()
        let ordinary = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .dark,
            configuration: .init(scale: 1, supersampling: 2)
        )

        let instrumentation = MaterialRenderInstrumentation()
        let observed = try renderer.render(
            recipe: inputs.recipe,
            material: inputs.material,
            background: .dark,
            configuration: MaterialRenderConfiguration(
                scale: 1,
                supersampling: 2,
                outlineVisibilityPlacement: .none,
                instrumentation: instrumentation
            )
        )
        #expect(instrumentation.preProjectionSupportAlphaPlanes.count
            == inputs.recipe.actors.count)
        #expect(ordinary.fullScreen.pngData == observed.fullScreen.pngData)
        #expect(ordinary.calendarTile.pngData == observed.calendarTile.pngData)
    }

    @Test("invalid actor mappings fail explicitly without borrowing another actor state")
    func invalidActorMappingsFailClosed() throws {
        let inputs = makeInputs(actorCount: 2, family: .gradient)
        let first = inputs.recipe.actors[0].eventID
        let second = inputs.recipe.actors[1].eventID
        let renderer = MotionRenderer()

        var missing = inputs.motion
        missing.removeValue(forKey: first)
        #expect(throws: MotionRendererError.missingMotionRecipe(first)) {
            _ = try renderer.frame(
                recipe: inputs.recipe,
                motionRecipes: missing,
                phase: 0.2,
                steps: .normal
            )
        }

        var mismatched = inputs.motion
        mismatched[first] = testMotion(eventID: second)
        #expect(throws: MotionRendererError.mismatchedMotionRecipe(
            expectedEventID: first,
            actualEventID: second
        )) {
            _ = try renderer.frame(
                recipe: inputs.recipe,
                motionRecipes: mismatched,
                phase: 0.2,
                steps: .normal
            )
        }

        #expect(throws: MotionRendererError.unknownTransition("unknown")) {
            _ = try renderer.frame(
                recipe: inputs.recipe,
                motionRecipes: inputs.motion,
                phase: 0.2,
                steps: .normal,
                transitions: ["unknown": .init(kind: .removal, progress: 0.5)]
            )
        }

        let duplicated = CompositionRecipe(
            daySeed: inputs.recipe.daySeed,
            grammar: inputs.recipe.grammar,
            viewport: inputs.recipe.viewport,
            actors: [inputs.recipe.actors[0], inputs.recipe.actors[0]]
        )
        #expect(throws: MotionRendererError.duplicateCompositionActor(first)) {
            _ = try renderer.frame(
                recipe: duplicated,
                motionRecipes: [first: try #require(inputs.motion[first])],
                phase: 0.2,
                steps: .normal
            )
        }

        do {
            _ = try MaterialRenderer().render(
                recipe: inputs.recipe,
                material: inputs.material,
                background: .dark,
                configuration: .init(
                    scale: 1,
                    actorPresentations: [first: .init(opacity: .nan, rigidRotation: 0)]
                )
            )
            Issue.record("Expected invalid actor presentation failure")
        } catch MaterialRendererError.invalidActorPresentation(let eventID) {
            #expect(eventID == first)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private extension ActorMotionRecipe {
    func pipe<T>(_ transform: (ActorMotionRecipe) throws -> T) rethrows -> T {
        try transform(self)
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maximumCount).map { start in
            Array(self[start..<Swift.min(start + maximumCount, count)])
        }
    }
}

private func approvedVisibleRecipes() throws -> [CompositionRecipe] {
    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent(
        "artifacts/day-objects-editorial-field/composition/composition-recipes-approved.json"
    ))
    return try JSONDecoder().decode(FrozenCompositionRecipeArchive.self, from: data)
        .fixtures.sorted { $0.fixtureIndex < $1.fixtureIndex }.map(\.recipe)
}

private func makeInputs(
    actorCount: Int,
    family: MaterialFamily
) -> (recipe: CompositionRecipe, material: DailyMaterialDNA, motion: [String: ActorMotionRecipe]) {
    let ids = Array(CorpusManifest.canonicalEventIDs.prefix(actorCount))
    let recipe = CompositionPlanner.make(daySeed: 0xBEEF, eventIDs: ids, viewport: .phone)
    return (
        recipe,
        MaterialDNA.fixture(
            daySeed: recipe.daySeed,
            eventIDs: recipe.actors.map(\.eventID),
            family: family,
            requestedColorCount: family == .solid ? 1 : 3
        ),
        MotionField.make(daySeed: recipe.daySeed, eventIDs: recipe.actors.map(\.eventID))
    )
}

private func makeSeparatedTransitionInputs() -> (
    recipe: CompositionRecipe,
    material: DailyMaterialDNA,
    motion: [String: ActorMotionRecipe]
) {
    let actors = [
        ActorCompositionRecipe(
            eventID: "transition-left",
            position: .init(x: 0.18, y: 0.5),
            diameter: 0.18,
            depth: 0.3,
            localBlur: 0,
            cropAllowance: 0,
            drawOrder: 0
        ),
        ActorCompositionRecipe(
            eventID: "transition-target",
            position: .init(x: 0.5, y: 0.5),
            diameter: 0.18,
            depth: 0.5,
            localBlur: 0,
            cropAllowance: 0,
            drawOrder: 1
        ),
        ActorCompositionRecipe(
            eventID: "transition-right",
            position: .init(x: 0.82, y: 0.5),
            diameter: 0.18,
            depth: 0.7,
            localBlur: 0,
            cropAllowance: 0,
            drawOrder: 2
        ),
    ]
    let recipe = CompositionRecipe(
        daySeed: 100,
        grammar: .openField,
        viewport: .phone,
        actors: actors
    )
    return (
        recipe,
        MaterialDNA.fixture(
            daySeed: recipe.daySeed,
            eventIDs: actors.map(\.eventID),
            family: .solid,
            requestedColorCount: 1
        ),
        MotionField.make(daySeed: recipe.daySeed, eventIDs: actors.map(\.eventID))
    )
}

private func makeAsymmetricOutlineInputs() -> (
    recipe: CompositionRecipe,
    material: DailyMaterialDNA
) {
    let eventIDs = ["outline-back", "outline-front"]
    let recipe = CompositionRecipe(
        daySeed: 104,
        grammar: .layeredOverlap,
        viewport: .phone,
        actors: [
            ActorCompositionRecipe(
                eventID: eventIDs[0],
                position: .init(x: 0.46, y: 0.5),
                diameter: 0.52,
                depth: 0.42,
                localBlur: 0.008,
                cropAllowance: 0,
                drawOrder: 0
            ),
            ActorCompositionRecipe(
                eventID: eventIDs[1],
                position: .init(x: 0.54, y: 0.5),
                diameter: 0.48,
                depth: 0.72,
                localBlur: 0.006,
                cropAllowance: 0,
                drawOrder: 1
            ),
        ]
    )
    let base = MaterialDNA.fixture(
        daySeed: recipe.daySeed,
        eventIDs: eventIDs,
        family: .outline,
        requestedColorCount: 1
    )
    let actors = base.actors.enumerated().map { index, actor in
        let outerCenter = CompositionPoint(
            x: index == 0 ? 0.31 : 0.69,
            y: index == 0 ? 0.42 : 0.58
        )
        let innerCenter = CompositionPoint(
            x: index == 0 ? 0.69 : 0.31,
            y: index == 0 ? 0.58 : 0.42
        )
        let contour = OrganicRadialContour(
            outerCenter: outerCenter,
            outerRadius: 0.47,
            innerCenter: innerCenter,
            innerRadius: 0.35,
            opacity: 1
        )
        return ActorMaterialRecipe(
            eventID: actor.eventID,
            family: actor.family,
            mutation: actor.mutation,
            colors: actor.colors,
            fields: actor.fields,
            baseOpacity: actor.baseOpacity,
            edgeSoftness: actor.edgeSoftness,
            contourWidth: 0.12,
            contourCount: 1,
            counterformRadius: nil,
            counterformSoftness: 0,
            organicTopology: OrganicRadialTopology(
                outerCenter: outerCenter,
                outerRadius: contour.outerRadius,
                innerCenter: innerCenter,
                innerRadius: contour.innerRadius,
                contours: [contour]
            )
        )
    }
    return (
        recipe,
        DailyMaterialDNA(
            daySeed: base.daySeed,
            family: base.family,
            accentMutation: base.accentMutation,
            requestedColorCount: base.requestedColorCount,
            actors: actors
        )
    )
}

private func actor(_ eventID: String, depth: Double, drawOrder: Int) -> ActorCompositionRecipe {
    ActorCompositionRecipe(
        eventID: eventID,
        position: .init(x: 0.5, y: 0.5),
        diameter: 0.18,
        depth: depth,
        localBlur: 0.01,
        cropAllowance: 0,
        drawOrder: drawOrder
    )
}

private func testMotion(
    eventID: String,
    phase: Double = 0.17,
    directionBias: Double = 0.2,
    amplitude: Double = 0.1,
    depthParallax: Double = 0.05
) -> ActorMotionRecipe {
    ActorMotionRecipe(
        eventID: eventID,
        period: 140,
        phase: phase,
        directionBias: directionBias,
        amplitude: amplitude,
        speedRatio: 1,
        breathingAmplitude: 0.04,
        depthParallax: depthParallax
    )
}

private func focusProfile(_ depth: Double) -> Double {
    0.008 * pow(abs(2 * min(1, max(0, depth)) - 1), 2)
}

private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

private func actorPixelRect(_ actor: ActorCompositionRecipe, padding: Int) -> PixelRect {
    let radius = Int(ceil(actor.diameter * EditorialViewport.phone.shortSide * 0.5)) + padding
    let centerX = Int((actor.position.x * EditorialViewport.phone.width).rounded())
    let centerY = Int((actor.position.y * EditorialViewport.phone.height).rounded())
    return PixelRect(
        x: centerX - radius,
        y: centerY - radius,
        width: radius * 2,
        height: radius * 2
    )
}

private func pixelCropBytes(_ data: Data, rect: PixelRect) throws -> [UInt8] {
    let decoded = try rgba(data)
    var result = [UInt8]()
    result.reserveCapacity(rect.width * rect.height * 4)
    for y in rect.y..<(rect.y + rect.height) {
        for x in rect.x..<(rect.x + rect.width) {
            let offset = (y * decoded.width + x) * 4
            result.append(contentsOf: decoded.bytes[offset..<(offset + 4)])
        }
    }
    return result
}

private func expectedPresentedSupportAlpha(
    recipe: CompositionRecipe,
    material: DailyMaterialDNA,
    presentations: [String: MaterialActorPresentation],
    actorIndex: Int
) throws -> (transformed: Data, untransformed: Data, fullOpacity: Data) {
    let capture = MaterialRawSceneCapture()
    _ = try MaterialRenderer().render(
        recipe: recipe,
        material: material,
        background: .dark,
        configuration: MaterialRenderConfiguration(
            scale: 2,
            outlineVisibilityPlacement: .none,
            rawSceneCapture: capture,
            presentationScale: 1,
            actorPresentations: presentations
        )
    )
    let captured = try #require(capture.actorLayers[safe: actorIndex])
    let presentation = try #require(presentations[recipe.actors[actorIndex].eventID])
    return (
        try placedSupportAlpha(captured, presentation: presentation),
        try placedSupportAlpha(
            captured,
            presentation: .init(opacity: presentation.opacity, rigidRotation: 0)
        ),
        try placedSupportAlpha(
            captured,
            presentation: .init(opacity: 1, rigidRotation: presentation.rigidRotation)
        )
    )
}

private func placedSupportAlpha(
    _ captured: MaterialCapturedActorLayer,
    presentation: MaterialActorPresentation
) throws -> Data {
    let sourceWidth = Int(EditorialViewport.phone.width) * 2
    let sourceHeight = Int(EditorialViewport.phone.height) * 2
    let source = try bitmapContext(width: sourceWidth, height: sourceHeight)
    source.clear(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
    source.saveGState()
    source.setAlpha(presentation.opacity)
    source.translateBy(x: captured.presentationCenter.x, y: captured.presentationCenter.y)
    source.rotate(by: presentation.rigidRotation)
    source.draw(
        captured.presentationSupport,
        in: captured.presentationSupportDrawRect.offsetBy(
            dx: -captured.presentationCenter.x,
            dy: -captured.presentationCenter.y
        )
    )
    source.restoreGState()
    let sourceImage = try #require(source.makeImage())
    let output = try bitmapContext(
        width: Int(EditorialViewport.phone.width),
        height: Int(EditorialViewport.phone.height)
    )
    output.draw(sourceImage, in: CGRect(
        x: 0,
        y: 0,
        width: EditorialViewport.phone.width,
        height: EditorialViewport.phone.height
    ))
    return try alphaPlane(output)
}

private func compositedOverBackground(
    _ sourceData: Data,
    background: BackgroundCondition
) throws -> [UInt8] {
    let source = try decodedPNG(sourceData)
    let context = try bitmapContext(width: source.width, height: source.height)
    let color = MaterialRenderer.backgroundColor(for: background)
    context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height))
    context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
    guard let data = context.data else {
        throw MaterialRendererError.cannotCreateBitmap(source.width, source.height)
    }
    return Array(UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self),
        count: source.width * source.height * 4
    ))
}

private func bitmapContext(width: Int, height: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else { throw MaterialRendererError.cannotCreateBitmap(width, height) }
    context.interpolationQuality = .high
    return context
}

private func alphaPlane(_ context: CGContext) throws -> Data {
    guard let data = context.data else {
        throw MaterialRendererError.cannotCreateBitmap(context.width, context.height)
    }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var alpha = Data()
    alpha.reserveCapacity(context.width * context.height)
    for y in 0..<context.height {
        for x in 0..<context.width {
            alpha.append(bytes[y * context.bytesPerRow + x * 4 + 3])
        }
    }
    return alpha
}

private func alphaPlaneSum(_ data: Data) -> Int {
    data.reduce(0) { $0 + Int($1) }
}

private func byteMismatchCount(_ lhs: Data, _ rhs: Data) -> Int {
    guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
    return zip(lhs, rhs).reduce(into: 0) { count, pair in
        if pair.0 != pair.1 { count += 1 }
    }
}

private func decodedPNG(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw MaterialRendererError.cannotCreateImage }
    return image
}

private func rgba(_ data: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
    let image = try decodedPNG(data)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else { throw MaterialRendererError.cannotCreateBitmap(image.width, image.height) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (bytes, image.width, image.height)
}

private func alphaSum(_ data: Data) throws -> Double {
    let decoded = try rgba(data)
    return stride(from: 3, to: decoded.bytes.count, by: 4).reduce(0) {
        $0 + Double(decoded.bytes[$1])
    }
}

private func alphaCentroidVector(_ data: Data, center: CGPoint) throws -> CGPoint {
    let decoded = try rgba(data)
    var weightedX = 0.0
    var weightedY = 0.0
    var weight = 0.0
    for y in 0..<decoded.height {
        for x in 0..<decoded.width {
            let alpha = Double(decoded.bytes[(y * decoded.width + x) * 4 + 3])
            weightedX += (Double(x) + 0.5) * alpha
            weightedY += (Double(y) + 0.5) * alpha
            weight += alpha
        }
    }
    return CGPoint(
        x: weightedX / weight - center.x,
        y: weightedY / weight - center.y
    )
}

private func wrappedAngle(_ value: Double) -> Double {
    let turn = 2 * Double.pi
    let wrapped = (value + Double.pi).truncatingRemainder(dividingBy: turn)
    return (wrapped < 0 ? wrapped + turn : wrapped) - Double.pi
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
