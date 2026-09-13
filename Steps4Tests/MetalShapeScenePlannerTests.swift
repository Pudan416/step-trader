import XCTest
@testable import Steps4

final class MetalShapeScenePlannerTests: XCTestCase {
    func testOneThousandSeedsObeyTheSceneGrammar() throws {
        let hollow: Set<MetalShapeMaterial> = [.contour, .proceduralContour, .eclipseGlow]
        for seed in UInt64(0)..<1_000 {
            for count in 1...6 {
                let scene = try MetalShapeScenePlanner.make(seed: seed, count: count)
                XCTAssertEqual(scene.actors.count, count, "seed \(seed), count \(count)")
                XCTAssertEqual(scene.actors.filter { $0.role == .primary }.count, 1)
                XCTAssertLessThanOrEqual(scene.actors.filter { $0.material == .directionalBlur }.count, 1)
                XCTAssertLessThanOrEqual(scene.actors.filter { $0.material == .eclipseGlow }.count, 1)
                XCTAssertLessThanOrEqual(scene.actors.filter(\.hasHighComplexityInterior).count, 2)
                if count >= 4 {
                    XCTAssertTrue(scene.actors.contains { hollow.contains($0.material) })
                }

                let morphologyCounts = Dictionary(grouping: scene.actors, by: \.preset.morphology).mapValues(\.count)
                XCTAssertTrue(morphologyCounts.values.allSatisfy { $0 <= 2 })
                let presetCounts = Dictionary(grouping: scene.actors, by: \.preset.id).mapValues(\.count)
                for actor in scene.actors {
                    XCTAssertLessThanOrEqual(presetCounts[actor.preset.id, default: 0], actor.preset.compatibility.maxInstances)
                    XCTAssertTrue(actor.preset.compatibility.allowed.contains(actor.material))
                    XCTAssertTrue(actor.preset.compatibility.roles.contains(actor.role))
                    XCTAssertTrue(actor.expandedBounds.isInsideUnitCanvas)
                }
            }
        }
    }

    func testSameSeedProducesSameScene() throws {
        XCTAssertEqual(
            try MetalShapeScenePlanner.make(seed: 314, count: 5),
            try MetalShapeScenePlanner.make(seed: 314, count: 5)
        )
    }
}
