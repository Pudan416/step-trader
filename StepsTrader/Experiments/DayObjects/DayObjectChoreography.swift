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
    static let mergeReachFactor = 0.18
    static let mergeAlpha = 0.16
    static let trailSigmaFactor = 0.36
    static let trailSigmaSupport = 3.2

    static func aspectRatio(for actor: DayObjectActor) -> Double {
        min(max(actor.appearance.elongation, 0.95), 1.05)
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
        let mergeReach = safeHalfSize.x * DayObjectActorGeometry.mergeReachFactor
        let forwardReach = safeHalfSize.x * bodyMultiplier + mergeReach
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
            safeHalfSize.y * bodyMultiplier + mergeReach,
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
    let depth: Double
    let depthBand: Int
    let localDepthSoftness: Double
    let materialPhase: Double
    let intentionalCropFraction: Double
    let bodyRadius: Double
    let trailReach: Double
    let footprintHalfExtents: SIMD2<Double>
    let isInsideSafeBounds: Bool
    let intersectsUIExclusion: Bool
    let intersectsNegativeSpace: Bool
}

struct DayObjectChoreographyScore: Equatable {
    let family: DayObjectChoreographyFamily
    let duration: Double

    // Compatibility surface for transition tests while the old chapter
    // vocabulary is removed from production motion.
    let chapters: [DayObjectChapter] = []
    var boundaryTimes: [Double] { [] }

    static func make(seed: UInt64) -> DayObjectChoreographyScore {
        let family = DayObjectChoreographyFamily.allCases[
            Int(mixed(seed ^ 0x243F_6A88_85A3_08D3)
                % UInt64(DayObjectChoreographyFamily.allCases.count))
        ]
        return DayObjectChoreographyScore(family: family, duration: 120)
    }

    func pose(
        for actor: DayObjectActor,
        at rawTime: Double,
        canvasAspect rawAspect: Double,
        compositionPlan: DayObjectCompositionPlan? = nil
    ) -> DayObjectPose {
        let time = rawTime.isFinite ? rawTime : 0
        let aspect = rawAspect.isFinite && rawAspect > 0 ? rawAspect : 1
        let depth = depthValue(for: actor, at: time)
        let profile = actor.choreographyConfiguration.sizeProfile
        let depthScale = profile == .spatial ? 0.56 + 1.04 * depth : 1
        let breathingAmplitude = profile == .uniform ? 0.018 : 0.035
        let actorBreathingPhase = 2 * Double.pi * (
            time / actor.depthSchedule.period
                + actor.phaseOffset / (2 * Double.pi)
        )
        let breathing = 1 + breathingAmplitude * sin(actorBreathingPhase)
        let scale = presetDiameter(
            for: actor,
            compositionPlan: compositionPlan
        ) * depthScale * breathing
        let trailReach = 0.008
        let rawTangent = routeTangent(for: actor, at: time)
        let halfSize = SIMD2<Double>(
            scale * 0.5,
            scale * 0.5 * DayObjectActorGeometry.aspectRatio(for: actor)
        )
        let position = resolvedPosition(
            for: actor,
            at: time,
            canvasAspect: aspect,
            compositionPlan: compositionPlan
        )
        let tangent = resolvedTangent(
            for: actor,
            at: time,
            canvasAspect: aspect,
            compositionPlan: compositionPlan,
            fallback: rawTangent
        )
        let footprint = DayObjectGeometryFootprint.make(
            halfSize: halfSize,
            direction: tangent,
            shape: actor.appearance.shape,
            trailLength: trailReach,
            shortSidePixels: 128
        )
        let bodyRadius = max(footprint.forwardReach, footprint.lateralReach)
        let halfCanvas = aspect >= 1
            ? SIMD2<Double>(aspect * 0.5, 0.5)
            : SIMD2<Double>(0.5, 0.5 / aspect)
        let inside = abs(position.x) + footprint.axisAlignedHalfExtents.x <= halfCanvas.x + 0.000_000_1
            && abs(position.y) + footprint.axisAlignedHalfExtents.y <= halfCanvas.y + 0.000_000_1
        let overflow = SIMD2(
            max(abs(position.x) + footprint.axisAlignedHalfExtents.x - halfCanvas.x, 0),
            max(abs(position.y) + footprint.axisAlignedHalfExtents.y - halfCanvas.y, 0)
        )
        let cropFraction = max(
            overflow.x / max(footprint.axisAlignedHalfExtents.x * 2, 0.000_001),
            overflow.y / max(footprint.axisAlignedHalfExtents.y * 2, 0.000_001)
        )
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
        let rotation: Double
        switch actor.appearance.shape {
        case .ellipse, .lens:
            rotation = atan2(tangent.y, tangent.x)
        case .sphere, .softBlob:
            rotation = 0
        }

        return DayObjectPose(
            position: position,
            tangent: tangent,
            rotation: rotation,
            scale: scale,
            opacity: opacity(for: actor, depth: depth),
            depth: depth,
            depthBand: min(max(Int(depth * 4), 0), 3),
            // A camera-like focus plane keeps middle-distance actors sharp;
            // distant and extremely near actors lose high-frequency detail.
            // The per-material softness is added in the shader.
            localDepthSoftness: cameraSoftness(for: depth),
            materialPhase: normalizedPhase(
                actor.appearance.radialPhase + time / 150
            ),
            intentionalCropFraction: min(max(cropFraction, 0), 1),
            bodyRadius: bodyRadius,
            trailReach: trailReach,
            footprintHalfExtents: footprint.axisAlignedHalfExtents,
            isInsideSafeBounds: inside,
            intersectsUIExclusion: intersectsUI,
            intersectsNegativeSpace: intersectsNegative
        )
    }

