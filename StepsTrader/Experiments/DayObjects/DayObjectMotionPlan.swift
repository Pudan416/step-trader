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
    let family: DayObjectChoreographyFamily
    let routes: [String: DayObjectRoute]
    let depths: [String: DayObjectDepthSchedule]
    let encounters: [String: DayObjectEncounter]

    static func make(rootSeed: UInt64, eventIDs: [String]) -> DayObjectMotionPlan {
        let family = DayObjectChoreographyFamily.allCases[
            Int(mixed(rootSeed ^ 0x243F_6A88_85A3_08D3)
                % UInt64(DayObjectChoreographyFamily.allCases.count))
        ]
        var seen = Set<String>()
        let ids = eventIDs.filter { seen.insert($0).inserted }.prefix(DayObjectScene.maxActors)
        var routes = [String: DayObjectRoute]()
        var depths = [String: DayObjectDepthSchedule]()
        var encounters = [String: DayObjectEncounter]()

        let routeRecords = ids.map { eventID -> (eventID: String, seed: UInt64) in
            (eventID, eventSeed(rootSeed: rootSeed, eventID: eventID))
        }
        var sectorByID = Dictionary(uniqueKeysWithValues: routeRecords.map {
            ($0.eventID, sector(for: $0.eventID, seed: $0.seed, family: family))
        })
        if routeRecords.count >= 8, Set(sectorByID.values).count < 5 {
            var counts = Dictionary(grouping: sectorByID.values, by: { $0 }).mapValues(\.count)
            var missing = (0..<9).filter { counts[$0] == nil }
            let movable = routeRecords.sorted {
                mixed($0.seed ^ 0xD6E8_FEB8_6659_FD93)
                    < mixed($1.seed ^ 0xD6E8_FEB8_6659_FD93)
            }
            for record in movable where Set(sectorByID.values).count < 5 {
                guard let current = sectorByID[record.eventID],
                      counts[current, default: 0] > 1,
                      !missing.isEmpty else { continue }
                let selected = missing.removeFirst()
                counts[current, default: 0] -= 1
                counts[selected, default: 0] += 1
                sectorByID[record.eventID] = selected
            }
        }
        var directionByID = Dictionary(uniqueKeysWithValues: routeRecords.map {
            ($0.eventID, direction(for: $0.eventID, seed: $0.seed))
        })
        if routeRecords.count >= 2, Set(directionByID.values).count == 1,
           let selected = routeRecords.min(by: {
               mixed($0.seed ^ 0xA409_3822_299F_31D0)
                   < mixed($1.seed ^ 0xA409_3822_299F_31D0)
           }) {
            directionByID[selected.eventID] = -(directionByID[selected.eventID] ?? 1)
        }
        for eventID in ids {
            let seed = eventSeed(rootSeed: rootSeed, eventID: eventID)
            let depthOrdinal = numericSuffix(eventID)
                ?? Int(mixed(seed ^ 0x1319_8A2E_0370_7344) % 10)
            // Ten stable encounter slots map to five shared pair channels. The
            // slot is derived only from the event ID, so removing another
            // happening never rerolls an existing orb's meeting geometry.
            let encounterSlot = numericSuffix(eventID).map { $0 % 10 }
                ?? Int(mixed(seed ^ 0xBE54_66CF_34E9_0C6C) % 10)
            let encounterChannel = encounterSlot / 2
            let encounterMemberOrdinal = encounterSlot % 2
            let encounterMemberCount = 2
            let encounterSeed = mixed(
                rootSeed ^ UInt64(encounterChannel) &* 0x9E37_79B9_7F4A_7C15
            )
            routes[eventID] = makeRoute(
                seed: seed,
                family: family,
                direction: directionByID[eventID] ?? 1,
                sector: sectorByID[eventID] ?? 0
            )
            depths[eventID] = DayObjectDepthSchedule(
                baseDepth: 0.5,
                amplitude: 0.38 + 0.08 * stableUnit(seed, salt: 0xA409_3822_299F_31D0),
                period: 60 + 80 * stableUnit(seed, salt: 0x082E_FA98_EC4E_6C89),
                phase: normalizedPhase(
                    (Double(depthOrdinal % 10) + 0.5) / 10
                        + 0.04 * (stableUnit(seed, salt: 0x4528_21E6_38D0_1377) - 0.5)
                )
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
            family: family,
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
        seed: UInt64,
        family: DayObjectChoreographyFamily,
        direction: Double,
        sector: Int
    ) -> DayObjectRoute {
        let pointCount = 4 + Int(mixed(seed ^ 0xD131_0BA6_98DF_B5AC) % 3)
        let baseAngle = 2 * Double.pi * stableUnit(seed, salt: 0x2FFD_72DB_D01A_DFB7)
        var major = 0.15 + 0.15 * stableUnit(seed, salt: 0xB8E1_AFED_6A26_7E96)
        var minor = 0.11 + 0.11 * stableUnit(seed, salt: 0xBA7C_9045_F12C_7F99)
        var rotation = baseAngle

        switch family {
        case .driftField:
            rotation += .pi / 4
        case .crossCurrent:
            major = 0.25 + 0.05 * stableUnit(seed, salt: 0x24A1_9947_B391_6CF7)
            minor = 0.10 + 0.04 * stableUnit(seed, salt: 0x0801_F2E2_858E_FC16)
            rotation = direction > 0 ? 0.12 : -0.12
        case .tidalSweep:
            major = 0.24 + 0.05 * stableUnit(seed, salt: 0x6369_20D8_7157_4E69)
            minor = 0.10 + 0.04 * stableUnit(seed, salt: 0xA458_FEA3_F493_3D7E)
            rotation = mixed(seed ^ 0x0D95_748F_728E_B658).isMultiple(of: 2) ? 0 : .pi / 2
        case .depthMigration:
            major = 0.12 + 0.06 * stableUnit(seed, salt: 0x718B_CD58_8215_4AEE)
            minor = 0.10 + 0.04 * stableUnit(seed, salt: 0x7B54_A41D_C25A_59B5)
        case .softEncounters:
            major = 0.20 + 0.09 * stableUnit(seed, salt: 0x9C30_D539_2AF2_6013)
            minor = 0.12 + 0.07 * stableUnit(seed, salt: 0xC5D1_B023_2860_85F0)
        }

        let cosRotation = cos(rotation)
        let sinRotation = sin(rotation)
        let rawPoints = (0..<pointCount).map { index -> SIMD2<Double> in
            let angle = baseAngle + 2 * Double.pi * Double(index) / Double(pointCount)
            let modulation = 0.88 + 0.24 * stableUnit(
                seed,
                salt: UInt64(index) &* 0x9E37_79B9_7F4A_7C15
            )
            let local = SIMD2(major * modulation * cos(angle), minor * modulation * sin(angle))
            return SIMD2(
                local.x * cosRotation - local.y * sinRotation,
                local.x * sinRotation + local.y * cosRotation
            )
        }
        let xs = rawPoints.map(\.x)
        let ys = rawPoints.map(\.y)
        let xExtent = (xs.max() ?? 0) - (xs.min() ?? 0)
        let yExtent = (ys.max() ?? 0) - (ys.min() ?? 0)
        let extent = max(xExtent, yExtent)
        let extentScale = extent > 0 ? min(max(0.205 / extent, 1), 0.68 / extent) : 1
        let points = rawPoints.map { $0 * extentScale }
        return DayObjectRoute(
            controlPoints: points,
            period: 45 + 75 * stableUnit(seed, salt: 0xF6BB_4B60_9FBC_CEAE),
            phase: stableUnit(seed, salt: 0x2D7E_9E3B_0912_1F40),
            direction: direction,
            sector: sector
        )
    }

    private static func direction(for eventID: String, seed: UInt64) -> Double {
        if let suffix = numericSuffix(eventID) {
            return suffix.isMultiple(of: 2) ? 1 : -1
        }
        return mixed(seed ^ 0xD1B5_4A32_D192_ED03).isMultiple(of: 2) ? 1 : -1
    }

    private static func sector(
        for eventID: String,
        seed: UInt64,
        family: DayObjectChoreographyFamily
    ) -> Int {
        if let suffix = numericSuffix(eventID) {
            if family == .softEncounters {
                let encounterSectors = [1, 1, 0, 2, 3, 4, 5, 0, 2, 3]
                return encounterSectors[suffix % encounterSectors.count]
            }
            return (suffix * 5 + 1) % 9
        }
        return Int(mixed(seed ^ 0x94D0_49BB_1331_11EB) % 9)
    }

    private static func numericSuffix(_ eventID: String) -> Int? {
        guard let suffix = eventID.split(separator: "-").last else { return nil }
        return Int(suffix)
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
