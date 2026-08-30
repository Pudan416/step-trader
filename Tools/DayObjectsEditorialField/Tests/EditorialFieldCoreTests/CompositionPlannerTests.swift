import Foundation
import Testing
@testable import EditorialFieldCore

@Suite("Editorial composition planner")
struct CompositionPlannerTests {
    private let ids = CorpusManifest.canonicalEventIDs
    private static let stressRecipes = (UInt64(0)..<2_048).map {
        CompositionPlanner.make(
            daySeed: $0,
            eventIDs: CorpusManifest.canonicalEventIDs,
            viewport: .phone
        )
    }

    @Test("retained actors keep their complete recipe through reorder, insertion, and removal")
    func retainedActorsDoNotReroll() {
        let full = CompositionPlanner.make(daySeed: 77, eventIDs: ids, viewport: .phone)
        let prefix = CompositionPlanner.make(daySeed: 77, eventIDs: Array(ids.prefix(5)), viewport: .phone)
        let reordered = CompositionPlanner.make(daySeed: 77, eventIDs: ids.reversed(), viewport: .phone)
        let removedIDs = ids.enumerated().compactMap { [1, 4, 8].contains($0.offset) ? nil : $0.element }
        let removed = CompositionPlanner.make(daySeed: 77, eventIDs: removedIDs, viewport: .phone)

        for id in ids.prefix(5) {
            #expect(full.actor(id) == prefix.actor(id))
        }
        for id in ids {
            #expect(full.actor(id) == reordered.actor(id))
        }
        for id in removedIDs {
            #expect(full.actor(id) == removed.actor(id))
        }
    }

    @Test("planner admits unique identities in stable priority and caps the scene at ten actors")
    func admissionIsStableAndBounded() {
        let extras = ["external-z", "external-a"]
        let input = Array(ids.reversed()) + extras + [ids[2], ids[2]]
        let recipe = CompositionPlanner.make(daySeed: 91, eventIDs: input, viewport: .phone)

        #expect(recipe.actors.count == 10)
        #expect(recipe.actors.map(\.eventID) == ids)
        #expect(Set(recipe.actors.map(\.eventID)).count == recipe.actors.count)
    }

    @Test("non-equal grammars preserve a broad continuous scale hierarchy")
    func broadScaleIsContinuousAndNotEqualSized() {
        for recipe in Self.stressRecipes {
            guard recipe.grammar != .equalScaleStudy else { continue }
            for count in 4...10 {
                let active = recipeKeepingPrefix(count, from: recipe)
                #expect(active.minimumDiameter >= 0.06)
                #expect(active.maximumDiameter <= 0.75)
                #expect(active.maximumDiameter / active.minimumDiameter >= 3)
                #expect((active.actors.map(\.depth).max() ?? 0) - (active.actors.map(\.depth).min() ?? 0) >= 0.44)
                let depthBands = Set(active.actors.map { actor -> Int in
                    if actor.depth < 0.28 { return 0 }
                    if actor.depth < 0.68 { return 1 }
                    return 2
                })
                #expect(depthBands == Set([0, 1, 2]))
            }
            #expect(Set(recipe.actors.map { Int(($0.diameter * 10_000).rounded()) }).count >= 7)
        }
    }

    @Test("the corpus can span tiny through cropped foreground without requiring a giant")
    func continuousHierarchyHasEditorialBreadth() {
        var foundTinyToCroppedForeground = false
        var foundSceneWithoutGiant = false

        for recipe in Self.stressRecipes {
            guard recipe.grammar != .equalScaleStudy else { continue }

            let hasTiny = recipe.actors.contains { $0.diameter <= 0.10 }
            let hasCroppedForeground = recipe.actors.contains {
                $0.depth >= 0.68 && $0.diameter >= 0.52 && recipe.cropFraction(of: $0) >= 0.15
            }
            let occupiedBands = Set(recipe.actors.map { actor -> Int in
                switch actor.diameter {
                case ..<0.12: 0
                case ..<0.22: 1
                case ..<0.38: 2
                case ..<0.55: 3
                default: 4
                }
            })

            foundTinyToCroppedForeground = foundTinyToCroppedForeground
                || (hasTiny && hasCroppedForeground && occupiedBands.count >= 4)
            foundSceneWithoutGiant = foundSceneWithoutGiant || recipe.maximumDiameter < 0.60
        }

        #expect(foundTinyToCroppedForeground)
        #expect(foundSceneWithoutGiant)
    }

    @Test("visible pairs form an asymmetric counterpoint away from the top cluster")
    func visiblePairsAvoidTopCluster() {
        let pairs = CorpusManifest.visibleV1().breadth.filter { $0.actorCount == 2 }
        #expect(pairs.count == 2)

        for fixture in pairs {
            let recipe = CompositionPlanner.make(
                daySeed: fixture.seed,
                eventIDs: fixture.eventIDs,
                viewport: .phone
            )
            let extent = occupiedVerticalExtent(recipe)
            let centerY = recipe.actors.map(\.position.y).reduce(0, +) / Double(recipe.actors.count)
            #expect((0.30...0.70).contains(centerY), "fixture \(fixture.index) center y: \(centerY)")
            #expect(extent.bottom - extent.top >= 0.24, "fixture \(fixture.index) is too compact: \(extent)")
        }
    }

