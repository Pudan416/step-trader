import Foundation
import simd

struct DayObjectRoute: Equatable {
    let controlPoints: [SIMD2<Double>]
    let period: Double
    let phase: Double
    let direction: Double

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

struct DayObjectMotionPlan: Equatable {
    let configuration: DayObjectChoreographyConfiguration
    let routes: [String: DayObjectRoute]
    let depths: [String: DayObjectDepthSchedule]

    var preset: DayObjectChoreographyPreset { configuration.preset }

    static func make(
        configuration: DayObjectChoreographyConfiguration,
        rootSeed: UInt64,
        eventIDs: [String]
    ) -> DayObjectMotionPlan {
        var seen = Set<String>()
        let ids = eventIDs.filter { seen.insert($0).inserted }.prefix(DayObjectScene.maxActors)
        var routes = [String: DayObjectRoute]()
        var depths = [String: DayObjectDepthSchedule]()

        for eventID in ids {
            let seed = eventSeed(rootSeed: rootSeed, eventID: eventID)
            let slot = configuration.slot(eventID: eventID, rootSeed: rootSeed)
            let route = makeRoute(configuration: configuration, slot: slot, seed: seed)
            routes[eventID] = route
            depths[eventID] = makeDepthSchedule(
                configuration: configuration,
                slot: slot,
                seed: seed,
                routePeriod: route.period
            )
        }

        return DayObjectMotionPlan(
            configuration: configuration,
            routes: routes,
            depths: depths
        )
    }

    private static func makeRoute(
        configuration: DayObjectChoreographyConfiguration,
        slot: DayObjectChoreographySlot,
        seed: UInt64
    ) -> DayObjectRoute {
        let center = canvasPoint(configuration.center)
        let anchor = canvasPoint(slot.anchor)
        let count = 32
        let points: [SIMD2<Double>]
        let phase: Double
        let period: Double

        switch configuration.topology {
        case .circularChoir:
            let radial = anchor - center
            points = sampled(count: count) { progress in
                center + rotated(radial, by: 2 * .pi * progress)
            }
            phase = 0
            period = configuration.loopDuration
        case .doubleOrbit:
            let radial = anchor - center
            points = sampled(count: count) { progress in
                center + rotated(radial, by: 2 * .pi * progress)
            }
            phase = 0
            period = min(max(configuration.loopDuration / slot.speedRatio, 90), 220)
        case .radialBloom:
            let radial = anchor - center
            points = sampled(count: count) { progress in
                let opening = 1 + 0.16 * sin(2 * .pi * progress)
                return center + rotated(radial * opening, by: 2 * .pi * progress)
            }
            phase = 0
            period = configuration.loopDuration
        case .breathingGrid:
            points = sampled(count: count) { progress in
                let angle = 2 * Double.pi * (progress + slot.phase)
                return anchor + SIMD2(0.010 * sin(angle), 0.007 * sin(2 * angle))
            }
            phase = 0
            period = configuration.loopDuration
        case .waveRibbon:
            let tangent = SIMD2(
                cos(configuration.orientation), sin(configuration.orientation)
            )
            let normal = SIMD2(-tangent.y, tangent.x)
            points = sampled(count: count) { progress in
                let wave = 2 * Double.pi * (progress - slot.phase)
                return anchor + normal * (0.045 * sin(wave))
                    + tangent * (0.007 * cos(wave))
            }
            phase = 0
            period = configuration.loopDuration
        case .spiralProcession:
            let radial = anchor - center
            points = sampled(count: count) { progress in
                let opening = 1 + 0.10 * sin(2 * .pi * progress)
                return center + rotated(radial * opening, by: 2 * .pi * progress)
            }
            phase = 0
            period = configuration.loopDuration
        case .eclipseStack:
            let members = configuration.slots
                .filter { $0.group == slot.group }
                .sorted { $0.ordinal < $1.ordinal }
            let groupCenter = members.map { canvasPoint($0.anchor) }
                .reduce(.zero, +) / Double(max(members.count, 1))
            let memberIndex = members.firstIndex { $0.ordinal == slot.ordinal } ?? 0
            let pairIndex = memberIndex / 2
            let tangent = SIMD2(
                cos(configuration.orientation), sin(configuration.orientation)
            )
            let normal = SIMD2(-tangent.y, tangent.x)
            let lane = simd_dot(anchor - groupCenter, normal)
            let amplitude = 0.21 + 0.012 * Double(pairIndex)
            points = sampled(count: count) { progress in
                let angle = 2 * Double.pi * (progress + slot.phase)
                return groupCenter + normal * lane + tangent * (amplitude * sin(angle))
                    + normal * (0.012 * sin(2 * angle))
            }
            phase = 0
            period = configuration.loopDuration
        case .crossCurrents(let crossingAngle, _):
            let axis = slot.group == 0
                ? configuration.orientation
                : configuration.orientation + crossingAngle
            let tangent = SIMD2(cos(axis), sin(axis))
            let normal = SIMD2(-tangent.y, tangent.x)
            points = sampled(count: count) { progress in
                let angle = 2 * Double.pi * progress
                return center + tangent * (0.24 * cos(angle))
                    + normal * (0.035 * sin(angle))
            }
            phase = slot.phase
            period = min(max(configuration.loopDuration / slot.speedRatio, 90), 220)
        case .constellation:
            let members = configuration.slots.filter { $0.group == slot.group }
            let groupCenter = members.map { canvasPoint($0.anchor) }
                .reduce(.zero, +) / Double(max(members.count, 1))
            let memberOffset = anchor - groupCenter
            let groupPhase = Double(slot.group) * 0.19
            points = sampled(count: count) { progress in
                let angle = 2 * Double.pi * (progress + groupPhase)
                let drift = SIMD2(0.025 * cos(angle), 0.020 * sin(angle))
                let localRotation = 0.16 * sin(angle)
                return groupCenter + drift + rotated(memberOffset, by: localRotation)
            }
            phase = 0
            period = configuration.loopDuration * (0.96 + 0.025 * Double(slot.group))
        case .depthField:
            let xAmplitude = 0.10 + 0.06 * stableUnit(seed, salt: 0xC0AC_29B7_C97C_50DD)
            let yAmplitude = 0.08 + 0.06 * stableUnit(seed, salt: 0x3F84_D5B5_B547_0917)
            let phaseOffset = 2 * Double.pi * slot.phase
            points = sampled(count: count) { progress in
                let angle = 2 * Double.pi * progress + phaseOffset
                return anchor + SIMD2(
                    xAmplitude * sin(angle),
                    yAmplitude * sin(2 * angle + 0.7)
                )
            }
            phase = 0
            period = 110 + 105 * stableUnit(seed, salt: 0xF6BB_4B60_9FBC_CEAE)
        }

        return DayObjectRoute(
            controlPoints: points,
            period: period,
            phase: phase,
            direction: slot.direction
        )
    }

