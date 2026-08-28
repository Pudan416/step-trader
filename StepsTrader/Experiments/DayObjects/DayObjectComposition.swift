import Foundation
import simd

/// Shape family used by the Day Objects renderer.
enum DayObjectShape: String, CaseIterable, Hashable {
    case sphere
    case ellipse
    case lens
    case softBlob

    var numericValue: UInt32 {
        switch self {
        case .sphere: 0
        case .ellipse: 1
        case .lens: 2
        case .softBlob: 3
        }
    }
}

enum DayObjectElongation: String, CaseIterable, Hashable {
    case round
    case oval

    var aspectRange: ClosedRange<Double> {
        switch self {
        case .round: 0.92...1.0
        case .oval: 0.72...0.90
        }
    }
}

enum DayObjectSizeBand: String, CaseIterable, Hashable {
    case focal
    case support
    case satellite

    var diameterRange: ClosedRange<Double> {
        switch self {
        case .focal: 0.28...0.42
        case .support: 0.15...0.26
        case .satellite: 0.065...0.13
        }
    }
}

enum DayObjectSizeComposition: UInt32, CaseIterable, Equatable {
    case constellation
    case nearField
    case balanced
    case foregroundCluster

    func band(for ordinal: Int) -> DayObjectSizeBand {
        let slot = ((ordinal % 10) + 10) % 10
        switch self {
        case .constellation:
            return [1, 3, 5, 7, 9].contains(slot) ? .support : .satellite
        case .nearField:
            if slot == 2 { return .focal }
            return [0, 4, 7].contains(slot) ? .support : .satellite
        case .balanced:
            if [0, 5].contains(slot) { return .focal }
            return [1, 3, 6, 8].contains(slot) ? .support : .satellite
        case .foregroundCluster:
            if [0, 4, 7].contains(slot) { return .focal }
            return [2, 6, 9].contains(slot) ? .support : .satellite
        }
    }
}

enum DayObjectCompositionArchetype: UInt32, CaseIterable, Equatable {
    case distributedField
    case diagonalCurrent
    case edgeMigration
    case focalPair
    case depthConstellation
    case crossingCurrents
}

enum DayObjectFill: String, CaseIterable, Hashable {
    case radialOne
    case radialTwo
    case radialThree

    var colorCount: Int {
        switch self {
        case .radialOne: 1
        case .radialTwo: 2
        case .radialThree: 3
        }
    }
}

enum DayObjectTrajectory: String, CaseIterable, Hashable {
    case orbit
    case lissajous
    case sweep
    case spiral
}

enum DayObjectSpin: String, CaseIterable, Hashable {
    case follow
    case slowRoll
    case tumble
}

/// Daily, viewport-normalized placement constraints. The costly choice of
/// focal/support regions is made once with the scene, not per pixel or frame.
struct DayObjectCompositionPlan: Equatable {
    private static let distributedPlacementCache = DayObjectRoutePlacementCache()
    let uiExclusionRegion: DayObjectNormalizedRect
    let negativeSpaceRegion: DayObjectNormalizedRect
    let targetNegativeSpaceFraction: Double
    let archetype: DayObjectCompositionArchetype
    let usesFullCanvas: Bool

    private let focalAnchor: SIMD2<Double>
    private let supportAnchor: SIMD2<Double>
    private let bridgeAnchor: SIMD2<Double>
    private let satelliteAnchor: SIMD2<Double>
    private let accentAnchor: SIMD2<Double>
    private let routeAnchorCandidates: [SIMD2<Double>]

