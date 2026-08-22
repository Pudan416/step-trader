import Foundation
import simd

enum DayObjectChapter: Int, CaseIterable, Equatable, Hashable {
    case orbit
    case spiral
    case crossing
    case stack
    case bloom
    case drift
}

enum DayObjectActorGeometry {
    static let softBlobRadialReach = 1.06
    static let trailSigmaFactor = 0.36
    static let trailSigmaSupport = 3.2

    static func aspectRatio(for actor: DayObjectActor) -> Double {
        let range = actor.elongation.aspectRange
        return range.lowerBound
            + (range.upperBound - range.lowerBound)
                * stableUnit(actor.seed, salt: 0x9E37_79B9_7F4A_7C15)
    }

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ salt
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}

struct DayObjectGeometryFootprint: Equatable {
    let forwardReach: Double
    let backwardReach: Double
    let lateralReach: Double
    let axisAlignedHalfExtents: SIMD2<Double>

    static func make(
        halfSize: SIMD2<Double>,
        direction rawDirection: SIMD2<Double>,
        shape: DayObjectShape,
        trailLength: Double,
        shortSidePixels: Double
    ) -> DayObjectGeometryFootprint {
        let safeHalfSize = SIMD2(
            halfSize.x.isFinite ? max(halfSize.x, 0) : 0,
            halfSize.y.isFinite ? max(halfSize.y, 0) : 0
        )
        let bodyMultiplier = shape == .softBlob
            ? DayObjectActorGeometry.softBlobRadialReach
            : 1
        let forwardReach = safeHalfSize.x * bodyMultiplier
        let backwardReach = max(
            forwardReach,
            safeHalfSize.x + max(trailLength.isFinite ? trailLength : 0, 0)
        )
        let pixels = shortSidePixels.isFinite ? max(shortSidePixels, 1) : 1
        let sigma = max(
            safeHalfSize.y * DayObjectActorGeometry.trailSigmaFactor,
            1.25 / pixels
        )
        let lateralReach = max(
            safeHalfSize.y * bodyMultiplier,
            sigma * DayObjectActorGeometry.trailSigmaSupport
        )
        let directionLength = simd_length(rawDirection)
        let direction = directionLength > 0.000_001
            ? rawDirection / directionLength
            : SIMD2<Double>(1, 0)
        let lateral = SIMD2<Double>(-direction.y, direction.x)
        let longitudinalReach = max(forwardReach, backwardReach)
        let pixelMargin = 2 / pixels
        let extents = SIMD2(
            longitudinalReach * abs(direction.x) + lateralReach * abs(lateral.x) + pixelMargin,
            longitudinalReach * abs(direction.y) + lateralReach * abs(lateral.y) + pixelMargin
        )
        return DayObjectGeometryFootprint(
            forwardReach: forwardReach,
            backwardReach: backwardReach,
            lateralReach: lateralReach,
            axisAlignedHalfExtents: extents
        )
    }
}

struct DayObjectPose: Equatable {
    let position: SIMD2<Double>
    let tangent: SIMD2<Double>
    let rotation: Double
    let scale: Double
    let opacity: Double
    let depthBand: Int
    let bodyRadius: Double
    let trailReach: Double
    let footprintHalfExtents: SIMD2<Double>
    let isInsideSafeBounds: Bool
    let intersectsUIExclusion: Bool
    let intersectsNegativeSpace: Bool
}

struct DayObjectChoreographyScore: Equatable {
    private static let transitionFraction = 0.12
    private static let twoPi = 2 * Double.pi

    let chapters: [DayObjectChapter]
    let duration: Double

    var boundaryTimes: [Double] {
        guard chapters.count > 1 else { return [] }
        let chapterDuration = duration / Double(chapters.count)
        return (1..<chapters.count).map { Double($0) * chapterDuration }
    }

