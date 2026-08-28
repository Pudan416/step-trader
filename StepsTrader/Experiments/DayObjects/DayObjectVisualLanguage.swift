import Foundation
import simd

/// One coherent optical universe is selected for a whole day. The legacy
/// aliases keep older fixtures source-compatible while they migrate to the
/// five approved circle families.
enum DayObjectMaterialFamily: UInt32, CaseIterable, Equatable {
    case softVolume
    case livingGlass
    case innerLight
    case atmosphericOrb
    case layeredMembrane

    static let satin = softVolume
    static let glass = livingGlass
    static let innerGlow = innerLight
    static let rimGlow = innerLight
    static let spectral = atmosphericOrb
    static let membrane = layeredMembrane
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
        paletteSet: DayObjectPaletteSet
    ) -> DayObjectVisualLanguage {
        var rng = SeededRNG.derived(from: rootSeed, domain: "dailyVisualLanguage")
        let family = DayObjectMaterialFamily.allCases[
            rng.nextInt(in: 0...(DayObjectMaterialFamily.allCases.count - 1))
        ]
        let circleShapes: [DayObjectShape] = [.sphere, .softBlob]
        let lightAngle = rng.nextDouble(in: 0...(2 * Double.pi))
        return DayObjectVisualLanguage(
            paletteSet: paletteSet,
            family: family,
            baseShape: circleShapes[rng.nextInt(in: 0...(circleShapes.count - 1))],
            baseElongation: 1,
            maximumElongation: 0.05,
            accentShare: rng.nextDouble(in: 0.15...0.30),
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
        let layerCount = family == .softVolume && mutationRole == .base
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
        let refractionStrength = family == .livingGlass
            ? rng.nextDouble(in: 0.006...0.028)
            : 0

        return DayObjectAppearance(
            colorAssignment: colorAssignment,
            material: family,
            mutationRole: mutationRole,
            shape: baseShape,
            elongation: elongation,
            layers: layers,
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
        case .softVolume:
            OpticalRanges(
                bodyOpacity: 0.78...0.96, centerOpacity: 0.72...0.95,
                rimOpacity: 0.08...0.22, innerGlow: 0.06...0.20,
                outerGlow: 0.01...0.08, depthSoftness: 0.04...0.18
            )
        case .livingGlass:
            OpticalRanges(
                bodyOpacity: 0.44...0.68, centerOpacity: 0.56...0.82,
                rimOpacity: 0.24...0.56, innerGlow: 0.03...0.16,
                outerGlow: 0.04...0.16, depthSoftness: 0.08...0.28
            )
        case .innerLight:
            OpticalRanges(
                bodyOpacity: 0.58...0.86, centerOpacity: 0.64...0.94,
                rimOpacity: 0.06...0.20, innerGlow: 0.34...0.72,
                outerGlow: 0.03...0.14, depthSoftness: 0.06...0.24
            )
        case .atmosphericOrb:
            OpticalRanges(
                bodyOpacity: 0.50...0.78, centerOpacity: 0.50...0.78,
                rimOpacity: 0.10...0.30, innerGlow: 0.10...0.30,
                outerGlow: 0.06...0.22, depthSoftness: 0.18...0.36
            )
        case .layeredMembrane:
            OpticalRanges(
                bodyOpacity: 0.48...0.72, centerOpacity: 0.50...0.78,
                rimOpacity: 0.16...0.42, innerGlow: 0.08...0.26,
                outerGlow: 0.04...0.18, depthSoftness: 0.08...0.28
            )
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