    static func make(
        seed: UInt64,
        uiExclusionRegion: DayObjectNormalizedRect,
        canvasCoverage: DayObjectCanvasCoverage = .excluding(.dayObjectsLabControls)
    ) -> DayObjectCompositionPlan {
        let usesFullCanvas = canvasCoverage == .fullCanvas
        let target = usesFullCanvas
            ? 0
            : 0.35 + 0.20 * stableUnit(seed, salt: 0x6A09_E667_F3BC_C909)
        let negativeSpace: DayObjectNormalizedRect
        if usesFullCanvas {
            negativeSpace = .empty
        } else if (0.35...0.55).contains(uiExclusionRegion.area) {
            negativeSpace = uiExclusionRegion
        } else if mixed(seed ^ 0xBB67_AE85_84CA_A73B).isMultiple(of: 2) {
            negativeSpace = DayObjectNormalizedRect(
                minX: 0,
                minY: 0,
                maxX: 1,
                maxY: target
            )
        } else {
            negativeSpace = DayObjectNormalizedRect(
                minX: 0,
                minY: 1 - target,
                maxX: 1,
                maxY: 1
            )
        }

        let anchorCoordinates = [0.16, 0.30, 0.44, 0.56, 0.70, 0.84]
        let candidates = anchorCoordinates.flatMap { y in
            anchorCoordinates.map { x in
                SIMD2<Double>(x, y)
            }
        }.filter {
            !negativeSpace.contains($0) && !uiExclusionRegion.contains($0)
        }
        let usable = candidates.isEmpty ? [SIMD2<Double>(0.5, 0.5)] : candidates
        let routeCoordinates = [
            0.08, 0.22, 0.25, 0.36, 0.375, 0.50,
            0.625, 0.64, 0.75, 0.78, 0.92,
        ]
        let routeCandidates = routeCoordinates.flatMap { y in
            routeCoordinates.map { x in SIMD2<Double>(x, y) }
        }.filter {
            !negativeSpace.contains($0) && !uiExclusionRegion.contains($0)
        }
        let focalIndex = Int(mixed(seed ^ 0x3C6E_F372_FE94_F82B) % UInt64(usable.count))
        let focal = usable[focalIndex]
        let clusterAngle = 2 * Double.pi * stableUnit(seed, salt: 0xA54F_F53A_5F1D_36F1)
        func clusteredAnchor(angle: Double, radius: Double) -> SIMD2<Double> {
            SIMD2(
                min(max(focal.x + radius * cos(angle), 0.06), 0.94),
                min(max(focal.y + radius * sin(angle), 0.06), 0.94)
            )
        }
        let support = clusteredAnchor(angle: clusterAngle, radius: 0.07)
        let bridge = (focal + support) * 0.5
        let satellite = clusteredAnchor(angle: clusterAngle + .pi, radius: 0.08)
        let accent = clusteredAnchor(angle: clusterAngle + .pi / 2, radius: 0.075)

        return DayObjectCompositionPlan(
            uiExclusionRegion: uiExclusionRegion,
            negativeSpaceRegion: negativeSpace,
            targetNegativeSpaceFraction: target,
            archetype: DayObjectCompositionArchetype.allCases[
                Int(mixed(seed ^ 0x510E_527F_ADE6_82D1)
                    % UInt64(DayObjectCompositionArchetype.allCases.count))
            ],
            usesFullCanvas: usesFullCanvas,
            focalAnchor: focal,
            supportAnchor: support,
            bridgeAnchor: bridge,
            satelliteAnchor: satellite,
            accentAnchor: accent,
            routeAnchorCandidates: routeCandidates.isEmpty
                ? [SIMD2<Double>(0.5, 0.5)]
                : routeCandidates
        )
    }

    func anchor(for role: DayObjectActorRole) -> SIMD2<Double> {
        switch role {
        case .focal: focalAnchor
        case .support: supportAnchor
        case .bridge: bridgeAnchor
        case .satellite: satelliteAnchor
        case .accent: accentAnchor
        }
    }

    func canvasPosition(
        for role: DayObjectActorRole,
        rawPosition: SIMD2<Double>,
        canvasAspect rawAspect: Double
    ) -> SIMD2<Double> {
        let aspect = rawAspect.isFinite && rawAspect > 0 ? rawAspect : 1
        let span = aspect >= 1
            ? SIMD2<Double>(aspect, 1)
            : SIMD2<Double>(1, 1 / aspect)
        let anchor = anchor(for: role)
        let anchorPosition = SIMD2<Double>(
            (anchor.x - 0.5) * span.x,
            (0.5 - anchor.y) * span.y
        )
        return anchorPosition + rawPosition * 0.52
    }

