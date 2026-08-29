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

enum DayObjectSizeRole: Equatable {
    case uniform
    case compact
    case medium
    case large
    case distant
    case middle
    case foreground
}

enum DayObjectDepthRole: Equatable {
    case focus
    case back
    case middle
    case front
    case migrating
}

enum DayObjectGridTopology: UInt32, CaseIterable, Equatable {
    case twoByFive
    case threeByThree
    case staggered
}

enum DayObjectRibbonAxis: UInt32, CaseIterable, Equatable {
    case horizontal
    case vertical
    case risingDiagonal
    case fallingDiagonal

    var angle: Double {
        switch self {
        case .horizontal: 0
        case .vertical: .pi / 2
        case .risingDiagonal: .pi / 4
        case .fallingDiagonal: -.pi / 4
        }
    }
}

enum DayObjectChoreographyTopology: Equatable {
    case circularChoir(radius: SIMD2<Double>)
    case doubleOrbit(innerRadius: Double, outerRadius: Double, speedRatio: Double)
    case radialBloom(radius: Double)
    case breathingGrid(DayObjectGridTopology)
    case waveRibbon(axis: DayObjectRibbonAxis, ribbonCount: Int)
    case spiralProcession(growth: Double)
    case eclipseStack(clusterCount: Int)
    case crossCurrents(crossingAngle: Double, speedRatio: Double)
    case constellation(clusterCount: Int)
    case depthField
}

struct DayObjectChoreographySlot: Equatable {
    let ordinal: Int
    /// Ring, ribbon, stream, row, or cluster membership owned by the preset.
    let group: Int
    /// The preset's real normalized canvas anchor, not a generic placement sector.
    let anchor: SIMD2<Double>
    /// The canonical geometry phase owned by the preset topology.
    let phase: Double
    /// A stable arbitrary-event offset that advances only this actor along its route.
    let identityPhase: Double
    let direction: Double
    let speedRatio: Double
    let sizeRole: DayObjectSizeRole
    let depthRole: DayObjectDepthRole
    let sizeMultiplier: Double
    let baseDepth: Double
}

struct DayObjectChoreographyConfiguration: Equatable {
    let preset: DayObjectChoreographyPreset
    let sizeProfile: DayObjectSizeProfile
    let depthProfile: DayObjectDepthProfile
    let topology: DayObjectChoreographyTopology
    let center: SIMD2<Double>
    let orientation: Double
    let eccentricity: Double
    let loopDuration: Double
    let baseDiameter: Double
    let slots: [DayObjectChoreographySlot]