    @Test("visible single-actor fields use distinct regions, scale, and depth")
    func visibleSinglesCarryDistinctEditorialRoles() {
        let fixtures = Array(CorpusManifest.visibleV1().breadth.prefix(2))
        let recipes = fixtures.map {
            CompositionPlanner.make(daySeed: $0.seed, eventIDs: $0.eventIDs, viewport: .phone)
        }
        #expect(recipes.allSatisfy { $0.actors.count == 1 })

        let first = recipes[0].actors[0]
        let second = recipes[1].actors[0]
        let regionDistance = CompositionGeometry.distance(
            from: first.position,
            to: second.position,
            viewport: .phone
        )
        let scaleRatio = max(first.diameter, second.diameter) / min(first.diameter, second.diameter)
        #expect(regionDistance >= 0.45, "single-actor region distance: \(regionDistance)")
        #expect(scaleRatio >= 1.18, "single-actor scale ratio: \(scaleRatio)")
        #expect(abs(first.depth - second.depth) >= 0.08)

        for recipe in recipes {
            #expect(actorsCenteredInTile(recipe).count == 1)
            #expect(tileVisibleVerticalFraction(recipe.actors[0], in: recipe) >= 0.75)
        }
    }

    @Test("breadth two through five retain every sparse identity in the tile")
    func sparseBreadthTilesRetainEverySilhouette() {
        let breadth = CorpusManifest.visibleV1().breadth
        for index in 2...5 {
            let fixture = breadth[index]
            let recipe = CompositionPlanner.make(
                daySeed: fixture.seed,
                eventIDs: fixture.eventIDs,
                viewport: .phone
            )
            let centeredIDs = Set(actorsCenteredInTile(recipe).map(\.eventID))

            #expect(
                centeredIDs == Set(fixture.eventIDs),
                "breadth \(index) centered IDs: \(centeredIDs); actors: \(recipe.actors)"
            )
            for actor in recipe.actors {
                let visibleFraction = tileVisibleVerticalFraction(actor, in: recipe)
                #expect(
                    visibleFraction >= 0.75,
                    "breadth \(index) actor \(actor.eventID) is only \(visibleFraction) visible"
                )
            }
        }
    }

    @Test("breadth fixture four breaks the diagonal with a readable cross-depth neighbour")
    func breadthFourUsesCrossDepthCounterpoint() {
        let fixture = CorpusManifest.visibleV1().breadth[4]
        let recipe = CompositionPlanner.make(
            daySeed: fixture.seed,
            eventIDs: fixture.eventIDs,
            viewport: .phone
        )

        let pairs = readableCrossDepthPairs(in: recipe)
        #expect(!pairs.isEmpty, "fixture 4 has no readable cross-depth pair: \(recipe.actors)")
        #expect(
            normalizedTriangleArea(recipe) >= 0.18,
            "fixture 4 remains diagonally linear: \(recipe.actors)"
        )

        let tileHeight = recipe.viewport.width / recipe.viewport.height
        let tileTop = (1 - tileHeight) * 0.5
        let tileBottom = 1 - tileTop
        let centersInTile = recipe.actors.filter { (tileTop...tileBottom).contains($0.position.y) }
        let actorsIntersectingTile = recipe.actors.filter { actor in
            let radiusY = actor.diameter * 0.5 * recipe.viewport.shortSide / recipe.viewport.height
            return actor.position.y + radiusY >= tileTop && actor.position.y - radiusY <= tileBottom
        }
        #expect(!centersInTile.isEmpty, "fixture 4 tile has no actor center")
        #expect(actorsIntersectingTile.count >= 2, "fixture 4 tile sees only \(actorsIntersectingTile)")
    }

    @Test("listed sparse breadth tiles retain readable editorial relationships")
    func sparseBreadthTilesRetainEditorialRelationships() {
        let breadth = CorpusManifest.visibleV1().breadth
        let single = CompositionPlanner.make(
            daySeed: breadth[1].seed,
            eventIDs: breadth[1].eventIDs,
            viewport: .phone
        )
        let singleCenters = actorsCenteredInTile(single)
        #expect(singleCenters.map(\.eventID) == single.actors.map(\.eventID))
        #expect(single.actors[0].diameter >= 0.35)
        #expect((0.12...0.88).contains(tileLocalY(single.actors[0], in: single)))
        #expect((0.12...0.88).contains(single.actors[0].position.x))

        let triple = CompositionPlanner.make(
            daySeed: breadth[4].seed,
            eventIDs: breadth[4].eventIDs,
            viewport: .phone
        )
        let tripleCenters = actorsCenteredInTile(triple)
        #expect(tripleCenters.map(\.eventID) == triple.actors.map(\.eventID))
        #expect(horizontalSpan(tripleCenters) >= 0.55)
        #expect(tileVerticalSpan(tripleCenters, in: triple) >= 0.35)
        #expect(!readableCrossDepthPairs(in: triple).isEmpty)
    }

    @Test("sparse continuity tiles retain identities and two-axis balance")
    func sparseContinuityTilesRetainVisibleIdentities() {
        let continuity = CorpusManifest.visibleV1().continuity
        let stageIndices = [0, 1, 2, 3, 6]
        let minimumReadableCenters = [1, 2, 3, 3, 3]
        var previousVisibleIDs: Set<String> = []
        var fiveActorRecipe: CompositionRecipe?

        for (offset, stageIndex) in stageIndices.enumerated() {
            let stage = continuity.stages[stageIndex]
            let recipe = CompositionPlanner.make(
                daySeed: continuity.seed,
                eventIDs: stage.eventIDs,
                viewport: .phone
            )
            let centered = actorsCenteredInTile(recipe)
            let visibleIDs = Set(centered.map(\.eventID))

            #expect(
                centered.count >= minimumReadableCenters[offset],
                "stage \(stageIndex) centered: \(centered.map(\.eventID)); actors: \(recipe.actors)"
            )
            #expect(previousVisibleIDs.isSubset(of: visibleIDs))
            #expect(Set(stage.eventIDs.prefix(min(3, stage.actorCount))).isSubset(of: visibleIDs))
            if stage.actorCount >= 2 {
                #expect(horizontalSpan(centered) >= 0.50)
                #expect(tileVerticalSpan(centered, in: recipe) >= 0.35)
            }
            if stageIndex == 3 || stageIndex == 6 {
                let lowerCounterweight = recipe.actors.first { $0.eventID == ids[4] }!
                #expect(tileVisibleVerticalFraction(lowerCounterweight, in: recipe) >= 0.30)
            }

            if stageIndex == 3 {
                fiveActorRecipe = recipe
            } else if stageIndex == 6 {
                #expect(recipe.actors == fiveActorRecipe?.actors)
            }
            previousVisibleIDs = visibleIDs
        }
    }

    @Test("continuity count ten carries two independent cross-depth overlaps")
    func continuityTenUsesIndependentDepthPairs() {
        let continuity = CorpusManifest.visibleV1().continuity
        let stage = continuity.stages.first { $0.actorCount == 10 }!
        let recipe = CompositionPlanner.make(
            daySeed: continuity.seed,
            eventIDs: stage.eventIDs,
            viewport: .phone
        )

        let pairs = readableCrossDepthPairs(in: recipe)
        let hasIndependentPairs = pairs.indices.contains { first in
            pairs.indices.contains { second in
                second > first
                    && Set([pairs[first].0, pairs[first].1, pairs[second].0, pairs[second].1]).count == 4
            }
        }
        #expect(hasIndependentPairs, "continuity count 10 depth pairs: \(pairs)")

        let thirds = Set(recipe.actors.map { min(2, max(0, Int($0.position.y * 3))) })
        #expect(thirds == Set([0, 1, 2]))
        let extent = occupiedVerticalExtent(recipe)
        #expect(extent.top <= 0.02)
        #expect(extent.bottom >= 0.98)
        #expect(CompositionGuardrails.evaluate(recipe).compactCluster <= 0.35)
    }

    @Test("dense visible fields use independent cropped edges and useful depth accents")
    func visibleDenseFieldsCarryAsymmetricDepth() {
        let denseFixtures = CorpusManifest.visibleV1().breadth.filter {
            $0.actorCount >= 7 && EditorialGrammar.select(daySeed: $0.seed) != .equalScaleStudy
        }
        #expect(denseFixtures.count == 3)

        for fixture in denseFixtures {
            let recipe = CompositionPlanner.make(
                daySeed: fixture.seed,
                eventIDs: fixture.eventIDs,
                viewport: .phone
            )
            let cropped = recipe.actors.filter { recipe.cropFraction(of: $0) >= 0.12 }
            let croppedEdges = Set(cropped.compactMap { croppedEdge(of: $0, in: recipe) })
            #expect(cropped.count >= 2, "fixture \(fixture.index) has only \(cropped.count) intentional crops")
            #expect(croppedEdges.count >= 2, "fixture \(fixture.index) repeats edge \(croppedEdges)")

            let extent = occupiedVerticalExtent(recipe)
            #expect(extent.top <= 0.02, "fixture \(fixture.index) top extent \(extent.top)")
            #expect(extent.bottom >= 0.98, "fixture \(fixture.index) bottom extent \(extent.bottom)")
            #expect(recipe.actors.contains { $0.diameter <= 0.105 && recipe.cropFraction(of: $0) < 0.10 })

            let depthBands = Set(recipe.actors.map { actor -> Int in
                if actor.depth < 0.28 { return 0 }
                if actor.depth < 0.68 { return 1 }
                return 2
            })
            #expect(depthBands == Set([0, 1, 2]))
        }
    }

    @Test("non-equal ten-actor fields sustain an extreme but continuous hierarchy")
    func tenActorHierarchyKeepsExtremeRange() {
        for recipe in Self.stressRecipes where recipe.grammar != .equalScaleStudy {
            #expect(recipe.maximumDiameter / recipe.minimumDiameter >= 4.5)

            let occupiedBands = Set(recipe.actors.map { actor -> Int in
                switch actor.diameter {
                case ...0.105: 0
                case ...0.18: 1
                case ...0.34: 2
                default: 3
                }
            })
            #expect(occupiedBands == Set([0, 1, 2, 3]))
            #expect(Set(recipe.actors.map { Int(($0.diameter * 10_000).rounded()) }).count >= 8)
        }
    }

    @Test("the rare equal-scale grammar remains related without becoming equal-sized")
    func equalScaleStudyRetainsEditorialVariation() {
        for recipe in Self.stressRecipes where recipe.grammar == .equalScaleStudy {
            #expect(recipe.maximumDiameter / recipe.minimumDiameter >= 1.60)
        }
    }

    @Test("breadth ten equal-scale field avoids rhythmic overlapping bead rows")
    func breadthTenEqualScaleAvoidsRhythmicOverlapRows() {
        let fixture = CorpusManifest.visibleV1().breadth[10]
        let recipe = CompositionPlanner.make(
            daySeed: fixture.seed,
            eventIDs: fixture.eventIDs,
            viewport: .phone
        )

        let rows = rhythmicOverlapTriples(in: recipe)
        #expect(rows.isEmpty, "breadth 10 rhythmic overlap rows: \(rows)")
    }

    @Test("breadth ten equal-scale field retains its readable editorial field")
    func breadthTenEqualScaleRetainsReadableEditorialField() {
        let fixture = CorpusManifest.visibleV1().breadth[10]
        let recipe = CompositionPlanner.make(
            daySeed: fixture.seed,
            eventIDs: fixture.eventIDs,
            viewport: .phone
        )

        #expect(recipe.grammar == .equalScaleStudy)
        #expect(recipe.actors.count == 10)
        #expect(recipe.actors.map(\.eventID) == fixture.eventIDs)
        #expect(recipe.minimumDiameter >= 0.18)
        #expect(recipe.actors.allSatisfy { recipe.cropFraction(of: $0) <= 0.35 })
        #expect(recipe.actors.filter { recipe.cropFraction(of: $0) >= 0.12 }.count >= 3)
        #expect(Set(recipe.actors.map { min(2, max(0, Int($0.position.y * 3))) }) == Set([0, 1, 2]))
        let extent = occupiedVerticalExtent(recipe)
        #expect(extent.top <= 0.02)
        #expect(extent.bottom >= 0.98)
        #expect(CompositionGuardrails.evaluate(recipe).compactCluster <= 0.35)

        let renderedOrder = recipe.actors.sorted { $0.drawOrder < $1.drawOrder }.map(\.eventID)
        let expectedOrder = recipe.actors.sorted {
            $0.depth == $1.depth ? $0.eventID < $1.eventID : $0.depth < $1.depth
        }.map(\.eventID)
        #expect(renderedOrder == expectedOrder)
    }

    @Test("distributed grammars occupy every vertical third with six or more actors")
    func distributedGrammarsUseAllVerticalThirds() {
        for recipe in Self.stressRecipes {
            guard recipe.grammar == .openField || recipe.grammar == .depthScatter else { continue }
            for count in 6...10 {
                let active = recipeKeepingPrefix(count, from: recipe)
                let thirds = Set(active.actors.map { min(2, max(0, Int($0.position.y * 3))) })
                #expect(thirds == Set([0, 1, 2]))
            }
        }
    }

    @Test("visible overlap grammars intersect in rendered phone geometry")
    func visibleOverlapUsesPhoneShortSideSpace() {
        for fixture in CorpusManifest.visibleV1().breadth where fixture.actorCount > 1 {
            let recipe = CompositionPlanner.make(
                daySeed: fixture.seed,
                eventIDs: fixture.eventIDs,
                viewport: .phone
            )
            if recipe.grammar == .layeredOverlap || recipe.grammar == .transparentPrint {
                #expect(
                    renderedIntersectionCount(recipe) > 0,
                    "fixture \(fixture.index) has no rendered overlap: \(recipe.actors)"
                )
            }
        }
    }

    @Test("dense and depth grammars keep rendered intersections across 2,048 seeds")
    func stressOverlapUsesPhoneShortSideSpace() {
        for recipe in Self.stressRecipes
        where recipe.grammar == .layeredOverlap
            || recipe.grammar == .transparentPrint
            || recipe.grammar == .depthScatter
        {
            #expect(renderedIntersectionCount(recipe) > 0)
        }
    }

    @Test("cropped foreground keeps a genuinely cropped near actor and readable counterweight")
    func croppedForegroundHasCounterweight() {
        for recipe in Self.stressRecipes {
            guard recipe.grammar == .croppedForeground else { continue }

            #expect(recipe.actors.contains {
                $0.depth >= 0.68
                    && $0.diameter >= 0.52
                    && recipe.cropFraction(of: $0) >= 0.15
                    && recipe.cropFraction(of: $0) <= $0.cropAllowance + 0.02
            })
            #expect(recipe.actors.contains {
                $0.depth < 0.68
                    && $0.diameter >= 0.14
                    && recipe.cropFraction(of: $0) < 0.08
            })
        }
    }

    @Test("large foreground remains softer than the sharpest middle-plane actor")
    func foregroundCarriesRelativeDefocus() {
        for recipe in Self.stressRecipes {
            guard let foreground = recipe.actors.filter({ $0.depth >= 0.68 && $0.diameter >= 0.52 })
                .max(by: { $0.diameter < $1.diameter }),
                let sharpMiddle = recipe.actors.filter({ $0.depth >= 0.28 && $0.depth < 0.68 })
                .min(by: { $0.localBlur < $1.localBlur }) else { continue }

            #expect(foreground.localBlur > sharpMiddle.localBlur)
        }
    }

    @Test("forbidden grid, ring, and flower controls score as catastrophic")
    func guardrailNegativeControlsRejectForbiddenPatterns() {
        let gridPoints = [0.70, 1.45].flatMap { y in
            [0.14, 0.32, 0.50, 0.68, 0.86].map { CompositionPoint(x: $0, y: y) }
        }
        let grid = controlRecipe(shortSidePoints: gridPoints, diameter: 0.12)
        let gridScores = CompositionGuardrails.evaluate(grid)
        #expect(gridScores.grid >= 0.95)
        #expect(gridScores.row >= 0.95)
        #expect(gridScores.equalSpacing >= 0.95)
        #expect(gridScores.equalScale >= 0.95)

        let ringCenter = CompositionPoint(x: 0.50, y: 1.08)
        let ringPoints = (0..<10).map { index -> CompositionPoint in
            let angle = Double(index) / 10 * 2 * Double.pi
            return CompositionPoint(
                x: ringCenter.x + cos(angle) * 0.36,
                y: ringCenter.y + sin(angle) * 0.36
            )
        }
        let ringScores = CompositionGuardrails.evaluate(
            controlRecipe(shortSidePoints: ringPoints, diameter: 0.12)
        )
        #expect(ringScores.ring >= 0.95)
        #expect(ringScores.equalSpacing >= 0.95)

        let flowerPoints = (0..<10).map { index -> CompositionPoint in
            let angle = Double(index) / 10 * 2 * Double.pi
            let radius = index.isMultiple(of: 2) ? 0.16 : 0.22
            return CompositionPoint(
                x: ringCenter.x + cos(angle) * radius,
                y: ringCenter.y + sin(angle) * radius
            )
        }
        let flowerScores = CompositionGuardrails.evaluate(
            controlRecipe(shortSidePoints: flowerPoints, diameter: 0.48)
        )
        #expect(flowerScores.commonFocalPoint >= 0.95)
        #expect(flowerScores.compactCluster >= 0.55)
    }

    @Test("continuity-prefix removals preserve actors and achievable composition guarantees")
    func continuityOneStepRemovalsRemainComposed() {
        let fixture = CorpusManifest.visibleV1().continuity
        for beforeCount in [2, 3, 5, 7, 10] {
            let beforeIDs = Array(CorpusManifest.canonicalEventIDs.prefix(beforeCount))
            let afterIDs = Array(beforeIDs.dropLast())
            let before = CompositionPlanner.make(daySeed: fixture.seed, eventIDs: beforeIDs, viewport: .phone)
            let after = CompositionPlanner.make(daySeed: fixture.seed, eventIDs: afterIDs, viewport: .phone)

            for id in afterIDs {
                #expect(before.actor(id) == after.actor(id))
            }
            if after.actors.count >= 4, after.grammar != .equalScaleStudy {
                #expect(after.maximumDiameter / after.minimumDiameter >= 3)
                let depthBands = Set(after.actors.map { actor -> Int in
                    if actor.depth < 0.28 { return 0 }
                    if actor.depth < 0.68 { return 1 }
                    return 2
                })
                #expect(depthBands == Set([0, 1, 2]))
            }
            if after.actors.count >= 6,
                after.grammar == .openField || after.grammar == .depthScatter
            {
                let thirds = Set(after.actors.map { min(2, max(0, Int($0.position.y * 3))) })
                #expect(thirds == Set([0, 1, 2]))
            }
        }
    }

    @Test("arbitrary identity sets stay immutable, finite, visible, and non-catastrophic")
    func arbitraryIdentitySetsKeepBoundedActorDNA() {
        // Universal 3:1/all-thirds assertions are intentionally absent here:
        // they are mathematically incompatible with immutable final actor values.
        // Arbitrary sets retain identity and must still avoid invalid/catastrophic geometry.
        let externalIDs = (0..<10).map { "external-editorial-\($0)" }
        let full = CompositionPlanner.make(daySeed: 24, eventIDs: externalIDs, viewport: .phone)
        let subsetIDs = [externalIDs[0], externalIDs[2], externalIDs[3], externalIDs[6], externalIDs[8], externalIDs[9]]
        let subset = CompositionPlanner.make(daySeed: 24, eventIDs: subsetIDs.reversed(), viewport: .phone)

        for id in subsetIDs {
            #expect(full.actor(id) == subset.actor(id))
        }
        for actor in subset.actors {
            #expect(actor.position.x.isFinite && actor.position.y.isFinite)
            #expect((0...1).contains(actor.position.x) && (0...1).contains(actor.position.y))
            #expect((0.06...0.75).contains(actor.diameter))
            #expect((0...1).contains(actor.depth))
            #expect(actor.localBlur.isFinite)
            #expect((0...0.45).contains(actor.cropAllowance))
            #expect(subset.cropFraction(of: actor) <= actor.cropAllowance + 0.07)
        }
        let scores = CompositionGuardrails.evaluate(subset)
        #expect(scores.grid < 0.95)
        #expect(scores.ring < 0.95)
        #expect(scores.commonFocalPoint < 0.95)
        #expect(scores.compactCluster < 0.95)

        let canonicalFull = CompositionPlanner.make(daySeed: 24, eventIDs: ids, viewport: .phone)
        let canonicalSubsetIDs = [ids[0], ids[2], ids[4], ids[5], ids[7], ids[9]]
        let canonicalSubset = CompositionPlanner.make(
            daySeed: 24,
            eventIDs: canonicalSubsetIDs,
            viewport: .phone
        )
        for id in canonicalSubsetIDs {
            #expect(canonicalFull.actor(id) == canonicalSubset.actor(id))
        }
        let canonicalScores = CompositionGuardrails.evaluate(canonicalSubset)
        #expect(canonicalScores.grid < 0.95)
        #expect(canonicalScores.ring < 0.95)
        #expect(canonicalScores.commonFocalPoint < 0.95)
        #expect(canonicalScores.compactCluster < 0.95)
    }

    @Test("every canonical removal subset avoids catastrophic regularity across 2,048 seeds")
    func exhaustiveCanonicalSubsetsAvoidCatastrophicRegularity() {
        var evaluated = 0
        var failures = 0
        var firstFailure: String?

        for recipe in Self.stressRecipes {
            for count in 4...9 {
                for actors in combinations(of: recipe.actors, count: count) {
                    let active = CompositionRecipe(
                        daySeed: recipe.daySeed,
                        grammar: recipe.grammar,
                        viewport: recipe.viewport,
                        actors: actors
                    )
                    let scores = CompositionGuardrails.evaluate(active)
                    evaluated += 1
                    if scores.commonFocalPoint >= 0.95
                        || scores.equalSpacing >= 0.95
                        || scores.grid >= 0.95
                        || scores.row >= 0.95
                    {
                        failures += 1
                        if firstFailure == nil {
                            firstFailure = "seed=\(recipe.daySeed), ids=\(actors.map(\.eventID)), scores=\(scores)"
                        }
                    }
                }
            }
        }

        #expect(evaluated == 1_734_656)
        #expect(failures == 0, "first catastrophic canonical subset: \(firstFailure ?? "none")")
        print("canonical arbitrary subsets evaluated: \(evaluated), catastrophic: \(failures)")
    }

    @Test("same-role external identities de-regularize without reroll")
    func sameRoleExternalIDsDoNotCollapse() {
        let collisionIDs = [
            "external-16", "external-27", "external-29", "external-47", "external-58",
            "external-67", "external-85", "external-92", "external-104", "external-113",
        ]
        let full = CompositionPlanner.make(daySeed: 24, eventIDs: collisionIDs, viewport: .phone)

        for count in [4, 6, 10] {
            let ids = Array(collisionIDs.prefix(count))
            let recipe = CompositionPlanner.make(daySeed: 24, eventIDs: ids.reversed(), viewport: .phone)
            for id in ids {
                #expect(recipe.actor(id) == full.actor(id))
            }
            let scores = CompositionGuardrails.evaluate(recipe)
            #expect(scores.grid < 0.95)
            #expect(scores.row < 0.95)
            #expect(scores.commonFocalPoint < 0.95)
        }

        let cropped = CompositionPlanner.make(
            daySeed: 44,
            eventIDs: Array(collisionIDs.prefix(4)),
            viewport: .phone
        )
        let croppedScores = CompositionGuardrails.evaluate(cropped)
        #expect(croppedScores.commonFocalPoint < 0.95)
        #expect(croppedScores.compactCluster < 0.95)
    }

    @Test("edge anchors do not create an equal-spacing removal subset")
    func edgeAnchorSubsetStaysIrregular() {
        let selectedIDs = [ids[0], ids[3], ids[4], ids[6]]
        let recipe = CompositionPlanner.make(daySeed: 9, eventIDs: selectedIDs, viewport: .phone)
        let scores = CompositionGuardrails.evaluate(recipe)
        #expect(scores.equalSpacing < 0.95, "actors: \(recipe.actors), scores: \(scores)")
    }

    @Test("grammar weights and regularity guardrails remain bounded across 2,048 seeds")
    func distributionAndRegularityGuardrails() {
        var grammarCounts = Dictionary(uniqueKeysWithValues: EditorialGrammar.allCases.map { ($0, 0) })
        var worst = CompositionGuardrailScores.zero

        for recipe in Self.stressRecipes {
            grammarCounts[recipe.grammar, default: 0] += 1
            let scores = CompositionGuardrails.evaluate(recipe)
            worst = worst.componentwiseMaximum(scores)

            #expect(scores.ring <= 0.82)
            #expect(scores.grid <= 0.72)
            #expect(scores.row <= 0.60)
            #expect(scores.commonFocalPoint <= 0.78)
            #expect(scores.compactCluster <= 0.78)
            #expect(scores.equalSpacing <= 0.92)
            if recipe.grammar != .equalScaleStudy {
                #expect(scores.equalScale <= 0.88)
            }
        }

        let equalShare = Double(grammarCounts[.equalScaleStudy, default: 0]) / 2_048
        #expect(equalShare <= 0.10)
        for grammar in EditorialGrammar.allCases {
            #expect(grammarCounts[grammar, default: 0] > 0)
        }

        let shares = EditorialGrammar.allCases.map {
            "\($0.rawValue)=\(String(format: "%.3f", Double(grammarCounts[$0, default: 0]) / 2_048))"
        }.joined(separator: ", ")
        print("composition grammar shares: \(shares)")
        print(
            "worst guardrails: ring=\(worst.ring), grid=\(worst.grid), row=\(worst.row), "
                + "focus=\(worst.commonFocalPoint), cluster=\(worst.compactCluster), "
                + "spacing=\(worst.equalSpacing), scale=\(worst.equalScale)"
        )
    }

    private func recipeKeepingPrefix(_ count: Int, from recipe: CompositionRecipe) -> CompositionRecipe {
        CompositionRecipe(
            daySeed: recipe.daySeed,
            grammar: recipe.grammar,
            viewport: recipe.viewport,
            actors: Array(recipe.actors.prefix(count))
        )
    }

    private func renderedIntersectionCount(_ recipe: CompositionRecipe) -> Int {
        let widthInShortSides = recipe.viewport.width / recipe.viewport.shortSide
        let heightInShortSides = recipe.viewport.height / recipe.viewport.shortSide
        var count = 0
        for left in recipe.actors.indices {
            for right in recipe.actors.indices where right > left {
                let lhs = recipe.actors[left]
                let rhs = recipe.actors[right]
                let dx = (lhs.position.x - rhs.position.x) * widthInShortSides
                let dy = (lhs.position.y - rhs.position.y) * heightInShortSides
                if hypot(dx, dy) < (lhs.diameter + rhs.diameter) * 0.5 {
                    count += 1
                }
            }
        }
        return count
    }

    private func actorsCenteredInTile(
        _ recipe: CompositionRecipe
    ) -> [ActorCompositionRecipe] {
        let tileHeight = recipe.viewport.width / recipe.viewport.height
        let tileTop = (1 - tileHeight) * 0.5
        let tileBottom = 1 - tileTop
        return recipe.actors.filter { (tileTop...tileBottom).contains($0.position.y) }
    }

    private func tileLocalY(
        _ actor: ActorCompositionRecipe,
        in recipe: CompositionRecipe
    ) -> Double {
        let tileHeight = recipe.viewport.width / recipe.viewport.height
        let tileTop = (1 - tileHeight) * 0.5
        return (actor.position.y - tileTop) / tileHeight
    }

    private func horizontalSpan(_ actors: [ActorCompositionRecipe]) -> Double {
        guard let minimum = actors.map(\.position.x).min(),
              let maximum = actors.map(\.position.x).max() else { return 0 }
        return maximum - minimum
    }

    private func tileVerticalSpan(
        _ actors: [ActorCompositionRecipe],
        in recipe: CompositionRecipe
    ) -> Double {
        guard let minimum = actors.map({ tileLocalY($0, in: recipe) }).min(),
              let maximum = actors.map({ tileLocalY($0, in: recipe) }).max() else { return 0 }
        return maximum - minimum
    }

    private func tileVisibleVerticalFraction(
        _ actor: ActorCompositionRecipe,
        in recipe: CompositionRecipe
    ) -> Double {
        let tileHeight = recipe.viewport.width / recipe.viewport.height
        let tileTop = (1 - tileHeight) * 0.5
        let tileBottom = 1 - tileTop
        let radiusY = actor.diameter * 0.5 * recipe.viewport.shortSide / recipe.viewport.height
        let visibleHeight = max(
            0,
            min(tileBottom, actor.position.y + radiusY) - max(tileTop, actor.position.y - radiusY)
        )
        return visibleHeight / (2 * radiusY)
    }

    private func readableCrossDepthPairs(
        in recipe: CompositionRecipe
    ) -> [(String, String)] {
        let widthInShortSides = recipe.viewport.width / recipe.viewport.shortSide
        let heightInShortSides = recipe.viewport.height / recipe.viewport.shortSide
        var pairs: [(String, String)] = []
        for left in recipe.actors.indices {
            for right in recipe.actors.indices where right > left {
                let lhs = recipe.actors[left]
                let rhs = recipe.actors[right]
                let dx = (lhs.position.x - rhs.position.x) * widthInShortSides
                let dy = (lhs.position.y - rhs.position.y) * heightInShortSides
                let radiusSum = (lhs.diameter + rhs.diameter) * 0.5
                let penetration = (radiusSum - hypot(dx, dy)) / radiusSum
                if (0.08...0.52).contains(penetration), abs(lhs.depth - rhs.depth) >= 0.12 {
                    pairs.append((lhs.eventID, rhs.eventID))
                }
            }
        }
        return pairs
    }

    private func rhythmicOverlapTriples(
        in recipe: CompositionRecipe
    ) -> [(String, String, String)] {
        let points = recipe.actors.map {
            CompositionGeometry.shortSidePoint($0.position, viewport: recipe.viewport)
        }
        var rows: [(String, String, String)] = []

        for triple in combinations(of: Array(recipe.actors.indices), count: 3) {
            for middle in triple {
                let ends = triple.filter { $0 != middle }
                let firstVector = (
                    x: points[ends[0]].x - points[middle].x,
                    y: points[ends[0]].y - points[middle].y
                )
                let secondVector = (
                    x: points[ends[1]].x - points[middle].x,
                    y: points[ends[1]].y - points[middle].y
                )
                let firstDistance = hypot(firstVector.x, firstVector.y)
                let secondDistance = hypot(secondVector.x, secondVector.y)
                guard firstDistance > 0, secondDistance > 0 else { continue }

                let directionCosine = (
                    firstVector.x * secondVector.x + firstVector.y * secondVector.y
                ) / (firstDistance * secondDistance)
                let spacingRatio = min(firstDistance, secondDistance) / max(firstDistance, secondDistance)
                let firstOverlap = overlapPenetration(
                    recipe.actors[middle],
                    recipe.actors[ends[0]],
                    distance: firstDistance
                )
                let secondOverlap = overlapPenetration(
                    recipe.actors[middle],
                    recipe.actors[ends[1]],
                    distance: secondDistance
                )

                if directionCosine <= -cos(20 * .pi / 180),
                    spacingRatio >= 0.68,
                    (0.08...0.52).contains(firstOverlap),
                    (0.08...0.52).contains(secondOverlap),
                    abs(firstOverlap - secondOverlap) <= 0.12
                {
                    rows.append((
                        recipe.actors[ends[0]].eventID,
                        recipe.actors[middle].eventID,
                        recipe.actors[ends[1]].eventID
                    ))
                }
            }
        }
        return rows
    }

    private func overlapPenetration(
        _ lhs: ActorCompositionRecipe,
        _ rhs: ActorCompositionRecipe,
        distance: Double
    ) -> Double {
        let radiusSum = (lhs.diameter + rhs.diameter) * 0.5
        return radiusSum > 0 ? (radiusSum - distance) / radiusSum : 0
    }

    private func normalizedTriangleArea(_ recipe: CompositionRecipe) -> Double {
        guard recipe.actors.count == 3 else { return 0 }
        let points = recipe.actors.map {
            CompositionGeometry.shortSidePoint($0.position, viewport: recipe.viewport)
        }
        let twiceArea = abs(
            (points[1].x - points[0].x) * (points[2].y - points[0].y)
                - (points[1].y - points[0].y) * (points[2].x - points[0].x)
        )
        let longestSquared = combinations(of: points, count: 2).map { pair in
            let dx = pair[0].x - pair[1].x
            let dy = pair[0].y - pair[1].y
            return dx * dx + dy * dy
        }.max() ?? 1
        return longestSquared > 0 ? twiceArea / longestSquared : 0
    }

    private func occupiedVerticalExtent(_ recipe: CompositionRecipe) -> (top: Double, bottom: Double) {
        let radiusScale = recipe.viewport.shortSide / recipe.viewport.height * 0.5
        return (
            recipe.actors.map { $0.position.y - $0.diameter * radiusScale }.min() ?? 0,
            recipe.actors.map { $0.position.y + $0.diameter * radiusScale }.max() ?? 0
        )
    }

    private func croppedEdge(
        of actor: ActorCompositionRecipe,
        in recipe: CompositionRecipe
    ) -> String? {
        let point = CompositionGeometry.shortSidePoint(actor.position, viewport: recipe.viewport)
        let radius = actor.diameter * 0.5
        let width = recipe.viewport.width / recipe.viewport.shortSide
        let height = recipe.viewport.height / recipe.viewport.shortSide
        let penetrations = [
            ("left", radius - point.x),
            ("right", radius - (width - point.x)),
            ("top", radius - point.y),
            ("bottom", radius - (height - point.y)),
        ]
        return penetrations.max(by: { $0.1 < $1.1 }).flatMap { edge, penetration in
            penetration / radius >= 0.12 ? edge : nil
        }
    }

    private func controlRecipe(
        shortSidePoints: [CompositionPoint],
        diameter: Double
    ) -> CompositionRecipe {
        let viewport = EditorialViewport.phone
        let widthInShortSides = viewport.width / viewport.shortSide
        let heightInShortSides = viewport.height / viewport.shortSide
        let actors = shortSidePoints.enumerated().map { index, point in
            ActorCompositionRecipe(
                eventID: "negative-control-\(index)",
                position: CompositionPoint(
                    x: point.x / widthInShortSides,
                    y: point.y / heightInShortSides
                ),
                diameter: diameter,
                depth: 0.5,
                localBlur: 0,
                cropAllowance: 0,
                drawOrder: index
            )
        }
        return CompositionRecipe(daySeed: 0, grammar: .openField, viewport: viewport, actors: actors)
    }

    private func combinations<T>(of values: [T], count: Int) -> [[T]] {
        guard count > 0, count <= values.count else { return [] }
        var result: [[T]] = []
        var current: [T] = []

        func visit(start: Int) {
            if current.count == count {
                result.append(current)
                return
            }
            let remaining = count - current.count
            guard start <= values.count - remaining else { return }
            for index in start...(values.count - remaining) {
                current.append(values[index])
                visit(start: index + 1)
                current.removeLast()
            }
        }

        visit(start: 0)
        return result
    }
}