    func encounterCenter(channel: Int, canvasAspect rawAspect: Double) -> SIMD2<Double> {
        let span = canvasSpan(for: rawAspect)
        // Each time-staggered pair meets inside one of the distributed lanes
        // it already owns. A brief overlap therefore does not collapse the
        // rest of the canvas into a single central pile.
        let centers = [
            SIMD2<Double>(0.50, 0.35),
            SIMD2<Double>(0.50, 0.50),
            SIMD2<Double>(0.50, 0.65),
            SIMD2<Double>(0.50, 0.40),
            SIMD2<Double>(0.50, 0.60),
        ]
        let normalized = centers[((channel % centers.count) + centers.count) % centers.count]
        return SIMD2(
            (normalized.x - 0.5) * span.x,
            (0.5 - normalized.y) * span.y
        )
    }

    /// Selects one time-independent route center for an actor, then deforms
    /// the raw choreography continuously within the clearance around it. The
    /// finite candidate set is created with the daily plan; only a small,
    /// actor-local scan remains at sampling time, never a scene-wide solve.
    func stableRoutePosition(
        for role: DayObjectActorRole,
        actorSeed: UInt64,
        rawPosition: SIMD2<Double>,
        footprintReach rawFootprintReach: Double,
        canvasAspect rawAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasSpan(for: rawAspect)
        let halfCanvas = span * 0.5
        let footprintReach = rawFootprintReach.isFinite
            ? max(rawFootprintReach, 0)
            : 0
        let minimum = -halfCanvas + SIMD2(repeating: footprintReach)
        let maximum = halfCanvas - SIMD2(repeating: footprintReach)
        guard minimum.x <= maximum.x, minimum.y <= maximum.y else { return .zero }

        let forbidden = [negativeSpaceRegion, uiExclusionRegion].filter { $0.area > 0 }.map { region in
            let bounds = canvasBounds(for: region, span: span)
            return (
                minimum: bounds.minimum - SIMD2(repeating: footprintReach),
                maximum: bounds.maximum + SIMD2(repeating: footprintReach)
            )
        }
        let preferred = anchor(for: role) + SIMD2<Double>(
            0.018 * (2 * Self.stableUnit(actorSeed, salt: 0x510E_527F_ADE6_82D1) - 1),
            0.018 * (2 * Self.stableUnit(actorSeed, salt: 0x9B05_688C_2B3E_6C1F) - 1)
        )
        let maximumRawComponent = 0.225
        let desiredMotionClearance = 0.052
        var best: (
            center: SIMD2<Double>,
            usableMotionClearance: Double,
            preferredDistance: Double
        )?

        for candidate in routeAnchorCandidates {
            let center = SIMD2<Double>(
                (candidate.x - 0.5) * span.x,
                (0.5 - candidate.y) * span.y
            )
            guard center.x >= minimum.x, center.x <= maximum.x,
                  center.y >= minimum.y, center.y <= maximum.y,
                  forbidden.allSatisfy({ !Self.contains(center, in: $0) }) else {
                continue
            }

            var clearance = min(
                center.x - minimum.x,
                maximum.x - center.x,
                center.y - minimum.y,
                maximum.y - center.y
            )
            for bounds in forbidden {
                let xSeparation: Double
                if center.x <= bounds.minimum.x {
                    xSeparation = bounds.minimum.x - center.x
                } else if center.x >= bounds.maximum.x {
                    xSeparation = center.x - bounds.maximum.x
                } else {
                    xSeparation = 0
                }
                let ySeparation: Double
                if center.y <= bounds.minimum.y {
                    ySeparation = bounds.minimum.y - center.y
                } else if center.y >= bounds.maximum.y {
                    ySeparation = center.y - bounds.maximum.y
                } else {
                    ySeparation = 0
                }
                clearance = min(clearance, max(xSeparation, ySeparation))
            }

            let usableMotionClearance = min(
                max(clearance - 0.000_001, 0),
                desiredMotionClearance
            )
            let preferredDistance = simd_distance_squared(candidate, preferred)
            if best == nil
                || usableMotionClearance > best!.usableMotionClearance + 1e-12
                || (abs(usableMotionClearance - best!.usableMotionClearance) <= 1e-12
                    && preferredDistance < best!.preferredDistance) {
                best = (center, usableMotionClearance, preferredDistance)
            }
        }

        guard let best else {
            let fixedAnchor = canvasPosition(
                for: role,
                rawPosition: .zero,
                canvasAspect: rawAspect
            )
            return constrainedPosition(
                fixedAnchor,
                footprintHalfExtents: SIMD2(repeating: footprintReach),
                canvasAspect: rawAspect
            )
        }
        let motionScale = best.usableMotionClearance / maximumRawComponent
        return best.center + rawPosition * motionScale
    }