    static func make(seed: UInt64) -> Self {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectChoreographyPreset")
        let preset = DayObjectChoreographyPreset.allCases[
            rng.nextInt(in: 0...(DayObjectChoreographyPreset.allCases.count - 1))
        ]
        let profile = profiles[preset]!
        let loopDuration = rng.nextDouble(in: 150...210)
        let eccentricity = rng.nextDouble(in: 0.92...1.08)

        let center: SIMD2<Double>
        switch preset {
        case .radialBloom:
            center = SIMD2(
                rng.nextDouble(in: 0.38...0.62),
                rng.nextDouble(in: 0.38...0.62)
            )
        case .constellation, .depthField:
            center = SIMD2(repeating: 0.5)
        default:
            center = SIMD2(
                rng.nextDouble(in: 0.46...0.54),
                rng.nextDouble(in: 0.46...0.54)
            )
        }

        let topology: DayObjectChoreographyTopology
        let orientation: Double
        let baseDiameter: Double
        switch preset {
        case .circularChoir:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .circularChoir(radius: SIMD2(0.255 * eccentricity, 0.255))
            baseDiameter = rng.nextDouble(in: 0.235...0.275)
        case .doubleOrbit:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .doubleOrbit(
                innerRadius: rng.nextDouble(in: 0.165...0.180),
                outerRadius: rng.nextDouble(in: 0.255...0.275),
                speedRatio: rng.nextDouble(in: 0.82...1.22)
            )
            baseDiameter = rng.nextDouble(in: 0.245...0.285)
        case .radialBloom:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .radialBloom(radius: rng.nextDouble(in: 0.235...0.275))
            baseDiameter = rng.nextDouble(in: 0.235...0.275)
        case .breathingGrid:
            orientation = rng.nextDouble(in: -0.16...0.16)
            topology = .breathingGrid(
                DayObjectGridTopology.allCases[
                    rng.nextInt(in: 0...(DayObjectGridTopology.allCases.count - 1))
                ]
            )
            baseDiameter = rng.nextDouble(in: 0.225...0.255)
        case .waveRibbon:
            let axis = DayObjectRibbonAxis.allCases[
                rng.nextInt(in: 0...(DayObjectRibbonAxis.allCases.count - 1))
            ]
            orientation = axis.angle + rng.nextDouble(in: -0.08...0.08)
            topology = .waveRibbon(
                axis: axis,
                ribbonCount: rng.nextInt(in: 1...2)
            )
            baseDiameter = rng.nextDouble(in: 0.225...0.255)
        case .spiralProcession:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .spiralProcession(growth: rng.nextDouble(in: 0.13...0.16))
            baseDiameter = rng.nextDouble(in: 0.235...0.260)
        case .eclipseStack:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .eclipseStack(clusterCount: rng.nextInt(in: 1...2))
            baseDiameter = rng.nextDouble(in: 0.255...0.295)
        case .crossCurrents:
            orientation = rng.nextDouble(in: 0.32...0.72)
            topology = .crossCurrents(
                crossingAngle: rng.nextDouble(in: 0.86...1.30),
                speedRatio: rng.nextDouble(in: 0.82...1.22)
            )
            baseDiameter = rng.nextDouble(in: 0.235...0.275)
        case .constellation:
            orientation = rng.nextDouble(in: -0.12...0.12)
            topology = .constellation(clusterCount: rng.nextInt(in: 3...4))
            baseDiameter = rng.nextDouble(in: 0.235...0.250)
        case .depthField:
            orientation = rng.nextDouble(in: 0...(2 * .pi))
            topology = .depthField
            baseDiameter = rng.nextDouble(in: 0.42...0.48)
        }

        let slots = makeSlots(
            preset: preset,
            topology: topology,
            center: center,
            orientation: orientation,
            eccentricity: eccentricity
        )
        return Self(
            preset: preset,
            sizeProfile: profile.0,
            depthProfile: profile.1,
            topology: topology,
            center: center,
            orientation: orientation,
            eccentricity: eccentricity,
            loopDuration: loopDuration,
            baseDiameter: baseDiameter,
            slots: slots
        )
    }

    func slot(eventID: String, rootSeed: UInt64) -> DayObjectChoreographySlot {
        let event = stableEventHash(eventID, rootSeed: rootSeed)
        let admissionOrdinal = event.numericOrdinal ?? Int(event.hash % 10)
        let slot = slots[Self.admissionToGeometryOrdinals(for: topology)[admissionOrdinal % 10]]
        let identityPhase = event.numericOrdinal.map { _ in 0 }
            ?? Self.identityPhase(forStableHash: event.hash)
        return DayObjectChoreographySlot(
            ordinal: slot.ordinal,
            group: slot.group,
            anchor: slot.anchor,
            phase: slot.phase,
            identityPhase: identityPhase,
            direction: slot.direction,
            speedRatio: slot.speedRatio,
            sizeRole: slot.sizeRole,
            depthRole: slot.depthRole,
            sizeMultiplier: slot.sizeMultiplier,
            baseDepth: slot.baseDepth
        )
    }

    func materialWeight(for family: DayObjectMaterialFamily) -> Int {
        let preferred: Set<DayObjectChoreographyPreset>
        switch family {
        case .outline:
            preferred = [.circularChoir, .doubleOrbit, .waveRibbon]
        case .glass:
            preferred = [.eclipseStack, .constellation, .depthField]
        case .luminous, .halo:
            preferred = [.radialBloom, .spiralProcession, .depthField]
        case .solid, .sphere:
            preferred = [.breathingGrid, .crossCurrents, .circularChoir]
        case .mist:
            preferred = [.constellation, .eclipseStack, .depthField]
        case .gradient, .counterform:
            preferred = Set(DayObjectChoreographyPreset.allCases)
        }
        return preferred.contains(preset) ? 3 : 1
    }

    private static let profiles: [DayObjectChoreographyPreset: (DayObjectSizeProfile, DayObjectDepthProfile)] = [
        .circularChoir: (.uniform, .flat), .doubleOrbit: (.grouped, .flat),
        .radialBloom: (.uniform, .flat), .breathingGrid: (.uniform, .flat),
        .waveRibbon: (.uniform, .flat), .spiralProcession: (.grouped, .flat),
        .eclipseStack: (.grouped, .layered), .crossCurrents: (.grouped, .layered),
        .constellation: (.grouped, .layered), .depthField: (.spatial, .migrating),
    ]

    private static let balancedAngles = [0, 5, 2, 7, 1, 6, 4, 9, 3, 8]