    func travelDirection(for actor: DayObjectActor) -> Double {
        actor.route.direction
    }

    private func position(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?
    ) -> SIMD2<Double> {
        if let compositionPlan {
            let evaluatedDiameter = evaluatedDiameter(
                for: actor,
                at: time,
                compositionPlan: compositionPlan
            )
            let baseDiameter = presetDiameter(
                for: actor,
                compositionPlan: compositionPlan
            )
            let evaluatedReach = planningReach(
                for: actor,
                diameter: evaluatedDiameter
            )
            let lanePlanningReach = compositionPlan.usesFullCanvas
                ? min(
                    evaluatedReach,
                    planningReach(for: actor, diameter: 0.16)
                )
                : planningReach(
                    for: actor,
                    diameter: baseDiameter * 1.43
                )
            let routePosition = actor.route.position(at: time)
            let base: SIMD2<Double>
            if actor.choreographyConfiguration.preset == .eclipseStack {
                base = compositionPlan.distributedRoutePosition(
                    sector: actor.route.sector,
                    actorSeed: actor.seed,
                    localPosition: .zero,
                    footprintReach: lanePlanningReach,
                    canvasAspect: canvasAspect
                ) + routePosition
            } else {
                base = compositionPlan.distributedRoutePosition(
                    sector: actor.route.sector,
                    actorSeed: actor.seed,
                    localPosition: routePosition,
                    footprintReach: lanePlanningReach,
                    canvasAspect: canvasAspect
                )
            }
            guard family == .softEncounters else {
                return base
            }
            let envelope = encounterEnvelope(for: actor.encounter, at: time)
            guard envelope > 0 else { return base }
            let memberCount = max(actor.encounter.memberCount, 2)
            let memberAngle = Double(actor.encounter.memberOrdinal)
                * 2 * Double.pi / Double(memberCount)
            let bodyRadius = encounterBodyRadius(
                for: actor,
                at: time,
                compositionPlan: compositionPlan
            )
            let ringDenominator = max(sin(Double.pi / Double(memberCount)), 0.35)
            let ringRadius = bodyRadius
                * (1 - actor.encounter.overlapFraction)
                / ringDenominator
            let rawTarget = compositionPlan.encounterCenter(
                channel: actor.encounter.channel,
                canvasAspect: canvasAspect
            ) + SIMD2(cos(memberAngle), sin(memberAngle)) * ringRadius
            let target = compositionPlan.constrainedPosition(
                rawTarget,
                footprintHalfExtents: SIMD2(repeating: bodyRadius + 0.002),
                canvasAspect: canvasAspect
            )
            return base + (target - base) * envelope
        }
        return unplannedPosition(for: actor, at: time, canvasAspect: canvasAspect)
    }

