import Foundation
import Testing
@testable import EditorialFieldCore

@Suite("Editorial radial material DNA")
struct MaterialDNATests {
    private let eventIDs = Array(CorpusManifest.canonicalEventIDs.prefix(10))

    @Test("all nine daily material families are reachable")
    func everyFamilyIsReachable() {
        let reached = Set((0..<512).map { seed in
            MaterialDNA.make(daySeed: UInt64(seed), eventIDs: eventIDs).family
        })

        #expect(reached == Set(MaterialFamily.allCases))
        #expect(MaterialFamily.allCases.count == 9)
    }

    @Test("one daily family and its compatible accent govern every actor")
    func dailyFamilyIsCoherent() {
        for seed in UInt64(0)..<128 {
            let dna = MaterialDNA.make(daySeed: seed, eventIDs: eventIDs)

            #expect(Set(dna.actors.map(\.family)) == Set([dna.family]))
            #expect(dna.actors.allSatisfy { actor in
                actor.mutation == nil || actor.mutation == dna.accentMutation
            })
            if let accent = dna.accentMutation {
                #expect(accent.isCompatible(with: dna.family))
            }
        }
    }

    @Test("actor-local material mutations survive reorder, insertion, and removal")
    func actorLocalMaterialIsStable() throws {
        let retained = Array(eventIDs.prefix(5))
        let original = MaterialDNA.make(daySeed: 0xA11CE, eventIDs: retained)
        let reordered = MaterialDNA.make(daySeed: 0xA11CE, eventIDs: retained.reversed())
        let expanded = MaterialDNA.make(daySeed: 0xA11CE, eventIDs: eventIDs)
        let reduced = MaterialDNA.make(daySeed: 0xA11CE, eventIDs: Array(retained.dropFirst()))

        for eventID in retained {
            #expect(try #require(original.actor(eventID)) == #require(reordered.actor(eventID)))
            #expect(try #require(original.actor(eventID)) == #require(expanded.actor(eventID)))
        }
        for eventID in retained.dropFirst() {
            #expect(try #require(original.actor(eventID)) == #require(reduced.actor(eventID)))
        }
    }

    @Test("solid is exactly one constant color with no analytic or brightness field")
    func solidHasNoHiddenField() {
        for seed in UInt64(0)..<64 {
            let solid = MaterialDNA.fixture(
                daySeed: seed,
                eventIDs: eventIDs,
                family: .solid,
                requestedColorCount: 3
            )

            #expect(solid.actors.allSatisfy { actor in
                actor.colors.count == 1
                    && actor.fields.isEmpty
                    && actor.family == .solid
            })
        }
    }

    @Test("outline and counterform are structurally visible among the first three actors")
    func structuralFamiliesAppearEarly() {
        for family in [MaterialFamily.outline, .counterform] {
            for seed in UInt64(0)..<32 {
                let dna = MaterialDNA.fixture(
                    daySeed: seed,
                    eventIDs: eventIDs,
                    family: family,
                    requestedColorCount: 3
                )
                let firstThree = dna.actors.prefix(3)

                if family == .outline {
                    #expect(firstThree.contains { $0.contourCount > 0 && $0.contourWidth > 0 })
                } else {
                    #expect(firstThree.contains { ($0.counterformRadius ?? 0) > 0 })
                }
            }
        }
    }

    @Test("material fixtures stay within the radial-only three-color budget")
    func descriptorsStayBoundedAndRadial() {
        let supported = Set(RadialBlend.allCases)
        #expect(supported == [.normal, .screen, .softLight, .multiply])

        for (familyIndex, family) in MaterialFamily.allCases.enumerated() {
            for colorCount in 1...3 {
                let dna = MaterialDNA.fixture(
                    daySeed: UInt64(familyIndex * 10 + colorCount),
                    eventIDs: eventIDs,
                    family: family,
                    requestedColorCount: colorCount
                )
                for actor in dna.actors {
                    #expect((1...3).contains(actor.colors.count))
                    #expect(actor.fields.count <= 3)
                    #expect(actor.fields.allSatisfy { supported.contains($0.blend) })
                    #expect(actor.fields.allSatisfy { field in
                        (0..<actor.colors.count).contains(field.colorIndex)
                            && (0.12...0.88).contains(field.focus.x)
                            && (0.12...0.88).contains(field.focus.y)
                            && (0.55...1.15).contains(field.radius)
                            && (0.35...0.80).contains(field.softness)
                    })
                }
            }
        }
    }

    @Test("unsupported radial blend values fail closed during decoding")
    func unsupportedBlendCannotDecode() {
        let json = Data(#"{"focus":{"x":0.5,"y":0.5},"radius":0.8,"softness":0.6,"opacity":1,"colorIndex":0,"blend":"overlay"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RadialField.self, from: json)
        }
    }

    @Test("organic structural topology is bounded actor-local recipe data")
    func structuralTopologyIsEncodedAndBounded() throws {
        for family in [MaterialFamily.halo, .outline, .counterform] {
            let dna = MaterialDNA.fixture(
                daySeed: 0xECCE_1705,
                eventIDs: eventIDs,
                family: family,
                requestedColorCount: 1
            )
            for actor in dna.actors {
                let topology = try #require(actor.organicTopology)
                #expect((0.28...0.72).contains(topology.outerCenter.x))
                #expect((0.28...0.72).contains(topology.outerCenter.y))
                #expect((0.28...0.72).contains(topology.innerCenter.x))
                #expect((0.28...0.72).contains(topology.innerCenter.y))
                #expect((0.03...0.50).contains(topology.innerRadius))
                #expect((0.08...0.50).contains(topology.outerRadius))
                if family == .outline {
                    for contour in topology.contours {
                        let bandWidth = contour.outerRadius - contour.innerRadius
                        let offset = hypot(
                            contour.innerCenter.x - contour.outerCenter.x,
                            contour.innerCenter.y - contour.outerCenter.y
                        )
                        #expect(offset >= bandWidth * 0.45)
                        #expect(offset < bandWidth)
                    }
                    #expect(topology.contours.count == actor.contourCount)
                    #expect(topology.outerCenter == topology.contours.first?.outerCenter)
                    #expect(topology.outerRadius == topology.contours.first?.outerRadius)
                    #expect(topology.innerCenter == topology.contours.last?.innerCenter)
                    #expect(topology.innerRadius == topology.contours.last?.innerRadius)
                    #expect(topology.contours.allSatisfy { contour in
                        (0.28...0.72).contains(contour.outerCenter.x)
                            && (0.28...0.72).contains(contour.outerCenter.y)
                            && (0.28...0.72).contains(contour.innerCenter.x)
                            && (0.28...0.72).contains(contour.innerCenter.y)
                            && (0.02...0.50).contains(contour.innerRadius)
                            && (0.02...0.50).contains(contour.outerRadius)
                            && contour.innerRadius < contour.outerRadius
                            && contour.opacity > 0
                            && contour.opacity <= 1
                    })
                } else {
                    #expect(hypot(
                        topology.innerCenter.x - topology.outerCenter.x,
                        topology.innerCenter.y - topology.outerCenter.y
                    ) >= 0.030)
                    #expect(topology.contours.isEmpty)
                }
                let encoded = try JSONEncoder().encode(actor)
                #expect(try JSONDecoder().decode(ActorMaterialRecipe.self, from: encoded) == actor)
            }
        }
        for family in MaterialFamily.allCases where ![.halo, .outline, .counterform].contains(family) {
            let dna = MaterialDNA.fixture(
                daySeed: 0xECCE_1705,
                eventIDs: eventIDs,
                family: family,
                requestedColorCount: 3
            )
            #expect(dna.actors.allSatisfy { $0.organicTopology == nil })
        }
    }

    @Test("material generation depends on identity and day seed, not composition geometry bytes")
    func materialIsCompositionIndependent() {
        let ids = Array(eventIDs.prefix(3))
        let first = MaterialDNA.make(daySeed: 42, eventIDs: ids)
        let second = MaterialDNA.make(daySeed: 42, eventIDs: ids)

        #expect(first == second)
        #expect(first.actors.map(\.eventID) == ids)
    }
}