    static func make(seed: UInt64) -> DayObjectChoreographyScore {
        var rng = SeededRNG.derived(from: seed, domain: "choreographyScore")
        let chapterCount = rng.nextInt(in: 3...5)
        var vocabulary = DayObjectChapter.allCases

        // An explicit Fisher-Yates shuffle keeps the daily order independent
        // of standard-library collection implementation details.
        if vocabulary.count > 1 {
            for index in stride(from: vocabulary.count - 1, through: 1, by: -1) {
                let other = rng.nextInt(in: 0...index)
                vocabulary.swapAt(index, other)
            }
        }

        return DayObjectChoreographyScore(
            chapters: Array(vocabulary.prefix(chapterCount)),
            duration: Double(rng.nextInt(in: 36...72))
        )
    }

    func pose(
        for actor: DayObjectActor,
        at rawTime: Double,
        canvasAspect rawAspect: Double,
        compositionPlan: DayObjectCompositionPlan? = nil
    ) -> DayObjectPose {
        let time = normalizedTime(rawTime)
        let sample = interpolatedSample(for: actor, at: time)
        let rawTangent = timeTangent(for: actor, at: time)
        let trailReach = 0.014 + 0.008 * actor.speedRatio
        let aspect = rawAspect.isFinite && rawAspect > 0 ? rawAspect : 1
        let renderScale = compositionPlan?.uiExclusionRegion == .dayObjectsLabControls
            || compositionPlan == nil
            ? sample.scale
            : min(sample.scale, DayObjectSizeBand.satellite.diameterRange.upperBound)
        let halfSize = SIMD2<Double>(
            renderScale * 0.5,
            renderScale * 0.5 * DayObjectActorGeometry.aspectRatio(for: actor)
        )
        var footprint = DayObjectGeometryFootprint.make(
            halfSize: halfSize,
            direction: rawTangent,
            shape: actor.shape,
            trailLength: trailReach,
            shortSidePixels: 128
        )
        var position = sample.position
        var tangent = rawTangent
        if let compositionPlan {
            position = constrainedPlannedPosition(
                for: actor,
                at: time,
                canvasAspect: aspect,
                plan: compositionPlan
            )
            tangent = plannedTimeTangent(
                for: actor,
                at: time,
                canvasAspect: aspect,
                plan: compositionPlan
            )
            footprint = DayObjectGeometryFootprint.make(
                halfSize: halfSize,
                direction: tangent,
                shape: actor.shape,
                trailLength: trailReach,
                shortSidePixels: 128
            )
        }
        let bodyRadius = max(footprint.forwardReach, footprint.lateralReach)
        let halfExtents = aspect >= 1
            ? SIMD2<Double>(aspect * 0.5, 0.5)
            : SIMD2<Double>(0.5, 0.5 / aspect)
        let inside = abs(position.x) + footprint.axisAlignedHalfExtents.x <= halfExtents.x + 0.000_000_1
            && abs(position.y) + footprint.axisAlignedHalfExtents.y <= halfExtents.y + 0.000_000_1
        let intersectsUI = compositionPlan?.intersectsUIExclusion(
            position: position,
            footprintHalfExtents: footprint.axisAlignedHalfExtents,
            canvasAspect: aspect
        ) ?? false
        let intersectsNegative = compositionPlan?.intersectsNegativeSpace(
            position: position,
            footprintHalfExtents: footprint.axisAlignedHalfExtents,
            canvasAspect: aspect
        ) ?? false

        return DayObjectPose(
            position: position,
            tangent: tangent,
            rotation: rotation(for: actor, tangent: tangent, at: time),
            scale: renderScale,
            opacity: sample.opacity,
            depthBand: sample.depthBand,
            bodyRadius: bodyRadius,
            trailReach: trailReach,
            footprintHalfExtents: footprint.axisAlignedHalfExtents,
            isInsideSafeBounds: inside,
            intersectsUIExclusion: intersectsUI,
            intersectsNegativeSpace: intersectsNegative
        )
    }

    private func constrainedPlannedPosition(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        plan: DayObjectCompositionPlan
    ) -> SIMD2<Double> {
        let sample = interpolatedSample(for: actor, at: normalizedTime(time))
        let planningDiameter = plan.uiExclusionRegion == .dayObjectsLabControls
            ? 0.34
            : min(
                baseLength(for: actor),
                DayObjectSizeBand.satellite.diameterRange.upperBound
            )
        let majorHalfSize = planningDiameter * 1.04 * 0.5
        let bodyMultiplier = actor.shape == .softBlob
            ? DayObjectActorGeometry.softBlobRadialReach
            : 1
        let orientationIndependentReach = majorHalfSize * bodyMultiplier
            + 0.014 + 0.008 * actor.speedRatio
            + 0.025
            + 2.0 / 128.0
        return plan.stableRoutePosition(
            for: actor.role,
            actorSeed: actor.seed,
            rawPosition: sample.position,
            footprintReach: orientationIndependentReach,
            canvasAspect: canvasAspect
        )
    }

