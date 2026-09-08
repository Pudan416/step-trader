#if DEBUG || INTERNAL_BUILD
import Foundation
import UIKit

struct MetalShapeAtlasCellRecord: Codable, Equatable, Sendable {
    let materialID: String
    let seed: UInt64
    let path: String
}

struct MetalShapeAtlasShapeRecord: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let source: String
    let morphology: String
    let preferredMaterials: [String]
    let allowedMaterials: [String]
    let roles: [String]
    let minimumSize: Float
    let maximumSize: Float
    let complexity: Float
    let visualMass: Float
    let images: [MetalShapeAtlasCellRecord]
}

struct MetalShapeAtlasMaterialRecord: Codable, Equatable, Sendable {
    let id: String
    let title: String
}

struct MetalShapeAtlasSceneActorRecord: Codable, Equatable, Sendable {
    let shapeID: String
    let role: String
    let materialID: String
}

struct MetalShapeAtlasSceneRecord: Codable, Equatable, Sendable {
    let seed: UInt64
    let index: Int
    let path: String
    let actors: [MetalShapeAtlasSceneActorRecord]
}

struct MetalShapeAtlasImageRecord: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let seed: UInt64
    let path: String
}

struct MetalShapeAtlasManifest: Codable, Equatable, Sendable {
    let version: Int
    let seeds: [UInt64]
    let shapes: [MetalShapeAtlasShapeRecord]
    let materials: [MetalShapeAtlasMaterialRecord]
    let scenes: [MetalShapeAtlasSceneRecord]
    let blurStudy: [MetalShapeAtlasImageRecord]
}

enum MetalShapeAtlasExport {
    static let seeds: [UInt64] = [64, 59, 48]

    static func makeManifest() throws -> MetalShapeAtlasManifest {
        let shapes = MetalShapeGenomeCatalog.presets.map { preset in
            let allowed = MetalShapeMaterial.allCases.filter { preset.compatibility.allowed.contains($0) }
            let images = seeds.flatMap { seed in
                allowed.map { material in
                    MetalShapeAtlasCellRecord(
                        materialID: material.rawValue,
                        seed: seed,
                        path: assetPath(tablePath(preset: preset, material: material, seed: seed))
                    )
                }
            }
            return MetalShapeAtlasShapeRecord(
                id: preset.id,
                title: preset.title,
                source: preset.source.rawValue,
                morphology: preset.morphology.rawValue,
                preferredMaterials: MetalShapeMaterial.allCases.filter { preset.compatibility.preferred.contains($0) }.map(\.rawValue),
                allowedMaterials: allowed.map(\.rawValue),
                roles: MetalShapeRole.allCases.filter { preset.compatibility.roles.contains($0) }.map(\.rawValue),
                minimumSize: preset.compatibility.minimumSize,
                maximumSize: preset.compatibility.maximumSize,
                complexity: preset.compatibility.complexity,
                visualMass: preset.compatibility.visualMass,
                images: images
            )
        }

        let scenes = try seeds.flatMap { seed in
            try (0..<4).map { index in
                let scene = try MetalShapeScenePlanner.make(seed: seed &+ UInt64(index * 10_007), count: index + 3)
                return MetalShapeAtlasSceneRecord(
                    seed: seed,
                    index: index,
                    path: assetPath(scenePath(seed: seed, index: index)),
                    actors: scene.actors.map {
                        MetalShapeAtlasSceneActorRecord(
                            shapeID: $0.preset.id,
                            role: $0.role.rawValue,
                            materialID: $0.material.rawValue
                        )
                    }
                )
            }
        }
        let blurTitles = ["Мягкий след", "Ребристый след", "Цветовое расщепление", "Изогнутый след"]
        let blurStudy = (0..<4).map { index in
            MetalShapeAtlasImageRecord(
                id: ["smooth", "ribbed", "chromatic", "curved"][index],
                title: blurTitles[index],
                seed: 42,
                path: assetPath(blurPath(index: index))
            )
        }
        return MetalShapeAtlasManifest(
            version: 1,
            seeds: seeds,
            shapes: shapes,
            materials: MetalShapeMaterial.allCases.map { .init(id: $0.rawValue, title: $0.russianTitle) },
            scenes: scenes,
            blurStudy: blurStudy
        )
    }

