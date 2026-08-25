import Foundation
import simd

enum DayObjectMaterialFamily: UInt32, CaseIterable, Equatable {
    case satin
    case innerGlow
    case rimGlow
    case glass
    case membrane
    case spectral
}

struct DayObjectAppearance: Equatable {
    let colorAssignment: DayObjectColorAssignment
    let material: DayObjectMaterialFamily
    let shape: DayObjectShape
    let focalDistance: Double
    let focalAngle: Double
    let radius: Double
    let falloff: Double
    let mixing: Double
    let distortion: Double
    let distortionShift: Double
    let distortionFrequency: Double
    let innerGlow: Double
    let outerGlow: Double
    let bodyOpacity: Double
    let centerOpacity: Double
    let rimOpacity: Double
    let refractionStrength: Double
    let refractionAngle: Double
    let membraneLayerCount: Int
    let membraneOffsets: SIMD2<Double>
    let localDepthSoftness: Double
    let lightResponse: Double
    let radialPhase: Double
}

struct DayObjectVisualLanguage: Equatable {
    let paletteSet: DayObjectPaletteSet
    let enabledMaterials: [DayObjectMaterialFamily]
    let dominantMaterial: DayObjectMaterialFamily
    let lightDirection: SIMD2<Double>
    let lightSoftness: Double
    let grainIntensity: Double

    static func make(
        rootSeed: UInt64,
        paletteSet: DayObjectPaletteSet
    ) -> DayObjectVisualLanguage {
        var rng = SeededRNG.derived(from: rootSeed, domain: "dailyVisualLanguage")
        var materials = DayObjectMaterialFamily.allCases
        for index in stride(from: materials.count - 1, through: 1, by: -1) {
            materials.swapAt(index, rng.nextInt(in: 0...index))
        }
        let enabled = Array(materials.prefix(rng.nextInt(in: 3...4)))
        let lightAngle = rng.nextDouble(in: 0...(2 * Double.pi))
        return DayObjectVisualLanguage(
            paletteSet: paletteSet,
            enabledMaterials: enabled,
            dominantMaterial: enabled[0],
            lightDirection: SIMD2(cos(lightAngle), sin(lightAngle)),
            lightSoftness: rng.nextDouble(in: 0.40...0.85),
            grainIntensity: 0.05
        )
    }

    func appearances(
        eventIDs: [String],
        rootSeed: UInt64
    ) -> [String: DayObjectAppearance] {
        var seen = Set<String>()
        let uniqueIDs = Array(eventIDs.filter { seen.insert($0).inserted }.prefix(10))
        let colorAssignments = DayObjectColorAllocator.assignments(
            eventIDs: uniqueIDs,
            rootSeed: rootSeed,
            paletteSet: paletteSet
        )
        var result = [String: DayObjectAppearance]()
        result.reserveCapacity(uniqueIDs.count)
        for eventID in uniqueIDs {
            guard let colorAssignment = colorAssignments[eventID] else { continue }
            result[eventID] = makeAppearance(
                eventID: eventID,
                rootSeed: rootSeed,
                colorAssignment: colorAssignment
            )
        }
        return result
    }

