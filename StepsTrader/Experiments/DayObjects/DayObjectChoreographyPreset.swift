import Foundation
import simd

enum DayObjectChoreographyPreset: UInt32, CaseIterable, Equatable {
    case circularChoir, doubleOrbit, radialBloom, breathingGrid, waveRibbon
    case spiralProcession, eclipseStack, crossCurrents, constellation, depthField
}

enum DayObjectSizeProfile: Equatable {
    case uniform, grouped, spatial
}

enum DayObjectDepthProfile: Equatable {
    case flat, layered, migrating
}

struct DayObjectChoreographySlot: Equatable {
    let ordinal: Int
    let group: Int
    let anchor: SIMD2<Double>
    let phase: Double
    let direction: Double
    let sizeMultiplier: Double
    let baseDepth: Double
}

struct DayObjectChoreographyConfiguration: Equatable {
    let preset: DayObjectChoreographyPreset
    let sizeProfile: DayObjectSizeProfile
    let depthProfile: DayObjectDepthProfile
    let center: SIMD2<Double>
    let orientation: Double
    let eccentricity: Double
    let slots: [DayObjectChoreographySlot]

    static func make(seed: UInt64) -> Self {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectChoreographyPreset")
        let preset = DayObjectChoreographyPreset.allCases[
            rng.nextInt(in: 0...(DayObjectChoreographyPreset.allCases.count - 1))
        ]
        let profile = profiles[preset]!
        let center = SIMD2(
            clamp(rng.nextDouble(in: 0...1), to: 0.18...0.82),
            clamp(rng.nextDouble(in: 0...1), to: 0.18...0.82)
        )
        let orientation = rng.nextDouble(in: 0...(2 * Double.pi))
        let eccentricity = clamp(rng.nextDouble(in: 0.60...1.40), to: 0.72...1.28)
        let slots = (0..<10).map { ordinal in
            let angle = orientation + 2 * Double.pi * Double(ordinal) / 10
            let radius = 0.16 + 0.20 * rng.nextDouble()
            let anchor = SIMD2(
                clamp(center.x + cos(angle) * radius * eccentricity, to: 0.18...0.82),
                clamp(center.y + sin(angle) * radius, to: 0.18...0.82)
            )
            return DayObjectChoreographySlot(
                ordinal: ordinal,
                group: ordinal / 2,
                anchor: anchor,
                phase: Double(ordinal) / 10 + 0.04 * (rng.nextDouble() - 0.5),
                direction: ordinal.isMultiple(of: 2) ? 1 : -1,
                sizeMultiplier: sizeMultiplier(for: ordinal, profile: profile.0),
                baseDepth: baseDepth(for: ordinal, profile: profile.1)
            )
        }
        return Self(
            preset: preset,
            sizeProfile: profile.0,
            depthProfile: profile.1,
            center: center,
            orientation: orientation,
            eccentricity: eccentricity,
            slots: slots
        )
    }

    func slot(eventID: String, rootSeed: UInt64) -> DayObjectChoreographySlot {
        let event = stableEventHash(eventID, rootSeed: rootSeed)
        if let numericOrdinal = event.numericOrdinal {
            return slots[numericOrdinal % 10]
        }
        let slot = slots[Int(event.hash % 10)]
        let offset = Double(event.hash >> 11) / Double(UInt64(1) << 53) * 0.08
        return DayObjectChoreographySlot(
            ordinal: slot.ordinal,
            group: slot.group,
            anchor: slot.anchor,
            phase: Self.normalizedPhase(slot.phase + offset),
            direction: slot.direction,
            sizeMultiplier: slot.sizeMultiplier,
            baseDepth: slot.baseDepth
        )
    }

    func materialWeight(for family: DayObjectMaterialFamily) -> Int {
        let preferred: Set<DayObjectMaterialFamily> = switch preset {
        case .circularChoir, .doubleOrbit, .radialBloom:
            [.sphere, .glass, .halo]
        case .breathingGrid, .waveRibbon, .crossCurrents:
            [.gradient, .solid, .outline]
        case .spiralProcession, .eclipseStack, .constellation:
            [.gradient, .luminous, .counterform]
        case .depthField:
            [.mist, .glass, .luminous]
        }
        return preferred.contains(family) ? 3 : 1
    }

    private static let profiles: [DayObjectChoreographyPreset: (DayObjectSizeProfile, DayObjectDepthProfile)] = [
        .circularChoir: (.uniform, .flat), .doubleOrbit: (.grouped, .flat),
        .radialBloom: (.uniform, .flat), .breathingGrid: (.uniform, .flat),
        .waveRibbon: (.uniform, .flat), .spiralProcession: (.grouped, .flat),
        .eclipseStack: (.grouped, .layered), .crossCurrents: (.grouped, .layered),
        .constellation: (.grouped, .layered), .depthField: (.spatial, .migrating),
    ]

    private static func sizeMultiplier(for ordinal: Int, profile: DayObjectSizeProfile) -> Double {
        switch profile {
        case .uniform:
            return 1
        case .grouped:
            return ordinal / 2 == 0 ? 1.25 : (ordinal / 2).isMultiple(of: 2) ? 1.05 : 0.85
        case .spatial:
            return 0.80 + 0.40 * Double(ordinal) / 9
        }
    }

    private static func baseDepth(for ordinal: Int, profile: DayObjectDepthProfile) -> Double {
        switch profile {
        case .flat:
            return 0.5
        case .layered:
            return 0.22 + 0.56 * Double(ordinal) / 9
        case .migrating:
            return 0.15 + 0.70 * Double(ordinal) / 9
        }
    }

    private func stableEventHash(_ eventID: String, rootSeed: UInt64) -> (hash: UInt64, numericOrdinal: Int?) {
        var hash = rootSeed ^ 0xCBF2_9CE4_8422_2325
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        return (hash, Self.numericEventOrdinal(eventID))
    }

    private static func numericEventOrdinal(_ eventID: String) -> Int? {
        guard eventID.hasPrefix("event-"),
              let ordinal = Int(eventID.dropFirst("event-".count)),
              ordinal >= 0 else { return nil }
        return ordinal
    }

    private static func normalizedPhase(_ phase: Double) -> Double {
        let remainder = phase.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
