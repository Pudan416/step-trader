import XCTest
@testable import Steps4

final class MetalShapeAtlasManifestTests: XCTestCase {
    func testManifestHasExactStableInventory() throws {
        let manifest = try MetalShapeAtlasExport.makeManifest()
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.seeds, [64, 59, 48])
        XCTAssertEqual(manifest.shapes.count, 8)
        XCTAssertEqual(manifest.shapes.filter { $0.source == "genome" }.count, 4)
        XCTAssertEqual(manifest.shapes.filter { $0.source == "legacy" }.count, 4)
        XCTAssertEqual(manifest.shapes.filter { $0.morphology == "snowflake" }.map(\.id), ["genome.snowflake"])
        XCTAssertEqual(manifest.shapes.filter { $0.morphology == "windflower" }.map(\.id), ["genome.windflower"])
        XCTAssertEqual(manifest.shapes.filter { $0.morphology == "concaveSquare" }.map(\.id), ["genome.concave-square"])
        XCTAssertEqual(manifest.materials.map(\.id), MetalShapeMaterial.allCases.map(\.rawValue))
        XCTAssertEqual(manifest.scenes.count, 12)
        XCTAssertEqual(manifest.blurStudy.count, 4)

        for shape in manifest.shapes {
            let allowed = Set(shape.allowedMaterials)
            XCTAssertFalse(allowed.isEmpty)
            XCTAssertEqual(shape.images.count, allowed.count * manifest.seeds.count)
            XCTAssertTrue(shape.images.allSatisfy { allowed.contains($0.materialID) })
            XCTAssertEqual(Set(shape.images.map(\.seed)), Set(manifest.seeds))
        }

        let first = try JSONEncoder.stable.encode(manifest)
        let second = try JSONEncoder.stable.encode(try MetalShapeAtlasExport.makeManifest())
        XCTAssertEqual(first, second)
    }
}