    private static func makeDepthSchedule(
        configuration: DayObjectChoreographyConfiguration,
        slot: DayObjectChoreographySlot,
        seed: UInt64,
        routePeriod: Double
    ) -> DayObjectDepthSchedule {
        let baseDepth: Double
        let amplitude: Double
        let period: Double
        let phase: Double

        switch configuration.preset {
        case .circularChoir, .doubleOrbit, .radialBloom,
             .breathingGrid, .waveRibbon, .spiralProcession:
            baseDepth = 0.55
            amplitude = 0.008 + 0.016 * stableUnit(seed, salt: 0xA409_3822_299F_31D0)
            period = routePeriod
            phase = slot.phase
        case .eclipseStack:
            baseDepth = 0.55
            amplitude = 0.20
            period = configuration.loopDuration
            phase = slot.phase
        case .crossCurrents:
            baseDepth = slot.baseDepth
            amplitude = 0.10
            period = routePeriod
            phase = slot.group == 0 ? 0 : 0.5
        case .constellation:
            baseDepth = slot.baseDepth
            amplitude = 0.10
            period = routePeriod
            phase = slot.phase
        case .depthField:
            baseDepth = 0.50
            amplitude = 0.42 + 0.05 * stableUnit(seed, salt: 0xA409_3822_299F_31D0)
            period = 105 + 110 * stableUnit(seed, salt: 0x082E_FA98_EC4E_6C89)
            phase = slot.phase
        }
        return DayObjectDepthSchedule(
            baseDepth: baseDepth,
            amplitude: amplitude,
            period: period,
            phase: normalizedPhase(phase)
        )
    }

    private static func sampled(
        count: Int,
        _ position: (Double) -> SIMD2<Double>
    ) -> [SIMD2<Double>] {
        (0..<count).map { position(Double($0) / Double(count)) }
    }

    private static func canvasPoint(_ normalized: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(normalized.x - 0.5, 0.5 - normalized.y)
    }

    private static func rotated(
        _ point: SIMD2<Double>,
        by angle: Double
    ) -> SIMD2<Double> {
        let cosine = cos(angle)
        let sine = sin(angle)
        return SIMD2(
            point.x * cosine - point.y * sine,
            point.x * sine + point.y * cosine
        )
    }

    private static func normalizedPhase(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
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
