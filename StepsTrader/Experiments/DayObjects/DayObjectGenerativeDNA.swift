import Foundation

enum DayObjectGeometryRegion: UInt32, CaseIterable, Equatable, Hashable {
    case circle
    case superellipse
    case softStar
    case compound
}

enum DayObjectMaterialMechanism: UInt32, CaseIterable, Equatable, Hashable {
    case solid
    case smoothRadial
    case layeredMembrane
    case boundary
    case radialFibers
    case harmonicPath
}

enum DayObjectVisualFamily: UInt32, CaseIterable, Equatable, Hashable {
    case surface
    case membrane
    case contour
    case fiber
    case harmonic
}

enum DayObjectPaletteMood: UInt32, CaseIterable, Equatable, Hashable {
    case warm
    case cool
    case saturated
    case lowContrast
}

enum DayObjectDepthMood: UInt32, CaseIterable, Equatable, Hashable {
    case depthField
    case equalMedium
    case croppedForeground
}

enum DayObjectEdgeMood: UInt32, CaseIterable, Equatable, Hashable {
    case cleanSoft
    case hairline
    case feathered
}

enum DayObjectMotionMood: UInt32, CaseIterable, Equatable, Hashable {
    case drift
    case current
    case float
}

struct DayObjectArtDirectionCoreCombination: Equatable, Hashable {
    let composition: UInt32
    let geometry: DayObjectGeometryRegion
    let material: DayObjectMaterialMechanism
}

struct DayObjectArtDirectionFingerprint: Equatable {
    let primaryFamily: DayObjectVisualFamily
    let composition: DayObjectCompositionArchetype
    let primaryGeometry: DayObjectGeometryRegion
    let supportingGeometry: DayObjectGeometryRegion?
    let primaryMaterial: DayObjectMaterialMechanism
    let accentMaterial: DayObjectMaterialMechanism?
    let paletteMood: DayObjectPaletteMood
    let depthMood: DayObjectDepthMood
    let edgeMood: DayObjectEdgeMood
    let motionMood: DayObjectMotionMood

    var coreCombination: DayObjectArtDirectionCoreCombination {
        DayObjectArtDirectionCoreCombination(
            composition: composition.rawValue,
            geometry: primaryGeometry,
            material: primaryMaterial
        )
    }

    func distance(to other: DayObjectArtDirectionFingerprint) -> Int {
        var result = 0
        if primaryFamily != other.primaryFamily { result += 1 }
        if composition != other.composition { result += 1 }
        if primaryGeometry != other.primaryGeometry { result += 1 }
        if supportingGeometry != other.supportingGeometry { result += 1 }
        if primaryMaterial != other.primaryMaterial { result += 1 }
        if accentMaterial != other.accentMaterial { result += 1 }
        if paletteMood != other.paletteMood { result += 1 }
        if depthMood != other.depthMood { result += 1 }
        if edgeMood != other.edgeMood { result += 1 }
        if motionMood != other.motionMood { result += 1 }
        return result
    }
}

struct DayObjectActorDNAResolution: Equatable {
    let geometry: DayObjectGeometryRegion
    let material: DayObjectMaterialMechanism
    let isGeometryAccent: Bool
    let isMaterialAccent: Bool
}

struct DayObjectArtDirection: Equatable {
    let seed: UInt64
    let epochIndex: Int
    let epochDay: Int
    let fingerprint: DayObjectArtDirectionFingerprint
    let primaryGeometry: DayObjectGeometryRegion
    let supportingGeometry: DayObjectGeometryRegion?
    let primaryMaterial: DayObjectMaterialMechanism
    let accentMaterial: DayObjectMaterialMechanism?
    let geometryAccentThreshold: Double
    let materialAccentThreshold: Double

