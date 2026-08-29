import Foundation
import simd

/// One coherent optical universe is selected for a whole day. These cases are
/// the Metal equivalents of the recipes in random-gradient-circle.html.
enum DayObjectMaterialFamily: UInt32, CaseIterable, Equatable {
    case gradient
    case solid
    case sphere
    case glass
    case mist
    case halo
    case luminous
    case outline
    case counterform

    // Compatibility names for older fixtures while the rendering tests move
    // to the HTML recipe vocabulary.
    static let softVolume = gradient
    static let livingGlass = glass
    static let innerLight = luminous
    static let atmosphericOrb = mist
    static let layeredMembrane = gradient
    static let satin = gradient
    static let innerGlow = luminous
    static let rimGlow = halo
    static let spectral = mist
    static let membrane = gradient
}

enum DayObjectMutationRole: UInt32, CaseIterable, Equatable {
    case base
    case soft
    case accent
}

struct DayObjectRadialLayer: Equatable {
    let focalOffset: SIMD2<Double>
    let radius: Double
    let softness: Double
    let opacity: Double
}

struct DayObjectAppearance: Equatable {
    let colorAssignment: DayObjectColorAssignment
    let material: DayObjectMaterialFamily
    let mutationRole: DayObjectMutationRole
    let shape: DayObjectShape
    let elongation: Double
    let layers: [DayObjectRadialLayer]
    let colorStopLocations: SIMD2<Double>
    let edgeSoftness: Double
    let minimumOpacity: Double
    let outlineCount: Int
    let outlineWidth: Double
    let outlineSpacing: Double
    let outlineWobble: Double
    let counterformRadius: Double
    let counterformSoftness: Double
    let coronaWidth: Double
    let coronaIntensity: Double

    // Compatibility fields consumed by the current GPU upload. The layered
    // renderer replaces these with the complete array in the Metal task.
    let focalDistance: Double
    let focalAngle: Double
    let radius: Double
    let falloff: Double
    let mixing: Double
    let distortion: Double
    let distortionShift: Double
    let distortionFrequency: Double
    let distortionPhase: Double
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
    let family: DayObjectMaterialFamily
    let baseShape: DayObjectShape
    let baseElongation: Double
    let maximumElongation: Double
    let accentShare: Double
    let lightDirection: SIMD2<Double>
    let lightSoftness: Double
    let grainIntensity: Double

    var enabledMaterials: [DayObjectMaterialFamily] { [family] }
    var dominantMaterial: DayObjectMaterialFamily { family }

    static func make(
        rootSeed: UInt64,
        paletteSet: DayObjectPaletteSet,
        choreography: DayObjectChoreographyConfiguration
    ) -> DayObjectVisualLanguage {
        var rng = SeededRNG.derived(from: rootSeed, domain: "dailyVisualLanguage")
        let weightedRecipes = DayObjectMaterialFamily.allCases.flatMap { family in
            Array(repeating: family, count: choreography.materialWeight(for: family))
        }
        let family = weightedRecipes[
            rng.nextInt(in: 0...(weightedRecipes.count - 1))
        ]
        let lightAngle = rng.nextDouble(in: 0...(2 * Double.pi))
        return DayObjectVisualLanguage(
            paletteSet: paletteSet,
            family: family,
            baseShape: .sphere,
            baseElongation: 1,
            maximumElongation: 0.05,
            accentShare: rng.nextDouble(in: 0.15...0.30),
            lightDirection: SIMD2(cos(lightAngle), sin(lightAngle)),
            lightSoftness: rng.nextDouble(in: 0.40...0.85),
            grainIntensity: 0.05
        )
    }