    private func encounterEnvelope(
        for encounter: DayObjectEncounter,
        at time: Double
    ) -> Double {
        let rawCycle = time / 90
        let cycle = rawCycle - floor(rawCycle)
        let delta = cycle >= encounter.phase
            ? cycle - encounter.phase
            : cycle + 1 - encounter.phase
        guard delta <= encounter.durationFraction else { return 0 }
        let progress = delta / max(encounter.durationFraction, 0.000_001)
        if progress < 0.25 {
            return smoothstep(progress / 0.25)
        }
        if progress > 0.75 {
            return smoothstep((1 - progress) / 0.25)
        }
        return 1
    }

    private func smoothstep(_ rawValue: Double) -> Double {
        let value = min(max(rawValue, 0), 1)
        return value * value * (3 - 2 * value)
    }

    private func unplannedPosition(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasAspect >= 1
            ? SIMD2<Double>(canvasAspect, 1)
            : SIMD2<Double>(1, 1 / canvasAspect)
        let column = actor.route.sector % 3
        let row = actor.route.sector / 3
        let center = SIMD2<Double>(
            (Double(column) + 0.5) / 3 - 0.5,
            0.5 - (Double(row) + 0.5) / 3
        ) * span
        return center + actor.route.position(at: time) * 0.45
    }

    private func routeTangent(for actor: DayObjectActor, at time: Double) -> SIMD2<Double> {
        let epsilon = 0.001
        let travel = actor.route.position(at: time + epsilon)
            - actor.route.position(at: time - epsilon)
        let length = simd_length(travel)
        return length > 1e-12 ? travel / length : SIMD2(actor.route.direction, 0)
    }

    private func finalTangent(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?,
        fallback: SIMD2<Double>
    ) -> SIMD2<Double> {
        let epsilon = 0.001
        let travel = position(
            for: actor,
            at: time + epsilon,
            canvasAspect: canvasAspect,
            compositionPlan: compositionPlan
        ) - position(
            for: actor,
            at: time - epsilon,
            canvasAspect: canvasAspect,
            compositionPlan: compositionPlan
        )
        let length = simd_length(travel)
        return length > 1e-12 ? travel / length : fallback
    }

    private func resolvedPosition(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?
    ) -> SIMD2<Double> {
        let routedPosition = position(
            for: actor,
            at: time,
            canvasAspect: canvasAspect,
            compositionPlan: compositionPlan
        )
        guard let compositionPlan,
              compositionPlan.usesFullCanvas,
              ![DayObjectChoreographyPreset.depthField, .eclipseStack]
                .contains(actor.choreographyConfiguration.preset) else {
            return routedPosition
        }
        let diameter = evaluatedDiameter(
            for: actor,
            at: time,
            compositionPlan: compositionPlan
        )
        let conservativeReach = planningReach(for: actor, diameter: diameter)
        return compositionPlan.constrainedPosition(
            routedPosition,
            footprintHalfExtents: SIMD2(repeating: conservativeReach),
            canvasAspect: canvasAspect
        )
    }

    private func resolvedTangent(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?,
        fallback: SIMD2<Double>
    ) -> SIMD2<Double> {
        let epsilon = 0.001
        let travel = resolvedPosition(
            for: actor,
            at: time + epsilon,
            canvasAspect: canvasAspect,
            compositionPlan: compositionPlan
        ) - resolvedPosition(
            for: actor,
            at: time - epsilon,
            canvasAspect: canvasAspect,
            compositionPlan: compositionPlan
        )
        let length = simd_length(travel)
        return length > 1e-12 ? travel / length : fallback
    }

    private func encounterBodyRadius(
        for actor: DayObjectActor,
        at time: Double,
        compositionPlan: DayObjectCompositionPlan?
    ) -> Double {
        let diameter = evaluatedDiameter(
            for: actor,
            at: time,
            compositionPlan: compositionPlan
        )
        let halfSize = SIMD2<Double>(
            diameter * 0.5,
            diameter * 0.5 * DayObjectActorGeometry.aspectRatio(for: actor)
        )
        let footprint = DayObjectGeometryFootprint.make(
            halfSize: halfSize,
            direction: SIMD2(1, 0),
            shape: actor.appearance.shape,
            trailLength: 0.008,
            shortSidePixels: 128
        )
        return max(footprint.forwardReach, footprint.lateralReach)
    }