    func distributedRoutePosition(
        sector: Int,
        actorSeed: UInt64,
        localPosition: SIMD2<Double>,
        footprintReach rawFootprintReach: Double,
        canvasAspect rawAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasSpan(for: rawAspect)
        let halfCanvas = span * 0.5
        let footprintReach = rawFootprintReach.isFinite ? max(rawFootprintReach, 0) : 0
        let minimum = -halfCanvas + SIMD2(repeating: footprintReach)
        let maximum = halfCanvas - SIMD2(repeating: footprintReach)
        guard minimum.x <= maximum.x, minimum.y <= maximum.y else { return .zero }

        let normalizedSector = ((sector % 9) + 9) % 9
        let column = normalizedSector % 3
        let requestedRow = normalizedSector / 3
        let usableBottom = usesFullCanvas
            ? 1
            : min(uiExclusionRegion.minY, negativeSpaceRegion.minY)
        let usableRows = usesFullCanvas ? 3 : (usableBottom < 0.78 ? 2 : 3)
        let row = requestedRow % usableRows
        let rowMinY = usableRows == 2
            ? Double(row) / 3
            : Double(row) * usableBottom / Double(usableRows)
        let rowMaxY = usableRows == 2
            ? (row == usableRows - 1 ? usableBottom : Double(row + 1) / 3)
            : Double(row + 1) * usableBottom / Double(usableRows)
        let preferred = SIMD2<Double>(
            (Double(column) + 0.5) / 3,
            (rowMinY + rowMaxY) * 0.5
        )
        let laneRegion = DayObjectNormalizedRect(
            minX: Double(column) / 3,
            minY: rowMinY,
            maxX: Double(column + 1) / 3,
            maxY: rowMaxY
        )
        let laneBounds = canvasBounds(for: laneRegion, span: span)
        let usesDistributedLanes = usesFullCanvas
            || uiExclusionRegion == .dayObjectsLabControls
        let laneMinimum = usesDistributedLanes
            ? laneBounds.minimum + SIMD2(repeating: 0.005)
            : minimum
        let laneMaximum = usesDistributedLanes
            ? laneBounds.maximum - SIMD2(repeating: 0.005)
            : maximum
        let forbidden = [negativeSpaceRegion, uiExclusionRegion].filter { $0.area > 0 }.map { region in
            let bounds = canvasBounds(for: region, span: span)
            return (
                minimum: bounds.minimum - SIMD2(repeating: footprintReach),
                maximum: bounds.maximum + SIMD2(repeating: footprintReach)
            )
        }
        let key = DayObjectRoutePlacementKey(
            sector: normalizedSector,
            aspect: rawAspect,
            footprintReach: footprintReach,
            ui: uiExclusionRegion,
            negative: negativeSpaceRegion
        )
        let selected = Self.distributedPlacementCache.value(for: key) {
            var options = [DayObjectRoutePlacement]()
            let allowedMinimum = SIMD2(
                max(minimum.x, laneMinimum.x),
                max(minimum.y, laneMinimum.y)
            )
            let allowedMaximum = SIMD2(
                min(maximum.x, laneMaximum.x),
                min(maximum.y, laneMaximum.y)
            )
            let preferredCenter = SIMD2<Double>(
                (preferred.x - 0.5) * span.x,
                (0.5 - preferred.y) * span.y
            )
            func clamped(_ point: SIMD2<Double>) -> SIMD2<Double> {
                SIMD2(
                    min(max(point.x, allowedMinimum.x), allowedMaximum.x),
                    min(max(point.y, allowedMinimum.y), allowedMaximum.y)
                )
            }
            var centers = [clamped(preferredCenter)]
            for bounds in forbidden {
                centers.append(clamped(SIMD2(bounds.minimum.x, preferredCenter.y)))
                centers.append(clamped(SIMD2(bounds.maximum.x, preferredCenter.y)))
                centers.append(clamped(SIMD2(preferredCenter.x, bounds.minimum.y)))
                centers.append(clamped(SIMD2(preferredCenter.x, bounds.maximum.y)))
            }
            centers += routeAnchorCandidates.map { candidate in
                SIMD2<Double>(
                    (candidate.x - 0.5) * span.x,
                    (0.5 - candidate.y) * span.y
                )
            }

            for center in centers {
                guard center.x >= minimum.x, center.x <= maximum.x,
                      center.y >= minimum.y, center.y <= maximum.y,
                      center.x >= laneMinimum.x, center.x <= laneMaximum.x,
                      center.y >= laneMinimum.y, center.y <= laneMaximum.y,
                      forbidden.allSatisfy({ !Self.contains(center, in: $0) }) else {
                    continue
                }
                var clearance = min(
                    center.x - minimum.x,
                    maximum.x - center.x,
                    center.y - minimum.y,
                    maximum.y - center.y,
                    center.x - laneMinimum.x,
                    laneMaximum.x - center.x,
                    center.y - laneMinimum.y,
                    laneMaximum.y - center.y
                )
                for bounds in forbidden {
                    let xDistance = center.x < bounds.minimum.x
                        ? bounds.minimum.x - center.x
                        : center.x > bounds.maximum.x ? center.x - bounds.maximum.x : 0
                    let yDistance = center.y < bounds.minimum.y
                        ? bounds.minimum.y - center.y
                        : center.y > bounds.maximum.y ? center.y - bounds.maximum.y : 0
                    clearance = min(clearance, max(xDistance, yDistance))
                }
                options.append(DayObjectRoutePlacement(
                    center: center,
                    clearance: max(clearance - 0.000_001, 0),
                    preferredDistance: simd_distance_squared(center, preferredCenter)
                ))
            }
            return options.min(by: { lhs, rhs in
                let lhsUsable = lhs.clearance >= 0.055
                let rhsUsable = rhs.clearance >= 0.055
                if lhsUsable != rhsUsable { return lhsUsable }
                if lhs.preferredDistance != rhs.preferredDistance {
                    return lhs.preferredDistance < rhs.preferredDistance
                }
                return lhs.clearance > rhs.clearance
            })
        }
        guard let selected else {
            return constrainedPosition(
                .zero,
                footprintHalfExtents: SIMD2(repeating: footprintReach),
                canvasAspect: rawAspect
            )
        }
        _ = actorSeed
        let motionScale = min(selected.clearance / 0.38, 1)
        return selected.center + localPosition * motionScale
    }