    func resolution(eventID: String) -> DayObjectActorDNAResolution {
        let identity = Self.stableHash(eventID)
        let geometryUnit = Self.unit(seed ^ identity ^ 0x4745_4F4D_4554_5259)
        let materialUnit = Self.unit(seed ^ identity ^ 0x4D41_5445_5249_414C)
        let usesSupportingGeometry = supportingGeometry != nil
            && geometryUnit < geometryAccentThreshold
        let usesAccentMaterial = accentMaterial != nil
            && materialUnit < materialAccentThreshold
        return DayObjectActorDNAResolution(
            geometry: usesSupportingGeometry ? supportingGeometry! : primaryGeometry,
            material: usesAccentMaterial ? accentMaterial! : primaryMaterial,
            isGeometryAccent: usesSupportingGeometry,
            isMaterialAccent: usesAccentMaterial
        )
    }

    func supports(
        geometry: DayObjectGeometryRegion,
        material: DayObjectMaterialMechanism
    ) -> Bool {
        Self.supports(geometry: geometry, material: material)
    }

    static func supports(
        geometry: DayObjectGeometryRegion,
        material: DayObjectMaterialMechanism
    ) -> Bool {
        switch material {
        case .solid, .smoothRadial, .layeredMembrane, .boundary:
            true
        case .radialFibers:
            geometry != .compound
        case .harmonicPath:
            geometry == .circle || geometry == .softStar
        }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF2_9CE4_8422_2325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }

