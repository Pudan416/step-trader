import Foundation
import simd

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
    let configuration: DayObjectChoreographyConfiguration
    let duration: Double

    var preset: DayObjectChoreographyPreset { configuration.preset }

    static func make(
        configuration: DayObjectChoreographyConfiguration
    ) -> DayObjectChoreographyScore {
        DayObjectChoreographyScore(
            configuration: configuration,
            duration: configuration.loopDuration
        )
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
        let scale = evaluatedDiameter(
            for: actor,
            at: time,
            depth: depth,
            compositionPlan: compositionPlan
        )
        let trailReach = 0.008
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
            compositionPlan: compositionPlan
        )
        let halfSize = SIMD2<Double>(
            scale * 0.5,
            scale * 0.5 * DayObjectActorGeometry.aspectRatio(for: actor)
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
        let inside = abs(position.x) + footprint.axisAlignedHalfExtents.x
                <= halfCanvas.x + 0.000_000_1
            && abs(position.y) + footprint.axisAlignedHalfExtents.y
                <= halfCanvas.y + 0.000_000_1
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
            localDepthSoftness: cameraSoftness(for: depth),
            materialPhase: normalizedPhase(actor.appearance.radialPhase + time / 150),
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

    private func rawRoutePosition(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double
    ) -> SIMD2<Double> {
        let span = canvasAspect >= 1
            ? SIMD2<Double>(canvasAspect, 1)
            : SIMD2<Double>(1, 1 / canvasAspect)
        return actor.route.position(at: time) * span
    }

    private func resolvedPosition(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?
    ) -> SIMD2<Double> {
        let routed = rawRoutePosition(for: actor, at: time, canvasAspect: canvasAspect)
        guard let compositionPlan else { return routed }
        if compositionPlan.usesFullCanvas {
            guard ![.depthField, .eclipseStack].contains(configuration.preset) else {
                return routed
            }
            let insetScale = configuration.preset == .radialBloom ? 0.80 : 0.88
            return routed * insetScale
        }

        return compositionPlan.safeChoreographyPosition(
            routed,
            formationReach: 0.14,
            canvasAspect: canvasAspect
        )
    }

    private func resolvedTangent(
        for actor: DayObjectActor,
        at time: Double,
        canvasAspect: Double,
        compositionPlan: DayObjectCompositionPlan?
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
        return length > 1e-12 ? travel / length : SIMD2(actor.route.direction, 0)
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
        _ = compositionPlan
        return configuration.baseDiameter * actor.choreographySlot.sizeMultiplier
    }

    private func evaluatedDiameter(
        for actor: DayObjectActor,
        at time: Double,
        depth: Double? = nil,
        compositionPlan: DayObjectCompositionPlan?
    ) -> Double {
        let evaluatedDepth = depth ?? depthValue(for: actor, at: time)
        let breathingPhase = 2 * Double.pi * (
            time / configuration.loopDuration + actor.choreographySlot.phase
        )
        let diameter = presetDiameter(for: actor, compositionPlan: compositionPlan)
            * diameterModulation(
                preset: configuration.preset,
                depth: evaluatedDepth,
                breathingWave: sin(breathingPhase)
            )
        guard compositionPlan?.usesFullCanvas == true else {
            return min(diameter, 0.112)
        }
        guard configuration.sizeProfile == .spatial else {
            return diameter
        }
        return min(max(diameter, 0.12), 0.74)
    }

    private func diameterModulation(
        preset: DayObjectChoreographyPreset,
        depth: Double,
        breathingWave: Double
    ) -> Double {
        let depthScale: Double
        switch preset {
        case .depthField:
            depthScale = 0.52 + 1.08 * depth
        case .eclipseStack:
            depthScale = 0.75 + 0.50 * depth
        default:
            depthScale = 1
        }
        let breathingAmplitude: Double
        switch preset {
        case .breathingGrid:
            breathingAmplitude = 0.018
        case .depthField:
            breathingAmplitude = 0.016
        default:
            breathingAmplitude = 0.008
        }
        return depthScale * (1 + breathingAmplitude * breathingWave)
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