    func constrainedPosition(
        _ rawPosition: SIMD2<Double>,
        footprintHalfExtents: SIMD2<Double>,
        canvasAspect rawAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasSpan(for: rawAspect)
        let halfCanvas = span * 0.5
        let minimum = -halfCanvas + footprintHalfExtents
        let maximum = halfCanvas - footprintHalfExtents
        let position = SIMD2(
            min(max(rawPosition.x, minimum.x), maximum.x),
            min(max(rawPosition.y, minimum.y), maximum.y)
        )

        // Daily anchors avoid these regions in the common case. This bounded
        // finite candidate projection is a final conservative constraint for
        // large/rotated footprints, not a global or per-pixel optimization.
        let forbidden = [negativeSpaceRegion, uiExclusionRegion].filter { $0.area > 0 }.map { region in
            let bounds = canvasBounds(for: region, span: span)
            return (
                minimum: bounds.minimum - footprintHalfExtents,
                maximum: bounds.maximum + footprintHalfExtents
            )
        }
        guard forbidden.contains(where: { Self.contains(position, in: $0) }) else {
            return position
        }

        let candidateX = [position.x, minimum.x, maximum.x] + forbidden.flatMap {
            [
                min(max($0.minimum.x, minimum.x), maximum.x),
                min(max($0.maximum.x, minimum.x), maximum.x),
            ]
        }
        let candidateY = [position.y, minimum.y, maximum.y] + forbidden.flatMap {
            [
                min(max($0.minimum.y, minimum.y), maximum.y),
                min(max($0.maximum.y, minimum.y), maximum.y),
            ]
        }
        let candidates = candidateY.flatMap { y in
            candidateX.map { x in SIMD2<Double>(x, y) }
        }.filter { candidate in
            forbidden.allSatisfy { !Self.contains(candidate, in: $0) }
        }
        return candidates.min { lhs, rhs in
            let lhsDistance = simd_distance_squared(lhs, position)
            let rhsDistance = simd_distance_squared(rhs, position)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.x != rhs.x ? lhs.x < rhs.x : lhs.y < rhs.y
        } ?? position
    }

