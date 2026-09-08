import Foundation

struct MetalShapeSceneBounds: Codable, Equatable, Sendable {
    let minimum: SIMD2<Float>
    let maximum: SIMD2<Float>

    var isInsideUnitCanvas: Bool {
        minimum.x >= -1 && minimum.y >= -1 && maximum.x <= 1 && maximum.y <= 1
    }
}

struct MetalShapeSceneActor: Codable, Equatable, Sendable {
    let preset: MetalShapePreset
    let role: MetalShapeRole
    let material: MetalShapeMaterial
    let position: SIMD2<Float>
    let size: Float
    let seed: UInt64

    var hasHighComplexityInterior: Bool {
        let hollow: Set<MetalShapeMaterial> = [.contour, .proceduralContour, .eclipseGlow]
        return preset.compatibility.complexity >= 0.7 && !hollow.contains(material)
    }

    var expandedBounds: MetalShapeSceneBounds {
        let expansion: Float
        switch material {
        case .directionalBlur:
            expansion = preset.compatibility.blurFootprint
        case .eclipseGlow:
            expansion = preset.compatibility.haloFootprint
        default:
            expansion = 0.025
        }
        let reach = SIMD2<Float>(repeating: size * 0.5 + expansion)
        return MetalShapeSceneBounds(minimum: position - reach, maximum: position + reach)
    }
}

struct MetalShapeScene: Codable, Equatable, Sendable {
    let seed: UInt64
    let actors: [MetalShapeSceneActor]
}

enum MetalShapeScenePlannerError: Error, Equatable {
    case invalidCount
    case insufficientCompatiblePresets
}

enum MetalShapeScenePlanner {
    private static let positions: [SIMD2<Float>] = [
        SIMD2(0, -0.04), SIMD2(-0.56, -0.48), SIMD2(0.56, 0.44),
        SIMD2(0.58, -0.44), SIMD2(-0.52, 0.50), SIMD2(0, 0.66),
    ]
    private static let targetSizes: [Float] = [0.46, 0.24, 0.23, 0.20, 0.18, 0.16]
    private static let hollowMaterials: Set<MetalShapeMaterial> = [.contour, .proceduralContour, .eclipseGlow]

    static func make(seed: UInt64, count: Int) throws -> MetalShapeScene {
        guard (1...6).contains(count) else { throw MetalShapeScenePlannerError.invalidCount }

        var random = SplitMix64(state: seed ^ 0xD1B5_4A32_D192_ED03)
        var actors: [MetalShapeSceneActor] = []
        var morphologyCounts: [MetalShapeMorphology: Int] = [:]
        var presetCounts: [String: Int] = [:]
        var blurCount = 0
        var eclipseCount = 0
        var complexInteriorCount = 0

        for index in 0..<count {
            let requiredHollow = count >= 4 && index == count - 1 && !actors.contains { hollowMaterials.contains($0.material) }
            let preferredRole: MetalShapeRole = index == 0 ? .primary : (index % 3 == 0 ? .accent : .supporting)
            let roleOrder: [MetalShapeRole] = index == 0 ? [.primary] : [preferredRole, preferredRole == .accent ? .supporting : .accent]
            var selection: (MetalShapePreset, MetalShapeRole, MetalShapeMaterial)?

            for role in roleOrder where selection == nil {
                let eligible = MetalShapeGenomeCatalog.presets.filter { preset in
                    preset.compatibility.roles.contains(role)
                        && morphologyCounts[preset.morphology, default: 0] < 2
                        && presetCounts[preset.id, default: 0] < preset.compatibility.maxInstances
                        && (!requiredHollow || !preset.compatibility.allowed.isDisjoint(with: hollowMaterials))
                }
                guard !eligible.isEmpty else { continue }
                let start = Int(random.next() % UInt64(eligible.count))
                for offset in 0..<eligible.count {
                    let preset = eligible[(start + offset) % eligible.count]
                    let candidates = materialCandidates(
                        for: preset,
                        requiredHollow: requiredHollow,
                        blurCount: blurCount,
                        eclipseCount: eclipseCount,
                        complexInteriorCount: complexInteriorCount
                    )
                    if !candidates.isEmpty {
                        let material = candidates[Int(random.next() % UInt64(candidates.count))]
                        selection = (preset, role, material)
                        break
                    }
                }
            }

            guard let (preset, role, material) = selection else {
                throw MetalShapeScenePlannerError.insufficientCompatiblePresets
            }
            let targetSize = min(max(targetSizes[index], preset.compatibility.minimumSize), preset.compatibility.maximumSize)
            let actor = MetalShapeSceneActor(
                preset: preset,
                role: role,
                material: material,
                position: positions[index],
                size: targetSize,
                seed: random.next()
            )
            guard actor.expandedBounds.isInsideUnitCanvas else {
                throw MetalShapeScenePlannerError.insufficientCompatiblePresets
            }
            actors.append(actor)
            morphologyCounts[preset.morphology, default: 0] += 1
            presetCounts[preset.id, default: 0] += 1
            if material == .directionalBlur { blurCount += 1 }
            if material == .eclipseGlow { eclipseCount += 1 }
            if actor.hasHighComplexityInterior { complexInteriorCount += 1 }
        }
        return MetalShapeScene(seed: seed, actors: actors)
    }

    private static func materialCandidates(
        for preset: MetalShapePreset,
        requiredHollow: Bool,
        blurCount: Int,
        eclipseCount: Int,
        complexInteriorCount: Int
    ) -> [MetalShapeMaterial] {
        let ordered = MetalShapeMaterial.allCases.filter { preset.compatibility.preferred.contains($0) }
            + MetalShapeMaterial.allCases.filter {
                preset.compatibility.allowed.contains($0) && !preset.compatibility.preferred.contains($0)
            }
        return ordered.filter { material in
            guard preset.compatibility.allowed.contains(material) else { return false }
            if requiredHollow && !hollowMaterials.contains(material) { return false }
            if blurCount >= 1 && material == .directionalBlur { return false }
            if eclipseCount >= 1 && material == .eclipseGlow { return false }
            if complexInteriorCount >= 2,
               preset.compatibility.complexity >= 0.7,
               !hollowMaterials.contains(material) { return false }
            return true
        }
    }
}

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
