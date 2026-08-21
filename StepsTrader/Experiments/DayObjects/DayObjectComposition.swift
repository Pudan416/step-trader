import Foundation
import simd

/// Shape family used by the Day Objects renderer.
enum DayObjectShape: String, CaseIterable, Hashable {
    case capsule
    case drop
    case slab
    case dart
    case wedge
    case scallop
    case burst
}

enum DayObjectElongation: String, CaseIterable, Hashable {
    case compact
    case stretched

    var aspectRange: ClosedRange<Double> {
        switch self {
        case .compact: 0.55...0.95
        case .stretched: 0.10...0.28
        }
    }
}

enum DayObjectScale: String, CaseIterable, Hashable {
    case small
    case medium
    case large

    var lengthRange: ClosedRange<Double> {
        switch self {
        case .small: 0.03...0.06
        case .medium: 0.08...0.14
        case .large: 0.18...0.30
        }
    }

    var perHappening: ClosedRange<Int> {
        switch self {
        case .small: 4...7
        case .medium: 2...3
        case .large: 1...1
        }
    }
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
    let uiExclusionRegion: DayObjectNormalizedRect
    let negativeSpaceRegion: DayObjectNormalizedRect
    let targetNegativeSpaceFraction: Double

    private let focalAnchor: SIMD2<Double>
    private let supportAnchor: SIMD2<Double>
    private let bridgeAnchor: SIMD2<Double>
    private let satelliteAnchor: SIMD2<Double>
    private let accentAnchor: SIMD2<Double>
    private let routeAnchorCandidates: [SIMD2<Double>]

    static func make(
        seed: UInt64,
        uiExclusionRegion: DayObjectNormalizedRect
    ) -> DayObjectCompositionPlan {
        let target = 0.35 + 0.20 * stableUnit(seed, salt: 0x6A09_E667_F3BC_C909)
        let negativeSpace: DayObjectNormalizedRect
        if (0.35...0.55).contains(uiExclusionRegion.area) {
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
        let routeCoordinates = stride(from: 0.05, through: 0.95, by: 0.10)
        let routeCandidates = routeCoordinates.flatMap { y in
            routeCoordinates.map { x in SIMD2<Double>(x, y) }
        }.filter {
            !negativeSpace.contains($0) && !uiExclusionRegion.contains($0)
        }
        let focalIndex = Int(mixed(seed ^ 0x3C6E_F372_FE94_F82B) % UInt64(usable.count))
        let focal = usable[focalIndex]
        let supportCandidates = usable.filter {
            let distance = simd_distance($0, focal)
            return distance >= 0.22 && distance <= 0.62
        }
        let supportPool = supportCandidates.isEmpty ? usable : supportCandidates
        let supportIndex = Int(mixed(seed ^ 0xA54F_F53A_5F1D_36F1) % UInt64(supportPool.count))
        let support = supportPool[supportIndex]
        let bridge = (focal + support) * 0.5
        let satellite = usable.max { lhs, rhs in
            simd_distance(lhs, focal) < simd_distance(rhs, focal)
        } ?? focal
        let accent = usable.min { lhs, rhs in
            simd_distance(lhs, support) < simd_distance(rhs, support)
        } ?? support

        return DayObjectCompositionPlan(
            uiExclusionRegion: uiExclusionRegion,
            negativeSpaceRegion: negativeSpace,
            targetNegativeSpaceFraction: target,
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

        let forbidden = [negativeSpaceRegion, uiExclusionRegion].map { region in
            let bounds = canvasBounds(for: region, span: span)
            return (
                minimum: bounds.minimum - SIMD2(repeating: footprintReach),
                maximum: bounds.maximum + SIMD2(repeating: footprintReach)
            )
        }
        let preferred = anchor(for: role) + SIMD2<Double>(
            0.08 * (2 * Self.stableUnit(actorSeed, salt: 0x510E_527F_ADE6_82D1) - 1),
            0.08 * (2 * Self.stableUnit(actorSeed, salt: 0x9B05_688C_2B3E_6C1F) - 1)
        )
        let maximumRawComponent = 0.225
        let desiredMotionClearance = maximumRawComponent * 0.52
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
        let forbidden = [negativeSpaceRegion, uiExclusionRegion].map { region in
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

/// Daily geometry choices retained while rendering moves to the stable scene.
struct DayObjectComposition: Equatable {
    let shape: DayObjectShape
    let elongation: DayObjectElongation
    let scale: DayObjectScale
    let fill: DayObjectFill
    let trajectory: DayObjectTrajectory
    let spin: DayObjectSpin
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

        let scale = pick(DayObjectScale.allCases, domain: "scale")
        var flockRNG = SeededRNG.derived(from: seed, domain: "flockSize")

        return DayObjectComposition(
            shape: pick(DayObjectShape.allCases, domain: "shape"),
            elongation: pick(DayObjectElongation.allCases, domain: "elongation"),
            scale: scale,
            fill: pick(DayObjectFill.allCases, domain: "fill"),
            trajectory: pick(DayObjectTrajectory.allCases, domain: "trajectory"),
            spin: pick(DayObjectSpin.allCases, domain: "spin"),
            flockSize: flockRNG.nextInt(in: scale.perHappening)
        )
    }

    var summary: String {
        "\(shape.rawValue) · \(elongation.rawValue) · \(scale.rawValue) · \(fill.rawValue) · "
            + "\(trajectory.rawValue) · \(spin.rawValue)"
    }
}
