import Foundation
import simd

enum DayObjectChoreographyFamily: UInt32, CaseIterable, Equatable {
    case driftField
    case crossCurrent
    case tidalSweep
    case depthMigration
    case softEncounters
}

struct DayObjectRoute: Equatable {
    let controlPoints: [SIMD2<Double>]
    let period: Double
    let phase: Double
    let direction: Double
    let sector: Int

    func position(at rawTime: Double) -> SIMD2<Double> {
        guard controlPoints.count >= 4, period.isFinite, period > 0 else {
            return controlPoints.first ?? .zero
        }
        let time = rawTime.isFinite ? rawTime : 0
        let rawProgress = phase + direction * time / period
        let progress = rawProgress - floor(rawProgress)
        let scaled = progress * Double(controlPoints.count)
        let index = Int(floor(scaled)) % controlPoints.count
        let local = scaled - floor(scaled)
        let count = controlPoints.count
        return Self.centripetalCatmullRom(
            controlPoints[(index - 1 + count) % count],
            controlPoints[index],
            controlPoints[(index + 1) % count],
            controlPoints[(index + 2) % count],
            progress: local
        )
    }

    private static func centripetalCatmullRom(
        _ p0: SIMD2<Double>,
        _ p1: SIMD2<Double>,
        _ p2: SIMD2<Double>,
        _ p3: SIMD2<Double>,
        progress: Double
    ) -> SIMD2<Double> {
        func interval(_ lhs: SIMD2<Double>, _ rhs: SIMD2<Double>) -> Double {
            max(pow(simd_distance(lhs, rhs), 0.5), 0.000_001)
        }
        func mix(
            _ lhs: SIMD2<Double>,
            _ rhs: SIMD2<Double>,
            from start: Double,
            to end: Double,
            at value: Double
        ) -> SIMD2<Double> {
            let denominator = max(end - start, 0.000_001)
            return ((end - value) * lhs + (value - start) * rhs) / denominator
        }

        let t0 = 0.0
        let t1 = t0 + interval(p0, p1)
        let t2 = t1 + interval(p1, p2)
        let t3 = t2 + interval(p2, p3)
        let t = t1 + min(max(progress, 0), 1) * (t2 - t1)
        let a1 = mix(p0, p1, from: t0, to: t1, at: t)
        let a2 = mix(p1, p2, from: t1, to: t2, at: t)
        let a3 = mix(p2, p3, from: t2, to: t3, at: t)
        let b1 = mix(a1, a2, from: t0, to: t2, at: t)
        let b2 = mix(a2, a3, from: t1, to: t3, at: t)
        return mix(b1, b2, from: t1, to: t2, at: t)
    }
}

struct DayObjectDepthSchedule: Equatable {
    let baseDepth: Double
    let amplitude: Double
    let period: Double
    let phase: Double
}

struct DayObjectEncounter: Equatable {
    let channel: Int
    let phase: Double
    let durationFraction: Double
    let overlapFraction: Double
    let memberOrdinal: Int
    let memberCount: Int
}

struct DayObjectMotionPlan: Equatable {
    let configuration: DayObjectChoreographyConfiguration
    let routes: [String: DayObjectRoute]
    let depths: [String: DayObjectDepthSchedule]
    let encounters: [String: DayObjectEncounter]

    var preset: DayObjectChoreographyPreset { configuration.preset }

    // Transitional display compatibility until the scene and score migrate to
    // the ten-preset vocabulary together.
    var family: DayObjectChoreographyFamily {
        switch preset {
        case .crossCurrents:
            return .crossCurrent
        case .waveRibbon:
            return .tidalSweep
        case .depthField:
            return .depthMigration
        case .eclipseStack:
            return .softEncounters
        default:
            return .driftField
        }
    }

    static func make(rootSeed: UInt64, eventIDs: [String]) -> DayObjectMotionPlan {
        make(
            configuration: DayObjectChoreographyConfiguration.make(seed: rootSeed),
            rootSeed: rootSeed,
            eventIDs: eventIDs
        )
    }