    static func make(
        rootSeed: UInt64,
        paletteSet: DayObjectPaletteSet
    ) -> DayObjectVisualLanguage {
        make(
            rootSeed: rootSeed,
            paletteSet: paletteSet,
            choreography: DayObjectChoreographyConfiguration.make(seed: rootSeed)
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
                colorAssignment: colorAssignment,
                mutationRole: mutationRole(eventID: eventID, rootSeed: rootSeed)
            )
        }
        return result
    }

    private func makeAppearance(
        eventID: String,
        rootSeed: UInt64,
        colorAssignment: DayObjectColorAssignment,
        mutationRole: DayObjectMutationRole
    ) -> DayObjectAppearance {
        let seed = eventSeed(rootSeed: rootSeed, eventID: eventID)
        var rng = SeededRNG.derived(from: seed, domain: "appearance")
        let layerCount = family == .gradient && mutationRole == .base
            ? 2
            : rng.nextInt(in: 2...3)
        let layers = (0..<layerCount).map { index in
            let angle = rng.nextDouble(in: 0...(2 * Double.pi))
            let maximumDistance = index == 0 ? 0.58 : 0.68
            let distance = rng.nextDouble(
                in: index == 0 ? 0.04...maximumDistance : 0.10...maximumDistance
            )
            return DayObjectRadialLayer(
                focalOffset: SIMD2(cos(angle), sin(angle)) * distance,
                radius: rng.nextDouble(in: index == 0 ? 0.72...1.18 : 0.42...0.92),
                softness: rng.nextDouble(in: 0.12...0.48),
                opacity: rng.nextDouble(in: index == 0 ? 0.64...1 : 0.18...0.76)
            )
        }
        let primaryLayer = layers[0]
        let firstStop = rng.nextDouble(in: 0.22...0.48)
        let secondStop = rng.nextDouble(in: max(firstStop + 0.16, 0.58)...0.88)
        let edgeSoftness: Double = switch family {
        case .solid, .gradient, .glass: rng.nextDouble(in: 0...0.08)
        case .sphere: rng.nextDouble(in: 0.03...0.12)
        case .outline: rng.nextDouble(in: 0.02...0.10)
        case .mist, .halo, .luminous, .counterform:
            rng.nextDouble(in: 0.16...0.42)
        }
        let outlineCount = family == .outline ? rng.nextInt(in: 1...3) : 0
        let outlineWidth = family == .outline ? rng.nextDouble(in: 0.012...0.075) : 0
        let outlineSpacing = family == .outline ? rng.nextDouble(in: 0.02...0.09) : 0
        let outlineWobble = family == .outline ? rng.nextDouble(in: 0.01...0.08) : 0
        let counterformRadius = family == .counterform
            ? rng.nextDouble(in: 0.44...0.62)
            : 0
        let counterformSoftness = family == .counterform
            ? rng.nextDouble(in: 0.01...0.08)
            : 0
        let coronaWidth = family == .counterform
            ? rng.nextDouble(in: 0.14...0.34)
            : 0
        let coronaIntensity = family == .counterform
            ? rng.nextDouble(in: 0.58...0.98)
            : 0
        let elongationScale: Double
        switch mutationRole {
        case .base: elongationScale = 0.35
        case .soft: elongationScale = 0.70
        case .accent: elongationScale = 1
        }
        let elongation = baseElongation
            + rng.nextDouble(in: -maximumElongation...maximumElongation) * elongationScale

        let optical = opticalRanges(for: family)
        let accentBoost = mutationRole == .accent ? 1.12 : 1
        let innerGlow = min(rng.nextDouble(in: optical.innerGlow) * accentBoost, 1)
        let outerGlow = min(rng.nextDouble(in: optical.outerGlow) * accentBoost, 1)
        let refractionStrength = family == .glass
            ? rng.nextDouble(in: 0.006...0.028)
            : 0

        return DayObjectAppearance(
            colorAssignment: colorAssignment,
            material: family,
            mutationRole: mutationRole,
            shape: baseShape,
            elongation: elongation,
            layers: layers,
            colorStopLocations: SIMD2(firstStop, secondStop),
            edgeSoftness: edgeSoftness,
            minimumOpacity: minimumOpacity(for: family),
            outlineCount: outlineCount,
            outlineWidth: outlineWidth,
            outlineSpacing: outlineSpacing,
            outlineWobble: outlineWobble,
            counterformRadius: counterformRadius,
            counterformSoftness: counterformSoftness,
            coronaWidth: coronaWidth,
            coronaIntensity: coronaIntensity,
            focalDistance: simd_length(primaryLayer.focalOffset),
            focalAngle: atan2(primaryLayer.focalOffset.y, primaryLayer.focalOffset.x),
            radius: primaryLayer.radius,
            falloff: primaryLayer.softness - 0.24,
            mixing: primaryLayer.opacity,
            distortion: rng.nextDouble(in: 0...0.18),
            distortionShift: rng.nextDouble(in: -0.55...0.55),
            distortionFrequency: rng.nextDouble(in: 0.8...4),
            distortionPhase: rng.nextDouble(in: 0...(2 * Double.pi)),
            innerGlow: innerGlow,
            outerGlow: outerGlow,
            bodyOpacity: rng.nextDouble(in: optical.bodyOpacity),
            centerOpacity: rng.nextDouble(in: optical.centerOpacity),
            rimOpacity: rng.nextDouble(in: optical.rimOpacity),
            refractionStrength: refractionStrength,
            refractionAngle: rng.nextDouble(in: 0...(2 * Double.pi)),
            membraneLayerCount: layerCount,
            membraneOffsets: SIMD2(
                rng.nextDouble(in: 0.03...0.10),
                rng.nextDouble(in: 0.03...0.10)
            ),
            localDepthSoftness: rng.nextDouble(in: optical.depthSoftness),
            lightResponse: rng.nextDouble(in: 0.45...1),
            radialPhase: rng.nextDouble(in: 0...1)
        )
    }

    private func mutationRole(
        eventID: String,
        rootSeed: UInt64
    ) -> DayObjectMutationRole {
        switch stableOrdinal(eventID: eventID, rootSeed: rootSeed) % 10 {
        case 3, 8: .accent
        case 1, 4, 6, 9: .soft
        default: .base
        }
    }

    private func stableOrdinal(eventID: String, rootSeed: UInt64) -> Int {
        let trailingDigits = eventID.reversed().prefix { $0.isNumber }.reversed()
        if !trailingDigits.isEmpty, let ordinal = Int(String(trailingDigits)) {
            return ordinal
        }
        return Int(materialPriority(eventID, rootSeed: rootSeed) % 10)
    }

    private struct OpticalRanges {
        let bodyOpacity: ClosedRange<Double>
        let centerOpacity: ClosedRange<Double>
        let rimOpacity: ClosedRange<Double>
        let innerGlow: ClosedRange<Double>
        let outerGlow: ClosedRange<Double>
        let depthSoftness: ClosedRange<Double>
    }

    private func opticalRanges(for family: DayObjectMaterialFamily) -> OpticalRanges {
        switch family {
        case .gradient:
            OpticalRanges(
                bodyOpacity: 0.78...0.96, centerOpacity: 0.72...0.95,
                rimOpacity: 0.08...0.22, innerGlow: 0.06...0.20,
                outerGlow: 0.01...0.08, depthSoftness: 0.04...0.18
            )
        case .solid:
            OpticalRanges(
                bodyOpacity: 0.92...1, centerOpacity: 0.92...1,
                rimOpacity: 0.04...0.12, innerGlow: 0.03...0.12,
                outerGlow: 0.01...0.05, depthSoftness: 0.02...0.10
            )
        case .sphere:
            OpticalRanges(
                bodyOpacity: 0.84...1, centerOpacity: 0.80...1,
                rimOpacity: 0.18...0.38, innerGlow: 0.12...0.32,
                outerGlow: 0.02...0.10, depthSoftness: 0.03...0.15
            )
        case .glass:
            OpticalRanges(
                bodyOpacity: 0.62...0.82, centerOpacity: 0.68...0.88,
                rimOpacity: 0.24...0.56, innerGlow: 0.03...0.16,
                outerGlow: 0.04...0.16, depthSoftness: 0.08...0.28
            )
        case .mist:
            OpticalRanges(
                bodyOpacity: 0.60...0.82, centerOpacity: 0.64...0.88,
                rimOpacity: 0.08...0.22, innerGlow: 0.10...0.30,
                outerGlow: 0.08...0.24, depthSoftness: 0.14...0.32
            )
        case .halo:
            OpticalRanges(
                bodyOpacity: 0.66...0.88, centerOpacity: 0.70...0.94,
                rimOpacity: 0.18...0.42, innerGlow: 0.18...0.46,
                outerGlow: 0.28...0.58, depthSoftness: 0.08...0.24
            )
        case .luminous:
            OpticalRanges(
                bodyOpacity: 0.68...0.92, centerOpacity: 0.78...1,
                rimOpacity: 0.10...0.28, innerGlow: 0.42...0.78,
                outerGlow: 0.12...0.34, depthSoftness: 0.06...0.22
            )
        case .outline:
            OpticalRanges(
                bodyOpacity: 0.78...1, centerOpacity: 0.78...1,
                rimOpacity: 0.60...1, innerGlow: 0.08...0.24,
                outerGlow: 0.08...0.24, depthSoftness: 0.04...0.18
            )
        case .counterform:
            OpticalRanges(
                bodyOpacity: 0.76...0.96, centerOpacity: 0.78...1,
                rimOpacity: 0.48...0.88, innerGlow: 0.18...0.48,
                outerGlow: 0.16...0.42, depthSoftness: 0.06...0.22
            )
        }
    }

    private func minimumOpacity(for family: DayObjectMaterialFamily) -> Double {
        switch family {
        case .gradient: 0.72
        case .solid: 0.88
        case .sphere: 0.82
        case .glass: 0.62
        case .mist: 0.58
        case .halo: 0.64
        case .luminous: 0.68
        case .outline: 0.72
        case .counterform: 0.72
        }
    }

    private func materialPriority(_ eventID: String, rootSeed: UInt64) -> UInt64 {
        var hash = rootSeed ^ 0x4528_21E6_38D0_1377
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        hash ^= hash >> 31
        return hash
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