    private func depthValue(for actor: DayObjectActor, at time: Double) -> Double {
        let schedule = actor.depthSchedule
        let phase = 2 * Double.pi * (time / schedule.period + schedule.phase)
        return min(max(schedule.baseDepth + schedule.amplitude * cos(phase), 0), 1)
    }

    private func cameraSoftness(for depth: Double) -> Double {
        let focusDepth = 0.55
        let farDistance = max((focusDepth - depth) / focusDepth, 0)
        let nearDistance = max((depth - focusDepth) / (1 - focusDepth), 0)
        return 0.018
            + 0.30 * pow(farDistance, 1.35)
            + 0.62 * pow(nearDistance, 1.35)
    }

    private func normalizedPhase(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private func presetDiameter(
        for actor: DayObjectActor,
        compositionPlan: DayObjectCompositionPlan?
    ) -> Double {
        let configuration = actor.choreographyConfiguration
        let multiplier = actor.choreographySlot.sizeMultiplier
        let diameter: Double
        switch configuration.sizeProfile {
        case .uniform:
            let seededUnit = min(max(configuration.orientation / (2 * Double.pi), 0), 1)
            diameter = 0.22 + 0.14 * seededUnit
        case .grouped:
            let groupUnit = min(max((multiplier - 0.85) / 0.40, 0), 1)
            diameter = 0.16 + 0.30 * groupUnit
        case .spatial:
            let spatialUnit = min(max((multiplier - 0.80) / 0.40, 0), 1)
            diameter = 0.12 + 0.62 * spatialUnit
        }
        guard compositionPlan?.usesFullCanvas == true else {
            return min(diameter, 0.112)
        }
        return diameter
    }

    private func evaluatedDiameter(
        for actor: DayObjectActor,
        at time: Double,
        compositionPlan: DayObjectCompositionPlan?
    ) -> Double {
        let profile = actor.choreographyConfiguration.sizeProfile
        let depth = depthValue(for: actor, at: time)
        let depthScale = profile == .spatial ? 0.56 + 1.04 * depth : 1
        let breathingAmplitude = profile == .uniform ? 0.018 : 0.035
        let actorBreathingPhase = 2 * Double.pi * (
            time / actor.depthSchedule.period
                + actor.phaseOffset / (2 * Double.pi)
        )
        let breathing = 1 + breathingAmplitude * sin(actorBreathingPhase)
        return presetDiameter(for: actor, compositionPlan: compositionPlan)
            * depthScale
            * breathing
    }

    private func opacity(for actor: DayObjectActor, depth: Double) -> Double {
        switch actor.choreographyConfiguration.depthProfile {
        case .flat:
            return 0.86 + 0.14 * stableUnit(
                actor.seed,
                salt: 0x1319_8A2E_0370_7344
            )
        case .layered, .migrating:
            return max(0.58 + 0.42 * depth, 0.72)
        }
    }

    private func planningReach(for actor: DayObjectActor, diameter: Double) -> Double {
        let major = diameter * 0.5
        let minor = major * DayObjectActorGeometry.aspectRatio(for: actor)
        let bodyMultiplier = actor.appearance.shape == .softBlob
            ? DayObjectActorGeometry.softBlobRadialReach
            : 1
        let merge = major * DayObjectActorGeometry.mergeReachFactor
        let longitudinal = max(major * bodyMultiplier + merge, major + 0.008)
        let lateral = max(
            minor * bodyMultiplier + merge,
            minor * DayObjectActorGeometry.trailSigmaFactor
                * DayObjectActorGeometry.trailSigmaSupport
        )
        return hypot(longitudinal, lateral) + 2.0 / 128.0
    }

    private func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        Double(Self.mixed(seed ^ salt) >> 11) / Double(UInt64(1) << 53)
    }

    private static func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
