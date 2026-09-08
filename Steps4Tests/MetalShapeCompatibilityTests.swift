import XCTest
@testable import Steps4

final class MetalShapeCompatibilityTests: XCTestCase {
    func testEveryPresetHasOneCoherentCompatibilityPolicy() {
        for preset in MetalShapeGenomeCatalog.presets {
            let policy = preset.compatibility
            XCTAssertFalse(policy.allowed.isEmpty, preset.id)
            XCTAssertFalse(policy.preferred.isEmpty, preset.id)
            XCTAssertTrue(policy.preferred.isSubset(of: policy.allowed), preset.id)
            XCTAssertFalse(policy.roles.isEmpty, preset.id)
            XCTAssertGreaterThan(policy.minimumSize, 0, preset.id)
            XCTAssertLessThanOrEqual(policy.minimumSize, policy.maximumSize, preset.id)
            XCTAssertLessThanOrEqual(policy.maximumSize, 1, preset.id)
            XCTAssertGreaterThan(policy.maxInstances, 0, preset.id)
            XCTAssertTrue((0...1).contains(policy.complexity), preset.id)
            XCTAssertTrue((0...1).contains(policy.visualMass), preset.id)
            XCTAssertTrue((0...0.5).contains(policy.haloFootprint), preset.id)
            XCTAssertTrue((0...0.5).contains(policy.blurFootprint), preset.id)
            XCTAssertEqual(policy.prohibited, Set(MetalShapeMaterial.allCases).subtracting(policy.allowed))
        }
    }
}