    @MainActor
    static func export(to destination: URL) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifest = try makeManifest()

        for preset in MetalShapeGenomeCatalog.presets {
            for material in MetalShapeMaterial.allCases where preset.compatibility.allowed.contains(material) {
                for seed in seeds {
                    let image = try await MetalShapeGenomeRenderer.image(
                        preset: preset,
                        material: material,
                        seed: seed,
                        size: CGSize(width: 768, height: 768),
                        scale: 1
                    )
                    try write(image: image, relativePath: tablePath(preset: preset, material: material, seed: seed), root: destination)
                }
            }
        }

        for record in manifest.scenes {
            let sceneSeed = record.seed &+ UInt64(record.index * 10_007)
            let scene = try MetalShapeScenePlanner.make(seed: sceneSeed, count: record.index + 3)
            let image = try await renderScene(scene)
            try write(image: image, relativePath: scenePath(seed: record.seed, index: record.index), root: destination)
        }

        let blurPreset = MetalShapeGenomeCatalog.presets.first { $0.id == "legacy.soft-square" }
            ?? MetalShapeGenomeCatalog.presets[0]
        for index in 0..<4 {
            let image = try await MetalShapeGenomeRenderer.image(
                preset: blurPreset,
                material: .directionalBlur,
                seed: 42,
                size: CGSize(width: 1_200, height: 900),
                scale: 1,
                blurMode: UInt32(index)
            )
            try write(image: image, relativePath: blurPath(index: index), root: destination)
        }

        let data = try JSONEncoder.stable.encode(manifest)
        try data.write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
    }

    @MainActor
    private static func renderScene(_ scene: MetalShapeScene) async throws -> UIImage {
        let canvasSize = CGSize(width: 1_200, height: 900)
        var layers: [(UIImage, CGRect)] = []
        for actor in scene.actors {
            let diameter = CGFloat(actor.size) * 720
            let image = try await MetalShapeGenomeRenderer.image(
                preset: actor.preset,
                material: actor.material,
                seed: actor.seed,
                size: CGSize(width: diameter, height: diameter),
                scale: 1
            )
            let center = CGPoint(
                x: canvasSize.width * (CGFloat(actor.position.x) + 1) * 0.5,
                y: canvasSize.height * (CGFloat(actor.position.y) + 1) * 0.5
            )
            layers.append((image, CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for (image, rect) in layers { image.draw(in: rect) }
        }
    }

    private static func write(image: UIImage, relativePath: String, root: URL) throws {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func tablePath(preset: MetalShapePreset, material: MetalShapeMaterial, seed: UInt64) -> String {
        "table/\(slug(preset.id))/\(material.rawValue)-\(seed).png"
    }

    static func scenePath(seed: UInt64, index: Int) -> String { "scenes/scene-\(seed)-\(index).png" }
    static func blurPath(index: Int) -> String { "blur-study/blur-42-\(index).png" }
    private static func assetPath(_ path: String) -> String { "assets/metal-shape-atlas/\(path)" }
    private static func slug(_ value: String) -> String { value.replacingOccurrences(of: ".", with: "-") }
}

extension MetalShapeMaterial {
    var russianTitle: String {
        switch self {
        case .solid: "Сплошной цвет"
        case .sideLight: "Боковой свет"
        case .contour: "Контур"
        case .directionalBlur: "Направленное размытие"
        case .radialTwo: "Радиальный · два цвета"
        case .radialThree: "Радиальный · три цвета"
        case .proceduralLight: "Процедурный свет"
        case .proceduralFlow: "Процедурное течение"
        case .proceduralContour: "Процедурный контур"
        case .eclipseGlow: "Светящийся контур"
        }
    }
}

extension JSONEncoder {
    static var stable: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
#endif