    static func make(
        configuration: DayObjectChoreographyConfiguration,
        rootSeed: UInt64,
        eventIDs: [String]
    ) -> DayObjectMotionPlan {
        var seen = Set<String>()
        let ids = eventIDs.filter { seen.insert($0).inserted }.prefix(DayObjectScene.maxActors)
        var routes = [String: DayObjectRoute]()
        var depths = [String: DayObjectDepthSchedule]()
        var encounters = [String: DayObjectEncounter]()

        for eventID in ids {
            let seed = eventSeed(rootSeed: rootSeed, eventID: eventID)
            let slot = configuration.slot(eventID: eventID, rootSeed: rootSeed)
            // Ten stable encounter slots map to five shared pair channels. The
            // slot is derived only from the event ID, so removing another
            // happening never rerolls an existing orb's meeting geometry.
            let encounterSlot = slot.ordinal
            let encounterChannel = encounterSlot / 2
            let encounterMemberOrdinal = encounterSlot % 2
            let encounterMemberCount = 2
            let encounterSeed = mixed(
                rootSeed ^ UInt64(encounterChannel) &* 0x9E37_79B9_7F4A_7C15
            )
            routes[eventID] = makeRoute(
                configuration: configuration,
                slot: slot,
                seed: seed,
                rootSeed: rootSeed
            )
            depths[eventID] = makeDepthSchedule(
                profile: configuration.depthProfile,
                slot: slot,
                seed: seed
            )
            encounters[eventID] = DayObjectEncounter(
                channel: encounterChannel,
                phase: normalizedPhase(
                    stableUnit(rootSeed, salt: 0xC0AC_29B7_C97C_50DD)
                        + Double(encounterChannel) / 5
                ),
                durationFraction: 0.05 + 0.13 * stableUnit(encounterSeed, salt: 0x3F84_D5B5_B547_0917),
                overlapFraction: 0.15 + 0.25 * stableUnit(encounterSeed, salt: 0x9216_D5D9_8979_FB1B),
                memberOrdinal: encounterMemberOrdinal,
                memberCount: encounterMemberCount
            )
        }

        return DayObjectMotionPlan(
            configuration: configuration,
            routes: routes,
            depths: depths,
            encounters: encounters
        )
    }