    private static func contains(
        _ point: SIMD2<Double>,
        in bounds: (minimum: SIMD2<Double>, maximum: SIMD2<Double>)
    ) -> Bool {
        point.x > bounds.minimum.x && point.x < bounds.maximum.x
            && point.y > bounds.minimum.y && point.y < bounds.maximum.y
    }

    func intersectsUIExclusion(
        position: SIMD2<Double>,
        footprintHalfExtents: SIMD2<Double>,
        canvasAspect: Double
    ) -> Bool {
        intersects(
            uiExclusionRegion,
            position: position,
            footprintHalfExtents: footprintHalfExtents,
            canvasAspect: canvasAspect
        )
    }

    func intersectsNegativeSpace(
        position: SIMD2<Double>,
        footprintHalfExtents: SIMD2<Double>,
        canvasAspect: Double
    ) -> Bool {
        intersects(
            negativeSpaceRegion,
            position: position,
            footprintHalfExtents: footprintHalfExtents,
            canvasAspect: canvasAspect
        )
    }

    private func intersects(
        _ region: DayObjectNormalizedRect,
        position: SIMD2<Double>,
        footprintHalfExtents: SIMD2<Double>,
        canvasAspect: Double
    ) -> Bool {
        guard region.area > 0 else { return false }
        let span = canvasSpan(for: canvasAspect)
        let bounds = canvasBounds(for: region, span: span)
        return position.x - footprintHalfExtents.x < bounds.maximum.x
            && position.x + footprintHalfExtents.x > bounds.minimum.x
            && position.y - footprintHalfExtents.y < bounds.maximum.y
            && position.y + footprintHalfExtents.y > bounds.minimum.y
    }

    private func canvasSpan(for rawAspect: Double) -> SIMD2<Double> {
        let aspect = rawAspect.isFinite && rawAspect > 0 ? rawAspect : 1
        return aspect >= 1
            ? SIMD2<Double>(aspect, 1)
            : SIMD2<Double>(1, 1 / aspect)
    }

