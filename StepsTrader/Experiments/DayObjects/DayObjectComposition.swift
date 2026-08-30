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
    let uiExclusionRegion: DayObjectNormalizedRect
    let negativeSpaceRegion: DayObjectNormalizedRect
    let targetNegativeSpaceFraction: Double
    let archetype: DayObjectCompositionArchetype
    let usesFullCanvas: Bool

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

        return DayObjectCompositionPlan(
            uiExclusionRegion: uiExclusionRegion,
            negativeSpaceRegion: negativeSpace,
            targetNegativeSpaceFraction: target,
            archetype: DayObjectCompositionArchetype.allCases[
                Int(mixed(seed ^ 0x510E_527F_ADE6_82D1)
                    % UInt64(DayObjectCompositionArchetype.allCases.count))
            ],
            usesFullCanvas: usesFullCanvas
        )
    }

    /// Applies one shared affine transform to the complete preset formation.
    /// The transform selects the largest continuous rectangle outside reserved
    /// UI/negative-space regions, so actors retain their preset relationships
    /// without frame-local projection jumps or generic per-actor sectors.
    func safeChoreographyPosition(
        _ rawPosition: SIMD2<Double>,
        formationReach rawFormationReach: Double,
        canvasAspect rawAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasSpan(for: rawAspect)
        let halfCanvas = span * 0.5
        let reach = rawFormationReach.isFinite ? max(rawFormationReach, 0) : 0
        let minimum = -halfCanvas + SIMD2(repeating: reach)
        let maximum = halfCanvas - SIMD2(repeating: reach)
        guard minimum.x < maximum.x, minimum.y < maximum.y else { return .zero }

        let forbidden = [negativeSpaceRegion, uiExclusionRegion].filter { $0.area > 0 }.map { region in
            let bounds = canvasBounds(for: region, span: span)
            return (
                minimum: bounds.minimum - SIMD2(repeating: reach),
                maximum: bounds.maximum + SIMD2(repeating: reach)
            )
        }

        var xEdges = [minimum.x, maximum.x]
        var yEdges = [minimum.y, maximum.y]
        for bounds in forbidden {
            xEdges += [
                min(max(bounds.minimum.x, minimum.x), maximum.x),
                min(max(bounds.maximum.x, minimum.x), maximum.x),
            ]
            yEdges += [
                min(max(bounds.minimum.y, minimum.y), maximum.y),
                min(max(bounds.maximum.y, minimum.y), maximum.y),
            ]
        }
        xEdges = Array(Set(xEdges)).sorted()
        yEdges = Array(Set(yEdges)).sorted()

        struct Candidate {
            let minimum: SIMD2<Double>
            let maximum: SIMD2<Double>
            let scale: Double
            let area: Double
            let centerDistance: Double
        }

        let sourceHalf = span * 0.62
        var candidates = [Candidate]()
        for minXIndex in xEdges.indices {
            for maxXIndex in xEdges.indices where maxXIndex > minXIndex {
                for minYIndex in yEdges.indices {
                    for maxYIndex in yEdges.indices where maxYIndex > minYIndex {
                        let lower = SIMD2(xEdges[minXIndex], yEdges[minYIndex])
                        let upper = SIMD2(xEdges[maxXIndex], yEdges[maxYIndex])
                        let size = upper - lower
                        guard size.x > 0.000_002, size.y > 0.000_002 else { continue }
                        let overlapsForbidden = forbidden.contains { bounds in
                            lower.x < bounds.maximum.x && upper.x > bounds.minimum.x
                                && lower.y < bounds.maximum.y && upper.y > bounds.minimum.y
                        }
                        guard !overlapsForbidden else { continue }
                        let scale = min(
                            size.x / (2 * sourceHalf.x),
                            size.y / (2 * sourceHalf.y)
                        )
                        let center = (lower + upper) * 0.5
                        candidates.append(Candidate(
                            minimum: lower,
                            maximum: upper,
                            scale: scale,
                            area: size.x * size.y,
                            centerDistance: simd_length_squared(center)
                        ))
                    }
                }
            }
        }

        guard let selected = candidates.max(by: { lhs, rhs in
            if abs(lhs.scale - rhs.scale) > 0.000_001 {
                return lhs.scale < rhs.scale
            }
            if abs(lhs.area - rhs.area) > 0.000_001 {
                return lhs.area < rhs.area
            }
            return lhs.centerDistance > rhs.centerDistance
        }) else { return .zero }

        let boundedRaw = SIMD2(
            min(max(rawPosition.x, -sourceHalf.x), sourceHalf.x),
            min(max(rawPosition.y, -sourceHalf.y), sourceHalf.y)
        )
        return (selected.minimum + selected.maximum) * 0.5
            + boundedRaw * max(selected.scale - 0.000_001, 0)
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