    private static func admissionToGeometryOrdinals(
        for topology: DayObjectChoreographyTopology
    ) -> [Int] {
        switch topology {
        case .doubleOrbit:
            [0, 3, 4, 7, 8, 1, 6, 9, 2, 5]
        case .waveRibbon(_, let ribbonCount) where ribbonCount == 1:
            [4, 0, 9, 5, 3, 6, 2, 7, 1, 8]
        case .waveRibbon:
            [4, 1, 8, 5, 0, 9, 2, 7, 6, 3]
        case .spiralProcession:
            [0, 5, 9, 3, 7, 1, 6, 4, 8, 2]
        default:
            Array(0..<10)
        }
    }

    private static func makeSlots(
        preset _: DayObjectChoreographyPreset,
        topology: DayObjectChoreographyTopology,
        center: SIMD2<Double>,
        orientation: Double,
        eccentricity: Double
    ) -> [DayObjectChoreographySlot] {
        let centerPoint = canvasPoint(center)
        func normalizedAnchor(_ local: SIMD2<Double>, rotation: Double = orientation) -> SIMD2<Double> {
            normalizedPoint(centerPoint + rotated(local, by: rotation))
        }
        func slot(
            _ ordinal: Int,
            group: Int,
            local: SIMD2<Double>,
            phase: Double,
            direction: Double = 1,
            speedRatio: Double = 1,
            sizeRole: DayObjectSizeRole,
            depthRole: DayObjectDepthRole,
            sizeMultiplier: Double,
            baseDepth: Double,
            rotation: Double = orientation
        ) -> DayObjectChoreographySlot {
            DayObjectChoreographySlot(
                ordinal: ordinal,
                group: group,
                anchor: normalizedAnchor(local, rotation: rotation),
                phase: normalizedPhase(phase),
                identityPhase: 0,
                direction: direction,
                speedRatio: speedRatio,
                sizeRole: sizeRole,
                depthRole: depthRole,
                sizeMultiplier: sizeMultiplier,
                baseDepth: baseDepth
            )
        }

        switch topology {
        case .circularChoir(let radius):
            return balancedAngles.enumerated().map { ordinal, angleIndex in
                let angle = 2 * Double.pi * Double(angleIndex) / 10
                return slot(
                    ordinal, group: 0,
                    local: SIMD2(radius.x * cos(angle), radius.y * sin(angle)),
                    phase: Double(angleIndex) / 10,
                    sizeRole: .uniform, depthRole: .focus,
                    sizeMultiplier: 0.99 + 0.02 * Double(ordinal) / 9,
                    baseDepth: 0.55
                )
            }
        case .doubleOrbit(let innerRadius, let outerRadius, let speedRatio):
            let ringOrder = [0, 2, 4, 1, 3]
            return (0..<10).map { ordinal in
                let group = ordinal % 2
                let member = ordinal / 2
                let angleIndex = ringOrder[member]
                let angle = 2 * Double.pi * Double(angleIndex) / 5
                let radius = group == 0 ? innerRadius : outerRadius
                let ratio = group == 0 ? 1 : speedRatio
                return slot(
                    ordinal, group: group,
                    local: SIMD2(radius * eccentricity * cos(angle), radius * sin(angle)),
                    phase: Double(angleIndex) / 5,
                    direction: group == 0 ? 1 : -1,
                    speedRatio: ratio,
                    sizeRole: group == 0 ? .medium : .large,
                    depthRole: .focus,
                    sizeMultiplier: group == 0 ? 0.96 : 1.04,
                    baseDepth: 0.55
                )
            }
        case .radialBloom(let radius):
            return balancedAngles.enumerated().map { ordinal, angleIndex in
                let angle = 2 * Double.pi * Double(angleIndex) / 10
                return slot(
                    ordinal, group: 0,
                    local: SIMD2(radius * cos(angle), radius * sin(angle)),
                    phase: Double(angleIndex) / 10,
                    sizeRole: .uniform, depthRole: .focus,
                    sizeMultiplier: 1, baseDepth: 0.55
                )
            }
        case .breathingGrid(let grid):
            let points: [SIMD2<Double>]
            switch grid {
            case .twoByFive:
                let source = [-0.26, -0.13, 0, 0.13, 0.26].flatMap { x in
                    [SIMD2(x, -0.18), SIMD2(x, 0.18)]
                }
                points = [source[4], source[5], source[0], source[9], source[1],
                          source[8], source[2], source[7], source[3], source[6]]
            case .threeByThree:
                points = [
                    SIMD2(0, 0), SIMD2(-0.24, -0.20), SIMD2(0.24, 0.20),
                    SIMD2(0.24, -0.20), SIMD2(-0.24, 0.20), SIMD2(-0.24, 0),
                    SIMD2(0.24, 0), SIMD2(0, -0.20), SIMD2(0, 0.20),
                    SIMD2(0.035, 0.025),
                ]
            case .staggered:
                points = [
                    SIMD2(-0.12, 0), SIMD2(0.12, 0), SIMD2(-0.24, -0.19),
                    SIMD2(0.24, 0.19), SIMD2(0.24, -0.19), SIMD2(-0.24, 0.19),
                    SIMD2(0, -0.19), SIMD2(0, 0.19), SIMD2(-0.27, 0), SIMD2(0.27, 0),
                ]
            }
            return points.enumerated().map { ordinal, point in
                let group = levelIndex(point.y, values: points.map(\.y))
                return slot(
                    ordinal, group: group, local: point,
                    phase: Double(ordinal) / 10,
                    sizeRole: .uniform, depthRole: .focus,
                    sizeMultiplier: 1, baseDepth: 0.55
                )
            }
        case .waveRibbon(_, let ribbonCount):
            let positions = [-0.25, -0.125, 0, 0.125, 0.25]
            return (0..<10).map { ordinal in
                let group = ribbonCount == 1 ? 0 : ordinal % 2
                let memberCount = ribbonCount == 1 ? 10 : 5
                let member = ribbonCount == 1 ? ordinal : ordinal / 2
                let longitudinal = ribbonCount == 1
                    ? -0.25 + 0.50 * Double(member) / 9
                    : positions[member]
                let lateral = ribbonCount == 1 ? 0 : (group == 0 ? -0.08 : 0.08)
                return slot(
                    ordinal, group: group,
                    local: SIMD2(longitudinal, lateral),
                    phase: Double(member) / Double(max(memberCount - 1, 1)),
                    sizeRole: .uniform, depthRole: .focus,
                    sizeMultiplier: 1, baseDepth: 0.55
                )
            }
        case .spiralProcession(let growth):
            return (0..<10).map { ordinal in
                let radius = 0.060 * exp(growth * Double(ordinal))
                let angle = 0.72 * Double(ordinal)
                return slot(
                    ordinal, group: 0,
                    local: SIMD2(radius * cos(angle), radius * sin(angle)),
                    phase: 0,
                    sizeRole: ordinal < 4 ? .compact : .medium,
                    depthRole: .focus,
                    sizeMultiplier: 0.76 + 0.36 * Double(ordinal) / 9,
                    baseDepth: 0.55
                )
            }
        case .eclipseStack(let clusterCount):
            return (0..<10).map { ordinal in
                let group = clusterCount == 1 ? 0 : ordinal % 2
                let member = clusterCount == 1 ? ordinal : ordinal / 2
                let clusterOffset = clusterCount == 1
                    ? SIMD2<Double>.zero
                    : SIMD2(group == 0 ? -0.16 : 0.16, group == 0 ? 0.06 : -0.06)
                let pair = member / 2
                let lane = 0.035 * Double(pair - 1)
                let sizeGroup = pair % 3
                let sizeMultiplier = [0.96, 1.0, 1.04][sizeGroup]
                return slot(
                    ordinal, group: group,
                    local: clusterOffset + SIMD2(0, lane),
                    phase: member.isMultiple(of: 2) ? 0 : 0.5,
                    sizeRole: sizeGroup == 0 ? .medium : .large,
                    depthRole: member.isMultiple(of: 2) ? .front : .middle,
                    sizeMultiplier: sizeMultiplier,
                    baseDepth: 0.55
                )
            }
        case .crossCurrents(let crossingAngle, let speedRatio):
            let positions = [-0.36, -0.18, 0, 0.18, 0.36]
            return (0..<10).map { ordinal in
                let group = ordinal % 2
                let member = ordinal / 2
                let axis = group == 0 ? orientation : orientation + crossingAngle
                let local = rotated(SIMD2(positions[member], 0), by: axis)
                return slot(
                    ordinal, group: group, local: local,
                    phase: Double(member) / 5,
                    direction: group == 0 ? 1 : -1,
                    speedRatio: group == 0 ? 1 : speedRatio,
                    sizeRole: group == 0 ? .medium : .large,
                    depthRole: group == 0 ? .middle : .front,
                    sizeMultiplier: group == 0 ? 0.96 : 1.04,
                    baseDepth: group == 0 ? 0.48 : 0.62,
                    rotation: 0
                )
            }
        case .constellation(let clusterCount):
            let clusterCenters: [SIMD2<Double>] = clusterCount == 3
                ? [SIMD2(-0.15, 0.24), SIMD2(0.15, 0), SIMD2(-0.03, -0.24)]
                : [SIMD2(-0.16, 0.24), SIMD2(0.16, 0.08),
                   SIMD2(-0.15, -0.24), SIMD2(0.16, -0.15)]
            return (0..<10).map { ordinal in
                let group = ordinal % clusterCount
                let member = ordinal / clusterCount
                let memberAngle = Double(member) * 2.2 + Double(group) * 0.37
                let memberRadius = member == 0 ? 0 : 0.030 + 0.005 * Double(member)
                let local = clusterCenters[group] + SIMD2(
                    memberRadius * cos(memberAngle),
                    memberRadius * sin(memberAngle)
                )
                let sizeMultiplier = [0.72, 0.86, 1.0][member % 3]
                let baseDepth = [0.36, 0.55, 0.72][group % 3]
                return slot(
                    ordinal, group: group, local: local,
                    phase: Double(group) / Double(clusterCount),
                    sizeRole: member == 0 ? .medium : .compact,
                    depthRole: group % 3 == 0 ? .back : group % 3 == 1 ? .middle : .front,
                    sizeMultiplier: sizeMultiplier,
                    baseDepth: baseDepth,
                    rotation: 0
                )
            }
        case .depthField:
            let points: [SIMD2<Double>] = [
                SIMD2(0, 0.34), SIMD2(0, -0.34), SIMD2(-0.35, 0), SIMD2(0.35, 0),
                SIMD2(-0.28, 0.27), SIMD2(0.28, -0.27), SIMD2(0.28, 0.27),
                SIMD2(-0.28, -0.27), SIMD2(-0.12, 0.08), SIMD2(0.14, -0.10),
            ]
            let multipliers = [0.34, 1.22, 0.66, 1.08, 0.46, 1.30, 0.56, 0.92, 0.74, 1.15]
            let depths = [0.18, 0.88, 0.52, 0.30, 0.74, 0.12, 0.64, 0.42, 0.82, 0.56]
            return points.enumerated().map { ordinal, point in
                let depth = depths[ordinal]
                let sizeRole: DayObjectSizeRole = depth > 0.72
                    ? .foreground : depth < 0.32 ? .distant : .middle
                return slot(
                    ordinal, group: ordinal, local: point,
                    phase: Double((ordinal * 3) % 10) / 10,
                    direction: ordinal.isMultiple(of: 3) ? -1 : 1,
                    speedRatio: 0.82 + 0.04 * Double(ordinal),
                    sizeRole: sizeRole, depthRole: .migrating,
                    sizeMultiplier: multipliers[ordinal], baseDepth: depth,
                    rotation: 0
                )
            }
        }
    }