    private func makeAppearance(
        eventID: String,
        rootSeed: UInt64,
        colorAssignment: DayObjectColorAssignment
    ) -> DayObjectAppearance {
        let seed = eventSeed(rootSeed: rootSeed, eventID: eventID)
        var rng = SeededRNG.derived(from: seed, domain: "appearance")
        let material = material(eventID: eventID, rootSeed: rootSeed)
        let shape = DayObjectShape.allCases[
            rng.nextInt(in: 0...(DayObjectShape.allCases.count - 1))
        ]

        let bodyOpacity: Double
        let centerOpacity: Double
        let rimOpacity: Double
        let innerGlow: Double
        let outerGlow: Double
        let distortion: Double
        let mixing: Double
        let refractionStrength: Double
        let membraneLayerCount: Int
        switch material {
        case .satin:
            bodyOpacity = rng.nextDouble(in: 0.78...0.96)
            centerOpacity = rng.nextDouble(in: 0.72...0.95)
            rimOpacity = rng.nextDouble(in: 0.08...0.22)
            innerGlow = rng.nextDouble(in: 0.05...0.18)
            outerGlow = rng.nextDouble(in: 0.02...0.10)
            distortion = rng.nextDouble(in: 0.04...0.18)
            mixing = rng.nextDouble(in: 0.55...0.90)
            refractionStrength = 0
            membraneLayerCount = 1
        case .innerGlow:
            bodyOpacity = rng.nextDouble(in: 0.62...0.88)
            centerOpacity = rng.nextDouble(in: 0.65...0.94)
            rimOpacity = rng.nextDouble(in: 0.04...0.16)
            innerGlow = rng.nextDouble(in: 0.35...0.75)
            outerGlow = rng.nextDouble(in: 0.02...0.12)
            distortion = rng.nextDouble(in: 0.05...0.22)
            mixing = rng.nextDouble(in: 0.58...0.94)
            refractionStrength = 0
            membraneLayerCount = 1
        case .rimGlow:
            bodyOpacity = rng.nextDouble(in: 0.48...0.78)
            centerOpacity = rng.nextDouble(in: 0.30...0.60)
            rimOpacity = rng.nextDouble(in: 0.35...0.70)
            innerGlow = rng.nextDouble(in: 0.04...0.20)
            outerGlow = rng.nextDouble(in: 0.10...0.32)
            distortion = rng.nextDouble(in: 0.04...0.18)
            mixing = rng.nextDouble(in: 0.50...0.86)
            refractionStrength = 0
            membraneLayerCount = 1
        case .glass:
            bodyOpacity = rng.nextDouble(in: 0.18...0.48)
            centerOpacity = rng.nextDouble(in: 0.12...0.35)
            rimOpacity = rng.nextDouble(in: 0.25...0.55)
            innerGlow = rng.nextDouble(in: 0.02...0.16)
            outerGlow = rng.nextDouble(in: 0.04...0.18)
            distortion = rng.nextDouble(in: 0.04...0.14)
            mixing = rng.nextDouble(in: 0.45...0.80)
            refractionStrength = rng.nextDouble(in: 0.006...0.028)
            membraneLayerCount = 1
        case .membrane:
            bodyOpacity = rng.nextDouble(in: 0.32...0.64)
            centerOpacity = rng.nextDouble(in: 0.30...0.62)
            rimOpacity = rng.nextDouble(in: 0.18...0.45)
            innerGlow = rng.nextDouble(in: 0.08...0.28)
            outerGlow = rng.nextDouble(in: 0.05...0.20)
            distortion = rng.nextDouble(in: 0.06...0.24)
            mixing = rng.nextDouble(in: 0.55...0.92)
            refractionStrength = 0
            membraneLayerCount = rng.nextInt(in: 2...3)
        case .spectral:
            bodyOpacity = rng.nextDouble(in: 0.50...0.82)
            centerOpacity = rng.nextDouble(in: 0.42...0.78)
            rimOpacity = rng.nextDouble(in: 0.16...0.42)
            innerGlow = rng.nextDouble(in: 0.12...0.38)
            outerGlow = rng.nextDouble(in: 0.06...0.22)
            distortion = rng.nextDouble(in: 0.08...0.30)
            mixing = rng.nextDouble(in: 0.65...1.00)
            refractionStrength = 0
            membraneLayerCount = 1
        }

        return DayObjectAppearance(
            colorAssignment: colorAssignment,
            material: material,
            shape: shape,
            focalDistance: rng.nextDouble(in: 0.05...0.68),
            focalAngle: rng.nextDouble(in: 0...(2 * Double.pi)),
            radius: rng.nextDouble(in: 0.78...1.18),
            falloff: rng.nextDouble(in: -0.12...0.38),
            mixing: mixing,
            distortion: distortion,
            distortionShift: rng.nextDouble(in: -0.55...0.55),
            distortionFrequency: Double(rng.nextInt(in: 2...8)),
            innerGlow: innerGlow,
            outerGlow: outerGlow,
            bodyOpacity: bodyOpacity,
            centerOpacity: centerOpacity,
            rimOpacity: rimOpacity,
            refractionStrength: refractionStrength,
            refractionAngle: rng.nextDouble(in: 0...(2 * Double.pi)),
            membraneLayerCount: membraneLayerCount,
            membraneOffsets: SIMD2(
                rng.nextDouble(in: 0.03...0.12),
                rng.nextDouble(in: 0.03...0.12)
            ),
            localDepthSoftness: rng.nextDouble(in: 0.04...0.36),
            lightResponse: rng.nextDouble(in: 0.45...1.00),
            radialPhase: rng.nextDouble(in: 0...(2 * Double.pi))
        )
    }

    private func material(
        eventID: String,
        rootSeed: UInt64
    ) -> DayObjectMaterialFamily {
        let trailingDigits = eventID.reversed().prefix { $0.isNumber }.reversed()
        let index: Int
        if !trailingDigits.isEmpty, let ordinal = Int(String(trailingDigits)) {
            index = ordinal % 10
        } else {
            var hash = rootSeed ^ 0x4528_21E6_38D0_1377
            for byte in eventID.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
            }
            hash ^= hash >> 31
            index = Int(hash % 10)
        }
        let dominantIndices: Set<Int> = [0, 1, 4, 5, 8, 9]
        guard !dominantIndices.contains(index) else { return dominantMaterial }
        let accents = enabledMaterials.filter { $0 != dominantMaterial }
        let accentOrdinal: Int
        switch index {
        case 2: accentOrdinal = 0
        case 3: accentOrdinal = 1
        case 6: accentOrdinal = 2
        default: accentOrdinal = 3
        }
        return accents[accentOrdinal % accents.count]
    }

    private func eventSeed(rootSeed: UInt64, eventID: String) -> UInt64 {
        var hash = rootSeed ^ 0x1319_8A2E_0370_7344
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 30
        hash &*= 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 27
        return hash
    }
}