    private static func unit(_ seed: UInt64) -> Double {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
        state ^= state >> 31
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

enum DayObjectArtDirectionScheduler {
    private static let epochLength = 14
    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    static func make(dayKey: String, identity: String) -> DayObjectArtDirection {
        let ordinal = dayOrdinal(dayKey)
        let identityHash = stableHash(identity)
        let epochIndex = floorDivision(ordinal, by: epochLength)
        let epochDay = positiveModulo(ordinal, by: epochLength)
        let epochSeed = mixed(
            identityHash
                ^ UInt64(bitPattern: Int64(epochIndex))
                ^ 0x4550_4F43_482D_444E
        )
        let familyPhase = Int(identityHash % UInt64(DayObjectVisualFamily.allCases.count))
        let family = DayObjectVisualFamily.allCases[
            positiveModulo(ordinal + familyPhase, by: DayObjectVisualFamily.allCases.count)
        ]
        let primaryMaterial = primaryMaterial(
            for: family,
            seed: mixed(epochSeed ^ UInt64(epochDay) ^ 0x5052_494D_4152_5901)
        )
        let composition = DayObjectCompositionArchetype.allCases[
            positiveModulo(
                ordinal * 5 + Int(epochSeed % 6),
                by: DayObjectCompositionArchetype.allCases.count
            )
        ]
        let geometry = compatibleGeometry(
            preferredIndex: positiveModulo(
                ordinal * 3 + Int((epochSeed >> 8) % 4),
                by: DayObjectGeometryRegion.allCases.count
            ),
            material: primaryMaterial
        )
        let supportingGeometry = supportingGeometry(
            primary: geometry,
            primaryMaterial: primaryMaterial,
            seed: mixed(epochSeed ^ UInt64(epochDay) ^ 0x5355_5050_4F52_5402)
        )
        let accentMaterial = accentMaterial(
            for: primaryMaterial,
            geometry: supportingGeometry ?? geometry,
            seed: mixed(epochSeed ^ UInt64(epochDay) ^ 0x4143_4345_4E54_0003)
        )
        let fingerprint = DayObjectArtDirectionFingerprint(
            primaryFamily: family,
            composition: composition,
            primaryGeometry: geometry,
            supportingGeometry: supportingGeometry,
            primaryMaterial: primaryMaterial,
            accentMaterial: accentMaterial,
            paletteMood: pick(
                DayObjectPaletteMood.allCases,
                seed: epochSeed ^ UInt64(epochDay) ^ 0x5041_4C45_5454_4504
            ),
            depthMood: pick(
                DayObjectDepthMood.allCases,
                seed: epochSeed ^ UInt64(epochDay) ^ 0x4445_5054_482D_0005
            ),
            edgeMood: pick(
                DayObjectEdgeMood.allCases,
                seed: epochSeed ^ UInt64(epochDay) ^ 0x4544_4745_2D44_4E06
            ),
            motionMood: pick(
                DayObjectMotionMood.allCases,
                seed: epochSeed ^ UInt64(epochDay) ^ 0x4D4F_5449_4F4E_0007
            )
        )
        return DayObjectArtDirection(
            seed: mixed(epochSeed ^ UInt64(epochDay) ^ 0x4441_592D_444E_4108),
            epochIndex: epochIndex,
            epochDay: epochDay,
            fingerprint: fingerprint,
            primaryGeometry: geometry,
            supportingGeometry: supportingGeometry,
            primaryMaterial: primaryMaterial,
            accentMaterial: accentMaterial,
            geometryAccentThreshold: 0.10 + unit(epochSeed ^ UInt64(epochDay) ^ 0x4745_4F2D_4143_4309) * 0.15,
            materialAccentThreshold: 0.10 + unit(epochSeed ^ UInt64(epochDay) ^ 0x4D41_542D_4143_430A) * 0.15
        )
    }

    private static func primaryMaterial(
        for family: DayObjectVisualFamily,
        seed: UInt64
    ) -> DayObjectMaterialMechanism {
        switch family {
        case .surface:
            seed.isMultiple(of: 4) ? .solid : .smoothRadial
        case .membrane:
            .layeredMembrane
        case .contour:
            .boundary
        case .fiber:
            .radialFibers
        case .harmonic:
            .harmonicPath
        }
    }

    private static func compatibleGeometry(
        preferredIndex: Int,
        material: DayObjectMaterialMechanism
    ) -> DayObjectGeometryRegion {
        let geometries = DayObjectGeometryRegion.allCases
        for offset in geometries.indices {
            let geometry = geometries[(preferredIndex + offset) % geometries.count]
            if DayObjectArtDirection.supports(geometry: geometry, material: material) {
                return geometry
            }
        }
        return .circle
    }

    private static func supportingGeometry(
        primary: DayObjectGeometryRegion,
        primaryMaterial: DayObjectMaterialMechanism,
        seed: UInt64
    ) -> DayObjectGeometryRegion? {
        let candidates = DayObjectGeometryRegion.allCases.filter {
            $0 != primary
                && DayObjectArtDirection.supports(geometry: $0, material: primaryMaterial)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(seed % UInt64(candidates.count))]
    }

    private static func accentMaterial(
        for primary: DayObjectMaterialMechanism,
        geometry: DayObjectGeometryRegion,
        seed: UInt64
    ) -> DayObjectMaterialMechanism? {
        let candidates: [DayObjectMaterialMechanism] = switch primary {
        case .solid: [.smoothRadial, .boundary]
        case .smoothRadial: [.layeredMembrane, .boundary]
        case .layeredMembrane: [.boundary, .smoothRadial]
        case .boundary: [.solid, .smoothRadial]
        case .radialFibers, .harmonicPath: [.boundary]
        }
        let compatible = candidates.filter {
            DayObjectArtDirection.supports(geometry: geometry, material: $0)
        }
        guard !compatible.isEmpty else { return nil }
        return compatible[Int(seed % UInt64(compatible.count))]
    }

    private static func dayOrdinal(_ dayKey: String) -> Int {
        let components = dayKey.split(separator: "-")
        if components.count == 3,
           let year = Int(components[0]),
           let month = Int(components[1]),
           let day = Int(components[2]) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            if let date = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )) {
                return calendar.dateComponents([.day], from: referenceDate, to: date).day ?? 0
            }
        }
        return Int(truncatingIfNeeded: stableHash(dayKey))
    }

    private static func floorDivision(_ value: Int, by divisor: Int) -> Int {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    private static func positiveModulo(_ value: Int, by divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func pick<T>(_ values: [T], seed: UInt64) -> T {
        values[Int(mixed(seed) % UInt64(values.count))]
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(0xCBF2_9CE4_8422_2325) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }

    private static func mixed(_ value: UInt64) -> UInt64 {
        var state = value &+ 0x9E37_79B9_7F4A_7C15
        state = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9
        state = (state ^ (state >> 27)) &* 0x94D0_49BB_1331_11EB
        return state ^ (state >> 31)
    }

    private static func unit(_ value: UInt64) -> Double {
        Double(mixed(value) >> 11) / Double(UInt64(1) << 53)
    }
}