    private static func levelIndex(_ value: Double, values: [Double]) -> Int {
        let levels = values.sorted().reduce(into: [Double]()) { result, candidate in
            if result.last.map({ abs($0 - candidate) > 0.001 }) ?? true {
                result.append(candidate)
            }
        }
        return levels.firstIndex { abs($0 - value) <= 0.001 } ?? 0
    }

    private static func canvasPoint(_ normalized: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(normalized.x - 0.5, 0.5 - normalized.y)
    }

    private static func normalizedPoint(_ canvas: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(
            min(max(canvas.x + 0.5, 0.04), 0.96),
            min(max(0.5 - canvas.y, 0.04), 0.96)
        )
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

    func stableEventHash(
        _ eventID: String,
        rootSeed: UInt64
    ) -> (hash: UInt64, numericOrdinal: Int?) {
        var hash = rootSeed ^ 0xCBF2_9CE4_8422_2325
        for byte in eventID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01B3
        }
        return (hash, Self.canonicalEventOrdinal(eventID))
    }

    static func identityPhase(forStableHash hash: UInt64) -> Double {
        let mixedHash = mixedStableHash(hash)
        return Double(mixedHash >> 11) / Double(UInt64(1) << 53) * 0.08
    }

    private static func canonicalEventOrdinal(_ eventID: String) -> Int? {
        for prefix in ["event-", "lab-event-"] where eventID.hasPrefix(prefix) {
            let suffix = eventID.dropFirst(prefix.count)
            guard !suffix.isEmpty,
                  suffix.utf8.allSatisfy({ (48...57).contains($0) }),
                  let ordinal = Int(suffix) else { return nil }
            return ordinal
        }
        return nil
    }

    private static func mixedStableHash(_ hash: UInt64) -> UInt64 {
        var value = hash &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func normalizedPhase(_ phase: Double) -> Double {
        let remainder = phase.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}