    private static func normalizedPhase(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private static func makeRoute(
        configuration: DayObjectChoreographyConfiguration,
        slot: DayObjectChoreographySlot,
        seed: UInt64,
        rootSeed: UInt64
    ) -> DayObjectRoute {
        let anchor = centered(slot.anchor)
        let pointCount = configuration.preset == .spiralProcession ? 10 : 8
        let points: [SIMD2<Double>]
        switch configuration.preset {
        case .circularChoir:
            points = angularLoop(
                center: anchor,
                radius: SIMD2(repeating: 0.075),
                rotation: configuration.orientation,
                count: pointCount
            )
        case .doubleOrbit:
            let radius = slot.group.isMultiple(of: 2) ? 0.065 : 0.105
            points = angularLoop(
                center: anchor,
                radius: SIMD2(radius * configuration.eccentricity, radius),
                rotation: configuration.orientation,
                count: pointCount
            )
        case .radialBloom:
            let spoke = atan2(
                slot.anchor.y - configuration.center.y,
                slot.anchor.x - configuration.center.x
            )
            points = angularLoop(
                center: anchor,
                radius: SIMD2(0.115, 0.018),
                rotation: -spoke,
                count: pointCount
            )
        case .breathingGrid:
            let stagger = slot.group.isMultiple(of: 2) ? -0.012 : 0.012
            points = angularLoop(
                center: anchor + SIMD2(stagger, 0),
                radius: SIMD2(0.045, 0.030),
                rotation: 0,
                count: pointCount
            )
        case .waveRibbon:
            let ribbonCenter = anchor + SIMD2(
                0,
                0.045 * sin(Double(slot.ordinal) * .pi / 5)
            )
            points = angularLoop(
                center: ribbonCenter,
                radius: SIMD2(0.055, 0.018),
                rotation: 0,
                count: pointCount
            )
        case .spiralProcession:
            points = (0..<pointCount).map { index in
                let half = Double(pointCount) / 2
                let outwardProgress = 1 - abs(Double(index) - half) / half
                let radius = 0.025 * exp(log(0.11 / 0.025) * outwardProgress)
                let angle = configuration.orientation
                    + 2 * Double.pi * Double(index) / Double(pointCount)
                return anchor + SIMD2(radius * cos(angle), radius * sin(angle))
            }
        case .eclipseStack:
            let groupSlots = configuration.slots.filter { $0.group == slot.group }
            let sharedAnchor = groupSlots.map { centered($0.anchor) }
                .reduce(.zero, +) / Double(max(groupSlots.count, 1))
            let memberSign = slot.ordinal.isMultiple(of: 2) ? 1.0 : -1.0
            let separationAxis = configuration.orientation + Double(slot.group) * .pi / 5
            let separationVector = SIMD2(
                0.36 * memberSign * cos(separationAxis),
                0.36 * memberSign * sin(separationAxis)
            )
            points = (0..<pointCount).map { index in
                let angle = 2 * Double.pi * Double(index) / Double(pointCount)
                let separation = 0.5 - 0.5 * cos(angle)
                return sharedAnchor + separationVector * separation
                    + (anchor - sharedAnchor) * 0.15 * separation
                    + SIMD2(0.035 * sin(angle), 0.018 * sin(2 * angle))
            }
        case .crossCurrents:
            points = angularLoop(
                center: anchor,
                radius: SIMD2(0.125, 0.025),
                rotation: slot.direction > 0 ? 0.10 : -0.10,
                count: pointCount
            )
        case .constellation:
            let radius = 0.026 + 0.006 * Double(slot.group)
            points = angularLoop(
                center: anchor,
                radius: SIMD2(radius, radius * 0.8),
                rotation: configuration.orientation + Double(slot.ordinal) * .pi / 10,
                count: pointCount
            )
        case .depthField:
            points = angularLoop(
                center: anchor,
                radius: SIMD2(0.105, 0.060),
                rotation: configuration.orientation + Double(slot.group) * .pi / 8,
                count: pointCount
            )
        }

        let routeSeed = configuration.preset == .eclipseStack
            ? mixed(rootSeed ^ UInt64(slot.group) &* 0xD6E8_FEB8_6659_FD93)
            : seed
        return DayObjectRoute(
            controlPoints: points,
            period: 90 + 130 * stableUnit(routeSeed, salt: 0xF6BB_4B60_9FBC_CEAE),
            phase: configuration.preset == .eclipseStack ? 0 : normalizedPhase(slot.phase),
            direction: direction(for: configuration.preset, slot: slot),
            sector: sector(for: configuration.preset, slot: slot)
        )
    }

    private static func makeDepthSchedule(
        profile: DayObjectDepthProfile,
        slot: DayObjectChoreographySlot,
        seed: UInt64
    ) -> DayObjectDepthSchedule {
        let baseDepth: Double
        let amplitude: Double
        switch profile {
        case .flat:
            baseDepth = 0.55
            amplitude = 0.04 * stableUnit(seed, salt: 0xA409_3822_299F_31D0)
        case .layered:
            baseDepth = slot.baseDepth
            amplitude = 0.10 + 0.12 * stableUnit(seed, salt: 0xA409_3822_299F_31D0)
        case .migrating:
            baseDepth = slot.baseDepth
            amplitude = 0.36 + 0.11 * stableUnit(seed, salt: 0xA409_3822_299F_31D0)
        }
        return DayObjectDepthSchedule(
            baseDepth: baseDepth,
            amplitude: amplitude,
            period: 90 + 130 * stableUnit(seed, salt: 0x082E_FA98_EC4E_6C89),
            phase: normalizedPhase(slot.phase)
        )
    }

    private static func angularLoop(
        center: SIMD2<Double>,
        radius: SIMD2<Double>,
        rotation: Double,
        count: Int
    ) -> [SIMD2<Double>] {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            let local = SIMD2(radius.x * cos(angle), radius.y * sin(angle))
            return center + SIMD2(
                local.x * cosine - local.y * sine,
                local.x * sine + local.y * cosine
            )
        }
    }

    private static func centered(_ anchor: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(anchor.x - 0.5, 0.5 - anchor.y)
    }

    private static func direction(
        for preset: DayObjectChoreographyPreset,
        slot: DayObjectChoreographySlot
    ) -> Double {
        switch preset {
        case .doubleOrbit, .eclipseStack, .crossCurrents:
            return slot.direction
        default:
            return 1
        }
    }

    private static func sector(
        for preset: DayObjectChoreographyPreset,
        slot: DayObjectChoreographySlot
    ) -> Int {
        let sectors: [Int]
        switch preset {
        case .breathingGrid:
            sectors = [0, 1, 2, 3, 4, 6, 7, 8, 5, 4]
        case .waveRibbon:
            sectors = [0, 3, 1, 4, 2, 8, 5, 6, 7, 8]
        case .eclipseStack:
            sectors = [4, 4, 1, 1, 7, 7, 3, 3, 5, 5]
        case .crossCurrents:
            sectors = [0, 2, 3, 5, 6, 8, 1, 7, 4, 4]
        default:
            sectors = [1, 2, 5, 8, 7, 6, 3, 0, 4, 4]
        }
        return sectors[slot.ordinal % sectors.count]
    }

    private static func eventSeed(rootSeed: UInt64, eventID: String) -> UInt64 {
        var hash = rootSeed ^ 0x6A09_E667_F3BC_C909
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        return mixed(hash)
    }

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        Double(mixed(seed ^ salt) >> 11) / Double(UInt64(1) << 53)
    }

    private static func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