    private func plannedTimeTangent(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        plan: DayObjectCompositionPlan
    ) -> SIMD2<Double> {
        let epsilon = min(0.0001, duration / Double(max(chapters.count, 1)) * 0.00001)
        let travel = constrainedPlannedPosition(
            for: actor,
            at: time + epsilon,
            canvasAspect: canvasAspect,
            plan: plan
        ) - constrainedPlannedPosition(
            for: actor,
            at: time - epsilon,
            canvasAspect: canvasAspect,
            plan: plan
        )
        let length = simd_length(travel)
        if length > 1e-12 {
            return travel / length
        }
        // A conservative exclusion route can intentionally collapse motion
        // to zero when no safe deformation radius remains. Keep orientation
        // deterministic there instead of inheriting a meaningless cusp from
        // the hidden raw path.
        return SIMD2(cos(actor.phaseOffset), sin(actor.phaseOffset))
    }

    private func normalizedTime(_ rawTime: Double) -> Double {
        guard rawTime.isFinite, duration > 0 else { return 0 }
        let remainder = rawTime.truncatingRemainder(dividingBy: duration)
        return remainder >= 0 ? remainder : remainder + duration
    }

    private func interpolatedSample(for actor: DayObjectActor, at time: Double) -> ChapterSample {
        guard !chapters.isEmpty else {
            return ChapterSample(
                position: .zero,
                scale: baseLength(for: actor),
                opacity: 1,
                depthBand: actor.depthBand
            )
        }

        let chapterDuration = duration / Double(chapters.count)
        let chapterPosition = time / chapterDuration
        let index = min(Int(chapterPosition), chapters.count - 1)
        let localProgress = chapterPosition - Double(index)
        let current = chapterSample(
            chapters[index],
            chapterIndex: index,
            actor: actor,
            localProgress: localProgress
        )
        let transitionStart = 1 - Self.transitionFraction
        guard localProgress >= transitionStart else { return current }

        let nextIndex = (index + 1) % chapters.count
        let next = chapterSample(
            chapters[nextIndex],
            chapterIndex: nextIndex,
            actor: actor,
            localProgress: localProgress - 1
        )
        let linearBlend = (localProgress - transitionStart) / Self.transitionFraction
        let blend = quinticSmoothstep(linearBlend)
        return ChapterSample(
            position: current.position + (next.position - current.position) * blend,
            scale: current.scale + (next.scale - current.scale) * blend,
            opacity: current.opacity + (next.opacity - current.opacity) * blend,
            depthBand: blend < 0.5 ? current.depthBand : next.depthBand
        )
    }

    private func timeTangent(for actor: DayObjectActor, at time: Double) -> SIMD2<Double> {
        let epsilon = min(0.0001, duration / Double(max(chapters.count, 1)) * 0.00001)
        var travel = interpolatedSample(
            for: actor,
            at: normalizedTime(time + epsilon)
        ).position - interpolatedSample(
            for: actor,
            at: normalizedTime(time - epsilon)
        ).position

        if simd_length_squared(travel) < 1e-16 {
            travel = interpolatedSample(
                for: actor,
                at: normalizedTime(time + epsilon * 8)
            ).position - interpolatedSample(
                for: actor,
                at: normalizedTime(time - epsilon * 8)
            ).position
        }
        let length = simd_length(travel)
        return length > 1e-12 ? travel / length : SIMD2<Double>(1, 0)
    }

    private func rotation(for actor: DayObjectActor, tangent: SIMD2<Double>, at time: Double) -> Double {
        let heading = atan2(tangent.y, tangent.x)
        let direction = travelDirection(for: actor)
        let masterTurns = time / duration
        switch actor.spin {
        case .follow:
            return heading
        case .slowRoll:
            return heading + direction * Self.twoPi * masterTurns
        case .tumble:
            return heading + direction * Self.twoPi * masterTurns * 2
        }
    }

