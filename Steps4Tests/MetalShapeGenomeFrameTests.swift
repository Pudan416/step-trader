import XCTest
import simd
@testable import Steps4

final class MetalShapeGenomeFrameTests: XCTestCase {
    func testUniformLayoutsMatchTheMetalABI() {
        XCTAssertEqual(MemoryLayout<MetalShapeGenomeUniforms>.alignment, 16)
        XCTAssertEqual(MemoryLayout<MetalShapeGenomeUniforms>.stride, 128)
        XCTAssertEqual(MetalShapeGenomeUniforms.metalStride, 128)
        XCTAssertEqual(MemoryLayout<MetalShapeMaterialUniforms>.alignment, 16)
        XCTAssertEqual(MemoryLayout<MetalShapeMaterialUniforms>.stride, 128)
        XCTAssertEqual(MetalShapeMaterialUniforms.metalStride, 128)
    }

    func testFrameIsDeterministicAndSeedVariationStaysBounded() throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first)
        let first = MetalShapeGenomeFrame.make(preset: preset, material: .proceduralFlow, seed: 42)
        XCTAssertEqual(first, MetalShapeGenomeFrame.make(preset: preset, material: .proceduralFlow, seed: 42))

        let second = MetalShapeGenomeFrame.make(preset: preset, material: .proceduralFlow, seed: 314)
        XCTAssertNotEqual(first.material.params0, second.material.params0)
        for frame in [first, second] {
            XCTAssertTrue((0..<1).contains(frame.material.params0.x))
            XCTAssertEqual(simd_length(frame.material.direction), 1, accuracy: 0.0001)
            XCTAssertTrue(frame.material.colorsAreFiniteAndBounded)
        }
    }

    func testEveryMaterialProducesSanitizedUniformsForEveryPreset() {
        for preset in MetalShapeGenomeCatalog.presets {
            for material in MetalShapeMaterial.allCases {
                let frame = MetalShapeGenomeFrame.make(preset: preset, material: material, seed: 2_718)
                XCTAssertEqual(frame.material.materialIndex, UInt32(MetalShapeMaterial.allCases.firstIndex(of: material)!))
                XCTAssertTrue(frame.material.colorsAreFiniteAndBounded, "\(preset.id) \(material)")
                XCTAssertTrue(frame.geometry.isFiniteAndBounded, preset.id)
            }
        }
    }

    func testLegacyDescriptorsReachTheSharedGeometryPayload() throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "legacy.soft-square" })
        let frame = MetalShapeGenomeFrame.make(preset: preset, material: .sideLight, seed: 42)
        XCTAssertEqual(frame.geometry.sourceKind, 1)
        XCTAssertEqual(frame.geometry.legacyShape, 6)
        XCTAssertEqual(frame.geometry.legacyVariant, 17)
        XCTAssertGreaterThan(frame.geometry.normalization, 0)
    }

    func testSuperformUsesTheSeedToProduceThreeRelatedGeometryExamples() throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "genome.superform" })
        let frames = [42, 314, 2_718].map {
            MetalShapeGenomeFrame.make(preset: preset, material: .sideLight, seed: UInt64($0))
        }

        XCTAssertEqual(frames.map(\.geometry.superformLobes), [5, 6, 7])
        XCTAssertTrue(frames.allSatisfy { $0.geometry.sourceKind == 2 })
        XCTAssertEqual(frames[0].geometry.superformIrregularity, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(frames[1].geometry.superformIrregularity, 0.08)
        XCTAssertGreaterThan(frames[2].geometry.superformIrregularity, frames[1].geometry.superformIrregularity)
        XCTAssertEqual(
            frames[0],
            MetalShapeGenomeFrame.make(preset: preset, material: .sideLight, seed: 42)
        )
    }

    func testSideLightUsesTwoTonalStops() throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first)
        let frame = MetalShapeGenomeFrame.make(preset: preset, material: .sideLight, seed: 42)
        XCTAssertEqual(frame.material.color2, frame.material.color1)
    }

    func testRendererProducesAnActualMetalImageAtTheRequestedSize() async throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first)
        let image = try await MetalShapeGenomeRenderer.image(
            preset: preset,
            material: .sideLight,
            seed: 42,
            size: CGSize(width: 96, height: 96),
            scale: 1
        )
        XCTAssertEqual(image.cgImage?.width, 96)
        XCTAssertEqual(image.cgImage?.height, 96)
    }


    func testProceduralFlowKeepsTheShapeCenterOpaque() async throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "genome.superform" })
        let image = try await MetalShapeGenomeRenderer.image(
            preset: preset,
            material: .proceduralFlow,
            seed: 42,
            size: CGSize(width: 96, height: 96),
            scale: 1
        )
        XCTAssertGreaterThan(alpha(in: image, x: 48, y: 48), 245)
    }

    func testEclipseGlowHasATransparentCenterAndLuminousEdge() async throws {
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "genome.superform" })
        let image = try await MetalShapeGenomeRenderer.image(
            preset: preset,
            material: .eclipseGlow,
            seed: 42,
            size: CGSize(width: 96, height: 96),
            scale: 1
        )
        XCTAssertLessThan(alpha(in: image, x: 48, y: 48), 20)
        let strongestEdge = (0..<96).map { alpha(in: image, x: $0, y: 48) }.max() ?? 0
        XCTAssertGreaterThan(strongestEdge, 160)
    }

    private func alpha(in image: UIImage, x: Int, y: Int) -> UInt8 {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        return bytes[y * cgImage.bytesPerRow + x * 4 + 3]
    }
}