    private func canvasBounds(
        for region: DayObjectNormalizedRect,
        span: SIMD2<Double>
    ) -> (minimum: SIMD2<Double>, maximum: SIMD2<Double>) {
        (
            minimum: SIMD2(
                (region.minX - 0.5) * span.x,
                (0.5 - region.maxY) * span.y
            ),
            maximum: SIMD2(
                (region.maxX - 0.5) * span.x,
                (0.5 - region.minY) * span.y
            )
        )
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

private struct DayObjectRoutePlacementKey: Hashable {
    let sector: Int
    let aspect: UInt64
    let footprintReach: UInt64
    let uiMinX: UInt64
    let uiMinY: UInt64
    let uiMaxX: UInt64
    let uiMaxY: UInt64
    let negativeMinX: UInt64
    let negativeMinY: UInt64
    let negativeMaxX: UInt64
    let negativeMaxY: UInt64

    init(
        sector: Int,
        aspect: Double,
        footprintReach: Double,
        ui: DayObjectNormalizedRect,
        negative: DayObjectNormalizedRect
    ) {
        self.sector = sector
        self.aspect = aspect.bitPattern
        self.footprintReach = footprintReach.bitPattern
        uiMinX = ui.minX.bitPattern
        uiMinY = ui.minY.bitPattern
        uiMaxX = ui.maxX.bitPattern
        uiMaxY = ui.maxY.bitPattern
        negativeMinX = negative.minX.bitPattern
        negativeMinY = negative.minY.bitPattern
        negativeMaxX = negative.maxX.bitPattern
        negativeMaxY = negative.maxY.bitPattern
    }
}

private struct DayObjectRoutePlacement {
    let center: SIMD2<Double>
    let clearance: Double
    let preferredDistance: Double
}

private final class DayObjectRoutePlacementCache {
    private let lock = NSLock()
    private var values = [DayObjectRoutePlacementKey: DayObjectRoutePlacement]()

    func value(
        for key: DayObjectRoutePlacementKey,
        make: () -> DayObjectRoutePlacement?
    ) -> DayObjectRoutePlacement? {
        lock.lock()
        let existing = values[key]
        lock.unlock()
        if let existing { return existing }

        guard let generated = make() else { return nil }
        lock.lock()
        values[key] = generated
        lock.unlock()
        return generated
    }
}

/// Daily geometry choices retained while rendering moves to the stable scene.
struct DayObjectComposition: Equatable {
    let shape: DayObjectShape
    let elongation: DayObjectElongation
    let fill: DayObjectFill
    let trajectory: DayObjectTrajectory
    let spin: DayObjectSpin
    let sizeComposition: DayObjectSizeComposition
    let flockSize: Int

    static let maxObjects = DayObjectScene.maxActors

    static func forDay(dayKey: String, identity: String = "local") -> DayObjectComposition {
        let normalizedIdentity = identity.isEmpty ? "anonymous" : identity
        let seed = CanvasElement.makeSeed(
            optionId: "dayObjects:\(normalizedIdentity)",
            dayKey: dayKey,
            index: 0
        )

        func pick<T>(_ options: [T], domain: StaticString) -> T {
            var rng = SeededRNG.derived(from: seed, domain: domain)
            return options[rng.nextInt(in: 0...(options.count - 1))]
        }

        return DayObjectComposition(
            shape: pick(DayObjectShape.allCases, domain: "shape"),
            elongation: pick(DayObjectElongation.allCases, domain: "elongation"),
            fill: pick(DayObjectFill.allCases, domain: "fill"),
            trajectory: pick(DayObjectTrajectory.allCases, domain: "trajectory"),
            spin: pick(DayObjectSpin.allCases, domain: "spin"),
            sizeComposition: pick(
                DayObjectSizeComposition.allCases,
                domain: "sizeComposition"
            ),
            flockSize: 1
        )
    }

    var summary: String {
        "\(shape.rawValue) · \(elongation.rawValue) · \(fill.rawValue) · "
            + "\(trajectory.rawValue) · \(spin.rawValue)"
    }
}
