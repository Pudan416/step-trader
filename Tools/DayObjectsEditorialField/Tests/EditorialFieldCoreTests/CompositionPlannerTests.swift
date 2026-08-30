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

            #expect(recipe.minimumDiameter >= 0.06)
            #expect(recipe.maximumDiameter <= 0.75)
            #expect(recipe.maximumDiameter / recipe.minimumDiameter >= 3)
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

    @Test("distributed grammars occupy every vertical third with six or more actors")
    func distributedGrammarsUseAllVerticalThirds() {
        for recipe in Self.stressRecipes {
            guard recipe.grammar == .openField || recipe.grammar == .depthScatter else { continue }

            let thirds = Set(recipe.actors.map { min(2, max(0, Int($0.position.y * 3))) })
            #expect(thirds == Set([0, 1, 2]))
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
                + "focus=\(worst.commonFocalPoint), cluster=\(worst.compactCluster)"
        )
    }
}