    private func chapterSample(
        _ chapter: DayObjectChapter,
        chapterIndex: Int,
        actor: DayObjectActor,
        localProgress: Double
    ) -> ChapterSample {
        let direction = travelDirection(for: actor)
        let actorAngle = Self.twoPi * localProgress * actor.speedRatio * direction + actor.phaseOffset
        let lane = -0.16 + 0.32 * stableUnit(actor.seed, salt: 0xA24B_AED4_963E_E407)
        let roleWeight: Double
        switch actor.role {
        case .focal: roleWeight = 1
        case .support: roleWeight = 0.86
        case .bridge: roleWeight = 0.78
        case .satellite: roleWeight = 0.94
        case .accent: roleWeight = 0.68
        }

        let position: SIMD2<Double>
        switch chapter {
        case .orbit:
            let radius = (0.14 + 0.07 * stableUnit(actor.seed, salt: 0x9E37_79B9_7F4A_7C15)) * roleWeight
            position = SIMD2<Double>(radius * cos(actorAngle), radius * 0.78 * sin(actorAngle))
        case .spiral:
            let breath = 0.5 + 0.5 * sin(Self.twoPi * localProgress + actor.phaseOffset * 0.31)
            let radius = (0.065 + 0.135 * breath) * (0.82 + 0.18 * roleWeight)
            position = SIMD2<Double>(radius * cos(actorAngle), radius * sin(actorAngle))
        case .crossing:
            position = SIMD2<Double>(
                0.22 * sin(actorAngle),
                lane * 0.72 + 0.045 * cos(actorAngle)
            )
        case .stack:
            position = SIMD2<Double>(
                lane + 0.06 * cos(actorAngle),
                0.205 * sin(actorAngle)
            )
        case .bloom:
            let radius = 0.11 + 0.055 * roleWeight
            position = SIMD2<Double>(
                radius * cos(actorAngle),
                radius * 0.82 * sin(actorAngle)
            )
        case .drift:
            position = SIMD2<Double>(
                0.215 * sin(actorAngle),
                0.17 * cos(actorAngle)
            )
        }

        let opacityBase: Double
        switch actor.role {
        case .focal: opacityBase = 1
        case .support: opacityBase = 0.92
        case .bridge: opacityBase = 0.86
        case .satellite: opacityBase = 0.78
        case .accent: opacityBase = 0.9
        }
        let visibility = actor.role == .accent
            ? 0.08 + 0.92 * (0.5 + 0.5 * cos(actorAngle * 0.5 + Double(chapterIndex)))
            : 1
        let depthShift: Int
        switch chapter {
        case .orbit, .stack: depthShift = 0
        case .spiral, .drift: depthShift = 1
        case .crossing: depthShift = chapterIndex.isMultiple(of: 2) ? 2 : 3
        case .bloom: depthShift = 3
        }

        return ChapterSample(
            position: position,
            scale: baseLength(for: actor),
            opacity: opacityBase * visibility,
            depthBand: (actor.depthBand + depthShift) % 4
        )
    }

    private func baseLength(for actor: DayObjectActor) -> Double {
        let range = actor.sizeBand.diameterRange
        return range.lowerBound
            + (range.upperBound - range.lowerBound)
                * stableUnit(actor.seed, salt: 0xA409_3822_299F_31D0)
    }

    func travelDirection(for actor: DayObjectActor) -> Double {
        mixed(actor.seed ^ 0xD1B5_4A32_D192_ED03).isMultiple(of: 2) ? 1 : -1
    }

    private func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        Double(mixed(seed ^ salt) >> 11) / Double(UInt64(1) << 53)
    }

    private func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private func quinticSmoothstep(_ rawValue: Double) -> Double {
        let value = min(max(rawValue, 0), 1)
        return value * value * value * (value * (value * 6 - 15) + 10)
    }
}

private struct ChapterSample {
    let position: SIMD2<Double>
    let scale: Double
    let opacity: Double
    let depthBand: Int
}
